#ifndef OPENMX_AMDGPU_OPENACC_STUB_H
#define OPENMX_AMDGPU_OPENACC_STUB_H

#include <stddef.h>

typedef enum acc_device_t {
    acc_device_none = 0,
    acc_device_default = 1,
    acc_device_nvidia = 2,
    acc_device_radeon = 3
} acc_device_t;

static inline int acc_get_num_devices(acc_device_t devtype)
{
    (void)devtype;
    return 0;
}

static inline void acc_set_device_num(int devnum, acc_device_t devtype)
{
    (void)devnum;
    (void)devtype;
}

static inline int acc_is_present(const void *data, size_t bytes)
{
    (void)data;
    (void)bytes;
    return 0;
}

#endif
