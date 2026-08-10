#include <magma_v2.h>
#include "hip_runtime_compat.h"

#include <hipsolver/hipsolver.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <strings.h>

extern "C" int MYID_MPI_COMM_WORLD;

namespace {

std::once_flag g_magma_once;
std::mutex     g_magma_mutex;
int            g_magma_init_info = MAGMA_SUCCESS;

double      *g_host_matrix = nullptr;
size_t       g_host_matrix_elems = 0;
double      *g_work = nullptr;
magma_int_t  g_lwork = 0;
magma_int_t *g_iwork = nullptr;
magma_int_t  g_liwork = 0;

magmaDoubleComplex *g_z_host_matrix = nullptr;
size_t              g_z_host_matrix_elems = 0;
magmaDoubleComplex *g_z_work = nullptr;
magma_int_t         g_z_lwork = 0;
double             *g_z_rwork = nullptr;
magma_int_t         g_z_lrwork = 0;
magma_int_t        *g_z_iwork = nullptr;
magma_int_t         g_z_liwork = 0;

int ensure_magma_initialized()
{
    std::call_once(g_magma_once, []() {
        g_magma_init_info = magma_init();
        if (g_magma_init_info != MAGMA_SUCCESS) {
            std::fprintf(stderr, "<Cluster> MAGMA initialization failed: info=%d\n", g_magma_init_info);
            std::fflush(stderr);
        }
    });
    return g_magma_init_info;
}

int ensure_host_matrix(size_t elems)
{
    double *new_ptr = nullptr;

    if (elems <= g_host_matrix_elems) {
        return MAGMA_SUCCESS;
    }
    if (magma_dmalloc_cpu(&new_ptr, elems) != MAGMA_SUCCESS) {
        return MAGMA_ERR_HOST_ALLOC;
    }
    if (g_host_matrix != nullptr) {
        magma_free_cpu(g_host_matrix);
    }
    g_host_matrix = new_ptr;
    g_host_matrix_elems = elems;
    return MAGMA_SUCCESS;
}

int ensure_work(magma_int_t lwork, magma_int_t liwork)
{
    if (lwork > g_lwork) {
        double *new_work = nullptr;

        if (magma_dmalloc_cpu(&new_work, static_cast<size_t>(lwork)) != MAGMA_SUCCESS) {
            return MAGMA_ERR_HOST_ALLOC;
        }
        if (g_work != nullptr) {
            magma_free_cpu(g_work);
        }
        g_work = new_work;
        g_lwork = lwork;
    }

    if (liwork > g_liwork) {
        magma_int_t *new_iwork = nullptr;

        if (magma_imalloc_cpu(&new_iwork, static_cast<size_t>(liwork)) != MAGMA_SUCCESS) {
            return MAGMA_ERR_HOST_ALLOC;
        }
        if (g_iwork != nullptr) {
            magma_free_cpu(g_iwork);
        }
        g_iwork = new_iwork;
        g_liwork = liwork;
    }

    return MAGMA_SUCCESS;
}

int ensure_z_host_matrix(size_t elems)
{
    magmaDoubleComplex *new_ptr = nullptr;

    if (elems <= g_z_host_matrix_elems) {
        return MAGMA_SUCCESS;
    }
    if (magma_zmalloc_cpu(&new_ptr, elems) != MAGMA_SUCCESS) {
        return MAGMA_ERR_HOST_ALLOC;
    }
    if (g_z_host_matrix != nullptr) {
        magma_free_cpu(g_z_host_matrix);
    }
    g_z_host_matrix = new_ptr;
    g_z_host_matrix_elems = elems;
    return MAGMA_SUCCESS;
}

int ensure_z_work(magma_int_t lwork, magma_int_t lrwork, magma_int_t liwork)
{
    if (lwork > g_z_lwork) {
        magmaDoubleComplex *new_work = nullptr;

        if (magma_zmalloc_cpu(&new_work, static_cast<size_t>(lwork)) != MAGMA_SUCCESS) {
            return MAGMA_ERR_HOST_ALLOC;
        }
        if (g_z_work != nullptr) {
            magma_free_cpu(g_z_work);
        }
        g_z_work = new_work;
        g_z_lwork = lwork;
    }

    if (lrwork > g_z_lrwork) {
        double *new_rwork = nullptr;

        if (magma_dmalloc_cpu(&new_rwork, static_cast<size_t>(lrwork)) != MAGMA_SUCCESS) {
            return MAGMA_ERR_HOST_ALLOC;
        }
        if (g_z_rwork != nullptr) {
            magma_free_cpu(g_z_rwork);
        }
        g_z_rwork = new_rwork;
        g_z_lrwork = lrwork;
    }

    if (liwork > g_z_liwork) {
        magma_int_t *new_iwork = nullptr;

        if (magma_imalloc_cpu(&new_iwork, static_cast<size_t>(liwork)) != MAGMA_SUCCESS) {
            return MAGMA_ERR_HOST_ALLOC;
        }
        if (g_z_iwork != nullptr) {
            magma_free_cpu(g_z_iwork);
        }
        g_z_iwork = new_iwork;
        g_z_liwork = liwork;
    }

    return MAGMA_SUCCESS;
}

hipsolverDnHandle_t g_hs_handle = nullptr;
hipDoubleComplex   *g_hs_work = nullptr;
int                 g_hs_lwork = 0;
int                 g_hs_work_n = 0;
double             *g_hs_dW = nullptr;
double             *g_hs_hW = nullptr;
int                 g_hs_W_n = 0;
int                *g_hs_dinfo = nullptr;

int ensure_hipsolver_ready(int n)
{
    if (g_hs_handle == nullptr) {
        if (hipsolverDnCreate(&g_hs_handle) != HIPSOLVER_STATUS_SUCCESS) {
            g_hs_handle = nullptr;
            return -1;
        }
    }
    if (g_hs_dinfo == nullptr) {
        if (hipMalloc((void **)&g_hs_dinfo, sizeof(int)) != hipSuccess) {
            g_hs_dinfo = nullptr;
            return -1;
        }
    }
    if (n > g_hs_W_n) {
        if (g_hs_dW != nullptr) hipFree(g_hs_dW);
        if (g_hs_hW != nullptr) std::free(g_hs_hW);
        g_hs_dW = nullptr;
        g_hs_hW = nullptr;
        g_hs_W_n = 0;
        if (hipMalloc((void **)&g_hs_dW, sizeof(double) * (size_t)n) != hipSuccess) {
            g_hs_dW = nullptr;
            return -1;
        }
        g_hs_hW = (double *)std::malloc(sizeof(double) * (size_t)n);
        if (g_hs_hW == nullptr) {
            return -1;
        }
        g_hs_W_n = n;
    }
    return 0;
}

} // namespace

/* Backend selection for the dense GPU eigensolvers.  rocSOLVER's zheevd runs
   entirely on the GPU and is far faster than hybrid MAGMA on CDNA server parts
   (MI100/MI200/MI300 report gfx9xx), while on RDNA consumer parts
   (gfx10xx/11xx/12xx, e.g. RX 9060XT = gfx1200) MAGMA is the faster of the
   two.  Override with OPENMX_GPU_EIGENSOLVER=hipsolver|magma (anything else,
   including "auto", keeps the detection). */
extern "C" int openmx_gpu_eigensolver_use_hipsolver(void)
{
    static int cached = -1;

    if (cached >= 0) {
        return cached;
    }

    const char *env = std::getenv("OPENMX_GPU_EIGENSOLVER");
    if (env != nullptr) {
        if (strcasecmp(env, "hipsolver") == 0) {
            cached = 1;
            return cached;
        }
        if (strcasecmp(env, "magma") == 0) {
            cached = 0;
            return cached;
        }
    }

    hipDeviceProp_t prop;
    int dev = 0;
    if (hipGetDevice(&dev) != hipSuccess || hipGetDeviceProperties(&prop, dev) != hipSuccess) {
        cached = 0;
        return cached;
    }
    cached = (std::strncmp(prop.gcnArchName, "gfx9", 4) == 0) ? 1 : 0;
    return cached;
}

/* True when the GPU is an APU sharing physical memory with the CPU (MI300A):
   host arrays are device-accessible and host<->device staging copies are pure
   waste.  Discrete CDNA parts (MI300X, MI2xx) report integrated=0 and still
   need real copies.  Override with OPENMX_GPU_ASSUME_APU=0/1. */
extern "C" int openmx_gpu_is_apu(void)
{
    static int cached = -1;

    if (cached >= 0) {
        return cached;
    }

    const char *env = std::getenv("OPENMX_GPU_ASSUME_APU");
    if (env != nullptr && *env != '\0') {
        cached = (std::atoi(env) != 0) ? 1 : 0;
        return cached;
    }

    hipDeviceProp_t prop;
    int dev = 0;
    if (hipGetDevice(&dev) != hipSuccess || hipGetDeviceProperties(&prop, dev) != hipSuccess) {
        cached = 0;
        return cached;
    }
    cached = (prop.integrated != 0) ? 1 : 0;

    if (std::getenv("OPENMX_GPU_VERBOSE") != nullptr && MYID_MPI_COMM_WORLD == 0) {
        std::fprintf(stderr, "openmx: GPU '%s' integrated(APU)=%d\n", prop.gcnArchName, cached);
        std::fflush(stderr);
    }
    return cached;
}

/* Drop-in replacement for openmx_magma_zheevdx_gpu backed by
   hipsolverDnZheevd.  rocSOLVER's full-spectrum divide&conquer is much faster
   than its partial zheevdx, so all n eigenpairs are computed and only the
   lowest maxn eigenvalues are stored into w; d_A is overwritten with all n
   eigenvectors (ascending), of which callers consume the first maxn columns. */
extern "C" int openmx_hipsolver_zheevd_gpu(int n, int maxn, void *d_A, double *w, int *mout_out)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    hipsolverStatus_t status;
    int lwork = 0;
    int info = 0;

    if (mout_out != nullptr) {
        *mout_out = 0;
    }
    if (n <= 0 || maxn <= 0 || maxn > n || d_A == nullptr || w == nullptr) {
        return MAGMA_ERR_ILLEGAL_VALUE;
    }

    if (ensure_hipsolver_ready(n) != 0) {
        return MAGMA_ERR_HOST_ALLOC;
    }

    if (n > g_hs_work_n) {
        status = hipsolverDnZheevd_bufferSize(g_hs_handle, HIPSOLVER_EIG_MODE_VECTOR,
                                              HIPSOLVER_FILL_MODE_LOWER, n,
                                              (hipDoubleComplex *)d_A, n, g_hs_dW, &lwork);
        if (status != HIPSOLVER_STATUS_SUCCESS) {
            return (int)status;
        }
        if (lwork < 1) {
            lwork = 1;
        }
        if (lwork > g_hs_lwork) {
            if (g_hs_work != nullptr) {
                hipFree(g_hs_work);
                g_hs_work = nullptr;
                g_hs_lwork = 0;
            }
            if (hipMalloc((void **)&g_hs_work, sizeof(hipDoubleComplex) * (size_t)lwork) != hipSuccess) {
                g_hs_work = nullptr;
                return MAGMA_ERR_DEVICE_ALLOC;
            }
            g_hs_lwork = lwork;
        }
        g_hs_work_n = n;
    }

    status = hipsolverDnZheevd(g_hs_handle, HIPSOLVER_EIG_MODE_VECTOR, HIPSOLVER_FILL_MODE_LOWER, n,
                               (hipDoubleComplex *)d_A, n, g_hs_dW, g_hs_work, g_hs_lwork, g_hs_dinfo);
    if (status != HIPSOLVER_STATUS_SUCCESS) {
        return (int)status;
    }

    if (hipMemcpy(&info, g_hs_dinfo, sizeof(int), hipMemcpyDeviceToHost) != hipSuccess) {
        return MAGMA_ERR_UNKNOWN;
    }
    if (info != 0) {
        return info;
    }
    if (hipMemcpy(g_hs_hW, g_hs_dW, sizeof(double) * (size_t)n, hipMemcpyDeviceToHost) != hipSuccess) {
        return MAGMA_ERR_UNKNOWN;
    }
    std::memcpy(w, g_hs_hW, sizeof(double) * (size_t)maxn);
    hipDeviceSynchronize();

    if (mout_out != nullptr) {
        *mout_out = maxn;
    }
    return 0;
}

/* Release only the large Zheevd scratch allocation.  Handles, eigenvalue
   storage, and host buffers are small and remain cached.  The caller invokes
   this after the synchronous solve when another MPI owner or a large
   back-transform needs the shared MI300A memory. */
extern "C" int openmx_hipsolver_release_workspace(void)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);

    if (g_hs_work != nullptr) {
        if (hipFree(g_hs_work) != hipSuccess) {
            return -1;
        }
        g_hs_work = nullptr;
    }
    g_hs_lwork = 0;
    g_hs_work_n = 0;
    return 0;
}

/* Diagnostic: run a standalone zheevd on a fresh random Hermitian matrix and
   print the wall time, to locate the point in the run where GPU performance
   collapses.  Enabled via OPENMX_ZHEEVD_SELFTEST=1. */
extern "C" void openmx_gpu_zheevd_selftest(const char *label)
{
    const int n = 2808;
    size_t    nn = (size_t)n * (size_t)n;
    hipDoubleComplex *h_A = (hipDoubleComplex *)std::malloc(sizeof(hipDoubleComplex) * nn);
    hipDoubleComplex *d_A = nullptr;
    double           *w = (double *)std::malloc(sizeof(double) * n);

    if (h_A == nullptr || w == nullptr) {
        std::free(h_A);
        std::free(w);
        return;
    }

    unsigned seed = 12345u;
    for (int j = 0; j < n; j++) {
        for (int i = j; i < n; i++) {
            seed = seed * 1664525u + 1013904223u;
            double re = (double)(seed >> 8) / (double)(1u << 24) - 0.5;
            seed = seed * 1664525u + 1013904223u;
            double im = (i == j) ? 0.0 : (double)(seed >> 8) / (double)(1u << 24) - 0.5;
            h_A[(size_t)j * n + i] = {re, im};
            h_A[(size_t)i * n + j] = {re, -im};
        }
    }

    if (hipMalloc((void **)&d_A, sizeof(hipDoubleComplex) * nn) != hipSuccess) {
        std::free(h_A);
        std::free(w);
        return;
    }

    for (int rep = 0; rep < 2; rep++) {
        hipMemcpy(d_A, h_A, sizeof(hipDoubleComplex) * nn, hipMemcpyHostToDevice);
        hipDeviceSynchronize();
        double t0 = std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
        int    mout = 0;
        int    info = openmx_hipsolver_zheevd_gpu(n, n, d_A, w, &mout);
        hipDeviceSynchronize();
        double t1 = std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
        std::printf("[ZHEEVD_SELFTEST] %-12s rep%d  %8.3f s (info=%d w0=%.4f)\n", label, rep, t1 - t0, info,
                    w[0]);
        std::fflush(stdout);
    }

    hipFree(d_A);
    std::free(h_A);
    std::free(w);
}

extern "C" int openmx_magma_dsyevdx_gpu(int n, int maxn, double *d_A, double *w, int *mout_out)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    magma_int_t mn = static_cast<magma_int_t>(n);
    magma_int_t mmaxn = static_cast<magma_int_t>(maxn);
    magma_int_t il = 1;
    magma_int_t iu = mmaxn;
    magma_int_t mout = 0;
    magma_int_t info = 0;
    magma_range_t range = (n == maxn) ? MagmaRangeAll : MagmaRangeI;
    double work_query = 0.0;
    magma_int_t iwork_query = 0;
    int err;

    if (mout_out != nullptr) {
        *mout_out = 0;
    }
    if (n <= 0 || maxn <= 0 || maxn > n || d_A == nullptr || w == nullptr) {
        return MAGMA_ERR_ILLEGAL_VALUE;
    }

    err = ensure_magma_initialized();
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    err = ensure_host_matrix(static_cast<size_t>(n) * static_cast<size_t>(n));
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    magma_int_t ret = magma_dsyevdx_gpu(MagmaVec, range, MagmaLower,
                                        mn, reinterpret_cast<magmaDouble_ptr>(d_A), mn,
                                        0.0, 0.0, il, iu, &mout, w,
                                        g_host_matrix, mn,
                                        &work_query, -1, &iwork_query, -1, &info);
    if (ret != MAGMA_SUCCESS) {
        return static_cast<int>(ret);
    }
    if (info != 0) {
        return static_cast<int>(info);
    }

    magma_int_t lwork = static_cast<magma_int_t>(work_query);
    magma_int_t liwork = iwork_query;
    if (lwork < 1) {
        lwork = 1;
    }
    if (liwork < 1) {
        liwork = 1;
    }

    err = ensure_work(lwork, liwork);
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    mout = 0;
    info = 0;
    ret = magma_dsyevdx_gpu(MagmaVec, range, MagmaLower,
                            mn, reinterpret_cast<magmaDouble_ptr>(d_A), mn,
                            0.0, 0.0, il, iu, &mout, w,
                            g_host_matrix, mn,
                            g_work, lwork, g_iwork, liwork, &info);
    hipDeviceSynchronize();

    if (mout_out != nullptr) {
        *mout_out = static_cast<int>(mout);
    }
    if (ret != MAGMA_SUCCESS) {
        return static_cast<int>(ret);
    }
    return static_cast<int>(info);
}

extern "C" int openmx_magma_zheevdx_gpu(int n, int maxn, void *d_A, double *w, int *mout_out)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    magma_int_t mn = static_cast<magma_int_t>(n);
    magma_int_t mmaxn = static_cast<magma_int_t>(maxn);
    magma_int_t il = 1;
    magma_int_t iu = mmaxn;
    magma_int_t mout = 0;
    magma_int_t info = 0;
    magma_range_t range = (n == maxn) ? MagmaRangeAll : MagmaRangeI;
    magmaDoubleComplex work_query = MAGMA_Z_ZERO;
    double rwork_query = 0.0;
    magma_int_t iwork_query = 0;
    int err;

    if (mout_out != nullptr) {
        *mout_out = 0;
    }
    if (n <= 0 || maxn <= 0 || maxn > n || d_A == nullptr || w == nullptr) {
        return MAGMA_ERR_ILLEGAL_VALUE;
    }

    err = ensure_magma_initialized();
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    err = ensure_z_host_matrix(static_cast<size_t>(n) * static_cast<size_t>(n));
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    magma_int_t ret = magma_zheevdx_gpu(MagmaVec, range, MagmaLower,
                                        mn, reinterpret_cast<magmaDoubleComplex_ptr>(d_A), mn,
                                        0.0, 0.0, il, iu, &mout, w,
                                        g_z_host_matrix, mn,
                                        &work_query, -1,
                                        &rwork_query, -1,
                                        &iwork_query, -1, &info);
    if (ret != MAGMA_SUCCESS) {
        return static_cast<int>(ret);
    }
    if (info != 0) {
        return static_cast<int>(info);
    }

    magma_int_t lwork = static_cast<magma_int_t>(MAGMA_Z_REAL(work_query));
    magma_int_t lrwork = static_cast<magma_int_t>(rwork_query);
    magma_int_t liwork = iwork_query;
    if (lwork < 1) {
        lwork = 1;
    }
    if (lrwork < 1) {
        lrwork = 1;
    }
    if (liwork < 1) {
        liwork = 1;
    }

    err = ensure_z_work(lwork, lrwork, liwork);
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    mout = 0;
    info = 0;
    ret = magma_zheevdx_gpu(MagmaVec, range, MagmaLower,
                            mn, reinterpret_cast<magmaDoubleComplex_ptr>(d_A), mn,
                            0.0, 0.0, il, iu, &mout, w,
                            g_z_host_matrix, mn,
                            g_z_work, lwork,
                            g_z_rwork, lrwork,
                            g_z_iwork, liwork, &info);
    hipDeviceSynchronize();

    if (mout_out != nullptr) {
        *mout_out = static_cast<int>(mout);
    }
    if (ret != MAGMA_SUCCESS) {
        return static_cast<int>(ret);
    }
    return static_cast<int>(info);
}

/* MAGMA's range-I path caches a dense host copy and several large pinned host
   work arrays.  On a unified-memory APU those allocations consume the same
   physical pool as the following GPU turns, so NC band calculations release
   them at a safe, synchronous turn boundary. */
extern "C" int openmx_magma_release_z_workspace(void)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);

    if (g_z_host_matrix != nullptr) magma_free_cpu(g_z_host_matrix);
    if (g_z_work != nullptr)        magma_free_cpu(g_z_work);
    if (g_z_rwork != nullptr)       magma_free_cpu(g_z_rwork);
    if (g_z_iwork != nullptr)       magma_free_cpu(g_z_iwork);
    g_z_host_matrix = nullptr;
    g_z_work = nullptr;
    g_z_rwork = nullptr;
    g_z_iwork = nullptr;
    g_z_host_matrix_elems = 0;
    g_z_lwork = 0;
    g_z_lrwork = 0;
    g_z_liwork = 0;
    return 0;
}
