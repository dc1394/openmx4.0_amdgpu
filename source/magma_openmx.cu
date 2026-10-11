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

/* MAGMA Ozaki-II (GEMMul8) routing of the dense eigensolves.  The _ozaki2
   drivers delegate to the stock MAGMA algorithms and only route the BLAS-3
   phases (syr2k/her2k, larfb gemm/trmm, dlaex3 gemm) through GEMMul8 INT8
   emulation inside a scoped activation; OPENMX_MAGMA_OZAKI2=0 restores the
   stock drivers bit-identically.  The two defaults follow the tuning note
   (third_party/MAGMA_OZAKI2_NOTES.md): 1-stage because the 2-stage bulge
   chasing starves under many busy MPI ranks, and a 4-way split of the
   percent-of-VRAM workspace cap because only the dense root rank solves. */
int use_magma_ozaki2()
{
    static int use = -1;

    if (use < 0) {
        const char *env = std::getenv("OPENMX_MAGMA_OZAKI2");
        use = (env == nullptr || env[0] == '\0') ? 1 : (std::atoi(env) != 0);
        if (use) {
            setenv("MAGMA_OZAKI2_ALGO", "1stage", 0);
            setenv("MAGMA_OZAKI2_LOCAL_RANKS", "4", 0);
            /* A modest per-process workspace plus a 1 GiB free guard routes
               3x as many backtransform GEMMs on a 16 GB card shared by 16
               ranks than the adapter's conservative defaults; GEMMul8's
               memory-saving mode blocks any GEMM to fit the cap. */
            setenv("MAGMA_OZAKI2_MAX_WS_MB", "512", 0);
            setenv("MAGMA_OZAKI2_MIN_FREE_MB", "1024", 0);
        }
    }
    return use;
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

/* rocSOLVER's Hermitian divide and conquer (zheevd of ROCm 7.2) returns
   info 0 with NaN vectors for a complex matrix whose elements are all real
   (the non-collinear Hamiltonian without spin-orbit coupling, at real k) and
   for an exactly block-diagonal one (a non-magnetic non-collinear one).  The
   solve therefore takes the unitary similarity D^H A D, D = diag(d_k),
   d_k = exp(2 pi i frac(k phi)), with every exactly zero off-diagonal element
   set to about 1e-200, and returns D V: same eigenvalues, the vectors of A. */
namespace {

__device__ inline void zheevd_phase(int k, double *c, double *s)
{
    double t = (double)k * 0.6180339887498949;

    t -= floor(t);
    sincospi(2.0 * t, s, c);
}

__global__ void k_zheevd_phase_in(double *a, int n)
{
    const size_t nn = (size_t)n * (size_t)n;

    for (size_t idx = blockIdx.x * (size_t)blockDim.x + threadIdx.x; idx < nn; idx += (size_t)gridDim.x * blockDim.x) {
        const int    row = (int)(idx % (size_t)n), col = (int)(idx / (size_t)n);
        const double re = a[2 * idx], im = a[2 * idx + 1];
        double       cr, sr, cc, sc;

        zheevd_phase(row, &cr, &sr);
        zheevd_phase(col, &cc, &sc);
        {
            const double pr = cr * cc + sr * sc, pi = cr * sc - sr * cc;   /* conj(d_row) d_col */
            double       r2 = re * pr - im * pi, i2 = re * pi + im * pr;

            if (r2 == 0.0 && i2 == 0.0 && row != col) r2 = 1.0e-200 * (double)(1 + (unsigned)(row * 7 + col * 13) % 17u);
            a[2 * idx] = r2;
            a[2 * idx + 1] = i2;
        }
    }
}

/* v <- D v for the first cols columns; clears *finite on a non-finite entry */
__global__ void k_zheevd_phase_out(double *v, int n, int cols, int *finite)
{
    const size_t count = (size_t)n * (size_t)cols;

    for (size_t idx = blockIdx.x * (size_t)blockDim.x + threadIdx.x; idx < count;
         idx += (size_t)gridDim.x * blockDim.x) {
        const double vr = v[2 * idx], vi = v[2 * idx + 1];
        double       c, s;

        if (!isfinite(vr) || !isfinite(vi)) *finite = 0;
        zheevd_phase((int)(idx % (size_t)n), &c, &s);
        v[2 * idx] = c * vr - s * vi;
        v[2 * idx + 1] = c * vi + s * vr;
    }
}

unsigned zheevd_grid(size_t count)
{
    size_t blocks = (count + 255) / 256;

    if (blocks > 65535u * 16u) blocks = 65535u * 16u;
    if (blocks < 1) blocks = 1;
    return (unsigned)blocks;
}

} // namespace

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

    hipLaunchKernelGGL(k_zheevd_phase_in, dim3(zheevd_grid((size_t)n * (size_t)n)), dim3(256), 0, 0,
                       (double *)d_A, n);
    if (hipGetLastError() != hipSuccess) {
        return MAGMA_ERR_UNKNOWN;
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
    {
        int finite = 1;

        /* g_hs_dinfo (0 after a successful solve) serves as the flag */
        if (hipMemcpy(g_hs_dinfo, &finite, sizeof(int), hipMemcpyHostToDevice) != hipSuccess) {
            return MAGMA_ERR_UNKNOWN;
        }
        hipLaunchKernelGGL(k_zheevd_phase_out, dim3(zheevd_grid((size_t)n * (size_t)n)), dim3(256), 0, 0,
                           (double *)d_A, n, n, g_hs_dinfo);
        if (hipGetLastError() != hipSuccess ||
            hipMemcpy(&finite, g_hs_dinfo, sizeof(int), hipMemcpyDeviceToHost) != hipSuccess) {
            return MAGMA_ERR_UNKNOWN;
        }
        if (!finite) {
            std::fprintf(stderr, "openmx_hipsolver_zheevd_gpu: rocSOLVER returned non-finite eigenvectors (n=%d)\n",
                         n);
            std::fflush(stderr);
            return MAGMA_ERR_UNKNOWN;
        }
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

    magma_int_t ret = (use_magma_ozaki2() ? magma_dsyevdx_ozaki2_gpu : magma_dsyevdx_gpu)(
                                        MagmaVec, range, MagmaLower,
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
    ret = (use_magma_ozaki2() ? magma_dsyevdx_ozaki2_gpu : magma_dsyevdx_gpu)(
                            MagmaVec, range, MagmaLower,
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

    magma_int_t ret = (use_magma_ozaki2() ? magma_zheevdx_ozaki2_gpu : magma_zheevdx_gpu)(
                                        MagmaVec, range, MagmaLower,
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
    ret = (use_magma_ozaki2() ? magma_zheevdx_ozaki2_gpu : magma_zheevdx_gpu)(
                            MagmaVec, range, MagmaLower,
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

/* FP32 full solves for the refined eigensolver (eigen_refine_gpu.cu, with
   OPENMX_EIGEN_FP32_SOLVER=magma or as the retry of a failed rocSOLVER solve):
   all n eigenpairs of the n x n matrix d_A (device, ldda n, lower triangle),
   the vectors in place, the eigenvalues ascending in w (host).  The host
   workspaces stay cached like those of the FP64 solves. */
namespace {

float              *g_f_host_matrix = nullptr;
size_t              g_f_host_elems = 0;
float              *g_f_work = nullptr;
magma_int_t         g_f_lwork = 0;
float              *g_f_rwork = nullptr;
magma_int_t         g_f_lrwork = 0;
magma_int_t        *g_f_iwork = nullptr;
magma_int_t         g_f_liwork = 0;

template <class T>
int grow_cpu(T **ptr, magma_int_t *have, magma_int_t want)
{
    if (want <= *have) return MAGMA_SUCCESS;
    T *grown = nullptr;
    if (magma_malloc_cpu((void **)&grown, sizeof(T) * static_cast<size_t>(want)) != MAGMA_SUCCESS)
        return MAGMA_ERR_HOST_ALLOC;
    if (*ptr != nullptr) magma_free_cpu(*ptr);
    *ptr = grown;
    *have = want;
    return MAGMA_SUCCESS;
}

int fp32_solve(int cplx, int n, void *d_A, float *w)
{
    magma_int_t mn = static_cast<magma_int_t>(n), info = 0;
    float       work_query[2] = {0.0f, 0.0f};
    float       rwork_query = 0.0f;
    magma_int_t iwork_query = 0;
    size_t      host_elems = static_cast<size_t>(n) * static_cast<size_t>(n) * (cplx ? 2u : 1u);
    int         err;

    if (n <= 0 || d_A == nullptr || w == nullptr) return MAGMA_ERR_ILLEGAL_VALUE;
    err = ensure_magma_initialized();
    if (err != MAGMA_SUCCESS) return err;
    if (host_elems > g_f_host_elems) {
        float *grown = nullptr;
        if (magma_smalloc_cpu(&grown, host_elems) != MAGMA_SUCCESS) return MAGMA_ERR_HOST_ALLOC;
        if (g_f_host_matrix != nullptr) magma_free_cpu(g_f_host_matrix);
        g_f_host_matrix = grown;
        g_f_host_elems = host_elems;
    }
    if (cplx)
        magma_cheevd_gpu(MagmaVec, MagmaLower, mn, reinterpret_cast<magmaFloatComplex_ptr>(d_A), mn, w,
                         reinterpret_cast<magmaFloatComplex *>(g_f_host_matrix), mn,
                         reinterpret_cast<magmaFloatComplex *>(work_query), -1, &rwork_query, -1, &iwork_query, -1,
                         &info);
    else
        magma_ssyevd_gpu(MagmaVec, MagmaLower, mn, reinterpret_cast<magmaFloat_ptr>(d_A), mn, w, g_f_host_matrix, mn,
                         work_query, -1, &iwork_query, -1, &info);
    if (info != 0) return static_cast<int>(info);
    {
        /* MAGMA's device workspace (chetrd2_gpu/cunmtr_gpu/cstedx, see
           cheevd_gpu.cpp) and room for the queue's library handles: a hipBLAS
           or hipBLASLt call that cannot allocate ends the process, so the
           solve is declined instead when the device is that full */
        const size_t nb = static_cast<size_t>(cplx ? magma_get_chetrd_nb(mn) : magma_get_ssytrd_nb(mn));
        const size_t nn = static_cast<size_t>(n) * static_cast<size_t>(n);
        size_t       words = static_cast<size_t>(n) * ((static_cast<size_t>(n) + 63) / 64) +
                             2 * static_cast<size_t>(n) * nb;
        size_t       free_bytes = 0, total_bytes = 0;

        if (words < nn) words = nn;
        words *= cplx ? 2 : 1;
        if (words < 3 * static_cast<size_t>(n) * (static_cast<size_t>(n) / 2 + 1))
            words = 3 * static_cast<size_t>(n) * (static_cast<size_t>(n) / 2 + 1);
        if (hipMemGetInfo(&free_bytes, &total_bytes) != hipSuccess ||
            free_bytes < words * sizeof(float) + (static_cast<size_t>(512) << 20)) {
            std::printf("<eigen_refine_gpu> MAGMA FP32 solve declined: %.1f MiB free, %.1f MiB needed\n",
                        free_bytes / 1048576.0, (words * sizeof(float) + (static_cast<size_t>(512) << 20)) / 1048576.0);
            std::fflush(stdout);
            return MAGMA_ERR_DEVICE_ALLOC;
        }
    }

    magma_int_t lwork = static_cast<magma_int_t>(work_query[0]) + 1;
    magma_int_t lrwork = static_cast<magma_int_t>(rwork_query) + 1;
    magma_int_t liwork = iwork_query + 1;

    if (grow_cpu(&g_f_work, &g_f_lwork, lwork * (cplx ? 2 : 1)) != MAGMA_SUCCESS ||
        (cplx && grow_cpu(&g_f_rwork, &g_f_lrwork, lrwork) != MAGMA_SUCCESS) ||
        grow_cpu(&g_f_iwork, &g_f_liwork, liwork) != MAGMA_SUCCESS)
        return MAGMA_ERR_HOST_ALLOC;
    info = 0;
    if (cplx)
        magma_cheevd_gpu(MagmaVec, MagmaLower, mn, reinterpret_cast<magmaFloatComplex_ptr>(d_A), mn, w,
                         reinterpret_cast<magmaFloatComplex *>(g_f_host_matrix), mn,
                         reinterpret_cast<magmaFloatComplex *>(g_f_work), lwork, g_f_rwork, lrwork, g_f_iwork, liwork,
                         &info);
    else
        magma_ssyevd_gpu(MagmaVec, MagmaLower, mn, reinterpret_cast<magmaFloat_ptr>(d_A), mn, w, g_f_host_matrix, mn,
                         g_f_work, lwork, g_f_iwork, liwork, &info);
    hipDeviceSynchronize();
    return static_cast<int>(info);
}

} // namespace

extern "C" int openmx_magma_ssyevd_gpu(int n, float *d_A, float *w)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    return fp32_solve(0, n, d_A, w);
}

extern "C" int openmx_magma_cheevd_gpu(int n, void *d_A, float *w)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    return fp32_solve(1, n, d_A, w);
}

extern "C" void openmx_magma_release_fp32_workspace(void)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    if (g_f_host_matrix != nullptr) magma_free_cpu(g_f_host_matrix);
    if (g_f_work != nullptr) magma_free_cpu(g_f_work);
    if (g_f_rwork != nullptr) magma_free_cpu(g_f_rwork);
    if (g_f_iwork != nullptr) magma_free_cpu(g_f_iwork);
    g_f_host_matrix = nullptr;
    g_f_work = g_f_rwork = nullptr;
    g_f_iwork = nullptr;
    g_f_host_elems = 0;
    g_f_lwork = g_f_lrwork = g_f_liwork = 0;
}

/* MAGMA's range-I path caches a dense host copy and several large pinned host
   work arrays.  On a unified-memory APU those allocations consume the same
   physical pool as the following GPU turns, so NC band calculations release
   them at a safe, synchronous turn boundary. */
/* Returns the Ozaki-II adapter's per-stream hipBLAS handles and device
   workspaces; a no-op when nothing was routed. */
extern "C" void openmx_magma_ozaki2_release(void)
{
    magma_ozaki2_release_workspaces();
}

extern "C" int openmx_magma_release_z_workspace(void)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);

    magma_ozaki2_release_workspaces();
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
