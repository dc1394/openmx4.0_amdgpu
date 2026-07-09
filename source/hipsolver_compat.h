#ifndef OPENMX_AMDGPU_HIPSOLVER_COMPAT_H
#define OPENMX_AMDGPU_HIPSOLVER_COMPAT_H

/*
 * hipSOLVER compatibility header for OpenMX's own sources.
 * C++ TUs use the real ROCm hipSOLVER header; plain C TUs get the small set of
 * hipSOLVER prototypes/enums OpenMX calls, plus the generic-API emulation
 * wrappers (hipsolverDnXsyevd / hipsolverDnXsyevdx) built on the typed hipSOLVER
 * entry points.  See hip_runtime_compat.h for why the CUDA-named shim headers
 * are kept in the tree for the third-party libraries.
 */

#include <stdint.h>
#include <stddef.h>
#include "hip_runtime_compat.h"
#include "hipblas_compat.h"

#ifdef __cplusplus
#include <hipsolver/hipsolver.h>
#else
typedef struct hipsolverDnContext *hipsolverDnHandle_t;
typedef int hipsolverStatus_t;
typedef enum {
    HIPSOLVER_EIG_MODE_NOVECTOR = 201,
    HIPSOLVER_EIG_MODE_VECTOR = 202
} hipsolverEigMode_t;
typedef enum {
    HIPSOLVER_EIG_RANGE_ALL = 221,
    HIPSOLVER_EIG_RANGE_V = 222,
    HIPSOLVER_EIG_RANGE_I = 223
} hipsolverEigRange_t;
enum { HIPSOLVER_STATUS_SUCCESS = 0, HIPSOLVER_STATUS_NOT_SUPPORTED = 8 };
hipsolverStatus_t hipsolverDnCreate(hipsolverDnHandle_t *handle);
hipsolverStatus_t hipsolverDnDestroy(hipsolverDnHandle_t handle);
hipsolverStatus_t hipsolverDnSetStream(hipsolverDnHandle_t handle, hipStream_t streamId);
hipsolverStatus_t hipsolverDnDsyevdx_bufferSize(hipsolverDnHandle_t handle, hipsolverEigMode_t jobz,
    hipsolverEigRange_t range, hipblasFillMode_t uplo, int n, double *A, int lda, double vl, double vu,
    int il, int iu, int *nev, double *W, int *lwork);
hipsolverStatus_t hipsolverDnDsyevdx(hipsolverDnHandle_t handle, hipsolverEigMode_t jobz,
    hipsolverEigRange_t range, hipblasFillMode_t uplo, int n, double *A, int lda, double vl, double vu,
    int il, int iu, int *nev, double *W, double *work, int lwork, int *devInfo);
hipsolverStatus_t hipsolverDnDsyevd_bufferSize(hipsolverDnHandle_t handle, hipsolverEigMode_t jobz,
    hipblasFillMode_t uplo, int n, double *A, int lda, double *W, int *lwork);
hipsolverStatus_t hipsolverDnDsyevd(hipsolverDnHandle_t handle, hipsolverEigMode_t jobz,
    hipblasFillMode_t uplo, int n, double *A, int lda, double *W, double *work, int lwork,
    int *devInfo);
hipsolverStatus_t hipsolverDnZheevdx_bufferSize(hipsolverDnHandle_t handle, hipsolverEigMode_t jobz,
    hipsolverEigRange_t range, hipblasFillMode_t uplo, int n, hipDoubleComplex *A, int lda, double vl, double vu,
    int il, int iu, int *nev, double *W, int *lwork);
hipsolverStatus_t hipsolverDnZheevdx(hipsolverDnHandle_t handle, hipsolverEigMode_t jobz,
    hipsolverEigRange_t range, hipblasFillMode_t uplo, int n, hipDoubleComplex *A, int lda, double vl, double vu,
    int il, int iu, int *nev, double *W, hipDoubleComplex *work, int lwork, int *devInfo);
#endif

/*
 * Generic-API emulation wrappers (equivalent to cusolverDnXsyevd/Xsyevdx on the
 * NVIDIA build) implemented on top of the typed hipSOLVER entry points.
 */
static inline hipsolverStatus_t hipsolverDnXsyevd_bufferSize(
    hipsolverDnHandle_t handle, void *params, hipsolverEigMode_t jobz,
    hipblasFillMode_t uplo, int64_t n, hipDataType dataTypeA, const void *A,
    int64_t lda, hipDataType dataTypeW, const void *W,
    hipDataType computeType, size_t *workspaceInBytesOnDevice,
    size_t *workspaceInBytesOnHost)
{
    (void)params;
    (void)dataTypeW;
    (void)computeType;

    int lwork = 0;
    hipsolverStatus_t status;

    if (dataTypeA == HIP_R_64F) {
        status = hipsolverDnDsyevd_bufferSize(
            handle, jobz, uplo, (int)n, (double *)A, (int)lda,
            (double *)W, &lwork);
        *workspaceInBytesOnDevice = (size_t)lwork * sizeof(double);
    } else {
        return HIPSOLVER_STATUS_NOT_SUPPORTED;
    }

    if (workspaceInBytesOnHost != NULL) {
        *workspaceInBytesOnHost = 0;
    }
    return status;
}

static inline hipsolverStatus_t hipsolverDnXsyevd(
    hipsolverDnHandle_t handle, void *params, hipsolverEigMode_t jobz,
    hipblasFillMode_t uplo, int64_t n, hipDataType dataTypeA, void *A,
    int64_t lda, hipDataType dataTypeW, void *W, hipDataType computeType,
    void *d_work, size_t workspaceInBytesOnDevice, void *h_work,
    size_t workspaceInBytesOnHost, int *devInfo)
{
    (void)params;
    (void)dataTypeW;
    (void)computeType;
    (void)h_work;
    (void)workspaceInBytesOnHost;

    if (dataTypeA == HIP_R_64F) {
        return hipsolverDnDsyevd(
            handle, jobz, uplo, (int)n, (double *)A, (int)lda,
            (double *)W, (double *)d_work,
            (int)(workspaceInBytesOnDevice / sizeof(double)), devInfo);
    }

    return HIPSOLVER_STATUS_NOT_SUPPORTED;
}

static inline hipsolverStatus_t hipsolverDnXsyevdx_bufferSize(
    hipsolverDnHandle_t handle, void *params, hipsolverEigMode_t jobz,
    hipsolverEigRange_t range, hipblasFillMode_t uplo, int64_t n,
    hipDataType dataTypeA, const void *A, int64_t lda, const double *vl,
    const double *vu, int64_t il, int64_t iu, int64_t *h_meig,
    hipDataType dataTypeW, const void *W, hipDataType computeType,
    size_t *workspaceInBytesOnDevice, size_t *workspaceInBytesOnHost)
{
    (void)params;
    (void)dataTypeW;
    (void)computeType;

    int lwork = 0;
    int nev = 0;
    hipsolverStatus_t status;
    const double vl_value = (vl != NULL) ? *vl : 0.0;
    const double vu_value = (vu != NULL) ? *vu : 0.0;

    if (dataTypeA == HIP_R_64F) {
        status = hipsolverDnDsyevdx_bufferSize(
            handle, jobz, range, uplo, (int)n, (double *)A, (int)lda,
            vl_value, vu_value, (int)il, (int)iu, &nev, (double *)W, &lwork);
        *workspaceInBytesOnDevice = (size_t)lwork * sizeof(double);
    } else {
        status = hipsolverDnZheevdx_bufferSize(
            handle, jobz, range, uplo, (int)n, (hipDoubleComplex *)A, (int)lda,
            vl_value, vu_value, (int)il, (int)iu, &nev, (double *)W, &lwork);
        *workspaceInBytesOnDevice = (size_t)lwork * sizeof(hipDoubleComplex);
    }

    if (workspaceInBytesOnHost != NULL) {
        *workspaceInBytesOnHost = 0;
    }
    if (h_meig != NULL) {
        *h_meig = (range == HIPSOLVER_EIG_RANGE_ALL) ? n : (iu - il + 1);
    }
    return status;
}

static inline hipsolverStatus_t hipsolverDnXsyevdx(
    hipsolverDnHandle_t handle, void *params, hipsolverEigMode_t jobz,
    hipsolverEigRange_t range, hipblasFillMode_t uplo, int64_t n,
    hipDataType dataTypeA, void *A, int64_t lda, const double *vl,
    const double *vu, int64_t il, int64_t iu, int64_t *h_meig,
    hipDataType dataTypeW, void *W, hipDataType computeType, void *d_work,
    size_t workspaceInBytesOnDevice, void *h_work, size_t workspaceInBytesOnHost,
    int *devInfo)
{
    (void)params;
    (void)dataTypeW;
    (void)computeType;
    (void)h_work;
    (void)workspaceInBytesOnHost;

    int nev = 0;
    int lwork;
    hipsolverStatus_t status;
    const double vl_value = (vl != NULL) ? *vl : 0.0;
    const double vu_value = (vu != NULL) ? *vu : 0.0;

    if (dataTypeA == HIP_R_64F) {
        lwork = (int)(workspaceInBytesOnDevice / sizeof(double));
        status = hipsolverDnDsyevdx(
            handle, jobz, range, uplo, (int)n, (double *)A, (int)lda,
            vl_value, vu_value, (int)il, (int)iu, &nev, (double *)W,
            (double *)d_work, lwork, devInfo);
    } else {
        lwork = (int)(workspaceInBytesOnDevice / sizeof(hipDoubleComplex));
        status = hipsolverDnZheevdx(
            handle, jobz, range, uplo, (int)n, (hipDoubleComplex *)A, (int)lda,
            vl_value, vu_value, (int)il, (int)iu, &nev, (double *)W,
            (hipDoubleComplex *)d_work, lwork, devInfo);
    }

    if (h_meig != NULL) {
        *h_meig = (range == HIPSOLVER_EIG_RANGE_ALL) ? n : (iu - il + 1);
    }
    return status;
}

#endif
