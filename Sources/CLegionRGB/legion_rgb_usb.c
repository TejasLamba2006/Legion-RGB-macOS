#include "legion_rgb_usb.h"

#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define ITE_VENDOR_ID 0x048D

typedef struct {
    uint16_t pid;
    const char *name;
} KnownDevice;

static const KnownDevice kKnownDevices[] = {
    { 0xC995, "Legion Pro (2024)" },
    { 0xC994, "Legion (2024)" },
    { 0xC993, "LOQ (2024)" },
    { 0xC985, "Legion Pro (2023)" },
    { 0xC984, "Legion (2023)" },
    { 0xC983, "LOQ (2023)" },
    { 0xC975, "Legion (2022)" },
    { 0xC973, "IdeaPad Gaming (2022)" },
    { 0xC965, "Legion (2021)" },
    { 0xC963, "IdeaPad Gaming (2021)" },
    { 0xC955, "Legion (2020)" },
};

static const size_t kKnownDeviceCount = sizeof(kKnownDevices) / sizeof(kKnownDevices[0]);

static io_service_t find_matching_usb_service(LegionDeviceInfo *out_info) {
    for (size_t i = 0; i < kKnownDeviceCount; i++) {
        CFMutableDictionaryRef match = IOServiceMatching(kIOUSBDeviceClassName);
        if (!match) continue;

        int vid = ITE_VENDOR_ID;
        int pid = kKnownDevices[i].pid;
        CFNumberRef vref = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
        CFNumberRef pref = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
        CFDictionarySetValue(match, CFSTR(kUSBVendorID), vref);
        CFDictionarySetValue(match, CFSTR(kUSBProductID), pref);
        CFRelease(vref);
        CFRelease(pref);

        io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, match);
        if (svc != IO_OBJECT_NULL) {
            if (out_info) {
                out_info->vendor_id = ITE_VENDOR_ID;
                out_info->product_id = kKnownDevices[i].pid;
                snprintf(out_info->model_name, sizeof(out_info->model_name),
                         "%s (0x%04X)", kKnownDevices[i].name, kKnownDevices[i].pid);
            }
            return svc;
        }
    }
    return IO_OBJECT_NULL;
}

int legion_rgb_probe(LegionDeviceInfo *out) {
    io_service_t svc = find_matching_usb_service(out);
    if (svc == IO_OBJECT_NULL) {
        return -1;
    }
    IOObjectRelease(svc);
    return 0;
}

static void set_err(char *buf, size_t len, const char *msg) {
    if (buf && len > 0) {
        snprintf(buf, len, "%s", msg);
    }
}

int legion_rgb_apply(LegionEffect effect,
                     const uint8_t zones[12],
                     uint8_t brightness,
                     uint8_t speed,
                     LegionDeviceInfo *out_dev,
                     char *err_buf,
                     size_t err_buf_len) {
    if (brightness < 1) brightness = 1;
    if (brightness > 2) brightness = 2;
    if (speed < 1) speed = 1;
    if (speed > 4) speed = 4;

    uint8_t payload[33];
    memset(payload, 0, sizeof(payload));
    payload[0] = 0xCC;
    payload[1] = 0x16;

    switch (effect) {
        case LEGION_EFFECT_STATIC:
            payload[2] = 0x01;
            if (zones) memcpy(&payload[5], zones, 12);
            break;
        case LEGION_EFFECT_BREATH:
            payload[2] = 0x03;
            if (zones) memcpy(&payload[5], zones, 12);
            break;
        case LEGION_EFFECT_SMOOTH:
            payload[2] = 0x06;
            break;
        case LEGION_EFFECT_WAVE_LEFT:
            payload[2] = 0x04;
            payload[19] = 0x01;
            break;
        case LEGION_EFFECT_WAVE_RIGHT:
            payload[2] = 0x04;
            payload[18] = 0x01;
            break;
        case LEGION_EFFECT_OFF:
            payload[2] = 0x01;
            break;
        default:
            set_err(err_buf, err_buf_len, "Unsupported effect");
            return -1;
    }

    payload[3] = speed;
    payload[4] = brightness;

    // Retry briefly if the ITE controller is mid-USB-reset (kIOReturnNotReady / 0xe00002be).
    LegionDeviceInfo info;
    memset(&info, 0, sizeof(info));
    IOCFPlugInInterface **plug_in = NULL;
    kern_return_t kr = kIOReturnNoDevice;
    for (int attempt = 0; attempt < 5; attempt++) {
        io_service_t usb_dev = find_matching_usb_service(&info);
        if (usb_dev == IO_OBJECT_NULL) {
            usleep(60000);
            continue;
        }
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(
            usb_dev, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug_in, &score);
        IOObjectRelease(usb_dev);
        if (kr == KERN_SUCCESS && plug_in) {
            break;
        }
        plug_in = NULL;
        usleep(60000);
    }

    if (kr == kIOReturnNoDevice) {
        set_err(err_buf, err_buf_len, "No supported Lenovo ITE 4-zone RGB controller found");
        return -1;
    }
    if (out_dev) *out_dev = info;
    if (kr != KERN_SUCCESS || !plug_in) {
        char tmp[128];
        snprintf(tmp, sizeof(tmp), "IOCreatePlugInInterfaceForService failed (0x%x)", kr);
        set_err(err_buf, err_buf_len, tmp);
        return (int)kr;
    }

    IOUSBDeviceInterface **dev = NULL;
    HRESULT hr = (*plug_in)->QueryInterface(
        plug_in, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&dev);
    (*plug_in)->Release(plug_in);
    if (hr != 0 || !dev) {
        char tmp[128];
        snprintf(tmp, sizeof(tmp), "QueryInterface(IOUSBDeviceInterface) failed (0x%x)", (unsigned)hr);
        set_err(err_buf, err_buf_len, tmp);
        return -1;
    }

    // HID Class SET_REPORT: Host-to-Device, Class, Interface; Feature report ID 0xCC.
    IOUSBDevRequest req;
    req.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface);
    req.bRequest      = 0x09;
    req.wValue        = (0x03 << 8) | 0xCC;
    req.wIndex        = 0;
    req.wLength       = sizeof(payload);
    req.pData         = payload;
    req.wLenDone      = 0;

    kr = (*dev)->DeviceRequest(dev, &req);
    if (kr != kIOReturnSuccess) {
        req.wIndex = 1;
        req.wLenDone = 0;
        kr = (*dev)->DeviceRequest(dev, &req);
    }

    (*dev)->Release(dev);

    if (kr != kIOReturnSuccess) {
        char tmp[128];
        snprintf(tmp, sizeof(tmp), "USB SET_REPORT failed (0x%x, sent %u bytes)", kr, req.wLenDone);
        set_err(err_buf, err_buf_len, tmp);
        return (int)kr;
    }
    return 0;
}
