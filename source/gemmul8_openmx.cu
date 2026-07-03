/*
 * Minimal explicit-instantiation translation unit of GEMMul8 for OpenMX.
 *
 * Upstream GEMMul8 builds one object per (routine, type, backend)
 * combination from the cu_recipe sources via its own make system.
 * OpenMX only needs the INT8-backend gemm/symm/syr2k/trmm for double and
 * gemm/hemm/her2k/trmm for cuDoubleComplex plus the matching workSize
 * queries, so this single TU includes the template definitions and
 * instantiates just those entry points.
 *
 * Compile with -I<GEMMul8>/include -I<GEMMul8>/src.
 */
#include "gemm/gemm_impl.hpp"
#include "worksize/worksize_impl.hpp"
#include "symm/symm_impl.hpp"
#include "syr2k/syr2k_impl.hpp"
#include "trmm/trmm_impl.hpp"
#include "hemm/hemm_impl.hpp"
#include "her2k/her2k_impl.hpp"

/*
 * The include chain above only declares the device-kernel launchers
 * (see *_declaration.hpp); upstream compiles their definitions as
 * separate per-instantiation objects.  Include the definition headers
 * here so the explicit instantiations below reach them implicitly.
 */
#include "oz2/mod/mod_hi2mid.hpp"
#include "oz2/scaling/fast/scaling.hpp"
#include "oz2/scaling/accu/extract.hpp"
#include "oz2/scaling/accu/scaling.hpp"
#include "oz2/scaling/general/scaling_rowwise.hpp"
#include "oz2/scaling/general/scaling_colwise.hpp"
#include "oz2/undo_scaling/undo_scaling.hpp"

/* NEW device-kernel definition headers required by the added ops. */
#include "oz2/scaling/fast/scaling_symm_hemm.hpp"     // scaling::fast::scaling_symm / scaling_hemm
#include "oz2/scaling/accu/extract_symm_hemm.hpp"     // scaling::accu::extract_symm / extract_hemm
#include "oz2/scaling/accu/scaling_symm_hemm.hpp"     // scaling::accu::scaling_symm / scaling_hemm
#include "oz2/scaling/general/scaling_symm_hemm.hpp"  // scaling::general::scaling_symm / scaling_hemm kernels
#include "oz2/undo_scaling/undo_scaling_syr2k_her2k.hpp" // undo_scaling::undo_scaling_syr2k / undo_scaling_her2k

namespace gemmul8 {

template std::vector<double> gemm<double, Backend::INT8, double, double>(
    cublasHandle_t,
    cublasOperation_t, cublasOperation_t,
    size_t, size_t, size_t,
    const double *,
    const double *const, size_t,
    const double *const, size_t,
    const double *,
    double *const, size_t,
    int, bool,
    void *const,
    void *const,
    void *const,
    bool, bool, bool, bool);

template std::vector<double> gemm<cuDoubleComplex, Backend::INT8, cuDoubleComplex, cuDoubleComplex>(
    cublasHandle_t,
    cublasOperation_t, cublasOperation_t,
    size_t, size_t, size_t,
    const cuDoubleComplex *,
    const cuDoubleComplex *const, size_t,
    const cuDoubleComplex *const, size_t,
    const cuDoubleComplex *,
    cuDoubleComplex *const, size_t,
    int, bool,
    void *const,
    void *const,
    void *const,
    bool, bool, bool, bool);

// symm (double)
template std::vector<double> symm<double, Backend::INT8, double, double>(
    cublasHandle_t,
    cublasSideMode_t, cublasFillMode_t,
    size_t, size_t,
    const double *,
    const double *const, size_t,
    const double *const, size_t,
    const double *,
    double *const, size_t,
    int, bool,
    void *const, void *const, void *const,
    bool, bool, bool, bool);

// syr2k (double)
template std::vector<double> syr2k<double, Backend::INT8, double, double>(
    cublasHandle_t,
    cublasFillMode_t, cublasOperation_t,
    size_t, size_t,
    const double *,
    const double *const, size_t,
    const double *const, size_t,
    const double *,
    double *const, size_t,
    int, bool,
    void *const, void *const, void *const,
    bool, bool, bool, bool);

// trmm (double) -- OUT-OF-PLACE: separate B (input) and C (output); NO beta arg
template std::vector<double> trmm<double, Backend::INT8, double, double>(
    cublasHandle_t,
    cublasSideMode_t, cublasFillMode_t,
    cublasOperation_t, cublasDiagType_t,
    size_t, size_t,
    const double *,
    const double *const, size_t,
    const double *const, size_t,
    double *const, size_t,
    int, bool,
    void *const, void *const, void *const,
    bool, bool, bool, bool);

// hemm (cuDoubleComplex)
template std::vector<double> hemm<cuDoubleComplex, Backend::INT8, cuDoubleComplex, cuDoubleComplex>(
    cublasHandle_t,
    cublasSideMode_t, cublasFillMode_t,
    size_t, size_t,
    const cuDoubleComplex *,
    const cuDoubleComplex *const, size_t,
    const cuDoubleComplex *const, size_t,
    const cuDoubleComplex *,
    cuDoubleComplex *const, size_t,
    int, bool,
    void *const, void *const, void *const,
    bool, bool, bool, bool);

// her2k (cuDoubleComplex) -- REAL beta (double); alpha is complex (TC*)
template std::vector<double> her2k<cuDoubleComplex, Backend::INT8, cuDoubleComplex, cuDoubleComplex>(
    cublasHandle_t,
    cublasFillMode_t, cublasOperation_t,
    size_t, size_t,
    const cuDoubleComplex *,
    const cuDoubleComplex *const, size_t,
    const cuDoubleComplex *const, size_t,
    const std::conditional_t<std::is_same_v<cuDoubleComplex, cuDoubleComplex>, double, float> *,
    cuDoubleComplex *const, size_t,
    int, bool,
    void *const, void *const, void *const,
    bool, bool, bool, bool);
// (equivalently the beta parameter type is `const double *`)

// trmm (cuDoubleComplex)
template std::vector<double> trmm<cuDoubleComplex, Backend::INT8, cuDoubleComplex, cuDoubleComplex>(
    cublasHandle_t,
    cublasSideMode_t, cublasFillMode_t,
    cublasOperation_t, cublasDiagType_t,
    size_t, size_t,
    const cuDoubleComplex *,
    const cuDoubleComplex *const, size_t,
    const cuDoubleComplex *const, size_t,
    cuDoubleComplex *const, size_t,
    int, bool,
    void *const, void *const, void *const,
    bool, bool, bool, bool);

template size_t workSize<false, Backend::INT8, Func::gemm>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);

template size_t workSize<true, Backend::INT8, Func::gemm>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);

template size_t workSize<false, Backend::INT8, Func::symm>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);
template size_t workSize<false, Backend::INT8, Func::syr2k>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);
template size_t workSize<false, Backend::INT8, Func::trmm>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);
template size_t workSize<true, Backend::INT8, Func::hemm>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);
template size_t workSize<true, Backend::INT8, Func::her2k>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);
template size_t workSize<true, Backend::INT8, Func::trmm>(
    size_t, size_t, size_t, int, bool, bool, size_t *, size_t *);

} // namespace gemmul8
