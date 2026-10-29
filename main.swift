// Pocket Pet — a little pixel pet (a goose, cats or a dalmatian) that lives on your desktop.
//
// They wander, type along with you, watch videos with popcorn,
// listen to music in headphones, nap when you're away, and wake up when you're back.
// Feed it, pet it, dress it up, throw it around, turn off gravity, or ask it what's on your calendar.
//
// Privacy: typing is detected from the system keystroke counter (never the keys themselves).

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    let world = World()
    func applicationDidFinishLaunching(_ notification: Notification) { world.start() }
    func applicationWillTerminate(_ notification: Notification) { world.save() }
    /// Opening the app again (Spotlight, Finder) while it runs: bring the pet back, or open its menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        world.summon()
        return false
    }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    if i + 3 < args.count { sheetHat = Hat(rawValue: args[i + 3]) }
    renderSheet(args[i + 1], only: i + 2 < args.count ? args[i + 2] : nil)
    exit(0)
}
if let i = args.firstIndex(of: "--panel"), i + 2 < args.count {
    MainActor.assumeIsolated { renderPanel(args[i + 1], tab: Int(args[i + 2]) ?? 0) }
    exit(0)
}
if let i = args.firstIndex(of: "--ics"), i + 1 < args.count, let text = try? String(contentsOfFile: args[i + 1], encoding: .utf8) {
    for e in ICSCalendar.parse(text) { print(e.start, e.end, e.allDay ? "all-day" : "", e.title) }
    exit(0)
}
if args.contains("--agenda") {     // checks the Google sign-in: prints how many events it can see today and tomorrow
    var loaded = false
    DispatchQueue.global().async { Secrets.load(); DispatchQueue.main.async { loaded = true } }
    while !loaded { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    let g = Google()
    g.loadSecrets()
    g.refreshEvents {
        print("signed in: \(g.signedIn), has client: \(g.hasClient), events: \(g.events.count), status: \(g.status)")
        g.diagnose { print("google says:", $0) }
        let df = DateFormatter(); df.dateFormat = "EEE HH:mm"
        for e in g.events { print(" ", df.string(from: e.start), "-", df.string(from: e.end), e.allDay ? "allday" : "", "[\(sanitize(e.title))]", e.title.count) }
        let a = Agenda.build(g.events)
        print(a.date, a.allDay, a.empty ?? "", "more:", a.more)
        for r in a.rows + a.tomorrow { print("  ", r.time, "|", r.title, r.until ?? "") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(20))
    print("timed out"); exit(1)
}
if let i = args.firstIndex(of: "--card"), i + 1 < args.count {
    MainActor.assumeIsolated { renderCard(args[i + 1]) }
    exit(0)
}
if args.contains("--bench") {     // times one animation frame: pose + pixel canvas, and painting a Retina-size window
    MainActor.assumeIsolated {
        let w = World()
        w.hidden = true
        w.sizeSetting = 4
        let pet = Pet(world: w, record: PetRecord(id: "x", species: .ginger, name: "M", outfit: Outfit(), fullness: 80, happiness: 80, energy: 80, x: 0))
        w.pet = pet
        pet.mode = .walk; pet.moving = true
        let side = Int(pet.side * 2)
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: 2, y: 2)
        let n = 500
        var t0 = Date()
        for i in 0..<n { pet.walkT = Double(i) * 0.05; pet.renderCanvas() }
        let render = Date().timeIntervalSince(t0) / Double(n) * 1000
        t0 = Date()
        for _ in 0..<n { ctx.clear(CGRect(x: 0, y: 0, width: side, height: side)); pet.draw(ctx) }
        let paint = Date().timeIntervalSince(t0) / Double(n) * 1000
        t0 = Date()
        for _ in 0..<n { _ = pet.spriteImage() }
        let sprite = Date().timeIntervalSince(t0) / Double(n) * 1000
        print(String(format: "pose+canvas %.3f ms, window paint %.3f ms, small sprite %.3f ms per frame", render, paint, sprite))
        // the sprite must match the old full-size drawing, pixel for pixel, on every edge
        for edge in 0..<4 {
            pet.edge = edge
            let m = Int((pet.side / pet.s).rounded()) * 2
            let old = CGContext(data: nil, width: m, height: m, bitsPerComponent: 8, bytesPerRow: m * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            old.translateBy(x: 0, y: CGFloat(m)); old.scaleBy(x: 2 / pet.s, y: -2 / pet.s); old.setShouldAntialias(false)
            pet.draw(old)
            let a = old.makeImage()!, b = pet.spriteImage()!
            let da = a.dataProvider!.data! as Data, db = b.dataProvider!.data! as Data
            var lit = 0
            for i in stride(from: 3, to: da.count, by: 4) where da[i] > 0 { lit += 1 }
            print("edge \(edge): \(da == db ? "identical" : "DIFFERENT"), \(lit) pet pixels, size \(b.width)x\(b.height)")
        }
    }
    exit(0)
}
if let i = args.firstIndex(of: "--wincheck"), i + 1 < args.count {   // photographs a real pet window (kept behind other windows)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let w = World()
        w.hidden = true
        w.sizeSetting = 4
        let pet = Pet(world: w, record: PetRecord(id: "x", species: .goose, name: "H", outfit: Outfit(hat: .party), fullness: 80, happiness: 80, energy: 80, x: 0))
        w.pet = pet
        pet.mode = .idle
        pet.renderCanvas()
        let side = pet.side
        let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: side, height: side), styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        let v = PetView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        v.pet = pet
        win.contentView = v
        win.orderBack(nil)
        v.needsDisplay = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let fn = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: Capture.self) }
        // .optionIncludingWindow = 8, .boundsIgnoreFraming | .bestResolution = 1 | 8
        if let img = fn?(.null, 8, UInt32(win.windowNumber), 9)?.takeRetainedValue() {
            let rep = NSBitmapImageRep(cgImage: img)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            print("captured \(img.width)x\(img.height)")
        } else { print("capture failed") }
        win.orderOut(nil)
    }
    exit(0)
}
if let i = args.firstIndex(of: "--simfs"), i + 1 < args.count {   // simulates entering and leaving a fullscreen app
    MainActor.assumeIsolated {
        let w = World()
        w.hidden = true
        w.sizeSetting = 4
        w.soundOn = false; w.synth.enabled = false
        let sp = i + 2 < args.count ? Species(rawValue: args[i + 2]) ?? .ginger : .ginger
        let pet = Pet(world: w, record: PetRecord(id: "x", species: sp, name: "M", outfit: Outfit(), fullness: 80, happiness: 80, energy: 80, x: 0))
        w.pet = pet
        pet.spawnIn()
        let dt = 1.0 / 20
        func run(_ secs: Double, _ label: String, every: Double = 0.5) {
            var next = 0.0, elapsed = 0.0, edges = Set<Int>()
            while elapsed < secs {
                w.t += dt; elapsed += dt
                pet.update(dt)
                edges.insert(pet.edge)
                if elapsed >= next {
                    next += every
                    let a = pet.area()
                    print(String(format: "%@ t=%4.1f mode=%@ edge=%d y-from-top=%5.0f y-from-floor=%5.0f", label, elapsed, "\(pet.mode)", pet.edge, a.maxY - pet.y, pet.y - a.minY))
                }
            }
            print("\(label) edges visited: \(edges.sorted())")
        }
        if sp == .bat { run(40, "bat  ", every: 1); exit(0) }
        run(4, "floor", every: 2)
        w.fullscreen = true
        pet.environmentChanged()
        run(2.5, "jump ", every: 0.25)
        run(30, "top  ", every: 5)
        if let img = pet.spriteImage() {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        // a fullscreen video starts: back down to the bottom to watch
        w.videoPID = 1; w.lastVideoSeen = w.t
        for _ in 0..<3 { if w.fullscreenApp == false { pet.environmentChanged(); break } }
        run(3, "video", every: 0.5)
        w.videoPID = nil
        w.fullscreen = false
        pet.environmentChanged()
        run(6, "down ", every: 0.5)
    }
    exit(0)
}
if let i = args.firstIndex(of: "--bellprobe"), i + 1 < args.count {
    // runs the real banner watcher for 15 s and writes down what it saw
    var out = "trusted=\(AXIsProcessTrusted())\n"
    let w = BannerWatcher()
    let t0 = Date()
    w.log = { out += String(format: "%5.1f ", Date().timeIntervalSince(t0)) + $0 + "\n" }
    w.onNotice = { n in out += "NOTICE \(n.title) | \(n.detail) | app \(n.appBundle ?? "-")\n" }
    w.start()
    out += "running=\(w.running)\n"
    RunLoop.main.run(until: Date().addingTimeInterval(15))
    try? out.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}
if let i = args.firstIndex(of: "--ncprobe"), i + 1 < args.count {   // what Notification Center looks like through Accessibility
    var out = "trusted=\(AXIsProcessTrusted())\n"
    func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
    func dump(_ e: AXUIElement, _ depth: Int, _ budget: inout Int) {
        guard depth < 14, budget > 0 else { return }
        budget -= 1
        var names: CFArray?; AXUIElementCopyActionNames(e, &names)
        var size = CGSize.zero
        if let v = attr(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &size) }
        let text = [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXIdentifierAttribute]
            .compactMap { attr(e, $0) as? String }.filter { !$0.isEmpty }.map { String($0.prefix(28)) }.joined(separator: " | ")
        out += String(repeating: "  ", count: depth) + "\(attr(e, kAXRoleAttribute) as? String ?? "?") \(attr(e, kAXSubroleAttribute) as? String ?? "") \(Int(size.width))x\(Int(size.height)) [\((names as? [String] ?? []).joined(separator: ","))] \(text)\n"
        for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? []) { dump(c, depth + 1, &budget) }
    }
    if let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first {
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        for pass in 1...3 {
            var budget = 400
            out += "=== pass \(pass)\n"
            dump(app, 0, &budget)
            RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        }
    } else { out += "Notification Center not running\n" }
    try? out.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}
if let i = args.firstIndex(of: "--axcheck"), i + 1 < args.count {   // run with `open` so macOS judges this app, not the shell
    try? "trusted=\(AXIsProcessTrusted())\n".write(toFile: args[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}
// Updates (used by release.sh): make your signing key, sign a release, or try installing one without the internet.
if let i = args.firstIndex(of: "--make-update-key"), i + 1 < args.count {
    do { print(try Updater.makeKey(in: args[i + 1])); exit(0) } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
if let i = args.firstIndex(of: "--sign-update"), i + 2 < args.count {
    do { print(try Updater.sign(args[i + 1], keyFile: args[i + 2])); exit(0) } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
if let i = args.firstIndex(of: "--apply-update"), i + 2 < args.count {
    do {
        let zip = try Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
        let app = try Updater.install(zip: zip, signature: try String(contentsOfFile: args[i + 2], encoding: .utf8))
        print("installed into \(app.path)"); exit(0)
    } catch { print("refused: \(error.localizedDescription)"); exit(1) }
}
if let i = args.firstIndex(of: "--secrets-test"), i + 1 < args.count {   // round-trips connections through a throwaway file
    Secrets.fileOverride = URL(fileURLWithPath: args[i + 1])
    Secrets.set("test-token-123", "refreshToken"); Secrets.set("https://example.com/cal.ics", "icsURL"); Secrets.flush()
    Secrets.set(nil, "icsURL"); Secrets.set("https://example.com/other.ics", "icsURL"); Secrets.flush()
    Secrets.load()
    print("read back:", Secrets.get("refreshToken") ?? "-", Secrets.get("icsURL") ?? "-")
    exit(0)
}
if let i = args.firstIndex(of: "--appicon"), i + 1 < args.count {
    renderAppIcon(args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--hero"), i + 1 < args.count {
    renderHero(args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--hatrack"), i + 2 < args.count, let sp = Species(rawValue: args[i + 2]) {
    renderHatRack(args[i + 1], sp)
    exit(0)
}
if let i = args.firstIndex(of: "--icons"), i + 1 < args.count {
    renderIcons(args[i + 1])
    exit(0)
}
if let i = args.firstIndex(of: "--edges"), i + 1 < args.count {
    MainActor.assumeIsolated { renderEdges(args[i + 1]) }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
