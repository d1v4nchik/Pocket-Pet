// Pocket Pet — a little pixel pet (a goose, cats or a dalmatian) that lives on your desktop.
//
// They wander, type along with you, watch videos with popcorn,
// listen to music in headphones, nap when you're away, and wake up when you're back.
// Feed it, pet it, dress it up, throw it around, turn off gravity, or ask it what's on your calendar.
//
// Privacy: typing is detected from the system keystroke counter (never the keys themselves).

import Cocoa
import SwiftUI

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
if let i = args.firstIndex(of: "--bubble-shot"), i + 2 < args.count {
    // a speech bubble with these lines, as the pet would say them (to check other scripts)
    let lines = args[(i + 2)...].map(sanitize)
    let px: CGFloat = 4
    let sz = bubbleSize(lines, px: px)
    let W = Int(sz.width) + 8, H = Int(sz.height) + 20
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(CGColor(gray: 0.85, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.setShouldAntialias(false)
    drawBubble(ctx, lines, bx: 4, by: 4, tipX: CGFloat(W / 2), px: px, tailUp: false)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    print(lines)
    exit(0)
}
if args.contains("--bat-test") {
    // the bat: free flight with gravity off, flying down for a snack with gravity on; and feeding a pet that isn't
    // the main one (your settings are put back after)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let d = UserDefaults.standard
        let keys = ["multiPets", "companions", "pet", "gravity", "restingPets"]
        let saved = keys.map { ($0, d.object(forKey: $0)) }
        defer { for (k, v) in saved { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        let w = World()
        w.hidden = true
        w.load()
        w.setMultiPets(false)
        w.changeSpecies(to: .bat)
        let bat = w.pet!
        w.idleSecs = 5; w.stillness = 0
        func run(_ secs: Double, _ each: () -> Void = {}) {
            for _ in 0..<Int(secs * 10) {
                w.t += 0.1; w.updateStats(0.1); for q in w.pets { q.update(0.1) }
                for it in w.items where !it.gone { it.update(0.1, world: w) }
                w.items.removeAll { $0.gone }; each()
            }
        }
        w.setGravity(true); run(10)
        print("gravity on: edge \(bat.edge) (2 = hanging from the top), in the air: \(bat.inAir), mode \(bat.mode)")
        w.setGravity(false)
        var air = 0.0, flights = 0, wasAir = false, xs = Set<Int>(), ys = Set<Int>()
        run(180) {
            if bat.inAir { air += 0.1; xs.insert(Int(bat.x / 100)); ys.insert(Int(bat.y / 100)) }
            if bat.inAir && !wasAir { flights += 1 }
            wasAir = bat.inAir
        }
        print("gravity off, 3 minutes: \(flights) flights, flying \(Int(air / 1.8))% of the time, over \(xs.count)x\(ys.count) squares of 100 pt, now \(bat.mode) edge \(bat.edge)")
        w.setGravity(true); run(20)
        print("gravity back on: in the air \(bat.inAir), edge \(bat.edge), mode \(bat.mode)")
        bat.fullness = 40
        w.feed(.berry)
        var ate = false, wentDown = false, secs = 0.0
        let before = bat.fullness
        run(40) { secs += 0.1; if bat.inAir { wentDown = true }; if bat.fullness > before && !ate { ate = true; print("  ate the berries after \(String(format: "%.1f", secs)) s") } }
        print("snack on the floor: flew down \(wentDown), ate it \(ate), food left \(w.items.filter { $0.isFood && !$0.gone }.count), back home: edge \(bat.edge) in air \(bat.inAir)")
        // several pets: food for a pet that isn't the main one goes to that pet
        w.setMultiPets(true)
        w.changeSpecies(to: .ginger)
        for c in w.companions { w.toggleCompanion(c.species) }
        w.toggleCompanion(.turtle)
        let main = w.pet!, panda = w.companions[0]
        run(8)
        main.fullness = 40; panda.fullness = 40
        let m0 = main.fullness, p0 = panda.fullness
        w.feed(.berry, for: panda)
        run(30)
        print("fed the turtle (not the main pet): turtle \(Int(p0)) -> \(Int(panda.fullness)), main pet \(Int(m0)) -> \(Int(main.fullness))")
        // a full pet leaves food alone, and the food goes away
        main.fullness = 95; panda.fullness = 95
        w.feed(.fish)
        run(5); let claimed = w.items.contains { $0.claim != nil }
        run(60)
        print("food nobody's hungry for: claimed \(claimed), still there after a minute: \(w.items.contains { $0.isFood })")
        // each pet's meters change on its own
        let before2 = (main.fullness, panda.fullness); run(120)
        print("two minutes later, food: main \(String(format: "%.2f", before2.0 - main.fullness)) down, turtle \(String(format: "%.2f", before2.1 - panda.fullness)) down")
        // nap and modes: all pets together, or just the one
        let savedTogether = w.modesTogether
        w.modesTogether = true
        for q in w.pets where q.isAsleep { q.forcedNap = false; q.setMode(.idle) }      // both awake to start with
        w.toggleNap(for: main); run(4)
        print("together on, nap: main asleep \(main.isAsleep), turtle asleep \(panda.isAsleep)")
        w.toggleNap(for: main); run(4)
        w.modesTogether = false
        for q in w.pets where q.isAsleep { q.forcedNap = false; q.setMode(.idle) }
        w.toggleNap(for: panda); run(4)
        print("together off, nap the turtle: main asleep \(main.isAsleep), turtle asleep \(panda.isAsleep)")
        w.toggleNap(for: panda); run(4)
        w.cycleStillness(for: panda); w.cycleStillness(for: panda); w.cycleStillness(for: panda); run(3)
        print("together off, turtle to study: turtle \(panda.mode), main \(main.mode)")
        w.modesTogether = savedTogether
    }
    exit(0)
}
if args.contains("--social-test") {
    // every scene for each pair of species: does it play out, finish, and leave both pets free? (settings put back after)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let d = UserDefaults.standard
        let saved = ["multiPets", "companions", "pet", "playTogether", "restingPets"].map { ($0, d.object(forKey: $0)) }
        defer { for (k, v) in saved { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        let w = World()
        w.hidden = true
        w.load()
        w.setMultiPets(true)
        w.playTogether = true; w.idleSecs = 5; w.stillness = 0
        // picture strips of each scene, saved where SOCIAL_SHOTS points (one PNG per pair of species)
        let shots = ProcessInfo.processInfo.environment["SOCIAL_SHOTS"]
        func frame(_ ps: [Pet]) -> CGImage? {
            let mid = (ps[0].x + ps[1].x) / 2, W = 360, H = 112
            guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: 4))
            ctx.interpolationQuality = .none
            for q in ps { if let im = q.spriteImage() {
                let cxp = (q.x - mid) / w.scale * 2 + CGFloat(W) / 2
                ctx.draw(im, in: CGRect(x: cxp - CGFloat(im.width) / 2, y: 4 + q.hopY / w.scale * 2 - 2, width: CGFloat(im.width), height: CGFloat(im.height)))
            } }
            return ctx.makeImage()
        }
        func sheet(_ rows: [[CGImage]], _ name: String) {
            guard let dir = shots, !rows.isEmpty else { return }
            let cols = rows.map(\.count).max() ?? 1, W = 360, H = 112, k = 2
            guard let ctx = CGContext(data: nil, width: cols * W * k, height: rows.count * H * k, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cols * W * k, height: rows.count * H * k))
            ctx.interpolationQuality = .none
            for (r, row) in rows.enumerated() { for (c, im) in row.enumerated() {
                ctx.draw(im, in: CGRect(x: c * W * k + 2, y: (rows.count - 1 - r) * H * k + 2, width: W * k - 4, height: H * k - 4))
            } }
            guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(dir)/\(name).png") as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, out, nil); CGImageDestinationFinalize(dest)
        }
        let pairs: [(Species, Species, [Game])] = [
            (.ginger, .siamese, [.boop, .groom, .fight]), (.dalmatian, .fox, [.boop, .sniff, .chase, .fight]),
            (.calico, .fox, [.wary, .hiss]), (.dalmatian, .tuxedo, [.wary, .hiss, .snub]),
            (.goose, .ginger, [.honk, .boop]), (.fox, .goose, [.honk]), (.parrot, .dalmatian, [.mimic]), (.calico, .parrot, [.mimic]),
            (.redPanda, .ginger, [.fight, .groom]), (.redPanda, .dalmatian, [.hiss]), (.goose, .redPanda, [.honk])]
        for (a, b, games) in pairs {
            for c in w.companions { w.toggleCompanion(c.species) }
            w.changeSpecies(to: a); w.toggleCompanion(b)
            let p = w.pet!, f = w.companions[0]
            var rows: [[CGImage]] = []
            for g in games {
                p.x = 700; f.x = 1000
                for q in w.pets { q.food = nil; q.pal = nil; q.game = nil; q.setMode(.idle); q.happiness = 90; q.energy = 90; q.fullness = 90 }
                for _ in 0..<60 { w.t += 0.1; for q in w.pets { q.update(0.1) } }      // settle on the floor
                for q in w.pets { q.setMode(.idle); q.nextSocial = w.t + 999 }
                p.start(g, with: f)
                var kinds: [String] = [], secs = 0.0, closest = CGFloat.infinity
                var row: [CGImage] = [], state = "", snapAt = -1.0
                while (p.mode == .social || f.mode == .social) && secs < 45 {
                    w.t += 0.05; secs += 0.05
                    for q in w.pets { q.update(0.05) }
                    let now = "\(p.social)\(f.social)\(p.mode)\(f.mode)\(p.moving)\(f.moving)"
                    if now != state { state = now; snapAt = secs + 0.3 }
                    if snapAt > 0 && secs >= snapAt && row.count < 8 { snapAt = -1; if let im = frame([p, f]) { row.append(im) } }
                    for q in [p, f] where q.mode == .social {
                        let k = "\(q === p ? "A" : "B").\(q.social)"
                        if kinds.last != k && !kinds.suffix(4).contains(k) { kinds.append(k) }
                    }
                    closest = min(closest, abs(p.x - f.x))
                }
                let clean = p.pal == nil && f.pal == nil && p.mode != .social && f.mode != .social
                print("\(a.rawValue)+\(b.rawValue) \(g): \(String(format: "%.1f", secs))s \(clean ? "ok" : "STUCK") closest \(Int(closest / w.scale)) cells -> \(kinds.joined(separator: " "))")
                // afterwards: do they step apart instead of staying on top of each other?
                for _ in 0..<200 { w.t += 0.1; for q in w.pets { q.update(0.1) } }
                let gap = abs(p.x - f.x) / w.scale
                print("   20 s later: \(Int(gap)) cells apart, modes \(p.mode) / \(f.mode)")
                rows.append(row)
            }
            sheet(rows, "\(a.rawValue)-\(b.rawValue)")
        }
        // left alone for five minutes with three pets: which scenes happen, and how long any two stand stacked
        for c in w.companions { w.toggleCompanion(c.species) }
        w.changeSpecies(to: .ginger); w.toggleCompanion(.siamese); w.toggleCompanion(.dalmatian)
        for q in w.pets { q.nextSocial = w.t + Double.random(in: 5...20) }
        var games: [String: Int] = [:], stacked = 0.0
        for _ in 0..<3000 {
            w.t += 0.1
            for q in w.pets {
                let before = q.game
                q.update(0.1)
                if let g = q.game, before == nil { games["\(g)", default: 0] += 1 }
            }
            let ps = w.pets
            for i in 0..<ps.count { for j in (i + 1)..<ps.count {
                let a = ps[i], b = ps[j]
                if a.mode != .social && b.mode != .social && a.mode != .walk && b.mode != .walk && !(a.isAsleep && b.isAsleep)
                    && abs(a.x - b.x) < a.bodyHalf + b.bodyHalf { stacked += 0.1 }
            } }
        }
        print("five minutes, three pets: scenes \(games.sorted { $0.key < $1.key }), stacked at rest \(Int(stacked)) s")
        // names stay with the pet when another one becomes the main pet
        let names = w.pets.map { "\($0.species.rawValue)=\($0.name)" }
        w.rename(w.companions[0], "Biscuit")
        w.makeMain(w.companions[0])
        w.setOutfit(Outfit(hat: .crown), for: w.companions[1])
        let who = w.companions[1].species
        w.toggleCompanion(who); w.toggleCompanion(who)
        let back = w.companions.first { $0.species == who }
        print("sent home and brought back: name \(back?.name ?? "-"), hat \(back?.outfit.hat.rawValue ?? "-")")
        let names3 = w.companions.map(\.name)
        w.setMultiPets(false); w.setMultiPets(true)
        print("several pets off and on again: before \(names3), after \(w.companions.map(\.name))")
        print("names before: \(names); after renaming and making it main: \(w.pets.map { "\($0.species.rawValue)=\($0.name)" })")
    }
    exit(0)
}
if args.contains("--multi-test") {
    // several pets at once: add two, let them live for a while, save, load, remove (your settings are put back after)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let d = UserDefaults.standard
        let saved = ["multiPets", "companions", "pet", "restingPets"].map { ($0, d.object(forKey: $0)) }
        defer { for (k, v) in saved { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        let w = World()
        w.hidden = true
        w.load()
        w.setMultiPets(true)
        let other = Species.allCases.filter { $0 != w.pet.species }
        w.toggleCompanion(other[0]); w.toggleCompanion(other[1])
        w.playTogether = true; w.idleSecs = 5; w.stillness = 0
        var said: [String: Int] = [:], visits = 0, tags = 0
        var wasVisiting = Set<ObjectIdentifier>(), wasZooming = Set<ObjectIdentifier>()
        for _ in 0..<1200 {                      // two minutes
            w.t += 0.1
            for p in w.pets {
                p.update(0.1)
                let id = ObjectIdentifier(p)
                if p.visiting != nil, !wasVisiting.contains(id) { visits += 1; wasVisiting.insert(id) } else if p.visiting == nil { wasVisiting.remove(id) }
                if p.mode == .zoomies, !wasZooming.contains(id) { tags += 1; wasZooming.insert(id) } else if p.mode != .zoomies { wasZooming.remove(id) }
                if w.t < p.bubbleUntil, let line = p.bubbleLines.first { said[line, default: 0] += 1 }
            }
        }
        print("in two minutes: \(visits) visits, \(tags) dashes (tag), said: \(said.keys.sorted())")
        print("pets on the desktop: \(w.pets.map { $0.species.rawValue })")
        w.save()
        let w2 = World(); w2.hidden = true; w2.load()
        print("after loading again: \(w2.pets.map { $0.species.rawValue })")
        w2.toggleCompanion(other[0])
        print("after sending \(other[0].rawValue) home: \(w2.pets.map { $0.species.rawValue })")
        w2.setMultiPets(false)
        print("multiple pets off: \(w2.pets.map { $0.species.rawValue })")
    }
    exit(0)
}
if args.contains("--still-test") {
    // "completely still": counts how many different pictures and positions the pet shows over 20 seconds
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let w = World()
        w.hidden = true
        w.load()
        let p = w.pet!
        w.idleSecs = 0.2
        for (label, music, still) in [("roaming, music on", true, 0), ("completely still, music on", true, 2), ("completely still, quiet", false, 2)] {
            w.stillness = still; w.musicPlaying = music; w.stillMusic = true
            p.followUntil = 0; p.setMode(.idle)
            var frames = Set<[UInt8]>(), xs = Set<Int>()
            for i in 0..<200 { w.t += 0.1; p.update(0.1); if i > 20 { frames.insert(p.canvas.px); xs.insert(Int(p.x)) } }
            print("\(label): \(frames.count) different pictures, \(xs.count) positions, mode \(p.mode)")
        }
    }
    exit(0)
}
if args.contains("--startle-test") {
    // puts the pet to sleep in each kind of nap, starts music, and reports whether it jumped awake
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let w = World()
        w.hidden = true
        w.load()
        let p = w.pet!
        func run(_ label: String, forced: Bool, napLength: Double, startle: Bool, menuOpenFor: Double = 0) {
            w.startleOnMusic = startle; w.napLength = napLength; w.musicPlaying = false; w.idleSecs = 600
            p.followUntil = 0
            p.forcedNap = false; p.setMode(.idle)
            if forced { p.forcedNap = false; p.toggleNap() } else { p.forcedNap = false; p.setMode(.yawning) }
            for _ in 0..<40 { w.t += 0.1; p.update(0.1) }                 // falls asleep
            let before = p.mode
            w.musicPlaying = true                                         // press play
            w.idleSecs = 0.2                                              // you're right there
            w.t += menuOpenFor; p.modeT += menuOpenFor                    // ...in a menu that stays open a while (the pet's clock runs on)
            var hopped = false
            var scared = false
            for _ in 0..<15 { w.t += 0.1; p.update(0.1); if p.hopY > 0 || p.hopV > 0 { hopped = true }; if w.t < p.scaredUntil { scared = true } }
            let during = p.mode
            for _ in 0..<20 { w.t += 0.1; p.update(0.1) }
            print("\(label): \(before) -> \(scared ? "scared " : "")\(during) -> \(p.mode)\(hopped ? ", jolted" : "")")
        }
        run("natural nap", forced: false, napLength: 0, startle: true)
        run("nap button, until woken", forced: true, napLength: 0, startle: true)
        run("nap button, 15 min", forced: true, napLength: 900, startle: true)
        run("pressed play in the menu (open 6 s)", forced: true, napLength: 900, startle: true, menuOpenFor: 6)
        run("startle switched off", forced: true, napLength: 0, startle: false)
    }
    exit(0)
}
if let i = args.firstIndex(of: "--sanitize"), i + 1 < args.count {     // what a speech bubble can show of some text
    print(sanitize(args[i + 1]))
    exit(0)
}
if let i = args.firstIndex(of: "--card-shot"), i + 1 < args.count {
    // the music card in a real floating window, captured as macOS draws it (glass, edge and shadow)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let sp = MusicPlayer()
        sp.preview(connected: true)
        let card = FloatingCard()
        card.show(MusicCardView(player: sp, model: MusicCardModel()), tip: CGPoint(x: -3800, y: 300), below: false, until: .infinity)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let fn = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: Capture.self) }
        if let num = NSApp.windows.first(where: { $0.isVisible })?.windowNumber, let img = fn?(.null, 8, UInt32(num), 9)?.takeRetainedValue() {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        }
    }
    exit(0)
}
if let i = args.firstIndex(of: "--pets-shot"), i + 1 < args.count {
    // the menu's Pets tab with three pets, in a real window as macOS draws it (your pets are put back after)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let d = UserDefaults.standard
        let saved = ["multiPets", "companions", "pet", "restingPets"].map { ($0, d.object(forKey: $0)) }
        defer { for (k, v) in saved { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        let w = World()
        w.hidden = true
        w.load()
        w.setMultiPets(true)
        for c in w.companions { w.toggleCompanion(c.species) }
        let other = Species.allCases.filter { $0 != w.pet.species }
        w.toggleCompanion(other[0]); w.toggleCompanion(other[3])
        w.ui.world = w; w.ui.tab = 0
        if i + 2 < args.count, args[i + 2] == "music" { w.ui.tab = 2; w.player.preview(connected: true) }
        w.hidden = false
        let win = NSWindow(contentRect: NSRect(x: -3800, y: 200, width: 340, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: RootView(m: w.ui).padding(16).frame(width: 340).background(Color(nsColor: .windowBackgroundColor)))
        win.setContentSize(win.contentView!.fittingSize)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let fn = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: Capture.self) }
        if let img = fn?(.null, 8, UInt32(win.windowNumber), 9)?.takeRetainedValue() {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        for c in w.companions { c.panel.orderOut(nil) }
    }
    exit(0)
}
if let i = args.firstIndex(of: "--settings-shot"), i + 1 < args.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { renderSettingsWindow(args[i + 1], pane: i + 2 < args.count ? args[i + 2] : "Behaviour") }
    exit(0)
}
if let i = args.firstIndex(of: "--screens"), i + 1 < args.count {
    MainActor.assumeIsolated { renderScreens(args[i + 1]) }
    exit(0)
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
