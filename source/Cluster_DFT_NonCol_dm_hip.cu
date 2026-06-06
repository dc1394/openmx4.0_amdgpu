#include <hip/hip_runtime.h>
#include <stddef.h>
#include <stdio.h>

typedef struct {
    double r;
    double i;
} dcomplex;

static int ClusterNonColDMReportHipError(const char *where, hipError_t err)
{
    if (err == hipSuccess) {
        return 0;
    }

    fprintf(stderr, "<Cluster> rank 0: HIP density-matrix GPU path failed at %s: %s (%d).\n",
            where, hipGetErrorString(err), (int)err);
    fflush(stderr);
    return 1;
}

__device__ static double ClusterNonColWarpReduceSum(double value)
{
    for (int offset = warpSize / 2; 0 < offset; offset >>= 1) {
        value += __shfl_down(value, offset, warpSize);
    }
    return value;
}

__global__ static void ClusterNonColDMKernel(int entry_count, int size_H1, int n, int n2, int nk_occ,
                                             int calc_edm, const int *basis0, const int *basis1,
                                             const double *occ, const double *occ_e,
                                             const dcomplex *dense_evec, double *dm_buffer)
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
    double dm11_r = 0.0;
    double dm22_r = 0.0;
    double dm12_r = 0.0;
    double dm12_i = 0.0;
    double dm11_i = 0.0;
    double dm22_i = 0.0;
    double edm11_r = 0.0;
    double edm22_r = 0.0;
    double edm12_r = 0.0;
    double edm12_i = 0.0;

    for (int k = lane; k < nk_occ; k += warpSize) {
        const double w = occ[k];
        const dcomplex va_up = dense_evec[(size_t)ia * (size_t)n2 + (size_t)k];
        const dcomplex vb_up = dense_evec[(size_t)ib * (size_t)n2 + (size_t)k];
        const dcomplex va_dn = dense_evec[(size_t)(ia + n) * (size_t)n2 + (size_t)k];
        const dcomplex vb_dn = dense_evec[(size_t)(ib + n) * (size_t)n2 + (size_t)k];
        const double re11 = va_up.r * vb_up.r + va_up.i * vb_up.i;
        const double im11 = va_up.r * vb_up.i - va_up.i * vb_up.r;
        const double re22 = va_dn.r * vb_dn.r + va_dn.i * vb_dn.i;
        const double im22 = va_dn.r * vb_dn.i - va_dn.i * vb_dn.r;
        const double re12 = va_up.r * vb_dn.r + va_up.i * vb_dn.i;
        const double im12 = va_up.r * vb_dn.i - va_up.i * vb_dn.r;

        dm11_r += w * re11;
        dm22_r += w * re22;
        dm12_r += w * re12;
        dm12_i += w * im12;
        dm11_i += w * im11;
        dm22_i += w * im22;

        if (calc_edm) {
            const double ew = occ_e[k];
            edm11_r += ew * re11;
            edm22_r += ew * re22;
            edm12_r += ew * re12;
            edm12_i += ew * im12;
        }
    }

    dm11_r = ClusterNonColWarpReduceSum(dm11_r);
    dm22_r = ClusterNonColWarpReduceSum(dm22_r);
    dm12_r = ClusterNonColWarpReduceSum(dm12_r);
    dm12_i = ClusterNonColWarpReduceSum(dm12_i);
    dm11_i = ClusterNonColWarpReduceSum(dm11_i);
    dm22_i = ClusterNonColWarpReduceSum(dm22_i);
    if (calc_edm) {
        edm11_r = ClusterNonColWarpReduceSum(edm11_r);
        edm22_r = ClusterNonColWarpReduceSum(edm22_r);
        edm12_r = ClusterNonColWarpReduceSum(edm12_r);
        edm12_i = ClusterNonColWarpReduceSum(edm12_i);
    }

    if (lane == 0) {
        dm_buffer[(size_t)size_H1 * 0u + (size_t)p] = dm11_r;
        dm_buffer[(size_t)size_H1 * 1u + (size_t)p] = dm22_r;
        dm_buffer[(size_t)size_H1 * 2u + (size_t)p] = dm12_r;
        dm_buffer[(size_t)size_H1 * 3u + (size_t)p] = dm12_i;
        dm_buffer[(size_t)size_H1 * 4u + (size_t)p] = dm11_i;
        dm_buffer[(size_t)size_H1 * 5u + (size_t)p] = dm22_i;

        if (calc_edm) {
            dm_buffer[(size_t)size_H1 * 6u + (size_t)p] = edm11_r;
            dm_buffer[(size_t)size_H1 * 7u + (size_t)p] = edm22_r;
            dm_buffer[(size_t)size_H1 * 8u + (size_t)p] = edm12_r;
            dm_buffer[(size_t)size_H1 * 9u + (size_t)p] = edm12_i;
        }
    }
}

extern "C" int ClusterNonCol_CalcDMRootDense_HIP(int entry_count, int size_H1, int n, int n2, int nk_occ,
                                                 int calc_edm, const int *basis0, const int *basis1,
                                                 const double *occ, const double *occ_e,
                                                 const dcomplex *dense_evec, double *dm_buffer)
{
    const int dm_components = calc_edm ? 10 : 6;
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
    dcomplex *d_dense_evec = NULL;
    double *d_dm_buffer = NULL;
    hipError_t err;
    size_t basis_bytes = sizeof(int) * (size_t)entry_count;
    size_t occ_bytes = sizeof(double) * (size_t)nk_occ;
    size_t evec_bytes = sizeof(dcomplex) * (size_t)n2 * (size_t)n2;
    size_t dm_bytes = sizeof(double) * (size_t)size_H1 * (size_t)dm_components;
    int failed = 0;

    err = hipGetDevice(&device_id);
    if (ClusterNonColDMReportHipError("hipGetDevice", err)) goto cleanup_failed;
    err = hipGetDeviceProperties(&prop, device_id);
    if (ClusterNonColDMReportHipError("hipGetDeviceProperties", err)) goto cleanup_failed;
    if (0 < prop.warpSize) {
        warp_size = prop.warpSize;
    }
    entries_per_block = block_size / warp_size;
    if (entries_per_block <= 0) {
        entries_per_block = 1;
    }
    grid = dim3((unsigned int)((entry_count + entries_per_block - 1) / entries_per_block));

    err = hipMalloc((void **)&d_basis0, basis_bytes);
    if (ClusterNonColDMReportHipError("hipMalloc(basis0)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_basis1, basis_bytes);
    if (ClusterNonColDMReportHipError("hipMalloc(basis1)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_occ, occ_bytes);
    if (ClusterNonColDMReportHipError("hipMalloc(occ)", err)) goto cleanup_failed;
    if (calc_edm) {
        err = hipMalloc((void **)&d_occ_e, occ_bytes);
        if (ClusterNonColDMReportHipError("hipMalloc(occ_e)", err)) goto cleanup_failed;
    }
    err = hipMalloc((void **)&d_dense_evec, evec_bytes);
    if (ClusterNonColDMReportHipError("hipMalloc(dense_evec)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_dm_buffer, dm_bytes);
    if (ClusterNonColDMReportHipError("hipMalloc(dm_buffer)", err)) goto cleanup_failed;

    err = hipMemcpy(d_basis0, basis0, basis_bytes, hipMemcpyHostToDevice);
    if (ClusterNonColDMReportHipError("hipMemcpy(basis0)", err)) goto cleanup_failed;
    err = hipMemcpy(d_basis1, basis1, basis_bytes, hipMemcpyHostToDevice);
    if (ClusterNonColDMReportHipError("hipMemcpy(basis1)", err)) goto cleanup_failed;
    err = hipMemcpy(d_occ, occ, occ_bytes, hipMemcpyHostToDevice);
    if (ClusterNonColDMReportHipError("hipMemcpy(occ)", err)) goto cleanup_failed;
    if (calc_edm) {
        err = hipMemcpy(d_occ_e, occ_e, occ_bytes, hipMemcpyHostToDevice);
        if (ClusterNonColDMReportHipError("hipMemcpy(occ_e)", err)) goto cleanup_failed;
    }
    err = hipMemcpy(d_dense_evec, dense_evec, evec_bytes, hipMemcpyHostToDevice);
    if (ClusterNonColDMReportHipError("hipMemcpy(dense_evec)", err)) goto cleanup_failed;

    hipLaunchKernelGGL(ClusterNonColDMKernel, grid, block, 0, 0,
                       entry_count, size_H1, n, n2, nk_occ, calc_edm,
                       d_basis0, d_basis1, d_occ, d_occ_e, d_dense_evec, d_dm_buffer);
    err = hipGetLastError();
    if (ClusterNonColDMReportHipError("ClusterNonColDMKernel launch", err)) goto cleanup_failed;
    err = hipDeviceSynchronize();
    if (ClusterNonColDMReportHipError("ClusterNonColDMKernel synchronize", err)) goto cleanup_failed;

    err = hipMemcpy(dm_buffer, d_dm_buffer, dm_bytes, hipMemcpyDeviceToHost);
    if (ClusterNonColDMReportHipError("hipMemcpy(dm_buffer)", err)) goto cleanup_failed;

    goto cleanup;

cleanup_failed:
    failed = 1;

cleanup:
    if (d_dm_buffer != NULL) hipFree(d_dm_buffer);
    if (d_dense_evec != NULL) hipFree(d_dense_evec);
    if (d_occ_e != NULL) hipFree(d_occ_e);
    if (d_occ != NULL) hipFree(d_occ);
    if (d_basis1 != NULL) hipFree(d_basis1);
    if (d_basis0 != NULL) hipFree(d_basis0);
    return failed;
}
