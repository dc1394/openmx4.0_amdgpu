#include <magma_v2.h>
#include <cuda_runtime.h>

#include <cstdio>
#include <mutex>

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

} // namespace

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
