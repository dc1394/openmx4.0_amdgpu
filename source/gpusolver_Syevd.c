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
#include "hip_runtime_compat.h"
#include "hipsolver_compat.h"
#include <stdint.h>
#include <stdlib.h>

int32_t gpusolver_Syevd(double * A, double * W, int32_t m)
{
    int32_t deviceCount;
    wait_hipfunc(hipGetDeviceCount(&deviceCount));

    if (0 < SCF_Gpu_Num && SCF_Gpu_Num < deviceCount) deviceCount = SCF_Gpu_Num;

    wait_hipfunc(hipSetDevice(openmx_gpu_map_rank_to_device(
        openmx_gpu_local_rank_noncollective(),
        openmx_gpu_local_size_noncollective(), deviceCount)));

    hipsolverDnHandle_t hipsolverH = NULL;
    hipStream_t       stream    = NULL;

    /* step 1: create gpusolver handle, bind a stream */
    wait_hipfunc(hipsolverDnCreate(&hipsolverH));

    wait_hipfunc(hipStreamCreateWithFlags(&stream, hipStreamNonBlocking));
    wait_hipfunc(hipsolverDnSetStream(hipsolverH, stream));

    int32_t const lda    = m;
    double *      d_A    = NULL;
    double *      d_W    = NULL;
    int32_t *     d_info = NULL;

    wait_hipfunc(hipMalloc((void **)(&d_A), sizeof(double) * lda * m));
    wait_hipfunc(hipMalloc((void **)(&d_W), sizeof(double) * m));
    wait_hipfunc(hipMalloc((void **)(&d_info), sizeof(int32_t)));

    wait_hipfunc(hipMemcpyAsync(d_A, A, sizeof(double) * lda * m, hipMemcpyHostToDevice, stream));

    // step 3: query working space of syevd
    hipsolverEigMode_t const jobz = HIPSOLVER_EIG_MODE_VECTOR;  // compute eigenvalues and eigenvectors.
    hipblasFillMode_t  const uplo = HIPBLAS_FILL_MODE_LOWER;

    size_t d_lwork = 0; /* size of workspace */
    size_t h_lwork = 0; /* size of workspace */

    wait_hipfunc(hipsolverDnXsyevd_bufferSize(hipsolverH, NULL, jobz, uplo, m, HIP_R_64F, d_A, lda, HIP_R_64F, d_W,
                                              HIP_R_64F, &d_lwork, &h_lwork));

    void * d_work = NULL; /* device workspace */

    wait_hipfunc(hipMalloc((void **)(&d_work), d_lwork));

    // host workspace for
    void * h_work = malloc(h_lwork);
    if (!h_work) {
        fprintf(stderr, "Could not allocate host memory.\n");
        exit(1);
    }

    // step 4: compute spectrum
    wait_hipfunc(hipsolverDnXsyevd(hipsolverH, NULL, jobz, uplo, m, HIP_R_64F, d_A, lda, HIP_R_64F, d_W, HIP_R_64F,
                                   d_work, d_lwork, h_work, h_lwork, d_info));

    wait_hipfunc(hipMemcpyAsync(A, d_A, sizeof(double) * lda * m, hipMemcpyDeviceToHost, stream));
    wait_hipfunc(hipMemcpyAsync(W, d_W, sizeof(double) * m, hipMemcpyDeviceToHost, stream));

    int32_t info;

    wait_hipfunc(hipMemcpyAsync(&info, d_info, sizeof(int32_t), hipMemcpyDeviceToHost, stream));

    wait_hipfunc(hipStreamSynchronize(stream));

    /* free resources */
    wait_hipfunc(hipFree(d_A));
    wait_hipfunc(hipFree(d_W));
    wait_hipfunc(hipFree(d_info));
    wait_hipfunc(hipFree(d_work));
    free(h_work);

    wait_hipfunc(hipsolverDnDestroy(hipsolverH));

    wait_hipfunc(hipStreamDestroy(stream));

    return info;
}
