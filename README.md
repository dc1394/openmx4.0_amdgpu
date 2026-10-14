# openmx4.0_amdgpu

## What does this code do?
The AMD GPU (ROCm/HIP) port of [openmx4.0_gpu](https://github.com/dc1394/openmx4.0_gpu), a GPU-accelerated version of [OpenMX](https://www.openmx-square.org/) (first-principles calculations with numerical atomic orbitals). The dense eigensolvers of the band and cluster calculations (collinear and non-collinear), the O(N) solvers (DC, DC-LNO, Krylov) and the heavy construction stages around them (Hamiltonian assembly, nonlocal and VNA projectors, density and orbital grids, forces, charge mixing) run on the GPU. The CUDA/cuBLAS/cuSOLVER code of the NVIDIA version is rewritten on HIP/hipBLAS/hipSOLVER, the OpenACC regions on OpenMP target offloading, and the single-GPU dense eigensolves use [MAGMA](https://icl.utk.edu/magma/) (hipMAGMA). The two trees track each other.

## Code author
Hiroyuki Kawai (Niigata Univ.)</br>
X account: [@dc1394](https://x.com/dc1394)

## How to enable GPU acceleration
GPU acceleration is on by default: `scf.eigen.lib` defaults to `gpusolver`. The conventional CPU paths are selected with

```ini
scf.eigen.lib             elpa2         # CPU (ELPA2) paths; default=gpusolver
```

A run that finds no usable GPU demotes itself to ELPA2, and `OPENMX_GPU=0` forces that demotion on a GPU machine (handy for CPU-vs-GPU comparisons with unmodified inputs).

## GPU diagnostic output
GPU diagnostics follow the NVIDIA version's `level.of.stdout` policy. The default remains 1; increase it in the input when investigating the GPU paths:

```ini
level.of.stdout          2
```

| Level | GPU output |
| --- | --- |
| 1 | Normal OpenMX progress and GPU labels; notices when GPU initialization fails or a dense GPU eigensolve must move to the CPU |
| 2 | Also workspace/cache plans, precision configuration and transitions, individual-stage fallbacks and solver retries |
| 3 | Also per-SCF/per-k-point refinement and warm-start details, per-rank low-memory diagnostics |

Errors and invalid-setting warnings remain visible. Explicit diagnostic/profile flags such as `OPENMX_GPU_VERBOSE`, `OPENMX_SETHAM_TIMING`, `OPENMX_BAND_PROFILE` and `OPENMX_EIGEN_REFINE_CHECK` retain their output. Changing the output level does not change the precision, GPU admission decisions or MPI participation.

At level 1 or higher, the nonlocal matrix, VNA projector and Hamiltonian progress lines carry `(GPU-accelerated)` when at least one rank successfully computes that stage on the GPU. These lines are printed after the stage so that a failed GPU attempt followed by CPU fallback is reported correctly. The current overlap/kinetic matrix implementation uses CPU OpenMP and does not carry a GPU label.

The NVIDIA synchronization and regression checks are recorded in [nvidia_sync_20261012.txt](nvidia_sync_20261012.txt).

## Distributed multi-GPU cluster diagonalization (gpusolver2)
With `gpusolver` a cluster calculation (one k-point) diagonalizes on a single GPU. `scf.eigen.lib gpusolver2` (cluster solver only) replaces that diagonalization with [ELPA](https://elpa.mpcdf.mpg.de/) 2026.02 (AMD GPU kernels) + [COSMA](https://github.com/eth-cscs/COSMA) (ROCm backend), engaging every rank and every GPU across nodes. A solve that does not fit in GPU memory falls back to the ELPA CPU kernels / ScaLAPACK; solves below n=256 stay on the CPU kernels. `OPENMX_GS2_ELPA_GPU` and `OPENMX_GS2_GEMM_GPU` (1 = GPU, 0 = CPU, unset = decide from free memory) override the two decisions; on a VRAM-limited card shared by many ranks use `OPENMX_GS2_GEMM_GPU=0`. ELPA, COSMA, COSTA and Tiled-MM are bundled as source archives under `source/third_party/dist/` and built by the first `make` (no network needed; autoconf, automake, libtool, m4 and python3 required). The `elpa1`/`elpa2` paths keep the ELPA 2018.05 embedded in OpenMX.

## GEMMul8
The large dense matrix multiplications of the GPU eigensolver path use a bridge to [GEMMul8](https://github.com/RIKEN-RCCS/GEMMul8) [v3.5.2](https://github.com/RIKEN-RCCS/GEMMul8/releases/tag/v3.5.2), pinned to commit `603b52363715796a0af5e4aa1ed8d386349b4251`. It emulates FP64 GEMM on the INT8 matrix cores (Ozaki scheme II), supporting consumer GPUs with limited FP64 throughput. The bridge defaults to native hipBLAS FP64 on MI300A and GEMMul8 on other GPUs. An explicit `scf.gemmul8.enable on` or `off` selects GEMMul8 or native FP64, respectively; the existing environment disable settings still apply. GEMMul8's memory-saving mode is on by default with a 256 MiB per-rank workspace cap (`OPENMX_GEMMUL8_MAX_WORKSPACE_MB`; 0 = uncapped).
The v3.5.2 build and numerical checks are recorded in [gemmul8_upgrade_20261005.txt](gemmul8_upgrade_20261005.txt).

### MI300A and Radeon defaults

MI300A tuning is selected by the exact `gfx942` architecture and the runtime's integrated-GPU flag. Discrete MI300X and consumer APUs do not inherit it. Device detection is deferred until GPU work is requested; parsing inputs and `OPENMX_GPU=0` do not initialize HIP for this policy.

| Policy | MI300A | Radeon RX 9060 XT |
|---|---|---|
| Common FP64 dense eigensolver dispatcher | native hipSOLVER/rocSOLVER | MAGMA |
| OpenMX GEMM bridge | native hipBLAS FP64 | GEMMul8 INT8 emulation |
| Automatic SCF refinement | off | two refinement steps, as before |
| NC cluster density matrix | native FP64 GEMMs | GEMMul8 GEMMs |
| NC cluster device buffers between SCF steps | retained, subject to memory checks | released, as before |

The direct dense entry points now apply the same architecture and explicit-backend policy as the generic wrappers. Previously, the NC cluster root called a historical MAGMA entry point that bypassed that policy, even when the progress label said hipSOLVER. `OPENMX_GPU_EIGENSOLVER=hipsolver|magma` takes precedence, and a failing native solve still retries from its saved input. The MAGMA fallback retains its Ozaki2 default; `OPENMX_MAGMA_OZAKI2=0` explicitly selects stock MAGMA. This setting is independent of the OpenMX GEMM bridge.

`OPENMX_CLUSTER_NC_DEVICE_KEEP=0|1` and `OPENMX_CLUSTER_GPU_DM_GEMM=0|1` override the NC defaults. `OPENMX_GEMMUL8_DISABLE=0` requests GEMMul8 even on MI300A unless the input explicitly sets `scf.gemmul8.enable off`. Backend diagnostics distinguish native hipBLAS from emulation, including workspace fallbacks.

The NC band path accounts for the selected native solver's full-spectrum workspace on MI300A. Successful workspace-size queries are cached by device and matrix dimension, and `OPENMX_NC_HIPSOLVER_TURN_RELEASE` / `OPENMX_NC_MAGMA_TURN_RELEASE` apply to the libraries actually used, including retries. The memory-limited collinear cluster spin path also releases both native and real MAGMA scratch between owners on MI300A. Other GPU policies retain their previous behavior.

Non-collinear DC-LNO retains its dedicated native full-spectrum solver, including on Radeon; the common dispatcher's backend override does not replace that entry point. On MI300A, its local GPU admission also checks the original overlap and Hamiltonian for Hermitian symmetry. A residual above `1e-8 * max(1, max|Aij|)` sends the complete local problem through the existing CPU path without changing either matrix. This threshold is a compatibility criterion, not an eigenvalue or final-SCF error bound. The check addresses a measured Hubbard-enabled NC DC-LNO case whose input Hamiltonian becomes non-Hermitian after the first SCF step; it does not repair that upstream asymmetry. This guard adds no GPU-detection calls in CPU paths, and Radeon skips its matrix scan. `OPENMX_GPU_VERBOSE=1` reports these CPU fallbacks.

For investigation, `OPENMX_CLUSTER_PROFILE=1` prints cumulative NC stages. `OPENMX_GPU_EIGENSOLVER_PROFILE=1` adds actual backend/attempt timings and separates workspace setup, phase transforms, solve, finite-value checks and retry copies. Detailed profiling adds synchronization and should be disabled for final timing comparisons. `OPENMX_GPU_VERBOSE=1` reports the actual backend without those additional synchronizations.

The architecture split, explicit overrides, repeated-input reset, retry restoration and NC buffer lifetimes have host-only regression checks:

```sh
python3 tests/run_gpu_eigen_dispatch.py
python3 tests/run_gemmul8_arch_policy.py
python3 tests/run_nc_mi300a_policy_cpu.py
python3 tests/run_band_noncol_mi300a_workspace_cpu.py
python3 tests/run_cluster_col_serial_workspace_cpu.py
python3 tests/run_dclno_mi300a_hermitian_guard.py
python3 tests/run_mi300a_rank_launcher.py
```

`tools/mi300a_rank_launcher.py` preserves each MPI rank's assigned CPUs before loading OpenMX, supplies explicit OS CPU IDs to `OMP_PLACES`, and records rank/PID/CPU identities in `OPENMX_AFFINITY_DIR`. It requires that the inherited CPU count equal `-nt`. On MI300A, use it inside a scheduler allocation with `HSA_OVERRIDE_CPU_AFFINITY_DEBUG=0` so ROCm helper threads inherit the rank's CPU mask. MPI startup binding reports alone do not establish that the masks remain correct after runtime initialization. The launcher has no GPU detection or solver-policy effects and is only used when explicitly selected.

## Arithmetic precision input

`scf.fp32.enable` defaults to `on`, preserving the device-specific precision
policies. Set it to `off` to disable FP32 eigenvector refinement and
double-float grid/orbital arithmetic, and to perform the VNA projector, force
and stress contractions in FP64. This input setting takes precedence over
the environment's FP32/DF requests and is reset for every input, including
successive `-runtest` cases. Existing float storage formats are unchanged.
GEMMul8 and MAGMA's Ozaki2 setting remain independent:

```text
scf.fp32.enable     off
scf.gemmul8.enable  on
```

## Refined FP32 eigensolver
The dense eigensolves of the SCF loop (cluster and band, collinear and non-collinear) run in FP32 and are then refined to FP64 accuracy, as in the NVIDIA version: all eigenpairs come from rocSOLVER's FP32 divide and conquer (`hipsolverDnSsyevd`/`Cheevd`), then the wanted ones get two Ogita-Aishima Newton steps whose products go through GEMMul8, and a Rayleigh-Ritz step resolves the nearly degenerate, partially occupied clusters. From the second SCF step on, the previous step's vectors serve as a warm start, so most steps need no FP32 eigensolve at all. A Radeon RX 9060 XT (gfx1200) runs FP64 at about 1/13 of its FP32 rate, so this is on by default on consumer GPUs (RDNA and consumer GCN) and off on CDNA, whose FP64 is fast. `OPENMX_EIGEN_REFINE=K` sets the number of refinement steps, 0 turns it off. Problems with n < `OPENMX_EIGEN_REFINE_MIN_N` (default 1000) keep the FP64 eigensolver, whose fixed costs are lower there.

The SCF ends in FP64. A run that stops on a refined step solves that step's Hamiltonian once more in FP64, so the energy density matrix and the forces come from FP64 vectors. The stop test on a refined step also requires the printed NormRD to be below `OPENMX_EIGEN_REFINE_STOP_GUARD` (default 100) times `scf.criterion`, and the last step `scf.maxIter` allows is always FP64. When a refinement cannot run (no room for its buffers, a failing solve), that step falls back to FP64 and reports it at stdout level 2 or higher. When every k-point owner of the one-k-point-per-rank band path fits one GPU turn group and the device has room for all of their refined solves at once, each owner solves its k-point once, in two halves: the FP32 estimates of all k-points give the chemical potential, then every owner finishes its refinement, from the first SCF step on. In serialized turn groups the path solves its k-points twice: pass 1 uses the previous step's chemical potential and parks each basis in host memory, and pass 2 finishes from it with the new one (`OPENMX_BAND_REFINE_BASIS_MB`, default 1024 MiB per rank). The k-dense band paths solve in two passes too.

rocSOLVER's complex divide and conquer of ROCm 7.2 returns NaN eigenvectors with `info = 0` for any complex Hermitian matrix whose elements are all real (the non-collinear Hamiltonian without spin-orbit coupling), and for exactly block-diagonal ones. The FP32 solve therefore works on the unitary similarity D^H A D with random phases (same spectrum) and maps the vectors back. The existing FP64 `zheevd` path does the same in FP64 and now also checks its result for NaNs.

Results on one RX 9060 XT (sidia333: 216 Si atoms; refined default against `OPENMX_EIGEN_REFINE=0`, same binary, 25 SCF steps and a force evaluation). Each pair agrees to within 4e-12 Ha in Utot and 1e-12 Ha/bohr in the forces, with the same number of SCF steps:

| case | ranks | diagonalization (s) FP64 / refined | total (s) FP64 / refined |
|---|---:|---:|---:|
| cluster, non-collinear, n2 = 5616 | 16 | 231 / 111 | 391 / 270 |
| cluster, collinear, n = 2808 | 16 | 46.9 / 12.4 | 143 / 108 |
| band, non-collinear, 2 k-points | 8 | 394 / 232 | 733 / 569 |
| band, collinear, 3 k-points (serialized turns) | 8 | 282 / 102 | 408 / 228 |

The FP64 cluster column already includes a new device-resident non-collinear root solve: the back transform and the density matrix take the vectors on the device. That alone cut the 216-atom non-collinear cluster from 559 s to 391 s.

| variable | default | meaning |
|---|---:|---|
| `OPENMX_EIGEN_REFINE` | device default | refinement steps; 0 = FP64 eigensolver |
| `OPENMX_EIGEN_REFINE_MIN_N` | 1000 | smallest matrix the refinement takes |
| `OPENMX_EIGEN_REFINE_UNTIL` | 0 | printed NormRD below which the rest of the cycle is FP64 (0 = never) |
| `OPENMX_EIGEN_REFINE_STOP_GUARD` | 100 | a stop on a refined step also needs NormRD below this times `scf.criterion` |
| `OPENMX_EIGEN_REFINE_WARM` / `_WARM_BAND` | 1 | warm starts from the previous step's vectors |
| `OPENMX_EIGEN_REFINE_FIRST_ALL` | 0 | 1 refines all states at the first cluster SCF step (default: the occupied ones and the usual margin) |
| `OPENMX_EIGEN_FP32_SOLVER` | rocsolver | `magma` takes MAGMA's FP32 solver first (each retries the other) |
| `OPENMX_GPU_FP32_FP64_RATIO` | by architecture | the throughput ratio behind the default (on at 8 or more) |
| `OPENMX_GEMMUL8_SOLVE_MIN_FREE_AFTER_MB` | 256 | free device memory the products of a dense solve must leave |
| `OPENMX_BAND_REFINE_BASIS_MB` | 1024 | host memory per rank for the parked bases of the two-pass band solves |
| `OPENMX_CLUSTER_NC_DEVICE_SOLVE` | 1 | 0 restores the host-staged non-collinear cluster solve |
| `OPENMX_CLUSTER_NC_DEVICE_KEEP` | 1 on MI300A, 0 otherwise | 1 keeps its device buffers between SCF steps instead of parking the basis on the host |

## Double-float grid integrals and on-the-fly orbitals
The grid integrals of each SCF step, the matrix elements of dVH + Vxc + VNA (`Set_Hamiltonian`) and the density on the grid (`Set_Density_Grid`), also run on the FP32 units, as in the NVIDIA version. Each product of an FP32 orbital with the FP64 potential or density matrix element (split into two floats) is formed exactly with an FMA, the partial sums are compensated (TwoSum), and they go into FP64 every 128 grid points. The result is FP64-grade: about 1e-15 of the sum of the magnitudes against a long-double reference, and the same SCF energies and forces as FP64 to within a few 1e-12. gfx1200 has no FP64 atomic add (a compare-and-swap loop), so the matrix-element kernel gives every output to one block. It splits the points of a pair, among them the pair of an atom with its own sphere, over up to 32 blocks and adds their partial sums in a fixed order. On the RX 9060 XT the double-float kernels run 3.6 to 6 times faster than the FP64 ones.

The orbitals are evaluated on the device from the PAO tables, batch by batch of atoms, instead of being read from orbital tables of several GiB (`orbs_otf_hip.cu`, double-float evaluation that matches the tables to one float ulp). The batches are sized to `OPENMX_SETHAM_ONTHEFLY_MB` (256 MiB) of device memory, at least one atom each, and the memory is held only for the duration of the call. That lets every MPI rank use the GPU for these integrals; before, only one rank per k-point group did, and the others ran them on the CPU. The ranks of a node test the free memory and allocate their batch memory one at a time, and a rank that finds no room runs that call on the CPU.

As in the NVIDIA version, the on-the-fly density workspace is planned before dispatch. The AMD planner uses its cached whole-atom arena size and the same 256 MiB reserve as the runtime allocation; it retains the existing automatic enlargement for an atom larger than the default batch bound. If preparation fails on some ranks, the single-owner service can integrate the density. When neither all-rank route nor that service is available, capable ranks still integrate on the GPU while the others use the existing CPU loop. Level 2 reports this mixed path and runtime fallbacks when the situation changes; level 3 adds each rank's workspace shortage. Concurrent allocations can still cause a runtime fallback after a successful preflight.

The GGA-PBE exchange-correlation potential on the grid (`Set_XC_Grid`: the gradient stencil, the functional, the divergence and the non-collinear rotation) also runs on the GPU, in FP64 and in the host's summation order, as in the NVIDIA version (`set_xc_grid_hip.cu`).

The OpenMP offload runtime preallocates a device heap of `LIBOMPTARGET_HEAP_SIZE` bytes (512 MiB by default) in every process, which OpenMX's target regions do not need. With 16 ranks on a 16 GB GPU these heaps held 7 GiB. The runtime reads the variable before `main`, so unless it is set, `openmx` re-executes itself once at startup with 64 MiB, which brings a rank down from about 700 MiB to 240 MiB of device memory.

All four cases of the previous section, 25 SCF steps and a force evaluation on one RX 9060 XT, now take (FP64 eigensolver and grid / refined eigensolver / refined eigensolver with the grid changes and the smaller OpenMP heap; Utot within 5e-12 Ha and forces within 2e-12 Ha/bohr of FP64 in every case, with the same number of SCF steps):

| case | ranks | total (s) | Set_Hamiltonian (s) | Set_Density_Grid (s) |
|---|---:|---:|---:|---:|
| cluster, non-collinear, n2 = 5616 | 16 | 391 / 270 / 217 | 55.5 / 55.4 / 37.4 | 43.6 / 43.5 / 29.0 |
| cluster, collinear, n = 2808 | 16 | 143 / 108 / 89 | 23.4 / 23.4 / 20.0 | 25.7 / 25.7 / 15.0 |
| band, non-collinear, 2 k-points | 8 | 733 / 569 / 371 | 102.6 / 102.3 / 39.3 | 169.3 / 168.2 / 34.0 |
| band, collinear, 3 k-points | 8 | 408 / 228 / 186 | 40.1 / 40.1 / 20.1 | 36.2 / 36.5 / 14.4 |

The memory the smaller heaps return also lets larger band problems keep their eigensolver on the device. ZrB2 2x2 (76 atoms, collinear, 1x3x3 k-points, 8 ranks, 49 SCF steps to `scf.criterion` 1e-9) used to fall back to the CPU eigensolver at every step (2 GiB free against 5.3 GiB needed) and took 360 s; it now runs on the GPU in 178 s (Set_Hamiltonian 84 to 26 s, Set_Density_Grid 71 to 17 s, diagonalization 141 to 87 s).

| variable | default | meaning |
|---|---:|---|
| `OPENMX_GRID_PRECISION` | device default | `df` or `fp64` grid kernels (double-float where the FP32 rate is at least 8 times the FP64 rate) |
| `OPENMX_ORBS_EVAL_PRECISION` | device default | `df` or `fp64` evaluation of the on-the-fly orbitals |
| `OPENMX_SETHAM_ONTHEFLY` | 1 | 0 turns the on-the-fly matrix elements off (tables or CPU) |
| `OPENMX_DENSITY_GRID_ONTHEFLY` | 1 | 0 turns the on-the-fly density off |
| `OPENMX_SETHAM_ONTHEFLY_MB` | 256 | device memory of one batch of atoms |
| `OPENMX_SETHAM_GPU_KOWNER_ONLY` | 0 | 1 keeps the grid integrals on the GPU to one rank per k-point group, as before |
| `OPENMX_XC_GRID_GPU` | 1 | 0 keeps the GGA-PBE exchange-correlation potential on the host |
| `OPENMX_GPU_HEAP_REEXEC` | 1 | 0 keeps the OpenMP runtime's default device heap (no re-execution); setting `LIBOMPTARGET_HEAP_SIZE` also skips it |
| `OPENMX_SETHAM_TIMING` | 0 | 1 prints the phase times of `Set_Hamiltonian` and of the on-the-fly batches |
| `OPENMX_OTF_CHECK` | 0 | 1 compares the on-the-fly orbitals with the tables where both exist |
| `OPENMX_SETHAM_ONTHEFLY_PLAN_CACHE` | 1 | 0 rebuilds the batch plans of the on-the-fly paths at every call |
| `OPENMX_SETHAM_ONTHEFLY_PINNED_MB` | 1024 | page-locked host memory per rank for the plans and transfers (pageable beyond it) |
| `OPENMX_SETDEN_ONTHEFLY_MB` | `OPENMX_SETHAM_ONTHEFLY_MB` | device memory of one batch of the on-the-fly density |
| `OPENMX_DENSITY_GRID_GPU_LOCAL` | 1 | 1: ranks with resident tables integrate the density from them (double-float CSR kernel), the others with on-the-fly tiles; 0: on-the-fly on every rank |

## More from the NVIDIA version: O(N) solvers, forces and robustness
The remaining GPU work of the NVIDIA version is ported as well. Unless stated otherwise the defaults are the NVIDIA ones; where this RX 9060 XT measured otherwise, the AMD default and the reason are given.

**Divide and conquer (DC).** The collinear GPU path stages its matrices with row copies and a device transpose (`hipblasDgeam`, bit-identical), reads the cached overlap in place in its device arena, and refills the host overlap only for a CPU fallback. The non-collinear GPU path is rewritten: it passed host arrays to rocSOLVER, which faults on a discrete GPU without XNACK, and it diagonalized the complex conjugate of the Hamiltonian (as did the NVIDIA OpenACC path), which flips the sign of the imaginary density-matrix parts of magnetic and spin-orbit clusters. The transforms now run on the device and the eigensolve uses MAGMA (or rocSOLVER with the phase similarity), with a CPU fallback per atom. On a 32-atom non-collinear diamond (8 ranks) the diagonalization takes 47 s instead of 475 s on the CPU, with Uele equal to 6e-12 Ha; on a 16-atom bcc Fe with non-collinear moments, 176 s instead of 1664 s.

**DC-LNO.** `OPENMX_DCLNO_PROFILE=1` prints MPI-aggregated stage times and a histogram of the local problem sizes. A local GPU eigensolve that does not converge or runs out of memory is solved again on the CPU, collinear and non-collinear (the non-collinear retry is an AMD addition), and `OPENMX_DCLNO_RETRY_TEST=1` forces that retry for testing. The residue rows of an atom take one allocation. The non-collinear local problems use rocSOLVER `zheevd` with the phase similarity. CG15c-DC-LNO with every local problem forced onto the GPU, and with every one retried on the CPU, gives Utot within 5e-12 Ha of the CPU run.

**Krylov.** The projected-solve GEMMs use the common bridge (native FP64 by default on MI300A, GEMMul8 on Radeon; `OPENMX_KRYLOV_GEMMUL8=0` bypasses the bridge for hipBLAS), their workspace counts in the memory preflight, and projected problems below `OPENMX_KRYLOV_GPU_EIGEN_MIN` (300) go to LAPACK; `OPENMX_KRYLOV_GPU_PROFILE=1` prints the stage times. At 16 ranks per GPU the Krylov GPU path stays off by default (`OPENMX_KRYLOV_GPU=1` turns it on).

**Dense eigensolvers.** A failed FP64 solve is retried from a copy of its input: MAGMA Ozaki-II with `info > 0` with stock MAGMA, and a rocSOLVER solve that fails or returns non-finite vectors with MAGMA (`OPENMX_MAGMA_OZAKI2_RETRY=0` turns it off, `OPENMX_GPUSOLVER_RETRY_TEST=1` solves everything twice for testing). The generic `gpusolver` wrappers keep a per-thread context, return errors instead of aborting, accept host or device arrays, and solve full spectra by divide and conquer; their callers check `info` before using the result. ROCm 7.2's rocSOLVER has further defects that the retry covers: `zheevd` still returns NaN vectors for exactly diagonal complex matrices and needed a larger dither (1e-100) for two-block matrices, `cheevd` needed 1e-25 instead of 1e-30 in the refined FP32 solve, and `dsyevdx`/`zheevdx` with an index range return no eigenpairs for degenerate diagonal matrices.

**Cluster and band solvers.** The non-collinear cluster root solve does its forward transform and the assembly of the 2n x 2n Hamiltonian on the device, keeps its host staging page-locked, and builds the density matrix with three GEMMul8 products (`OPENMX_CLUSTER_GPU_DM_GEMM`, about 10 s less on the 216-atom example). The collinear forward transform takes the full GEMMul8 workspace and returns it right after (`OPENMX_GEMMUL8_FORWARD_UNBLOCKED`), and the cluster solvers return their GEMMul8 workspaces after each dense solve (`OPENMX_CLUSTER_GEMMUL8_TURN_RELEASE`). In the band solvers, the non-collinear one-k-point-per-rank path solves once in two halves when all owners fit (see the refined eigensolver above), the non-collinear k-dense path keeps the transformed overlaps of the geometry (`OPENMX_BAND_NONCOL_OVERLAP_CACHE_MB`, 512) and skips the density-matrix gathers when every owner kept its vectors, and the collinear back transform goes through GEMMul8 (`OPENMX_BAND_GEMMUL8_BACKTRANSFORM`, 6 to 8 s less on the collinear band example). The refinement settings are reset at every input of a `-runtest` suite, and the variables that steer collective paths are read on the root rank.

**Grid integrals.** The on-the-fly paths cache their batch plans (the batches, their descriptors and the overlap-point lists) for the geometry and move every transfer through page-locked memory. The ranks whose Set_Hamiltonian tables are resident integrate the density from them with a double-float CSR kernel while the others use on-the-fly tiles, also for the DC, Krylov and DC-LNO solvers. The on-the-fly state and the density's device buffers are released before the forces. The orbital tables are built by the same trig-free FP64 evaluator as the tiles. `OPENMX_GRID_PRECISION` is parsed as in the NVIDIA version (`df` or `fp64`; any other value selects FP64).

**Forces and VNA projectors.** Force4B admits a rank by the exact sizes of its two workspaces, and has the NVIDIA case-1 streaming (`OPENMX_FORCE4B_CASE1_STREAM`, `_CASE1_STREAM_MB`), the cached-halo rank turns per physical GPU (`OPENMX_FORCE4B_CASE1_TURNS`, `_CASE1_TURN_MAX_RANKS`) and the case-2 streaming (`OPENMX_FORCE4B_CASE2_STREAM`); each is `auto`, 0 or 1. On a GPU whose FP64 rate is at most 1/8 of its FP32 rate, auto leaves the turns and streams off: on the RX 9060 XT with 16 ranks they ran force #4 in 15.9 s (turns) and 34 s (streaming) against 11.5 s on the CPU. The DC, Krylov and DC-LNO forces stay on the CPU there (CG15c-DC-LNO force #4: 4.9 s on the GPU against 1.7 s). The resident batch stays on: the 8-rank collinear band example spends 17.6 s in the forces instead of 22.8 s. `OPENMX_FORCE4B_WEAK_FP64_AUTO=1` gives such a GPU the NVIDIA policy. The HVNA2/HVNA3 projector batches are admitted by their real footprint with a halving pair batch, and the HVNA turns can be switched off (`OPENMX_SETPRO_HVNA_TURNS=0`). `OPENMX_FORCE_RELEASE_SCF_CACHES=0` keeps the SCF grid caches through the forces of a band run.

**Profiles and tests.** `OPENMX_BAND_PROFILE=1` prints the NVIDIA-format stage lines SETHPROF, SETHOTFPROF, SETHOTFDENPROF, SETVPOTPROF and SETDENPROF; `OPENMX_CLUSTER_PROFILE=1` adds CLUSTERPROF / NCCLUSTERPROF lines; `OPENMX_GEMMUL8_TIMING=1` reports every bridge GEMM per rank; `OPENMX_SETPRO_VERBOSE=1` explains the VNA projector admission. `tests/` holds the CPU harnesses (`python3 tests/run_*.py --cc gcc`, which cut the production functions out of the sources and run them against stubs) and short single-process GPU checks (`tests/run_gpusolver_smoke.sh`, `tests/run_force4b_gpu_smoke.py`, `tests/run_band_noncol_wavefunctions_gpu.py`, `tools/run_check_gemmul8_hip.sh`).

The four sidia333 cases of the sections above, ZrB2 2x2 and CG15c-DC-LNO, against the build of the previous section (refined defaults on both; Utot within 4e-11 Ha and forces within 6e-12 Ha/bohr, with the same number of SCF steps except ZrB2, 48 instead of 49):

| case | ranks | total (s) before / now | diagonalization (s) | forces (s) |
|---|---:|---:|---:|---:|
| cluster, non-collinear, n2 = 5616 | 16 | 217 / 183 | 94.4 / 62.8 | 18.5 / 17.9 |
| cluster, collinear, n = 2808 | 16 | 89.1 / 85.7 | 12.6 / 12.4 | 14.3 / 14.5 |
| band, non-collinear, 2 k-points | 8 | 371 / 283 | 227 / 155 | 26.2 / 21.2 |
| band, collinear, 3 k-points | 8 | 186 / 173 | 103 / 94.9 | 22.6 / 17.6 |
| ZrB2 2x2, band, collinear | 8 | 178 / 177 | 87.7 / 87.6 | 19.0 / 19.0 |
| CG15c-DC-LNO | 16 | 115 / 112 | 26.7 / 26.5 | 2.7 / 2.8 |

| variable | default | meaning |
|---|---:|---|
| `OPENMX_DCLNO_PROFILE` | 0 | 1 prints the DC-LNO stage profile |
| `OPENMX_DCLNO_RETRY_TEST` | 0 | 1 redoes every GPU local solve on the CPU (testing) |
| `OPENMX_DCLNO_NONCOL_GPU_THRESHOLD` | 400 | smallest non-collinear local problem solved on the GPU |
| `OPENMX_DC_NONCOL_GPU_THRESHOLD` | 300 | the same for the non-collinear DC clusters (2 NUM) |
| `OPENMX_GPUSOLVER_MIN_FREE_AFTER_MB` | 1536 | device memory the non-collinear DC admission keeps free |
| `OPENMX_KRYLOV_GEMMUL8` | 1 | 0 runs the Krylov GEMMs in plain hipBLAS FP64 |
| `OPENMX_MAGMA_OZAKI2_RETRY` | 1 | 0 turns off the copy and retry of failed dense solves |
| `OPENMX_GPUSOLVER_RETRY_TEST` | 0 | 1 solves every dense eigenproblem again with the next backend (testing) |
| `OPENMX_GPUSOLVER_CACHE_MB` | 64 | per-thread scratch kept by the generic wrappers and the kept retry copy |
| `OPENMX_GPU_EIGENSOLVER_MAGMA_MIN_N` | 0 | MAGMA entry points send problems below this size to rocSOLVER (measurement knob) |
| `OPENMX_CLUSTER_GPU_DM_GEMM` | 1 on MI300A or with GEMMul8 | non-collinear cluster density matrix by native FP64 or GEMMul8 products |
| `OPENMX_GEMMUL8_FORWARD_UNBLOCKED` | 1 | collinear cluster forward transform with the full GEMMul8 workspace |
| `OPENMX_CLUSTER_GEMMUL8_TURN_RELEASE` | 1 (0 on an APU) | GEMMul8 workspaces go back after each cluster dense solve |
| `OPENMX_CLUSTER_GPU_RETAIN_SCRATCH` | keep | 0 returns the collinear owner's scratch after every SCF step |
| `OPENMX_BAND_NONCOL_OVERLAP_CACHE_MB` | 512 | host cache of the transformed overlaps (non-collinear k-dense band) |
| `OPENMX_BAND_NONCOL_CACHE_TRACE` | 0 | 1 reports the non-collinear band caches per rank |
| `OPENMX_BAND_GEMMUL8_BACKTRANSFORM` | 1 | 0 runs the collinear band back transform in plain hipBLAS ZGEMM |
| `OPENMX_FORCE4B_CASE1_STREAM` / `_CASE1_TURNS` / `_CASE2_STREAM` | auto | Force4B streaming and rank turns (0 off, 1 forced) |
| `OPENMX_FORCE4B_WEAK_FP64_AUTO` | 0 | 1 lets auto use the turns and streams on an FP64-weak GPU |
| `OPENMX_FORCE4B_ORDERN_AUTO` | 0 | 1 gives the DC, Krylov and DC-LNO forces the general auto policy |
| `OPENMX_SETPRO_HVNA_TURNS` | 1 | 0 admits the HVNA batches only when every rank of the node fits at once |
| `OPENMX_FORCE_RELEASE_SCF_CACHES` | 1 | 0 keeps the SCF grid caches through the forces of a band run |
| `OPENMX_GEMMUL8_TIMING` | 0 | 1 reports the bridge GEMMs per rank at the end of the SCF |

## Multi-GPU parallelization and MPI
The ranks are split into one group per k-point and each group's eigenproblem is solved on one GPU, so the eigensolver keeps at most as many GPUs busy as there are k-points (`scf.Gpu.Num`, default 30, is only an upper bound). A cluster calculation therefore uses one GPU for the diagonalization however many the node has. Flat MPI with one thread per rank is the measured Radeon configuration below:

```sh
mpirun -np 16 ./openmx input.dat -nt 1
```

On MI300A, also measure hybrid MPI/OpenMP layouts within the same APU allocation. Fewer MPI ranks leave more CPU resources available during the root-only dense solve and change which shared-GPU grid paths are admitted. See the MI300A benchmark below for the tested 24-core configurations.

The NVIDIA hybrid updates through `47556613` are also applied to the AMD
host phases: per-thread Bessel caches in `Set_OLP_Kin`, atom-parallel
received nonlocal products and cluster CPU density-matrix fallback, and
correct scratch sizing for dynamic OpenMP teams in energy/stress routines.
Orbital spline endpoints and the stress XC loop's shared-counter race are
fixed. The AMD cluster path retains its existing GPU density-matrix
assembly; the final density now reuses the SCF's resident GPU tables.
`OPENMX_BAND_PROFILE=1` enables extra host-phase timing diagnostics.

For 16 allocated physical CPU cores, use disjoint rank bindings and keep
BLAS threading at one to avoid nested oversubscription:

```sh
export OMP_NUM_THREADS=4 OMP_DYNAMIC=FALSE OMP_PROC_BIND=close OMP_PLACES=cores
export OPENBLAS_NUM_THREADS=1 BLIS_NUM_THREADS=1 MKL_NUM_THREADS=1
export HSA_OVERRIDE_CPU_AFFINITY_DEBUG=0
mpirun -np 4 --map-by slot:PE=4 --bind-to core ./openmx input.dat -nt 4
# Alternative: OMP_NUM_THREADS=2, -np 8, slot:PE=2, and -nt 2.
```

`tools/run_runtest_l3.py --threads N` sets both `OMP_NUM_THREADS` and `-nt N`,
and defaults to `slot:PE=N` binding for hybrid runs. Explicit `--map-by`
and `--mpirun` settings remain available. GPU kernels do not gain OpenMP
workers; any speedup depends on the proportion of host work and the
memory available per rank. OpenMP reductions can change rounding order.
The 4x4/8x2 build, numerical and placement checks are recorded in
[hybrid_nvidia_port_20261014.txt](hybrid_nvidia_port_20261014.txt).

## Sharing one GPU among many ranks
ROCm needs no MPS-style daemon: the kernels of different processes run concurrently. What limits the rank count on a small card is memory. A rank's HIP/OpenMP context costs about 240 MiB before any physics data (700 MiB with the OpenMP runtime's default device heap, see the previous section), and a hipBLAS handle about 200 MiB more on the ranks that solve. Each GPU stage checks the free device memory before it starts and falls back to the CPU for that stage and SCF iteration when the ranks sharing the device cannot all be accommodated (a ROCm BLAS allocation failing inside a kernel would otherwise terminate the process); the run says so on stderr and stays correct. The knobs:

| variable | default | meaning |
|---|---:|---|
| `OPENMX_GPU` | 1 | 0 demotes the whole run to the CPU paths |
| `OPENMX_CLUSTER_GPU_DIAG_RESERVE_MB` | 256 | headroom kept by the cluster dense diagonalization |
| `OPENMX_KRYLOV_GPU_RESERVE_MB` | 512 | per-rank library headroom of the Krylov projected solves |
| `OPENMX_BAND_GPU_RESERVE_MB` | 512 | the same for the band diagonalizations, charged once per rank sharing the device |
| `OPENMX_SETHAM_GPU` | 1 | Hamiltonian matrix elements on the GPU; the packed orbital tables stay resident across the SCF loop |
| `OPENMX_GEMMUL8_MAX_WORKSPACE_MB` | 256 | GEMMul8 workspace cap per rank |

On a 16 GB Radeon (gfx1200) the 216-atom non-collinear cluster example below needs 16 ranks or fewer for the dense GPU diagonalization to engage; large-memory data-center GPUs are far from this limit.

## Build and install
Requirements: ROCm (developed with 7.2: `amdclang`/`amdflang`, `hipcc`, hipBLAS/hipBLASLt/rocBLAS, hipSOLVER/rocSOLVER, hipSPARSE); Open MPI built with the same ROCm's `amdflang` (the bundled ELPA needs an `mpi.mod` from the compiler that builds it); AMD AOCL (BLIS, libFLAME, ScaLAPACK, AOCL-FFTW) with the AOCC runtime it was built against; autoconf, automake, libtool, m4, python3 and git (GEMMul8 is a submodule).

```sh
git clone --recursive https://github.com/dc1394/openmx4.0_amdgpu.git
cd openmx4.0_amdgpu/source
make -j16 openmx \
  ROCM=/opt/rocm-7.2.0 \
  MPI_HOME=/path/to/openmpi-rocm-amdflang \
  AOCL_HOME=/path/to/aocl/gcc-or-aocc \
  AOCC_LIB=/path/to/aocc/lib
```

The Makefile variables above default to one specific machine; override them for yours. For an existing checkout, run `git submodule update --init --recursive` before rebuilding to select the bundled GEMMul8 version. The first `make` also builds hipMAGMA 2.10.0 (bundled archive), GEMMul8 (submodule) and the gpusolver2 stack, which takes a while. Questions are welcome via GitHub issues or [my X account](https://x.com/dc1394) (Japanese is fine there).

## Benchmarks
Benchmarks of the NVIDIA version this port derives from: https://journals.jps.jp/doi/10.7566/JPSJ.94.124003

### Reproducing GPU tuning with -runtestL3

The September 22–23, 2026 validation used a Radeon RX 9060 XT (16 GiB),
eight MPI ranks and one thread per rank. All 20 original L3 inputs were attempted:
19 completed, and Si1280-LNO stopped at the 16 GiB host-memory reserve after
the MPI process tree reached about 230 GiB RSS. Seventeen completed cases met
absolute tolerances of `1e-7` Ha for energy and `1e-7` Ha/bohr for every force
component. Ni63-O64 and Fe1000 require the numerical caveats in the
[full results and reproduction report](gpu_tuning_l3_20260922.txt).
Five CPU regression cases had exactly identical printed energies and forces.
Ni63-O64's reference-force discrepancy is also present in the untouched
executable. Fe1000 exceeds the strict tolerance with both transform settings;
two runs of the final binary also had a maximum force-component difference of
`2.04e-7` Ha/bohr. Fe1000 is therefore not a strict numerical/repeatability pass.

| L3 input | Original (s) | Tuned (s) | Speedup |
|---|---:|---:|---:|
| GGFF | 2255.05 | 593.10 | 3.80x |
| Pt63 | 26.76 | 13.14 | 2.04x |
| nsV4Bz5 | 35.68 | 17.77 | 2.01x |
| Mn12_148_F | 35.42 | 19.29 | 1.84x |
| CG15c | 238.76 | 189.11 | 1.26x |

These are single-run timings comparing the original runtime defaults against
the code changes plus the three launch settings below. Across the 12 cases
that completed in both configurations, total time fell from 2969.61 to
1136.20 seconds (2.61x). Interrupted cases are excluded from that ratio.
With matched launch settings, C60 took 8.89 -> 5.88 seconds and Mn12_148_F
took 34.51 -> 19.29 seconds; both retained force agreement within `1e-12`.

The GPU construction kernels use team reductions for energy and force integrals,
and reduce the Force3 grid on the device before returning the three force
components per atom pair. The HIP Hamiltonian kernel stages orbital tiles in
shared memory while preserving FP64 accumulation in grid order. Large collinear
cluster transforms (n >= 2048) use the existing GEMMul8 bridge, including its
workspace guard and `scf.gemmul8.enable` setting; density-matrix construction
reuses the most recent device eigenvectors. The CPU calculation loops are unchanged.
The collinear dense-solver memory check includes MAGMA scratch space and sums
simultaneous spin roots sharing the same physical GPU; retained SCF buffers are
credited toward that budget. If both spin roots cannot fit together but one
fits, the GPU processes them in sequence and returns the dense matrices and
library workspaces after each spin. Density-matrix construction uses the saved
host eigenvectors in this case. `OPENMX_CLUSTER_GPU_SERIAL=0` disables this
capacity fallback. If neither mode fits, all ranks release reproducible density
and library device workspaces, preserve the GPU overlap, and retry the same
memory budget once. A solve that still does not fit uses the existing ELPA
fallback. The first switch from GPU to ELPA within an SCF sequence initializes
the distributed overlap before solving. `OPENMX_CLUSTER_GPU_DIAG=0` selects
ELPA directly and skips workspace reclamation. CPU-selected solvers are
unchanged.
The collinear DC-LNO GPU path dispatches smaller local problems on every rank
admitted by its shared-device memory check, using the same rank-to-device map
as the other GPU paths. For matrices of dimension 2048 or larger on a shared
GPU, it retains one GPU owner while other ranks use the existing CPU solver.
The completed CG15c/MCCN measurements support concurrent dispatch for smaller
matrices; the large-matrix trials did not establish an end-to-end improvement.
`OPENMX_DCLNO_GPU_OWNER_THRESHOLD` changes that boundary; zero allows all ranks
at every size for A/B measurements. MAGMA's original algorithm and its internal
CPU/GPU crossover remain unchanged.
Large EH0 integration batches run one MPI rank at a time on each physical GPU
when any rank in that GPU group has at least 8192 pairs. This bounds simultaneous
long kernels and target-data transfers; small batches remain concurrent.
`OPENMX_EH0_GPU_CONCURRENCY=0` disables the admission control, and a positive
value sets the maximum active ranks per GPU. The integral and force formulas
are unchanged. In the measured C1000 case, this removed a long EH0 wait and
completed total-energy evaluation in about 25 seconds with matching forces.
The DC-LNO per-iteration release also returns MAGMA's separate GEMMul8 workspace,
so it does not reduce the memory available to later SCF and force phases.
The DS_VNA projector construction shrinks its pair batch from 256 when the
shared GPU cannot hold all ranks' temporary arrays. The allocation estimate
and target mappings use the same admitted batch size; if even one pair does
not fit, the existing CPU fallback is retained.
The subsequent HVNA contraction budgets its actual neighbour/output tables
and processes only as many ranks together as the shared device can hold,
returning the mapped arrays before admitting the next group of ranks.
The noncollinear multi-k GPU band path can retain compact eigenvectors between
the occupation and density-matrix passes, avoiding repeated eigensolves. This
host cache lives for one SCF call, uses at most 1024 MiB per rank, and is further
limited to 1/32 of the node's available RAM divided by its MPI ranks.
`OPENMX_BAND_NONCOL_KCACHE_MB=0` disables it; a positive value changes the
per-rank cap without bypassing the available-memory limit. GPU k-point groups
interleave MPI owners so their existing concurrency limit can actually run
independent solves together; `OPENMX_BAND_NONCOL_INTERLEAVE_K=0` restores the
original consecutive ordering. The collinear multi-k GPU path uses the same
owner interleaving, controlled by `OPENMX_BAND_COL_INTERLEAVE_K`.
The noncollinear multi-k GPU path also borrows the packed H/S and
imaginary nonlocal matrices already assembled for the current SCF,
avoiding repeated MPI gathers in both k-point passes. All ranks agree
before skipping gathers; unavailable caches retain the original path.
`OPENMX_BAND_NONCOL_PACKED_CACHE=0` restores the original gathers.

The collinear multi-k GPU path also retains transformed overlaps for the current
geometry and compact eigenvectors between the occupation and density-matrix
passes of each SCF step. The host caps are 512 MiB and 1024 MiB per rank,
respectively; each cache is additionally limited to 1/64 of available node RAM
divided by local MPI ranks. `OPENMX_BAND_COL_OVERLAP_CACHE_MB` and
`OPENMX_BAND_COL_KCACHE_MB` set these caps; zero disables the corresponding
cache. Cache misses retain the original GPU solve. Overlaps are invalidated
at the first SCF of each geometry and at run boundaries. The collinear band
GPU crossover is now 400 basis functions, and multi-k matrices of dimension
at most 512 use eight concurrent turns; larger matrices use two. Existing
`OPENMX_BAND_GPU_SWITCH_NUM` and concurrency overrides remain available.
`OPENMX_BAND_CACHE_TRACE=1` reports cache hits.

Memory-limited collinear cluster spin roots retain transformed overlaps on the
host while still releasing their dense device matrices between spins.
`OPENMX_CLUSTER_GPU_OVERLAP_CACHE_MB` defaults to 2048 MiB per root, further
limited to 1/32 of currently available node RAM; zero restores recomputation.
This cache is also invalidated for each new SCF sequence and input.

Density quadrature retains small device tables within a geometry: at most
64 MiB for the single-owner service (`OPENMX_DENSITY_GRID_GPU_CACHE_MB`) and
32 MiB per rank for the local mode (`OPENMX_DENSITY_GRID_GPU_LOCAL_CACHE_MB`).
The local cache is further limited by shared device free memory; its static
index joins are validated once per geometry. The existing explicit
`OPENMX_DENSITY_GRID_GPU_PERSISTENT` setting overrides the owner's automatic
retention policy. Before a collinear band solve falls back for insufficient
device memory, it releases reproducible density, density-matrix, construction
and library scratch buffers and retries the same admission budget. Transformed
overlaps and density host caches remain available; CPU solver arithmetic is
unchanged.

In GPU band mode, the density and shared orbital-table caches are released after
Force3, their last force-stage consumer. This makes their device memory
available to the following VNA projector batches; they are rebuilt for the
next geometry as usual. Other solvers retain their existing memory admission
behavior: the small DC-LNO force batches can run faster in the CPU fallback.
The force kernels and CPU mode are unchanged.

`tools/run_runtest_l3.py` runs original built-in inputs in separate directories
and MPI jobs. `--suite S`, `L`, `L2` and `L3` select `-runtest`, `-runtestL`,
`-runtestL2` and `-runtestL3`; the default remains L3 (20 inputs).
It preserves inputs and reference outputs,
snapshots the executable, and records times, numerical differences and memory
usage in `results.json`. It stops a job when Linux `MemAvailable` falls below
16 GiB or the job exceeds 3600 seconds, then continues with the next case.
These limits are configurable. Interrupted cases are not successful tests;
the runner continues through the suite and then returns a nonzero status.

```sh
python3 tools/run_runtest_l3.py --binary source/openmx --ranks 8 \
  --output work/codex_l3_after \
  --env GPU_MAX_HW_QUEUES=1 --env LIBOMPTARGET_AMDGPU_NUM_HSA_QUEUES=1 \
  --env HSA_ENABLE_SDMA=0
python3 tools/compare_runtest_l3.py work/codex_l3_before work/codex_l3_after
python3 tools/compare_runtest_l3.py --reference work/codex_l3_after
```

Use `--cases C60 GGFF` for selected L3 inputs, `--env OPENMX_GPU=0` for a CPU
comparison, and a fresh output directory for each run. The comparison checks
every force component as well as total energy, atom positions and grid dimensions;
the built-in test's force difference is a signed sum and can hide cancellation.
The comparison tool reads the suite from each run's metadata and rejects
comparisons between different suites.

For the smaller and longer SCF suites, use `--suite S`, `--suite L`, or
`--suite L2` with the same runtime settings and comparison commands. Long
SCF sequences in L2 can require a larger `--timeout`; an interrupted run has
no final energy/force validation and must be reported separately.

The runtime settings above were used for the final measurements with eight MPI
ranks sharing one gfx1200 GPU. With the runtime defaults, Fe1000 completed its
SCF and force phases but waited for many minutes in OpenMP GPU operations
during total-energy evaluation. Limiting both queue pools to one let the same
executable finish, with total-energy evaluation taking about 13 seconds.
Disabling SDMA alone did not resolve that wait; limiting queues alone still
left a HIP host-to-device copy waiting in Pt500. The final configuration combines
both settings with the EH0 admission control described above. These are launch
settings for this measured configuration; the executable does not override the
runtime environment. HIP and OpenMP have separate queue pools, as discussed in this
[ROCm issue](https://github.com/ROCm/legacy-rocm-build/issues/2705).

For GPU A/B measurements, `OPENMX_SETHAM_HIP_KERNEL=scalar` selects the original
Hamiltonian HIP kernel, and `OPENMX_CLUSTER_GPU_GEMM=0` restores native
hipBLAS SYMM/GEMM for the cluster transforms. `OPENMX_SETHAM_TIMING=1`,
`OPENMX_CLUSTER_PROFILE=1` and `OPENMX_FORCE_PROFILE=1` print stage timings;
`OPENMX_DCLNO_GPU_PROFILE=1` reports local GPU solve counts and elapsed time.

#### R-TiO2-1050 GPU memory setting

On the measured 16 GiB RX 9060 XT, `MAGMA_OZAKI2_MAX_WS_MB=384` lets the
collinear solver reclaim enough workspace to keep every R-TiO2-1050
SCF eigensolve on the GPU. This limits the actual MAGMA adapter allocation
as well as its admission estimate; memory reserves are unchanged. Set it
before launching OpenMX. The normal algorithm remains `1stage`.

The full original L2 input completed on v12 in 3318.75 s with 39 SCF steps,
38 workspace reclaims and no dense-solver CPU fallback. Reference errors
were 5.92e-9 Ha in energy and 4.15e-10 Ha/bohr in the maximum force component,
both below the existing 1e-7 limits. Construction and force stages still
use their existing memory-based CPU fallbacks. The baseline aborted at
SCF2, so this is a completion/accuracy result, not a baseline speed ratio.
Validation resumed on October 1 and the scheduled tests and final audit
finished on October 3, 2026. All seven L2 cases completed with this cap;
six passed the strict reference comparison. Fe1000 completed at SCF 380,
but its reference-energy difference of `1.01369e-7` Ha narrowly exceeds
the unchanged `1e-7` limit. The baseline also fails that reference check
(`1.09590e-7` Ha); the candidate/baseline energy and maximum-force differences
are `8.22e-9` Ha and `8.34e-9` Ha/bohr, both passing. The final audit retains
these two failed reference checks, with no pending tests.

Same-process integration passed all 14 S inputs and the three selected L
inputs. Fresh consecutive S timings were 106.74 s for the baseline and
107.15 s for v12, with all reference and baseline comparisons passing.
Both timings use the GPU; this is an optimization comparison. Separate
v12 S controls took 114.37 s with `OPENMX_GPU=0` and 106.12 s with GPU
acceleration enabled (7.2% shorter), using eight MPI ranks and one thread
per rank. These single-run results are distinct from the historical
16-rank benchmarks below; this validation did not measure CPU-only L/L2.

The interrupted September 30 and October 1 Pt500 runs remain archived
and are excluded from numerical passes. Test controllers and periodic
notifications have finished. The candidate has not been installed to
`work/openmx`; see the report below for the final results and limitations.

```sh
python3 tools/run_runtest_l3.py --binary source/openmx \
  --output work/codex_R_TiO2_ws384 --suite L2 --cases R-TiO2-1050 \
  --ranks 8 --timeout 10800 \
  --env GPU_MAX_HW_QUEUES=1 --env LIBOMPTARGET_AMDGPU_NUM_HSA_QUEUES=1 \
  --env HSA_ENABLE_SDMA=0 --env OPENMX_SETHAM_TIMING=1 \
  --env OPENMX_FORCE_PROFILE=1 --env OPENMX_CLUSTER_PROFILE=1 \
  --env OPENMX_GPU_VERBOSE=1 --env MAGMA_OZAKI2_MAX_WS_MB=384
python3 tools/compare_runtest_l3.py --reference work/codex_R_TiO2_ws384
```

#### Optional C1000 MAGMA algorithm and CPU affinity experiment

A separate L2 C1000 run with the same v11 binary used `MAGMA_OZAKI2_ALGO=auto`,
`MAGMA_NUM_THREADS=8` and `KMP_AFFINITY=disabled`. On the RX 9060 XT / 3970X,
elapsed time fell from 2029.18 s with the normal v11 settings to 1820.90 s
(1.114×; 10.26% shorter), with 41 SCF steps in both runs. Final energy and
every force component passed the original reference and normal-v11 comparisons
at the existing 1e-7 Ha / Ha/bohr limits. Only C1000 has completed full numerical
validation with these optional settings; the normal suites retain their settings.

This experiment allocates additional CPU cores: native MAGMA workers use CPU IDs
0–7, while the eight MPI ranks use IDs 8–15. `KMP_AFFINITY=disabled` preserves
the workers' explicit affinity across OpenMP regions. The runner keeps
OMP/BLIS/OpenBLAS threads at one. The measured gain includes this extra CPU
allocation and affinity change. Source and defaults are unchanged; OpenMX's
wrapper still selects `1stage` when `MAGMA_OZAKI2_ALGO` is unset.

Reproduce from the repository root with the archived v11 binary and a fresh
output directory; CPU IDs below are specific to the measured host:

```sh
python3 tools/run_runtest_l3.py --binary work/codex_gpu_sll2/openmx.v11 \
  --output work/codex_C1000_auto_affinity --suite L2 --cases C1000 \
  --ranks 8 --timeout 10800 --map-by pe-list=8,9,10,11,12,13,14,15:ordered \
  --env GPU_MAX_HW_QUEUES=1 --env LIBOMPTARGET_AMDGPU_NUM_HSA_QUEUES=1 \
  --env HSA_ENABLE_SDMA=0 --env OPENMX_SETHAM_TIMING=1 \
  --env OPENMX_FORCE_PROFILE=1 --env OPENMX_CLUSTER_PROFILE=1 \
  --env OPENMX_GPU_VERBOSE=1 --env MAGMA_NUM_THREADS=8 \
  --env KMP_AFFINITY=disabled --env MAGMA_OZAKI2_ALGO=auto
python3 tools/compare_runtest_l3.py --reference work/codex_C1000_auto_affinity
python3 tools/compare_runtest_l3.py work/codex_gpu_sll2/final-L2-case-C1000 \
  work/codex_C1000_auto_affinity
```

See the [S/L/L2 tuning report](gpu_tuning_s_l_l2_20260923.txt) for the separate
suite results, C1000 baseline discrepancy and experiment provenance.

### Built-in test suites (-runtest / -runtestL)
Desktop PC: AMD Ryzen Threadripper 3970X (16 of 32 cores used), 256 GB RAM, one AMD Radeon RX 9060 XT (gfx1200, 16 GB); ROCm 7.2.0, Open MPI 5.0.9 built with the ROCm compilers, AOCL 5.2.0; 16 MPI ranks sharing the GPU, flat MPI. GPU columns use the input-file defaults, CPU columns `OPENMX_GPU=0`. The GPU columns were measured again on 2026-10-12 after the ports of the previous sections, with `tools/run_runtest_l3.py` (one MPI job per input); the CPU columns are the earlier runs of the same CPU code:

```sh
mpirun -np 16 ./openmx -runtest  -nt 1                  # GPU (defaults)
OPENMX_GPU=0 mpirun -np 16 ./openmx -runtestL -nt 1     # CPU reference, same binary
```

`-runtest` (14 small systems, 2–60 atoms; seconds from runtest.result):

| input | CPU (s) | GPU (s) |
|---|---:|---:|
| Benzene | 4.25 | 6.42 |
| C60 | 9.59 | 11.07 |
| CO | 6.92 | 11.50 |
| Cr2 | 6.93 | 7.35 |
| Crys-MnO | 11.66 | 9.70 |
| GaAs | 16.83 | 12.84 |
| Glycine | 5.29 | 6.45 |
| Graphite4 | 3.93 | 4.68 |
| H2O-EF | 4.42 | 5.48 |
| H2O | 3.82 | 5.45 |
| HMn | 10.73 | 9.69 |
| Methane | 3.30 | 4.75 |
| Mol_MnO | 7.40 | 7.31 |
| Ndia2 | 4.68 | 4.29 |
| **Total** | **99.76** | **106.98** |

These systems are below the GPU/CPU switching thresholds of the eigensolvers, so only the construction stages differ, and on runs of a few seconds the per-input GPU setup costs more than they save. The point is correctness: all 14 pass with max diff Utot 6.5e-11 Hartree (CPU: 4.7e-11).

`-runtestL` (16 medium/large systems; ratio = CPU / GPU):

| input | atoms | solver | CPU (s) | GPU (s) | ratio |
|---|---:|---|---:|---:|---:|
| 5_5_13COb2 | 155 | band | 93.21 | 65.52 | 1.42 |
| B2C62_Band | 64 | band | 588.52 | 715.16 | 0.82 |
| CG15c-DC-LNO | 650 | dc-lno | 139.69 | 112.27 | 1.24 |
| DIA512-1 | 512 | krylov | 153.99 | 121.70 | 1.27 |
| FeBCC | 16 | band (sp) | 152.16 | 150.20 | 1.01 |
| GEL | 40 | band | 44.82 | 101.96 | 0.44 |
| GFRAG | 54 | cluster | 44.18 | 37.24 | 1.19 |
| GGFF | 40 | band (NC) | 1315.59 | 1445.69 | 0.91 |
| MCCN | 564 | krylov | 274.16 | 264.01 | 1.04 |
| Mn12_148_F | 148 | cluster (sp) | 101.00 | 65.77 | 1.54 |
| N1C999 | 1000 | dc-lno (sp) | 1204.12 | 1079.73 | 1.12 |
| Ni63-O64 | 127 | band (sp) | 91.22 | 63.87 | 1.43 |
| Pt63 | 63 | cluster | 66.48 | 51.14 | 1.30 |
| SialicAcid | 40 | cluster | 20.54 | 17.94 | 1.14 |
| ZrB2_2x2 | 76 | band | 284.33 | 182.19 | 1.56 |
| nsV4Bz5 | 64 | cluster | 123.11 | 68.37 | 1.80 |
| **Total** | | | **4697.12** | **4542.76** | **1.03** |

All 16 pass on the GPU (max diff Utot 2.2e-9 Hartree, on Pt63; CPU 2.3e-9; the official CPU references in `work/large_example/runtestL.result_*` are of the same order, largest on Pt63 in every case). With 16 ranks on one 16 GB desktop card each rank has a few hundred MB, so several dense band diagonalizations and the Krylov solves still run on the CPU; the suite is nonetheless 3% faster than the CPU build now (it was 12% slower before the refined eigensolver, the grid changes and the ports above). GEL (n = 456) loses because the collinear band crossover of 400 was tuned with 8 ranks per GPU; B2C62_Band and GGFF stay slower as well. These suites are correctness tests. The larger GPU gains come from dense diagonalizations that stay on the device: fewer ranks per GPU on a 16 GB card (below), or a data-center GPU with full-rate FP64 and large memory.

### 216-atom non-collinear cluster on the same card
Si, `scf.EigenvalueSolver cluster`, `scf.SpinPolarization NC`, n2 = 5616; 6 SCF iterations + one force evaluation; "CPU version" is standard OpenMX 4.0 built with the same compilers and AOCL:

| build / configuration | ranks | diagonalization (s) | total (s) |
|---|---:|---:|---:|
| CPU version | 18 | 109.3 | 247.1 |
| this code, defaults | 18 | 109.5 | 202.0 |
| this code, defaults | 16 | 99.5 | 202.6 |

At 18 ranks the per-rank contexts exhaust the card and the dense solve falls back to the CPU (the GPU still wins the total through the construction stages); at 16 ranks the dense GPU diagonalization engages and the diagonalization drops 10%. An RDNA GPU runs FP64 at 1/32 of its FP32 rate, so the headroom here is modest.

### AMD Instinct MI300A

#### Validated one-APU comparison, 2026-10-12

After pulling `d11980386c2ac26372488226280958abf1c7cdbf`, the MI300A fixes were built and tested in one allocation: PBS `44384.pbs`, node `a19`, APU/NUMA 2, physical CPU cores 48–71 and one integrated `gfx942` GPU. The environment was ROCm 7.2.0, Open MPI 5.0.10 and AOCL 5.1.0, with BLAS/MAGMA internal threads set to 1 and `HSA_XNACK=1`. Runs were sequential and used the same final binary, except for the explicitly identified old-binary comparison below. Wall times include MPI startup and final force evaluation.

All CPU references below use 24 MPI × 1 OpenMP and `OPENMX_GPU=0`. The main GPU configurations keep refinement off and use the MI300A native-FP64 GEMM/eigensolver policy; the collinear band row additionally sets `OPENMX_BAND_GPU_TURN_GROUP=4` and `OPENMX_BAND_GPU_CACHED_TURN_GROUP=2`. Every layout uses exactly 24 CPU cores. The recorded SCF count is the same for each CPU/GPU pair.

| Calculation | Input | CPU (s) | GPU enabled (s) | CPU/GPU | GPU MPI × OpenMP | SCF steps |
|---|---|---:|---:|---:|---:|---:|
| Non-collinear cluster | [Si216](work/sidia333_nc_cluster/sidia333_nc_cluster.dat) | 360.090 | 117.154 | 3.074 | 8 × 3 | 25 |
| Collinear cluster | [Si216, derived cluster case](work/sidia333/sidia333.dat) | 91.009 | 83.937 | 1.084 | 8 × 3 | 25 |
| Collinear band | [Si216](work/sidia333/sidia333.dat) | 313.559 | 84.818 | 3.697 | 8 × 3 | 25 |
| Non-collinear band | [Si216](work/sidia333_nc/sidia333_nc.dat) | 1777.147 | 305.429 | 5.819 | 8 × 3 | 25 |
| DC | [DIA216](work/DIA216_DC.dat) | 106.171 | 105.301 | 1.008 | 24 × 1 | 21 |
| DC-LNO | [CG15c, 650 atoms](work/large_example/CG15c-DC-LNO.dat) | 82.835 | 78.406 | 1.056 | 24 × 1 | 42 |
| Krylov | [DIA512](work/large_example/DIA512-1.dat) | 100.618 | 91.033 | 1.105 | 24 × 1 | 29 |

Original iteration limits were retained. Only the derived collinear cluster changes `EigenvalueSolver` to `Cluster` and `scf.Kgrid` to `1 1 1`; canonical copies use an absolute `DATA.PATH`. All original input files were preserved. The four cluster/band cases reached their original 25-step limit without meeting the `1e-13` SCF criterion. DC, DC-LNO and Krylov converged within their original limits of 60, 100 and 150. Agreement of the 25-step results does not establish a converged ground state or identical intermediate SCF trajectories.

All seven pairs passed total-energy, every force-component, atomic-position, grid and lattice comparisons. The largest differences were `6.321e-10` Ha in energy and `5.033e-9` Ha/bohr in force, below the respective `1e-7` acceptance limits. For the originally requested NC cluster, the differences were `7.049e-12` Ha and `1.15e-10` Ha/bohr across all 648 force components; its 1987 printed eigenvalues differed by at most `6.84e-10` Ha. DC's overall timing was essentially unchanged. Local eigensolves remained on the CPU in these DC-LNO and Krylov runs, so their timing improvements describe the GPU-enabled application as a whole.

The NC cluster GPU repeat took 112.466 s, giving a measured CPU24/GPU range of 3.074–3.202. Its CPU run at the same 8 × 3 layout took 670.648 s; the table deliberately uses the faster CPU24 reference. The old GPU24 implementation took 625.550 s in the same allocation, compared with 117.154 s for the first new GPU8 × 3 run: 5.340 times faster including the layout change. The old implementation's first attempt aborted inside UCX (`mm_ep.c:458`) at SCF 17; only its successful identical retry enters the comparison, and the failed log is retained.

Additional complete-input measurements support these input-specific options:

| Input and explicit option, 8 MPI × 3 OpenMP | Wall time (s) | CPU24/GPU |
|---|---:|---:|
| NC cluster, `OPENMX_EIGEN_REFINE=2` | 102.607 | 3.509 |
| NC band, `OPENMX_EIGEN_REFINE=2` | 220.398 | 8.063 |
| NC band, `OPENMX_NC_DEVICE_EIGENVECTOR_DM=1` | 292.415 | 6.077 |

These options passed the same energy/force checks. Refinement and device-DM were measured separately; their combination was not measured. The MI300A refinement default remains off: collinear band with refinement took 96.143 s against 92.023 s with the same default turn settings and native FP64. The explicit initial-turn-4/cached-turn-2 setting in the main table took 84.818 s. Collinear cluster refinement (82.666 s) and its GPU24 layout (86.774 s) offered no clear general advantage over the 83.937 s primary run. Small single-run timing differences should not be treated as universal gains.

Within a scheduler allocation containing one APU and its 24 cores, use explicit per-rank CPU placement. Start from the repository root and enter the input directory so its relative `DATA.PATH` resolves correctly. For the native NC cluster configuration:

```sh
cd work/sidia333_nc_cluster
export HSA_XNACK=1 UCX_RCACHE_ENABLE=n LIBOMPTARGET_MEMORY_MANAGER_THRESHOLD=0
export HSA_OVERRIDE_CPU_AFFINITY_DEBUG=0
export OPENMX_GPU=1 OPENMX_EIGEN_REFINE=0
export OPENMX_AFFINITY_DIR="$PWD/rank_affinity_$(date +%Y%m%d_%H%M%S)"
export BLIS_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MAGMA_NUM_THREADS=1
mpirun -np 8 --map-by ppr:8:node:PE=3 --bind-to core --report-bindings \
  python3 ../../tools/mi300a_rank_launcher.py ../openmx sidia333_nc_cluster.dat -nt 3
```

Use `OPENMX_EIGEN_REFINE=2` for the separately validated refinement option. For the faster CPU reference, retain the environment above and use a fresh identity directory:

```sh
export OPENMX_GPU=0
export OPENMX_AFFINITY_DIR="$PWD/rank_affinity_cpu_$(date +%Y%m%d_%H%M%S)"
mpirun -np 24 --map-by ppr:24:node:PE=1 --bind-to core --report-bindings \
  python3 ../../tools/mi300a_rank_launcher.py ../openmx sidia333_nc_cluster.dat -nt 1
```

All 24 final conditions passed validation, including sampled runtime thread masks associated with each rank, disjoint rank CPU masks and their union covering the allocated 24 physical cores. These are sampled observations, not continuous per-thread traces. The tested binary was installed as `work/openmx`, SHA256 `4abd6f847ffc0f210447cb1f390a5f916204fe07c4641d1516d70ffb47cfa148`; the previous executable was backed up and the existing user timing patch was preserved.

The [Japanese final report](work/codex_mi300a_modes_20261012/report_ja.final.txt), [full comparison](work/codex_mi300a_modes_20261012/full.summary.txt), [validation](work/codex_mi300a_modes_20261012/full.validation.json) and [installation record](work/codex_mi300a_modes_20261012/installed_validation.json) contain the settings, hashes, failure history and evidence. Initial implementation/cause-isolation runs remain under `work/codex_mi300a_20261012_66870cjm/`; early runs without the rank launcher are not substituted for this final comparison. The direct MAGMA entry's policy bypass was the main measured bottleneck; native FP64 GEMM, retained NC buffers and execution layout supplied additional improvements. Radeon branches and explicit overrides were checked by policy tests and source review; Radeon hardware was not remeasured in this MI300A investigation.

#### Earlier correctness-suite measurements

The suite tables in this subsection record the implementation before the 2026-10-12 MI300A dispatch and GEMM policy fixes. Their GPU settings are the defaults of that earlier implementation, and their timings do not describe the new defaults.

One APU of a 4-APU MI300A node: 24 Zen 4 cores and one CDNA 3 GPU sharing 128 GB of unified HBM3; ROCm 7.2.0, Open MPI 5.0.10 built with the ROCm compilers, AOCL 5.1.0; 24 MPI ranks on the APU, flat MPI, the same binary for every column. GPU columns use the earlier input-file defaults, CPU columns `OPENMX_GPU=0`:

```sh
export HSA_XNACK=1 UCX_RCACHE_ENABLE=n LIBOMPTARGET_MEMORY_MANAGER_THRESHOLD=0
mpirun -np 24 ./openmx -runtestL -nt 1                  # GPU (defaults)
OPENMX_GPU=0 mpirun -np 24 ./openmx -runtestL -nt 1     # CPU reference, same binary
```

`HSA_XNACK=1` is required for GPU runs on an MI300A: without it the OpenMP-target host mappings that stay alive across the SCF loop slow every kernel of every rank by an order of magnitude.

24 ranks on one GPU is above the sharing limit of the dense band eigensolvers (`OPENMX_BAND_GPU_MAX_DEVICE_RANKS`, default 16), so in this configuration the band diagonalizations, the Krylov projected solves and the resident Hamiltonian tables all keep to their CPU paths by default — on an APU the cores read the same HBM, and 24 Zen 4 cores beat one GPU serializing the small solves of 24 ranks. What stays on the device is the collinear cluster diagonalization (solved by the root rank) and its construction feeds.

`-runtest` (14 small systems; seconds from runtest.result):

| input | CPU (s) | GPU (s) |
|---|---:|---:|
| Benzene | 3.35 | 7.51 |
| C60 | 6.77 | 9.82 |
| CO | 6.49 | 9.94 |
| Cr2 | 5.33 | 6.72 |
| Crys-MnO | 9.29 | 11.54 |
| GaAs | 12.79 | 15.06 |
| Glycine | 3.58 | 5.21 |
| Graphite4 | 3.33 | 5.02 |
| H2O-EF | 3.51 | 5.06 |
| H2O | 3.47 | 6.02 |
| HMn | 7.27 | 8.71 |
| Methane | 2.74 | 4.24 |
| Mol_MnO | 5.55 | 6.86 |
| Ndia2 | 4.04 | 6.28 |
| **Total** | **77.49** | **108.00** |

As on the desktop card these systems sit below the eigensolver switching thresholds, so the GPU column only pays per-input setup. All 14 pass in both columns, max diff Utot 4.4e-11 Hartree on the GPU (CPU: 2.7e-10).

`-runtestL` (16 medium/large systems; ratio = CPU / GPU):

| input | atoms | solver | CPU (s) | GPU (s) | ratio |
|---|---:|---|---:|---:|---:|
| 5_5_13COb2 | 155 | band | 42.19 | 74.34 | 0.57 |
| B2C62_Band | 64 | band | 420.94 | 450.39 | 0.93 |
| CG15c-DC-LNO | 650 | dc-lno | 78.79 | 79.57 | 0.99 |
| DIA512-1 | 512 | krylov | 97.17 | 97.55 | 1.00 |
| FeBCC | 16 | band (sp) | 95.01 | 101.40 | 0.94 |
| GEL | 40 | band | 33.49 | 41.05 | 0.82 |
| GFRAG | 54 | cluster | 20.70 | 52.61 | 0.39 |
| GGFF | 40 | band (NC) | 685.51 | 826.32 | 0.83 |
| MCCN | 564 | krylov | 155.04 | 163.43 | 0.95 |
| Mn12_148_F | 148 | cluster (sp) | 55.30 | 97.15 | 0.57 |
| N1C999 | 1000 | dc-lno (sp) | 748.48 | 844.70 | 0.89 |
| Ni63-O64 | 127 | band (sp) | 61.18 | 93.49 | 0.65 |
| Pt63 | 63 | cluster | 38.39 | 78.41 | 0.49 |
| SialicAcid | 40 | cluster | 12.81 | 17.47 | 0.73 |
| ZrB2_2x2 | 76 | band | 159.90 | 161.30 | 0.99 |
| nsV4Bz5 | 64 | cluster | 67.20 | 97.44 | 0.69 |
| **Total** | | | **2772.11** | **3276.62** | **0.85** |

All 16 pass in both columns (max diff Utot 2.5e-9 Hartree on the GPU, largest on Pt63 as in the official references; CPU 1.2e-9). With the demoted stages on the CPU the O(N) and band inputs run within a few percent of the CPU reference — the difference there is mostly the fixed cost of keeping the ROCm runtime and `HSA_XNACK=1` active. The remaining gap is concentrated in the collinear cluster inputs (GFRAG, Pt63, Mn12, and the gamma-point-only 5_5_13COb2, which OpenMX reroutes to the cluster solver): their dense solve is collected onto the root rank while the other 23 ranks wait, which loses to 24 cores working in parallel at these sizes.

With that earlier implementation, these correctness suites ran fastest with `OPENMX_GPU=0` at 24 ranks per APU. A separate collinear band measurement (n=2808) at 8 ranks per APU used hipSOLVER for the full-spectrum dense eigensolve in 0.13–0.18 s, while the same rank count on the CPU took seconds. This also stays below `OPENMX_BAND_GPU_MAX_DEVICE_RANKS`, whose default is 16.

One practical note on this machine: long 24-rank suite runs occasionally abort in a UCX shared-memory assertion (`mm_ep.c:458`) of the system Open MPI 5.0.10/UCX build, at a random input and independent of the physics; single inputs and reruns pass unchanged.

## Important notes
GPU-accelerated OpenMX pays off for systems of hundreds of atoms with a dense solver; for fewer than a hundred atoms use standard OpenMX or `scf.eigen.lib elpa2`. Please use with caution as it may contain bugs — reports via GitHub issues or [my X account](https://x.com/dc1394) are appreciated.

## License

This project is a derivative work of **OpenMX** and is licensed under the
**GNU General Public License v3.0 or later (GPL-3.0-or-later)**, consistent
with the upstream OpenMX license. See the [LICENSE](LICENSE) file for the
full license text.

```
SPDX-License-Identifier: GPL-3.0-or-later
```

### Upstream Project

- **OpenMX** (Open source package for Material eXplorer), version 4.0 — <https://www.openmx-square.org/>
- Copyright (c) Taisuke Ozaki and OpenMX contributors — GNU General Public License v3.0 or later

The original OpenMX source code retains its original copyright notices and
license headers. Modifications made in this project (GPU acceleration for
the AMD HIP backend) are also licensed under GPL-3.0-or-later.

### Third-Party Components

Each component retains its original license; the original license files are
inside the respective source trees/archives.

- **GEMMul8** — <https://github.com/RIKEN-RCCS/GEMMul8> (submodule at `source/third_party/GEMMul8`, v3.5.2) — Copyright (c) 2025- RIKEN R-CCS, responsible developer Yuki Uchino — MIT License. If you use this project in academic work, please also cite the GEMMul8 upstream references.
- **MAGMA** 2.10.0 — <https://icl.utk.edu/magma/> (archive at `source/third_party/magma/`, built as hipMAGMA) — Copyright (c) The University of Tennessee — BSD 3-Clause License.
- **ELPA** 2026.02 — <https://elpa.mpcdf.mpg.de/> (archive under `source/third_party/dist/`, used by `gpusolver2`; the `elpa1`/`elpa2` paths use the ELPA 2018.05 embedded in upstream OpenMX) — Copyright (c) the ELPA consortium — GNU Lesser General Public License v3.0.
- **COSMA** 2.8.4, **COSTA**, **Tiled-MM** — <https://github.com/eth-cscs/COSMA>, <https://github.com/eth-cscs/COSTA>, <https://github.com/eth-cscs/Tiled-MM> (archives under `source/third_party/dist/`, used by `gpusolver2`) — Copyright (c) ETH Zürich (parts: Advanced Micro Devices, Inc.) — BSD 3-Clause License.

ROCm's hipBLAS/rocBLAS/hipSOLVER/rocSOLVER and AMD AOCL's BLIS/libFLAME/ScaLAPACK/AOCL-FFTW are linked at build time and not distributed with this repository.

### License Compatibility Summary

| Component | Original License | Compatible with GPL v3 |
|-----------|------------------|------------------------|
| OpenMX (upstream) | GPL-3.0-or-later | — (same license) |
| GPU modifications (this project) | GPL-3.0-or-later | — (same license) |
| GEMMul8 | MIT | Yes (permissive → strong copyleft) |
| MAGMA | BSD-3-Clause | Yes (permissive → strong copyleft) |
| ELPA (2018.05 embedded; 2026.02 for gpusolver2) | LGPL-3.0 | Yes (LGPL v3 code may be conveyed under GPL v3) |
| COSMA (with COSTA, Tiled-MM) | BSD-3-Clause | Yes (permissive → strong copyleft) |
