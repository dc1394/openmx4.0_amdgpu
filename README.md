# openmx4.0_amdgpu

## What does this code do?
This is the **AMD GPU (ROCm/HIP) port** of [openmx4.0_gpu](https://github.com/dc1394/openmx4.0_gpu), a GPU-accelerated version of [OpenMX](https://www.openmx-square.org/), a first-principles calculation code based on numerical atomic orbitals (NAO). The dense eigensolvers of the band calculations (collinear and non-collinear) and of the cluster calculations (collinear and non-collinear), the O(N)-type solvers (DC, DC-LNO, Krylov), and the heavy matrix-construction stages around them (Hamiltonian/overlap assembly, charge-density and orbital grids, forces, charge mixing) are GPU-accelerated. The cluster diagonalization can also be distributed over multiple GPUs and multiple nodes with ELPA (AMD GPU kernels) + COSMA; see below.

Relative to the NVIDIA version, the CUDA/cuBLAS/cuSOLVER code has been rewritten on HIP/hipBLAS/hipSOLVER-rocSOLVER, the OpenACC offload regions have been converted to OpenMP target offloading, and the single-GPU dense eigensolves run through [MAGMA](https://icl.utk.edu/magma/) (hipMAGMA) and hipSOLVER. The two trees track each other: features land first in one and are ported to the other.

## Code author
Hiroyuki Kawai (Niigata Univ.)</br>
X account: [@dc1394](https://x.com/dc1394)

## How to enable GPU acceleration
GPU acceleration is enabled by default: "scf.eigen.lib" defaults to "gpusolver", so no extra input line is required. Writing it explicitly is of course still fine:

```ini
scf.XcType                  GGA-PBE    # LDA|LSDA-CA|LSDA-PW|GGA-PBE
scf.SpinPolarization        off        # On|Off|NC
scf.ElectronicTemperature  300.0       # default=300 (K)
scf.energycutoff           150.0       # default=150 (Ry)
scf.maxIter                 40         # default=40
scf.EigenvalueSolver       band        # DC|GDC|Cluster|Band
scf.Kgrid                  9 9 9       # means n1 x n2 x n3
scf.Mixing.Type           rmm-diisk    # Simple|Rmm-Diis|Gr-Pulay|Kerker|Rmm-Diisk
scf.Init.Mixing.Weight     0.300       # default=0.30
scf.Min.Mixing.Weight      0.001       # default=0.001 
scf.Max.Mixing.Weight      0.700       # default=0.40 
scf.Mixing.History          7          # default=5
scf.Mixing.StartPulay       5          # default=6
scf.criterion             1.0e-10      # default=1.0e-6 (Hartree) 
scf.eigen.lib             gpusolver     # default=gpusolver
```

To run the conventional CPU paths instead, specify "elpa2" or "elpa1":

```ini
scf.eigen.lib             elpa2         # CPU (ELPA2) paths
```

A run that finds no usable GPU demotes itself to ELPA2 automatically, so the default is also safe on machines without an AMD GPU. The environment variable `OPENMX_GPU=0` forces the same demotion on a machine with a GPU, which is convenient for CPU-vs-GPU comparisons with unmodified input files.

## Distributed multi-GPU cluster diagonalization (ELPA GPU + COSMA)
A cluster calculation has only one k-point, so with the default "gpusolver" its dense eigenvalue problem is solved on a single GPU and, on a multi-GPU machine or a multi-node GPU cluster, the other GPUs idle during the diagonalization (see "Multi-GPU parallelization" below). Selecting

```ini
scf.EigenvalueSolver       cluster
scf.eigen.lib              gpusolver2    # ELPA (AMD GPU kernels) + COSMA
```

replaces the cluster diagonalization (collinear and non-collinear) with [ELPA](https://elpa.mpcdf.mpg.de/) 2026.02 (AMD GPU kernels) and [COSMA](https://github.com/eth-cscs/COSMA) (communication-optimal distributed matrix multiplication, ROCm backend), engaging every MPI rank and every GPU. This is the option for machines where the diagonalization must not be confined to one GPU, e.g. one or a few GPUs per node × many nodes. Notes:

- "gpusolver2" supports only `scf.EigenvalueSolver cluster`; any other solver stops with an input error. Everything outside the cluster diagonalization behaves exactly like "gpusolver", and a machine without a usable GPU demotes itself to ELPA2 as usual.
- When the GPU memory cannot hold a solve, that solve automatically falls back to the ELPA CPU kernels / ScaLAPACK instead of aborting the run. Solves below n=256 stay on the CPU kernels by design. `OPENMX_GS2_ELPA_GPU` and `OPENMX_GS2_GEMM_GPU` (=1 always GPU, =0 always CPU, unset = decide from free device memory) override the two decisions separately — on a VRAM-limited card shared by many ranks, `OPENMX_GS2_GEMM_GPU=0` is recommended.
- The required libraries (ELPA, COSMA, COSTA, Tiled-MM, and a private CMake if the system one is too old) are bundled as source archives under `source/third_party/dist/` and are built automatically by the first `make` — no network access is needed for them (autoconf, automake, libtool, m4 and python3 must be installed). The conventional "elpa1"/"elpa2" paths keep using the ELPA 2018.05 embedded in the OpenMX source; only "gpusolver2" links the bundled ELPA 2026.02, whose CPU kernels are built with the SSE/AVX/AVX2 SIMD variants (x86-64-v3 baseline) so the CPU fallback stays fast.

## GEMMul8: FP64 matrix multiplication on integer matrix cores
The large dense matrix multiplications of the GPU eigensolver path are executed through [GEMMul8](https://github.com/RIKEN-RCCS/GEMMul8) (v3.3.0), which emulates FP64 GEMM on the INT8 matrix cores using the Ozaki scheme II. This is enabled by default and is particularly effective on consumer GPUs (Radeon), whose native FP64 throughput is limited, while the total energy stays at the ~1e-10 Hartree agreement level in our tests. To compare with plain hipBLAS FP64 GEMM, it can be switched off:

```ini
scf.gemmul8.enable         off           # default=on
```

GEMMul8's memory-saving mode is wired in and **on by default with a 256 MiB per-rank workspace cap**: a GEMM whose workspace would exceed the cap runs in blocks that fit it, with the same accuracy, instead of claiming multi-GiB workspaces on a device shared by many ranks. `OPENMX_GEMMUL8_MAX_WORKSPACE_MB` overrides the cap (`0` restores the uncapped behavior).

## Multi-GPU parallelization
How many GPUs a run can actually use is bounded by the number of k-points requested with "scf.Kgrid". The MPI ranks are divided into one group per k-point, and the dense eigenvalue problem of each group is solved on a single GPU, so the eigenvalue solver keeps at most as many GPUs busy as there are k-points; any GPU beyond that number stays idle in this part of the calculation. (The Hamiltonian matrix elements and the grid work are distributed over all MPI ranks, and therefore over all GPUs.)

In particular, a cluster calculation — `scf.EigenvalueSolver cluster`, i.e. `scf.Kgrid 1 1 1` — has only one k-point, so with the default "gpusolver" **only one GPU is used for the diagonalization however many GPUs the node has**. Adding GPUs, or raising the upper bound `scf.Gpu.Num` (default 30, which effectively means "use every GPU found"), does not make such a run faster. (A collinear spin-polarized calculation solves the two spins in separate MPI worlds, so it can occupy two GPUs at most.)

Multiple GPUs therefore pay off for band calculations with a k-mesh; for a cluster calculation, either give the job one GPU and more CPU cores / MPI ranks, or select `scf.eigen.lib gpusolver2` (see above), which distributes the cluster diagonalization itself over all ranks and all GPUs.

## MPI vs. hybrid (MPI/OpenMP) parallelization
Use flat MPI. In OpenMX 4.0 GPU, hybrid MPI/OpenMP parallelization is not effective: OpenMP threads can still be requested as usual with the `-nt` option and such runs complete correctly, but they bring no speedup — only MPI parallelization is effective. Assign all the cores you want to use to MPI ranks instead, with one OpenMP thread per rank:

```sh
mpirun -np 16 ./openmx input.dat -nt 1
```

## Sharing one GPU among many ranks
With flat MPI, all the MPI ranks of a node normally share its GPU(s). Unlike CUDA, ROCm needs no MPS-style daemon for this — the kernels of different processes run concurrently on the device out of the box.

What does limit the rank count on a VRAM-poor card is the per-rank footprint: each rank's HIP + OpenMP-offload context costs roughly 0.5–1 GB of device memory before any physics data. The GPU stages preflight their device-memory needs and fall back to the CPU per stage when they do not fit (the run continues and stays correct), but if the *diagonalization* keeps printing its fallback message, the fastest fix is usually fewer ranks. As a data point, on a 16 GB Radeon (gfx1200) the 216-atom non-collinear cluster example below needs 16 ranks or fewer for the dense GPU diagonalization to engage; large-memory data-center APUs (e.g. Instinct MI300A) are far from this limit. The diagonalization preflight keeps a 256 MB headroom by default (`OPENMX_CLUSTER_GPU_DIAG_RESERVE_MB` overrides it).

The O(N) Krylov solver checks the device memory the same way before every SCF iteration: its projected solves need a fixed ~200–300 MB of library workspace per rank on top of their matrices (a ROCm BLAS allocation that fails inside a GEMM terminates the process rather than returning an error, so the check has to come first), and when the ranks sharing the GPU cannot all be given that headroom the iteration runs the CPU BLAS/LAPACK path instead. The per-rank headroom is `OPENMX_KRYLOV_GPU_RESERVE_MB` (default 512 MiB); lowering it on a VRAM-tight card trades safety for GPU use. The dense band diagonalizations (collinear and non-collinear) apply the same rule with `OPENMX_BAND_GPU_RESERVE_MB` (default 512 MiB): every rank sharing the device keeps its own solver context alive during the k-point solves, so the preflight charges the reserve once per rank, not once per concurrently solving rank, and falls back to the CPU eigensolver for that SCF iteration when the sum does not fit. The GPU density-matrix accumulation of that fallback applies the same device-wide rule to its eigenvector uploads, and a k point whose device accumulation still fails is redone on the CPU rather than aborting the run.

## Build and install
Building and installing is more difficult than with standard OpenMX. Requirements:

- **ROCm** (developed and tested with ROCm 7.2): `amdclang`/`amdflang` (ROCm LLVM), `hipcc`, hipBLAS/hipBLASLt/rocBLAS, hipSOLVER/rocSOLVER, hipSPARSE;
- **OpenMPI built with the same ROCm's `amdflang`** — the Fortran `mpi` module is compiler-specific, and the bundled ELPA's `use mpi` must find an `mpi.mod` written by the very compiler that builds it;
- **AMD AOCL** (BLIS, libFLAME, ScaLAPACK, AOCL-FFTW) and the AOCC runtime libraries AOCL was built against;
- autoconf, automake, libtool, m4, python3 (for the bundled ELPA build), and git (GEMMul8 is a submodule).

Clone with the submodule and build from `source/`:

```sh
git clone --recursive https://github.com/dc1394/openmx4.0_amdgpu.git
cd openmx4.0_amdgpu/source
make -j16 openmx \
  ROCM=/opt/rocm-7.2.0 \
  MPI_HOME=/path/to/openmpi-rocm-amdflang \
  AOCL_HOME=/path/to/aocl/gcc-or-aocc \
  AOCC_LIB=/path/to/aocc/lib
```

The Makefile defaults target one specific HPC system; override the variables above for your machine (they are all `?=` assignments). The first `make` also builds the bundled dependencies automatically — hipMAGMA 2.10.0 (source archive included in the repository), GEMMul8 (the submodule checkout), and the ELPA/COSMA stack for "gpusolver2" — which adds some time to the first build. If you're unsure about the build and installation process, feel free to ask in English via GitHub issues or [my X account](https://x.com/dc1394) (Japanese is also acceptable on my X account). I'll assist you as much as I can.

## Benchmarks
For benchmarks of the GPU-accelerated OpenMX this port derives from, please refer to the following literature (measured on NVIDIA GPUs):
https://journals.jps.jp/doi/10.7566/JPSJ.94.124003

### Built-in test suites (-runtest / -runtestL)
The two standard OpenMX test suites were run on a desktop PC — AMD Ryzen Threadripper 3970X (32 cores; 16 used), 256 GB RAM, one AMD Radeon RX 9060 XT (gfx1200, 16 GB) — with ROCm 7.2.0 (AMD clang 22 / amdflang), Open MPI 5.0.9 built with the same ROCm compilers, and AOCL 5.2.0 (AOCC build), 16 MPI ranks sharing the single GPU, flat MPI. The same binary was used for all columns: the GPU columns use the input-file defaults (`scf.eigen.lib gpusolver`, GEMMul8 on), the CPU columns run with `OPENMX_GPU=0`, which demotes the whole run to the CPU (ELPA2) paths.

```sh
# GPU (defaults)
mpirun -np 16 ./openmx -runtest  -nt 1
mpirun -np 16 ./openmx -runtestL -nt 1
# CPU reference (same binary)
OPENMX_GPU=0 mpirun -np 16 ./openmx -runtest  -nt 1
OPENMX_GPU=0 mpirun -np 16 ./openmx -runtestL -nt 1
```

`-runtest` (14 small systems, 2–60 atoms; elapsed seconds from runtest.result):

| input | CPU (s) | GPU (s) |
|---|---:|---:|
| Benzene | 5.70 | 7.65 |
| C60 | 9.53 | 19.91 |
| CO | 7.05 | 11.31 |
| Cr2 | 6.97 | 8.36 |
| Crys-MnO | 11.48 | 13.45 |
| GaAs | 16.77 | 17.56 |
| Glycine | 4.42 | 6.74 |
| Graphite4 | 3.74 | 5.29 |
| H2O-EF | 4.49 | 5.86 |
| H2O | 3.87 | 5.97 |
| HMn | 11.05 | 12.21 |
| Methane | 3.24 | 4.50 |
| Mol_MnO | 7.39 | 8.72 |
| Ndia2 | 4.65 | 5.21 |
| **Total** | **100.36** | **132.75** |

These systems are far below the GPU/CPU switching thresholds of the dense eigensolvers, so the diagonalization runs on the CPU in both columns and only the GPU-accelerated construction stages differ. On runs of a few seconds the per-input GPU setup (device buffers, BLAS/MAGMA handles, the first-touch of the offload regions, repeated for every input of the suite) outweighs what those stages save, so the GPU build is slower here — the point of this table is correctness: all 14 inputs pass on the GPU build with the same accuracy as the CPU paths (max diff Utot 3.8e-11 Hartree on the GPU, 4.7e-11 on the CPU).

`-runtestL` (16 medium/large systems; "ratio" is CPU / GPU):

| input | atoms | solver | CPU (s) | GPU (s) | ratio |
|---|---:|---|---:|---:|---:|
| 5_5_13COb2 | 155 | band | 93.37 | 89.47 | 1.04 |
| B2C62_Band | 64 | band | 586.62 | 664.98 | 0.88 |
| CG15c-DC-LNO | 650 | dc-lno | 139.39 | 145.19 | 0.96 |
| DIA512-1 | 512 | krylov | 153.13 | 147.51 | 1.04 |
| FeBCC | 16 | band (sp) | 151.06 | 187.00 | 0.81 |
| GEL | 40 | band | 44.70 | 54.36 | 0.82 |
| GFRAG | 54 | cluster | 44.23 | 56.77 | 0.78 |
| GGFF | 40 | band (NC) | 1336.86 | 1666.66 | 0.80 |
| MCCN | 564 | krylov | 273.16 | 265.48 | 1.03 |
| Mn12_148_F | 148 | cluster (sp) | 100.65 | 108.73 | 0.93 |
| N1C999 | 1000 | dc-lno (sp) | 1201.71 | 1186.10 | 1.01 |
| Ni63-O64 | 127 | band (sp) | 90.77 | 101.43 | 0.89 |
| Pt63 | 63 | cluster | 66.35 | 81.29 | 0.82 |
| SialicAcid | 40 | cluster | 19.78 | 28.70 | 0.69 |
| ZrB2_2x2 | 76 | band | 282.42 | 312.03 | 0.91 |
| nsV4Bz5 | 64 | cluster | 122.79 | 132.28 | 0.93 |
| **Total** | | | **4706.99** | **5227.99** | **0.90** |

All 16 inputs pass on the GPU build — max diff Utot 2.6e-9 Hartree on the GPU, 2.3e-9 on the CPU, the same order as the official CPU reference results bundled in `work/large_example/runtestL.result_*` (on both, the largest deviation is Pt63). Read the GPU column for what it is: 16 ranks sharing one 16 GB desktop card leave each rank only a few hundred MB of device memory, so on these inputs the dense band diagonalizations, the Krylov projected solves and several construction stages are refused by their device-memory preflights and run on the CPU (the run says so on stderr), and the GPU build ends up 10% slower over the suite: what is left on the GPU (density, Hamiltonian and force stages, some density-matrix accumulations) roughly pays for the per-input GPU setup and the FP64 rate of an RDNA card (1/32 of FP32), no more. The O(N) inputs (DIA512-1, MCCN, N1C999) come out even or slightly ahead; the small band and cluster inputs lose. These suites are correctness tests, not performance showcases — the GPU gains come from dense diagonalizations that actually stay on the device, which on a 16 GB card means fewer ranks per GPU (see the 216-atom example below) and on data-center GPUs with full-rate FP64 and large memory means the default configuration.

### A worked example on a desktop Radeon
216-atom Si non-collinear cluster (`scf.EigenvalueSolver cluster`, `scf.SpinPolarization NC`, matrix dimension n2 = 5616), 6 SCF iterations + one force evaluation, on a Ryzen Threadripper 3970X (16 cores used) with one 16 GB Radeon (gfx1200); "CPU version" is standard (non-GPU) OpenMX 4.0 built with the same compilers and AOCL:

| build / configuration | ranks | diagonalization (s) | total (s) |
|---|---:|---:|---:|
| CPU version | 18 | 109.3 | 247.1 |
| this code, defaults | 18 | 109.5 | 202.0 |
| this code, defaults | 16 | 99.5 | 202.6 |

At 18 ranks the per-rank GPU contexts exhaust the 16 GB card, the dense solve falls back to the CPU (same 109 s as the CPU version), and the GPU still wins the total through the accelerated construction stages. At 16 ranks the dense GPU diagonalization (MAGMA) engages with no extra options and the diagonalization drops by 10%. A desktop RDNA GPU runs FP64 at 1/32 of its FP32 rate, so the headroom here is modest; data-center GPUs with full-rate FP64 benefit far more.

### AMD Instinct MI300A
To be added.

## Important notes
At present, GPU-accelerated OpenMX performs faster than standard OpenMX for calculations involving systems containing hundreds of atoms. For calculations involving systems with fewer than a hundred atoms, standard OpenMX should be used (or set `scf.eigen.lib elpa2` to run the CPU paths of this code). Please use with caution as it may contain bugs.

## About bug reports
I would appreciate it if you could actively report any bugs. Please report them via GitHub issues or send them to [my X account](https://x.com/dc1394). Bug reports sent to my X account can be in English.

## License

This project is a derivative work of **OpenMX** and is licensed under the
**GNU General Public License v3.0 or later (GPL-3.0-or-later)**, consistent
with the upstream OpenMX license. See the [LICENSE](LICENSE) file for the
full license text.

```
SPDX-License-Identifier: GPL-3.0-or-later
```

### Upstream Project

This project is based on:

- **OpenMX** (Open source package for Material eXplorer)
- **Version**: 4.0
- **Upstream**: <https://www.openmx-square.org/>
- **Copyright**: Copyright (c) Taisuke Ozaki and OpenMX contributors
- **License**: GNU General Public License v3.0 or later

The original OpenMX source code retains its original copyright notices and
license headers. Modifications made in this project (GPU acceleration for
the AMD HIP backend) are also licensed under GPL-3.0-or-later.

### Third-Party Components

This project builds and links the following third-party projects. Each
component retains its original license; the original license files are
inside the respective source trees/archives.

#### GEMMul8

- **Source**: <https://github.com/RIKEN-RCCS/GEMMul8> (git submodule at
  `source/third_party/GEMMul8`, pinned to the v3.3.0 release)
- **Copyright**: Copyright (c) 2025- RIKEN R-CCS
- **Responsible developer**: Yuki Uchino (RIKEN Center for Computational Science)
- **License**: MIT License (`MIT`)

GEMMul8 (GEMMulate) is a library for emulating high-precision matrix
multiplication (SGEMM, DGEMM, CGEMM, ZGEMM) using INT8/FP8 matrix engines
based on the Ozaki Scheme II.

If you use this project in academic work, please also cite the GEMMul8
upstream references (see the GEMMul8 repository).

#### MAGMA

- **Source**: <https://icl.utk.edu/magma/> (release archive bundled at
  `source/third_party/magma/magma-2.10.0.tar.gz`, built as hipMAGMA by the
  first `make`)
- **Copyright**: Copyright (c) The University of Tennessee
- **License**: BSD 3-Clause License (`BSD-3-Clause`)

#### ELPA / COSMA (the "gpusolver2" stack)

The distributed multi-GPU cluster diagonalization (`scf.eigen.lib gpusolver2`)
links four additional libraries, bundled as source archives under
`source/third_party/dist/` and built automatically by the first `make`; each
archive carries its original license file:

- **ELPA** 2026.02 — <https://elpa.mpcdf.mpg.de/> — Copyright (c) the ELPA
  consortium — **GNU Lesser General Public License v3.0 (`LGPL-3.0`)**
  (`COPYING/` inside the archive). The conventional "elpa1"/"elpa2" CPU paths
  use the ELPA 2018.05 source embedded in upstream OpenMX under the same
  license.
- **COSMA** 2.8.4 — <https://github.com/eth-cscs/COSMA> — Copyright (c) ETH
  Zürich (parts: Advanced Micro Devices, Inc.) — **BSD 3-Clause License
  (`BSD-3-Clause`)**
- **COSTA** and **Tiled-MM** (COSMA dependencies) —
  <https://github.com/eth-cscs/COSTA>,
  <https://github.com/eth-cscs/Tiled-MM> — Copyright (c) ETH Zürich —
  **BSD 3-Clause License (`BSD-3-Clause`)**

System libraries (ROCm's hipBLAS/rocBLAS/hipSOLVER/rocSOLVER and AMD AOCL's
BLIS/libFLAME/ScaLAPACK/AOCL-FFTW) are linked at build time and are not
distributed with this repository.

### License Compatibility Summary

| Component | Original License | Compatible with GPL v3 |
|-----------|------------------|------------------------|
| OpenMX (upstream) | GPL-3.0-or-later | — (same license) |
| GPU modifications (this project) | GPL-3.0-or-later | — (same license) |
| GEMMul8 | MIT | Yes (permissive → strong copyleft) |
| MAGMA | BSD-3-Clause | Yes (permissive → strong copyleft) |
| ELPA (2018.05 embedded; 2026.02 for "gpusolver2") | LGPL-3.0 | Yes (LGPL v3 code may be conveyed under GPL v3) |
| COSMA (with COSTA, Tiled-MM) | BSD-3-Clause | Yes (permissive → strong copyleft) |
