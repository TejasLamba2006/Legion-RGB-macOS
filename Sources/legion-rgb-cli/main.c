#include "legion_rgb_usb.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int parse_hex(const char *s, uint8_t rgb[3]) {
    if (s[0] == '#') s++;
    if (strlen(s) != 6) return 0;
    unsigned int v = 0;
    if (sscanf(s, "%6x", &v) != 1) return 0;
    rgb[0] = (v >> 16) & 0xFF;
    rgb[1] = (v >> 8) & 0xFF;
    rgb[2] = v & 0xFF;
    return 1;
}

static void usage(void) {
    fprintf(stderr,
        "Usage: legion-rgb <command> [args] [-b 1|2] [-s 1..4]\n"
        "  static <RRGGBB> [z2 z3 z4]   Solid or 4-zone static color\n"
        "  breath <RRGGBB> [z2 z3 z4]   Breathing effect\n"
        "  smooth                        Rainbow smooth cycle\n"
        "  wave-left | wave-right        Rainbow wave\n"
        "  off                           Turn keyboard lighting off\n"
        "  probe                         Detect connected Lenovo ITE RGB controller\n"
        "Options: -b <1|2> brightness (default 2), -s <1..4> speed (default 2)\n");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        usage();
        return 1;
    }

    if (strcmp(argv[1], "probe") == 0) {
        LegionDeviceInfo info;
        if (legion_rgb_probe(&info) != 0) {
            fprintf(stderr, "No supported Lenovo ITE 4-zone RGB controller found.\n");
            return 1;
        }
        printf("Found: %s (VID=0x%04X PID=0x%04X)\n",
               info.model_name, info.vendor_id, info.product_id);
        return 0;
    }

    const char *cmd = argv[1];
    uint8_t brightness = 2;
    uint8_t speed = 2;
    uint8_t zones[12];
    memset(zones, 0xFF, sizeof(zones));
    int ncolors = 0;

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0 && i + 1 < argc) {
            brightness = (uint8_t)atoi(argv[++i]);
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            speed = (uint8_t)atoi(argv[++i]);
        } else if (ncolors < 4 && parse_hex(argv[i], &zones[ncolors * 3])) {
            ncolors++;
        } else {
            fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            usage();
            return 1;
        }
    }

    if (ncolors == 1) {
        for (int z = 1; z < 4; z++) {
            memcpy(&zones[z * 3], &zones[0], 3);
        }
    }

    LegionEffect effect;
    if (strcmp(cmd, "static") == 0) {
        if (ncolors == 0) {
            fprintf(stderr, "static requires at least one hex color (e.g. 00D4FF)\n");
            return 1;
        }
        effect = LEGION_EFFECT_STATIC;
    } else if (strcmp(cmd, "breath") == 0) {
        if (ncolors == 0) {
            fprintf(stderr, "breath requires at least one hex color (e.g. 00D4FF)\n");
            return 1;
        }
        effect = LEGION_EFFECT_BREATH;
    } else if (strcmp(cmd, "smooth") == 0) {
        effect = LEGION_EFFECT_SMOOTH;
    } else if (strcmp(cmd, "wave-left") == 0) {
        effect = LEGION_EFFECT_WAVE_LEFT;
    } else if (strcmp(cmd, "wave-right") == 0) {
        effect = LEGION_EFFECT_WAVE_RIGHT;
    } else if (strcmp(cmd, "off") == 0) {
        effect = LEGION_EFFECT_OFF;
    } else {
        usage();
        return 1;
    }

    LegionDeviceInfo info;
    char err[256] = {0};
    int rc = legion_rgb_apply(effect, zones, brightness, speed, &info, err, sizeof(err));
    if (rc != 0) {
        fprintf(stderr, "Error: %s\n", err[0] ? err : "failed to apply lighting");
        return 1;
    }
    printf("OK: applied '%s' on %s (brightness=%u speed=%u)\n",
           cmd, info.model_name, brightness, speed);
    return 0;
}
