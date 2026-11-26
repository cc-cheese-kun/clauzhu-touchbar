import Cocoa
import ObjectiveC

// CrabTouchBar — a crab that strolls back and forth across the ENTIRE Touch Bar while Claude
// Code is thinking / running a tool, and reaches up with a heart when you tap it.
//
// Reads ~/.claude/statusbar/state.json (kept fresh by the claude-status-bar hooks) to know when
// Claude is active. Writes nothing, installs no hooks.
//
// To span the whole bar (not just the right-hand Control Strip) it presents a *system-modal*
// Touch Bar via private NSTouchBar SPI — the same approach Pock/MTMR use. A small crab icon is
// left in the Control Strip as a dismiss anchor so the normal Touch Bar can always be restored.

// MARK: - Private Touch Bar bridges

private typealias VoidBoolFn = @convention(c) (Bool) -> Void
private typealias SetPresenceFn = @convention(c) (NSString, Bool) -> Void

private func dfrSym(_ name: String) -> UnsafeMutableRawPointer? {
    let paths = [
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation",
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
    ]
    for p in paths { if let h = dlopen(p, RTLD_NOW), let s = dlsym(h, name) { return s } }
    return nil
}

private let dfrSetPresence: SetPresenceFn? = dfrSym("DFRElementSetControlStripPresenceForIdentifier").map {
    unsafeBitCast($0, to: SetPresenceFn.self)
}
private let dfrShowsCloseBox: VoidBoolFn? = dfrSym("DFRSystemModalShowsCloseBoxWhenFrontMost").map {
    unsafeBitCast($0, to: VoidBoolFn.self)
}

private func sendTouchBarItemClassSelector(_ name: String, _ item: NSTouchBarItem) {
    let sel = NSSelectorFromString(name)
    let cls: AnyObject = NSTouchBarItem.self
    if cls.responds(to: sel) { _ = cls.perform(sel, with: item) }
}

/// `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]` (and fallbacks),
/// called through the ObjC IMP so we can pass the non-object `placement` arg.
@discardableResult
private func presentSystemModal(_ bar: NSTouchBar, tray id: NSTouchBarItem.Identifier) -> Bool {
    let cls: AnyClass = NSTouchBar.self
    let selP = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    if let m = class_getClassMethod(cls, selP) {
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString) -> Void
        let f = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        f(cls, selP, bar, 0, id.rawValue as NSString)
        return true
    }
    let sel2 = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    if let m = class_getClassMethod(cls, sel2) {
        typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, NSString) -> Void
        let f = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        f(cls, sel2, bar, id.rawValue as NSString)
        return true
    }
    return false
}

private func dismissSystemModal(_ bar: NSTouchBar) {
    let cls: AnyClass = NSTouchBar.self
    for name in ["dismissSystemModalTouchBar:", "minimizeSystemModalTouchBar:"] {
        if let m = class_getClassMethod(cls, NSSelectorFromString(name)) {
            typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
            let f = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            f(cls, NSSelectorFromString(name), bar)
            return
        }
    }
}

// MARK: - Image helpers

private func flippedHorizontally(_ img: NSImage) -> NSImage {
    let size = img.size
    let out = NSImage(size: size)
    out.lockFocus()
    let t = NSAffineTransform()
    t.translateX(by: size.width, yBy: 0)
    t.scaleX(by: -1, yBy: 1)
    t.concat()
    img.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1)
    out.unlockFocus()
    return out
}

private func grayscale(_ img: NSImage) -> NSImage {
    guard let tiff = img.tiffRepresentation, let ci = CIImage(data: tiff),
          let f = CIFilter(name: "CIColorControls") else { return img }
    f.setValue(ci, forKey: kCIInputImageKey)
    f.setValue(0.0, forKey: kCIInputSaturationKey)
    f.setValue(-0.12, forKey: kCIInputBrightnessKey)
    guard let out = f.outputImage,
          let cg = CIContext().createCGImage(out, from: out.extent) else { return img }
    return NSImage(cgImage: cg, size: img.size)
}

private func pixelHeart(scale: CGFloat) -> NSImage {
    // Classic 8-bit heart (8×7). 'R' = red body, 'H' = highlight, '.' = transparent.
    let rows = [
        ".RR..RR.",
        "RHHRRRRR",
        "RHRRRRRR",
        "RRRRRRRR",
        ".RRRRRR.",
        "..RRRR..",
        "...RR...",
    ]
    let cols = rows[0].count
    let size = NSSize(width: CGFloat(cols) * scale, height: CGFloat(rows.count) * scale)
    let img = NSImage(size: size)
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    let red = NSColor(srgbRed: 0.91, green: 0.13, blue: 0.16, alpha: 1)
    let hi = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.66, alpha: 1)
    for (r, row) in rows.enumerated() {
        for (c, ch) in row.enumerated() {
            let color: NSColor
            switch ch { case "R": color = red; case "H": color = hi; default: continue }
            color.setFill()
            let x = CGFloat(c) * scale
            let y = size.height - CGFloat(r + 1) * scale   // row 0 = top
            NSRect(x: x, y: y, width: scale, height: scale).fill()
        }
    }
    img.unlockFocus()
    return img
}

private func speechBubble(_ text: String) -> NSImage {
    // Blocky 8-bit speech bubble: black-outlined white box with a stepped tail pointing down-left.
    let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let ts = (text as NSString).size(withAttributes: attrs)
    let bodyW = (ts.width + 8).rounded()
    let bodyH = (ts.height + 4).rounded()
    let tailH: CGFloat = 4
    let size = NSSize(width: bodyW, height: bodyH + tailH)
    let img = NSImage(size: size)
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    NSColor.black.setFill()
    NSRect(x: 0, y: tailH, width: bodyW, height: bodyH).fill()
    NSColor.white.setFill()
    NSRect(x: 1, y: tailH + 1, width: bodyW - 2, height: bodyH - 2).fill()
    // Stepped pixel tail.
    NSColor.black.setFill()
    NSRect(x: 6, y: tailH - 2, width: 4, height: 4).fill()
    NSRect(x: 4, y: 0, width: 4, height: 4).fill()
    NSColor.white.setFill()
    NSRect(x: 7, y: tailH - 1, width: 2, height: 4).fill()   // merge tail into body
    NSRect(x: 5, y: 1, width: 2, height: 3).fill()
    (text as NSString).draw(at: NSPoint(x: 4, y: tailH + 2), withAttributes: attrs)
    img.unlockFocus()
    return img
}

private func horseImage(legPhase: Int) -> NSImage {
    // Blocky 8-bit galloping horse facing right; two leg phases for the gallop.
    let w: CGFloat = 28, h: CGFloat = 16
    let img = NSImage(size: NSSize(width: w, height: h))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    let body = NSColor(srgbRed: 0.58, green: 0.36, blue: 0.18, alpha: 1)
    let dark = NSColor(srgbRed: 0.32, green: 0.19, blue: 0.08, alpha: 1)
    func r(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ c: NSColor) {
        c.setFill(); NSRect(x: x, y: y, width: ww, height: hh).fill()
    }
    r(1, 6, 3, 7, dark)            // tail
    r(3, 5, 8, 8, body)            // hindquarter
    r(4, 5, 16, 7, body)           // body
    r(6, 12, 11, 1, body)          // back
    r(17, 7, 5, 7, body)           // neck
    r(17, 13, 6, 2, dark)          // mane
    r(21, 9, 6, 4, body)           // head
    r(26, 9, 2, 3, body)           // muzzle
    r(21, 13, 2, 2, dark)          // ear
    let back: [CGFloat]  = legPhase == 0 ? [5, 9]   : [4, 10]
    let front: [CGFloat] = legPhase == 0 ? [15, 18] : [16, 19]
    for lx in back + front {
        r(lx, 0, 2, 6, body)
        r(lx, 0, 2, 1, dark)       // hoof
    }
    img.unlockFocus()
    return img
}

// MARK: - Full-width crab view (handles the tap)

final class CrabBarView: NSView {
    var onTap: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.direct]
    }
    required init?(coder: NSCoder) { fatalError() }
    override func touchesBegan(with event: NSEvent) { onTap?() }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let trayId = NSTouchBarItem.Identifier("com.claudepig.crab.tray")
    let crabId = NSTouchBarItem.Identifier("com.claudepig.crab.crab")

    var touchBar: NSTouchBar!
    var container: CrabBarView!
    var crabView: NSImageView!
    var heartView: NSImageView!

    var framesRight: [NSImage] = []
    var framesLeft: [NSImage] = []
    var crabW: CGFloat = 22
    let crabH: CGFloat = 22         // smaller than the bar so it has headroom to hop
    let barH: CGFloat = 30

    var posX: CGFloat = 0
    var dir: CGFloat = 1            // +1 right, -1 left
    var frameIndex = 0
    var frameAccum: TimeInterval = 0
    var lastTick: TimeInterval = 0
    var heartStart: TimeInterval?
    let heartDuration: TimeInterval = 1.1
    let walkSpeed: CGFloat = 110    // points per second
    let frameInterval: TimeInterval = 0.07

    // Idle "8-bit" bob: whole-pixel vertical steps on a low-fps clock.
    var idleAccum: TimeInterval = 0
    var idleIndex = 0
    let idleStep: TimeInterval = 0.12
    let idleBob: [CGFloat] = [0, 1, 2, 2, 1, 0]

    // Dance once it's been idle a while.
    var idleSince: TimeInterval?
    var dancing = false
    let danceDelay: TimeInterval = 30
    var danceAccum: TimeInterval = 0
    var danceIndex = 0
    let danceStep: TimeInterval = 0.11
    let danceDX: [CGFloat] = [-4, -4, 0, 4, 4, 0]   // side-to-side shimmy (whole pixels)
    let danceDY: [CGFloat] = [ 0,  3, 5, 0, 3, 5]   // hop (kept within the bar's headroom)

    // After a minute of dancing, the crab gallops across the bar on a horse.
    var riding = false
    var danceStart: TimeInterval?
    var horseView: NSImageView!
    var horseFrames: [NSImage] = []
    var horseX: CGFloat = 0
    var horseAccum: TimeInterval = 0
    var horseFrameIdx = 0
    let rideAfterDance: TimeInterval = 60
    let horseSpeed: CGFloat = 230   // points per second

    var active = false
    var permission = false
    var permSince: TimeInterval?
    var bubbleView: NSImageView!
    var activityToken: NSObjectProtocol?
    let statePath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/state.json")

    // Clau猪：Claude 沒開時灰色趴著睡覺；一打開就播「起床」啟動動畫，再進入正常狀態。
    var off = true                  // Claude 進程不在
    var grayFrames: [NSImage] = []
    var grayView: NSImageView!      // 疊在螃蟹上面的灰色版本，起床時一格一格褪掉
    var zView: NSTextField!
    var introStart: TimeInterval?
    var introFromX: CGFloat = 0
    let introDuration: TimeInterval = 2.6
    var polling = false

    // 右側狀態牌（沿用 BTT 版的文字和底色），螃蟹只在左邊剩下的區域裡活動
    var statusBox: NSView!
    var statusLabel: NSTextField!
    let statusW: CGFloat = 112
    var stateWord = "睡了"
    let spin = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

    func applicationDidFinishLaunching(_ note: Notification) {
        // Single instance: if another copy is already running (e.g. login agent + manual launch),
        // bow out so we don't stack two crabs on the Touch Bar.
        let bid = Bundle.main.bundleIdentifier ?? "com.claudepig.crab"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .contains(where: { $0 != NSRunningApplication.current }) {
            NSApp.terminate(nil); return
        }

        // Keep timers running while we're a background accessory app (defeat App Nap), so the
        // crab keeps animating in the Touch Bar while you work in another app.
        activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiated],
                                                              reason: "animate the Touch Bar crab")

        let decoded: [NSImage] = clawdCrabFramePNGs.compactMap {
            guard let d = Data(base64Encoded: $0) else { return nil }
            return NSImage(data: d)
        }
        guard let first = decoded.first else { NSLog("CrabTouchBar: no frames"); NSApp.terminate(nil); return }
        framesRight = decoded
        framesLeft = decoded.map(flippedHorizontally)
        crabW = max(18, (crabH * first.size.width / max(first.size.height, 1)).rounded())
        NSLog("CrabTouchBar: \(decoded.count) frames, crabW=\(crabW), dfrPresence=\(dfrSetPresence != nil), showsClose=\(dfrShowsCloseBox != nil)")

        // Control-strip anchor (small crab) so the modal bar can be dismissed/restored.
        let trayIV = NSImageView(frame: NSRect(x: 0, y: 0, width: 24, height: barH))
        trayIV.imageScaling = .scaleProportionallyDown
        trayIV.image = first
        let trayItem = NSCustomTouchBarItem(identifier: trayId)
        trayItem.view = trayIV
        sendTouchBarItemClassSelector("addSystemTrayItem:", trayItem)
        dfrSetPresence?(trayId.rawValue as NSString, true)

        // Full-width crab view.
        container = CrabBarView(frame: NSRect(x: 0, y: 0, width: 1004, height: barH))
        container.onTap = { [weak self] in self?.tapped() }

        crabView = NSImageView(frame: NSRect(x: 0, y: 0, width: crabW, height: crabH))
        crabView.imageScaling = .scaleProportionallyDown
        crabView.image = first
        container.addSubview(crabView)

        let heart = pixelHeart(scale: 3)
        heartView = NSImageView(frame: NSRect(origin: .zero, size: heart.size))
        heartView.image = heart
        heartView.imageScaling = .scaleNone
        heartView.isHidden = true
        container.addSubview(heartView)

        let bub = speechBubble("help!")
        bubbleView = NSImageView(frame: NSRect(origin: .zero, size: bub.size))
        bubbleView.image = bub
        bubbleView.imageScaling = .scaleNone
        bubbleView.isHidden = true
        container.addSubview(bubbleView)

        grayFrames = decoded.map(grayscale)
        grayView = NSImageView(frame: crabView.frame)
        grayView.imageScaling = .scaleProportionallyDown
        grayView.image = grayFrames[0]
        container.addSubview(grayView, positioned: .above, relativeTo: crabView)

        zView = NSTextField(labelWithString: "z")
        zView.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        zView.textColor = NSColor(srgbRed: 0.82, green: 0.84, blue: 0.92, alpha: 1)
        zView.sizeToFit()
        zView.isHidden = true
        container.addSubview(zView)

        statusBox = NSView(frame: NSRect(x: 0, y: 0, width: statusW, height: barH))
        statusBox.wantsLayer = true
        statusBox.layer?.cornerRadius = 6
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 0, y: 5, width: statusW, height: 20)
        statusBox.addSubview(statusLabel)
        container.addSubview(statusBox)
        setStatus("睡了", r: 60, g: 60, b: 64)
        posX = 8

        horseFrames = [horseImage(legPhase: 0), horseImage(legPhase: 1)]
        horseView = NSImageView(frame: NSRect(origin: .zero, size: horseFrames[0].size))
        horseView.imageScaling = .scaleNone
        horseView.isHidden = true
        container.addSubview(horseView, positioned: .below, relativeTo: crabView)   // crab rides on top

        let crabItem = NSCustomTouchBarItem(identifier: crabId)
        crabItem.view = container

        touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [crabId]
        touchBar.templateItems = [crabItem]

        dfrShowsCloseBox?(false)
        let ok = presentSystemModal(touchBar, tray: trayId)
        NSLog("CrabTouchBar: presentSystemModal ok=\(ok)")

        lastTick = ProcessInfo.processInfo.systemUptime
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.pollState() }
        // Log the real bar width once laid out, so travel can be tuned if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            NSLog("CrabTouchBar: container bounds = \(self?.container.bounds ?? .zero)")
        }
        pollState()
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        nil // items provided via templateItems
    }

    func tapped() {
        heartStart = ProcessInfo.processInfo.systemUptime
        idleSince = heartStart   // petting resets the dance/ride countdown
        dancing = false; danceStart = nil
        if riding { riding = false; horseView?.isHidden = true }
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, min(0.1, now - lastTick))
        lastTick = now

        bubbleView.isHidden = true   // shown only in the permission branch below

        statusBox.setFrameOrigin(NSPoint(x: container.bounds.width - statusW, y: 0))
        let busyNow = !off && (active || permission)
        statusLabel.stringValue = "Clau猪 \(stateWord)" + (busyNow ? " \(spin[Int(now / 0.1) % spin.count])" : "")
        if busyNow && !permission {   // 幹活時深藍底輕輕呼吸，和 BTT 版一樣
            let k = 0.75 + 0.25 * abs((now / 0.3).truncatingRemainder(dividingBy: 12) - 6) / 6
            statusBox.layer?.backgroundColor = NSColor(srgbRed: 30*k/255, green: 70*k/255, blue: 140*k/255, alpha: 1).cgColor
        }
        let width = container.bounds.width - statusW - 6
        let maxX = max(0, width - crabW)

        // —— 啟動動畫 / 睡覺，優先於其他所有狀態 ——
        if let s = introStart {
            let t = now - s
            if t < introDuration { playIntro(t, maxX: maxX); return }
            introStart = nil
            grayView.isHidden = true
            idleSince = now
        }
        if off {
            heartView.isHidden = true; horseView.isHidden = true
            grayView.isHidden = false; grayView.alphaValue = 1
            grayView.image = grayFrames[0]
            crabView.image = framesRight[0]
            let y: CGFloat = -5                                // 趴下：身體沉到底
            crabView.setFrameOrigin(NSPoint(x: posX, y: y))
            grayView.setFrameOrigin(NSPoint(x: posX, y: y))
            // z 每 1.6 秒從頭頂冒一次，一格一格往上飄
            let p = CGFloat(now.truncatingRemainder(dividingBy: 1.6) / 1.6)
            zView.isHidden = p > 0.85
            zView.setFrameOrigin(NSPoint(x: posX + crabW - 2 + (p * 6).rounded(), y: 8 + (p * 12).rounded()))
            return
        }
        zView.isHidden = true

        // Heart: 8-bit pop — rises in whole-pixel steps and fades through discrete alpha levels.
        // The crab pauses ("reaching") while it shows.
        var reaching = false
        if let hs = heartStart {
            let t = now - hs
            if t < heartDuration {
                reaching = true
                let p = CGFloat(t / heartDuration)
                heartView.isHidden = false
                let baseX = posX + crabW / 2 - heartView.frame.width / 2
                let hx = min(max(0, baseX), width - heartView.frame.width).rounded()
                let rise = (p * 14).rounded()                       // whole-pixel rise
                heartView.setFrameOrigin(NSPoint(x: hx, y: 8 + rise))
                let levels: [CGFloat] = [1, 1, 0.8, 0.6, 0.4, 0.2]  // chunky retro fade
                heartView.alphaValue = levels[min(Int(p * CGFloat(levels.count)), levels.count - 1)]
            } else {
                heartView.isHidden = true
                heartStart = nil
            }
        }

        if reaching {
            crabView.setFrameOrigin(NSPoint(x: min(posX, maxX), y: 2))
            return
        }

        // Permission: Claude is waiting on you — the crab stops, faces a "help!" bubble that pops up.
        if permission {
            bubbleView.isHidden = false
            let bubW = bubbleView.frame.width
            var bx = posX + crabW - 6
            let onRight = bx + bubW <= width
            if !onRight { bx = posX - bubW + 8 }
            bx = min(max(0, bx), max(0, width - bubW))
            let pop = permSince.map { CGFloat(min(1, (now - $0) / 0.18)) } ?? 1
            bubbleView.setFrameOrigin(NSPoint(x: bx, y: 7 + pop * 3))

            idleAccum += dt
            if idleAccum >= 0.18 { idleAccum = 0; idleIndex += 1 }
            crabView.image = (onRight ? framesRight : framesLeft)[0]
            crabView.setFrameOrigin(NSPoint(x: min(posX, maxX), y: idleIndex % 2 == 0 ? 0 : 2))
            return
        }

        // Idle: bob → dance after danceDelay → after a minute of dancing, ride a horse across.
        if !active {
            if riding {
                horseX += horseSpeed * CGFloat(dt)
                horseAccum += dt
                if horseAccum >= 0.09 { horseAccum = 0; horseFrameIdx ^= 1 }
                horseView.image = horseFrames[horseFrameIdx]
                horseView.setFrameOrigin(NSPoint(x: horseX, y: 0))
                frameAccum += dt
                if frameAccum >= frameInterval { frameAccum = 0; frameIndex = (frameIndex + 1) % framesRight.count }
                crabView.image = framesRight[frameIndex]
                crabView.setFrameOrigin(NSPoint(x: horseX + 4, y: 8))   // perched on the horse's back
                if horseX > width {            // galloped off the far edge — reset the whole cycle
                    riding = false
                    horseView.isHidden = true
                    dancing = false
                    danceStart = nil
                    idleSince = now
                    posX = (maxX / 2).rounded()
                    NSLog("CrabTouchBar: ride end")
                }
                return
            }
            let idleDur = idleSince.map { now - $0 } ?? 0
            if idleDur >= danceDelay {
                if !dancing { dancing = true; danceStart = now }
                if let ds = danceStart, now - ds >= rideAfterDance {
                    riding = true
                    horseX = -horseFrames[0].size.width
                    horseView.isHidden = false
                    NSLog("CrabTouchBar: ride start")
                    return
                }
                danceAccum += dt
                if danceAccum >= danceStep { danceAccum = 0; danceIndex += 1 }
                let i = danceIndex % danceDX.count
                let frames = danceDX[i] < 0 ? framesLeft : framesRight
                crabView.image = frames[danceIndex % frames.count]
                let x = min(max(0, posX + danceDX[i]), maxX)
                crabView.setFrameOrigin(NSPoint(x: x, y: min(danceDY[i], barH - crabH)))
            } else {
                idleAccum += dt
                if idleAccum >= idleStep { idleAccum = 0; idleIndex += 1 }
                crabView.image = framesRight[0]
                crabView.setFrameOrigin(NSPoint(x: min(posX, maxX), y: idleBob[idleIndex % idleBob.count]))
            }
            return
        }

        guard maxX > 0 else { return }

        // Walk, bouncing at the edges (flip to face travel direction).
        posX += dir * walkSpeed * CGFloat(dt)
        if posX <= 0 { posX = 0; dir = 1 }
        if posX >= maxX { posX = maxX; dir = -1 }
        crabView.setFrameOrigin(NSPoint(x: posX, y: 0))

        frameAccum += dt
        if frameAccum >= frameInterval {
            frameAccum = 0
            frameIndex = (frameIndex + 1) % framesRight.count
            crabView.image = (dir >= 0 ? framesRight : framesLeft)[frameIndex]
        }
    }

    /// 啟動動畫，總長 introDuration（2.6 秒），全部用整像素、分檔透明度，保持 8-bit 手感：
    /// 0.0–0.5 灰色趴著繼續睡 → 0.5–0.9 抖兩下醒了 → 0.9–1.4 灰色一格一格褪成橙色、站起來
    /// → 1.4–1.8 原地蹦一下 → 1.8–2.6 走到中間，然後交給正常狀態。
    func playIntro(_ t: TimeInterval, maxX: CGFloat) {
        zView.isHidden = true
        heartView.isHidden = true
        let target = (maxX / 2).rounded()
        var x = introFromX, y: CGFloat = -5
        var img = framesRight[0]
        var grayAlpha: CGFloat = 1

        switch t {
        case ..<0.5:
            break
        case ..<0.9:                                    // 抖：左右各 1 像素
            x += (Int(t / 0.05) % 2 == 0) ? 1 : -1
        case ..<1.4:                                    // 褪色 + 站起來
            let p = CGFloat((t - 0.9) / 0.5)
            let levels: [CGFloat] = [1, 0.75, 0.5, 0.25, 0]
            grayAlpha = levels[min(Int(p * 5), 4)]
            y = -5 + (p * 5).rounded()
        case ..<1.8:                                    // 蹦一下
            let hop: [CGFloat] = [2, 5, 7, 7, 5, 2, 0, 0]
            y = hop[min(Int((t - 1.4) / 0.05), hop.count - 1)]
            grayAlpha = 0
        default:                                        // 走到中間
            let p = CGFloat(min(1, (t - 1.8) / 0.8))
            let e = 1 - pow(1 - p, 3)                   // ease-out
            x = (introFromX + (target - introFromX) * e).rounded()
            y = 0
            grayAlpha = 0
            img = framesRight[Int(t / frameInterval) % framesRight.count]
        }
        crabView.image = img
        crabView.setFrameOrigin(NSPoint(x: x, y: y))
        grayView.isHidden = grayAlpha == 0
        grayView.alphaValue = grayAlpha
        grayView.image = grayFrames[0]
        grayView.setFrameOrigin(NSPoint(x: x, y: y))
        posX = x; dir = 1
    }

    /// 狀態來源：優先讀 claude-status-bar 的 state.json（以後裝了 hooks 就自動用上，能分出「等你批准」）；
    /// 沒有就用陛下原有的 /Users/a0000/Claude/claude-state.py（讀 transcript 最後一條消息）。
    /// 在後台線程跑，不卡動畫。
    func pollState() {
        if polling { return }
        polling = true
        let statePath = self.statePath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let running = Self.claudeRunning()
            var st = "idle"
            if let d = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let s = obj["state"] as? String {
                st = s
            } else if running {
                st = Self.run("/usr/bin/python3", ["/Users/a0000/Claude/claude-state.py"]) == "busy" ? "thinking" : "idle"
            }
            DispatchQueue.main.async { self?.apply(running: running, st: st); self?.polling = false }
        }
    }

    static func run(_ exe: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 和 claude-anim.py 同一個判斷：Claude 桌面版裡的 claude-code 進程在不在。
    static func claudeRunning() -> Bool {
        run("/bin/ps", ["-axo", "args"]).split(separator: "\n").contains {
            $0.contains("claude-code/") && $0.contains("claude.app/Contents/MacOS/claude")
        }
    }

    func setStatus(_ word: String, r: CGFloat, g: CGFloat, b: CGFloat) {
        stateWord = word
        statusBox.layer?.backgroundColor = NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1).cgColor
    }

    func apply(running: Bool, st: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if off && running {                              // 剛被打開：播啟動動畫
            introStart = now
            introFromX = posX
            NSLog("ClaudePigCrab: wake intro")
        }
        if !off && !running { posX = min(posX, 8) }     // 關了：回左邊趴下
        off = !running
        let nowActive = running && (st == "thinking" || st == "tool")
        let nowPerm = running && st == "permission"
        if !running { setStatus("睡了", r: 60, g: 60, b: 64) }
        else if nowPerm { setStatus("等你批", r: 170, g: 110, b: 20) }
        else if nowActive { setStatus("干活中", r: 30, g: 70, b: 140) }
        else { setStatus("摸鱼中", r: 28, g: 28, b: 32) }
        permission = nowPerm
        permSince = nowPerm ? (permSince ?? now) : nil
        if nowActive {
            idleSince = nil          // working: cancel any idle/dance/ride countdown
            dancing = false; danceStart = nil
            if riding { riding = false; horseView?.isHidden = true }
        } else if idleSince == nil {
            idleSince = now           // just went idle: start the clock
        }
        active = nowActive
    }

    func applicationWillTerminate(_ note: Notification) {
        if touchBar != nil { dismissSystemModal(touchBar) }
        dfrSetPresence?(trayId.rawValue as NSString, false)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
