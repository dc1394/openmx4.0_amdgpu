#include "hipblas_compat.h"
#include "hip_runtime_compat.h"
#include "hip_complex_compat.h"

#include <cstdlib>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <unordered_map>

#include "gemmul8.hpp"

namespace {

constexpr unsigned kDefaultNumModuli = 15u;
constexpr unsigned kMaxNumModuli     = 20u;
constexpr unsigned kDefaultMinFreeAfterMiB = 1536u;
constexpr unsigned kDefaultMaxWorkspacePercent = 30u;
constexpr size_t   kMiB = 1024u * 1024u;

struct WorkspaceKey {
    int          device;
    hipStream_t stream;

    bool operator==(const WorkspaceKey &other) const
    {
        return device == other.device && stream == other.stream;
    }
};

struct WorkspaceKeyHash {
    std::size_t operator()(const WorkspaceKey &key) const
    {
        return (static_cast<std::size_t>(key.device) << 32) ^ (reinterpret_cast<std::uintptr_t>(key.stream) << 1);
    }
};

struct Workspace {
    void *ptr   = nullptr;
    size_t size = 0;
};

std::mutex g_workspace_mutex;
std::unordered_map<WorkspaceKey, Workspace, WorkspaceKeyHash> g_workspaces;

struct WorkspaceReport {
    size_t      required_bytes = 0;
    size_t      free_bytes     = 0;
    size_t      total_bytes    = 0;
    size_t      reserve_bytes  = 0;
    unsigned    max_workspace_percent = 0;
    unsigned    ranks_per_gpu  = 1;
    const char *reason = "allocation failure";
};

unsigned env_u32(const char *name, unsigned fallback)
{
    const char *value = std::getenv(name);
    char       *end   = nullptr;

    if (value == nullptr || *value == '\0') {
        return fallback;
    }

    unsigned long parsed = std::strtoul(value, &end, 10);
    if (end == value || *end != '\0') {
        return fallback;
    }

    return static_cast<unsigned>(parsed);
}

bool env_bool(const char *name, bool fallback)
{
    const char *value = std::getenv(name);

    if (value == nullptr || *value == '\0') {
        return fallback;
    }

    return value[0] == '1';
}

bool verbose_logging_enabled()
{
    bool verbose = env_bool("OPENMX_GPU_VERBOSE", false);

    verbose = env_bool("OPENMX_GEMM_VERBOSE", verbose);
    verbose = env_bool("OPENMX_GEMMUL8_VERBOSE", verbose);
    verbose = env_bool("GEMMUL8_VERBOSE", verbose);

    return verbose;
}

unsigned env_percent(const char *openmx_env, const char *gemmul8_env, unsigned fallback)
{
    unsigned percent = env_u32(gemmul8_env, fallback);
    percent          = env_u32(openmx_env, percent);

    if (100u < percent) {
        percent = 100u;
    }

    return percent;
}

size_t env_mib(const char *openmx_env, const char *gemmul8_env, unsigned fallback)
{
    unsigned mib = env_u32(gemmul8_env, fallback);
    mib          = env_u32(openmx_env, mib);

    return static_cast<size_t>(mib) * kMiB;
}

bool gemmul8_disabled(const char *openmx_env, const char *gemmul8_env)
{
    bool disabled = env_bool("GEMMUL8_DISABLE", false);
    disabled      = env_bool("OPENMX_GEMMUL8_DISABLE", disabled);
    disabled      = env_bool(gemmul8_env, disabled);
    disabled      = env_bool(openmx_env, disabled);

    return disabled;
}

unsigned gemmul8_num_moduli(const char *openmx_env, const char *gemmul8_env)
{
    unsigned num_moduli = env_u32(gemmul8_env, kDefaultNumModuli);
    num_moduli          = env_u32(openmx_env, num_moduli);

    if (num_moduli < 2u || kMaxNumModuli < num_moduli) {
        num_moduli = kDefaultNumModuli;
    }

    return num_moduli;
}

/* Number of MPI ranks sharing this GPU. The workspace budget must be divided by
   this: each rank checks free memory independently, so 32 ranks can each "see"
   room for a 1-GiB workspace and collectively exhaust the device, after which
   hipBLASLt's lazy initialization inside GEMMul8 dies with out-of-memory. */
unsigned ranks_sharing_gpu()
{
    unsigned local_size = env_u32("OPENMX_GEMMUL8_LOCAL_RANKS", 0u);

    if (local_size == 0u) {
        local_size = env_u32("OMPI_COMM_WORLD_LOCAL_SIZE", 0u);
    }
    if (local_size == 0u) {
        local_size = env_u32("SLURM_NTASKS_PER_NODE", 0u);
    }
    if (local_size == 0u) {
        local_size = 1u;
    }

    int device_count = 0;
    if (hipGetDeviceCount(&device_count) != hipSuccess || device_count < 1) {
        device_count = 1;
    }

    unsigned ranks = local_size / static_cast<unsigned>(device_count);
    return (ranks == 0u) ? 1u : ranks;
}

hipError_t release_workspace(Workspace &workspace)
{
    if (workspace.ptr == nullptr) {
        workspace.size = 0;
        return hipSuccess;
    }

    hipError_t status = hipFree(workspace.ptr);
    if (status == hipSuccess) {
        workspace.ptr  = nullptr;
        workspace.size = 0;
    }

    return status;
}

bool workspace_exceeds_fraction(size_t required, size_t total, unsigned max_percent, unsigned ranks_per_gpu)
{
    if (total == 0 || max_percent == 0) {
        return false;
    }
    if (ranks_per_gpu == 0u) {
        ranks_per_gpu = 1u;
    }
    return (total * static_cast<size_t>(max_percent)) / 100u / ranks_per_gpu < required;
}

bool free_after_workspace_is_too_low(size_t free_bytes, size_t workspace_size, size_t required, size_t reserve)
{
    if (required <= workspace_size) {
        return free_bytes < reserve;
    }

    const size_t extra_required = required - workspace_size;
    return free_bytes < extra_required || free_bytes - extra_required < reserve;
}

template <bool is_complex>
hipblasStatus_t ensure_workspace(hipblasHandle_t handle, size_t m, size_t n, size_t k, unsigned num_moduli, void **work,
                                WorkspaceReport *report)
{
    hipStream_t stream = nullptr;
    int          device = -1;

    hipblasStatus_t hipblas_status = hipblasGetStream(handle, &stream);
    if (hipblas_status != HIPBLAS_STATUS_SUCCESS) {
        return hipblas_status;
    }

    hipError_t hip_status = hipGetDevice(&device);
    if (hip_status != hipSuccess) {
        return HIPBLAS_STATUS_INTERNAL_ERROR;
    }

    const size_t required = gemmul8::workSize<is_complex, gemmul8::Backend::INT8>(m, n, k, num_moduli);
    WorkspaceKey key      = {device, stream};

    const unsigned ranks_per_gpu = ranks_sharing_gpu();

    if (report != nullptr) {
        report->required_bytes = required;
        report->reserve_bytes =
            env_mib("OPENMX_GEMMUL8_MIN_FREE_AFTER_MB", "GEMMUL8_MIN_FREE_AFTER_MB", kDefaultMinFreeAfterMiB);
        report->max_workspace_percent = env_percent("OPENMX_GEMMUL8_MAX_WORKSPACE_PERCENT",
                                                     "GEMMUL8_MAX_WORKSPACE_PERCENT",
                                                     kDefaultMaxWorkspacePercent);
        report->ranks_per_gpu = ranks_per_gpu;
    }

    std::lock_guard<std::mutex> lock(g_workspace_mutex);
    Workspace                  &workspace = g_workspaces[key];

    size_t free_bytes  = 0;
    size_t total_bytes = 0;
    hip_status        = hipMemGetInfo(&free_bytes, &total_bytes);
    if (hip_status == hipSuccess && report != nullptr) {
        report->free_bytes  = free_bytes;
        report->total_bytes = total_bytes;
    }

    if (hip_status == hipSuccess &&
        workspace_exceeds_fraction(required, total_bytes, report != nullptr ? report->max_workspace_percent : 0u,
                                   ranks_per_gpu)) {
        if (report != nullptr) {
            report->reason = "workspace fraction policy";
        }
        if (release_workspace(workspace) != hipSuccess) {
            return HIPBLAS_STATUS_INTERNAL_ERROR;
        }
        return HIPBLAS_STATUS_ALLOC_FAILED;
    }

    if (workspace.size < required) {
        hip_status = release_workspace(workspace);
        if (hip_status != hipSuccess) {
            return HIPBLAS_STATUS_INTERNAL_ERROR;
        }

        hip_status = hipMemGetInfo(&free_bytes, &total_bytes);
        if (hip_status == hipSuccess && report != nullptr) {
            report->free_bytes  = free_bytes;
            report->total_bytes = total_bytes;
        }
    }

    if (hip_status == hipSuccess &&
        free_after_workspace_is_too_low(free_bytes, workspace.size, required,
                                        report != nullptr ? report->reserve_bytes : 0u)) {
        if (report != nullptr) {
            report->reason = "free memory reserve policy";
        }
        if (release_workspace(workspace) != hipSuccess) {
            return HIPBLAS_STATUS_INTERNAL_ERROR;
        }
        return HIPBLAS_STATUS_ALLOC_FAILED;
    }

    if (workspace.size < required) {
        hip_status = hipMalloc(&workspace.ptr, required);
        if (hip_status != hipSuccess) {
            if (report != nullptr) {
                report->reason = "hipMalloc failure";
            }
            return HIPBLAS_STATUS_ALLOC_FAILED;
        }
        workspace.size = required;
    }

    *work = workspace.ptr;
    return HIPBLAS_STATUS_SUCCESS;
}

template <bool is_complex>
void log_workspace_fallback_once(const WorkspaceReport &report, const char *target)
{
    static bool warned = false;

    if (!verbose_logging_enabled()) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_workspace_mutex);
    if (warned) {
        return;
    }

    if (std::strcmp(report.reason, "environment disable") == 0) {
        fprintf(stderr,
                "openmx_gemmul8%sgemm: GEMMul8 disabled by environment; using %s.\n",
                is_complex ? "Z" : "D", target);
    }
    else {
        fprintf(stderr,
                "openmx_gemmul8%sgemm: GEMMul8 workspace fallback by %s; "
                "need %.3f MiB, HIP device free %.3f MiB / total %.3f MiB, "
                "reserve %.3f MiB, max-workspace %u%% shared by %u rank(s). Falling back to %s.\n",
                is_complex ? "Z" : "D", report.reason, (double)report.required_bytes / (1024.0 * 1024.0),
                (double)report.free_bytes / (1024.0 * 1024.0), (double)report.total_bytes / (1024.0 * 1024.0),
                (double)report.reserve_bytes / (1024.0 * 1024.0), report.max_workspace_percent,
                report.ranks_per_gpu, target);
    }
    fflush(stderr);
    warned = true;
}

} // namespace

extern "C" hipblasStatus_t openmx_gemmul8Dgemm(hipblasHandle_t handle,
                                               hipblasOperation_t transa,
                                               hipblasOperation_t transb,
                                               int m,
                                               int n,
                                               int k,
                                               const double *alpha,
                                               const double *A,
                                               int lda,
                                               const double *B,
                                               int ldb,
                                               const double *beta,
                                               double *C,
                                               int ldc)
{
    if (m <= 0 || n <= 0 || k <= 0) {
        return HIPBLAS_STATUS_SUCCESS;
    }

    const unsigned num_moduli = gemmul8_num_moduli("OPENMX_GEMMUL8_NUM_MOD_D", "GEMMUL8_NUM_MOD_D");
    const bool     fastmode   = env_bool("OPENMX_GEMMUL8_FASTMODE_D", env_bool("GEMMUL8_FASTMODE_D", false));
    const hipblasOperation_t gemmul8_transa = (transa == HIPBLAS_OP_C) ? HIPBLAS_OP_T : transa;
    const hipblasOperation_t gemmul8_transb = (transb == HIPBLAS_OP_C) ? HIPBLAS_OP_T : transb;
    void          *work = nullptr;
    WorkspaceReport report;

    if (gemmul8_disabled("OPENMX_GEMMUL8_DISABLE_D", "GEMMUL8_DISABLE_D")) {
        report.reason = "environment disable";
        log_workspace_fallback_once<false>(report, "native hipBLAS");
        return hipblasDgemm(handle, gemmul8_transa, gemmul8_transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
    }

    hipblasStatus_t status =
        ensure_workspace<false>(handle, static_cast<size_t>(m), static_cast<size_t>(n), static_cast<size_t>(k),
                                num_moduli, &work, &report);
    if (status == HIPBLAS_STATUS_ALLOC_FAILED) {
        log_workspace_fallback_once<false>(report, "native hipBLAS");
        return hipblasDgemm(handle, gemmul8_transa, gemmul8_transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
    }
    if (status != HIPBLAS_STATUS_SUCCESS) {
        return status;
    }

    (void)gemmul8::gemm<double, gemmul8::Backend::INT8>(handle, gemmul8_transa, gemmul8_transb, static_cast<size_t>(m),
                                                        static_cast<size_t>(n), static_cast<size_t>(k), alpha, A,
                                                        static_cast<size_t>(lda), B, static_cast<size_t>(ldb), beta, C,
                                                        static_cast<size_t>(ldc), num_moduli, fastmode, work);

    return HIPBLAS_STATUS_SUCCESS;
}

extern "C" size_t openmx_gemmul8ZWorkspaceSize(int m, int n, int k)
{
    if (m<=0 || n<=0 || k<=0 ||
        gemmul8_disabled("OPENMX_GEMMUL8_DISABLE_Z","GEMMUL8_DISABLE_Z")) return 0;
    const unsigned num_moduli=gemmul8_num_moduli("OPENMX_GEMMUL8_NUM_MOD_Z","GEMMUL8_NUM_MOD_Z");
    return gemmul8::workSize<true,gemmul8::Backend::INT8>((size_t)m,(size_t)n,(size_t)k,num_moduli);
}

extern "C" size_t openmx_gemmul8DWorkspaceSize(int m, int n, int k)
{
    if (m<=0 || n<=0 || k<=0 ||
        gemmul8_disabled("OPENMX_GEMMUL8_DISABLE_D","GEMMUL8_DISABLE_D")) return 0;
    const unsigned num_moduli=gemmul8_num_moduli("OPENMX_GEMMUL8_NUM_MOD_D","GEMMUL8_NUM_MOD_D");
    return gemmul8::workSize<false,gemmul8::Backend::INT8>((size_t)m,(size_t)n,(size_t)k,num_moduli);
}

extern "C" void openmx_gemmul8ReleaseWorkspaces(void)
{
    std::lock_guard<std::mutex> lock(g_workspace_mutex);
    hipError_t                 first_error = hipSuccess;

    for (auto it = g_workspaces.begin(); it != g_workspaces.end();) {
        hipError_t status = release_workspace(it->second);
        if (status == hipSuccess) {
            it = g_workspaces.erase(it);
        } else {
            if (first_error == hipSuccess) {
                first_error = status;
            }
            ++it;
        }
    }

    if (first_error != hipSuccess) {
        std::fprintf(stderr,
                     "openmx_gemmul8ReleaseWorkspaces: hipFree failed: %s\n",
                     hipGetErrorString(first_error));
        std::fflush(stderr);
    }
}

extern "C" hipblasStatus_t openmx_gemmul8Zgemm(hipblasHandle_t handle,
                                               hipblasOperation_t transa,
                                               hipblasOperation_t transb,
                                               int m,
                                               int n,
                                               int k,
                                               const hipDoubleComplex *alpha,
                                               const hipDoubleComplex *A,
                                               int lda,
                                               const hipDoubleComplex *B,
                                               int ldb,
                                               const hipDoubleComplex *beta,
                                               hipDoubleComplex *C,
                                               int ldc)
{
    if (m <= 0 || n <= 0 || k <= 0) {
        return HIPBLAS_STATUS_SUCCESS;
    }

    const unsigned num_moduli = gemmul8_num_moduli("OPENMX_GEMMUL8_NUM_MOD_Z", "GEMMUL8_NUM_MOD_Z");
    const bool     fastmode   = env_bool("OPENMX_GEMMUL8_FASTMODE_Z", env_bool("GEMMUL8_FASTMODE_Z", false));
    void          *work = nullptr;
    WorkspaceReport report;

    if (gemmul8_disabled("OPENMX_GEMMUL8_DISABLE_Z", "GEMMUL8_DISABLE_Z")) {
        report.reason = "environment disable";
        log_workspace_fallback_once<true>(report, "native hipBLAS");
        return hipblasZgemm(handle, transa, transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
    }

    hipblasStatus_t status =
        ensure_workspace<true>(handle, static_cast<size_t>(m), static_cast<size_t>(n), static_cast<size_t>(k),
                               num_moduli, &work, &report);
    if (status == HIPBLAS_STATUS_ALLOC_FAILED) {
        /* GPU memory is too tight for the GEMMul8 workspace: fall back to native
           hipBLAS (hipblasZgemm), which needs no extra workspace. If even that fails,
           its status propagates so the caller can fall back to CPU BLAS. */
        log_workspace_fallback_once<true>(report, "native hipBLAS");
        return hipblasZgemm(handle, transa, transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc);
    }
    if (status != HIPBLAS_STATUS_SUCCESS) {
        return status;
    }

    (void)gemmul8::gemm<hipDoubleComplex, gemmul8::Backend::INT8>(
        handle, transa, transb, static_cast<size_t>(m), static_cast<size_t>(n), static_cast<size_t>(k), alpha, A,
        static_cast<size_t>(lda), B, static_cast<size_t>(ldb), beta, C, static_cast<size_t>(ldc), num_moduli, fastmode,
        work);

    return HIPBLAS_STATUS_SUCCESS;
}
