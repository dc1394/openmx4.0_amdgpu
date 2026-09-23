# openmx4.0_amdgpu

## What does this code do?
The AMD GPU (ROCm/HIP) port of [openmx4.0_gpu](https://github.com/dc1394/openmx4.0_gpu), a GPU-accelerated version of [OpenMX](https://www.openmx-square.org/) (first-principles calculations with numerical atomic orbitals). The dense eigensolvers of the band and cluster calculations (collinear and non-collinear), the O(N) solvers (DC, DC-LNO, Krylov) and the heavy construction stages around them (Hamiltonian/overlap assembly, density and orbital grids, forces, charge mixing) run on the GPU. The CUDA/cuBLAS/cuSOLVER code of the NVIDIA version is rewritten on HIP/hipBLAS/hipSOLVER, the OpenACC regions on OpenMP target offloading, and the single-GPU dense eigensolves use [MAGMA](https://icl.utk.edu/magma/) (hipMAGMA). The two trees track each other.

## Code author
Hiroyuki Kawai (Niigata Univ.)</br>
X account: [@dc1394](https://x.com/dc1394)

## How to enable GPU acceleration
GPU acceleration is on by default: `scf.eigen.lib` defaults to `gpusolver`. The conventional CPU paths are selected with

```ini
scf.eigen.lib             elpa2         # CPU (ELPA2) paths; default=gpusolver
```

A run that finds no usable GPU demotes itself to ELPA2, and `OPENMX_GPU=0` forces that demotion on a GPU machine (handy for CPU-vs-GPU comparisons with unmodified inputs).

## Distributed multi-GPU cluster diagonalization (gpusolver2)
With `gpusolver` a cluster calculation (one k-point) diagonalizes on a single GPU. `scf.eigen.lib gpusolver2` (cluster solver only) replaces that diagonalization with [ELPA](https://elpa.mpcdf.mpg.de/) 2026.02 (AMD GPU kernels) + [COSMA](https://github.com/eth-cscs/COSMA) (ROCm backend), engaging every rank and every GPU across nodes. A solve that does not fit in GPU memory falls back to the ELPA CPU kernels / ScaLAPACK; solves below n=256 stay on the CPU kernels. `OPENMX_GS2_ELPA_GPU` and `OPENMX_GS2_GEMM_GPU` (1 = GPU, 0 = CPU, unset = decide from free memory) override the two decisions; on a VRAM-limited card shared by many ranks use `OPENMX_GS2_GEMM_GPU=0`. ELPA, COSMA, COSTA and Tiled-MM are bundled as source archives under `source/third_party/dist/` and built by the first `make` (no network needed; autoconf, automake, libtool, m4 and python3 required). The `elpa1`/`elpa2` paths keep the ELPA 2018.05 embedded in OpenMX.

## GEMMul8
The large dense matrix multiplications of the GPU eigensolver path run through [GEMMul8](https://github.com/RIKEN-RCCS/GEMMul8) v3.3.0, which emulates FP64 GEMM on the INT8 matrix cores (Ozaki scheme II) — effective on consumer GPUs with limited FP64 throughput, with total energies agreeing to ~1e-10 Hartree in our tests. `scf.gemmul8.enable off` switches to plain hipBLAS FP64. Its memory-saving mode is on by default with a 256 MiB per-rank workspace cap (`OPENMX_GEMMUL8_MAX_WORKSPACE_MB`; 0 = uncapped).

## Multi-GPU parallelization and MPI
The ranks are split into one group per k-point and each group's eigenproblem is solved on one GPU, so the eigensolver keeps at most as many GPUs busy as there are k-points (`scf.Gpu.Num`, default 30, is only an upper bound). A cluster calculation therefore uses one GPU for the diagonalization however many the node has — give it one GPU and more ranks, or use `gpusolver2`. Hybrid MPI/OpenMP brings no speedup here: use flat MPI with one thread per rank,

```sh
mpirun -np 16 ./openmx input.dat -nt 1
```

## Sharing one GPU among many ranks
ROCm needs no MPS-style daemon: the kernels of different processes run concurrently. What limits the rank count on a small card is memory — every rank's HIP/OpenMP context costs roughly 0.5–1 GB before any physics data. Each GPU stage checks the free device memory before it starts and falls back to the CPU for that stage and SCF iteration when the ranks sharing the device cannot all be accommodated (a ROCm BLAS allocation failing inside a kernel would otherwise terminate the process); the run says so on stderr and stays correct. The knobs:

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

The Makefile variables above default to one specific machine; override them for yours. The first `make` also builds hipMAGMA 2.10.0 (bundled archive), GEMMul8 (submodule) and the gpusolver2 stack, which takes a while. Questions are welcome via GitHub issues or [my X account](https://x.com/dc1394) (Japanese is fine there).

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
capacity fallback. A solve that cannot fit even one spin uses the existing ELPA
fallback before allocating the dense GPU matrices.
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

`tools/run_runtest_l3.py` runs each of the 20 original inputs with `-runtestL3`
in a separate directory and MPI job. It preserves inputs and reference outputs,
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

### Built-in test suites (-runtest / -runtestL)
Desktop PC: AMD Ryzen Threadripper 3970X (16 of 32 cores used), 256 GB RAM, one AMD Radeon RX 9060 XT (gfx1200, 16 GB); ROCm 7.2.0, Open MPI 5.0.9 built with the ROCm compilers, AOCL 5.2.0; 16 MPI ranks sharing the GPU, flat MPI, the same binary for every column. GPU columns use the input-file defaults, CPU columns `OPENMX_GPU=0`:

```sh
mpirun -np 16 ./openmx -runtest  -nt 1                  # GPU (defaults)
OPENMX_GPU=0 mpirun -np 16 ./openmx -runtestL -nt 1     # CPU reference, same binary
```

`-runtest` (14 small systems, 2–60 atoms; seconds from runtest.result):

| input | CPU (s) | GPU (s) |
|---|---:|---:|
| Benzene | 4.25 | 7.38 |
| C60 | 9.59 | 18.09 |
| CO | 6.92 | 10.59 |
| Cr2 | 6.93 | 8.21 |
| Crys-MnO | 11.66 | 13.14 |
| GaAs | 16.83 | 17.59 |
| Glycine | 5.29 | 6.64 |
| Graphite4 | 3.93 | 5.15 |
| H2O-EF | 4.42 | 5.80 |
| H2O | 3.82 | 6.02 |
| HMn | 10.73 | 11.72 |
| Methane | 3.30 | 4.46 |
| Mol_MnO | 7.40 | 8.40 |
| Ndia2 | 4.68 | 5.12 |
| **Total** | **99.76** | **128.31** |

These systems are below the GPU/CPU switching thresholds of the eigensolvers, so only the construction stages differ, and on runs of a few seconds the per-input GPU setup costs more than they save. The point is correctness: all 14 pass with max diff Utot 3.8e-11 Hartree (CPU: 4.7e-11).

`-runtestL` (16 medium/large systems; ratio = CPU / GPU):

| input | atoms | solver | CPU (s) | GPU (s) | ratio |
|---|---:|---|---:|---:|---:|
| 5_5_13COb2 | 155 | band | 93.21 | 87.88 | 1.06 |
| B2C62_Band | 64 | band | 588.52 | 709.30 | 0.83 |
| CG15c-DC-LNO | 650 | dc-lno | 139.69 | 145.27 | 0.96 |
| DIA512-1 | 512 | krylov | 153.99 | 149.03 | 1.03 |
| FeBCC | 16 | band (sp) | 152.16 | 173.49 | 0.88 |
| GEL | 40 | band | 44.82 | 63.56 | 0.71 |
| GFRAG | 54 | cluster | 44.18 | 52.58 | 0.84 |
| GGFF | 40 | band (NC) | 1315.59 | 1675.38 | 0.79 |
| MCCN | 564 | krylov | 274.16 | 266.85 | 1.03 |
| Mn12_148_F | 148 | cluster (sp) | 101.00 | 107.36 | 0.94 |
| N1C999 | 1000 | dc-lno (sp) | 1204.12 | 1190.41 | 1.01 |
| Ni63-O64 | 127 | band (sp) | 91.22 | 100.52 | 0.91 |
| Pt63 | 63 | cluster | 66.48 | 75.47 | 0.88 |
| SialicAcid | 40 | cluster | 20.54 | 28.00 | 0.73 |
| ZrB2_2x2 | 76 | band | 284.33 | 315.05 | 0.90 |
| nsV4Bz5 | 64 | cluster | 123.11 | 130.38 | 0.94 |
| **Total** | | | **4697.12** | **5270.54** | **0.89** |

All 16 pass on the GPU (max diff Utot 2.6e-9 Hartree; CPU 2.3e-9; the official CPU references in `work/large_example/runtestL.result_*` are of the same order, largest on Pt63 in every case). Read the GPU column for what it is: 16 ranks on one 16 GB desktop card leave each rank a few hundred MB, so the dense band diagonalizations, the Krylov solves and several construction stages are refused by their memory preflights and run on the CPU, and the suite ends up 12% slower on the GPU build; the O(N) inputs come out even or slightly ahead. These suites are correctness tests. The GPU gains come from dense diagonalizations that stay on the device — fewer ranks per GPU on a 16 GB card (below), or the default configuration on a data-center GPU with full-rate FP64 and large memory.

### 216-atom non-collinear cluster on the same card
Si, `scf.EigenvalueSolver cluster`, `scf.SpinPolarization NC`, n2 = 5616; 6 SCF iterations + one force evaluation; "CPU version" is standard OpenMX 4.0 built with the same compilers and AOCL:

| build / configuration | ranks | diagonalization (s) | total (s) |
|---|---:|---:|---:|
| CPU version | 18 | 109.3 | 247.1 |
| this code, defaults | 18 | 109.5 | 202.0 |
| this code, defaults | 16 | 99.5 | 202.6 |

At 18 ranks the per-rank contexts exhaust the card and the dense solve falls back to the CPU (the GPU still wins the total through the construction stages); at 16 ranks the dense GPU diagonalization engages and the diagonalization drops 10%. An RDNA GPU runs FP64 at 1/32 of its FP32 rate, so the headroom here is modest.

### AMD Instinct MI300A
One APU of a 4-APU MI300A node: 24 Zen 4 cores and one CDNA 3 GPU sharing 128 GB of unified HBM3; ROCm 7.2.0, Open MPI 5.0.10 built with the ROCm compilers, AOCL 5.1.0; 24 MPI ranks on the APU, flat MPI, the same binary for every column. GPU columns use the input-file defaults, CPU columns `OPENMX_GPU=0`:

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

In short, at 24 ranks per APU these correctness suites run fastest with `OPENMX_GPU=0`. The GPU pays off on an MI300A when a dense diagonalization dominates and at most `OPENMX_BAND_GPU_MAX_DEVICE_RANKS` ranks share the device: for a 333-atom collinear band system (n=2808) at 8 ranks per APU, hipSOLVER runs the full-spectrum dense eigensolve in 0.13–0.18 s where the same rank count on the CPU takes seconds.

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

- **GEMMul8** — <https://github.com/RIKEN-RCCS/GEMMul8> (submodule at `source/third_party/GEMMul8`, v3.3.0) — Copyright (c) 2025- RIKEN R-CCS, responsible developer Yuki Uchino — MIT License. If you use this project in academic work, please also cite the GEMMul8 upstream references.
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
