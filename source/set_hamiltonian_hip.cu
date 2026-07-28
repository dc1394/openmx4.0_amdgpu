#include <hip/hip_runtime.h>

#include <cstddef>

namespace {

constexpr int kThreads = 256;

__global__ void matrix_elements_kernel(
    int pair_count, int spin_count, std::size_t total_nolg,
    const int *pair_NO0, const int *pair_NO1, const int *pair_NOLG,
    const std::size_t *pair_h_offset, const std::size_t *pair_nolg_offset,
    const std::size_t *pair_orbs0_offset, const std::size_t *pair_orbs1_offset,
    const double *vpotbuf, const float *orbs0buf, const float *orbs1buf,
    double *hbuf)
{
    const int pair = static_cast<int>(blockIdx.x);
    if (pair >= pair_count) return;

    const int no0 = pair_NO0[pair];
    const int no1 = pair_NO1[pair];
    const int nolg = pair_NOLG[pair];
    const std::size_t mat_size = static_cast<std::size_t>(no0) * no1;
    const std::size_t count = static_cast<std::size_t>(spin_count) * mat_size;
    const std::size_t e = static_cast<std::size_t>(blockIdx.y) * blockDim.x + threadIdx.x;
    if (e >= count) return;

    const int spin = static_cast<int>(e / mat_size);
    const std::size_t ij = e - static_cast<std::size_t>(spin) * mat_size;
    const int i = static_cast<int>(ij / no1);
    const int j = static_cast<int>(ij - static_cast<std::size_t>(i) * no1);
    const std::size_t h_off = pair_h_offset[pair];
    const std::size_t nolg_off = pair_nolg_offset[pair];
    const std::size_t orbs0_off = pair_orbs0_offset[pair];
    const std::size_t orbs1_off = pair_orbs1_offset[pair];
    double sum = hbuf[h_off + e];

    for (int grid = 0; grid < nolg; ++grid) {
        sum += vpotbuf[static_cast<std::size_t>(spin) * total_nolg + nolg_off + grid] *
               static_cast<double>(orbs0buf[orbs0_off + static_cast<std::size_t>(grid) * no0 + i]) *
               static_cast<double>(orbs1buf[orbs1_off + static_cast<std::size_t>(grid) * no1 + j]);
    }
    hbuf[h_off + e] = sum;
}

template <typename T>
bool device_alloc_copy(T **dst, const T *src, std::size_t count)
{
    if (hipMalloc(reinterpret_cast<void **>(dst), sizeof(T) * count) != hipSuccess) return false;
    if (hipMemcpy(*dst, src, sizeof(T) * count, hipMemcpyHostToDevice) != hipSuccess) return false;
    return true;
}

} // namespace

extern "C" int Set_Hamiltonian_Hip_MatrixElements(
    int pair_count, int spin_count, int max_output_count,
    std::size_t total_h, std::size_t total_nolg, std::size_t total_orbs0, std::size_t total_orbs1,
    const int *pair_NO0, const int *pair_NO1, const int *pair_NOLG,
    const std::size_t *pair_h_offset, const std::size_t *pair_nolg_offset,
    const std::size_t *pair_orbs0_offset, const std::size_t *pair_orbs1_offset,
    const double *vpotbuf, const float *orbs0buf, const float *orbs1buf, double *hbuf)
{
    int *d_no0 = nullptr, *d_no1 = nullptr, *d_nolg = nullptr;
    std::size_t *d_hoff = nullptr, *d_noff = nullptr, *d_o0off = nullptr, *d_o1off = nullptr;
    double *d_vpot = nullptr, *d_h = nullptr;
    float *d_o0 = nullptr, *d_o1 = nullptr;
    int result = 0;

    if (pair_count <= 0 || spin_count <= 0 || max_output_count <= 0) return 0;
    (void)hipGetLastError();

#define COPY_DEVICE(dst, src, count) do { if (!device_alloc_copy(&(dst), (src), (count))) { result = 1; goto cleanup; } } while (0)
    COPY_DEVICE(d_no0, pair_NO0, pair_count);
    COPY_DEVICE(d_no1, pair_NO1, pair_count);
    COPY_DEVICE(d_nolg, pair_NOLG, pair_count);
    COPY_DEVICE(d_hoff, pair_h_offset, pair_count);
    COPY_DEVICE(d_noff, pair_nolg_offset, pair_count);
    COPY_DEVICE(d_o0off, pair_orbs0_offset, pair_count);
    COPY_DEVICE(d_o1off, pair_orbs1_offset, pair_count);
    COPY_DEVICE(d_vpot, vpotbuf, static_cast<std::size_t>(spin_count) * total_nolg);
    COPY_DEVICE(d_o0, orbs0buf, total_orbs0);
    COPY_DEVICE(d_o1, orbs1buf, total_orbs1);
    COPY_DEVICE(d_h, hbuf, total_h);
#undef COPY_DEVICE

    {
        const dim3 block(kThreads);
        const dim3 grid(static_cast<unsigned>(pair_count),
                        static_cast<unsigned>((max_output_count + kThreads - 1) / kThreads));
        hipLaunchKernelGGL(matrix_elements_kernel, grid, block, 0, 0,
                           pair_count, spin_count, total_nolg, d_no0, d_no1, d_nolg,
                           d_hoff, d_noff, d_o0off, d_o1off, d_vpot, d_o0, d_o1, d_h);
        if (hipGetLastError() != hipSuccess || hipDeviceSynchronize() != hipSuccess) {
            result = 2;
            goto cleanup;
        }
    }
    if (hipMemcpy(hbuf, d_h, sizeof(double) * total_h, hipMemcpyDeviceToHost) != hipSuccess) result = 2;

cleanup:
    hipFree(d_h); hipFree(d_o1); hipFree(d_o0); hipFree(d_vpot);
    hipFree(d_o1off); hipFree(d_o0off); hipFree(d_noff); hipFree(d_hoff);
    hipFree(d_nolg); hipFree(d_no1); hipFree(d_no0);
    (void)hipGetLastError();
    return result;
}
