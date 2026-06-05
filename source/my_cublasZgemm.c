#include "openmx_common.h"
#include <cuda_runtime.h>
#include <openacc.h>
#include <stdlib.h>
#include <stdio.h>

extern void F77_NAME(zgemm, ZGEMM)(char *TRANSA, char *TRANSB, INTEGER *M, INTEGER *N, INTEGER *K, dcomplex *ALPHA,
                                   dcomplex *A, INTEGER *LDA, dcomplex *B, INTEGER *LDB, dcomplex *BETA,
                                   dcomplex *C, INTEGER *LDC);

static const char *OpenMX_ZgemmCublasStatusName(cublasStatus_t status)
{
    switch (status) {
    case CUBLAS_STATUS_SUCCESS:
        return "CUBLAS_STATUS_SUCCESS";
    case CUBLAS_STATUS_NOT_INITIALIZED:
        return "CUBLAS_STATUS_NOT_INITIALIZED";
    case CUBLAS_STATUS_ALLOC_FAILED:
        return "CUBLAS_STATUS_ALLOC_FAILED";
    case CUBLAS_STATUS_INVALID_VALUE:
        return "CUBLAS_STATUS_INVALID_VALUE";
    case CUBLAS_STATUS_ARCH_MISMATCH:
        return "CUBLAS_STATUS_ARCH_MISMATCH";
    case CUBLAS_STATUS_MAPPING_ERROR:
        return "CUBLAS_STATUS_MAPPING_ERROR";
    case CUBLAS_STATUS_EXECUTION_FAILED:
        return "CUBLAS_STATUS_EXECUTION_FAILED";
    case CUBLAS_STATUS_INTERNAL_ERROR:
        return "CUBLAS_STATUS_INTERNAL_ERROR";
    case CUBLAS_STATUS_NOT_SUPPORTED:
        return "CUBLAS_STATUS_NOT_SUPPORTED";
    default:
        return "CUBLAS_STATUS_UNKNOWN";
    }
}

static int OpenMX_ZgemmRank(void)
{
    int initialized = 0;
    int rank = -1;

    MPI_Initialized(&initialized);
    if (initialized) {
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    }

    return rank;
}

static char OpenMX_ZgemmOpChar(cublasOperation_t op)
{
    if (op == CUBLAS_OP_C) {
        return 'C';
    }
    return (op == CUBLAS_OP_N) ? 'N' : 'T';
}

static void OpenMX_ZgemmCpu(cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k,
                            dcomplex const *A, dcomplex const *B, dcomplex *C)
{
    char transa_cpu = OpenMX_ZgemmOpChar(transa);
    char transb_cpu = OpenMX_ZgemmOpChar(transb);
    INTEGER mi = m;
    INTEGER ni = n;
    INTEGER ki = k;
    INTEGER lda = m;
    INTEGER ldb = k;
    INTEGER ldc = m;
    dcomplex alpha = {1.0, 0.0};
    dcomplex beta = {0.0, 0.0};

    F77_NAME(zgemm, ZGEMM)(&transa_cpu, &transb_cpu, &mi, &ni, &ki, &alpha, (dcomplex *)A, &lda, (dcomplex *)B,
                           &ldb, &beta, C, &ldc);
}

static void OpenMX_ZgemmLogGemmul8Retry(const char *where, cublasStatus_t status, int m, int n, int k)
{
    fprintf(stderr,
            "<GEMM> rank %d: GEMMul8 failed in %s for ZGEMM(m=%d,n=%d,k=%d): %s (%d). "
            "Retrying with native cuBLAS/hipBLAS.\n",
            OpenMX_ZgemmRank(), where, m, n, k, OpenMX_ZgemmCublasStatusName(status), (int)status);
    fflush(stderr);
}

static void OpenMX_ZgemmLogCpuFallback(const char *where, const char *backend, cublasStatus_t status, int m, int n,
                                       int k)
{
    fprintf(stderr,
            "<GEMM> rank %d: %s failed in %s for ZGEMM(m=%d,n=%d,k=%d): %s (%d). "
            "Falling back to CPU BLAS.\n",
            OpenMX_ZgemmRank(), backend, where, m, n, k, OpenMX_ZgemmCublasStatusName(status), (int)status);
    fflush(stderr);
}

static void OpenMX_ZgemmLogCudaCpuFallback(const char *where, cudaError_t status, int m, int n, int k)
{
    fprintf(stderr,
            "<GEMM> rank %d: GPU setup/transfer failed in %s for ZGEMM(m=%d,n=%d,k=%d): %s (%d). "
            "Falling back to CPU BLAS.\n",
            OpenMX_ZgemmRank(), where, m, n, k, cudaGetErrorString(status), (int)status);
    fflush(stderr);
}

static void OpenMX_ZgemmLogBackendOnce(const char *backend, int m, int n, int k)
{
    static int logged_gemmul8 = 0;
    static int logged_native = 0;
    int rank = OpenMX_ZgemmRank();
    int *logged = (backend[0] == 'G') ? &logged_gemmul8 : &logged_native;

    if (rank != 0 || *logged) return;

    fprintf(stderr,
            "<GEMM> rank %d: using %s for ZGEMM(m=%d,n=%d,k=%d). "
            "If it fails, OpenMX retries native cuBLAS/hipBLAS and then CPU BLAS.\n",
            rank, backend, m, n, k);
    fflush(stderr);
    *logged = 1;
}

static cublasStatus_t OpenMX_ZgemmTryGpu(cublasHandle_t handle, cublasOperation_t transa, cublasOperation_t transb,
                                         int m, int n, int k, dcomplex const *A, dcomplex const *B, dcomplex *C,
                                         const char *where)
{
    cuDoubleComplex const alpha = make_cuDoubleComplex(1.0, 0.0);
    cuDoubleComplex const beta = make_cuDoubleComplex(0.0, 0.0);
    cublasStatus_t status;

    status = openmx_gemmul8Zgemm(handle, transa, transb, m, n, k, &alpha, (cuDoubleComplex const *)A, m,
                                 (cuDoubleComplex const *)B, k, &beta, (cuDoubleComplex *)C, m);
    if (status == CUBLAS_STATUS_SUCCESS) {
        OpenMX_ZgemmLogBackendOnce("GEMMul8", m, n, k);
        return status;
    }

    OpenMX_ZgemmLogGemmul8Retry(where, status, m, n, k);
    status = cublasZgemm(handle, transa, transb, m, n, k, &alpha, (cuDoubleComplex const *)A, m,
                         (cuDoubleComplex const *)B, k, &beta, (cuDoubleComplex *)C, m);
    if (status == CUBLAS_STATUS_SUCCESS) {
        OpenMX_ZgemmLogBackendOnce("native cuBLAS/hipBLAS", m, n, k);
    }
    return status;
}

void my_cublasZgemm(cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k, dcomplex const * A,
    dcomplex const * B, dcomplex * C)
{
    cublasHandle_t handle = NULL;
    cublasStatus_t status;
    cudaError_t cuda_status;
    cuDoubleComplex *d_A = NULL;
    cuDoubleComplex *d_B = NULL;
    cuDoubleComplex *d_C = NULL;

    status = cublasCreate(&handle);
    if (status != CUBLAS_STATUS_SUCCESS) {
        OpenMX_ZgemmLogCpuFallback("my_cublasZgemm:cublasCreate", "native cuBLAS/hipBLAS", status, m, n, k);
        OpenMX_ZgemmCpu(transa, transb, m, n, k, A, B, C);
        return;
    }

    cuda_status = cudaMalloc((void **)&d_A, m * k * sizeof(cuDoubleComplex));
    if (cuda_status != cudaSuccess) {
        OpenMX_ZgemmLogCudaCpuFallback("my_cublasZgemm:cudaMalloc(A)", cuda_status, m, n, k);
        goto cpu_fallback;
    }
    cuda_status = cudaMalloc((void **)&d_B, n * k * sizeof(cuDoubleComplex));
    if (cuda_status != cudaSuccess) {
        OpenMX_ZgemmLogCudaCpuFallback("my_cublasZgemm:cudaMalloc(B)", cuda_status, m, n, k);
        goto cpu_fallback;
    }
    cuda_status = cudaMalloc((void **)&d_C, m * n * sizeof(cuDoubleComplex));
    if (cuda_status != cudaSuccess) {
        OpenMX_ZgemmLogCudaCpuFallback("my_cublasZgemm:cudaMalloc(C)", cuda_status, m, n, k);
        goto cpu_fallback;
    }

    cuda_status = cudaMemcpy(d_A, A, m * k * sizeof(cuDoubleComplex), cudaMemcpyHostToDevice);
    if (cuda_status != cudaSuccess) {
        OpenMX_ZgemmLogCudaCpuFallback("my_cublasZgemm:cudaMemcpy(A)", cuda_status, m, n, k);
        goto cpu_fallback;
    }
    cuda_status = cudaMemcpy(d_B, B, n * k * sizeof(cuDoubleComplex), cudaMemcpyHostToDevice);
    if (cuda_status != cudaSuccess) {
        OpenMX_ZgemmLogCudaCpuFallback("my_cublasZgemm:cudaMemcpy(B)", cuda_status, m, n, k);
        goto cpu_fallback;
    }

    status = OpenMX_ZgemmTryGpu(handle, transa, transb, m, n, k, (dcomplex const *)d_A, (dcomplex const *)d_B,
                                (dcomplex *)d_C, "my_cublasZgemm");
    if (status != CUBLAS_STATUS_SUCCESS) {
        OpenMX_ZgemmLogCpuFallback("my_cublasZgemm", "native cuBLAS/hipBLAS", status, m, n, k);
        goto cpu_fallback;
    }

    cuda_status = cudaMemcpy(C, d_C, m * n * sizeof(cuDoubleComplex), cudaMemcpyDeviceToHost);
    if (cuda_status != cudaSuccess) {
        OpenMX_ZgemmLogCudaCpuFallback("my_cublasZgemm:cudaMemcpy(C)", cuda_status, m, n, k);
        goto cpu_fallback;
    }

    if (d_A != NULL)
        wait_cudafunc(cudaFree(d_A));
    if (d_B != NULL)
        wait_cudafunc(cudaFree(d_B));
    if (d_C != NULL)
        wait_cudafunc(cudaFree(d_C));
    wait_cudafunc(cublasDestroy(handle));
    return;

cpu_fallback:
    if (d_A != NULL)
        cudaFree(d_A);
    if (d_B != NULL)
        cudaFree(d_B);
    if (d_C != NULL)
        cudaFree(d_C);
    if (handle != NULL)
        cublasDestroy(handle);
    OpenMX_ZgemmCpu(transa, transb, m, n, k, A, B, C);
}

void my_cublasZgemm_openacc(cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k, dcomplex const * A,
    dcomplex const * B, dcomplex * C)
{
    cublasHandle_t handle = NULL;
    cublasStatus_t status;

    status = cublasCreate(&handle);

#pragma acc data      present(A[0 : m * k], B[0 : k * n], C[0 : m * n])
    {
    if (status == CUBLAS_STATUS_SUCCESS) {
#pragma acc host_data use_device(A, B, C)
        {
            status = OpenMX_ZgemmTryGpu(handle, transa, transb, m, n, k, A, B, C, "my_cublasZgemm_openacc");
        }
    }

    if (handle != NULL) {
        cublasStatus_t destroy_status = cublasDestroy(handle);
        if (destroy_status != CUBLAS_STATUS_SUCCESS) {
            fprintf(stderr, "<GEMM> rank %d: cublasDestroy failed after ZGEMM: %s (%d).\n", OpenMX_ZgemmRank(),
                    OpenMX_ZgemmCublasStatusName(destroy_status), (int)destroy_status);
            fflush(stderr);
        }
    }

    if (status != CUBLAS_STATUS_SUCCESS) {
        OpenMX_ZgemmLogCpuFallback("my_cublasZgemm_openacc", "native cuBLAS/hipBLAS", status, m, n, k);
#pragma acc update self(A[0 : m * k], B[0 : k * n])
        OpenMX_ZgemmCpu(transa, transb, m, n, k, A, B, C);
#pragma acc update device(C[0 : m * n])
    }
    }
}
