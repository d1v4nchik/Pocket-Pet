// Everything around the pet: senses (typing, video, fullscreen, music, document word counts),
// snacks and toys, settings, saving, calendar reminders and the menu bar panel.

import Carbon
import Cocoa
import CoreAudio
import IOKit.pwr_mgt
import ServiceManagement
import SwiftUI
import UserNotifications

func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }
func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
func now() -> Double { CACurrentMediaTime() }

let anyInputEvent = CGEventType(rawValue: ~0)!

let numberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    return f
}()
func fmt(_ n: Int) -> String { numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)" }

final class Panel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Items (snacks, toys, butterflies)

final class ItemView: NSView {
    weak var item: Item?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let it = item, !it.blinkHidden else { return }
        ctx.setShouldAntialias(false)
        itemCanvas(it.kind, bites: it.bites, frame: it.frame, variant: it.variant).draw(ctx, 0, 0, it.scale, it.palette)
    }
    override func mouseDown(with event: NSEvent) { item?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { item?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { item?.mouseUp() }
}

final class Item {
    let kind: ItemKind
    var x: CGFloat, y: CGFloat
    var vx: CGFloat = 0, vy: CGFloat = 0
    var scale: CGFloat
    var bites = 0
    weak var claim: Pet?
    var refusedBy = false
    var held = false, onGround = false, gone = false, leaving = false, landed = false
    let born: Double
    var life: Double                       // snacks disappear when nobody eats them (sooner once refused)
    var spin = 0.0, flap = 0.0
    let variant = Int.random(in: 0..<4)       // a butterfly's wing pattern
    var target: CGPoint?
    var retarget = 0.0
    var grab = CGPoint.zero
    var downAt: CGPoint?
    var samples: [(Double, CGPoint)] = []
    var blinkHidden = false
    let palette: [CGColor]
    let panel: Panel
    let view: ItemView
    private var drawnKey = ""

    var isFood: Bool { kind != .ball && kind != .yarn && kind != .butterfly }
    var isBall: Bool { kind == .ball || kind == .yarn }
    var value: Double { kind == .bread || kind == .sausage ? 30 : (kind == .cookie ? 18 : 24) }
    var frame: Int { isBall ? Int(spin.rounded(.down)) : Int(flap * 10) % 4 }
    var resting: Bool { kind != .butterfly && !held && downAt == nil && abs(vx) < 1 && abs(vy) < 1 && (onGround || vx == 0) }

    init(kind: ItemKind, x: CGFloat, y: CGFloat, scale: CGFloat, t: Double, hidden: Bool) {
        self.kind = kind; self.x = x; self.y = y; self.scale = scale; born = t
        life = kind == .butterfly ? 40 : (kind == .ball || kind == .yarn ? 60 : 45)
        palette = kind == .butterfly ? makePalette(randomButterflyPalette()) : basePalette
        panel = Panel(size: CGSize(width: 14 * scale, height: 14 * scale))
        view = ItemView(frame: NSRect(x: 0, y: 0, width: 14 * scale, height: 14 * scale))
        view.item = self
        panel.contentView = view
        panel.ignoresMouseEvents = kind == .butterfly
        place()
        if !hidden { panel.orderFrontRegardless() }
    }

    func resize(_ s: CGFloat) {
        scale = s
        panel.setContentSize(NSSize(width: 14 * s, height: 14 * s))
        view.frame = NSRect(x: 0, y: 0, width: 14 * s, height: 14 * s)
        drawnKey = ""
    }

    func place() {
        let o = NSPoint(x: (x - 7 * scale).rounded(), y: (y - scale).rounded())
        if panel.frame.origin != o { panel.setFrameOrigin(o) }
    }

    func close() {
        gone = true
        panel.orderOut(nil)
    }

    func update(_ dt: Double, world: World) {
        if removeRequested { world.synth.play("poof"); close(); return }
        let s = scale, fdt = CGFloat(dt)
        let age = world.t - born
        if kind != .butterfly && claim == nil && !held && age > life {
            world.poof(at: CGPoint(x: x, y: y + 5 * s))
            close()
            return
        }
        blinkHidden = kind != .butterfly && claim == nil && age > life - 4 && Int(age * 6) % 2 == 0
        if kind == .butterfly {
            fly(dt, world: world)
        } else if !held {
            let a = world.area(near: CGPoint(x: x, y: y + 4))
            // a pet up on the edges gets its food floated over (decided by the pet it's for, not always your main pet;
            // a bat flies down for it instead)
            let floats = claim.map { $0.wallMode && $0.family != .bat } ?? false
            if world.gravity && !floats {
                if !(onGround && abs(vx) < 1) {
                    vy -= 2100 * fdt * s / 4
                    x += vx * fdt; y += vy * fdt
                }
                let r = world.xRange(7 * s)
                if x < r.lowerBound { x = r.lowerBound; vx = abs(vx) * 0.6 }
                if x > r.upperBound { x = r.upperBound; vx = -abs(vx) * 0.6 }
                let fl = world.floorY(x, y)
                if y <= fl {
                    y = fl
                    if vy < -260 {
                        if !landed || isBall && vy < -500 { world.synth.play(isBall ? "kick" : "pop") }
                        landed = true
                        vy = -vy * (isBall ? 0.6 : 0.22)
                    } else {
                        vy = 0
                    }
                    vx *= CGFloat(pow(isBall ? 0.45 : 0.002, dt))
                    if abs(vx) < 2 { vx = 0 }
                }
                onGround = y <= fl + 0.5 && abs(vy) < 1
            } else {
                if isFood, let p = claim, age > 0.6 {           // floats to whichever pet is eating it
                    let m = p.mouthPoint()
                    let dx = m.x - x, dy = m.y - y, d = max(1, hypot(dx, dy))
                    let sp = min(170 * s / 4, d * 3)
                    vx += (dx / d * sp - vx) * min(1, fdt * 4)
                    vy += (dy / d * sp - vy) * min(1, fdt * 4)
                } else {
                    let damp = CGFloat(pow(isBall ? 0.85 : 0.5, dt))
                    vx *= damp; vy *= damp
                    if hypot(vx, vy) < 2 { vx = 0; vy = 0 }
                }
                x += vx * fdt; y += vy * fdt
                if x < a.minX + 7 * s { x = a.minX + 7 * s; vx = abs(vx) * 0.8 }
                if x > a.maxX - 7 * s { x = a.maxX - 7 * s; vx = -abs(vx) * 0.8 }
                if y < a.minY { y = a.minY; vy = abs(vy) * 0.8 }
                if y > a.maxY - 14 * s { y = a.maxY - 14 * s; vy = -abs(vy) * 0.8 }
                onGround = false
            }
            if isBall { spin += Double(world.gravity ? vx : hypot(vx, vy) * (vx < 0 ? -1 : 1)) * dt / Double(4 * s) }
        }
        place()
        let m = NSEvent.mouseLocation
        let ignore = kind == .butterfly || !(held || downAt != nil || panel.frame.insetBy(dx: s, dy: s).contains(m))
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
        let key = "\(frame)-\(bites)-\(blinkHidden)"
        if key != drawnKey {
            drawnKey = key
            view.needsDisplay = true
        }
    }

    private func fly(_ dt: Double, world: World) {
        let s = scale
        flap += dt
        guard let pet = world.pet else { close(); return }
        let a = world.area(near: CGPoint(x: x, y: y))
        let age = world.t - born
        if age > 22 && !leaving {
            leaving = true
            target = CGPoint(x: x + (Bool.random() ? 1400 : -1400), y: a.minY + 700)
        }
        let near = hypot(pet.x - x, pet.y - y) < 90 * s / 4
        let hover = world.stillness == 1               // your pet is staying put: the butterfly flutters about right by it
        if !leaving && (target == nil || world.t > retarget || (near && !hover)) {
            if hover {
                let base = world.gravity && !pet.wallMode ? a.minY : pet.y
                target = CGPoint(x: clamp(pet.x + CGFloat(rnd(-90, 90)) * s / 4, a.minX + 30, a.maxX - 30),
                                 y: clamp(base + CGFloat(rnd(40, 120)) * s / 4, a.minY + 30, a.maxY - 40))
            } else if near {
                let tx = x + (x > pet.x ? 1 : -1) * CGFloat(rnd(140, 240))
                target = CGPoint(x: clamp(tx, a.minX + 30, a.maxX - 30), y: clamp(y + CGFloat(rnd(60, 160)) * s / 4, a.minY + 40, a.maxY - 40))
            } else {
                let base = world.gravity && !pet.wallMode ? a.minY : pet.y
                target = CGPoint(x: clamp(pet.x + CGFloat(rnd(-320, 320)), a.minX + 30, a.maxX - 30),
                                 y: clamp(base + CGFloat(rnd(45, 210)) * s / 4, a.minY + 30, a.maxY - 40))
            }
            retarget = world.t + rnd(1.5, 3.5)
        }
        if let tg = target {
            let dx = tg.x - x, dy = tg.y - y
            let d = max(1, hypot(dx, dy))
            let sp: CGFloat = (leaving ? 170 : (near ? 150 : 70)) * s / 4
            let stepLen = min(d, sp * CGFloat(dt))
            x += dx / d * stepLen
            y += dy / d * stepLen + CGFloat(sin(flap * 9)) * 0.9
        }
        if leaving {
            let all = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
            if !all.insetBy(dx: -60, dy: -60).contains(CGPoint(x: x, y: y)) || age > 34 { close() }
        }
    }

    /// Double-click a snack or toy and it goes away (a setting).
    static var doubleClickRemoves = true
    private var lastDown = 0.0
    var removeRequested = false

    func mouseDown() {
        let m = NSEvent.mouseLocation
        let n = now()
        if Item.doubleClickRemoves && n - lastDown < 0.35 { removeRequested = true }
        lastDown = n
        downAt = m
        grab = CGPoint(x: m.x - x, y: m.y - y)
        samples = [(now(), m)]
    }

    func mouseDragged() {
        guard let d = downAt else { return }
        let m = NSEvent.mouseLocation
        if !held && hypot(m.x - d.x, m.y - d.y) > 3 { held = true; vx = 0; vy = 0; onGround = false }
        guard held else { return }
        x = m.x - grab.x; y = m.y - grab.y
        let n = now()
        samples.append((n, m))
        samples.removeAll { n - $0.0 > 0.1 }
    }

    func mouseUp() {
        defer { downAt = nil }
        if held {
            held = false
            if let f = samples.first, let l = samples.last, l.0 - f.0 > 0.01 {
                vx = clamp((l.1.x - f.1.x) / CGFloat(l.0 - f.0), -2400, 2400)
                vy = clamp((l.1.y - f.1.y) / CGFloat(l.0 - f.0), -2400, 2400)
            }
        } else if isBall {
            vy = 480 * scale / 4
            vx = CGFloat(rnd(-220, 220))
            onGround = false
        }
    }
}

enum WaterUnit: Int, CaseIterable { case glasses, sips, ml, oz }

/// One of your own reminders: daily at a time, or every so often while you're at the computer.
struct Habit: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var every: Double = 0            // seconds of time at the computer between reminders; 0 = daily at hour:minute
    var hour = 9, minute = 0
    var lastShown: Date?

    var label: String {
        if every > 0 { return every >= 3600 ? "Every \(Int(every / 3600)) h" : "Every \(Int(every / 60)) min" }
        var c = DateComponents(); c.hour = hour; c.minute = minute
        let time = Calendar.current.date(from: c).map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
        return "Daily at \(time)"
    }
}

// MARK: - World

final class World: NSObject, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    var pet: Pet!
    var items: [Item] = []
    let synth = Synth()
    let google = Google()
    let macCal = MacCalendar()
    let ics = ICSCalendar()
    /// ManageBac's tasks and deadlines, from its calendar link: reminders the evening before and the morning of.
    let tasks = ICSCalendar(key: "managebacURL", days: 8)
    let agendaCard = FloatingCard()
    let musicCard = FloatingCard()
    private let musicModel = MusicCardModel()
    var lastPlay = 0.0                  // last time you played with the pet (it calms down when left alone)
    private var paused = false          // display asleep or screen locked: no frames at all
    private var lastSense = -1.0
    private var agendaShownAt = -10.0
    let player = MusicPlayer()
    let tabWatcher = TabWatcher()
    let bannerWatcher = BannerWatcher()
    let bellCard = FloatingCard()
    let toast = FloatingCard()
    let updater = Updater()
    private var nextUpdateCheckAt = Date().addingTimeInterval(20)     // by the real clock, so naps and sleep don't delay it
    private var hotKey: EventHotKeyRef?
    var notice: Notice?                 // what the bell is ringing for
    var menuOpen: Bool { popover.isShown || agendaCard.visible || musicCard.visible || bellCard.visible || waterCard.visible || habitCard.visible }
    var bellOn = true
    var bellTabs = true                 // also watch browser tabs (Safari, Chrome-based)
    private var lastRing = -100.0
    var waterEvery = 3600.0             // water reminders: seconds at the computer between them, 0 = off, -1 = adapts to your pace
    let waterCard = FloatingCard()
    // How water is counted (stored in millilitres, shown in your unit) and how much you aim for
    var waterUnit = WaterUnit.glasses
    var glassML = 250, sipML = 25
    var waterGoalMode = 0               // 0 a goal you set, 1 tailored to you
    var fixedGoalML = 2000
    var weightKG = 65.0, weightInLB = false
    var activity = 1                    // 0 light, 1 moderate, 2 very active
    var hotWeather = false
    var wakeMinutes = 8 * 60, bedMinutes = 23 * 60     // your day, for pacing and quiet nights (minutes after midnight)
    var quietAtNight = true
    private var activeSinceDrink = 0.0  // real seconds you've been at the computer since your last glass
    private var lastWall = Date()
    private var nextWaterTry = 0.0, waterSnoozes = 0
    private var sharing = false, hiddenForSharing = false
    let askCard = FloatingCard()
    private var nextTabPoll = 2.0
    let defaults = UserDefaults.standard
    var t = 0.0
    private var lastTick = 0.0
    private var timer: Timer?
    private var fps = 30.0, lowSince = 0.0

    // settings
    var gravity = true, sizeSetting = 4, sleepAfter = 120.0, soundOn = true, hidden = false
    var scale: CGFloat { CGFloat(sizeSetting) }
    var firstRun = false, awaySeconds = 0.0

    // senses
    var idleSecs = 0.0
    private var keyCounter: UInt32 = 0
    private var recentKeys: [Double] = []
    var lastKeyT = -1000.0, tapUntil = 0.0
    var videoPID: pid_t?, videoFrame: CGRect?, lastVideoSeen = -1000.0
    /// Apps making sound right now (asked off the main thread), so a muted clip in a document isn't taken for a video.
    private var soundingNow: [String] = [], videoScanning = false
    var fullscreen = false
    /// Fullscreen for anything but a video: pets head for the top edge. Fullscreen videos (YouTube...) keep them at the
    /// bottom, sitting in the black bar to watch; a short pause in the video doesn't send them back up.
    var fullscreenApp: Bool { fullscreen && !(videoPlaying || t - lastVideoSeen < 20) }
    /// In a fullscreen app the pet goes up to the top edge (climbing, or flying for birds), or stays at the bottom.
    var fullscreenClimb = true
    var fullscreenUp: Bool { fullscreenApp && fullscreenClimb }
    private var lastFullscreenApp = false
    private var fsOffSince: Double?
    var musicPlaying = false { didSet { if musicPlaying && !oldValue { musicStartedAt = t } } }
    var musicStartedAt = -1e9            // music starting mid-nap startles the pet
    var musicTitle = "", musicApp = ""

    // Advanced settings
    var stillness = 0                    // 0 moves around, 1 stays put (still grooms), 2 completely still
    var stillTyping = true, stillWatching = true, stillMusic = true    // ...and while staying put, still reacts to these
    var napLength = 0.0                  // the menu's nap: 0 = until you wake it, otherwise seconds
    var startleOnMusic = true            // music starting mid-nap makes it jump awake
    var followFor = 60.0                 // "come here": seconds, 0 = until you press the pin again
    var followSpeed = 1                  // 0 slow, 1 normal, 2 fast
    var showName = false
    /// Study mode: every pet sits and reads until you switch it off.
    var studying = UserDefaults.standard.bool(forKey: "studying") { didSet { UserDefaults.standard.set(studying, forKey: "studying") } }

    func toggleStudy() {
        studying.toggle()
        lastPlay = t
        if studying {
            for p in pets where !p.inAir && p.mode != .held { p.forcedNap = false; p.begin(.study) }
            pet.say(["STUDY TIME!"], 1.8)
        } else {
            for p in pets where p.mode == .study { p.setMode(.idle); if p.family == .bat && p.edge == 0 { p.swoop(home: true) } }     // the bat flies back up
            pet.say(["BREAK TIME!"], 1.6); pet.hearts(2)
        }
    }
    var volumes: [String: Double] = [:]  // Synth.categories (and "all") -> 0...1
    let habitCard = FloatingCard()
    var habits: [Habit] = []
    private var habitActive: [UUID: Double] = [:], habitSnoozed: [UUID: Double] = [:], showingHabit: UUID?
    private var notifiedPlaying: Bool?       // what Spotify/Music last told us
    private var nextAudioScan = 0.0
    private var musicAppRunning: Bool?
    var isNight = false
    private var nextCheck = 0.0, nextSave = 30.0, nextButterfly = 500.0, nextReminderCheck = 5.0, nextCalendar = 1e9

    // word count (only ever the document's own count)
    private var reminded = Set<String>()

    // panel
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let ui = UIModel()
    weak var popoverPet: Pet?
    /// Several pets at once (a setting): your pet, plus up to four companions picked in the Pets tab.
    var multiPets = false
    var playTogether = true              // several pets visit each other, play tag and nap together
    /// Several pets: nap, wake, stay put, freeze and study apply to all of them (on), or just the one you're looking after.
    var modesTogether = UserDefaults.standard.object(forKey: "modesTogether") as? Bool ?? true {
        didSet { UserDefaults.standard.set(modesTogether, forKey: "modesTogether") }
    }
    /// Modes act on every pet: the setting is on, or there's only one pet anyway.
    var together: Bool { modesTogether || companions.isEmpty }
    var companions: [Pet] = []
    var pets: [Pet] { [pet] + companions }
    static let maxCompanions = 4
    /// Pets you sent home: their names, outfits and moods, for when they come back.
    var resting: [PetRecord] = []
    private var uiTimer: Timer?
    private var imageCache: [String: NSImage] = [:]

    var typingNow: Bool { recentKeys.count >= 3 }
    var typingRecently: Bool { t - lastKeyT < 4 }
    var videoPlaying: Bool { videoPID != nil }
    /// Any mix of a private calendar link, a Google sign-in and the Mac's own calendars, all shown together.
    var useMacCalendar = true
    var macCalendarOn: Bool { useMacCalendar && macCal.authorized && !macCal.accounts.isEmpty }
    var calendarConnected: Bool { google.signedIn || ics.connected || macCalendarOn }
    var calendarEvents: [CalEvent] {
        var sources: [[CalEvent]] = []
        if ics.connected { sources.append(ics.events) }
        if google.signedIn { sources.append(google.events) }
        if macCalendarOn { sources.append(macCal.events) }
        // the same calendar often comes in two ways (say, its link and the Mac), so it's shown once
        func key(_ e: CalEvent) -> String { "\(e.title.lowercased().trimmingCharacters(in: .whitespaces))|\(Int(e.start.timeIntervalSince1970) / 60)" }
        var seen = Set<String>()
        return sources.joined().filter { seen.insert(key($0)).inserted }.sorted { $0.start < $1.start }
    }

    // MARK: Setup

    func start() {
        load()
        agendaCard.onClose = { [weak self] in self?.pet.agendaUntil = 0 }   // tapping the card ends the calendar pose too
        bellCard.onClose = { [weak self] in self?.bellLog("card hidden: \(Thread.callStackSymbols.dropFirst().prefix(4).map { $0.split(separator: " ").dropFirst(3).prefix(1).joined() }.joined(separator: " <- "))") }
        tabWatcher.onNotice = { [weak self] n in self?.ring(n) }
        bannerWatcher.onNotice = { [weak self] n in self?.ring(n) }
        if defaults.bool(forKey: "bellLog") { bannerWatcher.log = { [weak self] in self?.bellLog($0) } }
        tabWatcher.onRead = { [weak self] id in if self?.notice?.tabID == id { self?.dismissBell() } }   // read it in the browser already
        updater.onChange = { [weak self] in self?.updateBadge(); if self?.popover.isShown == true { self?.ui.refresh() } }
        UNUserNotificationCenter.current().delegate = self
        player.onChange = { [weak self] in
            guard let self else { return }
            if self.popover.isShown { self.ui.refresh() }
            if self.musicCard.visible { self.musicModel.tick &+= 1 }
        }
        synth.enabled = soundOn
        synth.setVolumes(volumes)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Secrets.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.google.loadSecrets(); self.ics.loadSecrets(); self.tasks.loadSecrets(); self.player.loadSecrets()
                self.nextCalendar = self.t        // fetch the calendar now that we can sign in
                self.ui.refresh()
            }
        }
        setupStatusItem()
        registerShortcut()
        pet.spawnIn()
        companions.forEach { $0.spawnIn() }
        lastTick = now()
        schedule(30)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pets.forEach { $0.environmentChanged() }
        }
        // React right away when switching Spaces or apps (that's when fullscreen changes).
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // right away, then a few more times while the desktop slides in
                for delay in [0, 0.08, 0.2, 0.4, 0.8, 1.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.checkFullscreen() }
                }
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.musicAppRunning = nil }
        }
        // Clicks reach the pet the moment the cursor is over it (and pass through as soon as it leaves),
        // whatever the frame rate: mouse moves are cheap events, not polling.
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.pets.forEach { $0.updateHover() } }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in self?.pets.forEach { $0.updateHover() }; return e }
        // The calendar and music cards close like menus: on any click outside them (mouse clicks need no permission).
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.clickedOutsideCards(onPet: false) }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.clickedOutsideCards(onPet: self?.pets.contains { e.window === $0.panel } ?? false)
            return e
        }
        // Nobody can see the pet: stop entirely until they're back.
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.pause(true) }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.pause(false) }
        }
        // back from sleep: look for an update soon (a laptop that's only ever closed and opened would wait otherwise)
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.nextUpdateCheckAt = min(self.nextUpdateCheckAt, Date().addingTimeInterval(30))
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.pause(true) }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.pause(false) }
        dnc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.musicNotification(n.userInfo, app: "Spotify")
        }
        dnc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.musicNotification(n.userInfo, app: "Music")
        }
        refreshNight()
        checkSystem()
    }

    private func pause(_ on: Bool) {
        guard on != paused else { return }
        paused = on
        if on {
            timer?.invalidate()
            timer = nil
        } else {
            lastTick = now()
            schedule(8)
        }
    }

    private func schedule(_ f: Double) {
        timer?.invalidate()
        let tm = Timer(timeInterval: 1 / f, repeats: true) { [weak self] _ in self?.tick() }
        tm.tolerance = 0.5 / f
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        fps = f
    }

    func tick() {
        let n = now()
        let dt = min(n - lastTick, 0.3)        // covers the slowest frame rate (4 a second while asleep), not long pauses
        lastTick = n
        t += dt
        sense()
        updateStats(dt)
        if !hidden { for p in pets { p.update(dt) } }
        for it in items where !it.gone { it.update(dt, world: self) }
        items.removeAll { $0.gone }
        if t > nextButterfly {
            nextButterfly = t + rnd(600, 1500)
            if chance(0.6) && !hidden && stillness < 2 && !studying && (pet.mode == .idle || pet.mode == .walk || pet.mode == .fly) { releaseButterfly() }
        }
        if t > nextReminderCheck { nextReminderCheck = t + 20; checkReminders() }
        if agendaCard.visible && (t > agendaCard.until || (typingNow && lastKeyT > agendaShownAt + 0.5) || hidden || pet.mode == .held) { agendaCard.hide() }
        if bellOn && bellTabs && t > nextTabPoll { nextTabPoll = t + 5; tabWatcher.poll() }
        // a menu or card took the bell's spot: bring it back once they're closed
        if notice != nil && !bellCard.visible && !popover.isShown && !agendaCard.visible && !musicCard.visible && t < lastRing + 120 { showBell() }
        if askCard.visible && t > askCard.until { askCard.hide() }
        // Water: counted in real minutes at the computer (the pet's own clock slows down while it naps), and never
        // skipped: if now's a bad moment (a menu is open, you're sharing your screen), it waits a minute and asks then.
        let wall = Date(), real = min(10, max(0, wall.timeIntervalSince(lastWall)))
        lastWall = wall
        if waterEvery != 0 && idleSecs < 90 && !hidden { activeSinceDrink += real }
        checkHabits(real)
        updateNameTag()
        if waterDue && t > nextWaterTry && !waterCard.visible {
            nextWaterTry = t + 60
            if !menuOpen && !sharing && !askCard.visible && !hidden && pet.mode != .held && idleSecs < 90 { remindWater() }
        }
        if waterCard.visible && (t > waterCard.until || hidden) { snoozeWater(quietly: true) }
        if habitCard.visible && (t > habitCard.until || hidden), let id = showingHabit { answerHabit(id, false) }
        if bellCard.visible && (t > bellCard.until || hidden) { dismissBell() }
        if toast.visible && t > toast.until { toast.hide() }
        // cards stay by the pet when it walks off or you drag it somewhere
        let cards = [bellCard, agendaCard, musicCard, waterCard, askCard, toast, habitCard]
        if cards.contains(where: \.visible) {
            let (tip, below) = pet.bubbleTip()
            for c in cards where c.visible { c.follow(tip: tip, below: below) }
        }
        if t > 8 && t - dt <= 8 { offerAccessibility() }          // a little after launch, once
        if t > 6 && t - dt <= 6 && defaults.bool(forKey: "movedToHomeApplications") {
            // the last update couldn't change the old copy's folder, so it went to ~/Applications: say where
            defaults.removeObject(forKey: "movedToHomeApplications")
            let (tip, below) = pet.bubbleTip()
            toast.show(ToastView(title: "Updated!", detail: "Pocket Pet now lives in the Applications folder in your home folder. You can delete the old copy.",
                                 close: { [weak self] in self?.toast.hide() }), tip: tip, below: below, until: t + 20)
        }
        if updater.enabled && Date() > nextUpdateCheckAt {
            nextUpdateCheckAt = Date().addingTimeInterval(3 * 3600)
            updater.check { [weak self] in self?.announceUpdate() }
        }
        if fullscreenUp != lastFullscreenApp { lastFullscreenApp = fullscreenUp; pets.forEach { $0.environmentChanged() } }
        if musicCard.visible {
            if musicCard.isKey || musicCard.frame.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) { musicCard.until = t + 3 }   // stays while you use it
            if t > musicCard.until || hidden || pet.mode == .held { musicCard.hide() }
        }
        if t > nextCalendar { nextCalendar = t + 600; google.refreshEvents(nil); ics.refresh(nil); tasks.refresh(nil); macCal.refresh() }
        if t > nextSave {
            nextSave = t + 30
            save()
            refreshNight()
        }
        // Only run as fast as the pet needs right now.
        guard !paused else { return }
        let busyItems = items.contains { !$0.resting }
        let want = hidden ? 1 : max(pets.map(\.wantsFPS).max() ?? 8, busyItems ? 20 : 0)
        if want > fps { schedule(want); lowSince = t }
        else if want < fps { if t - lowSince > 1.5 { schedule(want) } }
        else { lowSince = t }
    }

    func refreshNight() {
        let h = Calendar.current.component(.hour, from: Date())
        isNight = h >= 22 || h < 7
    }

    /// Every pet gets hungry, tired and bored on its own (it used to be only your main pet).
    func updateStats(_ dt: Double) {
        for p in pets {
            let asleep = p.mode == .sleeping || p.mode == .catnap
            p.fullness -= dt * (asleep ? 0.5 : 1) * 100 / (6 * 3600)
            p.energy += asleep ? dt * 100 / (15 * 60) : -dt * 100 / (10 * 3600)
            var hap = -dt * 100 / (8 * 3600) * (p.fullness < 20 ? 2 : 1)
            if p.mode == .typing || p.mode == .watching || p.mode == .listening { hap += dt * 100 / (3 * 3600) }
            p.happiness += hap
            p.fullness = clamp(p.fullness, 0, 100)
            p.energy = clamp(p.energy, 0, 100)
            p.happiness = clamp(p.happiness, 0, 100)
        }
    }

    func poof(at pt: CGPoint) {
        synth.play("poof")
        guard pet.edge == 0 else { return }
        let o = pet.cellToScreen(0, 0)
        let cx = Double((pt.x - o.x) / scale), cy = Double((o.y - pt.y) / scale)
        guard cx > 0, cx < Double(canvasW), cy > 0, cy < Double(canvasH) else { return }
        for _ in 0..<4 { pet.spawn(.puff, cx + rnd(-3, 3), cy + rnd(-3, 1), vx: rnd(-3, 3), vy: rnd(-4, -1), life: 0.6) }
    }

    // MARK: Geometry

    func screen(at px: CGFloat, _ py: CGFloat) -> NSScreen {
        let screens = NSScreen.screens
        let col = screens.filter { px >= $0.frame.minX && px < $0.frame.maxX }
        if let sc = col.first(where: { py >= $0.frame.minY - 8 && py < $0.frame.maxY }) ?? col.first { return sc }
        return screens.min(by: { abs($0.frame.midX - px) < abs($1.frame.midX - px) }) ?? NSScreen.main!
    }

    func area(near pt: CGPoint) -> CGRect {
        let sc = screen(at: pt.x, pt.y)
        return fullscreen ? sc.frame : sc.visibleFrame
    }

    func floorY(_ px: CGFloat, _ py: CGFloat) -> CGFloat { area(near: CGPoint(x: px, y: py)).minY }

    func xRange(_ m: CGFloat) -> ClosedRange<CGFloat> {
        let fs = NSScreen.screens.map { fullscreen ? $0.frame : $0.visibleFrame }
        let lo = (fs.map { $0.minX }.min() ?? 0) + m
        let hi = (fs.map { $0.maxX }.max() ?? 1000) - m
        return lo...max(lo, hi)
    }

    // MARK: Senses

    func sense() {
        guard t - lastSense >= 0.1 else { return }
        lastSense = t
        idleSecs = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
        // The system keystroke counter: we learn *that* you typed, never *what*.
        let c = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        if keyCounter != 0 && c != keyCounter {
            let d = Int(c &- keyCounter)
            if d > 0 && d < 200 {
                lastKeyT = t
                for _ in 0..<min(d, 6) { recentKeys.append(t) }
                tapUntil = t + 0.1
            }
        }
        keyCounter = c
        recentKeys.removeAll { t - $0 > 3 }
        if t > nextCheck {
            nextCheck = t + 4
            trusted = AXIsProcessTrusted()
            checkSystem()
        }
    }

    func checkSystem() {
        // Video players hold a "keep the display awake" power assertion while playing.
        var u: Unmanaged<CFDictionary>?
        var found: pid_t?
        var candidates: [(pid: pid_t, name: String)] = []
        if IOPMCopyAssertionsByProcess(&u) == kIOReturnSuccess, let dict = u?.takeRetainedValue() as NSDictionary? {
            let skip = ["caffeinate", "amphetamine", "keepingyouawake", "lungo", "theine", "powerd", "coreaudiod", "claude", "honk"]
            for (k, v) in dict {
                guard let pid = (k as? NSNumber)?.int32Value, pid != getpid(), let arr = v as? [NSDictionary] else { continue }
                for a in arr {
                    let t1 = a["AssertType"] as? String ?? "", t2 = a["AssertionTrueType"] as? String ?? ""
                    guard t1 == "PreventUserIdleDisplaySleep" || t2 == "PreventUserIdleDisplaySleep" || t1 == "NoDisplaySleepAssertion" else { continue }
                    let pname = (a["Process Name"] as? String ?? "").lowercased()
                    let aname = (a["AssertName"] as? String ?? "").lowercased()
                    if skip.contains(where: { pname.contains($0) || aname.contains($0) }) { continue }
                    candidates.append(((a["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value ?? pid, aname))
                }
            }
        }
        // Keeping the screen awake isn't enough on its own: browsers do it for a muted clip in a document, and so do some
        // reading and presenting apps. It's a video when that app is making sound, or when it's clearly a video player
        // in front of you and you've sat back for a while.
        if #available(macOS 14.2, *) {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            found = candidates.first { c in
                let bid = NSRunningApplication(processIdentifier: c.pid)?.bundleIdentifier ?? ""
                let heard = !bid.isEmpty && soundingNow.contains { $0.hasPrefix(bid) || bid.hasPrefix($0) }
                let videoish = ["video", "movie", "film", "media playback"].contains { c.name.contains($0) }
                return heard || (videoish && c.pid == front && idleSecs > 45)
            }?.pid
            if !candidates.isEmpty && !videoScanning {
                videoScanning = true
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let s = Self.soundingApps()
                    DispatchQueue.main.async { self?.soundingNow = s; self?.videoScanning = false }
                }
            } else if candidates.isEmpty { soundingNow = [] }
        } else {
            found = candidates.first?.pid
        }
        videoPID = found
        if found != nil { lastVideoSeen = t }
        if bellOn { bannerWatcher.start() } else if bannerWatcher.running { bannerWatcher.stop() }
        checkSharing()
        checkFullscreen()
        checkMusic()
    }

    /// SkyLight is macOS's window server framework. It isn't public, so it's looked up at run time and simply skipped
    /// if a future macOS changes it.
    private static let skyLight: (conn: @convention(c) () -> Int32, spaces: @convention(c) (Int32) -> Unmanaged<CFArray>?)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let c = dlsym(h, "SLSMainConnectionID") ?? dlsym(h, "CGSMainConnectionID"),
              let s = dlsym(h, "SLSCopyManagedDisplaySpaces") ?? dlsym(h, "CGSCopyManagedDisplaySpaces") else { return nil }
        return (unsafeBitCast(c, to: (@convention(c) () -> Int32).self), unsafeBitCast(s, to: (@convention(c) (Int32) -> Unmanaged<CFArray>?).self))
    }()

    /// Is the desktop on this screen a fullscreen one (an app or Split View)? nil when macOS won't say.
    func fullscreenDesktop(on sc: NSScreen) -> Bool? {
        guard let sl = Self.skyLight,
              let displays = sl.spaces(sl.conn())?.takeRetainedValue() as? [[String: Any]], !displays.isEmpty else { return nil }
        let num = sc.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        let uuid = CGDisplayCreateUUIDFromDisplayID(num).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        // one entry per screen, or a single "Main" one when screens share their desktops
        let d = displays.first { ($0["Display Identifier"] as? String) == uuid } ?? displays.first
        guard let current = d?["Current Space"] as? [String: Any], let type = current["type"] as? Int else { return nil }
        return type == 4
    }

    /// Is the pet's screen showing a fullscreen desktop? Also finds the window the video is in.
    func checkFullscreen() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        let me = getpid()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        func rect(_ w: [String: Any]) -> CGRect? {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0, layer < 20,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.width > 150, r.height > 120 else { return nil }
            return r
        }
        // Fullscreen = some app's window spans the whole width of the pet's screen down to the very bottom (where the
        // Dock would be), starting at the top or just under the notch, and the menu bar is gone. Once fullscreen, it stays
        // so while that window is there, even if you peek at the menu bar. Any app counts, not just the frontmost one,
        // which lags behind while macOS switches desktops.
        let sc = screen(at: pet.x, pet.y), f = sc.frame
        let top = mainH - f.maxY, bottom = mainH - f.minY, notch = max(sc.safeAreaInsets.top, 0)
        let spans = list.contains { w in
            guard let opid = w[kCGWindowOwnerPID as String] as? Int32, opid != me,
                  (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let r = rect(w) else { return false }
            return abs(r.minX - f.minX) < 2 && abs(r.width - f.width) < 2 && abs(r.maxY - bottom) < 2 && r.minY - top <= notch + 2
        }
        let menuBarShowing = list.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return abs(r.minY - top) < 2 && r.width > f.width * 0.5 && r.minX < f.maxX && r.maxX > f.minX
        }
        // Best answer first: macOS itself says whether this screen is showing a fullscreen desktop (works when you switch
        // to one that was already fullscreen, and on notched Macs where the menu bar stays). Window shapes are the fallback.
        let covers = fullscreenDesktop(on: sc) ?? (spans && (fullscreen || !menuBarShowing))
        if covers {
            fsOffSince = nil
            if !fullscreen { fullscreen = true; pets.forEach { $0.environmentChanged() } }     // entering: right away
        } else if fullscreen {
            // leaving: only once it's still true a moment later (desktops sliding can blink the window list)
            if let since = fsOffSince, now() - since > 0.25 {
                fsOffSince = nil
                fullscreen = false
                pets.forEach { $0.environmentChanged() }
            } else if fsOffSince == nil {
                fsOffSince = now()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkFullscreen() }
            }
        }
        if let vp = videoPID {
            var frame: CGRect?
            for match in [vp, front] {
                for w in list {
                    guard let opid = w[kCGWindowOwnerPID as String] as? Int32, opid == match,
                          (w[kCGWindowLayer as String] as? Int) == 0, let r = rect(w) else { continue }
                    frame = CGRect(x: r.minX, y: mainH - r.maxY, width: r.width, height: r.height)
                    break
                }
                if frame != nil { break }
            }
            videoFrame = frame
        }
    }

    // MARK: Music

    /// Music players. Browsers count too while they play sound without a video, but only with a music site open
    /// (YouTube Music, SoundCloud...): they also make sound for calls, Discord's pings and ads.
    static let musicApps = ["com.spotify.client", "com.apple.Music", "com.apple.podcasts", "com.tidal.desktop",
                            "com.deezer.deezer-desktop", "com.amazon.music", "com.github.th-ch.youtube-music", "sh.cider",
                            "com.plexamp.Plexamp", "com.pandora.desktop", "com.soundcloud.desktop", "org.videolan.vlc",
                            "com.colliderli.iina", "com.audirvana", "com.roon.Roon", "com.qobuz.QobuzDesktop"]
    private var heard: String?            // the app Core Audio last heard playing music
    /// Accessibility, looked up every few seconds rather than on every redraw of the menu.
    var trusted = AXIsProcessTrusted()
    private var pausedPlayers = Set<String>()    // Spotify/Music said they're paused (their sound can linger in Core Audio a while)
    private var browserSound = false      // a browser is making sound, so its tabs are worth a look

    /// Headphones stay on for as long as Spotify/Music say they're playing. Until one of them has
    /// told us anything (right after launch), Core Audio is asked who's playing sound, now and then.
    func checkMusic() {
        let players = Self.musicApps + Array(DocBrowsers.all)
        if musicAppRunning == nil {       // only re-checked when an app opens or quits
            musicAppRunning = NSWorkspace.shared.runningApplications.contains { app in
                players.contains { (app.bundleIdentifier ?? "").hasPrefix($0) }
            }
        }
        guard musicAppRunning == true else { musicPlaying = false; notifiedPlaying = nil; heard = nil; tellPlayer(); return }
        if t > nextAudioScan && !audioScanning {
            // Core Audio is asked off the main thread (a busy sound system can't freeze the app); the answer comes back here
            nextAudioScan = t + 6
            audioScanning = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let sounding = Self.soundingApps()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.audioScanning = false
                    self.heard = self.musicPlayingIn(sounding)
                    if let h = self.heard, self.pausedPlayers.contains(h) { self.heard = nil }   // the player itself says it's paused
                    // with the bell's tab check off, tabs are only looked at while a browser makes sound (no bell, no questions)
                    if self.browserSound && !(self.bellOn && self.bellTabs) { self.tabWatcher.poll(ring: false) }
                }
            }
        }
        let notified = notifiedPlaying == true          // Spotify and Apple Music say so themselves, instantly
        musicPlaying = notified || heard != nil
        if !notified, let h = heard { musicApp = h }
        tellPlayer()
    }

    /// Lets the music player know when something it can't ask directly (another app, a browser) is playing.
    private func tellPlayer() {
        let other = heard.map { $0 != "Spotify" && $0 != "Music" } ?? false
        player.otherPlaying = other && notifiedPlaying != true
        player.otherName = other ? heard! : ""
    }

    private var audioScanning = false

    /// Core Audio's list of processes playing sound right now (no permission needed), as bundle ids (app helpers too).
    private static func soundingApps() -> [String] {
        guard #available(macOS 14.2, *) else { return [] }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var out: [String] = []
        for id in ids {
            var running: UInt32 = 0
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            var raddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &raddr, 0, nil, &rsize, &running) == noErr, running != 0 else { continue }
            var bundle: Unmanaged<CFString>?
            var bsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var baddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &baddr, 0, nil, &bsize, &bundle) == noErr,
                  let b = bundle?.takeRetainedValue() as String? else { continue }
            out.append(b)
        }
        return out
    }

    /// Of the apps making sound, the music app (or a browser with a music site open and no video) that's playing, if any.
    private func musicPlayingIn(_ sounding: [String]) -> String? {
        browserSound = false
        for b in sounding {
            if let id = Self.musicApps.first(where: { b.hasPrefix($0) }) {
                if id == MusicPlayer.spotifyID { return "Spotify" }
                if id == MusicPlayer.musicID { return "Music" }
                return NSWorkspace.shared.runningApplications.first { ($0.bundleIdentifier ?? "").hasPrefix(id) }?.localizedName ?? "your player"
            }
            // a browser (its audio runs in a helper, hence the prefix): only with a music site open, and no video
            if !videoPlaying, let id = DocBrowsers.all.first(where: { b.hasPrefix($0) }) {
                browserSound = true
                if let site = tabWatcher.musicSite(in: id) { return site }
            }
        }
        return nil
    }

    func musicNotification(_ info: [AnyHashable: Any]?, app: String) {
        let state = info?["Player State"] as? String ?? ""
        let title = info?["Name"] as? String ?? ""
        let playing = state == "Playing"
        notifiedPlaying = playing
        if playing { pausedPlayers.remove(app) } else { pausedPlayers.insert(app) }
        if playing && (title != musicTitle || !musicPlaying) && !title.isEmpty {
            let shown = sanitize(title)
            if !shown.isEmpty { pet.say(["♪ " + String(shown.prefix(22))], 3) }
        }
        let shown = popover.isShown || musicCard.visible
        if shown { player.refresh() }
        if title != musicTitle {
            // a new song: fetch its cover now, menu open or not, so it's already there when you look (in the
            // background this never asks for permission)
            if !shown { player.refresh(quiet: true) }
            player.refreshUpNext()
            // Spotify can report the new title a moment before its cover: look again shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.player.refresh(quiet: !shown) }
        }
        musicPlaying = playing
        musicTitle = title
        musicApp = app
    }

    // MARK: Music card

    /// A single click on the pet while Spotify plays shows the mini player (after a beat, so a double-click can still open the agenda).
    func petClicked() {
        guard musicPlaying && player.running else { return }
        if musicCard.visible { musicCard.hide() } else { showMusicCard() }
    }

    func petDoubleClicked() {
        musicCard.hide()
        showAgenda()
    }

    private func showMusicCard() {
        guard !hidden else { return }
        closePopover(); bellCard.hide(); toast.hide()
        player.refresh()
        agendaCard.hide()
        let (tip, below) = pet.bubbleTip()
        musicCard.show(MusicCardView(player: player, model: musicModel), tip: tip, below: below, until: t + 8)
    }

    // MARK: Notification bell

    /// Troubleshooting: `defaults write local.honk.desktopgoose bellLog -bool true` writes what the bell sees
    /// to ~/Library/Logs/Pocket Pet bell.log (only who sent what, never the messages).
    func bellLog(_ line: String) {
        guard defaults.bool(forKey: "bellLog") else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Pocket Pet bell.log")
        let text = "\(Date()) t=\(Int(t)) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }

    func ring(_ n: Notice) {
        bellLog("ring \(n.title) | \(n.detail) bellOn=\(bellOn) hidden=\(hidden)")
        guard bellOn, !hidden else { return }
        // a browser message can arrive twice (a tab count and a banner): one ring is enough
        if let last = notice, t - lastRing < 6, last.title == n.title || (last.site != nil && last.site == n.site) { return }
        notice = n
        lastRing = t
        pet.spawnBang()
        synth.play("chime")
        showBell()
    }

    private func showBell() {
        guard let n = notice, !hidden else { return }
        bellLog("show card \(n.title)")
        let (tip, below) = pet.bubbleTip()
        bellCard.show(BellView(bell: iconImage(.bell), title: n.title, detail: n.detail, open: { [weak self] in self?.openNotice() }),
                      tip: tip, below: below, until: t + 120)
    }

    /// Goes to where the notification came from: the browser tab, the banner itself, or the app.
    func openNotice() {
        guard let n = notice else { return }
        dismissBell()
        if let bid = n.browser, let tab = n.tabID { tabWatcher.open(bid, tabID: tab); return }
        if let el = n.banner, bannerWatcher.press(el) { return }
        if let bid = n.appBundle {
            if let site = n.site, DocBrowsers.all.contains(bid) { tabWatcher.open(bid, site: site); return }
            NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.activate()
        }
    }

    func dismissBell() {
        if notice != nil { bellLog("dismiss \(Thread.callStackSymbols.dropFirst().prefix(3).joined(separator: " <- "))") }
        notice = nil
        bellCard.hide()
    }

    func setBellTabs(_ on: Bool) {
        bellTabs = on
        if !on, notice?.browser != nil { dismissBell() }
        save()
    }

    // MARK: Water and screen sharing

    /// Millilitres today (glasses from before millilitres count as 250 ml each).
    var waterToday: Int {
        guard defaults.string(forKey: "waterDay") == Self.dayKey() else { return 0 }
        if let ml = defaults.object(forKey: "waterML") as? Int { return ml }
        return defaults.integer(forKey: "glasses") * 250
    }
    /// The water day runs from 4 AM to 4 AM: a drink after midnight still counts for the day you're in.
    static var waterNow: Date { Date().addingTimeInterval(-4 * 3600) }
    /// Millilitres per day ("2026-10-29": 1500), kept for a year, for the Water pane's chart.
    var waterHistory: [String: Int] {
        var h = defaults.dictionary(forKey: "waterHistoryML") as? [String: Int]
            ?? (defaults.dictionary(forKey: "waterHistory") as? [String: Int] ?? [:]).mapValues { $0 * 250 }
        if h[Self.isoDay(Self.waterNow)] == nil && waterToday > 0 { h[Self.isoDay(Self.waterNow)] = waterToday }
        return h
    }

    private func setWater(ml n: Int) {
        defaults.set(Self.dayKey(), forKey: "waterDay"); defaults.set(n, forKey: "waterML")
        var h = waterHistory
        h[Self.isoDay(Self.waterNow)] = n
        if h.count > 400 { for k in h.keys.sorted().prefix(h.count - 400) { h[k] = nil } }
        defaults.set(h, forKey: "waterHistoryML")
    }

    /// The goal you set, or one tailored to you: about 33 ml per kg of body weight, more when you're active or it's hot.
    var waterGoalML: Int { waterGoalMode == 1 ? tailoredGoalML : fixedGoalML }
    var tailoredGoalML: Int {
        let raw = weightKG * 33 + [0, 350, 700][max(0, min(2, activity))] + (hotWeather ? 500 : 0)
        return Int((raw / 50).rounded()) * 50
    }
    /// One tap of + (or "I drank some"): a glass, or a sip when you count sips.
    var servingML: Int { waterUnit == .sips ? sipML : glassML }

    /// An amount in the unit you count in: "3 glasses", "24 sips", "750 ml", "25 oz" (or just the number).
    func waterText(_ ml: Int, unit: Bool = true) -> String {
        switch waterUnit {
        case .glasses:
            let g = Double(ml) / Double(glassML), n = g.rounded() == g ? String(Int(g)) : String(format: "%.1f", g)
            return unit ? "\(n) \(g == 1 ? "glass" : "glasses")" : n
        case .sips:
            let n = Int((Double(ml) / Double(sipML)).rounded())
            return unit ? "\(n) \(n == 1 ? "sip" : "sips")" : "\(n)"
        case .ml:
            let n = NumberFormatter.localizedString(from: NSNumber(value: ml), number: .decimal)
            return unit ? "\(n) ml" : n
        case .oz:
            let n = Int((Double(ml) / 29.5735).rounded())
            return unit ? "\(n) oz" : "\(n)"
        }
    }
    func waterValue(_ ml: Int) -> Double {
        switch waterUnit {
        case .glasses: return Double(ml) / Double(glassML)
        case .sips: return Double(ml) / Double(sipML)
        case .ml: return Double(ml)
        case .oz: return Double(ml) / 29.5735
        }
    }
    var waterLine: String { "\(waterText(waterToday, unit: false)) of \(waterText(waterGoalML)) today" }

    /// Your waking hours today (the water day's), for pacing and quiet nights.
    var wakingHours: (start: Date, end: Date) {
        let base = Calendar.current.startOfDay(for: Self.waterNow)
        let start = base.addingTimeInterval(Double(wakeMinutes) * 60)
        var end = base.addingTimeInterval(Double(bedMinutes) * 60)
        if end <= start { end = end.addingTimeInterval(86400) }
        return (start, end)
    }
    var awakeHours: Bool { let h = wakingHours, now = Date(); return now >= h.start && now < h.end }
    /// What you'd have had by now, spreading your goal evenly over your waking hours.
    /// How much you'd have had by now on an even pace through your waking hours (an hour after you wake to bedtime: nobody
    /// drinks the moment they're up).
    func waterExpected(at d: Date) -> Int {
        let h = wakingHours, start = h.start.addingTimeInterval(3600)
        guard h.end > start else { return 0 }
        let f = min(1, max(0, d.timeIntervalSince(start) / h.end.timeIntervalSince(start)))
        return Int(Double(waterGoalML) * f)
    }
    var waterExpected: Int { waterExpected(at: Date()) }
    /// "On track", "Ahead of schedule", or something to aim for in the next couple of hours ("Aim for 2 more glasses by
    /// 3 PM") rather than a running tally of how far behind you are.
    var paceText: String {
        let today = waterToday, goal = waterGoalML
        if today >= goal { return "Goal reached!" }
        let slack = max(servingML / 2, 200)
        if waterExpected - today <= slack { return today > waterExpected + servingML ? "Ahead of schedule" : "On track" }
        let cal = Calendar.current, h = wakingHours
        var by = cal.date(bySetting: .minute, value: 0, of: Date().addingTimeInterval(2 * 3600)) ?? Date().addingTimeInterval(2 * 3600)
        if by > h.end { by = h.end }
        let need = min(goal - today, max(servingML, waterExpected(at: by) - today))
        let rounded = min(goal - today, ((need + servingML - 1) / servingML) * servingML)
        let tf = DateFormatter()
        tf.setLocalizedDateFormatFromTemplate(by.timeIntervalSince(cal.date(bySetting: .minute, value: 0, of: by) ?? by) > 60 ? "jmm" : "j")
        return "Aim for \(waterText(rounded)) more by \(tf.string(from: by))"
    }

    /// Time for a reminder? Every so often, or (adapting to your pace) sooner the further behind you are and not at all
    /// while you're ahead. Never once you reach your goal, or (if you like) outside your waking hours.
    /// How long after your last drink (real seconds at the computer) the next reminder comes: your fixed interval, or,
    /// keeping pace, every 45 minutes (30 when you're well behind).
    var waterInterval: Double {
        if waterEvery > 0 { return waterEvery }
        return waterExpected - waterToday >= 600 ? 30 * 60 : 45 * 60
    }
    /// Keeping pace, it only asks when you're at least a glass behind, in any unit (counting sips used to make it nag
    /// over half a sip).
    var waterDue: Bool {
        guard waterEvery != 0, waterToday < waterGoalML, !(quietAtNight && !awakeHours) else { return false }
        if waterEvery < 0 && waterExpected - waterToday < 250 { return false }
        return activeSinceDrink >= waterInterval
    }

    static func isoDay(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func dayKey() -> String { let d = Calendar.current.dateComponents([.year, .month, .day], from: waterNow); return "\(d.year!)-\(d.month!)-\(d.day!)" }

    /// The pet sits up with a glass of water and a card asks whether you've had some.
    func remindWater() {
        let title = waterSnoozes > 0 ? ["Still thirsty?", "Water time, for real"].randomElement()!
                                     : ["Water break?", "Time for a sip", "Stay hydrated!", "Thirsty?", "Glug glug?"].randomElement()!
        pet.offerWater(for: 60)
        synth.play("pop")
        for i in 0..<3 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) { [weak self] in self?.pet.spawnDrop() } }
        let (tip, below) = pet.bubbleTip()
        waterCard.show(waterView(title: title, answer: { [weak self] drank in
            if drank { self?.drankWater() } else { self?.snoozeWater() }
        }), tip: tip, below: below, until: t + 60)
    }

    func waterView(title: String, done: Bool = false, answer: @escaping (Bool) -> Void = { _ in }) -> WaterView {
        let goal = waterGoalML, today = waterToday
        let glasses = waterUnit == .glasses && goal % glassML == 0 && goal / glassML <= 12
        return WaterView(title: title, line: waterLine, progress: Double(today) / Double(max(1, goal)),
                         dots: glasses ? (today / glassML, goal / glassML) : nil, pace: paceText,
                         drink: waterUnit == .sips ? "I took a sip" : "I drank some", done: done, answer: answer)
    }

    func drankWater() {
        let before = waterToday
        setWater(ml: before + servingML)
        activeSinceDrink = 0; waterSnoozes = 0
        pet.drink()
        synth.play("chomp")
        if before < waterGoalML && waterToday >= waterGoalML {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.pet.celebrate("HYDRATED!") }
        }
        guard !popover.isShown else { return }          // counted from the menu: no card on top of it
        let (tip, below) = pet.bubbleTip()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            waterCard.show(waterView(title: "", done: true), tip: tip, below: below, until: t + 2.2)
        }
    }

    /// "Later" (or the card left alone): asks again in 15 minutes.
    func snoozeWater(quietly: Bool = false) {
        waterCard.hide()
        pet.putAway()
        waterSnoozes += 1
        // "Later" really means later: 20 minutes, or 30 once you've put it off twice
        activeSinceDrink = max(0, waterInterval - (waterSnoozes > 2 ? 30 : 20) * 60)
        if !quietly { pet.say(["OKAY, IN A BIT!"], 1.6) }
    }

    func setWater(_ every: Double) {
        waterEvery = every
        activeSinceDrink = 0
        save()
    }

    /// macOS's window server knows when something is capturing the screen (a call's screen share, a recording).
    private static let screenWatched: (@convention(c) () -> Bool)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let f = dlsym(h, "SLSIsScreenWatcherPresent") ?? dlsym(h, "CGSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(f, to: (@convention(c) () -> Bool).self)
    }()

    /// Sharing your screen in a call: ask whether to hide the pet until it stops (and come back by itself after).
    private func checkSharing() {
        let now = Self.screenWatched?() ?? false
        guard now != sharing else { return }
        sharing = now
        if now && !hidden {
            let (tip, below) = pet.bubbleTip()
            askCard.show(AskView(title: "Sharing your screen?", detail: "Hide \(pet.name) until you stop sharing?", yes: "Hide", no: "Stay",
                                 answer: { [weak self] hide in
                                     guard let self else { return }
                                     self.askCard.hide()
                                     if hide && !self.hidden { self.hiddenForSharing = true; self.toggleHidden(quietly: true) }
                                 }), tip: tip, below: below, until: t + 30)
        } else if !now {
            askCard.hide()
            if hiddenForSharing && hidden { hiddenForSharing = false; toggleHidden(); pet.say(["I'M BACK!"], 1.6) }
        }
    }

    func setBell(_ on: Bool) {
        bellOn = on
        if !on { dismissBell(); bannerWatcher.stop() } else { offerAccessibility(force: true) }
        save()
    }

    /// Browser tabs work out of the box; every other app's notifications need Accessibility. Offered once (and again
    /// whenever you switch the bell on), with a note saying why, then macOS asks.
    func offerAccessibility(force: Bool = false) {
        guard bellOn, !AXIsProcessTrusted(), !hidden, force || !defaults.bool(forKey: "offeredAccessibility") else { return }
        defaults.set(true, forKey: "offeredAccessibility")
        let (tip, below) = pet.bubbleTip()
        toast.show(ToastView(title: "Ring for every notification?", detail: "Click here, then switch on Pocket Pet under Accessibility. It only reads who a notification is from.",
                             close: { [weak self] in self?.toast.hide(); self?.requestAccessibility() }), tip: tip, below: below, until: t + 20)
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: Calendar

    func showAgenda() {
        guard calendarConnected else {
            pet.showAgenda(["CONNECT YOUR", "CALENDAR IN MY MENU"])
            return
        }
        let show = { [weak self] in
            guard let self, !self.hidden else { return }
            let agenda = Agenda.build(self.calendarEvents)
            let dur = min(16, 7 + Double(agenda.lineCount))
            self.pet.showAgenda([], for: dur)
            let (tip, below) = self.pet.bubbleTip()
            self.musicCard.hide(); self.closePopover(); self.bellCard.hide(); self.toast.hide()
            self.agendaShownAt = self.t
            self.agendaCard.show(AgendaView(agenda: agenda, close: { [weak self] in self?.agendaCard.hide() }), tip: tip, below: below, until: self.t + dur)
        }
        // fetch whichever sources are stale (and the Mac's own calendars), then show once they're all back
        let stale = [google.signedIn && Date().timeIntervalSince(google.lastFetch) > 120,
                     ics.connected && Date().timeIntervalSince(ics.lastFetch) > 120, macCal.authorized]
        var waiting = stale.filter { $0 }.count
        guard waiting > 0 else { show(); return }
        let done = { waiting -= 1; if waiting == 0 { show() } }
        if stale[0] { google.refreshEvents(done) }
        if stale[1] { ics.refresh(done) }
        if stale[2] { macCal.refresh(done) }
    }

    /// Up to `n` letters for the pixel bubble, cut between words.
    func shortTitle(_ s: String, _ n: Int = 18) -> String {
        let t = sanitize(s)
        guard t.count > n else { return t }
        let cut = t.prefix(n - 2)
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) >= n / 2 { return String(cut[..<sp]) + ".." }
        return String(cut) + ".."
    }

    /// ManageBac tasks: the evening before a task is due (from 4 PM) and the morning it's due (from 8 AM), once each.
    func checkTasks() {
        guard tasks.connected, !hidden else { return }
        let cal = Calendar.current, nowD = Date()
        let hour = cal.component(.hour, from: nowD)
        for e in tasks.events where e.end > nowD || e.allDay {
            let due = cal.startOfDay(for: e.allDay ? e.start : e.end.addingTimeInterval(-1))
            let today = cal.startOfDay(for: nowD)
            let daysLeft = cal.dateComponents([.day], from: today, to: due).day ?? 99
            let kind = daysLeft == 1 && hour >= 16 ? "eve" : daysLeft == 0 && hour >= 8 ? "day" : nil
            guard let kind, !reminded.contains("task" + e.id + kind) else { continue }
            reminded.insert("task" + e.id + kind)
            let name = shortTitle(e.title)
            pet.say(["HOMEWORK!", name.isEmpty ? "A TASK" : name, kind == "eve" ? "DUE TOMORROW" : "DUE TODAY"], 7)
            pet.spawnBang()
            synth.play("chime")
            return                                   // one at a time; the next one comes a little later
        }
    }

    func checkReminders() {
        checkTasks()
        guard calendarConnected else { return }
        let nowD = Date()
        for e in calendarEvents where !e.allDay {
            let mins = e.start.timeIntervalSince(nowD) / 60
            let name = shortTitle(e.title)
            let place = sanitize(Agenda.place(e.location) ?? "")
            let at = !place.isEmpty && place.count <= 14 ? ["AT " + place] : []        // which room, when it fits
            if mins > 0 && mins <= 10 && !reminded.contains(e.id + "soon") {
                reminded.insert(e.id + "soon")
                pet.say([name.isEmpty ? "MEETING" : name, "IN \(Int(mins.rounded(.up))) MIN!"] + at, 6)
                pet.spawnBang()
                synth.play("chime")
            } else if mins <= 0 && mins > -1.5 && !reminded.contains(e.id + "now") {
                reminded.insert(e.id + "now")
                pet.say([name.isEmpty ? "MEETING" : name, "STARTS NOW!"] + at, 6)
                pet.spawnBang()
                synth.play("chime")
            }
        }
    }

    // MARK: Actions

    /// Food for one pet (your main pet unless you say which): it lands by that pet and it's saved for it.
    func feed(_ kind: ItemKind, for target: Pet? = nil) {
        lastPlay = t
        showIfHidden()
        let p = target ?? pet!
        let a = area(near: CGPoint(x: p.x, y: p.y))
        if gravity {
            let fx = clamp(p.x + CGFloat(p.facing) * CGFloat(rnd(110, 240)) * scale / 4, a.minX + 40, a.maxX - 40)
            let it = Item(kind: kind, x: fx, y: area(near: CGPoint(x: fx, y: p.y)).maxY - 14 * scale, scale: scale, t: t, hidden: hidden)
            items.append(it)
            if !p.hungry { if !p.isAsleep { p.say(["I'M FULL!"], 2) } }           // it stays put for whoever's hungry, then vanishes
            else if !companions.isEmpty && !p.isAsleep { p.releaseFood(); it.claim = p; p.food = it; p.spawnBang(); p.begin(.eating) }   // nobody else gets it
        } else {
            let it = Item(kind: kind, x: a.midX + CGFloat(rnd(-200, 200)), y: a.midY + CGFloat(rnd(-100, 100)), scale: scale, t: t, hidden: hidden)
            it.vx = CGFloat(rnd(-80, 80)); it.vy = CGFloat(rnd(-80, 80))
            if p.hungry { it.claim = p; p.food = it; p.begin(.eating) } else if !p.isAsleep { p.say(["I'M FULL!"], 2) }
            items.append(it)
        }
        p.panel.orderFrontRegardless()
    }

    func throwBall(for target: Pet? = nil) {
        lastPlay = t
        showIfHidden()
        let p = target ?? pet!
        if let old = items.first(where: { $0.isBall }) {        // already out: bring it back instead of ignoring the press
            old.close()
            items.removeAll { $0 === old }
        }
        let kind: ItemKind = p.family == .cat ? .yarn : .ball
        let a = area(near: CGPoint(x: p.x, y: p.y))
        let it: Item
        if gravity {
            it = Item(kind: kind, x: clamp(p.x + CGFloat(p.facing) * 150 * scale / 4, a.minX + 40, a.maxX - 40), y: p.y + 300, scale: scale, t: t, hidden: hidden)
        } else {
            it = Item(kind: kind, x: a.midX, y: a.midY, scale: scale, t: t, hidden: hidden)
            it.vx = CGFloat(rnd(-300, 300)); it.vy = CGFloat(rnd(-300, 300))
        }
        items.append(it)
        p.panel.orderFrontRegardless()
    }

    func releaseButterfly() {
        lastPlay = t
        showIfHidden()
        // holding completely still: no butterflies. Staying put: it turns up right beside your pet
        guard stillness < 2, !items.contains(where: { $0.kind == .butterfly }), let p = pet else { return }
        let vf = area(near: CGPoint(x: p.x, y: p.y))
        let left = p.x - vf.minX > vf.maxX - p.x
        let bx = stillness == 1 ? clamp(p.x + (left ? -1 : 1) * 110 * scale / 4, vf.minX + 30, vf.maxX - 30) : (left ? vf.minX + 10 : vf.maxX - 10)
        items.append(Item(kind: .butterfly, x: bx, y: vf.minY + 160 * scale / 4, scale: scale, t: t, hidden: hidden))
    }

    func setGravity(_ on: Bool) {
        guard on != gravity else { return }
        gravity = on
        pets.forEach { $0.environmentChanged() }
        save()
        ui.refresh()
    }

    func setSize(_ n: Int) {
        sizeSetting = n
        pets.forEach { $0.buildWindow() }
        items.forEach { $0.resize(scale) }
        save()
    }

    func setSound(_ on: Bool) { soundOn = on; synth.enabled = on; save() }

    func setVolume(_ v: Double, for category: String) {
        volumes[category] = v
        synth.setVolumes(volumes)
        save()
    }

    /// The menu's stay-in-place button: roams, then stays put, then holds completely still, then roams again.
    /// The paw button, in four steps: roams, stays put, holds completely still, reads (study mode), then roams again.
    /// The paw button for one pet (when modes aren't shared): roam, stay put, freeze, read.
    func cycleStillness(for p: Pet) {
        guard !together else { cycleStillness(); return }
        if p.ownStudying {
            p.ownStudying = false; p.ownStillness = 0
            if p.mode == .study { p.setMode(.idle); if p.family == .bat && p.edge == 0 { p.swoop(home: true) } }
            p.say(["BREAK TIME!"], 1.6); p.hearts(2)
        } else if p.ownStillness == 2 {
            p.ownStillness = 0; p.ownStudying = true
            if !p.inAir && p.mode != .held { p.forcedNap = false; p.begin(.study) }
            p.say(["STUDY TIME!"], 1.8)
        } else {
            p.ownStillness += 1
            p.say([["I'LL STAY HERE"], ["FREEZE!"]][p.ownStillness - 1], 1.8)
        }
    }

    /// The nap button: all of them doze off (or wake up) together, or just this one.
    func toggleNap(for p: Pet) {
        guard together else { p.toggleNap(); return }
        let wake = p.isAsleep
        for q in pets where q.isAsleep == wake { q.toggleNap() }
    }

    func cycleStillness() {
        if studying { toggleStudy(); stillness = 0; save(); return }          // reading -> free to roam
        if stillness == 2 { stillness = 0; save(); toggleStudy(); return }    // completely still -> reading
        stillness += 1
        save()
        pet.say([["FREE TO ROAM!"], ["I'LL STAY HERE"], ["FREEZE!"]][stillness], 1.8)
    }

    // MARK: Advanced settings window

    private var advancedWindow: NSWindow?

    /// Opens Advanced Settings in a window of its own (brought forward if it's already open).
    func openAdvanced() {
        closePopover()
        if advancedWindow == nil { advancedWindow = makeAdvancedWindow() }
        NSApp.activate(ignoringOtherApps: true)
        advancedWindow?.makeKeyAndOrderFront(nil)
    }

    /// Back to the menu (its Music tab has the Spotify steps).
    func closeAdvanced() {
        advancedWindow?.close()
        if let b = statusItem?.button { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { b.performClick(nil) } }
    }

    /// A standard settings window: title bar, sidebar up to the top like System Settings, resizable.
    func makeAdvancedWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Advanced Settings"
        w.isReleasedWhenClosed = false
        w.toolbar = NSToolbar()
        w.toolbarStyle = .unified
        w.contentView = NSHostingView(rootView: AdvancedSettingsView(m: ui))
        w.contentMinSize = NSSize(width: 640, height: 460)
        w.setFrameAutosaveName("AdvancedSettings")
        if !w.setFrameUsingName("AdvancedSettings") { w.center() }
        return w
    }

    // MARK: Name tag

    /// Each pet's name in a little tag above it (when switched on), out of the way of speech and cards.
    private func updateNameTag() {
        for p in pets {
            let cardsUp = p === pet && (askCard.visible || habitCard.visible || toast.visible)
            let want = showName && !hidden && !menuOpen && !cardsUp && !p.bubble.panel.isVisible
            let tag = p.nameTag
            if want {
                let (tip, below) = p.bubbleTip()
                if !tag.visible || p.tagShows != p.name {
                    tag.show(NameTagView(name: p.name), tip: tip, below: below, until: .infinity)
                    p.tagShows = p.name
                } else {
                    tag.follow(tip: tip, below: below)
                }
            } else if tag.visible {
                tag.hide()
            }
        }
    }

    // MARK: Habit reminders

    /// Your own reminders: at a time each day, or every so often while you're at the computer.
    private func checkHabits(_ real: Double) {
        guard !habits.isEmpty else { return }
        let atComputer = idleSecs < 90 && !hidden
        for h in habits where h.every > 0 && atComputer { habitActive[h.id, default: 0] += real }
        guard t > nextHabitCheck else { return }
        nextHabitCheck = t + 15
        guard atComputer, !menuOpen, !habitCard.visible, !askCard.visible, !sharing, pet.mode != .held else { return }
        let now = Date(), cal = Calendar.current
        for i in habits.indices {
            let h = habits[i]
            if let s = habitSnoozed[h.id], t < s { continue }
            var due = false
            if h.every > 0 {
                due = habitActive[h.id, default: 0] >= h.every
            } else {
                let at = cal.date(bySettingHour: h.hour, minute: h.minute, second: 0, of: now) ?? now
                due = now >= at && (h.lastShown.map { !cal.isDate($0, inSameDayAs: now) || $0 < at } ?? true)
            }
            if due { showHabit(i); return }
        }
    }
    private var nextHabitCheck = 0.0

    private func showHabit(_ i: Int) {
        let h = habits[i]
        habits[i].lastShown = Date()
        habitActive[h.id] = 0
        showingHabit = h.id
        save()
        pet.say([shortTitle(h.text, 22).uppercased()], 4)
        pet.spawnBang()
        synth.play("chime")
        let (tip, below) = pet.bubbleTip()
        habitCard.show(HabitView(text: h.text, schedule: h.label, answer: { [weak self] done in self?.answerHabit(h.id, done) }),
                       tip: tip, below: below, until: t + 90)
    }

    func answerHabit(_ id: UUID, _ done: Bool) {
        habitCard.hide()
        showingHabit = nil
        if done { pet.hearts(4); pet.celebrate("NICE!") }
        else {
            // asks again in 10 minutes
            habitSnoozed[id] = t + 10 * 60
            if let i = habits.firstIndex(where: { $0.id == id }) { habits[i].lastShown = nil; habitActive[id] = habits[i].every }
            pet.say(["IN 10 MIN!"], 1.6)
        }
    }

    func addHabit(_ h: Habit) {
        var h = h
        // a daily time that's already gone by today starts tomorrow
        if h.every == 0, let at = Calendar.current.date(bySettingHour: h.hour, minute: h.minute, second: 0, of: Date()), Date() > at { h.lastShown = Date() }
        habits.append(h); habitActive[h.id] = 0; save()
    }
    func removeHabit(_ id: UUID) { habits.removeAll { $0.id == id }; save() }

    // MARK: Water glasses

    /// Took one off (pressed + by mistake).
    func undoWater() { setWater(ml: max(0, waterToday - servingML)) }

    /// Several pets at once: tapping a pet in the Pets tab brings it along, or sends it home.
    func toggleCompanion(_ sp: Species) {
        if let c = companions.first(where: { $0.species == sp }) {
            c.say(["BYE!"], 1)
            c.panel.orderOut(nil); c.bubble.hide(); c.nameTag.hide()
            companions.removeAll { $0 === c }
            resting.removeAll { $0.species == sp }; resting.append(c.record)      // its name and outfit wait for it
        } else if sp != pet.species && companions.count < Self.maxCompanions {
            // back again: with the name and outfit it had
            var r = resting.first { $0.species == sp }
                ?? PetRecord(id: UUID().uuidString, species: sp, name: sp.defaultName, outfit: Outfit(), fullness: 80, happiness: 85, energy: 90, x: 0)
            resting.removeAll { $0.species == sp }
            r.x = Double(pet.x) + Double.random(in: -160...160)
            let c = Pet(world: self, record: r)
            companions.append(c)
            if !hidden { c.spawnIn() } else { c.panel.orderOut(nil) }
        }
        save()
    }

    /// Off: the other pets go home, but they're remembered (names, outfits, moods) and come back when it's on again.
    func setMultiPets(_ on: Bool) {
        guard on != multiPets else { return }
        if !on {
            save()                                           // remember who was out, then send them home
            for c in companions { c.panel.orderOut(nil); c.bubble.hide(); c.nameTag.hide() }
            companions = []
            multiPets = false
        } else {
            multiPets = true
            if let data = defaults.data(forKey: "companions"), let recs = try? JSONDecoder().decode([PetRecord].self, from: data) {
                companions = recs.filter { $0.species != pet.species }.prefix(Self.maxCompanions).map { Pet(world: self, record: $0) }
                for c in companions { if !hidden { c.spawnIn() } else { c.panel.orderOut(nil) } }
            }
        }
        save()
    }

    func changeSpecies(to sp: Species) {
        guard pet.species != sp else { return }
        if let c = companions.first(where: { $0.species == sp }) {      // a companion already: it swaps places with yours
            c.species = pet.species
            if c.name == sp.defaultName { c.name = c.species.defaultName }
            c.transformed()
        }
        if pet.name == pet.species.defaultName { pet.name = sp.defaultName }
        pet.species = sp
        pet.transformed()
        save()
    }

    func setOutfit(_ o: Outfit, for target: Pet? = nil) {
        let p = target ?? pet!
        guard p.outfit != o else { return }
        p.outfit = o
        p.admire()
        save()
    }

    func rename(_ name: String) { rename(pet, name) }

    /// Renames any of your pets; it says its new name.
    func rename(_ p: Pet, _ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        guard !n.isEmpty, n != p.name else { return }
        p.name = n
        p.say(["I'M \(sanitize(p.name))!"], 2)
        p.hearts(2)
        save()
    }

    /// Several pets: another one becomes your main pet (the one the menu, dress-up and reminders are about).
    /// Each keeps its own name, outfit and mood.
    func makeMain(_ c: Pet) {
        guard let i = companions.firstIndex(where: { $0 === c }) else { return }
        companions[i] = pet
        pet = c
        c.hearts(2)
        save()
    }

    func toggleHidden(quietly: Bool = false) {
        hidden.toggle()
        // a gray paw means "hidden, click me to bring it back"
        statusItem?.button?.appearsDisabled = hidden
        statusItem?.button?.toolTip = hidden ? "\(pet.name) is hidden. Click to bring them back" : pet.name
        if hidden {
            closePopover()
            agendaCard.hide(); musicCard.hide(); bellCard.hide()
            // the paw can be lost among other menu bar icons, so say how to get the pet back
            let (tip, below) = pet.bubbleTip()
            if !quietly { toast.show(ToastView(title: "\(pet.name) is hidden", detail: "Press ⌃⌥P, or open Pocket Pet again, to bring them back.",
                                 close: { [weak self] in self?.toast.hide() }), tip: tip, below: below, until: t + 6) }
            pets.forEach { $0.panel.orderOut(nil); $0.bubble.hide() }
            items.forEach { $0.panel.orderOut(nil) }
        } else {
            pets.forEach { $0.panel.orderFrontRegardless() }
            items.forEach { $0.panel.orderFrontRegardless() }
            lastTick = now()
        }
    }

    func showIfHidden() { if hidden { toggleHidden() } }

    /// A click somewhere else closes an open calendar or music card right away. Clicks on the pet are left to it
    /// (one click toggles the music card, a double-click the calendar).
    func clickedOutsideCards(onPet: Bool) {
        guard !onPet else { return }
        let m = NSEvent.mouseLocation
        for card in [agendaCard, musicCard] where card.visible && !card.frame.contains(m) { card.hide() }
        if waterCard.visible && waterCard.until - t > 3 && !waterCard.frame.contains(m) { snoozeWater(quietly: true) }
        if habitCard.visible && !habitCard.frame.contains(m), let id = showingHabit { answerHabit(id, false) }
    }

    /// A new version is out: say so once (it stays in Settings after that).
    /// A new version: a macOS notification, the pet's own toast, a dot on the paw and a banner in the menu. A new version
    /// is announced right away, then again once a day until it's installed.
    func announceUpdate() {
        updateBadge()
        guard let r = updater.available else { return }
        let lastAt = defaults.double(forKey: "announcedAt")
        guard defaults.string(forKey: "announcedVersion") != r.version || Date().timeIntervalSince1970 - lastAt > 86400 else { return }
        defaults.set(r.version, forKey: "announcedVersion")
        defaults.set(Date().timeIntervalSince1970, forKey: "announcedAt")
        notifyUpdate(r.version)
        guard !hidden else { return }
        pet.say(["NEW VERSION!"], 3)
        let (tip, below) = pet.bubbleTip()
        toast.show(ToastView(title: "Pocket Pet \(r.version) is here", detail: "Click to update. It takes a few seconds and restarts your pet.",
                             close: { [weak self] in self?.toast.hide(); self?.updater.install() }), tip: tip, below: below, until: t + 25)
    }

    /// The system notification (macOS asks once whether Pocket Pet may send them). Clicking it installs the update.
    private func notifyUpdate(_ version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = "Pocket Pet \(version) is here"
            c.body = "Click to update. It takes a few seconds and your pet comes right back."
            c.sound = .default
            center.add(UNNotificationRequest(identifier: "update-\(version)", content: c, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("update-") { DispatchQueue.main.async { self.updater.install() } }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    /// A dot on the menu bar paw while an update is waiting.
    func updateBadge() {
        statusItem?.button?.image = pawIcon(dot: updater.available != nil)
    }

    /// ⌃⌥P, or opening the app again: bring a hidden pet back, otherwise open its menu.
    func summon() {
        if hidden {
            toggleHidden()
            pet.say(["I'M BACK!"], 1.6)
        } else if !popover.isShown {
            showPopover(for: pet)
        }
    }

    /// A system-wide shortcut (no permission needed for this kind).
    private func registerShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            let world = Unmanaged<World>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { world.summon() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x5050_4554), id: 1)        // "PPET"
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    /// Asked once and remembered: the menu redraws often and asking macOS each time is slow.
    private var loginState: Bool?
    var openAtLogin: Bool {
        get {
            if let s = loginState { return s }
            var on = false
            if #available(macOS 13.0, *) { on = SMAppService.mainApp.status == .enabled }
            loginState = on
            return on
        }
        set {
            guard #available(macOS 13.0, *) else { return }
            defer { loginState = nil }
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                let a = NSAlert()
                a.messageText = "Couldn't change Open at login"
                a.informativeText = "Move Pocket Pet into your Applications folder and try again.\n\n\(error.localizedDescription)"
                a.runModal()
            }
        }
    }

    func quit() {
        save()
        NSApp.terminate(nil)
    }

    // MARK: Persistence

    func load() {
        let d = defaults
        gravity = d.object(forKey: "gravity") as? Bool ?? true
        sizeSetting = d.object(forKey: "size") as? Int ?? 4
        sleepAfter = d.object(forKey: "sleepAfter") as? Double ?? 120
        soundOn = d.object(forKey: "sound") as? Bool ?? true
        stillness = d.integer(forKey: "stillness")
        stillTyping = d.object(forKey: "stillTyping") as? Bool ?? true
        stillWatching = d.object(forKey: "stillWatching") as? Bool ?? true
        stillMusic = d.object(forKey: "stillMusic") as? Bool ?? true
        napLength = d.double(forKey: "napLength")
        startleOnMusic = d.object(forKey: "startleOnMusic") as? Bool ?? true
        fullscreenClimb = d.object(forKey: "fullscreenClimb") as? Bool ?? true
        followFor = d.object(forKey: "followFor") as? Double ?? 60
        followSpeed = d.object(forKey: "followSpeed") as? Int ?? 1
        showName = d.bool(forKey: "showName")
        Item.doubleClickRemoves = d.object(forKey: "doubleClickRemoves") as? Bool ?? true
        volumes = d.dictionary(forKey: "volumes") as? [String: Double] ?? [:]
        fixedGoalML = d.object(forKey: "waterGoalML") as? Int ?? (d.object(forKey: "waterGoal") as? Int ?? 8) * 250
        waterUnit = WaterUnit(rawValue: d.integer(forKey: "waterUnit")) ?? .glasses
        glassML = d.object(forKey: "glassML") as? Int ?? 250
        sipML = d.object(forKey: "sipML") as? Int ?? 25
        waterGoalMode = d.integer(forKey: "waterGoalMode")
        weightKG = d.object(forKey: "weightKG") as? Double ?? 65
        weightInLB = d.bool(forKey: "weightInLB")
        activity = d.object(forKey: "activity") as? Int ?? 1
        hotWeather = d.bool(forKey: "hotWeather")
        wakeMinutes = d.object(forKey: "wakeMinutes") as? Int ?? 8 * 60
        bedMinutes = d.object(forKey: "bedMinutes") as? Int ?? 23 * 60
        quietAtNight = d.object(forKey: "quietAtNight") as? Bool ?? true
        if let data = d.data(forKey: "habits"), let h = try? JSONDecoder().decode([Habit].self, from: data) { habits = h }
        bellOn = d.object(forKey: "bell") as? Bool ?? true
        bellTabs = d.object(forKey: "bellTabs") as? Bool ?? true
        useMacCalendar = d.object(forKey: "useMacCalendar") as? Bool ?? true
        waterEvery = d.object(forKey: "water") as? Double ?? 3600
        let saved = d.double(forKey: "savedAt")
        awaySeconds = saved > 0 ? Date().timeIntervalSince1970 - saved : 0
        var rec: PetRecord?
        if let data = d.data(forKey: "pet") { rec = try? JSONDecoder().decode(PetRecord.self, from: data) }
        if rec == nil, let data = d.data(forKey: "pets"), let all = try? JSONDecoder().decode([PetRecord].self, from: data) { rec = all.first }
        if rec == nil, let n = d.string(forKey: "name") {
            rec = PetRecord(id: UUID().uuidString, species: .goose, name: n, outfit: Outfit(),
                            fullness: d.double(forKey: "fullness"), happiness: d.double(forKey: "happiness"),
                            energy: d.double(forKey: "energy"), x: d.double(forKey: "x"))
        }
        if rec == nil {
            firstRun = true
            rec = PetRecord(id: UUID().uuidString, species: .goose, name: "Honk", outfit: Outfit(), fullness: 80, happiness: 80, energy: 90, x: 0)
        }
        var r = rec!
        if awaySeconds > 60 {
            r.fullness = clamp(r.fullness - awaySeconds * 100 / (6 * 3600) * 0.5, 5, 100)
            r.happiness = clamp(r.happiness - awaySeconds * 100 / (8 * 3600) * 0.5, 15, 100)
            if awaySeconds > 3600 { r.energy = 100 }
        }
        pet = Pet(world: self, record: r)
        multiPets = d.bool(forKey: "multiPets")
        playTogether = d.object(forKey: "playTogether") as? Bool ?? true
        if multiPets, let data = d.data(forKey: "companions"), let recs = try? JSONDecoder().decode([PetRecord].self, from: data) {
            companions = recs.prefix(Self.maxCompanions).map { Pet(world: self, record: $0) }
        }
        if let data = d.data(forKey: "restingPets"), let recs = try? JSONDecoder().decode([PetRecord].self, from: data) { resting = recs }
    }

    func save() {
        let d = defaults
        d.set(gravity, forKey: "gravity")
        d.set(sizeSetting, forKey: "size")
        d.set(sleepAfter, forKey: "sleepAfter")
        d.set(soundOn, forKey: "sound")
        d.set(stillness, forKey: "stillness")
        d.set(stillTyping, forKey: "stillTyping"); d.set(stillWatching, forKey: "stillWatching"); d.set(stillMusic, forKey: "stillMusic")
        d.set(napLength, forKey: "napLength")
        d.set(startleOnMusic, forKey: "startleOnMusic")
        d.set(fullscreenClimb, forKey: "fullscreenClimb")
        d.set(followFor, forKey: "followFor"); d.set(followSpeed, forKey: "followSpeed")
        d.set(showName, forKey: "showName")
        d.set(Item.doubleClickRemoves, forKey: "doubleClickRemoves")
        d.set(volumes, forKey: "volumes")
        d.set(fixedGoalML, forKey: "waterGoalML")
        d.set(waterUnit.rawValue, forKey: "waterUnit"); d.set(glassML, forKey: "glassML"); d.set(sipML, forKey: "sipML")
        d.set(waterGoalMode, forKey: "waterGoalMode"); d.set(weightKG, forKey: "weightKG"); d.set(weightInLB, forKey: "weightInLB")
        d.set(activity, forKey: "activity"); d.set(hotWeather, forKey: "hotWeather")
        d.set(wakeMinutes, forKey: "wakeMinutes"); d.set(bedMinutes, forKey: "bedMinutes"); d.set(quietAtNight, forKey: "quietAtNight")
        if let data = try? JSONEncoder().encode(habits) { d.set(data, forKey: "habits") }
        d.set(bellOn, forKey: "bell")
        d.set(bellTabs, forKey: "bellTabs")
        d.set(useMacCalendar, forKey: "useMacCalendar")
        d.set(waterEvery, forKey: "water")
        if let data = try? JSONEncoder().encode(pet.record) { d.set(data, forKey: "pet") }
        d.set(multiPets, forKey: "multiPets")
        d.set(playTogether, forKey: "playTogether")
        if multiPets, let data = try? JSONEncoder().encode(companions.map(\.record)) { d.set(data, forKey: "companions") }    // kept while it's off
        if let data = try? JSONEncoder().encode(resting) { d.set(data, forKey: "restingPets") }
        d.set(Date().timeIntervalSince1970, forKey: "savedAt")
    }

    // MARK: Menu bar panel

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = pawIcon()
        statusItem.button?.toolTip = pet.name
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        ui.world = self
        let host = NSHostingController(rootView: RootView(m: ui))
        if #available(macOS 13.0, *) { host.sizingOptions = [.preferredContentSize] }
        popover.contentViewController = host
    }

    @objc func statusClicked() {
        if popover.isShown { popover.performClose(nil); return }
        // pet hidden: a click on the paw brings it back (right-click still opens the menu)
        if hidden && NSApp.currentEvent?.type != .rightMouseUp {
            toggleHidden()
            pet.say(["I'M BACK!"], 1.6)
            return
        }
        guard let b = statusItem.button else { return }
        ui.focus = nil
        open(from: b, rect: b.bounds, edge: .minY)
    }

    func showPopover(for p: Pet) {
        if popover.isShown { popover.performClose(nil) }
        guard !p.inAir, p.edge == 0, p.mode != .held, p.mode != .glide, p.mode != .drift, let r = p.hitRectScreen() else {
            statusClicked()
            return
        }
        popoverPet = p
        ui.focus = p === pet ? nil : p.id          // the menu looks after the pet you clicked
        p.freeze()
        let f = p.panel.frame
        open(from: p.view, rect: NSRect(x: r.minX - f.minX, y: f.maxY - r.maxY, width: r.width, height: r.height), edge: .maxY)
    }

    private func open(from view: NSView, rect: NSRect, edge: NSRectEdge) {
        agendaCard.hide(); musicCard.hide(); bellCard.hide(); toast.hide()      // one menu at a time
        player.refresh()
        player.refreshUpNext()
        NSApp.activate(ignoringOtherApps: true)
        ui.refresh()
        popover.show(relativeTo: rect, of: view, preferredEdge: edge)
        popover.contentViewController?.view.window?.makeKey()   // so the very first click on a button counts
        uiTimer?.invalidate()
        // The needs bars change slowly: every 5 s is plenty (the song's progress bar ticks by itself, and redrawing the
        // whole menu every second made scrolling the queue stutter).
        let tm = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.ui.refresh() }
        tm.tolerance = 1
        RunLoop.main.add(tm, forMode: .common)
        uiTimer = tm
    }

    func closePopover() { if popover.isShown { popover.performClose(nil) } }

    func popoverDidClose(_ notification: Notification) {
        uiTimer?.invalidate()
        uiTimer = nil
        if let p = popoverPet, p.mode == .idle { p.actDur = 1 }
        popoverPet = nil
        // names typed but not confirmed with Return still count
        if ui.editing { rename(ui.draft) }
        for (id, n) in ui.names { if let p = pets.first(where: { $0.id == id }) { rename(p, n) } }
        ui.editing = false; ui.names = [:]; ui.renaming = nil
        ui.tab = 0; ui.closetPart = 0              // the menu always opens on Pets again, whatever tab you left it on
    }

    func pawIcon(dot: Bool = false) -> NSImage {
        let rows = [
            "....XX.XX....",
            "...XXX.XXX...",
            ".XX.XX.XX.XX.",
            "XXX.......XXX",
            "XX..XXXXX..XX",
            "...XXXXXXX...",
            "..XXXXXXXXX..",
            "..XXXXXXXXX..",
            "...XXXXXXX...",
            "....XXXXX....",
        ]
        let img = NSImage(size: NSSize(width: dot ? 18 : 15, height: 14), flipped: true) { _ in
            // a template draws in black and macOS tints it; with the update dot it draws in the menu bar's own text color
            (dot ? NSColor.labelColor : NSColor.black).setFill()
            for (r, row) in rows.enumerated() {
                for (i, ch) in row.enumerated() where ch == "X" { NSRect(x: 1 + i, y: 2 + r, width: 1, height: 1).fill() }
            }
            if dot { NSColor.systemRed.setFill(); NSBezierPath(ovalIn: NSRect(x: 12.5, y: 0.5, width: 5, height: 5)).fill() }
            return true
        }
        img.isTemplate = !dot
        return img
    }

    // MARK: Pictures for the panel (in grayscale, to match the black-and-white panel)

    func iconImage(_ ic: Icon) -> NSImage {
        let key = "icon-\(ic)"
        if let i = imageCache[key] { return i }
        let img = iconCanvas(ic).trimmed(0).image(grayPalette(basePalette), scale: 8)
        imageCache[key] = img
        return img
    }

    /// Menu buttons that need the pet to move: close the menu first (the pet holds still while it's open).
    func fromMenu(_ action: () -> Void) {
        if let p = popoverPet { popoverPet = nil; if p.mode == .idle { p.actDur = 1 } }
        closePopover()
        action()
    }

    func itemImage(_ k: ItemKind) -> NSImage {
        let key = "item-\(k)"
        if let i = imageCache[key] { return i }
        let pal = grayPalette(k == .butterfly ? makePalette(butterflyPalettes[0]) : basePalette)   // lavender, edged darker, reads well in gray
        let img = itemCanvas(k, bites: 0, frame: 0).trimmed(0).image(pal, scale: 8)
        imageCache[key] = img
        return img
    }

    /// One accessory on its own, for the closet's tiles (nil for "none").
    func accessoryImage(_ o: Outfit) -> NSImage? {
        let key = "acc-\(o.hat.rawValue)-\(o.glasses.rawValue)-\(o.neck.rawValue)"
        if let i = imageCache[key] { return i }
        var c = Canvas(32, 28)
        drawAccessory(&c, o)
        guard c.bounds() != nil else { return nil }
        c.outline()
        let img = c.trimmed(1).image(grayPalette(basePalette), scale: 8)
        imageCache[key] = img
        return img
    }

    /// The whole pet in its outfit, for the closet.
    func bodyImage(_ sp: Species, _ o: Outfit) -> NSImage {
        let key = "body-\(sp.rawValue)-\(o.hat.rawValue)-\(o.glasses.rawValue)-\(o.neck.rawValue)"
        if let i = imageCache[key] { return i }
        var p = Pose()
        p.outfit = o
        if !sp.isBird { p.stance = .sit; p.tailUp = false }
        if sp.family == .dog { p.mouth = .tongue }
        var c = Canvas(canvasW, canvasH)
        drawPet(&c, sp, p, cx: canvasW / 2)
        c.outline()
        let img = c.trimmed(1).image(grayPalette(makePalette(sp.colors)), scale: 6)
        imageCache[key] = img
        return img
    }

    /// Just the pet's face (and whatever it's wearing on its head).
    func faceImage(_ sp: Species, _ o: Outfit = Outfit(), roomForHat: Bool = false) -> NSImage {
        let key = "face-\(sp.rawValue)-\(o.hat.rawValue)-\(o.glasses.rawValue)-\(o.neck.rawValue)-\(roomForHat)"
        if let i = imageCache[key] { return i }
        var p = Pose()
        p.outfit = o
        if !sp.isBird { p.stance = .sit; p.tailUp = false }
        if sp.family == .dog { p.mouth = .tongue }
        if sp == .turtle { p.stance = .upright; p.prop = .laptop; p.headDY = 99 }     // the front-facing face (no laptop drawn)
        var c = Canvas(canvasW, canvasH)
        let a = drawPet(&c, sp, p, cx: canvasW / 2)
        c.outline()
        let up = roomForHat || sp == .bat ? 8 : 4       // the bat's ears stick up
        let crop = sp == .turtle ? c.cropped(a.headX - 8, a.headTop - 1, a.headX + 8, a.headTop + 13)      // its whole round face
            : a.profile
            ? c.cropped(a.headX - 4, a.headTop - up, a.headX + 8, a.headTop + 7)
            : c.cropped(a.headX - 7, a.headTop - up, a.headX + 7, a.headTop + 9)
        let img = crop.image(grayPalette(makePalette(sp.colors)), scale: 6)
        imageCache[key] = img
        return img
    }
}
