#include "openmx_common.h"
#include <cuda_runtime.h>
#include <openacc.h>
#include <stdlib.h>
#include <stdio.h>

extern void F77_NAME(dgemm, DGEMM)(char *TRANSA, char *TRANSB, INTEGER *M, INTEGER *N, INTEGER *K, double *ALPHA,
                                   double *A, INTEGER *LDA, double *B, INTEGER *LDB, double *BETA, double *C,
                                   INTEGER *LDC);

static const char *OpenMX_DgemmCublasStatusName(cublasStatus_t status)
{
    switch (status) {
    case CUBLAS_STATUS_SUCCESS:
        return "HIPBLAS_STATUS_SUCCESS";
    case CUBLAS_STATUS_NOT_INITIALIZED:
        return "HIPBLAS_STATUS_NOT_INITIALIZED";
    case CUBLAS_STATUS_ALLOC_FAILED:
        return "HIPBLAS_STATUS_ALLOC_FAILED";
    case CUBLAS_STATUS_INVALID_VALUE:
        return "HIPBLAS_STATUS_INVALID_VALUE";
    case CUBLAS_STATUS_ARCH_MISMATCH:
        return "HIPBLAS_STATUS_ARCH_MISMATCH";
    case CUBLAS_STATUS_MAPPING_ERROR:
        return "HIPBLAS_STATUS_MAPPING_ERROR";
    case CUBLAS_STATUS_EXECUTION_FAILED:
        return "HIPBLAS_STATUS_EXECUTION_FAILED";
    case CUBLAS_STATUS_INTERNAL_ERROR:
        return "HIPBLAS_STATUS_INTERNAL_ERROR";
    case CUBLAS_STATUS_NOT_SUPPORTED:
        return "HIPBLAS_STATUS_NOT_SUPPORTED";
    default:
        return "HIPBLAS_STATUS_UNKNOWN";
    }
}

static int OpenMX_DgemmRank(void)
{
    int initialized = 0;
    int rank = -1;

    MPI_Initialized(&initialized);
    if (initialized) {
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    }

    return rank;
}

static char OpenMX_DgemmOpChar(cublasOperation_t op)
{
    return (op == CUBLAS_OP_N) ? 'N' : 'T';
}

static void OpenMX_DgemmCpu(cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k,
                            double const *A, double const *B, double *C)
{
    char transa_cpu = OpenMX_DgemmOpChar(transa);
    char transb_cpu = OpenMX_DgemmOpChar(transb);
    INTEGER mi = m;
    INTEGER ni = n;
    INTEGER ki = k;
    INTEGER lda = m;
    INTEGER ldb = k;
    INTEGER ldc = m;
    double alpha = 1.0;
    double beta = 0.0;

    F77_NAME(dgemm, DGEMM)(&transa_cpu, &transb_cpu, &mi, &ni, &ki, &alpha, (double *)A, &lda, (double *)B, &ldb,
                           &beta, C, &ldc);
}

static void OpenMX_DgemmLogGemmul8Retry(const char *where, cublasStatus_t status, int m, int n, int k)
{
    fprintf(stderr,
            "<GEMM> rank %d: GEMMul8 failed in %s for DGEMM(m=%d,n=%d,k=%d): %s (%d). "
            "Retrying with native hipBLAS.\n",
            OpenMX_DgemmRank(), where, m, n, k, OpenMX_DgemmCublasStatusName(status), (int)status);
    fflush(stderr);
}

static void OpenMX_DgemmLogCpuFallback(const char *where, const char *backend, cublasStatus_t status, int m, int n,
                                       int k)
{
    fprintf(stderr,
            "<GEMM> rank %d: %s failed in %s for DGEMM(m=%d,n=%d,k=%d): %s (%d). "
            "Falling back to CPU BLAS.\n",
            OpenMX_DgemmRank(), backend, where, m, n, k, OpenMX_DgemmCublasStatusName(status), (int)status);
    fflush(stderr);
}

static void OpenMX_DgemmLogCudaCpuFallback(const char *where, cudaError_t status, int m, int n, int k)
{
    fprintf(stderr,
            "<GEMM> rank %d: GPU setup/transfer failed in %s for DGEMM(m=%d,n=%d,k=%d): %s (%d). "
            "Falling back to CPU BLAS.\n",
            OpenMX_DgemmRank(), where, m, n, k, cudaGetErrorString(status), (int)status);
    fflush(stderr);
}

static void OpenMX_DgemmLogBackendOnce(const char *backend, int m, int n, int k)
{
    static int logged_gemmul8 = 0;
    static int logged_native = 0;
    int rank = OpenMX_DgemmRank();
    int *logged = (backend[0] == 'G') ? &logged_gemmul8 : &logged_native;

    if (rank != 0 || *logged) return;

    fprintf(stderr,
            "<GEMM> rank %d: using %s for DGEMM(m=%d,n=%d,k=%d). "
            "If it fails, OpenMX retries native hipBLAS and then CPU BLAS.\n",
            rank, backend, m, n, k);
    fflush(stderr);
    *logged = 1;
}

static cublasStatus_t OpenMX_DgemmTryGpu(cublasHandle_t handle, cublasOperation_t transa, cublasOperation_t transb,
                                         int m, int n, int k, double const *A, double const *B, double *C,
                                         const char *where)
{
    double const alpha = 1.0;
    double const beta = 0.0;
    cublasStatus_t status;

    status = openmx_gemmul8Dgemm(handle, transa, transb, m, n, k, &alpha, A, m, B, k, &beta, C, m);
    if (status == CUBLAS_STATUS_SUCCESS) {
        OpenMX_DgemmLogBackendOnce("GEMMul8", m, n, k);
        return status;
    }

    OpenMX_DgemmLogGemmul8Retry(where, status, m, n, k);
    status = cublasDgemm(handle, transa, transb, m, n, k, &alpha, A, m, B, k, &beta, C, m);
    if (status == CUBLAS_STATUS_SUCCESS) {
        OpenMX_DgemmLogBackendOnce("native hipBLAS", m, n, k);
    }
    return status;
}

void my_cublasDgemm(cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k, double const * A,
                    double const * B, double * C)
{
    cublasHandle_t handle = NULL;
    cublasStatus_t status;
    cudaError_t cuda_status;
    double *d_A = NULL;
    double *d_B = NULL;
    double *d_C = NULL;

    status = cublasCreate(&handle);
    if (status != CUBLAS_STATUS_SUCCESS) {
        OpenMX_DgemmLogCpuFallback("my_cublasDgemm:hipblasCreate", "native hipBLAS", status, m, n, k);
        OpenMX_DgemmCpu(transa, transb, m, n, k, A, B, C);
        return;
    }

    cuda_status = cudaMalloc((void **)&d_A, m * k * sizeof(double));
    if (cuda_status != cudaSuccess) {
        OpenMX_DgemmLogCudaCpuFallback("my_cublasDgemm:hipMalloc(A)", cuda_status, m, n, k);
        goto cpu_fallback;
    }
    cuda_status = cudaMalloc((void **)&d_B, n * k * sizeof(double));
    if (cuda_status != cudaSuccess) {
        OpenMX_DgemmLogCudaCpuFallback("my_cublasDgemm:hipMalloc(B)", cuda_status, m, n, k);
        goto cpu_fallback;
    }
    cuda_status = cudaMalloc((void **)&d_C, m * n * sizeof(double));
    if (cuda_status != cudaSuccess) {
        OpenMX_DgemmLogCudaCpuFallback("my_cublasDgemm:hipMalloc(C)", cuda_status, m, n, k);
        goto cpu_fallback;
    }

    cuda_status = cudaMemcpy(d_A, A, m * k * sizeof(double), cudaMemcpyHostToDevice);
    if (cuda_status != cudaSuccess) {
        OpenMX_DgemmLogCudaCpuFallback("my_cublasDgemm:hipMemcpy(A)", cuda_status, m, n, k);
        goto cpu_fallback;
    }
    cuda_status = cudaMemcpy(d_B, B, n * k * sizeof(double), cudaMemcpyHostToDevice);
    if (cuda_status != cudaSuccess) {
        OpenMX_DgemmLogCudaCpuFallback("my_cublasDgemm:hipMemcpy(B)", cuda_status, m, n, k);
        goto cpu_fallback;
    }

    status = OpenMX_DgemmTryGpu(handle, transa, transb, m, n, k, d_A, d_B, d_C, "my_cublasDgemm");
    if (status != CUBLAS_STATUS_SUCCESS) {
        OpenMX_DgemmLogCpuFallback("my_cublasDgemm", "native hipBLAS", status, m, n, k);
        goto cpu_fallback;
    }

    cuda_status = cudaMemcpy(C, d_C, m * n * sizeof(double), cudaMemcpyDeviceToHost);
    if (cuda_status != cudaSuccess) {
        OpenMX_DgemmLogCudaCpuFallback("my_cublasDgemm:hipMemcpy(C)", cuda_status, m, n, k);
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
    OpenMX_DgemmCpu(transa, transb, m, n, k, A, B, C);
}

void my_cublasDgemm_openacc(cublasOperation_t transa, cublasOperation_t transb, int m, int n, int k, double const * A,
                            double const * B, double * C)
{
    cublasHandle_t handle = NULL;
    cublasStatus_t status;

    status = cublasCreate(&handle);

#pragma acc data      present(A[0 : m * k], B[0 : k * n], C[0 : m * n])
    {
    if (status == CUBLAS_STATUS_SUCCESS) {
#pragma acc host_data use_device(A, B, C)
        {
            status = OpenMX_DgemmTryGpu(handle, transa, transb, m, n, k, A, B, C, "my_cublasDgemm_openacc");
        }
    }

    if (handle != NULL) {
        cublasStatus_t destroy_status = cublasDestroy(handle);
        if (destroy_status != CUBLAS_STATUS_SUCCESS) {
            fprintf(stderr, "<GEMM> rank %d: hipblasDestroy failed after DGEMM: %s (%d).\n", OpenMX_DgemmRank(),
                    OpenMX_DgemmCublasStatusName(destroy_status), (int)destroy_status);
            fflush(stderr);
        }
    }

    if (status != CUBLAS_STATUS_SUCCESS) {
        OpenMX_DgemmLogCpuFallback("my_cublasDgemm_openacc", "native hipBLAS", status, m, n, k);
#pragma acc update self(A[0 : m * k], B[0 : k * n])
        OpenMX_DgemmCpu(transa, transb, m, n, k, A, B, C);
#pragma acc update device(C[0 : m * n])
    }
    }
}
