/*
 * Copyright 2020 NVIDIA Corporation.  All rights reserved.
 *
 * NOTICE TO LICENSEE:
 *
 * This source code and/or documentation ("Licensed Deliverables") are
 * subject to NVIDIA intellectual property rights under U.S. and
 * international Copyright laws.
 *
 * These Licensed Deliverables contained herein is PROPRIETARY and
 * CONFIDENTIAL to NVIDIA and is being provided under the terms and
 * conditions of a form of NVIDIA software license agreement by and
 * between NVIDIA and Licensee ("License Agreement") or electronically
 * accepted by Licensee.  Notwithstanding any terms or conditions to
 * the contrary in the License Agreement, reproduction or disclosure
 * of the Licensed Deliverables to any third party without the express
 * written consent of NVIDIA is prohibited.
 *
 * NOTWITHSTANDING ANY TERMS OR CONDITIONS TO THE CONTRARY IN THE
 * LICENSE AGREEMENT, NVIDIA MAKES NO REPRESENTATION ABOUT THE
 * SUITABILITY OF THESE LICENSED DELIVERABLES FOR ANY PURPOSE.  IT IS
 * PROVIDED "AS IS" WITHOUT EXPRESS OR IMPLIED WARRANTY OF ANY KIND.
 * NVIDIA DISCLAIMS ALL WARRANTIES WITH REGARD TO THESE LICENSED
 * DELIVERABLES, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY,
 * NONINFRINGEMENT, AND FITNESS FOR A PARTICULAR PURPOSE.
 * NOTWITHSTANDING ANY TERMS OR CONDITIONS TO THE CONTRARY IN THE
 * LICENSE AGREEMENT, IN NO EVENT SHALL NVIDIA BE LIABLE FOR ANY
 * SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, OR ANY
 * DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
 * WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
 * ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
 * OF THESE LICENSED DELIVERABLES.
 *
 * U.S. Government End Users.  These Licensed Deliverables are a
 * "commercial item" as that term is defined at 48 C.F.R. 2.101 (OCT
 * 1995), consisting of "commercial computer software" and "commercial
 * computer software documentation" as such terms are used in 48
 * C.F.R. 12.212 (SEPT 1995) and is provided to the U.S. Government
 * only as a commercial end item.  Consistent with 48 C.F.R.12.212 and
 * 48 C.F.R. 227.7202-1 through 227.7202-4 (JUNE 1995), all
 * U.S. Government End Users acquire the Licensed Deliverables with
 * only those rights set forth herein.
 *
 * Any use of the Licensed Deliverables in individual and commercial
 * software must include, in the user documentation and internal
 * comments to the code, the above Disclaimer and U.S. Government End
 * Users Notice.
 */

#include "openmx_common.h"
#include "set_hip_default_device_from_local_rank.h"
#include "set_openmp_device_from_local_rank.h"
#include <assert.h>
#include "hip_runtime_compat.h"
#include "hipsolver_compat.h"
#include <omp.h>
#include <stdint.h>
#include <stdio.h>

int32_t gpusolver_Syevdx(double * A, double * W, int32_t m, int32_t MaxN)
{
    int32_t const lda = m;

    hipsolverDnHandle_t hipsolverH = NULL;
    hipStream_t       stream    = NULL;

    double *  d_A = NULL;
    double *  d_W = NULL;
    double    vl     = 0.0;
    double    vu     = 0.0;
    int       h_meig = 0;
    int       lwork  = 0;
    int32_t * d_info = NULL;

    int32_t info = 0;

    size_t workspaceInBytesOnDevice = 0;    /* size of workspace */
    void * d_work                   = NULL; /* device workspace */
    size_t workspaceInBytesOnHost   = 0;    /* size of workspace */
    void * h_work                   = NULL; /* host workspace for */

    /* step 1: create gpusolver handle, bind a stream */
    wait_hipfunc(hipsolverDnCreate(&hipsolverH));

    wait_hipfunc(hipStreamCreateWithFlags(&stream, hipStreamNonBlocking));
    wait_hipfunc(hipsolverDnSetStream(hipsolverH, stream));

    wait_hipfunc(hipMalloc((void **)(&d_A), sizeof(double) * lda * m));
    wait_hipfunc(hipMalloc((void **)(&d_W), sizeof(double) * m));
    wait_hipfunc(hipMalloc((void **)(&d_info), sizeof(int32_t)));

    wait_hipfunc(hipMemcpyAsync(d_A, A, sizeof(double) * lda * m, hipMemcpyHostToDevice, stream));

    // step 3: query working space of syevd
    hipsolverEigMode_t  jobz = HIPSOLVER_EIG_MODE_VECTOR;  // compute eigenvalues and eigenvectors.
    hipblasFillMode_t   uplo = HIPBLAS_FILL_MODE_LOWER;
    hipsolverEigRange_t range;
    if (m == MaxN) {
        range = HIPSOLVER_EIG_RANGE_ALL;
    } else {
        range = HIPSOLVER_EIG_RANGE_I;
    }

    wait_hipfunc(hipsolverDnDsyevdx_bufferSize(hipsolverH, jobz, range, uplo, m, d_A, lda, vl, vu,
                                                1, MaxN, &h_meig, d_W, &lwork));
    workspaceInBytesOnDevice = (size_t)lwork * sizeof(double);
    workspaceInBytesOnHost = 0;

    wait_hipfunc(hipMalloc((void **)(&d_work), workspaceInBytesOnDevice));
    h_work = (workspaceInBytesOnHost == 0) ? NULL : malloc(workspaceInBytesOnHost);
    if (workspaceInBytesOnHost != 0 && !h_work) {
        fprintf(stderr, "Could not allocate host memory.\n");
        exit(1);
    }

    // step 4: compute spectrum
    wait_hipfunc(hipsolverDnDsyevdx(hipsolverH, jobz, range, uplo, m, d_A, lda, vl, vu, 1, MaxN,
                                     &h_meig, d_W, (double *)d_work, lwork, d_info));

    wait_hipfunc(hipMemcpyAsync(A, d_A, sizeof(double) * lda * m, hipMemcpyDeviceToHost, stream));
    wait_hipfunc(hipMemcpyAsync(W, d_W, sizeof(double) * MaxN, hipMemcpyDeviceToHost, stream));
    wait_hipfunc(hipMemcpyAsync(&info, d_info, sizeof(int32_t), hipMemcpyDeviceToHost, stream));

    wait_hipfunc(hipStreamSynchronize(stream));
    /* free resources */
    wait_hipfunc(hipFree(d_A));
    wait_hipfunc(hipFree(d_W));
    wait_hipfunc(hipFree(d_info));
    wait_hipfunc(hipFree(d_work));
    if (h_work != NULL) free(h_work);

    wait_hipfunc(hipsolverDnDestroy(hipsolverH));

    wait_hipfunc(hipStreamDestroy(stream));

    return info;
}

int32_t gpusolver_Syevdx_openmp(double * A, double * W, int32_t m, int32_t MaxN)
{
    int32_t info = 0;

    /* step 1: create gpusolver handle, bind a stream */
    {
        hipsolverDnHandle_t hipsolverH = NULL;

        wait_hipfunc(hipsolverDnCreate(&hipsolverH));

        hipStream_t stream = NULL;
        wait_hipfunc(hipStreamCreateWithFlags(&stream, hipStreamNonBlocking));
        wait_hipfunc(hipsolverDnSetStream(hipsolverH, stream));

        //  wait_hipfunc(hipMalloc((void **)(&d_A), sizeof(double) * lda * m));
        //  wait_hipfunc(hipMalloc((void **)(&d_W), sizeof(double) * m));
        // wait_hipfunc(hipMalloc((void **)(&d_info), sizeof(int32_t)));

        //  wait_hipfunc(hipMemcpyAsync(d_A, A, sizeof(double) * lda * m, hipMemcpyHostToDevice,
        //                             stream));

        // step 3: query working space of syevd
        hipsolverEigMode_t const  jobz  = HIPSOLVER_EIG_MODE_VECTOR;  // compute eigenvalues and eigenvectors.
        hipblasFillMode_t const   uplo  = HIPBLAS_FILL_MODE_LOWER;
        hipsolverEigRange_t const range = HIPSOLVER_EIG_RANGE_I;

        int32_t const lda = m;
        double        vl     = 0.0;
        double        vu     = 0.0;
        int           h_meig = 0;
        int           lwork  = 0;

        size_t workspaceInBytesOnDevice = 0; /* size of workspace */
        size_t workspaceInBytesOnHost   = 0; /* size of workspace */
        int32_t *d_info = NULL;

        wait_hipfunc(hipsolverDnDsyevdx_bufferSize(hipsolverH, jobz, range, uplo, m, A, lda, vl, vu,
                                                    1, MaxN, &h_meig, W, &lwork));
        workspaceInBytesOnDevice = (size_t)lwork * sizeof(double);
        workspaceInBytesOnHost = 0;

        void * d_work = NULL; /* device workspace */

        wait_hipfunc(hipMalloc((void **)(&d_work), workspaceInBytesOnDevice));
        wait_hipfunc(hipMalloc((void **)(&d_info), sizeof(int32_t)));

        void * h_work = NULL; /* host workspace for */

        h_work = (workspaceInBytesOnHost == 0) ? NULL : malloc(workspaceInBytesOnHost);
        if (workspaceInBytesOnHost != 0 && !h_work) {
            fprintf(stderr, "Could not allocate host memory.\n");
            exit(1);
        }

        //  step 4: compute spectrum
        wait_hipfunc(hipsolverDnDsyevdx(hipsolverH, jobz, range, uplo, m, A, lda, vl, vu, 1, MaxN,
                                         &h_meig, W, (double *)d_work, lwork, d_info));

        // wait_hipfunc(hipMemcpyAsync(A, d_A, sizeof(double) * lda * m, hipMemcpyDeviceToHost,
        //                            stream));
        // wait_hipfunc(hipMemcpyAsync(W, d_W, sizeof(double) * m, hipMemcpyDeviceToHost,
        //                            stream));
        wait_hipfunc(hipMemcpyAsync(&info, d_info, sizeof(int32_t), hipMemcpyDeviceToHost, stream));
        wait_hipfunc(hipStreamSynchronize(stream));
        /* free resources */
        // wait_hipfunc(hipFree(d_A));
        // wait_hipfunc(hipFree(d_W));
        wait_hipfunc(hipFree(d_info));
        wait_hipfunc(hipFree(d_work));
        if (h_work != NULL) free(h_work);

        wait_hipfunc(hipsolverDnDestroy(hipsolverH));
        wait_hipfunc(hipStreamDestroy(stream));
    }

    return info;
}

int32_t gpusolver_Syevdx_Complex(dcomplex * A, double * W, int32_t m, int32_t MaxN)
{
    int32_t const lda = m;

    hipsolverDnHandle_t hipsolverH = NULL;
    hipStream_t       stream    = NULL;

    hipDoubleComplex * d_A    = NULL;
    double *          d_W    = NULL;
    double            vl     = 0.0;
    double            vu     = 0.0;
    int               h_meig = 0;
    int               lwork  = 0;
    int32_t *         d_info = NULL;

    int32_t info = 0;

    size_t workspaceInBytesOnDevice = 0;    /* size of workspace */
    void * d_work                   = NULL; /* device workspace */
    size_t workspaceInBytesOnHost   = 0;    /* size of workspace */
    void * h_work                   = NULL; /* host workspace for */

    /* step 1: create gpusolver handle, bind a stream */
    wait_hipfunc(hipsolverDnCreate(&hipsolverH));

    wait_hipfunc(hipStreamCreateWithFlags(&stream, hipStreamNonBlocking));
    wait_hipfunc(hipsolverDnSetStream(hipsolverH, stream));

    wait_hipfunc(hipMalloc((void **)(&d_A), sizeof(hipDoubleComplex) * lda * m));
    wait_hipfunc(hipMalloc((void **)(&d_W), sizeof(double) * m));
    wait_hipfunc(hipMalloc((void **)(&d_info), sizeof(int32_t)));

    wait_hipfunc(hipMemcpyAsync(d_A, A, sizeof(hipDoubleComplex) * lda * m, hipMemcpyHostToDevice, stream));

    // step 3: query working space of syevd
    hipsolverEigMode_t  jobz  = HIPSOLVER_EIG_MODE_VECTOR;  // compute eigenvalues and eigenvectors.
    hipblasFillMode_t   uplo  = HIPBLAS_FILL_MODE_LOWER;
    hipsolverEigRange_t range = HIPSOLVER_EIG_RANGE_I;

    wait_hipfunc(hipsolverDnZheevdx_bufferSize(hipsolverH, jobz, range, uplo, m, d_A, lda, vl, vu,
                                                1, MaxN, &h_meig, d_W, &lwork));
    workspaceInBytesOnDevice = (size_t)lwork * sizeof(hipDoubleComplex);
    workspaceInBytesOnHost = 0;

    wait_hipfunc(hipMalloc((void **)(&d_work), workspaceInBytesOnDevice));
    h_work = (workspaceInBytesOnHost == 0) ? NULL : malloc(workspaceInBytesOnHost);
    if (workspaceInBytesOnHost != 0 && !h_work) {
        fprintf(stderr, "Could not allocate host memory.\n");
        exit(1);
    }

    // step 4: compute spectrum
    wait_hipfunc(hipsolverDnZheevdx(hipsolverH, jobz, range, uplo, m, d_A, lda, vl, vu, 1, MaxN,
                                     &h_meig, d_W, (hipDoubleComplex *)d_work, lwork, d_info));

    wait_hipfunc(hipMemcpyAsync(A, d_A, sizeof(hipDoubleComplex) * lda * m, hipMemcpyDeviceToHost, stream));
    wait_hipfunc(hipMemcpyAsync(W, d_W, sizeof(double) * MaxN, hipMemcpyDeviceToHost, stream));
    wait_hipfunc(hipMemcpyAsync(&info, d_info, sizeof(int32_t), hipMemcpyDeviceToHost, stream));

    wait_hipfunc(hipStreamSynchronize(stream));
    /* free resources */
    wait_hipfunc(hipFree(d_A));
    wait_hipfunc(hipFree(d_W));
    wait_hipfunc(hipFree(d_info));
    wait_hipfunc(hipFree(d_work));
    if (h_work != NULL) free(h_work);

    wait_hipfunc(hipsolverDnDestroy(hipsolverH));

    wait_hipfunc(hipStreamDestroy(stream));

    return info;
}

int32_t gpusolver_Syevdx_Complex_openmp(dcomplex * A, double * W, int32_t m, int32_t MaxN)
{
    int32_t const lda = m;

    hipsolverDnHandle_t hipsolverH = NULL;
    hipStream_t       stream    = NULL;
    //set_hip_default_device_from_local_rank();

    // OpenMP
    //set_openmp_nvidia_device_from_local_rank();

    // hipDoubleComplex* d_A = NULL;
    // double* d_W = NULL;
    double  vl     = 0.0;
    double  vu     = 0.0;
    int     h_meig = 0;
    int     lwork  = 0;
    // int32_t* d_info = NULL;

    int32_t info = 0;
    int32_t *d_info = NULL;

    size_t workspaceInBytesOnDevice = 0;    /* size of workspace */
    void * d_work                   = NULL; /* device workspace */
    size_t workspaceInBytesOnHost   = 0;    /* size of workspace */
    void * h_work                   = NULL; /* host workspace for */

    /* step 1: create gpusolver handle, bind a stream */
    {
        wait_hipfunc(hipsolverDnCreate(&hipsolverH));
        wait_hipfunc(hipStreamCreateWithFlags(&stream, hipStreamNonBlocking));
        wait_hipfunc(hipsolverDnSetStream(hipsolverH, stream));

        // wait_hipfunc(hipMallocAsync((void**)(&d_A), sizeof(hipDoubleComplex) * lda * m, stream));
        // wait_hipfunc(hipMallocAsync((void**)(&d_W), sizeof(double) * m, stream));
        // wait_hipfunc(hipMallocAsync((void**)(&d_info), sizeof(int32_t), stream));

        // wait_hipfunc(hipMemcpyAsync(d_A, A, sizeof(hipDoubleComplex) * lda * m, hipMemcpyHostToDevice,
        // stream));

        // step 3: query working space of syevd
        hipsolverEigMode_t const jobz = HIPSOLVER_EIG_MODE_VECTOR;  // compute eigenvalues and eigenvectors.
        hipblasFillMode_t const  uplo = HIPBLAS_FILL_MODE_LOWER;
        hipsolverEigRange_t      range;
        if (m == MaxN) {
            range = HIPSOLVER_EIG_RANGE_ALL;
        } else {
            range = HIPSOLVER_EIG_RANGE_I;
        }

        wait_hipfunc(hipsolverDnZheevdx_bufferSize(hipsolverH, jobz, range, uplo, m, (hipDoubleComplex *)A, lda, vl, vu,
                                                    1, MaxN, &h_meig, W, &lwork));
        workspaceInBytesOnDevice = (size_t)lwork * sizeof(hipDoubleComplex);
        workspaceInBytesOnHost = 0;

        wait_hipfunc(hipMallocAsync((void **)(&d_work), workspaceInBytesOnDevice, stream));
        wait_hipfunc(hipMallocAsync((void **)(&d_info), sizeof(int32_t), stream));

        h_work = (workspaceInBytesOnHost == 0) ? NULL : malloc(workspaceInBytesOnHost);
        if (workspaceInBytesOnHost != 0 && !h_work) {
            fprintf(stderr, "Could not allocate host memory.\n");
            exit(1);
        }

        // step 4: compute spectrum
        wait_hipfunc(hipsolverDnZheevdx(hipsolverH, jobz, range, uplo, m, (hipDoubleComplex *)A, lda, vl, vu, 1, MaxN,
                                         &h_meig, W, (hipDoubleComplex *)d_work, lwork, d_info));

        // wait_hipfunc(hipMemcpyAsync(A, d_A, sizeof(hipDoubleComplex) * lda * m, hipMemcpyDeviceToHost,
        //     stream));

        // wait_hipfunc(hipMemcpyAsync(W, d_W, sizeof(double) * m, hipMemcpyDeviceToHost,
        //     stream));

        wait_hipfunc(hipMemcpyAsync(&info, d_info, sizeof(int32_t), hipMemcpyDeviceToHost, stream));

        /* free resources */
        // wait_hipfunc(hipFreeAsync(d_A, stream));
        // wait_hipfunc(hipFreeAsync(d_W, stream));
        // wait_hipfunc(hipFreeAsync(d_info, stream));
        wait_hipfunc(hipStreamSynchronize(stream));

        wait_hipfunc(hipFree(d_work));
        wait_hipfunc(hipFree(d_info));

        if (h_work != NULL) {
            free(h_work);
        }

        wait_hipfunc(hipsolverDnDestroy(hipsolverH));
        wait_hipfunc(hipStreamDestroy(stream));
    }

    return info;
}
