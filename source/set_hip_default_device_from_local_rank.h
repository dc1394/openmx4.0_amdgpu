#ifndef _SET_HIP_DEFAULT_DEVICE_FROM_LOCAL_RANK_H_
#define _SET_HIP_DEFAULT_DEVICE_FROM_LOCAL_RANK_H_

#include <mpi.h>

int set_hip_default_device_from_local_rank();
int set_hip_default_device_from_local_rank_noncollective(void);

#endif // _SET_HIP_DEFAULT_DEVICE_FROM_LOCAL_RANK_H_
