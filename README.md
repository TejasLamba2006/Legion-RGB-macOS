# Legion RGB macOS

Native macOS SwiftUI app and CLI for controlling 4-zone RGB keyboards on Lenovo Legion, LOQ, and IdeaPad Gaming laptops (2020 to 2024 ITE USB controllers).

I built this after getting macOS running on my Lenovo LOQ 15IRX9. Every RGB tool I found for these keyboards was Linux or Windows only, and calling `IOHIDManager` directly on macOS runs straight into TCC Input Monitoring blocks (`kIOReturnNotPermitted`). Talking to the ITE USB controller directly with a HID `SET_REPORT` control transfer over `IOKit` avoids that completely. No kernel extension, no `libusb`, no `sudo`, and no Input Monitoring prompts.

## What is included

- Self-contained `Legion RGB.app` bundle (drag into `/Applications` and run; no external binary needed)
- Live 30 fps 4-zone keyboard preview with click-to-select zones, per-zone macOS ColorPicker, and a "Sync All Zones" toggle
- 6 lighting modes: Static, Breath, Smooth rainbow, Wave Left, Wave Right, and Off
- Low and High brightness levels plus 1x to 4x animation speed
- 8 built-in presets, persistent settings, and a menu bar icon for quick switching
- Standalone `legion-rgb` CLI for scripts and terminal use

## Supported controllers

Auto-detects any of these 11 Lenovo ITE 4-zone USB controllers (Vendor ID `0x048D`):

| Product ID | Model family |
| --- | --- |
| `0xC995` | Legion Pro (2024) |
| `0xC994` | Legion (2024) |
| `0xC993` | LOQ (2024) |
| `0xC985` | Legion Pro (2023) |
| `0xC984` | Legion (2023) |
| `0xC983` | LOQ (2023) |
| `0xC975` | Legion (2022) |
| `0xC973` | IdeaPad Gaming (2022) |
| `0xC965` | Legion (2021) |
| `0xC963` | IdeaPad Gaming (2021) |
| `0xC955` | Legion (2020) |

Tested directly on hardware with a Lenovo LOQ 15IRX9 (`0x048D:0xC993`, ITE 8295) running macOS Tahoe 26.7.3. The remaining 10 PIDs use the same 33-byte `0xCC` feature report format. Per-key RGB models are not supported.

## Install

Download `Legion-RGB-macOS-app.zip` from the [Releases](../../releases) page, unzip it, and move `Legion RGB.app` to `/Applications`.

Because the app is ad-hoc signed, clear the quarantine attribute if macOS blocks the first launch:

```bash
xattr -dr com.apple.quarantine "/Applications/Legion RGB.app"
```

## Build from source

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`). No external dependencies.

```bash
git clone https://github.com/TejasLamba2006/Legion-RGB-macOS.git
cd Legion-RGB-macOS
make build
```

This outputs:

- `build/Legion RGB.app` (self-contained app bundle)
- `build/legion-rgb` (standalone CLI)

To install both system-wide (`/Applications/Legion RGB.app` and `/usr/local/bin/legion-rgb`):

```bash
make install
```

## CLI usage

```bash
legion-rgb probe                                    # detect connected controller
legion-rgb static 00D4FF -b 2                       # solid color (brightness 1 or 2)
legion-rgb static FF0000 00FF00 0000FF FFFF00 -b 2  # 4 individual zones
legion-rgb breath 00FF66 -b 2 -s 2                  # breathing effect (speed 1 to 4)
legion-rgb smooth -b 2 -s 2                         # rainbow cycle
legion-rgb wave-left -b 2 -s 3                      # wave left
legion-rgb wave-right -b 2 -s 3                     # wave right
legion-rgb off                                      # turn lighting off
```

## How it works

macOS locks `IOHIDDeviceOpen` behind Input Monitoring permissions, which breaks on some Hackintosh configs and adds unnecessary friction for a lighting utility. Instead, `Sources/CLegionRGB/legion_rgb_usb.c` matches the ITE device via `IOServiceGetMatchingService`, opens an `IOUSBDeviceInterface`, and sends a standard USB HID class `SET_REPORT` control transfer (`bmRequestType=0x21`, `bRequest=0x09`, `wValue=0x03CC`, 33-byte payload) directly to interface 0 (falling back to interface 1 if needed).

Both the SwiftUI app and the CLI compile against that same C file, so `Legion RGB.app` ships as a single binary with zero runtime dependencies.

## Credits

The 33-byte ITE `0xCC` feature report layout and PID table are documented by [4JX/L5P-Keyboard-RGB](https://github.com/4JX/L5P-Keyboard-RGB).

## License

MIT. See [LICENSE](LICENSE).
