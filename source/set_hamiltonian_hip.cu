#include <hip/hip_runtime.h>

#include <cstddef>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

constexpr int kThreads = 256;

/* Each team forms a 16x16 orbital tile.  Cache 32 grid points in LDS and
   apply the potential to the left orbital once, rather than once per
   matrix element.  FP64 accumulation still follows the original grid order.
   In particular, the float orbitals are converted before multiplication. */
__global__ __launch_bounds__(kThreads) void matrix_elements_tiled_kernel(
    int pair_count, std::size_t total_nolg,
    const int *__restrict__ pair_NO0, const int *__restrict__ pair_NO1,
    const int *__restrict__ pair_NOLG,
    const std::size_t *__restrict__ pair_h_offset,
    const std::size_t *__restrict__ pair_nolg_offset,
    const std::size_t *__restrict__ pair_orbs0_offset,
    const std::size_t *__restrict__ pair_orbs1_offset,
    const double *__restrict__ vpotbuf, const float *__restrict__ orbs0buf,
    const float *__restrict__ orbs1buf, double *__restrict__ hbuf)
{
    const int pair = blockIdx.x;
    const int spin = blockIdx.y;
    if (pair >= pair_count) return;
    const int no0 = pair_NO0[pair], no1 = pair_NO1[pair];
    const int nolg = pair_NOLG[pair];
    const std::size_t hbase = pair_h_offset[pair] +
                            static_cast<std::size_t>(spin) * no0 * no1;
    const double *v = vpotbuf + static_cast<std::size_t>(spin) * total_nolg + pair_nolg_offset[pair];
    const float *a = orbs0buf + pair_orbs0_offset[pair];
    const float *b = orbs1buf + pair_orbs1_offset[pair];
    const int lane = threadIdx.x;
    const int row = lane / 16, col = lane % 16;
    __shared__ double left[32][16];
    __shared__ float right[32][16];

    for (int i0 = 0; i0 < no0; i0 += 16) {
        for (int j0 = 0; j0 < no1; j0 += 16) {
            const bool active = i0 + row < no0 && j0 + col < no1;
            const std::size_t hidx = hbase + static_cast<std::size_t>(i0 + row) * no1 + j0 + col;
            double sum = active ? hbuf[hidx] : 0.0;
            for (int g0 = 0; g0 < nolg; g0 += 32) {
                const int count = nolg - g0 < 32 ? nolg - g0 : 32;
                for (int t = lane; t < 32 * 16; t += kThreads) {
                    const int g = t / 16, o = t % 16;
                    left[g][o] = (g < count && i0 + o < no0)
                        ? v[g0 + g] * static_cast<double>(a[static_cast<std::size_t>(g0 + g) * no0 + i0 + o]) : 0.0;
                    right[g][o] = (g < count && j0 + o < no1)
                        ? b[static_cast<std::size_t>(g0 + g) * no1 + j0 + o] : 0.0f;
                }
                __syncthreads();
                if (active) {
                    for (int g = 0; g < count; ++g)
                        sum += left[g][row] * static_cast<double>(right[g][col]);
                }
                __syncthreads();
            }
            if (active) hbuf[hidx] = sum;
        }
    }
}

bool use_tiled_kernel()
{
    /* Keep the original kernel available for reproducible GPU A/B runs. */
    const char *value = std::getenv("OPENMX_SETHAM_HIP_KERNEL");
    return value == nullptr || std::strcmp(value, "scalar") != 0;
}

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

int launch_matrix_elements(int pair_count, int spin_count, int max_output_count, std::size_t total_nolg,
                           const int *d_no0, const int *d_no1, const int *d_nolg,
                           const std::size_t *d_hoff, const std::size_t *d_noff,
                           const std::size_t *d_o0off, const std::size_t *d_o1off,
                           const double *d_vpot, const float *d_o0, const float *d_o1, double *d_h)
{
    const dim3 block(kThreads);
    const dim3 grid(static_cast<unsigned>(pair_count),
                    static_cast<unsigned>((max_output_count + kThreads - 1) / kThreads));
    const bool tiled = use_tiled_kernel();
    const char *trace = std::getenv("OPENMX_SETHAM_TIMING");
    const bool profile = trace != nullptr && std::atoi(trace) != 0;
    std::chrono::steady_clock::time_point start;
    if (profile) start = std::chrono::steady_clock::now();
    if (tiled) {
        hipLaunchKernelGGL(matrix_elements_tiled_kernel,
                           dim3(static_cast<unsigned>(pair_count), static_cast<unsigned>(spin_count)),
                           block, 0, 0, pair_count, total_nolg, d_no0, d_no1, d_nolg,
                           d_hoff, d_noff, d_o0off, d_o1off, d_vpot, d_o0, d_o1, d_h);
    } else {
        hipLaunchKernelGGL(matrix_elements_kernel, grid, block, 0, 0,
                           pair_count, spin_count, total_nolg, d_no0, d_no1, d_nolg,
                           d_hoff, d_noff, d_o0off, d_o1off, d_vpot, d_o0, d_o1, d_h);
    }
    if (hipGetLastError() != hipSuccess || hipDeviceSynchronize() != hipSuccess) return 2;
    if (profile) {
        const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        std::fprintf(stdout, "SETHAM_HIP kernel=%s pairs=%d spins=%d time=%.6f s\n",
                     tiled ? "tiled" : "scalar", pair_count, spin_count, seconds);
        std::fflush(stdout);
    }
    return 0;
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

    result = launch_matrix_elements(pair_count, spin_count, max_output_count, total_nolg,
                                    d_no0, d_no1, d_nolg, d_hoff, d_noff, d_o0off, d_o1off,
                                    d_vpot, d_o0, d_o1, d_h);
    if (result != 0) goto cleanup;
    if (hipMemcpy(hbuf, d_h, sizeof(double) * total_h, hipMemcpyDeviceToHost) != hipSuccess) result = 2;

cleanup:
    hipFree(d_h); hipFree(d_o1); hipFree(d_o0); hipFree(d_vpot);
    hipFree(d_o1off); hipFree(d_o0off); hipFree(d_noff); hipFree(d_hoff);
    hipFree(d_nolg); hipFree(d_no1); hipFree(d_no0);
    (void)hipGetLastError();
    return result;
}

/* The same kernel on the tables Set_Hamiltonian keeps resident on the device
   between SCF iterations (device pointers of the associated copies): only
   the potential and the output travel. */
extern "C" int Set_Hamiltonian_Hip_MatrixElements_Resident(
    int pair_count, int spin_count, int max_output_count,
    std::size_t total_h, std::size_t total_nolg,
    const int *d_no0, const int *d_no1, const int *d_nolg,
    const std::size_t *d_hoff, const std::size_t *d_noff,
    const std::size_t *d_o0off, const std::size_t *d_o1off,
    const float *d_o0, const float *d_o1,
    const double *vpotbuf, double *hbuf)
{
    double *d_vpot = nullptr, *d_h = nullptr;
    int result = 0;

    if (pair_count <= 0 || spin_count <= 0 || max_output_count <= 0) return 0;
    if (d_no0 == nullptr || d_no1 == nullptr || d_nolg == nullptr || d_hoff == nullptr ||
        d_noff == nullptr || d_o0off == nullptr || d_o1off == nullptr || d_o0 == nullptr || d_o1 == nullptr) {
        return 1;
    }
    (void)hipGetLastError();

    if (!device_alloc_copy(&d_vpot, vpotbuf, static_cast<std::size_t>(spin_count) * total_nolg) ||
        !device_alloc_copy(&d_h, hbuf, total_h)) {
        result = 1;
        goto cleanup;
    }
    result = launch_matrix_elements(pair_count, spin_count, max_output_count, total_nolg,
                                    d_no0, d_no1, d_nolg, d_hoff, d_noff, d_o0off, d_o1off,
                                    d_vpot, d_o0, d_o1, d_h);
    if (result != 0) goto cleanup;
    if (hipMemcpy(hbuf, d_h, sizeof(double) * total_h, hipMemcpyDeviceToHost) != hipSuccess) result = 2;

cleanup:
    hipFree(d_h); hipFree(d_vpot);
    (void)hipGetLastError();
    return result;
}
