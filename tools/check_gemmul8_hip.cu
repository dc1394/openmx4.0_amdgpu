// Numerical checks for the entry points instantiated by gemmul8_openmx.cu.
// Link with source/gemmul8_bridge.o, source/third_party/GEMMul8/lib/libgemmul8.a,
// hipBLAS and hipBLASLt; use the same HIP architecture as the OpenMX build.
#include <hip/hip_runtime.h>
#include <hipblas/hipblas.h>
#include "gemmul8.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

extern "C" hipblasStatus_t openmx_gemmul8Dgemm(
    hipblasHandle_t, hipblasOperation_t, hipblasOperation_t, int, int, int,
    const double *, const double *, int, const double *, int,
    const double *, double *, int);
extern "C" hipblasStatus_t openmx_gemmul8Zgemm(
    hipblasHandle_t, hipblasOperation_t, hipblasOperation_t, int, int, int,
    const hipDoubleComplex *, const hipDoubleComplex *, int,
    const hipDoubleComplex *, int, const hipDoubleComplex *, hipDoubleComplex *, int);
extern "C" void openmx_gemmul8SetEnabled(int);
extern "C" void openmx_gemmul8ReleaseWorkspaces();

void check(hipError_t status) {
    if (status != hipSuccess) throw std::runtime_error(hipGetErrorString(status));
}
void check(hipblasStatus_t status) {
    if (status != HIPBLAS_STATUS_SUCCESS)
        throw std::runtime_error("hipBLAS status " + std::to_string(status));
}

struct Buffer {
    void *ptr = nullptr;
    explicit Buffer(size_t bytes) { check(hipMalloc(&ptr, bytes)); }
    ~Buffer() { if (ptr) (void)hipFree(ptr); }
    Buffer(const Buffer &) = delete;
    template <class T> T *as() { return static_cast<T *>(ptr); }
};

template <class T> constexpr bool complex_v = !std::is_same_v<T, double>;
template <class T> T scalar(double re, double im = 0) {
    if constexpr (complex_v<T>) return {re, im};
    else return re;
}
template <class T> double norm(T value) {
    if constexpr (complex_v<T>) return std::hypot(value.x, value.y);
    else return std::abs(value);
}
template <class T> double distance(T a, T b) {
    if constexpr (complex_v<T>) return std::hypot(a.x - b.x, a.y - b.y);
    else return std::abs(a - b);
}
template <class T> std::vector<T> matrix(int ld, int columns, int seed) {
    std::vector<T> result(size_t(ld) * columns);
    for (size_t i = 0; i < result.size(); ++i) {
        // Unequal signed real/imaginary components, with a modest dynamic range.
        double re = std::ldexp(double(int((i * 37 + seed) % 101) - 50) / 51,
                               int(i % 5) - 2);
        double im = std::ldexp(double(int((i * 43 + seed * 3) % 97) - 48) / 49,
                               int(i % 7) - 3);
        result[i] = scalar<T>(re, im);
    }
    return result;
}

int passed = 0;
template <class T, class Native, class Emulated>
void compare(const std::string &name, const std::vector<T> &initial,
             Native native, Emulated emulated) {
    const size_t bytes = initial.size() * sizeof(T);
    Buffer reference(bytes), candidate(bytes);
    check(hipMemcpy(reference.ptr, initial.data(), bytes, hipMemcpyHostToDevice));
    check(hipMemcpy(candidate.ptr, initial.data(), bytes, hipMemcpyHostToDevice));
    native(reference.as<T>());
    emulated(candidate.as<T>());
    check(hipDeviceSynchronize());
    std::vector<T> a(initial.size()), b(initial.size());
    check(hipMemcpy(a.data(), reference.ptr, bytes, hipMemcpyDeviceToHost));
    check(hipMemcpy(b.data(), candidate.ptr, bytes, hipMemcpyDeviceToHost));
    double error = 0, scale = 1;
    for (size_t i = 0; i < a.size(); ++i) {
        if (!std::isfinite(norm(a[i])) || !std::isfinite(norm(b[i])))
            throw std::runtime_error(name + ": nonfinite output");
        error = std::max(error, distance(a[i], b[i]));
        scale = std::max(scale, norm(a[i]));
    }
    // This also checks untouched triangles and leading-dimension padding.
    if (error > 2e-12 * scale) throw std::runtime_error(name + ": numerical mismatch");
    std::printf("PASS %-46s max_abs_error=%.3e scaled_error=%.3e\n",
                name.c_str(), error, error / scale);
    std::fflush(stdout);
    ++passed;
}

template <class T> void gemm(hipblasHandle_t handle, hipblasOperation_t ta,
                            hipblasOperation_t tb, int m, int n, int k,
                            bool enabled, bool require_blocking = false) {
    int lda = (ta == HIPBLAS_OP_N ? m : k) + 3;
    int ldb = (tb == HIPBLAS_OP_N ? k : n) + 4;
    int ldc = m + 5;
    auto a = matrix<T>(lda, ta == HIPBLAS_OP_N ? k : m, 7);
    auto b = matrix<T>(ldb, tb == HIPBLAS_OP_N ? n : k, 11);
    auto c = matrix<T>(ldc, n, 17);
    Buffer da(a.size() * sizeof(T)), db(b.size() * sizeof(T));
    check(hipMemcpy(da.ptr, a.data(), a.size() * sizeof(T), hipMemcpyHostToDevice));
    check(hipMemcpy(db.ptr, b.data(), b.size() * sizeof(T), hipMemcpyHostToDevice));
    const T alpha = scalar<T>(0.75, -0.25), beta = scalar<T>(-0.5, 0.125);
    const size_t full = gemmul8::workSize<complex_v<T>, gemmul8::Backend::INT8>(m, n, k, 15);
    if (require_blocking && full <= (size_t(256) << 20))
        throw std::runtime_error("The large GEMM does not exercise workspace blocking");
    openmx_gemmul8SetEnabled(enabled);
    std::string name = complex_v<T> ? "ZGEMM" : "DGEMM";
    name += " " + std::to_string(ta) + "/" + std::to_string(tb) + " " +
            std::to_string(m) + "x" + std::to_string(n) + "x" + std::to_string(k);
    name += enabled ? " emulated" : " disabled";
    if (require_blocking)
        std::printf("blocking workspace: %zu bytes, bridge cap: 268435456 bytes\n", full);
    compare<T>(name, c, [&](T *out) {
        if constexpr (complex_v<T>)
            check(hipblasZgemm(handle, ta, tb, m, n, k, &alpha, da.as<T>(), lda,
                              db.as<T>(), ldb, &beta, out, ldc));
        else
            check(hipblasDgemm(handle, ta, tb, m, n, k, &alpha, da.as<T>(), lda,
                              db.as<T>(), ldb, &beta, out, ldc));
    }, [&](T *out) {
        if constexpr (complex_v<T>)
            check(openmx_gemmul8Zgemm(handle, ta, tb, m, n, k, &alpha, da.as<T>(), lda,
                                    db.as<T>(), ldb, &beta, out, ldc));
        else
            check(openmx_gemmul8Dgemm(handle, ta, tb, m, n, k, &alpha, da.as<T>(), lda,
                                    db.as<T>(), ldb, &beta, out, ldc));
    });
}

template <class T> void structured(hipblasHandle_t h) {
    constexpr int m = 129, n = 137, k = 145, ldc = m + 5;
    const T alpha = scalar<T>(0.75, -0.25), beta = scalar<T>(-0.5);
    const double real_beta = -0.5;
    const char *type = complex_v<T> ? "Z" : "D";
    gemmul8::set_memory_saving(h, false);
    for (auto side : {HIPBLAS_SIDE_LEFT, HIPBLAS_SIDE_RIGHT}) {
        int order = side == HIPBLAS_SIDE_LEFT ? m : n;
        int lda = order + 3, ldb = m + 4;
        auto a = matrix<T>(lda, order, 19), b = matrix<T>(ldb, n, 23);
        for (int i = 0; i < order; ++i) a[size_t(i) * lda + i] = scalar<T>(2);
        Buffer da(a.size() * sizeof(T)), db(b.size() * sizeof(T));
        check(hipMemcpy(da.ptr, a.data(), a.size() * sizeof(T), hipMemcpyHostToDevice));
        check(hipMemcpy(db.ptr, b.data(), b.size() * sizeof(T), hipMemcpyHostToDevice));
        for (auto uplo : {HIPBLAS_FILL_MODE_LOWER, HIPBLAS_FILL_MODE_UPPER}) {
            Buffer work(gemmul8::workSize<complex_v<T>, gemmul8::Backend::INT8,
                        complex_v<T> ? gemmul8::Func::hemm : gemmul8::Func::symm>(m, n, order, 15));
            auto c = matrix<T>(ldc, n, 29);
            std::string suffix = " " + std::to_string(side) + "/" + std::to_string(uplo);
            compare<T>(std::string(type) + (complex_v<T> ? "HEMM" : "SYMM") + suffix, c,
                [&](T *out) {
                    if constexpr (complex_v<T>) check(hipblasZhemm(h, side, uplo, m, n, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &beta, out, ldc));
                    else check(hipblasDsymm(h, side, uplo, m, n, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &beta, out, ldc));
                }, [&](T *out) {
                    if constexpr (complex_v<T>) gemmul8::hemm<T>(h, side, uplo, m, n, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &beta, out, ldc, 15, false, work.ptr);
                    else gemmul8::symm<T>(h, side, uplo, m, n, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &beta, out, ldc, 15, false, work.ptr);
                });
            Buffer tw(gemmul8::workSize<complex_v<T>, gemmul8::Backend::INT8,
                      gemmul8::Func::trmm>(m, n, order, 15));
            for (auto op : {HIPBLAS_OP_N, HIPBLAS_OP_T, HIPBLAS_OP_C}) {
                for (auto diag : {HIPBLAS_DIAG_NON_UNIT, HIPBLAS_DIAG_UNIT}) {
                    compare<T>(std::string(type) + "TRMM" + suffix + " " +
                        std::to_string(op) + "/" + std::to_string(diag), c,
                        [&](T *out) {
                            if constexpr (complex_v<T>) check(hipblasZtrmm(h, side, uplo, op, diag,
                                m, n, &alpha, da.as<T>(), lda, db.as<T>(), ldb, out, ldc));
                            else check(hipblasDtrmm(h, side, uplo, op, diag,
                                m, n, &alpha, da.as<T>(), lda, db.as<T>(), ldb, out, ldc));
                        }, [&](T *out) {
                            gemmul8::trmm<T>(h, side, uplo, op, diag, m, n, &alpha,
                                da.as<T>(), lda, db.as<T>(), ldb, out, ldc, 15, false, tw.ptr);
                        });
                }
            }
        }
    }
    for (auto uplo : {HIPBLAS_FILL_MODE_LOWER, HIPBLAS_FILL_MODE_UPPER}) {
        for (auto op : {HIPBLAS_OP_N, complex_v<T> ? HIPBLAS_OP_C : HIPBLAS_OP_T}) {
            int lda = (op == HIPBLAS_OP_N ? m : k) + 3;
            int ldb = lda + 1, cols = op == HIPBLAS_OP_N ? k : m;
            auto a = matrix<T>(lda, cols, 31), b = matrix<T>(ldb, cols, 37);
            auto c = matrix<T>(ldc, m, 41);
            Buffer da(a.size() * sizeof(T)), db(b.size() * sizeof(T));
            check(hipMemcpy(da.ptr, a.data(), a.size() * sizeof(T), hipMemcpyHostToDevice));
            check(hipMemcpy(db.ptr, b.data(), b.size() * sizeof(T), hipMemcpyHostToDevice));
            Buffer work(gemmul8::workSize<complex_v<T>, gemmul8::Backend::INT8,
                        complex_v<T> ? gemmul8::Func::her2k : gemmul8::Func::syr2k>(m, m, k, 15));
            compare<T>(std::string(type) + (complex_v<T> ? "HER2K" : "SYR2K") + " " +
                std::to_string(uplo) + "/" + std::to_string(op), c,
                [&](T *out) {
                    if constexpr (complex_v<T>) check(hipblasZher2k(h, uplo, op, m, k, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &real_beta, out, ldc));
                    else check(hipblasDsyr2k(h, uplo, op, m, k, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &beta, out, ldc));
                }, [&](T *out) {
                    if constexpr (complex_v<T>) gemmul8::her2k<T>(h, uplo, op, m, k, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &real_beta, out, ldc, 15, false, work.ptr);
                    else gemmul8::syr2k<T>(h, uplo, op, m, k, &alpha,
                        da.as<T>(), lda, db.as<T>(), ldb, &beta, out, ldc, 15, false, work.ptr);
                });
        }
    }
}

int main() {
    try {
        std::printf("GEMMul8 %s, INT8, num_moduli=15\n", gemmul8::version_string);
        hipblasHandle_t h;
        check(hipblasCreate(&h));
        for (auto a : {HIPBLAS_OP_N, HIPBLAS_OP_T, HIPBLAS_OP_C}) {
            for (auto b : {HIPBLAS_OP_N, HIPBLAS_OP_T, HIPBLAS_OP_C}) {
                gemm<double>(h, a, b, 129, 137, 145, true);
                gemm<hipDoubleComplex>(h, a, b, 129, 137, 145, true);
            }
        }
        gemm<double>(h, HIPBLAS_OP_N, HIPBLAS_OP_N, 4097, 2049, 2049, true, true);
        gemm<hipDoubleComplex>(h, HIPBLAS_OP_C, HIPBLAS_OP_N, 2049, 2049, 2049, true, true);
        gemm<double>(h, HIPBLAS_OP_T, HIPBLAS_OP_N, 129, 137, 145, false);
        gemm<hipDoubleComplex>(h, HIPBLAS_OP_C, HIPBLAS_OP_T, 129, 137, 145, false);
        openmx_gemmul8ReleaseWorkspaces();
        structured<double>(h);
        structured<hipDoubleComplex>(h);
        check(hipblasDestroy(h));
        std::printf("All %d checks passed.\n", passed);
        return 0;
    } catch (const std::exception &error) {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        return 1;
    }
}
