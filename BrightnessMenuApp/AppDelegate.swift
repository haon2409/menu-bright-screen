import Cocoa
import IOKit
import IOKit.graphics
import Darwin

// Private bridge for DisplayServices (Apple private framework).
// Not App Store–safe, but works reliably on modern MacBook panels.
private final class DisplayServicesBridge {
    static let shared = DisplayServicesBridge()

    typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getBrightnessSym: GetBrightnessFn?
    private let setBrightnessSym: SetBrightnessFn?
    private let getLinearSym: GetBrightnessFn?
    private let setLinearSym: SetBrightnessFn?

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let h = handle {
            if let sym = dlsym(h, "DisplayServicesGetBrightness") {
                getBrightnessSym = unsafeBitCast(sym, to: GetBrightnessFn.self)
            } else {
                getBrightnessSym = nil
            }
            if let sym = dlsym(h, "DisplayServicesSetBrightness") {
                setBrightnessSym = unsafeBitCast(sym, to: SetBrightnessFn.self)
            } else {
                setBrightnessSym = nil
            }
            if let sym = dlsym(h, "DisplayServicesGetLinearBrightness") {
                getLinearSym = unsafeBitCast(sym, to: GetBrightnessFn.self)
            } else {
                getLinearSym = nil
            }
            if let sym = dlsym(h, "DisplayServicesSetLinearBrightness") {
                setLinearSym = unsafeBitCast(sym, to: SetBrightnessFn.self)
            } else {
                setLinearSym = nil
            }
        } else {
            getBrightnessSym = nil
            setBrightnessSym = nil
            getLinearSym = nil
            setLinearSym = nil
        }
    }

    deinit {
        if let h = handle {
            dlclose(h)
        }
    }

    func readPercent(displayID: CGDirectDisplayID) -> Float? {
        var v: Float = 0
        if let f = getBrightnessSym, f(displayID, &v) == 0 {
            return v * 100.0
        }
        if let f = getLinearSym, f(displayID, &v) == 0 {
            return v * 100.0
        }
        return nil
    }

    func writePercent(displayID: CGDirectDisplayID, percent: Float) -> Bool {
        let value = max(0, min(100, percent)) / 100.0
        if let f = setBrightnessSym, f(displayID, value) == 0 {
            return true
        }
        if let f = setLinearSym, f(displayID, value) == 0 {
            return true
        }
        return false
    }
}

// Custom NSSliderCell that draws the filled (left) portion as fully opaque white
// and draws a fully opaque knob so the track does not show through.
final class MenuBarSliderCell: NSSliderCell {
    var fillColor: NSColor = .white // solid, non-dynamic
    var knobFillColor: NSColor = .white
    var knobBorderColor: NSColor = NSColor.black.withAlphaComponent(0.2)
    var knobBorderWidth: CGFloat = 1.0

    // Sun icon tuning
    var sunRayCount: Int = 8
    var sunIconColor: NSColor = NSColor.black.withAlphaComponent(0.85)

    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        // Draw default track first
        super.drawBar(inside: aRect, flipped: flipped)

        // Compute the fill rect from the left edge to the center of the knob
        let knob = self.knobRect(flipped: flipped)
        let fillWidth = max(0, min(aRect.width, knob.midX - aRect.minX))
        let fillRect = NSRect(x: aRect.minX, y: aRect.minY, width: fillWidth, height: aRect.height)

        // Clip to the track shape so the fill inherits rounded corners
        NSGraphicsContext.saveGraphicsState()
        let trackPath = NSBezierPath(roundedRect: aRect, xRadius: aRect.height / 2, yRadius: aRect.height / 2)
        trackPath.addClip()

        // Draw with normal compositing, fully opaque
        let ctx = NSGraphicsContext.current
        let previousOp = ctx?.compositingOperation
        ctx?.compositingOperation = .sourceOver

        fillColor.setFill()
        NSBezierPath(rect: fillRect).fill()

        if let prev = previousOp {
            ctx?.compositingOperation = prev
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // Draw a fully opaque knob that completely covers the track beneath it,
    // with a sun icon that scales with the current brightness value.
    override func drawKnob() {
        let flipped = controlView?.isFlipped ?? false
        var rect = knobRect(flipped: flipped).insetBy(dx: 0.5, dy: 0.5)

        // Ensure minimum size for visibility
        if rect.height < 10 {
            let delta = (10 - rect.height) / 2
            rect = rect.insetBy(dx: -delta, dy: -delta)
        }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext.current
        let previousOp = ctx?.compositingOperation
        ctx?.compositingOperation = .sourceOver

        // Opaque circular knob
        let radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        knobFillColor.setFill()
        path.fill()

        // Draw sun glyph inside the knob
        drawSunGlyph(in: rect)

        // Optional subtle border to define edges on light backgrounds
        knobBorderColor.setStroke()
        path.lineWidth = knobBorderWidth
        path.stroke()

        if let prev = previousOp {
            ctx?.compositingOperation = prev
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSunGlyph(in knobRect: NSRect) {
        // Brightness fraction 0...1 from the cell's current value
        let range = max(0.0001, maxValue - minValue)
        let fraction = CGFloat((doubleValue - minValue) / range) // 0...1

        // Geometry
        let center = CGPoint(x: knobRect.midX, y: knobRect.midY)
        let R = min(knobRect.width, knobRect.height) / 2.0 - knobBorderWidth // inner padding
        let coreRadius = max(1.0, R * (0.30 + 0.10 * fraction))              // center disk
        let rayLength = max(0.8, R * (0.18 + 0.32 * fraction))               // grows with brightness
        let rayInner = coreRadius + 0.8
        let rayOuter = min(R - 0.7, coreRadius + rayLength)
        let rayThickness = max(0.9, 1.0 + 0.6 * fraction)

        // Choose icon color; keep strong contrast against white knob
        let iconColor: NSColor = sunIconColor
        iconColor.set()

        // Draw rays
        let raysPath = NSBezierPath()
        raysPath.lineCapStyle = .round
        raysPath.lineWidth = rayThickness

        let count = max(6, sunRayCount)
        let twoPi = CGFloat.pi * 2
        for i in 0..<count {
            let angle = twoPi * CGFloat(i) / CGFloat(count)
            let dx = cos(angle)
            let dy = sin(angle)
            let p0 = CGPoint(x: center.x + dx * rayInner, y: center.y + dy * rayInner)
            let p1 = CGPoint(x: center.x + dx * rayOuter, y: center.y + dy * rayOuter)
            raysPath.move(to: p0)
            raysPath.line(to: p1)
        }
        raysPath.stroke()

        // Draw center disk
        let diskRect = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
        let diskPath = NSBezierPath(ovalIn: diskRect)
        iconColor.setFill()
        diskPath.fill()
    }
}

// Custom status item view that hosts a slider directly in the menu bar.
// Left-click/drag: adjust brightness. Right-click/Control-click: show context menu.
final class SliderStatusView: NSView {
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    weak var target: AnyObject?
    var action: Selector?
    weak var statusItem: NSStatusItem?
    var contextMenu: NSMenu?

    // Opt out of vibrancy for solid rendering
    override var allowsVibrancy: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Use a non-vibrant appearance (Aqua or Dark Aqua) to avoid translucency
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        slider.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // Preserve current range/value before swapping the cell
        let currentMin = slider.minValue
        let currentMax = slider.maxValue
        let currentValue = slider.doubleValue

        // Install custom cell (this resets range to defaults 0...1)
        let cell = MenuBarSliderCell()
        slider.cell = cell

        // Restore range and value so our "percent" math stays correct
        slider.minValue = currentMin
        slider.maxValue = currentMax
        slider.doubleValue = currentValue

        // Now set behavior and action (target/action live on the cell)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))

        // Layout
        slider.autoresizingMask = [.width, .height]
        slider.frame = bounds.insetBy(dx: 6, dy: 2)
        addSubview(slider)

        // Improve hit testing: make the whole view interactive
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        toolTip = "Screen Brightness"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Keep drawing consistent if appearance flips between light/dark
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        slider.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        slider.needsDisplay = true
        needsDisplay = true
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        if let t = target, let a = action {
            _ = t.perform(a, with: sender)
        }
    }

    // Right-click or Control-click to show menu
    override func rightMouseDown(with event: NSEvent) {
        showMenu(at: event.locationInWindow)
    }
    override func otherMouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(at: event.locationInWindow)
        } else {
            super.otherMouseDown(with: event)
        }
    }

    private func showMenu(at locationInWindow: NSPoint) {
        guard let menu = contextMenu, let statusItem = statusItem else { return }
        statusItem.popUpMenu(menu)
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    private var sliderView: SliderStatusView!
    private var updateTimer: Timer?
    private var contextMenu: NSMenu!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Make this a menu bar–only app (no Dock icon, no app menu)
        NSApp.setActivationPolicy(.accessory)
        // For a permanent solution, also set LSUIElement = YES in Info.plist.

        // Create a status item with a 100pt-wide slider
        let sliderWidth: CGFloat = 100
        statusItem = NSStatusBar.system.statusItem(withLength: sliderWidth)
        let thickness = NSStatusBar.system.thickness
        let frame = NSRect(x: 0, y: 0, width: sliderWidth, height: thickness)

        // Create the slider view
        let view = SliderStatusView(frame: frame)
        view.statusItem = statusItem
        view.target = self
        view.action = #selector(sliderChanged(_:))
        statusItem.view = view
        sliderView = view

        // Context menu (right-click / Control-click)
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        contextMenu = menu
        sliderView.contextMenu = menu

        // Initial update
        updateBrightness()

        // Periodic update (every 1 second) to reflect external changes
        updateTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateBrightness), userInfo: nil, repeats: true)
    }

    @objc func updateBrightness() {
        if let brightness = getCurrentDisplayBrightness() {
            if NSApp.currentEvent?.type != .leftMouseDragged {
                sliderView.slider.floatValue = brightness
            }
            sliderView.slider.isEnabled = true
            sliderView.toolTip = String(format: "Screen Brightness: %.0f%%", brightness)
        } else {
            sliderView.slider.isEnabled = false
            sliderView.toolTip = "Screen Brightness: N/A"
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let percent = sender.floatValue
        _ = setCurrentDisplayBrightness(percent: percent)
        sliderView.toolTip = String(format: "Screen Brightness: %.0f%%", percent)
    }

    // MARK: - Brightness

    private func getCurrentDisplayBrightness() -> Float? {
        let displayID = targetDisplayID()
        if let id = displayID, let v = DisplayServicesBridge.shared.readPercent(displayID: id) {
            return v
        }
        if let service = brightnessCapableService() {
            defer { IOObjectRelease(service) }
            var value: Float = 0
            let r = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
            if r == kIOReturnSuccess { return value * 100.0 }
        }
        return nil
    }

    @discardableResult
    private func setCurrentDisplayBrightness(percent: Float) -> Bool {
        let displayID = targetDisplayID()
        if let id = displayID, DisplayServicesBridge.shared.writePercent(displayID: id, percent: percent) {
            return true
        }
        if let service = brightnessCapableService() {
            defer { IOObjectRelease(service) }
            let value = max(0, min(100, percent)) / 100.0
            let r = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, value)
            return r == kIOReturnSuccess
        }
        return false
    }

    /// Prefer the built-in panel; if none, fall back to the main display.
    private func targetDisplayID() -> CGDirectDisplayID? {
        if let internalID = builtInDisplayID() {
            return internalID
        }
        return CGMainDisplayID()
    }

    /// Finds the CGDirectDisplayID of the built-in display.
    private func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return nil }
        return displayIDs.first(where: { CGDisplayIsBuiltin($0) != 0 })
    }

    /// Attempts to get an IOKit service that supports the brightness parameter.
    private func brightnessCapableService() -> io_service_t? {
        if let builtInID = builtInDisplayID(), let service = ioServicePort(for: builtInID) {
            var test: Float = 0
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &test) == kIOReturnSuccess {
                return service // caller releases
            } else {
                IOObjectRelease(service)
            }
        }
        guard let matching = IOServiceMatching("IODisplayConnect") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            var value: Float = 0
            let r = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
            if r == kIOReturnSuccess {
                return service // caller releases
            }
            IOObjectRelease(service)
        }
        return nil
    }

    /// Maps a CGDirectDisplayID to its IOKit service (IODisplayConnect) by matching vendor + model.
    private func ioServicePort(for displayID: CGDirectDisplayID) -> io_service_t? {
        guard let matching = IOServiceMatching("IODisplayConnect") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let targetVendor = CGDisplayVendorNumber(displayID)
        let targetModel  = CGDisplayModelNumber(displayID)

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            if let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as? [String: Any] {
                let vendor = info[kDisplayVendorID as String] as? UInt32
                let model  = info[kDisplayProductID as String] as? UInt32
                if vendor == targetVendor && model == targetModel {
                    return service // caller releases
                }
            }
            IOObjectRelease(service)
        }
        return nil
    }
}
