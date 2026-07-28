#ifndef _SET_HIP_DEFAULT_DEVICE_FROM_LOCAL_RANK_H_
#define _SET_HIP_DEFAULT_DEVICE_FROM_LOCAL_RANK_H_

#include <mpi.h>

int set_hip_default_device_from_local_rank();
int set_hip_default_device_from_local_rank_noncollective(void);

/* Shared rank-to-device map used by every site that binds a rank to a GPU.
   Contiguous blocks of local ranks share a device (block map) instead of the
   old round-robin (local_rank % device_count): the Band solver's k-point
   worlds are contiguous rank blocks whose owner ranks sit world-size apart,
   so a round-robin map can place every k-owner on device 0 and serialize
   their concurrent eigensolves.  The block map spreads the owners across
   the allowed devices while keeping the same number of ranks per device,
   and it must be the ONLY map in the binary: a rank's HIP and OpenMP device
   must stay identical from initialization to the last SCF step.  Set
   OPENMX_GPU_RANK_MAP=mod to restore the old map. */
int openmx_gpu_map_rank_to_device(int local_rank, int local_size, int device_count);

/* Node-local rank/size without communication (launcher-provided envs,
   falling back to MPI_COMM_WORLD, which is exact on single-node runs). */
int openmx_gpu_local_rank_noncollective(void);
int openmx_gpu_local_size_noncollective(void);

/* One-time, noncollective, per-rank answer to "may this rank touch the GPU
   at all?".  Creates the rank's HIP context through error-returning runtime
   calls, verifies a free-memory margin, and forces OpenMP target
   initialization.  Ranks that fail keep the OpenMP initial device and must
   take host code paths. */
int gpu_rank_device_usable(void);

#endif // _SET_HIP_DEFAULT_DEVICE_FROM_LOCAL_RANK_H_
