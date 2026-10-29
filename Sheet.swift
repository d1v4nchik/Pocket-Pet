// Debug renders for checking the art: `PocketPet --sheet out.png [species]`

import Cocoa
import SwiftUI

let canvasW = 64, canvasH = 52

/// Optional hat for every pose in a sheet: `PocketPet --sheet out.png goose party`
var sheetHat: Hat?

func renderSheet(_ path: String, only: String? = nil) {
    let key = only == "key"
    let s: CGFloat = only == nil ? 2 : (key ? 3 : 5)
    var cells: [(String, Canvas, [CGColor])] = []

    func add(_ name: String, _ sp: Species, _ edit: (inout Pose) -> Void) {
        var p = Pose()
        edit(&p)
        if let h = sheetHat, !p.nightcap { p.outfit.hat = h }
        var c = Canvas(canvasW, canvasH)
        drawPet(&c, sp, p, cx: canvasW / 2)
        c.outline()
        cells.append((name, c, makePalette(sp.colors)))
    }

    if key {
        for sp in Species.allCases {
            add(sanitize(sp.title), sp) { _ in }
            add("SIT", sp) { $0.stance = .sit; $0.tailUp = false }
            add("HAPPY", sp) { $0.eyes = .happy; $0.mouth = sp.family == .dog ? .tongue : .open; $0.blush = true; if !sp.isBird { $0.stance = .sit } }
        }
    }
    for sp in Species.allCases where only == nil || sp.rawValue == only {
        add(sanitize(sp.title), sp) { _ in }
        add("WALK", sp) { $0.stance = .walk; $0.phase = 1.2 }
        add("SIT", sp) { $0.stance = .sit; $0.tailUp = false }
        add("TYPE", sp) { $0.stance = .sit; $0.prop = .laptop; $0.arm = .tap; $0.tailUp = false; if sp == .goose { $0.headDX = 2; $0.headDY = 7 } else { $0.headDY = 1 } }
        add("TYPE 2", sp) { $0.stance = .sit; $0.prop = .laptop; $0.arm = .forward; $0.tailUp = false; if sp == .goose { $0.headDX = 2; $0.headDY = 7 } }
        add("POPCORN", sp) { $0.stance = .sit; $0.prop = .popcorn; $0.arm = sp.isBird ? .forward : .scoop; $0.eyes = .up; $0.tailUp = false }
        add("MUSIC", sp) { $0.stance = sp.isBird ? .stand : .sit; $0.phones = true; $0.eyes = .happy; $0.tailUp = false }
        add("CALENDAR", sp) { $0.stance = .sit; $0.prop = .calendar; $0.arm = .hold; $0.tailUp = false }
        add("WATER", sp) { $0.stance = .sit; $0.prop = .glass; $0.arm = sp.isBird ? .forward : .hold; $0.tailUp = false }
        add("SIP", sp) { $0.stance = .sit; $0.prop = .glass; $0.arm = sp.isBird ? .forward : .toMouth; $0.eyes = .happy; $0.tailUp = false }
        add("NAP", sp) { $0.stance = sp.isBird ? .sit : .curl; $0.eyes = .closed; if sp == .goose { $0.headDX = -1; $0.headDY = 12 } else if sp.isBird { $0.headDY = 3 } }
        add("SLEEP", sp) { $0.stance = sp.isBird ? .sit : .curl; $0.eyes = .closed; $0.nightcap = true; if sp == .goose { $0.headDX = -1; $0.headDY = 12 } else if sp.isBird { $0.headDY = 3 } }
        if sp.isBird {
            let goose = sp == .goose
            add("PECK", sp) { $0.headDX = goose ? 4 : 3; $0.headDY = goose ? 24 : 9; $0.eyes = .closed }
            add("PREEN", sp) { $0.headDX = goose ? -2 : -3; $0.headDY = goose ? 11 : 2; $0.eyes = .closed }
            add("SNACK", sp) { $0.stance = .sit; $0.prop = .popcorn; $0.headDX = goose ? 4 : 3; $0.headDY = goose ? 13 : 4; $0.eyes = .closed }
            add("GAZE", sp) { $0.eyes = .up; $0.headDY = -2 }
            add("FLY", sp) { $0.stance = .fly; $0.arm = .raised }
            add("FLY 2", sp) { $0.stance = .fly; $0.arm = .down }
            add("HONK", sp) { $0.mouth = .open; $0.arm = .raised; $0.eyes = .wide }
        } else {
            add("LIE", sp) { $0.stance = .lie; $0.eyes = .half }
            add("STRETCH", sp) { $0.stance = .stretch; $0.eyes = .closed; $0.mouth = .open }
            add("HUNT", sp) { $0.stance = .crouch; $0.eyes = .wide; $0.wiggle = 1 }
            add("LEAP", sp) { $0.stance = .leap; $0.eyes = .wide }
            add("UPRIGHT", sp) { $0.stance = .upright; $0.eyes = .happy; $0.mouth = .tongue }
            add("EAT", sp) { $0.stance = .eat; $0.eyes = .happy }
            add("UMBRELLA", sp) { $0.stance = .umbrella }
            add("HELD", sp) { $0.stance = .held }
            add("HAPPY", sp) { $0.eyes = .happy; $0.mouth = .open; $0.blush = true }
        }
    }
    if only == nil {
        let outfits: [Outfit] = [
            Outfit(hat: .topHat, glasses: .none, neck: .bowtie), Outfit(hat: .crown, glasses: .hearts, neck: .none),
            Outfit(hat: .party, glasses: .none, neck: .scarf), Outfit(hat: .crown, glasses: .round, neck: .bell),
            Outfit(hat: .witch, glasses: .none, neck: .bandana), Outfit(hat: .cowboy, glasses: .shades, neck: .none),
            Outfit(hat: .bow, glasses: .none, neck: .bell), Outfit(hat: .flower, glasses: .round, neck: .scarf),
        ]
        for (i, o) in outfits.enumerated() {
            let sp = [Species.goose, .ginger, .calico, .dalmatian, .siamese, .tuxedo, .ginger, .dalmatian][i]
            add("OUTFIT", sp) { $0.outfit = o; $0.stance = sp.isBird ? .stand : .sit; $0.tailUp = false }
        }
        for k in [ItemKind.fish, .milk, .bread, .cheese, .berry, .sausage, .cookie, .ball, .yarn] {
            cells.append(("ITEM", itemCanvas(k, bites: 0, frame: 0), basePalette))
        }
        for (i, bp) in butterflyPalettes.enumerated() { cells.append(("BFLY", itemCanvas(.butterfly, bites: 0, frame: 0, variant: i), makePalette(bp))) }
        for i in 0..<4 { cells.append(("RANDOM", itemCanvas(.butterfly, bites: 0, frame: i == 3 ? 1 : 0, variant: i), makePalette(randomButterflyPalette()))) }
    }

    let cols = only == nil ? 10 : (key ? 9 : 6)
    let cellW = CGFloat(canvasW) * s + 8, cellH = CGFloat(canvasH) * s + 22
    let rowsN = (cells.count + cols - 1) / cols
    let W = Int(CGFloat(cols) * cellW), H = Int(CGFloat(rowsN) * cellH)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(false)
    ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.90, blue: 0.86, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for (i, cell) in cells.enumerated() {
        let ox = CGFloat(i % cols) * cellW + 4, oy = CGFloat(i / cols) * cellH + 4
        ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.95, blue: 0.92, alpha: 1))
        ctx.fill(CGRect(x: ox, y: oy, width: CGFloat(canvasW) * s, height: CGFloat(canvasH) * s))
        let c = cell.1
        cell.1.draw(ctx, ox + (CGFloat(canvasW - c.w) * s) / 2, oy + (CGFloat(canvasH - c.h) * s) / 2, s, cell.2)
        drawText(cell.0, ctx, ox, oy + CGFloat(canvasH) * s + 4, 2, basePalette[1])
    }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Renders the control panel to a PNG (for checking the UI): `PocketPet --panel out.png <tab>`
@MainActor func renderPanel(_ path: String, tab: Int) {
    plainGlass = true
    let w = World()
    w.hidden = true
    w.load()
    w.ui.world = w
    w.ui.tab = tab >= 10 ? 3 : tab          // 11-13: Settings with a calendar way open
    if tab >= 10 && tab < 20 { w.ui.calWay = tab - 10 }
    if tab == 2 || tab == 20 { w.ui.tab = 2; w.player.preview(connected: tab == 20) }
    let savedOpen = UserDefaults.standard.stringArray(forKey: "openSections")
    defer { UserDefaults.standard.set(savedOpen, forKey: "openSections") }      // your real menu keeps its sections
    if w.ui.tab == 3 { w.ui.open = ["Pet", "Water", "Reminders"] }
    w.hidden = false                // windows were never shown; this just keeps the menu's header normal
    w.pet.mode = .idle
    w.pet.renderCanvas()
    // on a white panel over the same backdrop as the cards, so it reads on light and dark pages alike
    let r = ImageRenderer(content: RootView(m: w.ui)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .padding(20).background(Color.gray.opacity(0.4)))
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Renders the pet walking on each edge (floor, right wall, ceiling, left wall): `PocketPet --edges out.png`
@MainActor func renderEdges(_ path: String) {
    let w = World()
    w.hidden = true
    w.sizeSetting = 4
    let pet = Pet(world: w, record: PetRecord(id: "x", species: .ginger, name: "Mango", outfit: Outfit(hat: .party), fullness: 80, happiness: 80, energy: 80, x: 0))
    w.pet = pet
    pet.mode = .walk
    let side = pet.side
    let W = Int(side * 4 + 30), H = Int(side + 20)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(CGColor(gray: 0.85, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for e in 0..<4 {
        pet.edge = e
        pet.renderCanvas()
        ctx.saveGState()
        ctx.translateBy(x: 10 + CGFloat(e) * (side + 4), y: 10)
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        let wall: CGRect = [CGRect(x: 0, y: side - 3, width: side, height: 3), CGRect(x: side - 3, y: 0, width: 3, height: side),
                            CGRect(x: 0, y: 0, width: side, height: 3), CGRect(x: 0, y: 0, width: 3, height: side)][e]
        ctx.fill(wall)
        pet.draw(ctx)
        ctx.restoreGState()
    }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Renders the agenda card from sample events: `PocketPet --card out.png`
@MainActor func renderCard(_ path: String) {
    plainGlass = true
    let d = Calendar.current.startOfDay(for: Date())
    func ev(_ h: Double, _ m: Double, _ title: String, all: Bool = false, day: Double = 0) -> CalEvent {
        let s = d.addingTimeInterval(day * 86400 + h * 3600 + m * 60)
        return CalEvent(id: title, title: title, start: s, end: s.addingTimeInterval(all ? 86400 : 3600), allDay: all)
    }
    let now = d.addingTimeInterval(9.75 * 3600)
    func at(_ e: CalEvent, _ place: String) -> CalEvent { var e = e; e.location = place; return e }
    // made-up sample day for the README
    let events = [ev(0, 0, "Mom's birthday", all: true), ev(0, 0, "Project due", all: true), at(ev(9, 15, "Team standup"), "Room 3"),
                  ev(10, 45, "Coffee with Alex"), at(ev(11, 30, "Design review"), "https://meet.google.com/abc"),
                  at(ev(12, 30, "Yoga"), "Studio, 2nd floor, 12 Main Street"), ev(13, 30, "Lunch"), ev(15, 0, "Study session"),
                  ev(18, 0, "Dentist"), ev(19, 30, "Movie night"), ev(9, 30, "Piano lesson", day: 1)]
    let late = d.addingTimeInterval(20.6 * 3600)
    let sp = MusicPlayer()
    sp.preview(connected: false)
    let view = VStack(spacing: 20) {
        AgendaView(agenda: Agenda.build(events, now: now))
        AgendaView(agenda: Agenda.build(events, now: late))
        MusicCardView(player: sp, model: MusicCardModel())
        WaterView(title: "Water break?", glasses: 3, goal: 8)
    }.padding(20).background(Color.gray.opacity(0.4))
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// The Advanced Settings window, drawn by the app itself (no screen recording needed): `PocketPet --settings-shot out.png Water`
@MainActor func renderSettingsWindow(_ path: String, pane: String) {
    let w = World()
    w.hidden = true
    w.load()
    w.ui.world = w
    let win = w.makeAdvancedWindow()
    win.contentView = NSHostingView(rootView: AdvancedSettingsView(m: w.ui, start: pane))
    win.setFrame(NSRect(x: -4000, y: 200, width: 720, height: 560), display: true)     // off screen
    win.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    // the window as the window server drew it (an app may always capture its own windows)
    typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let fn = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: Capture.self) }
    if let img = fn?(.null, 8, UInt32(win.windowNumber), 9)?.takeRetainedValue() {
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    win.orderOut(nil)
}

/// The README's screenshots in one picture, on the pets lineup's cream: the menu, today's calendar, the music card and
/// a water break, side by side. `PocketPet --screens out.png`
@MainActor func renderScreens(_ path: String) {
    plainGlass = true
    let w = World()
    w.hidden = true
    w.load()
    w.ui.world = w
    w.ui.tab = 0
    w.hidden = false
    w.pet.mode = .idle
    w.pet.renderCanvas()
    // a made-up cover for the sample song: a warm gradient, nothing real
    let cover = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { r in
        let g = NSGradient(colors: [NSColor(red: 1, green: 0.62, blue: 0.45, alpha: 1), NSColor(red: 0.93, green: 0.36, blue: 0.56, alpha: 1)])
        g?.draw(in: r, angle: -60)
        return true
    }
    ArtCache.put("preview:cover", cover)
    let d = Calendar.current.startOfDay(for: Date())
    func ev(_ h: Double, _ m: Double, _ title: String, _ place: String? = nil, all: Bool = false) -> CalEvent {
        let s = d.addingTimeInterval(h * 3600 + m * 60)
        var e = CalEvent(id: title, title: title, start: s, end: s.addingTimeInterval(all ? 86400 : 3600), allDay: all)
        e.location = place
        return e
    }
    // made-up sample day
    let events = [ev(0, 0, "Mom's birthday", all: true), ev(9, 15, "Team standup", "Room 3"), ev(10, 45, "Coffee with Alex"),
                  ev(11, 30, "Design review", "https://meet.google.com/abc"), ev(12, 30, "Yoga", "Studio, 2nd floor"),
                  ev(15, 0, "Study session"), ev(18, 0, "Dentist")]
    let sp = MusicPlayer()
    sp.preview(connected: false)
    let lift = { (v: AnyView) in v.shadow(color: .black.opacity(0.10), radius: 14, y: 5) }
    let menu = RootView(m: w.ui).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
    let view = HStack(alignment: .top, spacing: 26) {
        lift(AnyView(menu))
        lift(AnyView(AgendaView(agenda: Agenda.build(events, now: d.addingTimeInterval(9.75 * 3600)))))
        VStack(spacing: 22) {
            lift(AnyView(MusicCardView(player: sp, model: MusicCardModel())))
            lift(AnyView(WaterView(title: "Water break?", glasses: 3, goal: 8)))
        }
    }
    .padding(34)
    .background(Color(red: 0xfd / 255, green: 0xf3 / 255, blue: 0xe3 / 255))
    .environment(\.colorScheme, .light)
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// Every snack, toy and button icon, in color and in the menu's gray: `PocketPet --icons out.png`
func renderIcons(_ path: String) {
    let items: [ItemKind] = [.fish, .bone, .cookie, .yarn, .ball, .butterfly]
    var cans = items.map { itemCanvas($0, bites: 0, frame: 0) }
    var pals = items.map { $0 == .butterfly ? makePalette(butterflyPalettes[1]) : basePalette }
    for ic in [Icon.moon, .sun, .pin, .roam, .anchor, .still] { cans.append(iconCanvas(ic)); pals.append(basePalette) }
    let k = 10, cell = 16 * k
    let W = cell * cans.count, H = cell * 2
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.82, alpha: 1)); ctx.fill(CGRect(x: 0, y: cell, width: W, height: cell))
    ctx.setFillColor(CGColor(gray: 0.22, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: cell))
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    for (i, c) in cans.enumerated() {
        c.draw(ctx, CGFloat(i * cell + k), CGFloat(k), CGFloat(k), pals[i])
        c.draw(ctx, CGFloat(i * cell + k), CGFloat(cell + k), CGFloat(k), grayPalette(pals[i]))
    }
    if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
}

/// The app icon: a pixel paw print (for every kind of pet) on a soft rounded square. `PocketPet --appicon dir.iconset`
func renderAppIcon(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var c = Canvas(21, 21)
    func blob(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
        for y in 0..<21 { for x in 0..<21 {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1 { c.set(x, y, dx < -0.2 && dy < -0.2 ? .blush : .nose) }
        } }
    }
    blob(10.5, 14.8, 5.2, 4.2)                         // the big pad
    for (x, y) in [(3.0, 9.6), (7.2, 5.2), (13.8, 5.2), (18.0, 9.6)] { blob(x, y, 2.0, 2.5) }   // toes, a gap between each
    c.outline()
    let face = c.trimmed(0)
    let pal = makePalette([.nose: 0xff8fa8, .blush: 0xffc2cf])
    for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                       (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
        let S = CGFloat(px)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        // Apple's icon grid: the tile is ~80% of the canvas, centered
        let inset = S * 0.1, tile = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
        let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
        ctx.addPath(path); ctx.setFillColor(cgColor(0xfdf3e3)); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(cgColor(0xead9bf)); ctx.setLineWidth(max(1, S / 128)); ctx.strokePath()
        // whole pixels only, so it stays crisp
        let cell = max(1, floor(tile.width * 0.72 / CGFloat(max(face.w, face.h))))
        let fw = CGFloat(face.w) * cell, fh = CGFloat(face.h) * cell
        ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false)
        face.draw(ctx, ((S - fw) / 2).rounded(), ((S - fh) / 2 + cell * 0.5).rounded(), cell, pal)
        if let img = ctx.makeImage() {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
        }
    }
}

/// Every pet in a row, in color, for the README: `PocketPet --hero out.png`
func renderHero(_ path: String) {
    let looks: [(Species, Outfit)] = [(.goose, Outfit(hat: .party)), (.parrot, Outfit(hat: .crown)), (.ginger, Outfit(neck: .bell)),
                                      (.siamese, Outfit(hat: .bow)), (.tuxedo, Outfit(hat: .topHat, neck: .bowtie)), (.calico, Outfit(hat: .flower)),
                                      (.dalmatian, Outfit(glasses: .shades, neck: .bandana)), (.fox, Outfit()), (.bat, Outfit(hat: .witch))]
    let pics = looks.map { sp, o -> (Canvas, [CGColor]) in
        var p = Pose(); p.outfit = o
        if !sp.isBird { p.stance = .sit; p.tailUp = sp == .fox }       // the fox shows off its tail
        if sp == .dalmatian { p.mouth = .tongue }
        var c = Canvas(canvasW, canvasH)
        drawPet(&c, sp, p, cx: canvasW / 2)
        c.outline()
        return (c.trimmed(0), makePalette(sp.colors))
    }
    let k = 6, gap = 6, pad = 10
    let H = (pics.map { $0.0.h }.max() ?? 0) + 2 * pad
    let W = pics.reduce(0) { $0 + $1.0.w } + gap * (pics.count - 1) + 2 * pad
    guard let ctx = CGContext(data: nil, width: W * k, height: H * k, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(cgColor(0xfdf3e3)); ctx.fill(CGRect(x: 0, y: 0, width: W * k, height: H * k))
    ctx.translateBy(x: 0, y: CGFloat(H * k)); ctx.scaleBy(x: 1, y: -1)
    var x = pad
    for (c, pal) in pics {
        c.draw(ctx, CGFloat(x * k), CGFloat((H - pad - c.h) * k), CGFloat(k), pal)      // all standing on one line
        x += c.w + gap
    }
    if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
}

/// One pet wearing every hat, a few poses each: `PocketPet --hatrack out.png bat`
func renderHatRack(_ path: String, _ sp: Species) {
    var cells: [Canvas] = []
    for h in Hat.allCases where h != .none {
        for stance in (sp.isBird ? [Stance.stand, .fly] : [.sit, .walk]) {
            var p = Pose(); p.outfit.hat = h; p.stance = stance; p.tailUp = false
            var c = Canvas(canvasW, canvasH)
            drawPet(&c, sp, p, cx: canvasW / 2)
            c.outline()
            cells.append(c)
        }
    }
    let k = 4, cols = 6, cw = canvasW * k, ch = canvasH * k
    let rows = (cells.count + cols - 1) / cols
    guard let ctx = CGContext(data: nil, width: cols * cw, height: rows * ch, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(cgColor(0xf5efe6)); ctx.fill(CGRect(x: 0, y: 0, width: cols * cw, height: rows * ch))
    ctx.translateBy(x: 0, y: CGFloat(rows * ch)); ctx.scaleBy(x: 1, y: -1)
    for (i, c) in cells.enumerated() { c.draw(ctx, CGFloat(i % cols * cw), CGFloat(i / cols * ch), CGFloat(k), makePalette(sp.colors)) }
    if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
}
