#include <hip/hip_runtime.h>
#include <stddef.h>
#include <stdio.h>

static double ClusterCol_hip_dense_build_kernel_time = 0.0;
static double ClusterCol_hip_dm_kernel_time = 0.0;

extern "C" void ClusterCol_HIPDetailTimer_Reset(void)
{
    ClusterCol_hip_dense_build_kernel_time = 0.0;
    ClusterCol_hip_dm_kernel_time = 0.0;
}

extern "C" void ClusterCol_HIPDetailTimer_Get(double *dense_build_kernel, double *dm_kernel)
{
    if (dense_build_kernel != NULL) {
        *dense_build_kernel = ClusterCol_hip_dense_build_kernel_time;
    }
    if (dm_kernel != NULL) {
        *dm_kernel = ClusterCol_hip_dm_kernel_time;
    }
}

static int ClusterColDMReportHipError(const char *where, hipError_t err)
{
    if (err == hipSuccess) {
        return 0;
    }

    fprintf(stderr, "<Cluster> rank 0: HIP collinear density-matrix GPU path failed at %s: %s (%d).\n",
            where, hipGetErrorString(err), (int)err);
    fflush(stderr);
    return 1;
}

__global__ static void ClusterColDenseBuildKernel(int tnum, const double *H1, const int *dense_index, double *d_H)
{
    int p = (int)(blockIdx.x * blockDim.x + threadIdx.x);

    if (p < tnum) {
        atomicAdd(&d_H[dense_index[p]], H1[p]);
    }
}

extern "C" int ClusterCol_BuildDeviceDenseFromPacked_HIP(const double *H1, const int *dense_index,
                                                         int tnum, int n, double *d_H)
{
    const int block_size = 256;
    dim3 block(block_size);
    dim3 grid((unsigned int)((tnum + block_size - 1) / block_size));
    double *d_H1 = NULL;
    int *d_dense_index = NULL;
    hipError_t err;
    size_t sparse_bytes = sizeof(double) * (size_t)tnum;
    size_t index_bytes = sizeof(int) * (size_t)tnum;
    size_t dense_bytes = sizeof(double) * (size_t)n * (size_t)n;
    int failed = 0;
    hipEvent_t ev_start = NULL;
    hipEvent_t ev_stop = NULL;
    float kernel_ms = 0.0f;

    if (d_H == NULL) {
        fprintf(stderr, "<Cluster> rank 0: HIP dense matrix build received a NULL device matrix.\n");
        fflush(stderr);
        return 1;
    }

    err = hipMalloc((void **)&d_H1, sparse_bytes);
    if (ClusterColDMReportHipError("hipMalloc(dense H1)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_dense_index, index_bytes);
    if (ClusterColDMReportHipError("hipMalloc(dense index)", err)) goto cleanup_failed;

    err = hipMemcpy(d_H1, H1, sparse_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(dense H1)", err)) goto cleanup_failed;
    err = hipMemcpy(d_dense_index, dense_index, index_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(dense index)", err)) goto cleanup_failed;

    err = hipMemset(d_H, 0, dense_bytes);
    if (ClusterColDMReportHipError("hipMemset(dense matrix)", err)) goto cleanup_failed;

    err = hipEventCreate(&ev_start);
    if (ClusterColDMReportHipError("hipEventCreate(dense start)", err)) goto cleanup_failed;
    err = hipEventCreate(&ev_stop);
    if (ClusterColDMReportHipError("hipEventCreate(dense stop)", err)) goto cleanup_failed;
    err = hipEventRecord(ev_start, 0);
    if (ClusterColDMReportHipError("hipEventRecord(dense start)", err)) goto cleanup_failed;

    hipLaunchKernelGGL(ClusterColDenseBuildKernel, grid, block, 0, 0, tnum, d_H1, d_dense_index, d_H);
    err = hipGetLastError();
    if (ClusterColDMReportHipError("ClusterColDenseBuildKernel launch", err)) goto cleanup_failed;
    err = hipEventRecord(ev_stop, 0);
    if (ClusterColDMReportHipError("hipEventRecord(dense stop)", err)) goto cleanup_failed;
    err = hipEventSynchronize(ev_stop);
    if (ClusterColDMReportHipError("hipEventSynchronize(dense stop)", err)) goto cleanup_failed;
    err = hipEventElapsedTime(&kernel_ms, ev_start, ev_stop);
    if (ClusterColDMReportHipError("hipEventElapsedTime(dense)", err)) goto cleanup_failed;
    ClusterCol_hip_dense_build_kernel_time += (double)kernel_ms * 1.0e-3;
    err = hipDeviceSynchronize();
    if (ClusterColDMReportHipError("ClusterColDenseBuildKernel synchronize", err)) goto cleanup_failed;

    goto cleanup;

cleanup_failed:
    failed = 1;

cleanup:
    if (ev_stop != NULL) hipEventDestroy(ev_stop);
    if (ev_start != NULL) hipEventDestroy(ev_start);
    if (d_dense_index != NULL) hipFree(d_dense_index);
    if (d_H1 != NULL) hipFree(d_H1);
    return failed;
}

__device__ static double ClusterColWarpReduceSum(double value)
{
    for (int offset = warpSize / 2; 0 < offset; offset >>= 1) {
        value += __shfl_down(value, offset, warpSize);
    }
    return value;
}

__global__ static void ClusterColDMKernel(int entry_count, int size_H1, int maxn, int nk_occ, int calc_pdm,
                                          const int *basis0, const int *basis1,
                                          const double *occ, const double *occ_e, const double *pocc,
                                          const double *dense_evec, double *dm_buffer)
{
    const int warps_per_block = blockDim.x / warpSize;
    const int warp_in_block = threadIdx.x / warpSize;
    const int lane = threadIdx.x - warp_in_block * warpSize;
    const int p = (int)(blockIdx.x * warps_per_block + warp_in_block);

    if (entry_count <= p) {
        return;
    }

    const int ia = basis0[p];
    const int ib = basis1[p];
    double dm = 0.0;
    double edm = 0.0;
    double pdm = 0.0;

    for (int k = lane; k < nk_occ; k += warpSize) {
        const double prod = dense_evec[(size_t)ia * (size_t)maxn + (size_t)k] *
                            dense_evec[(size_t)ib * (size_t)maxn + (size_t)k];

        dm  += occ[k] * prod;
        edm += occ_e[k] * prod;
        if (calc_pdm) {
            pdm += pocc[k] * prod;
        }
    }

    dm = ClusterColWarpReduceSum(dm);
    edm = ClusterColWarpReduceSum(edm);
    if (calc_pdm) {
        pdm = ClusterColWarpReduceSum(pdm);
    }

    if (lane == 0) {
        dm_buffer[(size_t)p] = dm;
        dm_buffer[(size_t)size_H1 + (size_t)p] = edm;
        if (calc_pdm) {
            dm_buffer[(size_t)size_H1 * 2u + (size_t)p] = pdm;
        }
    }
}

extern "C" int ClusterCol_CalcDMRootDense_HIP(int entry_count, int size_H1, int n, int maxn, int nk_occ, int calc_pdm,
                                              const int *basis0, const int *basis1,
                                              const double *occ, const double *occ_e, const double *pocc,
                                              const double *dense_evec, double *dm_buffer)
{
    const int dm_components = calc_pdm ? 3 : 2;
    const int block_size = 256;
    int device_id = 0;
    hipDeviceProp_t prop;
    int warp_size = 64;
    int entries_per_block;
    dim3 block(block_size);
    dim3 grid;
    int *d_basis0 = NULL;
    int *d_basis1 = NULL;
    double *d_occ = NULL;
    double *d_occ_e = NULL;
    double *d_pocc = NULL;
    double *d_dense_evec = NULL;
    double *d_dm_buffer = NULL;
    hipError_t err;
    size_t basis_bytes = sizeof(int) * (size_t)entry_count;
    size_t occ_bytes = sizeof(double) * (size_t)nk_occ;
    size_t evec_bytes = sizeof(double) * (size_t)n * (size_t)maxn;
    size_t dm_bytes = sizeof(double) * (size_t)size_H1 * (size_t)dm_components;
    int failed = 0;
    hipEvent_t ev_start = NULL;
    hipEvent_t ev_stop = NULL;
    float kernel_ms = 0.0f;

    err = hipGetDevice(&device_id);
    if (ClusterColDMReportHipError("hipGetDevice", err)) goto cleanup_failed;
    err = hipGetDeviceProperties(&prop, device_id);
    if (ClusterColDMReportHipError("hipGetDeviceProperties", err)) goto cleanup_failed;
    if (0 < prop.warpSize) {
        warp_size = prop.warpSize;
    }
    entries_per_block = block_size / warp_size;
    if (entries_per_block <= 0) {
        entries_per_block = 1;
    }
    grid = dim3((unsigned int)((entry_count + entries_per_block - 1) / entries_per_block));

    err = hipMalloc((void **)&d_basis0, basis_bytes);
    if (ClusterColDMReportHipError("hipMalloc(basis0)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_basis1, basis_bytes);
    if (ClusterColDMReportHipError("hipMalloc(basis1)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_occ, occ_bytes);
    if (ClusterColDMReportHipError("hipMalloc(occ)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_occ_e, occ_bytes);
    if (ClusterColDMReportHipError("hipMalloc(occ_e)", err)) goto cleanup_failed;
    if (calc_pdm) {
        err = hipMalloc((void **)&d_pocc, occ_bytes);
        if (ClusterColDMReportHipError("hipMalloc(pocc)", err)) goto cleanup_failed;
    }
    err = hipMalloc((void **)&d_dense_evec, evec_bytes);
    if (ClusterColDMReportHipError("hipMalloc(dense_evec)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_dm_buffer, dm_bytes);
    if (ClusterColDMReportHipError("hipMalloc(dm_buffer)", err)) goto cleanup_failed;

    err = hipMemcpy(d_basis0, basis0, basis_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(basis0)", err)) goto cleanup_failed;
    err = hipMemcpy(d_basis1, basis1, basis_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(basis1)", err)) goto cleanup_failed;
    err = hipMemcpy(d_occ, occ, occ_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(occ)", err)) goto cleanup_failed;
    err = hipMemcpy(d_occ_e, occ_e, occ_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(occ_e)", err)) goto cleanup_failed;
    if (calc_pdm) {
        err = hipMemcpy(d_pocc, pocc, occ_bytes, hipMemcpyHostToDevice);
        if (ClusterColDMReportHipError("hipMemcpy(pocc)", err)) goto cleanup_failed;
    }
    err = hipMemcpy(d_dense_evec, dense_evec, evec_bytes, hipMemcpyHostToDevice);
    if (ClusterColDMReportHipError("hipMemcpy(dense_evec)", err)) goto cleanup_failed;

    err = hipEventCreate(&ev_start);
    if (ClusterColDMReportHipError("hipEventCreate(DM start)", err)) goto cleanup_failed;
    err = hipEventCreate(&ev_stop);
    if (ClusterColDMReportHipError("hipEventCreate(DM stop)", err)) goto cleanup_failed;
    err = hipEventRecord(ev_start, 0);
    if (ClusterColDMReportHipError("hipEventRecord(DM start)", err)) goto cleanup_failed;

    hipLaunchKernelGGL(ClusterColDMKernel, grid, block, 0, 0,
                       entry_count, size_H1, maxn, nk_occ, calc_pdm,
                       d_basis0, d_basis1, d_occ, d_occ_e, d_pocc,
                       d_dense_evec, d_dm_buffer);
    err = hipGetLastError();
    if (ClusterColDMReportHipError("ClusterColDMKernel launch", err)) goto cleanup_failed;
    err = hipEventRecord(ev_stop, 0);
    if (ClusterColDMReportHipError("hipEventRecord(DM stop)", err)) goto cleanup_failed;
    err = hipEventSynchronize(ev_stop);
    if (ClusterColDMReportHipError("hipEventSynchronize(DM stop)", err)) goto cleanup_failed;
    err = hipEventElapsedTime(&kernel_ms, ev_start, ev_stop);
    if (ClusterColDMReportHipError("hipEventElapsedTime(DM)", err)) goto cleanup_failed;
    ClusterCol_hip_dm_kernel_time += (double)kernel_ms * 1.0e-3;
    err = hipDeviceSynchronize();
    if (ClusterColDMReportHipError("ClusterColDMKernel synchronize", err)) goto cleanup_failed;

    err = hipMemcpy(dm_buffer, d_dm_buffer, dm_bytes, hipMemcpyDeviceToHost);
    if (ClusterColDMReportHipError("hipMemcpy(dm_buffer)", err)) goto cleanup_failed;

    goto cleanup;

cleanup_failed:
    failed = 1;

cleanup:
    if (ev_stop != NULL) hipEventDestroy(ev_stop);
    if (ev_start != NULL) hipEventDestroy(ev_start);
    if (d_dm_buffer != NULL) hipFree(d_dm_buffer);
    if (d_dense_evec != NULL) hipFree(d_dense_evec);
    if (d_pocc != NULL) hipFree(d_pocc);
    if (d_occ_e != NULL) hipFree(d_occ_e);
    if (d_occ != NULL) hipFree(d_occ);
    if (d_basis1 != NULL) hipFree(d_basis1);
    if (d_basis0 != NULL) hipFree(d_basis0);
    return failed;
}
