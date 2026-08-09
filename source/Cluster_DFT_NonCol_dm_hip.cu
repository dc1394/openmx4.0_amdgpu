#include <hip/hip_runtime.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static int BandNonColReportHipError(const char *where, hipError_t err)
{
    if (err == hipSuccess) {
        return 0;
    }

    fprintf(stderr, "<Band> HIP non-collinear GPU path failed at %s: %s (%d).\n",
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
        const dcomplex va_up = dense_evec[(size_t)ia * (size_t)nk_occ + (size_t)k];
        const dcomplex vb_up = dense_evec[(size_t)ib * (size_t)nk_occ + (size_t)k];
        const dcomplex va_dn = dense_evec[(size_t)(ia + n) * (size_t)nk_occ + (size_t)k];
        const dcomplex vb_dn = dense_evec[(size_t)(ib + n) * (size_t)nk_occ + (size_t)k];
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
    size_t evec_bytes = sizeof(dcomplex) * (size_t)n2 * (size_t)nk_occ;
    size_t evec_dst_pitch = sizeof(dcomplex) * (size_t)nk_occ;
    size_t evec_src_pitch = sizeof(dcomplex) * (size_t)n2;
    size_t evec_width = sizeof(dcomplex) * (size_t)nk_occ;
    size_t evec_height = (size_t)n2;
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
    err = hipMemcpy2D(d_dense_evec, evec_dst_pitch, dense_evec, evec_src_pitch,
                      evec_width, evec_height, hipMemcpyHostToDevice);
    if (ClusterNonColDMReportHipError("hipMemcpy2D(dense_evec)", err)) goto cleanup_failed;

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

typedef struct
{
    int m_index;
    int dense_index;
    int phase_index;
} BandNonColHipConstructEntry;

__global__ static void BandNonColDenseMsKernel(int cpx_flag, int count,
                                               const BandNonColHipConstructEntry *entries,
                                               const double *M1, const double *phase_r,
                                               const double *phase_i, dcomplex *d_M)
{
    int idx = (int)(blockIdx.x * blockDim.x + threadIdx.x);

    if (idx < count) {
        const BandNonColHipConstructEntry entry = entries[idx];
        const double pr = phase_r[entry.phase_index];
        const double pi = phase_i[entry.phase_index];
        const double value = M1[entry.m_index];
        double vr;
        double vi;

        if (cpx_flag == 0) {
            vr = value * pr;
            vi = value * pi;
        } else {
            vr = -value * pi;
            vi =  value * pr;
        }

        atomicAdd(&d_M[entry.dense_index].r, vr);
        atomicAdd(&d_M[entry.dense_index].i, vi);
    }
}

extern "C" int BandNonCol_BuildDenseMs_HIP(int cpx_flag, int count, int h_count, int phase_count, int n,
                                           const BandNonColHipConstructEntry *entries,
                                           const double *phase_r, const double *phase_i,
                                           const double *M1, dcomplex *d_M)
{
    const int block_size = 256;
    dim3 block(block_size);
    BandNonColHipConstructEntry *d_entries = NULL;
    double *d_M1 = NULL;
    double *d_phase_r = NULL;
    double *d_phase_i = NULL;
    hipError_t err;
    const int entry_chunk = 262144;
    int alloc_entries = count < entry_chunk ? count : entry_chunk;
    size_t entry_bytes = sizeof(BandNonColHipConstructEntry) * (size_t)alloc_entries;
    size_t h_bytes = sizeof(double) * (size_t)h_count;
    size_t phase_bytes = sizeof(double) * (size_t)phase_count;
    size_t dense_bytes = sizeof(dcomplex) * (size_t)n * (size_t)n;
    int failed = 0;

    if (count < 0 || h_count <= 0 || phase_count <= 0 || n <= 0 ||
        entries == NULL || phase_r == NULL || phase_i == NULL || M1 == NULL || d_M == NULL) {
        fprintf(stderr, "<Band> HIP non-collinear dense matrix build received invalid arguments.\n");
        fflush(stderr);
        return 1;
    }

    if (0 < count) {
        err = hipMalloc((void **)&d_entries, entry_bytes);
        if (BandNonColReportHipError("hipMalloc(dense entries)", err)) goto cleanup_failed;
    }
    err = hipMalloc((void **)&d_M1, h_bytes);
    if (BandNonColReportHipError("hipMalloc(dense M1)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_phase_r, phase_bytes);
    if (BandNonColReportHipError("hipMalloc(dense phase_r)", err)) goto cleanup_failed;
    err = hipMalloc((void **)&d_phase_i, phase_bytes);
    if (BandNonColReportHipError("hipMalloc(dense phase_i)", err)) goto cleanup_failed;

    err = hipMemcpy(d_M1, M1, h_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(dense M1)", err)) goto cleanup_failed;
    err = hipMemcpy(d_phase_r, phase_r, phase_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(dense phase_r)", err)) goto cleanup_failed;
    err = hipMemcpy(d_phase_i, phase_i, phase_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(dense phase_i)", err)) goto cleanup_failed;
    err = hipMemset(d_M, 0, dense_bytes);
    if (BandNonColReportHipError("hipMemset(dense matrix)", err)) goto cleanup_failed;

    for (int offset = 0; offset < count; offset += entry_chunk) {
        int chunk_count = count - offset;
        size_t chunk_bytes;
        dim3 grid;

        if (entry_chunk < chunk_count) {
            chunk_count = entry_chunk;
        }
        chunk_bytes = sizeof(BandNonColHipConstructEntry) * (size_t)chunk_count;
        grid = dim3((unsigned int)((chunk_count + block_size - 1) / block_size));

        err = hipMemcpy(d_entries, entries + offset, chunk_bytes, hipMemcpyHostToDevice);
        if (BandNonColReportHipError("hipMemcpy(dense entries)", err)) goto cleanup_failed;

        hipLaunchKernelGGL(BandNonColDenseMsKernel, grid, block, 0, 0,
                           cpx_flag, chunk_count, d_entries, d_M1, d_phase_r, d_phase_i, d_M);
        err = hipGetLastError();
        if (BandNonColReportHipError("BandNonColDenseMsKernel launch", err)) goto cleanup_failed;
        err = hipDeviceSynchronize();
        if (BandNonColReportHipError("BandNonColDenseMsKernel synchronize", err)) goto cleanup_failed;
    }

    goto cleanup;

cleanup_failed:
    failed = 1;

cleanup:
    if (d_phase_i != NULL) hipFree(d_phase_i);
    if (d_phase_r != NULL) hipFree(d_phase_r);
    if (d_M1 != NULL) hipFree(d_M1);
    if (d_entries != NULL) hipFree(d_entries);
    return failed;
}

__global__ static void BandNonColAddDenseKernel(int count, dcomplex *dst, const dcomplex *src)
{
    int idx = (int)(blockIdx.x * blockDim.x + threadIdx.x);
    if (idx < count) {
        dst[idx].r += src[idx].r;
        dst[idx].i += src[idx].i;
    }
}

extern "C" int BandNonCol_AddDense_HIP(int count, dcomplex *d_dst, const dcomplex *d_src)
{
    const int block_size = 256;
    dim3 block(block_size);
    dim3 grid((unsigned int)((count + block_size - 1) / block_size));
    hipError_t err;

    if (count < 0 || d_dst == NULL || d_src == NULL) {
        fprintf(stderr, "<Band> HIP non-collinear dense add received invalid arguments.\n");
        fflush(stderr);
        return 1;
    }
    if (count == 0) {
        return 0;
    }

    hipLaunchKernelGGL(BandNonColAddDenseKernel, grid, block, 0, 0, count, d_dst, d_src);
    err = hipGetLastError();
    if (BandNonColReportHipError("BandNonColAddDenseKernel launch", err)) return 1;
    err = hipDeviceSynchronize();
    if (BandNonColReportHipError("BandNonColAddDenseKernel synchronize", err)) return 1;
    return 0;
}

__global__ static void BandNonColSymmetrizeHermitianKernel(int n, dcomplex *A)
{
    int idx = (int)(blockIdx.x * blockDim.x + threadIdx.x);
    int nn = n * n;

    if (idx < nn) {
        int j = idx / n;
        int i = idx - j * n;

        if (i == j) {
            A[(size_t)i + (size_t)j * (size_t)n].i = 0.0;
        } else if (j < i) {
            size_t lij = (size_t)i + (size_t)j * (size_t)n;
            size_t uji = (size_t)j + (size_t)i * (size_t)n;
            double ar = 0.5 * (A[lij].r + A[uji].r);
            double ai = 0.5 * (A[lij].i - A[uji].i);
            A[lij].r = ar;
            A[lij].i = ai;
            A[uji].r =  ar;
            A[uji].i = -ai;
        }
    }
}

extern "C" int BandNonCol_SymmetrizeDenseHermitian_HIP(int n, dcomplex *d_A)
{
    const int block_size = 256;
    int count = n * n;
    dim3 block(block_size);
    dim3 grid((unsigned int)((count + block_size - 1) / block_size));
    hipError_t err;

    if (n <= 0 || d_A == NULL) {
        fprintf(stderr, "<Band> HIP non-collinear symmetrization received invalid arguments.\n");
        fflush(stderr);
        return 1;
    }

    hipLaunchKernelGGL(BandNonColSymmetrizeHermitianKernel, grid, block, 0, 0, n, d_A);
    err = hipGetLastError();
    if (BandNonColReportHipError("BandNonColSymmetrizeHermitianKernel launch", err)) return 1;
    err = hipDeviceSynchronize();
    if (BandNonColReportHipError("BandNonColSymmetrizeHermitianKernel synchronize", err)) return 1;
    return 0;
}

__global__ static void BandNonColBuildHs2Kernel(int n, int n2, const dcomplex *H11,
                                                const dcomplex *H22, const dcomplex *H12,
                                                dcomplex *H2)
{
    int idx = (int)(blockIdx.x * blockDim.x + threadIdx.x);
    int n2n2 = n2 * n2;

    if (idx < n2n2) {
        int j = idx / n2;
        int i = idx - j * n2;
        size_t idx2 = (size_t)i + (size_t)j * (size_t)n2;

        if (i < n && j < n) {
            size_t src = (size_t)i + (size_t)j * (size_t)n;
            H2[idx2] = H11[src];
        } else if (i < n && n <= j) {
            int jj = j - n;
            size_t src = (size_t)i + (size_t)jj * (size_t)n;
            H2[idx2] = H12[src];
        } else if (n <= i && j < n) {
            int ii = i - n;
            size_t src = (size_t)j + (size_t)ii * (size_t)n;
            H2[idx2].r =  H12[src].r;
            H2[idx2].i = -H12[src].i;
        } else {
            int ii = i - n;
            int jj = j - n;
            size_t src = (size_t)ii + (size_t)jj * (size_t)n;
            H2[idx2] = H22[src];
        }
    }
}

extern "C" int BandNonCol_BuildDenseHs2_HIP(int n, int n2, const dcomplex *d_H11,
                                            const dcomplex *d_H22, const dcomplex *d_H12,
                                            dcomplex *d_H2)
{
    const int block_size = 256;
    int count = n2 * n2;
    dim3 block(block_size);
    dim3 grid((unsigned int)((count + block_size - 1) / block_size));
    hipError_t err;

    if (n <= 0 || n2 <= 0 || d_H11 == NULL || d_H22 == NULL || d_H12 == NULL || d_H2 == NULL) {
        fprintf(stderr, "<Band> HIP non-collinear Hs2 build received invalid arguments.\n");
        fflush(stderr);
        return 1;
    }

    hipLaunchKernelGGL(BandNonColBuildHs2Kernel, grid, block, 0, 0, n, n2, d_H11, d_H22, d_H12, d_H2);
    err = hipGetLastError();
    if (BandNonColReportHipError("BandNonColBuildHs2Kernel launch", err)) return 1;
    err = hipDeviceSynchronize();
    if (BandNonColReportHipError("BandNonColBuildHs2Kernel synchronize", err)) return 1;
    return 0;
}

__global__ static void BandNonColBuildSs2Kernel(int n, int n2, const dcomplex *S, dcomplex *S2)
{
    int idx = (int)(blockIdx.x * blockDim.x + threadIdx.x);
    int n2n2 = n2 * n2;

    if (idx < n2n2) {
        int i = idx / n2;
        int j = idx - i * n2;
        int idx2 = n2 * i + j;

        if (i < n && j < n) {
            int src = n * i + j;
            S2[idx2] = S[src];
        } else if (n <= i && n <= j) {
            int src = n * (i - n) + (j - n);
            S2[idx2] = S[src];
        } else {
            S2[idx2].r = 0.0;
            S2[idx2].i = 0.0;
        }
    }
}

extern "C" int BandNonCol_BuildDenseSs2_HIP(int n, int n2, const dcomplex *d_S, dcomplex *d_S2)
{
    const int block_size = 256;
    int count = n2 * n2;
    dim3 block(block_size);
    dim3 grid((unsigned int)((count + block_size - 1) / block_size));
    hipError_t err;

    if (n <= 0 || n2 <= 0 || d_S == NULL || d_S2 == NULL) {
        fprintf(stderr, "<Band> HIP non-collinear Ss2 build received invalid arguments.\n");
        fflush(stderr);
        return 1;
    }

    hipLaunchKernelGGL(BandNonColBuildSs2Kernel, grid, block, 0, 0, n, n2, d_S, d_S2);
    err = hipGetLastError();
    if (BandNonColReportHipError("BandNonColBuildSs2Kernel launch", err)) return 1;
    err = hipDeviceSynchronize();
    if (BandNonColReportHipError("BandNonColBuildSs2Kernel synchronize", err)) return 1;
    return 0;
}

__global__ static void BandNonColDMRootDenseKernel(int entry_count, int n, int n2, int nk_occ,
                                                   int dense_evec_ld,
                                                   const int *basis0, const int *basis1,
                                                   const int *phase_index,
                                                   const double *phase_r, const double *phase_i,
                                                   const double *occ, const double *eig_occ,
                                                   const dcomplex *dense_evec, double *dm_buffer,
                                                   int size_H1)
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
    const int ph = phase_index[p];
    const double co = phase_r[ph];
    const double si = phase_i[ph];
    double dm11_r = 0.0;
    double dm11_i = 0.0;
    double dm22_r = 0.0;
    double dm22_i = 0.0;
    double dm12_r = 0.0;
    double dm12_i = 0.0;
    double edm11_r = 0.0;
    double edm11_i = 0.0;
    double edm22_r = 0.0;
    double edm22_i = 0.0;

    for (int k = lane; k < nk_occ; k += warpSize) {
        const double w = occ[k];
        const double ew = eig_occ[k];
        const dcomplex va_up = dense_evec[(size_t)ia * (size_t)dense_evec_ld + (size_t)k];
        const dcomplex vb_up = dense_evec[(size_t)ib * (size_t)dense_evec_ld + (size_t)k];
        const dcomplex va_dn = dense_evec[(size_t)(ia + n) * (size_t)dense_evec_ld + (size_t)k];
        const dcomplex vb_dn = dense_evec[(size_t)(ib + n) * (size_t)dense_evec_ld + (size_t)k];
        const double re11 = va_up.r * vb_up.r + va_up.i * vb_up.i;
        const double im11 = va_up.r * vb_up.i - va_up.i * vb_up.r;
        const double re22 = va_dn.r * vb_dn.r + va_dn.i * vb_dn.i;
        const double im22 = va_dn.r * vb_dn.i - va_dn.i * vb_dn.r;
        const double re12 = va_up.r * vb_dn.r + va_up.i * vb_dn.i;
        const double im12 = va_up.r * vb_dn.i - va_up.i * vb_dn.r;

        dm11_r += w * re11;
        dm11_i += w * im11;
        dm22_r += w * re22;
        dm22_i += w * im22;
        dm12_r += w * re12;
        dm12_i += w * im12;
        edm11_r += ew * re11;
        edm11_i += ew * im11;
        edm22_r += ew * re22;
        edm22_i += ew * im22;
    }

    dm11_r = ClusterNonColWarpReduceSum(dm11_r);
    dm11_i = ClusterNonColWarpReduceSum(dm11_i);
    dm22_r = ClusterNonColWarpReduceSum(dm22_r);
    dm22_i = ClusterNonColWarpReduceSum(dm22_i);
    dm12_r = ClusterNonColWarpReduceSum(dm12_r);
    dm12_i = ClusterNonColWarpReduceSum(dm12_i);
    edm11_r = ClusterNonColWarpReduceSum(edm11_r);
    edm11_i = ClusterNonColWarpReduceSum(edm11_i);
    edm22_r = ClusterNonColWarpReduceSum(edm22_r);
    edm22_i = ClusterNonColWarpReduceSum(edm22_i);

    if (lane == 0) {
        dm_buffer[(size_t)size_H1 * 0u + (size_t)p] = co * dm11_r - si * dm11_i;
        dm_buffer[(size_t)size_H1 * 1u + (size_t)p] = co * dm22_r - si * dm22_i;
        dm_buffer[(size_t)size_H1 * 2u + (size_t)p] = co * dm12_r - si * dm12_i;
        dm_buffer[(size_t)size_H1 * 3u + (size_t)p] = co * dm12_i + si * dm12_r;
        dm_buffer[(size_t)size_H1 * 4u + (size_t)p] = co * dm11_i + si * dm11_r;
        dm_buffer[(size_t)size_H1 * 5u + (size_t)p] = co * dm22_i + si * dm22_r;
        dm_buffer[(size_t)size_H1 * 6u + (size_t)p] = co * edm11_r - si * edm11_i;
        dm_buffer[(size_t)size_H1 * 7u + (size_t)p] = co * edm22_r - si * edm22_i;
    }
}

typedef struct {
    int initialized;
    int device_id;
    size_t entry_capacity;
    size_t pair_capacity;
    size_t occ_capacity;
    size_t dm_capacity;
    int *d_basis0;
    int *d_basis1;
    int *d_phase_index;
    double *d_phase_r;
    double *d_phase_i;
    double *d_occ;
    double *d_eig_occ;
    double *d_dm_buffer;
} BandNonColDMDeviceWorkspace;

static BandNonColDMDeviceWorkspace BandNonCol_dm_device_workspace = {0};
static int BandNonCol_dm_device_atexit_registered = 0;

/* This routine frees only storage owned by the DM helper.  In particular,
   the d_C2 eigenvector pointer supplied by Band_DFT_NonCol is borrowed and
   is deliberately neither stored in this workspace nor freed here. */
static void BandNonCol_DMDeviceWorkspaceFreeOwned(BandNonColDMDeviceWorkspace *w)
{
    if (w->d_dm_buffer  != NULL) (void)hipFree(w->d_dm_buffer);
    if (w->d_eig_occ    != NULL) (void)hipFree(w->d_eig_occ);
    if (w->d_occ        != NULL) (void)hipFree(w->d_occ);
    if (w->d_phase_i    != NULL) (void)hipFree(w->d_phase_i);
    if (w->d_phase_r    != NULL) (void)hipFree(w->d_phase_r);
    if (w->d_phase_index!= NULL) (void)hipFree(w->d_phase_index);
    if (w->d_basis1     != NULL) (void)hipFree(w->d_basis1);
    if (w->d_basis0     != NULL) (void)hipFree(w->d_basis0);

    memset(w,0,sizeof(*w));
    w->device_id = -1;
}

static int BandNonCol_DMDeviceWorkspaceRelease(int report_errors)
{
    BandNonColDMDeviceWorkspace *w = &BandNonCol_dm_device_workspace;
    int saved_device = -1;
    int switched_device = 0;
    int release_failed = 0;
    hipError_t err;

    if (!w->initialized) return 0;

    err = hipGetDevice(&saved_device);
    if (err!=hipSuccess){
        if (report_errors) BandNonColReportHipError("hipGetDevice(DM workspace release)",err);
        return 1;
    }
    if (saved_device!=w->device_id){
        err = hipSetDevice(w->device_id);
        if (err!=hipSuccess){
            if (report_errors) BandNonColReportHipError("hipSetDevice(DM workspace owner)",err);
            return 1;
        }
        switched_device = 1;
    }

    /* The normal path has already synchronized, while the failure path may
       still have outstanding work referring to these allocations. */
    err = hipDeviceSynchronize();
    if (err!=hipSuccess){
        if (report_errors){
            BandNonColReportHipError("hipDeviceSynchronize(DM workspace release)",err);
        }
        release_failed = 1;
    }
    BandNonCol_DMDeviceWorkspaceFreeOwned(w);

    if (switched_device){
        err = hipSetDevice(saved_device);
        if (err!=hipSuccess){
            if (report_errors) BandNonColReportHipError("hipSetDevice(DM workspace restore)",err);
            return 1;
        }
    }
    return release_failed;
}

static void BandNonCol_DMDeviceWorkspaceProcessCleanup(void)
{
    BandNonColDMDeviceWorkspace *w = &BandNonCol_dm_device_workspace;
    int saved_device = -1;

    /* MPI may already be finalized here, so cleanup is intentionally silent. */
    if (!w->initialized) return;
    (void)hipGetDevice(&saved_device);
    if (hipSetDevice(w->device_id)==hipSuccess){
        (void)hipDeviceSynchronize();
        BandNonCol_DMDeviceWorkspaceFreeOwned(w);
    }
    if (0<=saved_device) (void)hipSetDevice(saved_device);
}

static int BandNonCol_DMDeviceWorkspaceRegisterCleanup(void)
{
    if (!BandNonCol_dm_device_atexit_registered){
        if (atexit(BandNonCol_DMDeviceWorkspaceProcessCleanup)!=0){
            fprintf(stderr,"<Band> Failed to register HIP DM workspace cleanup.\n");
            fflush(stderr);
            return 1;
        }
        BandNonCol_dm_device_atexit_registered = 1;
    }
    return 0;
}

static int BandNonCol_DMDeviceWorkspaceEnsure(int device_id, size_t entry_count,
                                              size_t pair_count, size_t occ_count,
                                              size_t dm_count)
{
    BandNonColDMDeviceWorkspace *w = &BandNonCol_dm_device_workspace;
    BandNonColDMDeviceWorkspace replacement;
    hipError_t err;

    if (BandNonCol_DMDeviceWorkspaceRegisterCleanup()!=0) return 1;

    if (w->initialized && w->device_id!=device_id){
        if (BandNonCol_DMDeviceWorkspaceRelease(1)!=0) return 1;
    }
    if (w->initialized && entry_count<=w->entry_capacity && pair_count<=w->pair_capacity &&
        occ_count<=w->occ_capacity && dm_count<=w->dm_capacity){
        return 0;
    }

    memset(&replacement,0,sizeof(replacement));
    replacement.device_id = device_id;
    replacement.entry_capacity = (w->entry_capacity<entry_count) ? entry_count : w->entry_capacity;
    replacement.pair_capacity = (w->pair_capacity<pair_count) ? pair_count : w->pair_capacity;
    replacement.occ_capacity = (w->occ_capacity<occ_count) ? occ_count : w->occ_capacity;
    replacement.dm_capacity = (w->dm_capacity<dm_count) ? dm_count : w->dm_capacity;

    err = hipMalloc((void **)&replacement.d_basis0,
                    sizeof(int)*replacement.entry_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM basis0)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_basis1,
                    sizeof(int)*replacement.entry_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM basis1)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_phase_index,
                    sizeof(int)*replacement.entry_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM phase_index)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_phase_r,
                    sizeof(double)*replacement.pair_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM phase_r)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_phase_i,
                    sizeof(double)*replacement.pair_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM phase_i)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_occ,
                    sizeof(double)*replacement.occ_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM occ)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_eig_occ,
                    sizeof(double)*replacement.occ_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM eig_occ)",err)) goto allocation_failed;
    err = hipMalloc((void **)&replacement.d_dm_buffer,
                    sizeof(double)*replacement.dm_capacity);
    if (BandNonColReportHipError("hipMalloc(cached DM buffer)",err)) goto allocation_failed;
    replacement.initialized = 1;

    if (w->initialized){
        /* Both workspaces belong to the current device at this point. */
        BandNonCol_DMDeviceWorkspaceFreeOwned(w);
    }
    *w = replacement;
    return 0;

allocation_failed:
    BandNonCol_DMDeviceWorkspaceFreeOwned(&replacement);
    return 1;
}

static int BandNonCol_CalcDMRootDenseImpl_HIP(int entry_count, int pair_count, int size_H1,
                                             int n, int n2, int nk_occ,
                                             const int *basis0, const int *basis1,
                                             const int *phase_index, const double *phase_r,
                                             const double *phase_i, const double *occ,
                                             const double *eig_occ, const dcomplex *dense_evec,
                                             int dense_evec_ld, int dense_evec_on_device,
                                             double *dm_buffer)
{
    const int block_size = 256;
    int device_id = 0;
    hipDeviceProp_t prop;
    int warp_size = 64;
    int entries_per_block;
    dim3 block(block_size);
    dim3 grid;
    BandNonColDMDeviceWorkspace *device_ws = NULL;
    int *d_basis0 = NULL;
    int *d_basis1 = NULL;
    int *d_phase_index = NULL;
    double *d_phase_r = NULL;
    double *d_phase_i = NULL;
    double *d_occ = NULL;
    double *d_eig_occ = NULL;
    dcomplex *d_dense_evec_copy = NULL;
    const dcomplex *d_dense_evec = NULL;
    double *d_dm_buffer = NULL;
    hipError_t err;
    size_t entry_int_bytes;
    size_t pair_bytes;
    size_t occ_bytes;
    size_t evec_bytes;
    size_t evec_dst_pitch;
    size_t evec_src_pitch;
    size_t evec_width;
    size_t evec_height;
    size_t dm_count;
    size_t dm_bytes;
    int failed = 0;

    if (entry_count <= 0 || pair_count <= 0 || size_H1 <= 0 ||
        n <= 0 || n2 <= 0 || (size_t)n2 != 2U*(size_t)n ||
        nk_occ <= 0 || dense_evec_ld < nk_occ ||
        basis0 == NULL || basis1 == NULL || phase_index == NULL ||
        phase_r == NULL || phase_i == NULL || occ == NULL || eig_occ == NULL ||
        dense_evec == NULL || dm_buffer == NULL) {
        fprintf(stderr, "<Band> HIP non-collinear density matrix received invalid arguments.\n");
        fflush(stderr);
        return 1;
    }

    entry_int_bytes = sizeof(int)*(size_t)entry_count;
    pair_bytes = sizeof(double)*(size_t)pair_count;
    occ_bytes = sizeof(double)*(size_t)nk_occ;
    evec_dst_pitch = sizeof(dcomplex)*(size_t)nk_occ;
    evec_src_pitch = sizeof(dcomplex)*(size_t)dense_evec_ld;
    evec_width = sizeof(dcomplex)*(size_t)nk_occ;
    evec_height = (size_t)n2;
    dm_count = (size_t)size_H1*8U;
    dm_bytes = sizeof(double)*dm_count;
    if ((size_t)n2>SIZE_MAX/(size_t)nk_occ ||
        (size_t)n2*(size_t)nk_occ>SIZE_MAX/sizeof(dcomplex)){
        fprintf(stderr,"<Band> HIP non-collinear density-matrix eigenvector size overflow.\n");
        fflush(stderr);
        return 1;
    }
    evec_bytes = sizeof(dcomplex)*(size_t)n2*(size_t)nk_occ;

    err = hipGetDevice(&device_id);
    if (BandNonColReportHipError("hipGetDevice(BandNonCol DM)", err)) goto cleanup_failed;
    err = hipGetDeviceProperties(&prop, device_id);
    if (BandNonColReportHipError("hipGetDeviceProperties(BandNonCol DM)", err)) goto cleanup_failed;
    if (0 < prop.warpSize) {
        warp_size = prop.warpSize;
    }
    entries_per_block = block_size / warp_size;
    if (entries_per_block <= 0) {
        entries_per_block = 1;
    }
    grid = dim3((unsigned int)((entry_count + entries_per_block - 1) / entries_per_block));

    if (dense_evec_on_device) {
        if (BandNonCol_DMDeviceWorkspaceEnsure(device_id,(size_t)entry_count,
                                               (size_t)pair_count,(size_t)nk_occ,
                                               dm_count)!=0){
            goto cleanup_failed;
        }
        device_ws = &BandNonCol_dm_device_workspace;
        d_basis0 = device_ws->d_basis0;
        d_basis1 = device_ws->d_basis1;
        d_phase_index = device_ws->d_phase_index;
        d_phase_r = device_ws->d_phase_r;
        d_phase_i = device_ws->d_phase_i;
        d_occ = device_ws->d_occ;
        d_eig_occ = device_ws->d_eig_occ;
        d_dm_buffer = device_ws->d_dm_buffer;
        d_dense_evec = dense_evec;
    }
    else {
        err = hipMalloc((void **)&d_basis0, entry_int_bytes);
        if (BandNonColReportHipError("hipMalloc(DM basis0)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_basis1, entry_int_bytes);
        if (BandNonColReportHipError("hipMalloc(DM basis1)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_phase_index, entry_int_bytes);
        if (BandNonColReportHipError("hipMalloc(DM phase_index)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_phase_r, pair_bytes);
        if (BandNonColReportHipError("hipMalloc(DM phase_r)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_phase_i, pair_bytes);
        if (BandNonColReportHipError("hipMalloc(DM phase_i)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_occ, occ_bytes);
        if (BandNonColReportHipError("hipMalloc(DM occ)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_eig_occ, occ_bytes);
        if (BandNonColReportHipError("hipMalloc(DM eig_occ)", err)) goto cleanup_failed;
        err = hipMalloc((void **)&d_dense_evec_copy, evec_bytes);
        if (BandNonColReportHipError("hipMalloc(DM dense_evec)", err)) goto cleanup_failed;
        d_dense_evec = d_dense_evec_copy;
        err = hipMalloc((void **)&d_dm_buffer, dm_bytes);
        if (BandNonColReportHipError("hipMalloc(DM buffer)", err)) goto cleanup_failed;
    }

    err = hipMemcpy(d_basis0, basis0, entry_int_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM basis0)", err)) goto cleanup_failed;
    err = hipMemcpy(d_basis1, basis1, entry_int_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM basis1)", err)) goto cleanup_failed;
    err = hipMemcpy(d_phase_index, phase_index, entry_int_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM phase_index)", err)) goto cleanup_failed;
    err = hipMemcpy(d_phase_r, phase_r, pair_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM phase_r)", err)) goto cleanup_failed;
    err = hipMemcpy(d_phase_i, phase_i, pair_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM phase_i)", err)) goto cleanup_failed;
    err = hipMemcpy(d_occ, occ, occ_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM occ)", err)) goto cleanup_failed;
    err = hipMemcpy(d_eig_occ, eig_occ, occ_bytes, hipMemcpyHostToDevice);
    if (BandNonColReportHipError("hipMemcpy(DM eig_occ)", err)) goto cleanup_failed;
    if (!dense_evec_on_device) {
        err = hipMemcpy2D(d_dense_evec_copy, evec_dst_pitch, dense_evec, evec_src_pitch,
                          evec_width, evec_height, hipMemcpyHostToDevice);
        if (BandNonColReportHipError("hipMemcpy2D(DM dense_evec)", err)) goto cleanup_failed;
    }
    err = hipMemset(d_dm_buffer, 0, dm_bytes);
    if (BandNonColReportHipError("hipMemset(DM buffer)", err)) goto cleanup_failed;

    hipLaunchKernelGGL(BandNonColDMRootDenseKernel, grid, block, 0, 0,
                       entry_count, n, n2, nk_occ,
                       dense_evec_on_device ? dense_evec_ld : nk_occ,
                       d_basis0, d_basis1, d_phase_index,
                       d_phase_r, d_phase_i, d_occ, d_eig_occ, d_dense_evec,
                       d_dm_buffer, size_H1);
    err = hipGetLastError();
    if (BandNonColReportHipError("BandNonColDMRootDenseKernel launch", err)) goto cleanup_failed;
    err = hipDeviceSynchronize();
    if (BandNonColReportHipError("BandNonColDMRootDenseKernel synchronize", err)) goto cleanup_failed;
    err = hipMemcpy(dm_buffer, d_dm_buffer, dm_bytes, hipMemcpyDeviceToHost);
    if (BandNonColReportHipError("hipMemcpy(DM buffer back)", err)) goto cleanup_failed;

    goto cleanup;

cleanup_failed:
    failed = 1;

cleanup:
    if (dense_evec_on_device){
        if (failed) (void)BandNonCol_DMDeviceWorkspaceRelease(1);
        return failed;
    }
    if (d_dm_buffer != NULL) hipFree(d_dm_buffer);
    if (d_dense_evec_copy != NULL) hipFree(d_dense_evec_copy);
    if (d_eig_occ != NULL) hipFree(d_eig_occ);
    if (d_occ != NULL) hipFree(d_occ);
    if (d_phase_i != NULL) hipFree(d_phase_i);
    if (d_phase_r != NULL) hipFree(d_phase_r);
    if (d_phase_index != NULL) hipFree(d_phase_index);
    if (d_basis1 != NULL) hipFree(d_basis1);
    if (d_basis0 != NULL) hipFree(d_basis0);
    return failed;
}

extern "C" int BandNonCol_CalcDMRootDense_HIP(int entry_count, int pair_count, int size_H1,
                                              int n, int n2, int nk_occ,
                                              const int *basis0, const int *basis1,
                                              const int *phase_index, const double *phase_r,
                                              const double *phase_i, const double *occ,
                                              const double *eig_occ, const dcomplex *dense_evec,
                                              double *dm_buffer)
{
    return BandNonCol_CalcDMRootDenseImpl_HIP(entry_count,pair_count,size_H1,n,n2,nk_occ,
                                              basis0,basis1,phase_index,phase_r,phase_i,
                                              occ,eig_occ,dense_evec,n2,0,dm_buffer);
}

extern "C" int BandNonCol_CalcDMRootDenseDevice_HIP(int entry_count, int pair_count, int size_H1,
                                                    int n, int n2, int nk_occ,
                                                    const int *basis0, const int *basis1,
                                                    const int *phase_index, const double *phase_r,
                                                    const double *phase_i, const double *occ,
                                                    const double *eig_occ,
                                                    const dcomplex *d_dense_evec,
                                                    int dense_evec_ld, double *dm_buffer)
{
    return BandNonCol_CalcDMRootDenseImpl_HIP(entry_count,pair_count,size_H1,n,n2,nk_occ,
                                              basis0,basis1,phase_index,phase_r,phase_i,
                                              occ,eig_occ,d_dense_evec,dense_evec_ld,1,dm_buffer);
}
