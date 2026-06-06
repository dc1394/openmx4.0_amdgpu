/*
-- MAGMA (version 2.9.0) --
 Univ. of Tennessee, Knoxville
 Univ. of California, Berkeley
 Univ. of Colorado, Denver
 @date January 2025

 @generated from sparse/include/magmasparse_zc.h, mixed zc -> ds, Wed Jan 22 14:42:56 2025
 @author Hartwig Anzt
*/

#ifndef MAGMASPARSE_DS_H
#define MAGMASPARSE_DS_H

#include "magma_types.h"
#include "magmasparse_types.h"

#define PRECISION_d


/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE Matrix Descriptors
*/


#ifdef __cplusplus
extern "C" {
#endif

/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE Auxiliary functions
*/
/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_vector_zlac2c is deprecated and will be removed in the next release")
magma_int_t
magma_vector_dlag2s(
    magma_d_matrix x,
    magma_s_matrix *y,
    magma_queue_t queue );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_sparse_matrix_zlac2c is deprecated and will be removed in the next release")
magma_int_t
magma_sparse_matrix_dlag2s(
    magma_d_matrix A,
    magma_s_matrix *B,
    magma_queue_t queue );


/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_vector_slag2d is deprecated and will be removed in the next release")
magma_int_t
magma_vector_slag2d(
    magma_s_matrix x,
    magma_d_matrix *y,
    magma_queue_t queue );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_sparse_matrix_slag2d is deprecated and will be removed in the next release")
magma_int_t
magma_sparse_matrix_slag2d(
    magma_s_matrix A,
    magma_d_matrix *B,
    magma_queue_t queue );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magmablas_dlag2s_sparse is deprecated and will be removed in the next release")
void
magmablas_dlag2s_sparse(
    magma_int_t M,
    magma_int_t N ,
    magmaDouble_const_ptr dA,
    magma_int_t lda,
    magmaFloat_ptr dSA,
    magma_int_t ldsa,
    magma_queue_t queue,
    magma_int_t *info );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magmablas_slag2d_sparse is deprecated and will be removed in the next release")
void
magmablas_slag2d_sparse(
    magma_int_t M,
    magma_int_t N ,
    magmaFloat_const_ptr dSA,
    magma_int_t ldsa,
    magmaDouble_ptr dA,
    magma_int_t lda,
    magma_queue_t queue,
    magma_int_t *info );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_dlag2s_CSR_DENSE is deprecated and will be removed in the next release")
void
magma_dlag2s_CSR_DENSE(
    magma_d_matrix A,
    magma_s_matrix *B,
    magma_queue_t queue );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_dlag2s_CSR_DENSE_alloc is deprecated and will be removed in the next release")
void
magma_dlag2s_CSR_DENSE_alloc(
    magma_d_matrix A,
    magma_s_matrix *B,
    magma_queue_t queue );

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_dlag2s_CSR_DENSE_convert is deprecated and will be removed in the next release")
void
magma_dlag2s_CSR_DENSE_convert(
    magma_d_matrix A,
    magma_s_matrix *B,
    magma_queue_t queue );

/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE function definitions / Data on CPU
*/


/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE function definitions / Data on CPU / Multi-GPU
*/

/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE function definitions / Data on GPU
*/

/// @deprecated
/// @ingroup magma_deprecated_sparse
MAGMA_DEPRECATE("magma_dlag2s_CSR_DENSE_convert is deprecated and will be removed in the next release")
magma_int_t
magma_dsgecsrmv_mixed_prec(
    magma_trans_t transA,
    magma_int_t m, magma_int_t n,
    double alpha,
    magmaDouble_ptr ddiagval,
    magmaFloat_ptr doffdiagval,
    magmaIndex_ptr drowptr,
    magmaIndex_ptr dcolind,
    magmaDouble_ptr dx,
    double beta,
    magmaDouble_ptr dy,
    magma_queue_t queue );



/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE utility function definitions
*/



/* ////////////////////////////////////////////////////////////////////////////
 -- MAGMA_SPARSE BLAS function definitions
*/



#ifdef __cplusplus
}
#endif

#undef PRECISION_d
#endif /* MAGMASPARSE_DS_H */
