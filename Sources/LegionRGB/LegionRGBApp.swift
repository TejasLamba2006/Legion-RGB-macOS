import SwiftUI
import AppKit
import Combine

// MARK: - Models

enum RGBEffect: String, CaseIterable, Identifiable, Codable {
    case staticColor = "static"
    case breath = "breath"
    case smooth = "smooth"
    case waveLeft = "wave-left"
    case waveRight = "wave-right"
    case off = "off"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .staticColor: return "Static"
        case .breath:      return "Breath"
        case .smooth:      return "Smooth"
        case .waveLeft:    return "Wave Left"
        case .waveRight:   return "Wave Right"
        case .off:         return "Off"
        }
    }

    var icon: String {
        switch self {
        case .staticColor: return "lightbulb.fill"
        case .breath:      return "waveform.path.ecg"
        case .smooth:      return "rainbow"
        case .waveLeft:    return "arrow.left.circle.fill"
        case .waveRight:   return "arrow.right.circle.fill"
        case .off:         return "power"
        }
    }

    var cEffect: LegionEffect {
        switch self {
        case .staticColor: return LEGION_EFFECT_STATIC
        case .breath:      return LEGION_EFFECT_BREATH
        case .smooth:      return LEGION_EFFECT_SMOOTH
        case .waveLeft:    return LEGION_EFFECT_WAVE_LEFT
        case .waveRight:   return LEGION_EFFECT_WAVE_RIGHT
        case .off:         return LEGION_EFFECT_OFF
        }
    }

    var usesZoneColors: Bool {
        self == .staticColor || self == .breath
    }

    var usesSpeed: Bool {
        self == .breath || self == .smooth || self == .waveLeft || self == .waveRight
    }
}

struct RGBColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&v)
        self.r = Double((v >> 16) & 0xFF) / 255.0
        self.g = Double((v >> 8) & 0xFF) / 255.0
        self.b = Double(v & 0xFF) / 255.0
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.r = Double(c.redComponent)
        self.g = Double(c.greenComponent)
        self.b = Double(c.blueComponent)
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    var bytes: (UInt8, UInt8, UInt8) {
        (
            UInt8(max(0, min(255, Int((r * 255.0).rounded())))),
            UInt8(max(0, min(255, Int((g * 255.0).rounded())))),
            UInt8(max(0, min(255, Int((b * 255.0).rounded()))))
        )
    }

    var hex: String {
        let (ri, gi, bi) = bytes
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}

struct RGBPreset: Identifiable {
    let id = UUID()
    let name: String
    let effect: RGBEffect
    let zones: [RGBColor]
    let speed: Int
    let brightness: Int
}

struct SavedState: Codable {
    var effect: RGBEffect
    var zones: [RGBColor]
    var brightness: Int
    var speed: Int
    var linkZones: Bool
}

// MARK: - Controller (Calls Embedded IOKit USB HID Driver Directly)

@MainActor
final class RGBController: ObservableObject {
    @Published var effect: RGBEffect = .staticColor
    @Published var zones: [RGBColor] = [
        RGBColor(hex: "00D4FF"),
        RGBColor(hex: "4D7CFF"),
        RGBColor(hex: "A855F7"),
        RGBColor(hex: "FF2E93")
    ]
    @Published var selectedZone: Int = 0
    @Published var linkZones: Bool = false
    @Published var brightness: Int = 2
    @Published var speed: Int = 2
    @Published var statusText: String = "Scanning USB..."
    @Published var deviceName: String = "ITE RGB"
    @Published var isConnected: Bool = false
    @Published var lastError: String? = nil

    private var debounceTask: Task<Void, Never>?
    private let stateURL: URL

    static let presets: [RGBPreset] = [
        RGBPreset(name: "Cyberpunk", effect: .staticColor,
                  zones: [RGBColor(hex: "00F0FF"), RGBColor(hex: "4D7CFF"), RGBColor(hex: "B026FF"), RGBColor(hex: "FF1E8E")],
                  speed: 2, brightness: 2),
        RGBPreset(name: "Ice Blue", effect: .staticColor,
                  zones: [RGBColor(hex: "7DD3FC"), RGBColor(hex: "38BDF8"), RGBColor(hex: "0EA5E9"), RGBColor(hex: "818CF8")],
                  speed: 2, brightness: 2),
        RGBPreset(name: "Sunset", effect: .staticColor,
                  zones: [RGBColor(hex: "FF3B30"), RGBColor(hex: "FF7A00"), RGBColor(hex: "FFB800"), RGBColor(hex: "FF2D55")],
                  speed: 2, brightness: 2),
        RGBPreset(name: "Matrix", effect: .breath,
                  zones: [RGBColor(hex: "00FF66"), RGBColor(hex: "00E676"), RGBColor(hex: "00C853"), RGBColor(hex: "69F0AE")],
                  speed: 2, brightness: 2),
        RGBPreset(name: "Pure White", effect: .staticColor,
                  zones: Array(repeating: RGBColor(hex: "FFFFFF"), count: 4),
                  speed: 2, brightness: 2),
        RGBPreset(name: "Aurora Wave", effect: .waveRight,
                  zones: [RGBColor(hex: "00FFCC"), RGBColor(hex: "00B4FF"), RGBColor(hex: "8A2BE2"), RGBColor(hex: "FF00AA")],
                  speed: 2, brightness: 2),
        RGBPreset(name: "Rainbow", effect: .smooth,
                  zones: [RGBColor(hex: "FF0000"), RGBColor(hex: "FFFF00"), RGBColor(hex: "00FF00"), RGBColor(hex: "0088FF")],
                  speed: 2, brightness: 2),
        RGBPreset(name: "Lights Off", effect: .off,
                  zones: Array(repeating: RGBColor(hex: "000000"), count: 4),
                  speed: 1, brightness: 1),
    ]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LegionRGB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = dir.appendingPathComponent("state.json")
        loadState()
        probeDevice()
    }

    func setZoneColor(_ index: Int, color: Color) {
        let rgb = RGBColor(nsColor: NSColor(color))
        if linkZones {
            zones = Array(repeating: rgb, count: 4)
        } else if index >= 0 && index < 4 {
            zones[index] = rgb
        }
        if !effect.usesZoneColors {
            effect = .staticColor
        }
        scheduleApply()
    }

    func applyPreset(_ preset: RGBPreset) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            effect = preset.effect
            zones = preset.zones
            speed = preset.speed
            brightness = preset.brightness
            linkZones = false
        }
        scheduleApply(immediate: true)
    }

    func scheduleApply(immediate: Bool = false) {
        saveState()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 45_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            self.applyNow()
        }
    }

    func probeDevice() {
        Task.detached {
            var info = LegionDeviceInfo()
            let rc = legion_rgb_probe(&info)
            let name = Self.extractModelName(&info)
            await MainActor.run {
                if rc == 0 {
                    self.isConnected = true
                    self.deviceName = name
                    self.statusText = "Connected - \(name)"
                    self.lastError = nil
                } else {
                    self.isConnected = false
                    self.statusText = "No Lenovo ITE controller found"
                }
            }
        }
    }

    func applyNow() {
        let cEff = effect.cEffect
        let label = effect.label
        let b = UInt8(max(1, min(2, brightness)))
        let s = UInt8(max(1, min(4, speed)))
        var zoneBytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<min(4, zones.count) {
            let (r, g, bl) = zones[i].bytes
            zoneBytes[i * 3] = r
            zoneBytes[i * 3 + 1] = g
            zoneBytes[i * 3 + 2] = bl
        }

        Task.detached {
            var info = LegionDeviceInfo()
            var errBuf = [CChar](repeating: 0, count: 256)
            let rc = zoneBytes.withUnsafeBufferPointer { zptr in
                legion_rgb_apply(cEff, zptr.baseAddress, b, s, &info, &errBuf, errBuf.count)
            }
            let name = Self.extractModelName(&info)
            let errMsg = String(cString: errBuf)
            await MainActor.run {
                if rc == 0 {
                    self.isConnected = true
                    self.deviceName = name
                    self.statusText = "\(label) - \(name)"
                    self.lastError = nil
                } else {
                    self.isConnected = false
                    self.statusText = "Device error"
                    self.lastError = errMsg.isEmpty ? "Failed to send USB report (\(rc))" : errMsg
                }
            }
        }
    }

    nonisolated private static func extractModelName(_ info: inout LegionDeviceInfo) -> String {
        withUnsafePointer(to: &info.model_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) { cstr in
                String(cString: cstr)
            }
        }
    }

    private func saveState() {
        let s = SavedState(effect: effect, zones: zones, brightness: brightness, speed: speed, linkZones: linkZones)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: stateURL)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(SavedState.self, from: data),
              s.zones.count == 4 else { return }
        effect = s.effect
        zones = s.zones
        brightness = max(1, min(2, s.brightness))
        speed = max(1, min(4, s.speed))
        linkZones = s.linkZones
    }
}

// MARK: - Live Animated 4-Zone Keyboard Preview

struct KeyboardPreview: View {
    @ObservedObject var ctrl: RGBController

    private let rows: [[(String, CGFloat)]] = [
        [("esc",1.1),("F1",1),("F2",1),("F3",1),("F4",1),("F5",1),("F6",1),("F7",1),("F8",1),("F9",1),("F10",1),("F11",1),("F12",1),("del",1.1),("home",0.9),("end",0.9),("pgup",0.9),("pgdn",0.9)],
        [("`",1),("1",1),("2",1),("3",1),("4",1),("5",1),("6",1),("7",1),("8",1),("9",1),("0",1),("-",1),("=",1),("⌫",1.8),("num",0.9),("/",0.9),("*",0.9),("-",0.9)],
        [("⇥",1.4),("Q",1),("W",1),("E",1),("R",1),("T",1),("Y",1),("U",1),("I",1),("O",1),("P",1),("[",1),("]",1),("\\",1.4),("7",0.9),("8",0.9),("9",0.9),("+",0.9)],
        [("⇪",1.7),("A",1),("S",1),("D",1),("F",1),("G",1),("H",1),("J",1),("K",1),("L",1),(";",1),("'",1),("⏎",2.1),("4",0.9),("5",0.9),("6",0.9),("+",0.9)],
        [("⇧",2.2),("Z",1),("X",1),("C",1),("V",1),("B",1),("N",1),("M",1),(",",1),(".",1),("/",1),("⇧",1.7),("▲",0.95),("1",0.9),("2",0.9),("3",0.9),("⏎",0.9)],
        [("fn",1.1),("⌃",1.1),("⌥",1.1),("⌘",1.2),("space",5.6),("⌘",1.1),("⌥",1.1),("◀",0.95),("▼",0.95),("▶",0.95),("0",1.8),(".",0.9),("⏎",0.9)],
    ]

    private func liveZoneColors(at date: Date) -> [Color] {
        let t = date.timeIntervalSinceReferenceDate
        let rate = 0.25 + Double(ctrl.speed) * 0.22
        let dim = ctrl.brightness == 1 ? 0.58 : 1.0

        switch ctrl.effect {
        case .off:
            return Array(repeating: Color.white.opacity(0.06), count: 4)
        case .staticColor:
            return ctrl.zones.map { $0.color.opacity(dim) }
        case .breath:
            let pulse = 0.22 + 0.78 * (0.5 + 0.5 * sin(t * rate * 3.0))
            return ctrl.zones.map { $0.color.opacity(dim * pulse) }
        case .smooth:
            let h = (t * rate * 0.35).truncatingRemainder(dividingBy: 1.0)
            let c = Color(hue: h, saturation: 0.9, brightness: 1.0).opacity(dim)
            return Array(repeating: c, count: 4)
        case .waveLeft:
            return (0..<4).map { z in
                let h = (t * rate * 0.6 + Double(z) * 0.22).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: h, saturation: 0.92, brightness: 1.0).opacity(dim)
            }
        case .waveRight:
            return (0..<4).map { z in
                let h = (t * rate * 0.6 + Double(3 - z) * 0.22).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: h, saturation: 0.92, brightness: 1.0).opacity(dim)
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let cols = liveZoneColors(at: timeline.date)
            ZStack {
                LinearGradient(colors: cols, startPoint: .leading, endPoint: .trailing)
                    .blur(radius: 26)
                    .opacity(ctrl.effect == .off ? 0.0 : 0.45)
                    .padding(-6)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.085, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: cols.map { $0.opacity(0.65) }, startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1.2
                            )
                    )

                VStack(spacing: 4) {
                    ForEach(0..<rows.count, id: \.self) { rIdx in
                        let row = rows[rIdx]
                        let totalWeight = row.reduce(0) { $0 + $1.1 }
                        GeometryReader { geo in
                            let spacing: CGFloat = 3
                            let avail = geo.size.width - spacing * CGFloat(row.count - 1)
                            HStack(spacing: spacing) {
                                ForEach(0..<row.count, id: \.self) { kIdx in
                                    let key = row[kIdx]
                                    let prefix = row.prefix(kIdx).reduce(0) { $0 + $1.1 } + key.1 * 0.5
                                    let frac = prefix / totalWeight
                                    let zone = min(3, max(0, Int(frac * 4.0)))
                                    let zColor = cols[zone]
                                    let isSelected = ctrl.effect.usesZoneColors && (ctrl.linkZones || ctrl.selectedZone == zone)

                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color(white: 0.14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .fill(zColor.opacity(ctrl.effect == .off ? 0.02 : 0.22))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .strokeBorder(zColor.opacity(isSelected ? 0.9 : 0.45), lineWidth: isSelected ? 0.9 : 0.6)
                                            )
                                            .shadow(color: zColor.opacity(ctrl.effect == .off ? 0 : 0.55), radius: 3)

                                        Text(key.0)
                                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                                            .foregroundColor(ctrl.effect == .off ? .white.opacity(0.35) : .white.opacity(0.92))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                    }
                                    .frame(width: max(8, avail * (key.1 / totalWeight)), height: geo.size.height)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            ctrl.selectedZone = zone
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 21)
                    }
                }
                .padding(11)

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { z in
                            let active = ctrl.effect.usesZoneColors && (ctrl.linkZones || ctrl.selectedZone == z)
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    ctrl.selectedZone = z
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(cols[z])
                                        .frame(width: 7, height: 7)
                                    Text("Zone \(z + 1)")
                                        .font(.system(size: 9.5, weight: active ? .bold : .medium, design: .rounded))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(active ? Color.white.opacity(0.18) : Color.black.opacity(0.35))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(active ? cols[z].opacity(0.9) : Color.white.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .offset(y: 26)
            }
            .frame(height: 162)
            .padding(.bottom, 22)
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var ctrl: RGBController

    private let quickSwatches: [String] = [
        "00D4FF", "3B82F6", "8B5CF6", "EC4899",
        "FF2D55", "FF6B00", "FFD60A", "00FF88", "FFFFFF"
    ]

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: ctrl.effect == .off ? [.gray.opacity(0.4), .gray.opacity(0.2)] : ctrl.zones.map(\.color),
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 34, height: 34)
                                .shadow(color: ctrl.zones[0].color.opacity(0.4), radius: 6)
                            Image(systemName: "keyboard.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Legion RGB")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(ctrl.isConnected ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(ctrl.statusText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            ctrl.effect = (ctrl.effect == .off) ? .staticColor : .off
                        }
                        ctrl.scheduleApply(immediate: true)
                    } label: {
                        Image(systemName: ctrl.effect == .off ? "power" : "lightbulb.max.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ctrl.effect == .off ? .secondary : .yellow)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(ctrl.effect == .off ? "Turn On" : "Turn Off")
                }

                KeyboardPreview(ctrl: ctrl)

                HStack(spacing: 6) {
                    ForEach(RGBEffect.allCases) { eff in
                        let selected = ctrl.effect == eff
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                ctrl.effect = eff
                            }
                            ctrl.scheduleApply(immediate: true)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: eff.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(eff.label)
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selected ? .primary : .secondary)
                    }
                }

                if ctrl.effect.usesZoneColors {
                    VStack(spacing: 10) {
                        HStack {
                            Text(ctrl.linkZones ? "All 4 Zones Linked" : "Zone \(ctrl.selectedZone + 1) Color")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("Sync All Zones", isOn: $ctrl.linkZones)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.system(size: 11, weight: .medium))
                                .onChange(of: ctrl.linkZones) { _, linked in
                                    if linked {
                                        let c = ctrl.zones[ctrl.selectedZone]
                                        ctrl.zones = Array(repeating: c, count: 4)
                                        ctrl.scheduleApply(immediate: true)
                                    }
                                }
                        }

                        HStack(spacing: 10) {
                            ColorPicker(
                                "",
                                selection: Binding(
                                    get: { ctrl.zones[ctrl.selectedZone].color },
                                    set: { ctrl.setZoneColor(ctrl.selectedZone, color: $0) }
                                ),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .scaleEffect(1.15)

                            HStack(spacing: 6) {
                                ForEach(quickSwatches, id: \.self) { hex in
                                    let swColor = RGBColor(hex: hex).color
                                    Button {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            ctrl.setZoneColor(ctrl.selectedZone, color: swColor)
                                        }
                                    } label: {
                                        Circle()
                                            .fill(swColor)
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                                            )
                                            .shadow(color: swColor.opacity(0.45), radius: 3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                            Text("#\(ctrl.zones[ctrl.selectedZone].hex)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Brightness")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Picker("", selection: $ctrl.brightness) {
                            Text("Low").tag(1)
                            Text("High").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: ctrl.brightness) { _, _ in ctrl.scheduleApply(immediate: true) }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Animation Speed")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(ctrl.speed)x")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Picker("", selection: $ctrl.speed) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("4").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!ctrl.effect.usesSpeed)
                        .opacity(ctrl.effect.usesSpeed ? 1.0 : 0.45)
                        .onChange(of: ctrl.speed) { _, _ in ctrl.scheduleApply(immediate: true) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Presets")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(RGBController.presets) { preset in
                            Button {
                                ctrl.applyPreset(preset)
                            } label: {
                                VStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            preset.effect == .off
                                            ? LinearGradient(colors: [.gray.opacity(0.35), .black.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: preset.zones.map(\.color), startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(height: 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
                                        )
                                    Text(preset.name)
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                }
                                .padding(7)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let err = ctrl.lastError {
                    Text(err)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            .padding(18)
        }
        .frame(width: 560)
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Native NSVisualEffectView Wrapper

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - App & Menu Bar Entry Point

@main
struct LegionRGBApp: App {
    @StateObject private var ctrl = RGBController()

    var body: some Scene {
        Window("Legion RGB", id: "main") {
            ContentView(ctrl: ctrl)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Legion RGB", systemImage: "keyboard.fill") {
            MenuBarQuickView(ctrl: ctrl)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarQuickView: View {
    @ObservedObject var ctrl: RGBController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Legion RGB...") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        ForEach(RGBController.presets) { preset in
            Button(preset.name) {
                ctrl.applyPreset(preset)
            }
        }
        Divider()
        Button("Quit Legion RGB") {
            NSApp.terminate(nil)
        }
    }
}
