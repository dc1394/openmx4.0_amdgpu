#include <magma_v2.h>
#include <cuda_runtime.h>

#include <cstdio>
#include <cstdint>
#include <mutex>
#include <unordered_map>

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

struct ZgemmQueueKey {
    int          device;
    cudaStream_t stream;

    bool operator==(const ZgemmQueueKey &other) const
    {
        return device == other.device && stream == other.stream;
    }
};

struct ZgemmQueueKeyHash {
    std::size_t operator()(const ZgemmQueueKey &key) const
    {
        return (static_cast<std::size_t>(key.device) << 32) ^ (reinterpret_cast<std::uintptr_t>(key.stream) << 1);
    }
};

std::mutex g_zgemm_queue_mutex;
std::unordered_map<ZgemmQueueKey, magma_queue_t, ZgemmQueueKeyHash> g_zgemm_queues;

magma_queue_t ensure_zgemm_queue(int device, cudaStream_t stream, hipblasHandle_t hipblas_handle)
{
    std::lock_guard<std::mutex> lock(g_zgemm_queue_mutex);
    ZgemmQueueKey key = {device, stream};

    auto it = g_zgemm_queues.find(key);
    if (it != g_zgemm_queues.end()) {
        return it->second;
    }

    magma_queue_t queue = nullptr;
    magma_queue_create_from_hip(device, stream, hipblas_handle, nullptr, &queue);
    if (queue != nullptr) {
        g_zgemm_queues.emplace(key, queue);
    }
    return queue;
}

int magma_trans_from_char(char op, magma_trans_t *trans)
{
    switch (op) {
    case 'N':
    case 'n':
        *trans = MagmaNoTrans;
        return MAGMA_SUCCESS;
    case 'T':
    case 't':
        *trans = MagmaTrans;
        return MAGMA_SUCCESS;
    case 'C':
    case 'c':
        *trans = MagmaConjTrans;
        return MAGMA_SUCCESS;
    default:
        return MAGMA_ERR_ILLEGAL_VALUE;
    }
}

} // namespace

/* Native MAGMA ZGEMM (magmablas_zgemm) on device pointers; alpha/beta/dA/dB/dC use
   the cuDoubleComplex layout. Returns MAGMA_SUCCESS (0) on success. Needs no GPU
   workspace beyond the one-time queue, so it can run when GEMMul8 cannot.
   hipblas_handle (optional, may be NULL) is reused for the MAGMA queue so no
   extra hipBLAS handle has to be created on an already memory-starved GPU. */
extern "C" int openmx_magma_zgemm(char transa, char transb, int m, int n, int k,
                                  const void *alpha, const void *d_A, int lda,
                                  const void *d_B, int ldb, const void *beta,
                                  void *d_C, int ldc, void *stream, void *hipblas_handle)
{
    magma_trans_t magma_transa;
    magma_trans_t magma_transb;
    int           device = -1;

    if (m <= 0 || n <= 0 || k <= 0) {
        return MAGMA_SUCCESS;
    }
    if (alpha == nullptr || beta == nullptr || d_A == nullptr || d_B == nullptr || d_C == nullptr) {
        return MAGMA_ERR_ILLEGAL_VALUE;
    }
    if (magma_trans_from_char(transa, &magma_transa) != MAGMA_SUCCESS ||
        magma_trans_from_char(transb, &magma_transb) != MAGMA_SUCCESS) {
        return MAGMA_ERR_ILLEGAL_VALUE;
    }

    int err = ensure_magma_initialized();
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    if (cudaGetDevice(&device) != cudaSuccess) {
        return MAGMA_ERR_UNKNOWN;
    }

    magma_queue_t queue =
        ensure_zgemm_queue(device, static_cast<cudaStream_t>(stream), static_cast<hipblasHandle_t>(hipblas_handle));
    if (queue == nullptr) {
        return MAGMA_ERR_DEVICE_ALLOC;
    }

    (void)hipGetLastError();

    /* MAGMA's gemm kernels compute C = alpha*A*B + beta*C reading C even when
       beta == 0, so NaN bit patterns in an uninitialized C would propagate
       (0 * NaN = NaN). Zero the m-by-n C block first to honor BLAS semantics. */
    {
        const magmaDoubleComplex *beta_z = static_cast<const magmaDoubleComplex *>(beta);
        if (MAGMA_Z_REAL(*beta_z) == 0.0 && MAGMA_Z_IMAG(*beta_z) == 0.0) {
            hipError_t memset_status =
                hipMemset2DAsync(d_C, (size_t)ldc * sizeof(magmaDoubleComplex), 0,
                                 (size_t)m * sizeof(magmaDoubleComplex), (size_t)n,
                                 static_cast<cudaStream_t>(stream));
            if (memset_status != hipSuccess) {
                std::fprintf(stderr, "openmx_magma_zgemm: hipMemset2DAsync failed: %s\n",
                             hipGetErrorString(memset_status));
                std::fflush(stderr);
                return MAGMA_ERR_UNKNOWN;
            }
        }
    }
    magmablas_zgemm(magma_transa, magma_transb, static_cast<magma_int_t>(m), static_cast<magma_int_t>(n),
                    static_cast<magma_int_t>(k), *static_cast<const magmaDoubleComplex *>(alpha),
                    static_cast<magmaDoubleComplex_const_ptr>(d_A), static_cast<magma_int_t>(lda),
                    static_cast<magmaDoubleComplex_const_ptr>(d_B), static_cast<magma_int_t>(ldb),
                    *static_cast<const magmaDoubleComplex *>(beta), static_cast<magmaDoubleComplex_ptr>(d_C),
                    static_cast<magma_int_t>(ldc), queue);

    cudaError_t launch_status = hipGetLastError();
    if (launch_status != cudaSuccess) {
        std::fprintf(stderr, "openmx_magma_zgemm: magmablas_zgemm launch failed: %s\n",
                     cudaGetErrorString(launch_status));
        std::fflush(stderr);
        return MAGMA_ERR_UNKNOWN;
    }

    return MAGMA_SUCCESS;
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
    cudaDeviceSynchronize();

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
    cudaDeviceSynchronize();

    if (mout_out != nullptr) {
        *mout_out = static_cast<int>(mout);
    }
    if (ret != MAGMA_SUCCESS) {
        return static_cast<int>(ret);
    }
    return static_cast<int>(info);
}
