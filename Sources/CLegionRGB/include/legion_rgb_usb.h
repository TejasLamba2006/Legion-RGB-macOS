#ifndef LEGION_RGB_USB_H
#define LEGION_RGB_USB_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t vendor_id;
    uint16_t product_id;
    char model_name[64];
} LegionDeviceInfo;

typedef enum {
    LEGION_EFFECT_STATIC     = 0x01,
    LEGION_EFFECT_BREATH     = 0x03,
    LEGION_EFFECT_WAVE_LEFT  = 0x04,
    LEGION_EFFECT_WAVE_RIGHT = 0x14,
    LEGION_EFFECT_SMOOTH     = 0x06,
    LEGION_EFFECT_OFF        = 0x00
} LegionEffect;

// Probes the USB registry for any of the 11 supported Lenovo ITE 4-zone RGB PIDs.
// Returns 0 on match and fills `out`, or -1 if no supported controller is attached.
int legion_rgb_probe(LegionDeviceInfo *out);

// Sends a 33-byte HID Feature SET_REPORT (Report ID 0xCC) directly over USB control transfer.
// `zones` must be 12 bytes (4 zones x RGB) for STATIC/BREATH; ignored otherwise.
// `brightness`: 1 (Low) or 2 (High). `speed`: 1..4.
// Returns 0 on success, non-zero IOReturn or -1 on error (writes message to err_buf if non-NULL).
int legion_rgb_apply(LegionEffect effect,
                     const uint8_t zones[12],
                     uint8_t brightness,
                     uint8_t speed,
                     LegionDeviceInfo *out_dev,
                     char *err_buf,
                     size_t err_buf_len);

#ifdef __cplusplus
}
#endif

#endif
