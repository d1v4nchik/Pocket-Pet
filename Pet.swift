// The pet: its body, brain, drawing and how it reacts to the mouse.

import Cocoa

enum Mode {
    case fly, glide, drift, landing, dizzy, held,
         idle, walk, typing, watching, listening, yawning, sleeping, waking, catnap,
         eating, refusing, ball, tired, butterfly, vocal, angry, petted, beg, zoomies, hunt, agenda
}
enum IdleAct { case stand, look, preen, peck, sit, vocal, yawn, flap, hop, gaze, lie, groom, stretch, beg }
enum FlyGoal { case wander, land }

/// Things a pet has to be on the floor for.
private let edgeAngle: [CGFloat] = [0, -.pi / 2, .pi, .pi / 2]

private let groundModes: Set<Mode> = [.typing, .watching, .listening, .yawning, .sleeping, .waking, .catnap,
                                      .tired, .beg, .zoomies, .hunt, .walk, .refusing, .agenda]

struct PetRecord: Codable {
    var id: String
    var species: Species
    var name: String
    var outfit: Outfit
    var fullness: Double
    var happiness: Double
    var energy: Double
    var x: Double
}

/// Shows the pet as a tiny bitmap that the graphics card scales up with hard pixel edges,
/// instead of repainting a Retina-size window on the CPU for every frame.
final class PetView: NSView {
    weak var pet: Pet?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.magnificationFilter = .nearest
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = pet?.spriteImage() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pet?.mouseDown() }
    override func mouseDragged(with event: NSEvent) { pet?.mouseDragged() }
    override func mouseUp(with event: NSEvent) { pet?.mouseUp(clicks: event.clickCount) }
    override func rightMouseDown(with event: NSEvent) {
        guard let pet else { return }
        pet.world.showPopover(for: pet)
    }
}

/// Speech bubbles live in their own little window so they never get cut off.
final class BubbleWindow {
    let panel = Panel(size: CGSize(width: 10, height: 10))
    private let view = BubbleView()
    private var shown: ([String], CGPoint, Bool)?

    init() {
        panel.contentView = view
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    func show(_ lines: [String], tip: CGPoint, below: Bool, px: CGFloat) {
        let key = (lines, CGPoint(x: tip.x.rounded(), y: tip.y.rounded()), below)
        if let s = shown, s.0 == key.0, s.1 == key.1, s.2 == key.2 { return }
        shown = key
        let sz = bubbleSize(lines, px: px)
        let tail = 3 * px
        let screen = NSScreen.screens.first { $0.frame.contains(tip) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let w = sz.width, h = sz.height + tail
        let ox = clamp(tip.x - w / 2, vf.minX + 2, max(vf.minX + 2, vf.maxX - w - 2))
        let oy = clamp(below ? tip.y - h : tip.y, vf.minY + 2, max(vf.minY + 2, vf.maxY - h - 2))
        panel.setFrame(NSRect(x: ox.rounded(), y: oy.rounded(), width: w, height: h), display: false)
        view.frame = NSRect(x: 0, y: 0, width: w, height: h)
        view.lines = lines
        view.tipX = tip.x - ox.rounded()
        view.below = below
        view.px = px
        view.needsDisplay = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        guard shown != nil else { return }
        shown = nil
        panel.orderOut(nil)
    }
}

final class BubbleView: NSView {
    var lines: [String] = []
    var tipX: CGFloat = 0
    var below = false
    var px: CGFloat = 2
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, !lines.isEmpty else { return }
        ctx.setShouldAntialias(false)
        drawBubble(ctx, lines, bx: 0, by: below ? 3 * px : 0, tipX: tipX, px: px, tailUp: below)
    }
}

final class Pet {
    unowned let world: World
    let id: String
    var species: Species { didSet { palette = makePalette(species.colors) } }
    var name: String
    var outfit: Outfit
    var palette: [CGColor]
    var fullness: Double, happiness: Double, energy: Double

    let cw = canvasW, chh = canvasH, cx = canvasW / 2
    var g: Int { chh - 2 }
    var s: CGFloat { world.scale }
    var t: Double { world.t }
    var panel: Panel!
    var view: PetView!
    let bubble = BubbleWindow()
    var side: CGFloat = 0

    // body: (x, y) is where the pet touches the floor/wall/ceiling, in screen points
    var x: CGFloat, y: CGFloat = 0
    var p: CGFloat = 0              // position around the screen edge (zero gravity)
    var edge = 0                    // 0 floor, 1 right wall, 2 ceiling, 3 left wall
    var vx: CGFloat = 0, vy: CGFloat = 0
    var hopY: CGFloat = 0, hopV: CGFloat = 0, leapV: CGFloat = 0
    var facing = 1, turnAt = -10.0
    var apexY: CGFloat = 0
    var inAir = false               // birds flying
    var umbrella = false
    var moving = false, running = false, walkT = 0.0, flapT = 0.0

    // brain
    var mode: Mode = .glide, modeT = 0.0
    var act: IdleAct = .stand, actT = 0.0, actDur = 2.0
    var walkTarget: CGFloat = 0
    var flyGoal: FlyGoal = .land, afterLand: Mode?, flyTarget: CGPoint?, nextFlyPick = 0.0
    var nextBlink = 2.0, blinkUntil = 0.0, blushUntil = 0.0
    var greeted = false
    var forcedNap = false, sleptAt = 0.0, napEnd = 0.0
    var seated = false, popT = 0.0
    var nextReact = 0.0, nextBeg = 90.0, nextPeck = 0.0, peckStart = -10.0
    var nextKick = 0.0, kickUntil = 0.0, kicks = 0
    var refuseFacing = 1
    weak var food: Item?
    var celebrateText = "", celebrateUntil = 0.0
    var bubbleLines: [String] = [], bubbleUntil = 0.0
    var particles: [Particle] = []
    var canvas = Canvas(canvasW, canvasH)
    var hitCells: (Int, Int, Int, Int)?
    var head = (x: 32, y: 10)
    var nextZ = 0.0, nextSweat = 0.0, nextNote = 0.0
    var zoomLeft = 0, huntPhase = 0, huntT = 0.0, agendaUntil = 0.0
    var agendaProp = Prop.calendar, drinkUntil = 0.0      // what it holds up: the calendar, or a glass of water
    var quickDrop = false
    var noticedUntil = -10.0
    var playUntil = -10.0           // playing with a toy you just gave it: typing waits a moment
    var sliding = false           // dragged along the top edge in fullscreen
    var followUntil = 0.0             // "come here": tags along after the cursor until then
    var following: Bool { t < followUntil }
    var lastStance = Stance.stand, transitionUntil = 0.0
    var drawnEdge = -1
    /// Holds still while any of its menus or cards is open, so they stay with it.
    var frozen: Bool { world.popoverPet === self || world.menuOpen }

    // mouse
    var downAt: CGPoint?, grab = CGPoint.zero, dragging = false
    var samples: [(Double, CGPoint)] = []
    var shake = 0, lastDir = 0
    var clicks: [Double] = []
    private var lastClick: (at: Double, pt: CGPoint)?, pendingClick: DispatchWorkItem?
    var strokeDist: CGFloat = 0, strokeIdle = 0.0, lastMouse = CGPoint.zero, petCooldown = 0.0
    var cursorMovedAt = -10.0, mouseInside = false

    init(world: World, record r: PetRecord) {
        self.world = world
        id = r.id
        species = r.species
        name = r.name
        outfit = r.outfit
        palette = makePalette(r.species.colors)
        fullness = r.fullness; happiness = r.happiness; energy = r.energy
        x = CGFloat(r.x)
        buildWindow()
    }

    var record: PetRecord {
        PetRecord(id: id, species: species, name: name, outfit: outfit, fullness: fullness, happiness: happiness, energy: energy, x: Double(x))
    }

    var family: Family { species.family }
    var isBird: Bool { species.isBird }
    /// Walking the screen edges instead of the floor: zero gravity, or a fullscreen app (then only the top edge).
    var wallMode: Bool { !isBird && (!world.gravity || world.fullscreenApp || family == .bat) }
    var flyMode: Bool { isBird && (!world.gravity || world.fullscreenApp) }
    /// A fullscreen app: four-legged pets get spooked, leap to the top edge and hang out there upside down.
    /// Bats always live up there, hanging.
    var ceilingMode: Bool { !isBird && (world.fullscreenApp || family == .bat) }
    var isAsleep: Bool { mode == .sleeping || mode == .yawning || mode == .catnap }
    var sleepThreshold: Double { world.sleepAfter * (energy < 25 ? 0.5 : 1) }

    /// How often this pet needs to be redrawn right now (lower = less CPU).
    var wantsFPS: Double {
        // As few frames as each moment needs: being dragged or thrown is the only thing that gets 30.
        if mode == .held || mode == .glide || mode == .drift || hopY > 0 { return 30 }
        if inAir || running { return 20 }
        if moving { return 15 }                           // its pixels are 4 pt wide, so walking looks the same at 15
        switch mode {
        case .sleeping, .catnap: return 4                // drifting Zzz read fine at 4
        default: break
        }
        if !particles.isEmpty { return 12 }               // hearts and notes float slowly
        switch mode {
        case .idle, .listening, .watching, .agenda, .beg: return 8
        case .typing: return 12
        default: return 16
        }
    }

    // MARK: Window & geometry

    func buildWindow() {
        side = CGFloat(max(cw, chh) + 4) * s
        if panel == nil {
            panel = Panel(size: CGSize(width: side, height: side))
            view = PetView(frame: NSRect(x: 0, y: 0, width: side, height: side))
            view.pet = self
            panel.contentView = view
            panel.acceptsMouseMovedEvents = true
            if !world.hidden { panel.orderFrontRegardless() }
        } else {
            panel.setContentSize(NSSize(width: side, height: side))
            view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        }
        drawnEdge = -1
    }

    func close() {
        releaseFood()
        bubble.hide()
        panel.orderOut(nil)
    }

    /// Where the feet sit inside the (square) window for the current edge.
    func anchorView() -> CGPoint {
        switch edge {
        case 1: return CGPoint(x: side - s, y: side / 2)
        case 2: return CGPoint(x: side / 2, y: s)
        case 3: return CGPoint(x: s, y: side / 2)
        default: return CGPoint(x: side / 2, y: side - s)
        }
    }

    /// Canvas cell -> point inside the window. The canvas is turned onto walls and the ceiling.
    func toView(_ cxp: Double, _ cyp: Double) -> CGPoint {
        let dx = (CGFloat(cxp) - (CGFloat(cx) + 0.5)) * s, dy = (CGFloat(cyp) - CGFloat(chh - 1)) * s
        let a = edgeAngle[edge]
        let c = cos(a).rounded(), sn = sin(a).rounded()
        let av = anchorView()
        return CGPoint(x: av.x + dx * c - dy * sn, y: av.y + dx * sn + dy * c)
    }

    func cellToScreen(_ cxp: Double, _ cyp: Double) -> CGPoint {
        let v = toView(cxp, cyp)
        return CGPoint(x: panel.frame.minX + v.x, y: panel.frame.minY + side - v.y)
    }

    func localX(_ lx: Int) -> Double { Double(facing > 0 ? lx : 2 * cx - lx) }
    func mouthPoint() -> CGPoint {
        family == .bat ? cellToScreen(Double(cx), Double(head.y + 6)) : cellToScreen(localX(cx + 12), Double(chh - 6))
    }
    func centerPoint() -> CGPoint { cellToScreen(Double(cx), Double(chh - 12)) }

    func hitRectScreen() -> CGRect? {
        guard let hc = hitCells else { return nil }
        // Symmetric around the body so turning around never changes the clickable area.
        let reach = max(cx - hc.0, hc.2 - cx)
        let pts = [cellToScreen(Double(cx - reach), Double(hc.1)), cellToScreen(Double(cx + reach + 1), Double(hc.1)),
                   cellToScreen(Double(cx - reach), Double(hc.3 + 1)), cellToScreen(Double(cx + reach + 1), Double(hc.3 + 1))]
        let xs = pts.map { $0.x }, ys = pts.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func place() {
        let av = anchorView(), up = upVec()
        let o = NSPoint(x: (x + up.dx * hopY - av.x).rounded(), y: (y + up.dy * hopY - (side - av.y)).rounded())
        if panel.frame.origin != o { panel.setFrameOrigin(o) }
    }

    func upVec() -> CGVector { [CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)][edge] }
    func fwdVec() -> CGVector { [CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)][edge] }

    func area() -> CGRect {
        let up = upVec()
        return world.area(near: CGPoint(x: x + up.dx * 10, y: y + up.dy * 10))
    }

    var margin: CGFloat { 17 * s }

    func perimeter(_ a: CGRect) -> (CGRect, CGFloat) {
        let R = a.insetBy(dx: margin, dy: margin)
        return (R, 2 * (R.width + R.height))
    }

    func placeOnPerimeter() {
        let a = area()
        let (R, L) = perimeter(a)
        guard L > 0 else { return }
        var q = p.truncatingRemainder(dividingBy: L)
        if q < 0 { q += L }
        p = q
        if q < R.width { edge = 0; x = R.minX + q; y = a.minY }
        else if q < R.width + R.height { edge = 1; x = a.maxX; y = R.minY + (q - R.width) }
        else if q < 2 * R.width + R.height { edge = 2; x = R.maxX - (q - R.width - R.height); y = a.maxY }
        else { edge = 3; x = a.minX; y = R.maxY - (q - 2 * R.width - R.height) }
    }

    func perimeterP(nearX px: CGFloat, y py: CGFloat) -> CGFloat {
        let a = area()
        let (R, _) = perimeter(a)
        let dB = abs(py - a.minY), dT = abs(a.maxY - py), dL = abs(px - a.minX), dR = abs(a.maxX - px)
        let m = min(dB, dT, dL, dR)
        if m == dB { return clamp(px, R.minX, R.maxX) - R.minX }
        if m == dR { return R.width + clamp(py, R.minY, R.maxY) - R.minY }
        if m == dT { return R.width + R.height + (R.maxX - clamp(px, R.minX, R.maxX)) }
        return 2 * R.width + R.height + (R.maxY - clamp(py, R.minY, R.maxY))
    }

    func trackDelta(_ target: CGFloat) -> CGFloat {
        guard wallMode else { return target - x }
        let L = perimeter(area()).1
        guard L > 0 else { return 0 }
        var d = (target - p).truncatingRemainder(dividingBy: L)
        if d > L / 2 { d -= L }
        if d < -L / 2 { d += L }
        return d
    }

    /// Walk along the floor (or climb around the walls) toward a track position.
    @discardableResult
    func go(_ target: CGFloat, speed: CGFloat, _ dt: Double, run: Bool = false) -> Bool {
        let d = trackDelta(target)
        if abs(d) < 3 { return true }
        facing = d > 0 ? 1 : -1
        let v = speed * s / 4 * (fullness < 15 ? 0.7 : 1) * CGFloat(dt)
        if wallMode { p += CGFloat(facing) * min(abs(d), v) } else { x += CGFloat(facing) * min(abs(d), v) }
        moving = true
        running = run
        walkT += dt
        return false
    }

    func floorTarget(_ px: CGFloat, _ py: CGFloat) -> CGFloat {
        if ceilingMode { let top = topSpan(); return clamp(perimeterP(nearX: px, y: area().maxY), top.lowerBound, top.upperBound) }
        return wallMode ? perimeterP(nearX: px, y: area().minY) : px
    }

    @discardableResult
    func flyTo(_ tp: CGPoint, speed: CGFloat, _ dt: Double) -> Bool {
        let dx = tp.x - x, dy = tp.y - y
        let d = hypot(dx, dy)
        let sp = min(speed * s / 4, d * 3)
        let tvx = d > 0.1 ? dx / d * sp : 0, tvy = d > 0.1 ? dy / d * sp : 0
        let k = CGFloat(min(1, dt * 3))
        vx += (tvx - vx) * k
        vy += (tvy - vy) * k
        x += vx * CGFloat(dt)
        y += vy * CGFloat(dt)
        if abs(vx) > 8 { facing = vx > 0 ? 1 : -1 }
        flapT += dt * (vy > 20 || abs(vx) > 60 ? 1.6 : 1)
        return d < 6
    }

    func flyBounds() -> CGRect {
        let a = area()
        return CGRect(x: a.minX + margin, y: a.minY + 10, width: max(1, a.width - 2 * margin), height: max(1, a.height - CGFloat(chh) * s - 20))
    }

    /// Turn toward a point, with a dead zone and a short cooldown so it never flickers.
    func face(toward pt: CGPoint, dead: CGFloat = 40) {
        guard t - turnAt > 0.8 else { return }
        let f = fwdVec()
        let d = (pt.x - x) * f.dx + (pt.y - y) * f.dy
        guard abs(d) > dead else { return }
        let nf = d > 0 ? 1 : -1
        if nf != facing { facing = nf; turnAt = t }
    }

    // MARK: Lifecycle

    func spawnIn() {
        let main = NSScreen.main ?? NSScreen.screens[0]
        let r = world.xRange(margin)
        if x == 0 || !r.contains(x) { x = main.visibleFrame.midX + CGFloat.random(in: -250...250) }
        x = clamp(x, r.lowerBound, r.upperBound)
        let a = world.area(near: CGPoint(x: x, y: main.frame.midY))
        y = a.maxY - CGFloat(chh) * s * 0.9
        apexY = y
        edge = 0
        mode = .idle
        if isBird {
            inAir = true; vy = -60
            flyGoal = flyMode ? .wander : .land
            setMode(.fly)
        } else if !wallMode {
            setMode(.glide)
        } else {
            y = a.midY
            vx = CGFloat.random(in: -160...160); vy = CGFloat.random(in: -160...160)
            setMode(.drift)
        }
    }

    func update(_ dt: Double) {
        modeT += dt; actT += dt
        moving = false; running = false
        if t > nextBlink { blinkUntil = t + 0.12; nextBlink = t + rnd(2.5, 6) }
        if !frozen || inAir || mode == .held || mode == .glide || mode == .drift {
            think(dt)
            physics(dt)
        }
        updateParticles(dt)
        let old = canvas.px
        renderCanvas()
        place()
        updateMouse(dt)
        if canvas.px != old || edge != drawnEdge {
            drawnEdge = edge
            view.needsDisplay = true
        }
        updateBubble()
    }

    /// The panel is open on this pet: sit still and look at the person.
    func freeze() {
        guard !inAir, mode != .held, mode != .glide, mode != .drift, edge == 0 else { return }
        if !isAsleep { setMode(.idle); act = isBird ? .stand : .sit; actT = 0; actDur = 1.5 }
    }

    func environmentChanged() {
        guard mode != .held else { return }
        if ceilingMode {
            guard edge != 2 || mode == .drift else { return }
            if family == .bat { if mode != .drift { swoop(home: true) }; return }
            // Startled by the fullscreen app: a jump, and a dash for the top edge.
            releaseFood()
            spawnBang()
            say([family == .cat ? "EEK!" : "WHOA!"], 1.4)
            world.synth.play(family == .cat ? "hiss" : "woof")
            hopY = 0; hopV = 0; umbrella = false
            vx = 0; vy = 1500 * s / 4
            setMode(.drift)
            return
        }
        if world.gravity {
            if isBird {
                if inAir && !flyMode { flyGoal = .land; afterLand = nil }
                if !inAir && flyMode && (mode == .idle || mode == .walk) { takeOff() }
            } else if edge != 0 || mode == .drift {
                // back from the top edge (fullscreen ended, or gravity turned on): a quick drop, no slow umbrella float
                let a = area()
                x = clamp(x, a.minX + margin, a.maxX - margin)
                y = clamp(y, a.minY, a.maxY - CGFloat(chh) * s * 0.8)
                edge = 0
                startFalling()
                quickDrop = true
            }
        } else {
            if isBird {
                if !inAir { takeOff() }
            } else {
                p = perimeterP(nearX: x, y: y)
                if mode == .glide { umbrella = false; setMode(.drift) }
            }
        }
    }

    func takeOff() {
        inAir = true
        edge = 0
        vy = 220 * s / 4
        vx = CGFloat(facing) * 40
        flyGoal = .wander
        flyTarget = nil
        afterLand = nil
        setMode(.fly)
    }

    func startFalling() {
        apexY = y
        hopY = 0
        if isBird {
            inAir = true; flyGoal = .land; afterLand = nil
            setMode(.fly)
        } else {
            umbrella = false
            vx = 0; vy = 0
            setMode(.glide)
        }
    }

    // MARK: Brain

    func setMode(_ m: Mode) {
        guard m != mode else { return }
        if mode == .eating { releaseFood() }
        if mode == .glide { umbrella = false }
        mode = m
        modeT = 0
        switch m {
        case .waking:
            spawnBang()
            world.synth.play("yawn")
        case .watching:
            seated = false
            nextReact = t + rnd(30, 60)
        case .ball:
            kicks = 0
        case .zoomies:
            walkTarget = farTarget()
        case .hunt:
            huntPhase = 0; huntT = 0
        case .catnap:
            nextZ = t + 1
        case .sleeping:
            sleptAt = t; nextZ = t + 0.4
        case .listening:
            nextNote = t + 0.3
        default:
            break
        }
    }

    func releaseFood() {
        if let f = food, f.claim === self { f.claim = nil }
        food = nil
    }

    func say(_ lines: [String], _ dur: Double) {
        bubbleLines = lines.map(sanitize).filter { !$0.isEmpty }
        bubbleUntil = t + dur
    }

    /// Starts a mode, landing or climbing down first if the pet needs the floor for it.
    @discardableResult
    func begin(_ m: Mode) -> Bool {
        if inAir && (groundModes.contains(m) || (m == .eating && world.gravity)) {
            flyGoal = .land
            afterLand = m
            if mode != .fly { setMode(.fly) }
            return true
        }
        setMode(m)
        return true
    }

    /// High-priority reasons to stop whatever ambient thing the pet is doing.
    func ambientInterrupt(skipMusic: Bool = false) -> Bool {
        let w = world
        if w.typingNow { return begin(.typing) }
        if w.videoPlaying { return begin(.watching) }
        if let f = w.items.first(where: { $0.isFood && !$0.gone && $0.claim == nil && !$0.refusedBy }) {
            f.claim = self
            food = f
            spawnBang()
            return begin(.eating)
        }
        if w.items.contains(where: { $0.isBall && !$0.gone }) { return begin(.ball) }
        if w.items.contains(where: { $0.kind == .butterfly && !$0.leaving && !$0.gone }) {
            spawnBang()
            return begin(.butterfly)
        }
        if !skipMusic && !following && w.musicPlaying && w.idleSecs < max(sleepThreshold * 3, 600) { return begin(.listening) }
        if w.idleSecs > sleepThreshold { return begin(.yawning) }
        return false
    }

    func think(_ dt: Double) {
        if following { follow() }
        // pressed while on the move: stop and look at you right away (the click's answer follows a beat later)
        if t < noticedUntil && !inAir && [.walk, .zoomies, .hunt, .ball, .butterfly].contains(mode) {
            moving = false
            face(toward: NSEvent.mouseLocation, dead: 10)
            return
        }
        // food and toys get noticed even mid-typing or mid-movie
        if !inAir && [.typing, .watching, .listening].contains(mode) {
            if let f = world.items.first(where: { $0.isFood && !$0.gone && $0.claim == nil && !$0.refusedBy }) {
                f.claim = self; food = f; spawnBang(); begin(.eating); return
            }
            if world.items.contains(where: { $0.isBall && !$0.gone }) { playUntil = t + 10; spawnBang(); begin(.ball); return }
        }
        // notice typing and videos whatever it's busy with, except moments it can't stop (held, falling, landing, eating)
        let cannot: Set<Mode> = [.held, .glide, .drift, .landing, .dizzy, .eating, .typing, .watching, .waking,
                                 .sleeping, .yawning, .catnap, .agenda]
        if !inAir && !cannot.contains(mode) && !(mode == .ball && t < playUntil) {
            if world.typingNow { begin(.typing); return }
            if world.videoPlaying && mode != .listening { begin(.watching); return }
        }
        switch mode {
        case .held: break
        case .fly: flyThink(dt)
        case .glide: glideThink(dt)
        case .drift: driftThink(dt)
        case .landing: if modeT > 0.35 { greetOrIdle() }
        case .dizzy: if modeT > 2.6 { say(["WOAH..."], 1.6); greetOrIdle() }
        case .idle: idleThink(dt)
        case .walk:
            if ambientInterrupt() { return }
            if go(walkTarget, speed: isBird ? 55 : (family == .dog ? 50 : 42), dt, run: running) {
                setMode(.idle); act = .stand; actT = 0; actDur = rnd(1.5, 4)
            }
        case .typing:
            if !world.typingRecently {
                setMode(.idle)
                act = isBird ? .stand : .sit; actT = 0; actDur = rnd(2, 4)
            }
        case .watching: watchThink(dt)
        case .listening: listenThink(dt)
        case .yawning:
            if !forcedNap && world.idleSecs < 0.8 && modeT > 0.3 {
                spawn(.question, Double(head.x), Double(head.y) - 3, vy: -2, life: 1)
                setMode(.idle)
                return
            }
            if modeT > 2.8 { setMode(.sleeping) }
        case .sleeping:
            if t > nextZ { nextZ = t + rnd(1.0, 1.6); spawnZ() }
            if forcedNap {
                if energy >= 100 && modeT > 60 { forcedNap = false; setMode(.waking) }
            } else if world.idleSecs < 0.8 || (world.videoPlaying && modeT > 2) {
                setMode(.waking)
            }
        case .catnap:
            if t > nextZ { nextZ = t + rnd(1.2, 1.8); spawnZ() }
            if t > napEnd || world.typingNow || world.videoPlaying || world.items.contains(where: { !$0.gone && $0.kind != .butterfly }) {
                setMode(.waking)
            }
        case .waking:
            if modeT > 2.6 {
                if world.typingNow { setMode(.typing); return }
                if t - sleptAt > 60 && sleptAt > 0 { say([t - sleptAt > 1800 ? "GOOD MORNING!" : "HI!"], 1.8) }
                sleptAt = 0
                setMode(.idle)
                act = isBird ? .stand : .sit; actT = 0; actDur = 2
            }
        case .eating: eatThink(dt)
        case .refusing:
            facing = modeT < 1.2 && Int(modeT / 0.2) % 2 == 1 ? -refuseFacing : refuseFacing
            if modeT > 1.8 { setMode(.idle) }
        case .ball: ballThink(dt)
        case .tired:
            if t > nextSweat {
                nextSweat = t + 0.7
                spawn(.drop, Double(head.x) - Double(facing) * 2, Double(head.y), vx: -Double(facing) * 2, vy: -2, life: 0.8, g: 14)
            }
            if modeT > 3.5 { energy = max(0, energy - 5); setMode(.idle) }
        case .butterfly: butterflyThink(dt)
        case .vocal, .petted:
            if modeT > (mode == .vocal ? 0.9 : 2.6) { setMode(.idle) }
        case .angry: angryThink(dt)
        case .beg:
            if modeT > 3.2 { setMode(.idle) }
        case .agenda:
            if t > agendaUntil || (world.typingNow && world.lastKeyT > t - modeT + 0.5) { setMode(.idle) }
        case .zoomies:
            if world.typingNow || world.videoPlaying { setMode(.idle); return }
            if go(walkTarget, speed: 250, dt, run: true) {
                zoomLeft -= 1
                if zoomLeft <= 0 {
                    setMode(.idle); act = family == .cat ? .groom : .sit; actT = 0; actDur = 3
                    say(["!"], 0.8)
                } else {
                    walkTarget = farTarget()
                }
            }
        case .hunt: huntThink(dt)
        }
    }

    func greetOrIdle() {
        setMode(.idle)
        act = isBird ? .stand : .sit; actT = 0; actDur = 2.5
        guard !greeted else { return }
        greeted = true
        if world.firstRun {
            say(["HI! I'M \(sanitize(name))", "DRAG ME AROUND!"], 4)
        } else if world.awaySeconds > 3 * 3600 {
            say(["MISSED YOU!"], 2.5)
            hearts(3)
        } else {
            say(["HI!"], 1.8)
        }
        world.synth.play(family == .cat ? "mrrp" : "chirp")
    }

    func idleThink(_ dt: Double) {
        if inAir {
            flyGoal = flyMode ? .wander : .land
            afterLand = nil
            setMode(.fly)
            return
        }
        if ambientInterrupt() { return }
        if flyMode && modeT > (t - world.lastPlay > 180 ? 20 : 1.5) { takeOff(); return }   // calm birds perch a while
        if fullness < 25 && t > nextBeg {
            nextBeg = t + rnd(70, 140)
            setMode(.beg)
            say([isBird ? "HUNGRY..." : "\(species.vocal.word)..."], 3)
            return
        }
        if family == .cat && edge == 0 && !ceilingMode && act != .lie && act != .stretch {
            let m = NSEvent.mouseLocation
            let near = abs(m.x - x) < 420 && m.y - y < 170 && m.y > y - 10 && !mouseInside
            if near && t - cursorMovedAt < 0.4 && chance(dt * 0.25) { setMode(.hunt); return }
        }
        switch act {
        case .look:
            if Int(actT / 0.9) != Int((actT - dt) / 0.9) && chance(0.5) && edge == 0 { facing = -facing; turnAt = t }
        case .stand, .gaze, .sit, .lie:
            let m = NSEvent.mouseLocation
            if !mouseInside && hypot(m.x - x, m.y - y) < 500 { face(toward: m, dead: 60) }
        default:
            break
        }
        if actT > actDur { nextAct() }
    }

    func nextAct() {
        actT = 0
        let r = Double.random(in: 0..<1)
        if ceilingMode {
            // Fullscreen app: pad along the top edge upside down, now and then stopping to look around.
            let top = topSpan()
            if edge != 2 || !top.contains(p) { walkTarget = clamp(p, top.lowerBound, top.upperBound); running = false; setMode(.walk); return }
            let calm = t - world.lastPlay > 180
            if family == .bat {
                if r < (calm ? 0.06 : 0.18) { swoop(home: false); return }
                if r < (calm ? 0.2 : 0.4) { startWalk(); return }
                act = [.stand, .stand, .look, .lie].randomElement()!
                actDur = calm ? rnd(12, 30) : rnd(3, 8)
                return
            }
            if r < (calm ? 0.25 : 0.5) { startWalk(); return }
            act = [.stand, .look, .stand].randomElement()!
            actDur = calm ? rnd(8, 20) : rnd(2, 6)
            return
        }
        if t - world.lastPlay > 180 && chance(0.5) {
            // Left alone for a few minutes, pets settle down like real ones: longer rests, fewer walks (and much less power).
            act = isBird ? [.sit, .stand, .sit].randomElement()! : [.lie, .sit, .lie, family == .cat ? .groom : .lie].randomElement()!
            actDur = rnd(10, 25)
            return
        }
        if wallMode && edge != 0 {
            // clinging to a wall or the ceiling: mostly keep climbing
            if r < 0.6 { startWalk() } else { act = .stand; actDur = rnd(2, 5) }
            return
        }
        switch family {
        case .bird:
            switch r {
            case ..<0.34: startWalk(); return
            case ..<0.48: act = .look; actDur = rnd(2, 4)
            case ..<0.58: act = .sit; actDur = rnd(5, 12)
            case ..<0.66: act = .preen; actDur = rnd(2, 3.5)
            case ..<0.74: act = .peck; actDur = rnd(1.5, 3)
            case ..<0.78: act = .vocal; actDur = 0.9; say([species.vocal.word], 0.9)
            case ..<0.83: act = .flap; actDur = 1.0
            case ..<0.87: act = .hop; actDur = 0.8; hopV = 320 * s / 4
            case ..<0.92: act = .gaze; actDur = rnd(1.5, 3)
            default: act = .stand; actDur = rnd(2, 5)
            }
        case .cat:
            switch r {
            case ..<0.26: startWalk(); return
            case ..<0.40: act = .sit; actDur = rnd(5, 14)
            case ..<0.50: act = .lie; actDur = rnd(8, 20)
            case ..<0.60: act = .groom; actDur = rnd(3, 6)
            case ..<0.65: act = .stretch; actDur = 2.2
            case ..<0.71: act = .look; actDur = rnd(2, 4)
            case ..<0.74: act = .vocal; actDur = 1.0; say([["MEOW", "MRRP?", "MEW"].randomElement()!], 1.0)
            case ..<0.80:
                if energy < 85 { napEnd = t + rnd(20, 50); setMode(.catnap); return }
                act = .lie; actDur = rnd(6, 12)
            case ..<0.84: zoomLeft = Int.random(in: 3...5); setMode(.zoomies); return
            case ..<0.90: act = .gaze; actDur = rnd(2, 4)
            default: act = .stand; actDur = rnd(2, 5)
            }
        case .bat:
            act = .stand; actDur = rnd(3, 8)
        case .dog:
            switch r {
            case ..<0.34: startWalk(); return
            case ..<0.48: act = .sit; actDur = rnd(4, 10)
            case ..<0.58: act = .lie; actDur = rnd(6, 16)
            case ..<0.64: act = .stretch; actDur = 1.8
            case ..<0.70: act = .look; actDur = rnd(2, 4)
            case ..<0.74: act = .vocal; actDur = 0.9; say([species.vocal.word + "!"], 0.9)
            case ..<0.79: zoomLeft = Int.random(in: 3...4); setMode(.zoomies); return
            case ..<0.84: act = .hop; actDur = 0.8; hopV = 300 * s / 4
            case ..<0.90: act = .gaze; actDur = rnd(2, 4)
            default: act = .stand; actDur = rnd(2, 5)
            }
        }
        if energy < 30 && chance(0.3) { act = .yawn; actDur = 1.4 }
    }

    /// A bat lets go of the top edge, flutters out in an arc and flies back up (or just flies up, `home`).
    func swoop(home: Bool) {
        let a = area()
        edge = 0
        y = min(y, a.maxY - 30 * s)
        if home { vx = 0; vy = 300 * s / 4 }
        else {
            vx = (Bool.random() ? 1 : -1) * CGFloat(rnd(380, 560)) * s / 4
            vy = -CGFloat(rnd(750, 1000)) * s / 4
            world.synth.play("chirp")
        }
        setMode(.drift)
    }

    func startWalk() {
        walkTarget = randomWalkTarget()
        running = false
        setMode(.walk)
    }

    /// The stretch of the edge track along the top of the screen.
    func topSpan() -> ClosedRange<CGFloat> {
        let (R, _) = perimeter(area())
        let lo = R.width + R.height
        return (lo + 4)...(lo + max(8, R.width - 4))
    }

    func randomWalkTarget() -> CGFloat {
        if ceilingMode {
            let top = topSpan()
            return clamp(p + CGFloat.random(in: -450...450), top.lowerBound, top.upperBound)
        }
        if wallMode {
            let L = perimeter(area()).1
            return p + CGFloat.random(in: -L * 0.3...L * 0.3)
        }
        let vf = world.area(near: CGPoint(x: x, y: y))
        let lo = max(vf.minX + margin, x - 450), hi = min(vf.maxX - margin, x + 450)
        return lo < hi ? CGFloat.random(in: lo...hi) : x
    }

    func farTarget() -> CGFloat {
        if ceilingMode { return CGFloat.random(in: topSpan()) }
        if wallMode {
            let L = perimeter(area()).1
            return p + (Bool.random() ? 1 : -1) * CGFloat.random(in: L * 0.15...L * 0.4)
        }
        let vf = world.area(near: CGPoint(x: x, y: y))
        let lo = vf.minX + margin, hi = vf.maxX - margin
        guard lo < hi else { return x }
        let mid = (lo + hi) / 2
        return x > mid ? CGFloat.random(in: lo...max(lo, mid)) : CGFloat.random(in: min(hi, mid)...hi)
    }

    func flyThink(_ dt: Double) {
        if flyGoal == .wander && (!flyMode || shake >= 6) { flyGoal = .land; afterLand = nil }
        if flyGoal == .wander {
            if frozen { flyTarget = CGPoint(x: x, y: y); nextFlyPick = t + 1; flyTo(flyTarget!, speed: 95, dt); return }   // hover by the open menu
            if ambientInterrupt() && (mode != .fly || flyGoal == .land) { return }
            let b = flyBounds()
            if flyTarget == nil || t > nextFlyPick {
                if chance(0.3) {
                    flyTarget = CGPoint(x: x, y: y)
                } else {
                    flyTarget = CGPoint(x: CGFloat.random(in: b.minX...b.maxX), y: CGFloat.random(in: min(b.maxY, b.minY + 40)...b.maxY))
                }
                nextFlyPick = t + rnd(3, 7)
            }
            flyTo(flyTarget!, speed: 95, dt)
            return
        }
        let fl = world.floorY(x, y)
        let r = world.xRange(margin)
        let tx = clamp(x + vx * 0.25, r.lowerBound, r.upperBound)
        flyTo(CGPoint(x: tx, y: fl), speed: 130, dt)
        if y - fl < 4 {
            y = fl; vx = 0; vy = 0
            inAir = false
            edge = 0
            if shake >= 6 {
                shake = 0
                setMode(.dizzy)
                stars(5)
            } else if let m = afterLand {
                afterLand = nil
                setMode(m)
            } else {
                setMode(.landing)
            }
        }
    }

    /// Gravity on: pop an umbrella and float down.
    func glideThink(_ dt: Double) {
        let fdt = CGFloat(dt)
        let fl = world.floorY(x, y)
        if !umbrella && !quickDrop && modeT > 0.2 && vy < 0 && y - fl > 60 {
            umbrella = true
            world.synth.play("pop")
        }
        if umbrella {
            vy += (-105 * s / 4 - vy) * min(1, fdt * 4)
            vx *= pow(0.3, fdt)
            x += CGFloat(sin(t * 2.2)) * 22 * fdt * s / 4
        } else {
            vy -= 2200 * fdt * s / 4
        }
        x += vx * fdt
        y += vy * fdt
        apexY = max(apexY, y)
        // pushed or thrown off screen: drift back in smoothly instead of snapping to the edge
        let r = world.xRange(margin)
        let inX = clamp(x, r.lowerBound, r.upperBound)
        if inX != x {
            x += (inX - x) * min(1, fdt * 6)
            if (x < inX && vx < 0) || (x > inX && vx > 0) { vx *= CGFloat(pow(0.05, dt)) }
        }
        let top = world.area(near: CGPoint(x: x, y: y)).maxY - CGFloat(chh) * s
        if y > top { y += (top - y) * min(1, fdt * 6); vy = min(vy, 0) }
        if y <= fl {
            y = fl; vx = 0; vy = 0
            quickDrop = false
            if umbrella {
                umbrella = false
                spawn(.puff, Double(cx), Double(chh - 30), vy: -2, life: 0.5)
            }
            if shake >= 6 {
                setMode(.dizzy)
                stars(5)
            } else {
                setMode(.landing)
                world.synth.play(family == .cat ? "mrrp" : "pop")
            }
            shake = 0
        }
    }

    /// Zero gravity: zip over to the nearest screen edge and hold on to it.
    func driftThink(_ dt: Double) {
        let fdt = CGFloat(dt)
        let a = area()
        // let go somewhere off screen: glide back inside first, then head for an edge
        let inside = CGPoint(x: clamp(x, a.minX, a.maxX), y: clamp(y, a.minY, a.maxY))
        if hypot(inside.x - x, inside.y - y) > 6 {
            x += (inside.x - x) * min(1, fdt * 7)
            y += (inside.y - y) * min(1, fdt * 7)
            vx *= CGFloat(pow(0.1, dt)); vy *= CGFloat(pow(0.1, dt))
            return
        }
        let dB = y - a.minY, dT = a.maxY - y, dL = x - a.minX, dR = a.maxX - x
        let m = min(dB, dT, dL, dR)
        let dir = ceilingMode ? CGVector(dx: 0, dy: 1)
            : m == dB ? CGVector(dx: 0, dy: -1) : m == dT ? CGVector(dx: 0, dy: 1) : m == dL ? CGVector(dx: -1, dy: 0) : CGVector(dx: 1, dy: 0)
        // straight up to the top edge, fast; a bat's gentler pull turns its swoops into arcs
        let pull = (family == .bat ? 1500 : ceilingMode ? 5200 : 2600) * s / 4 * fdt
        vx = vx * pow(0.15, fdt) + dir.dx * pull
        vy = vy * pow(0.15, fdt) + dir.dy * pull
        x += vx * fdt
        y += vy * fdt
        if x <= a.minX || x >= a.maxX || y <= a.minY || y >= a.maxY {
            x = clamp(x, a.minX, a.maxX)
            y = clamp(y, a.minY, a.maxY)
            if ceilingMode { let R = perimeter(a).0; x = clamp(x, R.minX + 4, R.maxX - 4); y = a.maxY }
            p = perimeterP(nearX: x, y: y)
            vx = 0; vy = 0
            placeOnPerimeter()
            if shake >= 6 { shake = 0; setMode(.dizzy); stars(5) } else { setMode(.landing) }
        }
    }

    func watchThink(_ dt: Double) {
        if world.typingNow { begin(.typing); return }
        if !world.videoPlaying && t - world.lastVideoSeen > 4 {
            say(["THAT WAS FUN!"], 2.2)
            setMode(.idle)
            return
        }
        if let f = world.videoFrame {
            let r = world.xRange(margin)
            let seatX = clamp(f.maxX - 60 * s / 4, r.lowerBound, r.upperBound)
            let target = floorTarget(seatX, area().minY)
            if seated && abs(trackDelta(target)) > 140 { seated = false }
            if !seated {
                // hurry over so it doesn't miss the start
                if go(target, speed: abs(trackDelta(target)) > 400 ? 260 : 160, dt, run: true) { seated = true; popT = 0 } else { return }
            }
            if edge == 0 { facing = f.midX > x ? 1 : -1 }
        } else {
            seated = true
        }
        let before = popT.truncatingRemainder(dividingBy: 3.4)
        popT += dt
        let cyc = popT.truncatingRemainder(dividingBy: 3.4)
        if before < 2.05 && cyc >= 2.05 && chance(0.35) {
            spawn(.kernel, localX(cx + (isBird ? 12 : 10)), Double(chh - 12), vx: Double(facing) * rnd(2, 6), vy: -rnd(8, 12), life: 1.6, g: 30)
        }
        if t > nextReact {
            nextReact = t + rnd(40, 100)
            say([["OOH", "HAHA", "WOW!", "NICE", "!!"].randomElement()!], 1.6)
        }
    }

    func listenThink(_ dt: Double) {
        if world.typingNow { begin(.typing); return }
        if world.videoPlaying { begin(.watching); return }
        if !world.musicPlaying { if modeT > 1 { setMode(.idle) }; return }
        if ambientInterrupt(skipMusic: true) { return }
        if t > nextNote {
            nextNote = t + rnd(1.6, 2.6)
            spawn(.note, Double(head.x) + rnd(-5, 5), Double(head.y) - 2, vx: rnd(-2.5, 2.5), vy: -rnd(3.5, 5.5), life: 1.8)
        }
    }

    func eatThink(_ dt: Double) {
        guard let f = food, !f.gone else { food = nil; setMode(.idle); return }
        if world.gravity && !wallMode {
            if f.held || !f.onGround {
                face(toward: CGPoint(x: f.x, y: f.y), dead: 10)
                if !f.held && !inAir { go(f.x - CGFloat(facing) * 12 * s, speed: 120, dt, run: true) }
                return
            }
            if inAir { begin(.eating); return }
            let dir: CGFloat = f.x >= x ? 1 : -1
            let standX = f.x - dir * 12 * s
            if abs(standX - x) > 3 && !go(standX, speed: 130, dt, run: true) { return }
            facing = Int(dir)
        } else {
            let m = mouthPoint()
            if hypot(f.x - m.x, f.y - m.y) > 10 * s { return }
        }
        if fullness > 90 && f.bites == 0 {
            f.refusedBy = true
            releaseFood()
            refuseFacing = facing
            setMode(.refusing)
            say(["I'M FULL!"], 2)
            return
        }
        guard t > nextPeck else { return }
        nextPeck = t + 0.6
        peckStart = t
        f.bites += 1
        world.synth.play("chomp")
        for _ in 0..<3 {
            spawn(.crumb, localX(cx + 12) + rnd(-2, 2), Double(chh - 5), vx: rnd(-4, 4), vy: -rnd(4, 9), life: 1.2, g: 30)
        }
        if f.bites >= 3 {
            f.close()
            food = nil
            fullness = min(100, fullness + f.value)
            let favorite = species.favorites.contains(f.kind)
            happiness = min(100, happiness + (favorite ? 12 : 6))
            hearts(favorite ? 6 : 4)
            say([favorite ? "MY FAVORITE!" : "YUM!"], 1.8)
            world.synth.play(family == .cat ? "purr" : "chirp")
            setMode(.idle)
            act = family == .cat ? .groom : .stand; actT = 0; actDur = 2.5
        }
    }

    func ballThink(_ dt: Double) {
        guard let b = world.items.first(where: { $0.isBall && !$0.gone }) else { setMode(.idle); return }
        if world.typingNow { begin(.typing); return }
        if world.videoPlaying { begin(.watching); return }
        if kicks >= 8 || t - b.born > 50 {
            b.close()
            world.synth.play("poof")
            say(["PHEW!"], 1.5)
            begin(.tired)
            return
        }
        if b.held { face(toward: CGPoint(x: b.x, y: b.y), dead: 10); return }
        if world.gravity && !wallMode && !inAir {
            let dir: CGFloat = b.x >= x ? 1 : -1
            let kickX = b.x - dir * 9 * s
            if abs(kickX - x) > 3 { go(kickX, speed: 150, dt, run: true) }
            facing = Int(dir)
            let low = b.y - world.floorY(b.x, b.y) < 10 * s
            if low && abs(b.x - (x + dir * 9 * s)) < 6 * s && t > nextKick { kick(b, CGVector(dx: dir, dy: 1)) }
        } else {
            if inAir {
                flyTo(CGPoint(x: b.x - CGFloat(facing) * 10 * s, y: b.y), speed: 160, dt)
            } else {
                go(perimeterP(nearX: b.x, y: b.y), speed: 150, dt, run: true)
            }
            let m = mouthPoint(), c = centerPoint()
            if hypot(b.x - m.x, b.y - m.y) < 10 * s && t > nextKick {
                let dx = b.x - c.x, dy = b.y - c.y, d = max(1, hypot(dx, dy))
                kick(b, CGVector(dx: dx / d, dy: dy / d))
            }
        }
    }

    func kick(_ b: Item, _ dir: CGVector) {
        nextKick = t + 0.7
        kickUntil = t + 0.25
        kicks += 1
        let sp = CGFloat(rnd(330, 560)) * s / 4
        b.vx = dir.dx * sp
        b.vy = world.gravity ? CGFloat(rnd(280, 540)) * s / 4 : dir.dy * sp
        world.synth.play("kick")
        happiness = min(100, happiness + 2)
        if chance(0.3) { say([species.vocal.word + "!"], 0.8) }
    }

    func butterflyThink(_ dt: Double) {
        if world.typingNow { begin(.typing); return }
        if world.videoPlaying { begin(.watching); return }
        guard let b = world.items.first(where: { $0.kind == .butterfly && !$0.gone }), !b.leaving else {
            say(["BYE BYE!"], 1.5)
            setMode(.idle)
            return
        }
        if inAir {
            flyTo(CGPoint(x: b.x - CGFloat(facing) * 12 * s, y: b.y - 8 * s), speed: 120, dt)
        } else {
            go(floorTarget(b.x, b.y), speed: 120, dt, run: true)
            if edge == 0 && abs(b.x - x) < 40 * s / 4 && b.y - y < 110 * s / 4 && hopY == 0 && chance(dt * 2.5) {
                hopV = 360 * s / 4
            }
        }
    }

    func angryThink(_ dt: Double) {
        let m = NSEvent.mouseLocation
        if family == .cat {
            if modeT > 1.3 { go(floorTarget(x + (x > m.x ? 1 : -1) * 300, y), speed: 200, dt, run: true) }
            if modeT > 3.0 { say(["HMPH."], 1.5); setMode(.idle) }
        } else {
            if inAir { flyTo(CGPoint(x: m.x, y: m.y - 20), speed: 190, dt) }
            else { go(floorTarget(m.x, m.y), speed: 190, dt, run: true) }
            if modeT > 3.6 { say(["HMPH."], 1.5); setMode(.idle) }
        }
    }

    func huntThink(_ dt: Double) {
        if world.typingNow || world.videoPlaying { setMode(.idle); return }
        let m = NSEvent.mouseLocation
        huntT += dt
        switch huntPhase {
        case 0:
            face(toward: m, dead: 20)
            let tx = m.x - CGFloat(facing) * 80 * s / 4
            if go(tx, speed: 30, dt) || huntT > 5 { huntPhase = 1; huntT = 0 }
            if abs(m.x - x) > 650 || m.y - y > 300 { spawn(.question, Double(head.x), Double(head.y) - 3, vy: -2, life: 1); setMode(.idle) }
        case 1:
            face(toward: m, dead: 20)
            if huntT > 1.3 {
                huntPhase = 2; huntT = 0
                hopV = 380 * s / 4
                leapV = CGFloat(facing) * max(120, min(320, abs(m.x - x) * 1.6)) * s / 4
            }
        case 2:
            if hopY == 0 && huntT > 0.15 {
                huntPhase = 3; huntT = 0
                let mp = mouthPoint()
                if hypot(m.x - mp.x, m.y - mp.y) < 70 {
                    say(["GOTCHA!"], 1.2)
                    hearts(2)
                    happiness = min(100, happiness + 3)
                } else {
                    spawn(.question, Double(head.x), Double(head.y) - 3, vy: -2, life: 1)
                }
            }
        default:
            if huntT > 1.0 { setMode(.idle); act = .sit; actT = 0; actDur = rnd(2, 4) }
        }
    }

    // MARK: Physics

    func physics(_ dt: Double) {
        let fdt = CGFloat(dt)
        if hopV != 0 || hopY > 0 {
            hopV -= 1500 * fdt * s / 4
            hopY += hopV * fdt
            if hopY <= 0 {
                hopY = 0; hopV = 0; leapV = 0
            } else if leapV != 0 {
                if wallMode { p += leapV * fdt } else { x += leapV * fdt }
            }
        }
        if mode == .held || mode == .glide || mode == .drift || inAir { return }
        if wallMode { placeOnPerimeter(); return }
        edge = 0
        let r = world.xRange(margin)
        x = clamp(x, r.lowerBound, r.upperBound)
        let fl = world.floorY(x, y)
        if y > fl + 2 { startFalling() } else { y = fl }
    }

    // MARK: Particles

    func spawn(_ k: PKind, _ px: Double, _ py: Double, vx: Double = 0, vy: Double = 0, life: Double = 1.2, g: Double = 0, size: Int = 0) {
        particles.append(Particle(kind: k, x: px, y: py, vx: vx, vy: vy, life: life, gravity: g, size: size))
        if particles.count > 40 { particles.removeFirst() }
    }

    func spawnDrop() {
        spawn(.drop, Double(head.x) + rnd(-4, 4), Double(head.y) - 6, vx: rnd(-1, 1), vy: -rnd(2, 4), life: 1.2)
    }

    func spawnBang() {
        spawn(.bang, Double(head.x) + 1, Double(head.y) - 3, vy: -3, life: 0.9)
    }

    func spawnZ() {
        let back = -Double(facing)
        spawn(.z, Double(head.x) + back * 2, Double(head.y) - 2, vx: back * 1.6, vy: -3.2, life: 2.6, size: chance(0.5) ? 1 : 0)
    }

    func hearts(_ n: Int) {
        for _ in 0..<n {
            spawn(.heart, Double(head.x) + rnd(-4, 4), Double(head.y) - 2 - rnd(0, 3), vx: rnd(-1.5, 1.5), vy: rnd(-6, -3.5), life: rnd(1.0, 1.6))
        }
    }

    func stars(_ n: Int) {
        for _ in 0..<n {
            spawn(.star, Double(head.x) + rnd(-3, 3), Double(head.y) - 2, vx: rnd(-9, 9), vy: rnd(-11, -4), life: rnd(0.6, 1.1), g: 18)
        }
    }

    func updateParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        let floorRow = Double(chh - 2)
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].vy += particles[i].gravity * dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            if particles[i].kind == .z || particles[i].kind == .note { particles[i].x += sin(particles[i].life * 4) * 0.05 }
            if particles[i].y > floorRow {
                particles[i].y = floorRow
                particles[i].vy = 0
                particles[i].vx *= 0.5
            }
        }
        particles.removeAll { $0.life <= 0 || $0.y < -6 }
    }

    // MARK: Things people do

    func celebrate(_ text: String) {
        celebrateText = text
        celebrateUntil = t + 2.4
        stars(8)
        world.synth.play("chime")
        happiness = min(100, happiness + 3)
    }

    func petted() {
        happiness = min(100, happiness + 6)
        blushUntil = t + 2.5
        hearts(3)
        world.synth.play(family == .cat ? "purr" : "chirp")
        if family == .cat && chance(0.6) { say(["PRRR"], 1.4) }
        switch mode {
        case .idle, .walk, .beg, .vocal:
            setMode(.petted)
            if family != .cat && chance(0.4) { say(["♥"], 1.5) }
        default:
            break
        }
    }

    func admire() {
        hearts(4)
        say([["CUTE!", "FANCY!", "SO STYLISH", "♥ ♥ ♥"].randomElement()!], 1.6)
        world.synth.play("chirp")
        if mode == .idle || mode == .walk { setMode(.petted) }
    }

    func transformed() {
        for _ in 0..<6 { spawn(.puff, Double(cx) + rnd(-10, 10), Double(chh - 10) - rnd(0, 14), vx: rnd(-4, 4), vy: rnd(-4, 0), life: 0.7) }
        stars(6)
        say(["TA-DA!"], 1.6)
        world.synth.play("poof")
        if inAir && !isBird { inAir = false; startFalling() }
        if !inAir && isBird && flyMode { takeOff() }
        if wallMode { p = perimeterP(nearX: x, y: y) }
        if isBird && edge != 0 { edge = 0; startFalling() }
    }

    /// Follows the cursor around for a minute.
    func comeHere() {
        world.lastPlay = t
        followUntil = t + 60
        forcedNap = false
        if isAsleep { setMode(.waking) }
        else if !inAir && (mode == .idle || mode == .listening || mode == .agenda) { setMode(.walk) }
        say(["COMING!"], 1.2)
    }

    /// Steers toward the cursor, stopping a little to the side of it so it never sits under the pointer and blocks clicks.
    func follow() {
        let m = NSEvent.mouseLocation
        let gap = 55 * s / 4
        if inAir {
            guard flyGoal == .wander else { return }
            let side: CGFloat = x < m.x ? -1 : 1
            flyTarget = CGPoint(x: m.x + side * gap * 1.3, y: max(m.y - 20, world.floorY(m.x, m.y) + 10))
            nextFlyPick = t + 1
            return
        }
        guard mode == .idle || mode == .walk else { return }
        let raw = ceilingMode ? floorTarget(m.x, m.y) : wallMode ? perimeterP(nearX: m.x, y: m.y) : m.x
        let d = trackDelta(raw)
        var target = raw - (d > 0 ? 1 : -1) * gap
        if !wallMode { let r = world.xRange(margin); target = clamp(target, r.lowerBound, r.upperBound) }
        let far = abs(trackDelta(target))
        if mode == .idle {
            if far > 40 { walkTarget = target; setMode(.walk) }
            else { face(toward: m) }
        } else {
            walkTarget = target
        }
        running = far > 220
    }

    func toggleNap() {
        if isAsleep {
            forcedNap = false
            setMode(.waking)
        } else {
            forcedNap = true
            begin(.yawning)
        }
    }

    func showAgenda(_ lines: [String], for dur: Double? = nil, prop: Prop = .calendar) {
        agendaProp = prop
        agendaUntil = t + (dur ?? max(5, 1.6 * Double(lines.count)))
        if !lines.isEmpty { say(lines, agendaUntil - t) }
        if inAir { return }
        begin(.agenda)
    }

    /// Water reminder: sits and holds up a glass.
    func offerWater(for dur: Double) { showAgenda([], for: dur, prop: .glass) }

    /// You had some water: it has a sip too, happily.
    func drink() {
        drinkUntil = t + 1.6
        showAgenda([], for: 2.6, prop: .glass)
        hearts(3)
        for i in 0..<3 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.3) { [weak self] in self?.spawnDrop() } }
        happiness = min(100, happiness + 4)
    }

    func putAway() { if mode == .agenda { agendaUntil = t } }

    // MARK: Mouse

    func mouseDown() {
        world.lastPlay = t
        noticedUntil = t + 0.6
        let m = NSEvent.mouseLocation
        downAt = m
        dragging = false
        grab = CGPoint(x: m.x - x, y: m.y - y)
        samples = [(now(), m)]
    }

    func mouseDragged() {
        guard let d = downAt else { return }
        let m = NSEvent.mouseLocation
        // Fullscreen: it stays up on the top edge; dragging only slides it along
        if ceilingMode && !isBird && family != .bat && (edge == 2 || sliding) {
            if !dragging && hypot(m.x - d.x, m.y - d.y) > 9 {
                dragging = true; sliding = true
                releaseFood()
                setMode(.idle); act = .stand; actT = 0; actDur = 2
                world.closePopover()
            }
            guard sliding else { return }
            let top = topSpan()
            p = clamp(perimeterP(nearX: m.x, y: area().maxY), top.lowerBound, top.upperBound)
            placeOnPerimeter()
            place()
            return
        }
        if !dragging && hypot(m.x - d.x, m.y - d.y) > 9 {     // a slightly wobbly click is still a click
            dragging = true
            hopY = 0; hopV = 0; leapV = 0; shake = 0; lastDir = 0
            forcedNap = false
            releaseFood()
            edge = 0
            inAir = false
            umbrella = false
            grab = CGPoint(x: 0, y: (isBird ? 14 : 22) * s)
            setMode(.held)
            world.synth.play(family == .cat ? "mrrp" : (isBird ? "squawk" : "chirp"))
            say([chance(0.5) ? "HEY!" : "WHEE!"], 1.2)
            world.closePopover()
        }
        guard dragging else { return }
        x = m.x - grab.x
        y = m.y - grab.y
        let n = now()
        if let last = samples.last {
            let dx = m.x - last.1.x
            let dir = dx > 6 ? 1 : (dx < -6 ? -1 : 0)
            if dir != 0 && dir != lastDir {
                if lastDir != 0 { shake += 1 }
                lastDir = dir
            }
        }
        samples.append((n, m))
        samples.removeAll { n - $0.0 > 0.12 }
    }

    func mouseUp(clicks count: Int) {
        defer { downAt = nil }
        if sliding { sliding = false; dragging = false; return }
        guard dragging else {
            // Wait a beat before reacting: if a second click comes it's a double-click (the calendar), and the pet
            // mustn't hop or move in between or the second click would miss it.
            let m = NSEvent.mouseLocation, n = now()
            if let last = lastClick, n - last.at < NSEvent.doubleClickInterval, hypot(m.x - last.pt.x, m.y - last.pt.y) < 24 {
                lastClick = nil
                pendingClick?.cancel(); pendingClick = nil
                world.petDoubleClicked()
            } else {
                lastClick = (n, m)
                pendingClick?.cancel()
                let job = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.world.notice != nil { self.world.openNotice(); return }     // the bell is ringing: go there
                    self.clicked(); self.world.petClicked()
                }
                pendingClick = job
                DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.3), execute: job)
            }
            return
        }
        dragging = false
        let n = now()
        let recent = samples.filter { n - $0.0 < 0.1 }
        if let f = recent.first, let l = recent.last, l.0 - f.0 > 0.01 {
            vx = clamp((l.1.x - f.1.x) / CGFloat(l.0 - f.0), -2200, 2200)
            vy = clamp((l.1.y - f.1.y) / CGFloat(l.0 - f.0), -2200, 2200)
        } else {
            vx = 0; vy = 0
        }
        apexY = y
        if isBird {
            inAir = true
            flyGoal = (world.gravity && !world.fullscreenApp) ? .land : .wander
            afterLand = nil
            setMode(.fly)
        } else if !wallMode {
            umbrella = false
            setMode(.glide)
        } else {
            setMode(.drift)
        }
    }

    func clicked() {
        clicks.append(t)
        clicks.removeAll { t - $0 > 2.5 }
        switch mode {
        case .sleeping, .yawning, .catnap:
            forcedNap = false
            setMode(.waking)
            return
        case .held:
            return
        case .glide, .drift:
            say(["WHEE!"], 0.9); return
        case .eating:
            hearts(1); say(["NOM!"], 0.8); return
        case .landing, .dizzy, .waking:
            spawnBang(); world.synth.play(species.vocal.sound); return
        default:
            break
        }
        if inAir {                                   // flying: answer without dropping out of the sky
            say([species.vocal.word + "!"], 0.9)
            world.synth.play(species.vocal.sound)
            return
        }
        if clicks.count >= 5 {
            clicks.removeAll()
            setMode(.angry)
            let hiss = family == .cat
            say([hiss ? "HISS!" : "\(species.vocal.word)!!"], 1.4)
            world.synth.play(hiss ? "hiss" : (isBird ? "honk2" : "woof"))
            happiness = max(0, happiness - 3)
            return
        }
        setMode(.vocal)
        modeT = 0
        say([species.vocal.word + "!"], 0.9)
        world.synth.play(species.vocal.sound)
        happiness = min(100, happiness + 1)
    }

    /// Lets clicks through everywhere except the pet itself; detects petting (stroking with the cursor).
    func updateMouse(_ dt: Double) {
        let m = NSEvent.mouseLocation
        if hypot(m.x - lastMouse.x, m.y - lastMouse.y) > 1.5 { cursorMovedAt = t }
        defer { lastMouse = m }
        updateHover()
        petCooldown -= dt
        if mouseInside && !dragging && NSEvent.pressedMouseButtons == 0 {
            strokeDist += hypot(m.x - lastMouse.x, m.y - lastMouse.y)
            strokeIdle = 0
            if strokeDist > 280 * s / 4 && petCooldown <= 0 {
                strokeDist = 0
                petCooldown = 1.5
                petted()
            }
        } else {
            strokeIdle += dt
            if strokeIdle > 0.7 { strokeDist = 0 }
        }
    }

    /// Catch clicks only over the pet itself; everywhere else they go to the app underneath.
    func updateHover() {
        guard panel != nil, let r = hitRectScreen() else { return }
        // a little extra margin once inside, so the edge never flickers
        let inside = r.insetBy(dx: mouseInside ? -8 : -2, dy: mouseInside ? -8 : -2).contains(NSEvent.mouseLocation)
        mouseInside = inside
        let ignore = !(inside || dragging || downAt != nil || now() - (lastClick?.at ?? -10) < 0.7)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    // MARK: Drawing

    func makePose() -> Pose {
        var p = Pose()
        let blink = t < blinkUntil
        let flapFast = Int(t / 0.09) % 2 == 0
        let wag = family == .dog && (mode == .petted || mode == .vocal || mode == .ball || mode == .eating || mode == .landing
                                     || (mode == .idle && happiness > 70 && (act == .stand || act == .sit)))
        p.outfit = outfit
        p.phones = world.musicPlaying
        p.eyes = blink ? .closed : .open
        p.tail = t * (wag ? 14 : 1.6)
        p.bob = isBird ? (t.truncatingRemainder(dividingBy: 1.8) < 0.9 ? 0 : 1) : 0
        if family == .dog && !blink && (wag || mode == .walk) { p.mouth = .tongue }
        if moving {
            p.stance = .walk
            p.phase = walkT * (running ? 16 : 9)
            if isBird { p.bob = sin(p.phase * 2) > 0.3 ? 1 : 0; p.headDX = sin(p.phase * 2) > 0 ? 1 : 0 }
        }
        if inAir {
            p.stance = .fly
            p.arm = [Arm.raised, .rest, .down, .rest][Int(flapT / 0.08) % 4]
            p.bob = 0; p.headDX = 0
        }
        switch mode {
        case .idle:
            if !inAir { idlePose(&p) }
        case .walk, .fly:
            break
        case .typing:
            let tapping = t < world.tapUntil
            p.stance = .sit; p.prop = .laptop; p.bob = 0; p.tailUp = false
            p.arm = tapping ? .tap : .forward
            switch species {
            case .goose: p.headDX = 2; p.headDY = 7 + (tapping ? 1 : 0)
            default: p.headDY = tapping ? 1 : 0; if family == .dog { p.mouth = .closed }
            }
            if t < celebrateUntil {
                p.arm = isBird ? (flapFast ? .raised : .rest) : .raised
                p.eyes = .happy; p.mouth = .open; p.headDY = 0
            }
        case .watching:
            if moving { break }
            p.stance = .sit; p.prop = .popcorn; p.bob = 0; p.tailUp = false
            p.arm = isBird ? .forward : .rest
            if family == .dog { p.mouth = .closed }
            let cyc = popT.truncatingRemainder(dividingBy: 3.4)
            if cyc < 2.05 {
                p.eyes = blink ? .closed : .up
                if species == .goose { p.headDY = -1 }
                if cyc < 1.0 { p.mouth = Int(cyc * 8) % 2 == 0 ? .open : .closed }
            } else if cyc < 2.45 {
                switch species {
                case .goose: p.headDX = 4; p.headDY = 13; p.eyes = .closed
                default: p.arm = .scoop
                }
            } else {
                p.eyes = .up
                if !isBird { p.arm = .toMouth } else if species == .goose { p.headDY = -1 }
                p.mouth = Int(cyc * 8) % 2 == 0 ? .open : .closed
            }
        case .listening:
            if moving { break }
            let beat = Int(t / 0.42) % 2
            let bar = Int(t / 1.68) % 4
            p.eyes = bar % 2 == 0 ? .happy : (blink ? .closed : .open)
            if isBird {
                p.stance = bar == 1 ? .walk : .stand
                p.phase = beat == 0 ? 1.2 : 4.3
                p.bob = beat; p.headDX = beat
                if bar == 3 { p.arm = flapFast ? .raised : .rest }
            } else {
                p.stance = .sit; p.tailUp = true; p.tail = t * 4
                p.headDY = beat
                if bar == 3 { p.arm = beat == 0 ? .raised : .rest }
            }
        case .agenda:
            p.stance = .sit; p.prop = agendaProp; p.arm = isBird ? .forward : .hold; p.tailUp = false; p.bob = 0
            if family == .dog { p.mouth = .closed }
            if agendaProp == .glass && t < drinkUntil { p.arm = isBird ? .forward : .toMouth; p.eyes = .happy; p.headDY = isBird ? 1 : 0 }
            else if agendaProp == .glass { p.eyes = .open; p.tail = t * 3; p.tailUp = true }
        case .yawning:
            if isBird {
                if modeT < 1.2 { p.mouth = .open; p.eyes = .closed; p.headDY = -2; p.arm = .raised }
                else { p.stance = .sit; p.bob = 0; p.eyes = Int(modeT * 5) % 2 == 0 ? .closed : .half; birdSleepHead(&p, k: min(1, (modeT - 1.2) / 1.2)) }
            } else {
                if modeT < 1.2 { p.stance = .sit; p.mouth = .open; p.eyes = .closed; p.tailUp = false }
                else if modeT < 2.0 { p.stance = .lie; p.eyes = Int(modeT * 5) % 2 == 0 ? .closed : .half }
                else { p.stance = .curl; p.eyes = .closed }
            }
            p.nightcap = world.isNight && modeT > 2.0
        case .sleeping, .catnap:
            p.eyes = .closed
            p.bob = t.truncatingRemainder(dividingBy: 3.2) < 1.6 ? 0 : 1
            if isBird { p.stance = .sit; birdSleepHead(&p, k: 1) } else { p.stance = .curl }
            p.nightcap = mode == .sleeping && world.isNight
            p.blush = t < blushUntil
        case .waking:
            if isBird {
                if modeT < 0.35 { p.stance = .sit; birdSleepHead(&p, k: 1); p.bob = -1; p.eyes = modeT > 0.15 ? .wide : .closed; p.nightcap = world.isNight }
                else if modeT < 1.0 { p.stance = .sit; p.eyes = .wide; p.bob = 0; p.arm = flapFast ? .raised : .rest }
                else if modeT < 1.8 { p.headDY = -3; p.mouth = .open; p.eyes = .closed; p.arm = .raised; p.bob = 0 }
                else { p.eyes = (modeT > 1.9 && modeT < 2.0) || (modeT > 2.15 && modeT < 2.25) ? .closed : .open }
            } else {
                if modeT < 0.35 { p.stance = .curl; p.bob = -1; p.eyes = modeT > 0.15 ? .wide : .closed; p.nightcap = world.isNight }
                else if modeT < 1.0 { p.stance = .sit; p.eyes = .wide; p.tailUp = true }
                else if modeT < 1.8 { p.stance = .stretch; p.eyes = .closed; p.mouth = .open }
                else { p.eyes = (modeT > 1.9 && modeT < 2.0) || (modeT > 2.15 && modeT < 2.25) ? .closed : .open }
            }
        case .eating:
            if moving { p.eyes = .wide; break }
            if let f = food, world.gravity, !wallMode, !f.onGround || f.held { p.eyes = .up; if species == .goose { p.headDY = -2 }; break }
            let k = t - peckStart
            let chew: Mouth = k < 0.5 && Int(k * 12) % 2 == 0 ? .open : .closed
            switch species {
            case .goose:
                if k < 0.22 { p.headDX = 4; p.headDY = 24; p.eyes = .closed } else { p.headDX = 3; p.headDY = 12; p.eyes = .happy; p.mouth = chew }
            default:
                p.stance = .eat; p.eyes = .happy; p.headDY = k < 0.22 ? 1 : 0; p.mouth = chew
            }
        case .refusing:
            p.eyes = .closed
            if !isBird { p.stance = .sit; p.tailUp = false; p.mouth = .closed } else if species == .goose { p.headDY = -1 }
        case .ball:
            if t < kickUntil {
                if !isBird { p.stance = .leap; p.eyes = .wide }
                else if !inAir { p.headDX = 3; p.headDY = species == .goose ? 5 : 2; p.mouth = .open; p.arm = .raised; p.eyes = .wide }
            } else if !moving {
                p.eyes = .wide
            }
        case .tired:
            p.stance = .sit; p.eyes = .closed; p.bob = 0; p.tailUp = false
            p.mouth = Int(t / 0.22) % 2 == 0 ? (family == .dog ? .tongue : .open) : .closed
        case .butterfly:
            p.eyes = .up
            if !isBird { p.tail = t * 4 } else if !inAir { if species == .goose { p.headDY = -3 }; if hopY > 0 { p.arm = flapFast ? .raised : .rest } }
        case .vocal:
            if isBird {
                p.mouth = Int(modeT / 0.15) % 2 == 0 ? .open : .closed
                if !inAir { p.arm = .raised; p.headDX = species == .goose ? 2 : 1; p.eyes = .wide }
            } else {
                p.stance = moving ? .walk : .sit; p.mouth = modeT < 0.6 ? .open : .closed; p.eyes = .happy; p.tailUp = true
            }
        case .angry:
            if !isBird {
                if modeT < 1.3 { p.stance = .crouch; p.earsFlat = true; p.mouth = .open; p.eyes = .angry }
                else { p.earsFlat = true; p.eyes = .angry; p.tailUp = false; p.mouth = .closed }
            } else {
                p.eyes = .angry; p.mouth = Int(t / 0.1) % 2 == 0 ? .open : .closed
                if !inAir { p.headDX = species == .goose ? 6 : 2; p.headDY = species == .goose ? 8 : 2; p.arm = flapFast ? .raised : .rest }
            }
        case .petted:
            p.eyes = .happy; p.blush = true
            if isBird { p.headDY = 1; p.bob = Int(t / 0.2) % 2; p.arm = Int(t / 0.25) % 2 == 0 ? .raised : .rest }
            else { p.stance = family == .dog ? .upright : .sit; p.tailUp = true; p.headDX = Int(t / 0.3) % 2 }
        case .beg:
            p.eyes = .sad
            if isBird { if species == .goose { p.headDY = 3; p.headDX = 1 }; if fullness < 10 { p.stance = .sit; p.bob = 0 } }
            else { p.stance = family == .dog ? .upright : .sit; p.tailUp = false; p.mouth = modeT < 0.8 ? .open : .closed }
        case .held:
            p.stance = isBird ? .held : .held; p.bob = 0; p.headDX = 0
            p.phase = t * 6
            if isBird {
                p.arm = flapFast ? .raised : .rest; p.eyes = .wide
                p.mouth = Int(t / 0.4) % 3 == 0 ? .open : .closed
            } else {
                p.eyes = modeT < 0.6 ? .wide : (Int(t / 1.5) % 3 == 0 ? .closed : .happy)
                p.mouth = modeT < 0.6 ? .open : (family == .dog ? .tongue : .closed)
            }
        case .glide:
            p.stance = umbrella ? .umbrella : .held; p.bob = 0
            p.phase = t * (umbrella ? 2 : 10)
            p.eyes = umbrella ? .happy : .wide
            if family == .dog && umbrella { p.mouth = .tongue }
        case .drift:
            p.stance = .leap; p.bob = 0
            p.eyes = .wide
        case .landing:
            p.stance = .squash; p.eyes = .closed; p.bob = 0
        case .dizzy:
            p.eyes = .dizzy; p.bob = 0; p.headDX = Int(t / 0.25) % 3 - 1
            if !isBird { p.stance = .sit; p.tailUp = false; p.headDX = 0 }
        case .zoomies:
            p.eyes = .wide; p.tailUp = false
            if family == .dog { p.mouth = .tongue }
        case .hunt:
            switch huntPhase {
            case 0: p.stance = .crouch; p.eyes = .wide
            case 1: p.stance = .crouch; p.eyes = .wide; p.wiggle = Int(t / 0.08) % 2 == 0 ? 1 : -1
            case 2: p.stance = hopY > 0 ? .leap : .crouch; p.eyes = .wide
            default: p.stance = .sit; p.tailUp = true
            }
        }
        if (mode == .idle || mode == .walk) && fullness < 15 && p.eyes == .open { p.eyes = .sad }
        return p
    }

    /// Birds tuck their head down to sleep (k = 0...1).
    private func birdSleepHead(_ p: inout Pose, k: Double) {
        if species == .goose {
            p.headDX = Int((-1 * k).rounded()); p.headDY = 3 + Int(9 * k)
        } else {
            p.headDX = Int((-2 * k).rounded()); p.headDY = Int(3 * k)
        }
    }

    func idlePose(_ p: inout Pose) {
        let blink = t < blinkUntil
        switch family {
        case .bird:
            switch act {
            case .sit: p.stance = .sit; p.bob = 0
            case .preen:
                if species == .goose { p.headDX = -2; p.headDY = 11 + Int(t / 0.18) % 2 } else { p.headDX = -3; p.headDY = 2 + Int(t / 0.18) % 2 }
                p.eyes = .closed
            case .peck:
                let down = actT.truncatingRemainder(dividingBy: 0.7) < 0.2
                if species == .goose { p.headDX = 4; p.headDY = down ? 24 : 12 } else { p.headDX = 3; p.headDY = down ? 9 : 4 }
            case .vocal: p.mouth = Int(actT / 0.15) % 2 == 0 ? .open : .closed; p.arm = .raised; p.headDX = 1; p.headDY = -1
            case .flap: p.arm = Int(actT / 0.12) % 2 == 0 ? .raised : .rest
            case .yawn: p.mouth = actT > 0.2 && actT < 1.1 ? .open : .closed; p.eyes = .closed; p.headDY = -2
            case .gaze: p.eyes = blink ? .closed : .up; if species == .goose { p.headDY = -2 }
            case .hop: if hopY > 0 { p.arm = Int(t / 0.08) % 2 == 0 ? .raised : .rest; p.stance = .held; p.phase = t * 6 }
            default: break
            }
        default:
            switch act {
            case .sit: p.stance = .sit; p.tailUp = false
            case .lie:
                p.stance = .lie
                p.eyes = actT.truncatingRemainder(dividingBy: 4) < 1.2 ? .closed : (blink ? .closed : .half)   // the slow blink
                if family == .dog { p.mouth = .closed }
            case .groom:
                p.stance = .sit; p.tailUp = false; p.eyes = .closed
                let k = Int(actT / 0.35) % 2
                p.arm = k == 0 ? .lick : .toMouth
                p.mouth = k == 0 ? .tongue : .closed
            case .stretch:
                p.stance = .stretch; p.eyes = .closed
                p.mouth = actT > 0.6 && actT < 1.6 ? .open : .closed
            case .yawn: p.stance = .sit; p.mouth = actT > 0.2 && actT < 1.1 ? .open : .closed; p.eyes = .closed; p.tailUp = false
            case .gaze: p.stance = .sit; p.eyes = blink ? .closed : .up; p.tailUp = false
            case .vocal: p.stance = .sit; p.mouth = actT < 0.6 ? .open : .closed; p.tailUp = true
            case .hop: if hopY > 0 { p.stance = .leap; p.eyes = .happy }
            case .beg: p.stance = .upright
            default: break
            }
        }
    }

    func renderCanvas() {
        var pose = makePose()
        // a quick in-between frame when sitting down or getting up, so it doesn't snap
        let low: Set<Stance> = [.sit, .lie, .curl, .upright], high: Set<Stance> = [.stand, .walk, .eat]
        if pose.stance != lastStance {
            if (low.contains(pose.stance) && high.contains(lastStance)) || (high.contains(pose.stance) && low.contains(lastStance)) {
                transitionUntil = t + 0.14
            }
            lastStance = pose.stance
        }
        if t < transitionUntil && !isBird && family != .bat { pose.stance = .crouch }
        if family == .bat { pose.phase = t * 13 }            // wing beats
        var c = Canvas(cw, chh)
        let a = drawPet(&c, species, pose, cx: cx)
        if facing < 0 { c.mirror(around: cx) }
        head = (facing < 0 ? 2 * cx - a.headX : a.headX, a.headTop)
        hitCells = c.bounds()
        if mode == .dizzy {
            for i in 0..<3 {
                let ang = t * 5 + Double(i) * 2.1
                c.sprite(head.x + Int((cos(ang) * 5).rounded()) - 1, head.y - 4 + Int((sin(ang) * 1.5).rounded()), SPR_STAR, ["X": .star])
            }
        }
        for pt in particles where !(pt.life < 0.25 && Int(pt.life * 30) % 2 == 0) { drawParticle(&c, pt) }
        c.outline()
        canvas = c
    }

    func currentBubble() -> [String]? {
        if t < celebrateUntil { return [celebrateText] }
        if t < bubbleUntil && !bubbleLines.isEmpty { return bubbleLines }
        return nil
    }

    func updateBubble() {
        // no speech while a menu or card is up: they'd sit on top of each other
        guard !world.hidden, !world.menuOpen, let lines = currentBubble(), !lines.isEmpty else { bubble.hide(); return }
        let (tip, below) = bubbleTip()
        bubble.show(lines, tip: tip, below: below, px: max(2, (s * 0.5).rounded()))
    }

    /// Where speech and cards come from, in screen space so they're never sideways or inside the pet:
    /// just above it, or just below it when it hangs from the top (or a wall leaves no room above).
    func bubbleTip() -> (CGPoint, Bool) {
        let h = cellToScreen(Double(head.x) + 0.5, Double(head.y))
        guard let r = hitRectScreen() else { return (h, false) }
        let x = clamp(h.x, r.minX + 6, max(r.minX + 6, r.maxX - 6))
        let roomAbove = area().maxY - r.maxY > 70
        if edge == 2 || (edge != 0 && !roomAbove) { return (CGPoint(x: x, y: r.minY - 2), true) }
        return (CGPoint(x: x, y: r.maxY + 2), false)
    }

    /// The window's picture at 2 pixels per cell (half-cell offsets stay exact), top row first.
    func spriteImage() -> CGImage? {
        let n = Int((side / s).rounded()) * 2
        // drawn straight in the screen's color space and native pixel order, so macOS doesn't convert every frame
        let space = panel?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(n))
        ctx.scaleBy(x: 2 / s, y: -2 / s)
        ctx.setShouldAntialias(false)
        draw(ctx)
        return ctx.makeImage()
    }

    func draw(_ ctx: CGContext) {
        let av = anchorView()
        ctx.saveGState()
        ctx.translateBy(x: av.x, y: av.y)
        ctx.rotate(by: edgeAngle[edge])
        ctx.translateBy(x: -(CGFloat(cx) + 0.5) * s, y: -CGFloat(chh - 1) * s)
        canvas.draw(ctx, 0, 0, s, palette)
        ctx.restoreGState()
    }

    /// A still portrait for the control panel.
    func portrait() -> NSImage {
        var c = Canvas(cw, chh)
        var pose = Pose()
        pose.outfit = outfit
        if !isBird { pose.stance = .sit; pose.tailUp = false }
        if family == .dog { pose.mouth = .tongue }
        drawPet(&c, species, pose, cx: cx)
        c.outline()
        return c.trimmed(1).image(palette, scale: 6)
    }
}
