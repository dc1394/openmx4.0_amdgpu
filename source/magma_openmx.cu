#include <magma_v2.h>
#include "magma_ozaki2.h"
#include <cuda_runtime.h>

#include <cstdio>
#include <cstdlib>
#include <mutex>

namespace {

std::once_flag g_magma_once;
std::mutex     g_magma_mutex;
int            g_magma_init_info = MAGMA_SUCCESS;

std::once_flag g_ozaki2_once;
bool           g_ozaki2_enabled = true;
/* OPENMX_MAGMA_OZAKI2_RETRY=1 snapshots d_A to host before every Ozaki-II
   solve so a failure can be retried with the native driver on intact input.
   Off by default: the adapter's rank-divided workspace cap + free-VRAM guard
   already prevent the OOM this protects against, and the per-solve D2H copy
   costs ~1% end-to-end in band runs. */
bool           g_ozaki2_retry   = false;

/* Env switch OPENMX_MAGMA_OZAKI2 (default 1 = enabled): route the eigensolver
   calls below through the EXPERIMENTAL magma_{d,z}...evdx_ozaki2_gpu drivers,
   which enable Ozaki-II (GEMMul8) GEMM routing while they run. */
bool ozaki2_enabled()
{
    std::call_once(g_ozaki2_once, []() {
        const char *env = std::getenv("OPENMX_MAGMA_OZAKI2");
        if (env != nullptr && env[0] != '\0') {
            g_ozaki2_enabled = (std::atoi(env) != 0);
        }
        const char *retry = std::getenv("OPENMX_MAGMA_OZAKI2_RETRY");
        if (retry != nullptr && retry[0] != '\0') {
            g_ozaki2_retry = (std::atoi(retry) != 0);
        }
        /* Budget hint for the MAGMA Ozaki-II adapter: its per-rank workspace
           cap divides by MAGMA_OZAKI2_LOCAL_RANKS (else OMPI/Slurm local
           size).  OpenMX serializes dense GPU eigensolve turns (pairs in
           Band_DFT_Col, root-only in the cluster paths), so plan for ~4
           concurrent workspaces instead of one per local MPI rank.  A value
           already set by the user wins (overwrite=0). */
        setenv("MAGMA_OZAKI2_LOCAL_RANKS", "4", 0);
        /* Default the Ozaki-II drivers to the 1-stage algorithm inside
           OpenMX: production runs pack many busy-polling MPI ranks per
           node, which starves the 2-stage solver's CPU phases (core-pinned
           bulge-chasing pthreads) — measured as a hang-level slowdown at
           n=2808 (band, 32 ranks) and -5..-11% end-to-end (cluster/nc),
           even though 2-stage wins on an otherwise idle machine.  GEMMul8
           routing within 1-stage is a pure win over the legacy path.  An
           explicit MAGMA_OZAKI2_ALGO in the environment overrides this. */
        setenv("MAGMA_OZAKI2_ALGO", "1stage", 0);
        const char *algo = std::getenv("MAGMA_OZAKI2_ALGO");
        std::fprintf(stderr,
                     "OpenMX: MAGMA eigensolver: Ozaki-II path %s (MAGMA_OZAKI2_ALGO=%s)\n",
                     g_ozaki2_enabled ? "enabled" : "disabled",
                     (algo != nullptr && algo[0] != '\0') ? algo : "auto");
        std::fflush(stderr);
    });
    return g_ozaki2_enabled;
}

double      *g_host_matrix = nullptr;
size_t       g_host_matrix_elems = 0;
double      *g_work = nullptr;
magma_int_t  g_lwork = 0;
magma_int_t *g_iwork = nullptr;
magma_int_t  g_liwork = 0;

/* Host-side snapshot of d_A taken before an Ozaki-II solve: the solve
   overwrites d_A in place, so a failed attempt (e.g. GPU OOM under
   many-rank VRAM pressure) can only be retried with the native driver
   if the input is restored first. */
double *g_backup = nullptr;
size_t  g_backup_elems = 0;

magmaDoubleComplex *g_z_host_matrix = nullptr;
size_t              g_z_host_matrix_elems = 0;
magmaDoubleComplex *g_z_backup = nullptr;
size_t              g_z_backup_elems = 0;

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

int ensure_backup(size_t elems)
{
    double *new_ptr = nullptr;

    if (elems <= g_backup_elems) {
        return MAGMA_SUCCESS;
    }
    if (magma_dmalloc_cpu(&new_ptr, elems) != MAGMA_SUCCESS) {
        return MAGMA_ERR_HOST_ALLOC;
    }
    if (g_backup != nullptr) {
        magma_free_cpu(g_backup);
    }
    g_backup = new_ptr;
    g_backup_elems = elems;
    return MAGMA_SUCCESS;
}

int ensure_z_backup(size_t elems)
{
    magmaDoubleComplex *new_ptr = nullptr;

    if (elems <= g_z_backup_elems) {
        return MAGMA_SUCCESS;
    }
    if (magma_zmalloc_cpu(&new_ptr, elems) != MAGMA_SUCCESS) {
        return MAGMA_ERR_HOST_ALLOC;
    }
    if (g_z_backup != nullptr) {
        magma_free_cpu(g_z_backup);
    }
    g_z_backup = new_ptr;
    g_z_backup_elems = elems;
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

    const size_t nelem = static_cast<size_t>(n) * static_cast<size_t>(n);
    err = ensure_host_matrix(nelem);
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    /* Identical signatures; use the same driver for the lwork query and the solve. */
    auto run_solve = [&](decltype(&magma_dsyevdx_gpu) fn) -> int {
        double work_query = 0.0;
        magma_int_t iwork_query = 0;
        mout = 0;
        info = 0;
        magma_int_t ret = fn(MagmaVec, range, MagmaLower,
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

        int werr = ensure_work(lwork, liwork);
        if (werr != MAGMA_SUCCESS) {
            return werr;
        }

        mout = 0;
        info = 0;
        ret = fn(MagmaVec, range, MagmaLower,
                 mn, reinterpret_cast<magmaDouble_ptr>(d_A), mn,
                 0.0, 0.0, il, iu, &mout, w,
                 g_host_matrix, mn,
                 g_work, lwork, g_iwork, liwork, &info);
        cudaDeviceSynchronize();
        if (ret != MAGMA_SUCCESS) {
            return static_cast<int>(ret);
        }
        return static_cast<int>(info);
    };

    int rc;
    if (ozaki2_enabled()) {
        /* Snapshot d_A so a failed Ozaki-II attempt can fall back to the
           native driver on intact input (the solve overwrites d_A). */
        bool have_backup = g_ozaki2_retry &&
            ensure_backup(nelem) == MAGMA_SUCCESS &&
            cudaMemcpy(g_backup, d_A, nelem * sizeof(double),
                       cudaMemcpyDeviceToHost) == cudaSuccess;
        rc = run_solve(magma_dsyevdx_ozaki2_gpu);
        if (rc != 0 && have_backup) {
            std::fprintf(stderr,
                         "OpenMX: MAGMA Ozaki-II dsyevdx solve failed (rc=%d, n=%d, maxn=%d); "
                         "releasing Ozaki-II workspaces and retrying with the native driver.\n",
                         rc, n, maxn);
            std::fflush(stderr);
            magma_ozaki2_release_workspaces();
            if (cudaMemcpy(d_A, g_backup, nelem * sizeof(double),
                           cudaMemcpyHostToDevice) == cudaSuccess) {
                rc = run_solve(magma_dsyevdx_gpu);
            }
        }
    } else {
        rc = run_solve(magma_dsyevdx_gpu);
    }

    if (mout_out != nullptr) {
        *mout_out = static_cast<int>(mout);
    }
    return rc;
}

/* Release the Ozaki-II per-(device,stream) hipBLAS handles and workspaces
   cached inside MAGMA.  Not wired to any call site yet. */
extern "C" void openmx_magma_ozaki2_release(void)
{
    std::lock_guard<std::mutex> lock(g_magma_mutex);
    magma_ozaki2_release_workspaces();
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

    const size_t nelem = static_cast<size_t>(n) * static_cast<size_t>(n);
    err = ensure_z_host_matrix(nelem);
    if (err != MAGMA_SUCCESS) {
        return err;
    }

    /* Identical signatures; use the same driver for the lwork query and the solve. */
    auto run_solve = [&](decltype(&magma_zheevdx_gpu) fn) -> int {
        magmaDoubleComplex work_query = MAGMA_Z_ZERO;
        double rwork_query = 0.0;
        magma_int_t iwork_query = 0;
        mout = 0;
        info = 0;
        magma_int_t ret = fn(MagmaVec, range, MagmaLower,
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

        int werr = ensure_z_work(lwork, lrwork, liwork);
        if (werr != MAGMA_SUCCESS) {
            return werr;
        }

        mout = 0;
        info = 0;
        ret = fn(MagmaVec, range, MagmaLower,
                 mn, reinterpret_cast<magmaDoubleComplex_ptr>(d_A), mn,
                 0.0, 0.0, il, iu, &mout, w,
                 g_z_host_matrix, mn,
                 g_z_work, lwork,
                 g_z_rwork, lrwork,
                 g_z_iwork, liwork, &info);
        cudaDeviceSynchronize();
        if (ret != MAGMA_SUCCESS) {
            return static_cast<int>(ret);
        }
        return static_cast<int>(info);
    };

    int rc;
    if (ozaki2_enabled()) {
        /* Snapshot d_A so a failed Ozaki-II attempt can fall back to the
           native driver on intact input (the solve overwrites d_A). */
        bool have_backup = g_ozaki2_retry &&
            ensure_z_backup(nelem) == MAGMA_SUCCESS &&
            cudaMemcpy(g_z_backup, d_A, nelem * sizeof(magmaDoubleComplex),
                       cudaMemcpyDeviceToHost) == cudaSuccess;
        rc = run_solve(magma_zheevdx_ozaki2_gpu);
        if (rc != 0 && have_backup) {
            std::fprintf(stderr,
                         "OpenMX: MAGMA Ozaki-II zheevdx solve failed (rc=%d, n=%d, maxn=%d); "
                         "releasing Ozaki-II workspaces and retrying with the native driver.\n",
                         rc, n, maxn);
            std::fflush(stderr);
            magma_ozaki2_release_workspaces();
            if (cudaMemcpy(d_A, g_z_backup, nelem * sizeof(magmaDoubleComplex),
                           cudaMemcpyHostToDevice) == cudaSuccess) {
                rc = run_solve(magma_zheevdx_gpu);
            }
        }
    } else {
        rc = run_solve(magma_zheevdx_gpu);
    }

    if (mout_out != nullptr) {
        *mout_out = static_cast<int>(mout);
    }
    return rc;
}
