// The pets themselves: species, coats, and how each one is drawn in every pose.
// Style: slim silhouettes, flat colors and crisp outlines (like the original cats).

import Cocoa

// MARK: - Poses

enum Stance {
    case stand, walk, sit, lie, curl, stretch, crouch, leap, upright, eat, squash,
         fly,                                    // birds in the air
         umbrella, held                          // seen from the front (gliding down, held up)
}
enum Eyes { case open, closed, happy, wide, angry, dizzy, sad, up, half }
enum Mouth { case closed, open, tongue }
/// Wing (birds) or front paw (four-legged pets).
enum Arm { case rest, raised, forward, tap, down, scoop, toMouth, lick, hold }
enum Prop { case none, laptop, popcorn, calendar }

enum Hat: String, Codable, CaseIterable { case none, bow, flower, crown, topHat, party, beanie, witch, cowboy }
enum Glasses: String, Codable, CaseIterable { case none, shades, hearts, round }
enum Neckwear: String, Codable, CaseIterable { case none, scarf, bowtie, bell, bandana }

struct Outfit: Codable, Equatable {
    var hat = Hat.none
    var glasses = Glasses.none
    var neck = Neckwear.none
}

struct Pose {
    var stance = Stance.stand
    var phase = 0.0          // walk / flap cycle
    var bob = 0
    var headDX = 0
    var headDY = 0
    var eyes = Eyes.open
    var mouth = Mouth.closed
    var arm = Arm.rest
    var tail = 0.0           // tail sway phase
    var tailUp = true
    var earsFlat = false
    var prop = Prop.none
    var blush = false
    var nightcap = false
    var phones = false
    var wiggle = 0
    var outfit = Outfit()
}

/// Where the head ended up, so outfits, bubbles and particles can follow it.
struct Anchors {
    var headX: Int
    var headTop: Int
    var headW: Int
    var eyes: [(Int, Int)]     // top-left cell of each eye
    var profile: Bool          // side-view bird head: one eye, beak to the right
    var neck: (Int, Int)
}

// MARK: - Species

enum Family { case bird, cat, dog, bat }
enum Ears { case cat, flop }
enum Tail { case cat, fluffy, thin }
enum Coat { case tabby, points, tuxedo, calico, spots }

struct QuadSpec {
    var ears: Ears
    var tail: Tail
    var coat: Coat
    var half: Int = 9      // body half-length
    var legH: Int = 4
    var bodyH: Int = 7
}

enum Species: String, CaseIterable, Identifiable, Codable {
    case goose, ginger, siamese, tuxedo, calico, dalmatian, bat
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "duck", "mallard", "whiteDuck": self = .goose
        case "corgi", "collie", "aussie": self = .dalmatian
        case "weasel": self = .ginger
        case "midnight": self = .tuxedo
        case "smokey": self = .siamese
        default: self = Species(rawValue: raw) ?? .goose
        }
    }

    var family: Family {
        switch self {
        case .goose: return .bird
        case .dalmatian: return .dog
        case .bat: return .bat
        default: return .cat
        }
    }
    var isBird: Bool { family == .bird }

    var title: String {
        switch self {
        case .goose: return "Goose"
        case .ginger: return "Ginger cat"
        case .siamese: return "Siamese"
        case .tuxedo: return "Tuxedo cat"
        case .calico: return "Calico"
        case .dalmatian: return "Dalmatian"
        case .bat: return "Bat"
        }
    }

    var defaultName: String {
        switch self {
        case .goose: return "Honk"
        case .ginger: return "Mango"
        case .siamese: return "Mochi"
        case .tuxedo: return "Oreo"
        case .calico: return "Patches"
        case .dalmatian: return "Domino"
        case .bat: return "Luna"
        }
    }

    var vocal: (word: String, sound: String) {
        switch family {
        case .bird: return ("HONK", "honk")
        case .dog: return ("WOOF", "woof")
        case .cat: return ("MEOW", "meow")
        case .bat: return ("SQUEAK", "chirp")
        }
    }

    /// Snacks this pet loves the most.
    var favorites: Set<ItemKind> {
        switch family {
        case .bird: return [.bread, .cookie, .berry]
        case .cat: return [.fish]
        case .dog: return [.bone, .sausage]
        case .bat: return [.cookie, .berry]
        }
    }

    var quad: QuadSpec {
        switch self {
        case .siamese: return QuadSpec(ears: .cat, tail: .fluffy, coat: .points)
        case .tuxedo: return QuadSpec(ears: .cat, tail: .cat, coat: .tuxedo)
        case .calico: return QuadSpec(ears: .cat, tail: .cat, coat: .calico)
        case .dalmatian: return QuadSpec(ears: .flop, tail: .thin, coat: .spots, half: 9, legH: 5, bodyH: 6)
        default: return QuadSpec(ears: .cat, tail: .cat, coat: .tabby)
        }
    }

    var colors: [Col: UInt32] {
        switch self {
        case .goose:
            return [.body: 0xffffff, .bodyShade: 0xdfe3ea, .wing: 0xeef1f5, .wingDark: 0xa9b3c1]
        case .ginger:
            return [.body: 0xffa04a, .bodyShade: 0xe0823a, .mark: 0xdd7a2c, .belly: 0xfff1d8, .nose: 0xff9db4, .inner: 0xff9db4]
        case .siamese:
            return [.body: 0xf6eee2, .bodyShade: 0xe0d4c4, .mark: 0x6f5c58, .belly: 0xfffaf2, .eye: 0x5fa0e6,
                    .nose: 0x5a4846, .inner: 0x8f7a76]
        case .tuxedo:
            return [.body: 0x3f3a4a, .bodyShade: 0x2f2b38, .mark: 0x3f3a4a, .belly: 0xfbf8f3, .eye: 0xf5d35a,
                    .nose: 0xff9db4, .inner: 0xd28c9a, .outline: 0x1c1922]
        case .calico:
            return [.body: 0xffffff, .bodyShade: 0xdfe0e8, .mark: 0xf4a24a, .mark2: 0x3b3645, .belly: 0xffffff]
        case .dalmatian:
            return [.body: 0xffffff, .bodyShade: 0xe6e3ee, .mark: 0x3a3440, .belly: 0xffffff, .nose: 0x3a3440]
        case .bat:
            return [.body: 0x4f4166, .bodyShade: 0x3d3252, .wing: 0x6a5785, .wingDark: 0x392e4e, .belly: 0x6f5f88,
                    .inner: 0xf08aac, .mark: 0x241f2e, .eye: 0x241f2e, .eyeHi: 0xffffff, .nose: 0x241f2e, .outline: 0x18141f]
        }
    }
}

// MARK: - Props

func drawLaptop(_ c: inout Canvas, lx: Int, g: Int) {
    c.thick(lx + 9, g - 2, lx + 11, g - 11, 1, .screen)
    c.thick(lx + 10, g - 1, lx + 12, g - 11, 2, .lapDark)
    c.hline(lx, lx + 10, g, .lapDark)
    c.hline(lx, lx + 9, g - 1, .lapLight)
}

func drawPopcorn(_ c: inout Canvas, bx: Int, g: Int) {
    let bt = g - 7
    let rows: [(Int, Int)] = [(0, 6), (0, 6), (0, 6), (1, 5), (1, 5), (1, 5), (1, 5), (1, 5)]
    for (i, sp) in rows.enumerated() {
        for xx in sp.0...sp.1 { c.set(bx + xx, bt + i, i == 0 || xx % 2 == 0 ? .popRed : .popCream) }
    }
    let corn: [(Int, Int, Col)] = [(0, -1, .popCream), (1, -1, .popYellow), (2, -1, .popCream), (3, -1, .popCream),
                                   (4, -1, .popYellow), (5, -1, .popCream), (6, -1, .popCream), (1, -2, .popCream),
                                   (2, -2, .popYellow), (4, -2, .popCream), (5, -2, .popCream), (3, -3, .popCream)]
    for (dx, dy, col) in corn { c.set(bx + dx, bt + dy, col) }
}

func drawCalendar(_ c: inout Canvas, x: Int, y: Int) {
    c.rect(x, y, 7, 7, .page)
    c.rect(x, y, 7, 2, .pageRed)
    c.set(x + 1, y - 1, .lapDark); c.set(x + 5, y - 1, .lapDark)
    c.hline(x + 1, x + 5, y + 3, .lapLight)
    c.hline(x + 1, x + 4, y + 5, .lapLight)
}

func drawUmbrella(_ c: inout Canvas, ux: Int, top: Int, handleTo: (Int, Int)) {
    c.thick(ux, top + 5, handleTo.0, handleTo.1, 1, .handle)
    c.set(ux, top, .handle)
    let rows: [(Int, Int)] = [(-2, 2), (-4, 4), (-6, 6), (-7, 7)]
    for (i, sp) in rows.enumerated() {
        for x in sp.0...sp.1 { c.set(ux + x, top + 1 + i, ((x + 8) / 3) % 2 == 0 ? .umbA : .umbB) }
    }
    for x in [-7, -6, -5, -1, 0, 1, 5, 6, 7] { c.set(ux + x, top + 5, ((x + 8) / 3) % 2 == 0 ? .umbA : .umbB) }
}

// MARK: - Goose

private func profileEye(_ c: inout Canvas, _ e: Eyes, _ ex: Int, _ ey: Int) {
    switch e {
    case .open, .half: c.set(ex, ey, .eye)
    case .up: c.set(ex + 1, ey - 1, .eye)
    case .closed: c.hline(ex - 1, ex, ey + 1, .eye)
    case .happy: c.set(ex - 1, ey + 1, .eye); c.set(ex, ey, .eye); c.set(ex + 1, ey + 1, .eye)
    case .wide: c.rect(ex, ey, 2, 2, .eye); c.set(ex, ey, .eyeHi)
    case .angry: c.set(ex, ey + 1, .eye); c.set(ex, ey, .eye); c.set(ex - 1, ey - 1, .eye)
    case .sad: c.set(ex, ey + 1, .eye); c.set(ex, ey, .eye); c.set(ex + 1, ey - 1, .eye)
    case .dizzy: for (dx, dy) in [(-1, 0), (1, 0), (0, 1), (-1, 2), (1, 2)] { c.set(ex + dx, ey + dy, .eye) }
    }
}

private func birdWing(_ c: inout Canvas, _ arm: Arm, cx: Int, r0: Int) {
    switch arm {
    case .raised:
        c.region(cx, r0 - 6, [(-11, -10), (-12, -8), (-12, -6), (-11, -4), (-10, -2), (-9, 0), (-8, 1), (-7, 1), (-5, 0)], fill: .wing, edge: .wingDark)
    case .forward, .scoop, .toMouth, .hold:
        c.region(cx, r0 + 3, [(-6, 3), (-7, 8), (-7, 10), (-6, 9), (-4, 5)], fill: .wing, edge: .wingDark)
    case .tap:
        c.region(cx, r0 + 3, [(-6, 3), (-7, 7), (-7, 8), (-6, 9), (-4, 10), (7, 11), (9, 11)], fill: .wing, edge: .wingDark)
    case .down:
        c.region(cx, r0 + 5, [(-6, 2), (-7, 2), (-7, 1), (-7, 0), (-6, -1), (-6, -2), (-5, -3), (-5, -4)], fill: .wing, edge: .wingDark)
    default:
        c.region(cx, r0 + 2, [(-6, 0), (-8, 2), (-9, 3), (-9, 3), (-8, 2), (-6, 0)], fill: .wing, edge: .wingDark)
    }
}

/// Long-necked goose, side view facing right.
private func drawGoose(_ c: inout Canvas, _ p: Pose, cx: Int) -> Anchors {
    let g = c.h - 2
    let st = p.stance
    let sitting = st == .sit || st == .lie || st == .curl
    let airborne = st == .fly || st == .held || st == .umbrella || st == .leap
    let legLen = st == .squash ? 1 : 3
    let bb = sitting ? g : (airborne ? g - 5 : g - legLen - 1)
    let r0 = bb - 10 + p.bob

    if st == .fly {
        c.hline(cx - 7, cx - 5, bb + 1, .feet)
        c.hline(cx - 4, cx - 2, bb + 1, .feet)
    } else if !sitting {
        for (i, lx) in [cx - 3, cx + 1].enumerated() {
            if airborne {
                let len = (Int(p.phase) % 2 == i) ? 4 : 3
                for yy in (bb + 1)...(bb + len) { c.set(lx, yy, .feet) }
                c.set(lx + 1, bb + len, .feet)
            } else {
                let sv = st == .walk ? sin(p.phase + (i == 0 ? 0 : .pi)) : 0
                let lifted = sv > 0.5
                let fx = lx + Int((sv * 1.2).rounded())
                let footY = lifted ? g - 1 : g
                if footY - 1 >= bb + 1 { for yy in (bb + 1)...(footY - 1) { c.set(lx, yy, .feet) } }
                c.hline(fx, fx + 2, footY, .feet)
            }
        }
    }

    let w = st == .squash ? 1 : 0
    c.hline(cx - 12, cx - 11, r0 - 1, .body)
    c.hline(cx - 12 - w, cx - 6, r0, .body)
    c.hline(cx - 11 - w, cx - 8, r0 + 1, .body)
    let body: [(Int, Int)] = [(-5, 3), (-7, 5), (-8, 6), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-8, 6), (-6, 4)]
    for (i, sp) in body.enumerated() { c.hline(cx + sp.0 - w, cx + sp.1 + w, r0 + i, i >= 9 ? .bodyShade : .body) }

    if p.prop == .laptop { drawLaptop(&c, lx: cx + 9, g: g) }
    if p.prop == .popcorn { drawPopcorn(&c, bx: cx + 9, g: g) }
    if p.prop == .calendar { drawCalendar(&c, x: cx + 8, y: r0 + 1) }
    birdWing(&c, p.arm, cx: cx, r0: r0)

    let hx = cx + 3 + p.headDX
    let ht = r0 - 15 + p.headDY
    let nby = r0 + 1
    c.thick(cx + 3, nby, hx + 1, ht + 4 <= nby ? ht + 3 : ht + 1, 3, .body)
    c.spans(hx, ht, [(1, 4), (0, 5), (0, 5), (0, 5), (0, 4)], .body)
    if p.mouth != .closed {
        c.hline(hx + 6, hx + 8, ht + 1, .beak); c.hline(hx + 6, hx + 7, ht + 2, .beak)
        c.set(hx + 6, ht + 3, .mouth); c.hline(hx + 6, hx + 7, ht + 4, .beak)
    } else {
        c.hline(hx + 6, hx + 8, ht + 2, .beak); c.hline(hx + 6, hx + 7, ht + 3, .beakDark)
    }
    profileEye(&c, p.eyes, hx + 3, ht + 1)
    if p.blush { c.hline(hx + 3, hx + 4, ht + 3, .blush) }
    return Anchors(headX: hx + 2, headTop: ht, headW: 6, eyes: [(hx + 3, ht + 1)], profile: true, neck: (hx + 2, ht + 5))
}

// MARK: - Cats and the dalmatian

private func sock(_ q: QuadSpec) -> Col {
    switch q.coat {
    case .tuxedo: return .belly
    case .points: return .mark
    default: return .body
    }
}

/// Front-facing head, 9 wide. hx/ht = top-left of the head itself; ears sit above, floppy ears at the sides.
private func quadHead(_ c: inout Canvas, _ sp: Species, _ hx: Int, _ ht: Int, _ p: Pose) {
    let q = sp.quad
    let dog = sp.family == .dog
    let earCol: Col = q.coat == .points ? .mark : .body
    let leftEar: Col = q.coat == .calico ? .mark2 : earCol
    let rightEar: Col = q.coat == .calico ? .mark : earCol
    if q.ears == .cat {
        if p.earsFlat {
            c.hline(hx - 2, hx + 1, ht + 1, leftEar); c.set(hx - 2, ht + 2, leftEar)
            c.hline(hx + 7, hx + 10, ht + 1, rightEar); c.set(hx + 10, ht + 2, rightEar)
        } else {
            c.set(hx + 1, ht - 3, leftEar); c.hline(hx + 1, hx + 2, ht - 2, leftEar); c.hline(hx + 1, hx + 3, ht - 1, leftEar)
            c.set(hx + 7, ht - 3, rightEar); c.hline(hx + 6, hx + 7, ht - 2, rightEar); c.hline(hx + 5, hx + 7, ht - 1, rightEar)
            c.set(hx + 2, ht - 1, .inner); c.set(hx + 6, ht - 1, .inner)
        }
    }
    let shape: [(Int, Int)] = dog
        ? [(1, 7), (0, 8), (0, 8), (0, 8), (0, 8), (0, 8), (1, 7), (2, 6)]
        : [(1, 7), (0, 8), (0, 8), (0, 8), (0, 8), (1, 7), (2, 6)]
    c.spans(hx, ht, shape, .body)

    switch q.coat {
    case .tabby:
        for x in [hx + 3, hx + 5] { c.set(x, ht, .mark); c.set(x, ht + 1, .mark) }
        c.set(hx, ht + 3, .mark); c.set(hx + 8, ht + 3, .mark)
    case .points:
        c.ellipse(Double(hx) + 4, Double(ht) + 3.6, 3.2, 2.4, .mark)
    case .tuxedo:
        c.rect(hx + 2, ht + 4, 5, 3, .belly); c.set(hx + 4, ht + 3, .belly); c.hline(hx + 3, hx + 5, ht + 6, .belly)
    case .calico:
        c.rect(hx, ht, 3, 2, .mark2); c.set(hx, ht + 2, .mark2)
        c.hline(hx + 6, hx + 8, ht, .mark)
    case .spots:
        c.set(hx + 6, ht + 1, .mark); c.set(hx + 2, ht, .mark)
    }
    if q.ears == .flop {
        let lift = p.earsFlat ? 1 : 0
        c.spans(hx, ht + lift, [(-1, 0), (-3, -1), (-3, -1), (-3, -1), (-3, -1), (-2, -1)], .mark)
        c.spans(hx, ht + lift, [(8, 9), (9, 11), (9, 11), (9, 11), (9, 11), (9, 10)], .mark)
    }

    // face
    let L = hx + 1, R = hx + 6, ey = ht + 2
    switch p.eyes {
    case .open:
        c.rect(L, ey, 2, 2, .eye); c.rect(R, ey, 2, 2, .eye)
        c.set(L, ey, .eyeHi); c.set(R, ey, .eyeHi)
    case .half:
        c.hline(L, L + 1, ey + 1, .eye); c.hline(R, R + 1, ey + 1, .eye)
    case .up:
        c.rect(L, ey - 1, 2, 2, .eye); c.rect(R, ey - 1, 2, 2, .eye)
        c.set(L + 1, ey - 1, .eyeHi); c.set(R + 1, ey - 1, .eyeHi)
    case .wide:
        c.rect(L, ey - 1, 2, 3, .eye); c.rect(R, ey - 1, 2, 3, .eye)
        c.set(L, ey - 1, .eyeHi); c.set(R, ey - 1, .eyeHi)
    case .closed:
        c.hline(L, L + 1, ey + 1, .eye); c.hline(R, R + 1, ey + 1, .eye)
    case .happy:
        c.set(L - 1, ey + 1, .eye); c.set(L, ey, .eye); c.set(L + 1, ey + 1, .eye)
        c.set(R, ey + 1, .eye); c.set(R + 1, ey, .eye); c.set(R + 2, ey + 1, .eye)
    case .angry:
        c.hline(L, L + 1, ey + 1, .eye); c.hline(R, R + 1, ey + 1, .eye)
        c.set(L, ey, .eye); c.set(R + 1, ey, .eye)
    case .sad:
        c.hline(L, L + 1, ey + 1, .eye); c.hline(R, R + 1, ey + 1, .eye)
        c.set(L + 1, ey, .eye); c.set(R, ey, .eye)
    case .dizzy:
        for (dx, dy) in [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)] { c.set(L - 1 + dx, ey - 1 + dy, .eye); c.set(R - 1 + dx, ey - 1 + dy, .eye) }
    }
    if q.coat != .tuxedo && q.coat != .points { c.rect(hx + 2, ht + 4, 5, 2, .belly) }
    c.set(hx + 4, ht + 4, .nose)
    if dog { c.set(hx + 3, ht + 4, .nose); c.set(hx + 5, ht + 4, .nose) }
    let my = ht + 5
    switch p.mouth {
    case .closed:
        c.set(hx + 3, my, .bodyShade); c.set(hx + 5, my, .bodyShade)
    case .open:
        c.hline(hx + 3, hx + 5, my, .mouth); c.set(hx + 4, my + 1, .mouth)
    case .tongue:
        if dog { c.hline(hx + 3, hx + 5, my, .mouth); c.rect(hx + 4, my + 1, 1, 2, .tongue) }
        else { c.set(hx + 3, my, .mouth); c.set(hx + 5, my, .mouth); c.set(hx + 4, my + 1, .tongue) }
    }
    if p.blush { c.set(hx + 1, ht + 4, .blush); c.set(hx + 7, ht + 4, .blush) }
}

private func quadAnchors(_ hx: Int, _ ht: Int) -> Anchors {
    Anchors(headX: hx + 4, headTop: ht, headW: 9, eyes: [(hx + 1, ht + 2), (hx + 6, ht + 2)], profile: false, neck: (hx + 4, ht + 7))
}

/// Coat markings on a side-view body spanning x0...x1, rows r0...rb.
private func sideCoat(_ c: inout Canvas, _ q: QuadSpec, _ x0: Int, _ x1: Int, _ r0: Int, _ rb: Int) {
    let inBody = { (x: Int, y: Int) -> Bool in x >= x0 - 1 && x <= x1 + 1 && y >= r0 && y <= rb }
    switch q.coat {
    case .tabby:
        for x in stride(from: x0 + 3, through: x1 - 3, by: 3) { c.paint(.body, .mark) { xx, y in xx == x && y >= r0 && y <= r0 + 2 } }
    case .calico:
        c.patch(.mark) { x, y in inBody(x, y) && x <= x0 + 5 && y <= r0 + 3 }
        c.patch(.mark2) { x, y in inBody(x, y) && x >= x0 + 9 && x <= x0 + 13 && y <= r0 + 2 }
    case .spots:
        for (dx, dy) in [(2, 1), (6, 3), (9, 1), (12, 3), (4, 4), (15, 1)] where x0 + dx < x1 {
            c.paint(.body, .mark) { x, y in (x == x0 + dx || x == x0 + dx + 1) && y == r0 + dy }
        }
    default:
        break
    }
    if q.coat == .tuxedo {
        c.patch(.belly) { x, y in inBody(x, y) && (y >= rb - 1 || (x >= x1 - 3 && y >= r0 + 2)) }
    } else {
        c.paint(.body, .belly) { x, y in (y == rb && x >= x0 + 3 && x <= x1 - 3) || (y == rb - 1 && x >= x0 + 5 && x <= x1 - 5) }
    }
}

private func sideTail(_ c: inout Canvas, _ q: QuadSpec, bx: Int, by: Int, _ p: Pose) {
    let sw = Int((sin(p.tail) * 2).rounded()), sw2 = Int((sin(p.tail - 0.8) * 1.4).rounded())
    switch q.tail {
    case .cat:
        if p.tailUp { c.polyline([(bx, by), (bx - 3, by - 3), (bx - 3 + sw2, by - 7), (bx - 2 + sw, by - 10)], 2, .body) }
        else { c.polyline([(bx, by + 1), (bx - 4, by + 3), (bx - 7 + sw2, by + 5)], 2, .body) }
        if q.coat == .tabby { c.paint(.body, .mark) { x, y in y < by - 3 && y % 3 == 0 && x < bx } }
    case .fluffy:
        c.polyline([(bx, by), (bx - 3, by - 3), (bx - 3 + sw2, by - 7), (bx - 2 + sw, by - 10)], 3, .mark)
    case .thin:
        c.polyline([(bx, by), (bx - 3, by - 2), (bx - 5 + sw, by - 5)], 2, .body)
    }
}

private func drawQuad(_ c: inout Canvas, _ sp: Species, _ p: Pose, cx: Int) -> Anchors {
    let q = sp.quad
    let g = c.h - 2
    let sk = sock(q)
    var hx = cx, ht = 0
    var shoulder: (Int, Int)?

    switch p.stance {
    case .stand, .walk, .crouch, .squash, .eat:
        let crouch = p.stance == .crouch
        let legH = crouch ? 1 : (p.stance == .squash ? max(1, q.legH - 2) : q.legH)
        let rb = g - legH                      // bottom row of the body
        let r0 = rb - q.bodyH + 1 + p.bob
        let x0 = cx - q.half + (crouch ? p.wiggle : 0), x1 = cx + q.half - 1
        sideTail(&c, q, bx: x0 + 1, by: r0 + 1, p)
        let legX = [x0 + 1, x0 + 3, x1 - 4, x1 - 2]
        let offs: [Double] = [0, .pi, 0, .pi]
        for i in [1, 2, 0, 3] {
            let sv = p.stance == .walk ? sin(p.phase + offs[i]) : 0
            let lift = p.stance == .walk && cos(p.phase + offs[i]) > 0.35 ? 1 : 0
            let lx = legX[i] + Int((sv * 1.3).rounded())
            let far = i == 1 || i == 2
            c.rect(lx, rb, 2, g - lift - rb + 1, far ? .bodyShade : .body)
            c.hline(lx, lx + 1, g - lift, far && sk == .body ? .bodyShade : sk)
        }
        var rows: [(Int, Int)] = [(2, -3), (1, -1)]
        for _ in 0..<(q.bodyH - 3) { rows.append((0, 0)) }
        rows.append((1, -1))
        for (i, s) in rows.enumerated() { c.hline(x0 + s.0, x1 + s.1, r0 + i, .body) }
        sideCoat(&c, q, x0, x1, r0, rb)
        hx = x1 - 4 + p.headDX
        ht = r0 - 6 + p.headDY
        if crouch { hx += 2; ht += 2 }
        if p.stance == .eat { hx = x1 - 2 + p.headDX; ht = g - 7 + p.headDY }

    case .sit:
        let top = g - 13 + p.bob
        let wrap = (q.tail == .cat || q.tail == .fluffy) && !p.tailUp
        if !wrap {
            switch q.tail {
            case .cat, .fluffy:
                c.polyline([(cx - 7, g - 3), (cx - 10, g - 7), (cx - 10 + Int(sin(p.tail - 0.8) * 1.4), g - 11), (cx - 9 + Int(sin(p.tail) * 2), g - 14)], q.tail == .fluffy ? 3 : 2, q.tail == .fluffy ? .mark : .body)
            case .thin:
                c.polyline([(cx - 6, g - 1), (cx - 10, g), (cx - 13 + Int(sin(p.tail) * 2), g)], 2, .body)
            }
        }
        let torso: [(Int, Int)] = [(-2, 2), (-3, 3), (-4, 3), (-5, 4), (-6, 4), (-6, 4), (-7, 4), (-7, 4), (-8, 4), (-8, 4), (-8, 4), (-8, 4), (-7, 4)]
        c.spans(cx, top, torso, .body)
        c.hline(cx - 8, cx - 1, g, .body)
        c.rect(cx + 1, g - 5, 2, 6, .body)
        c.rect(cx + 3, g - 5, 2, 6, .body)
        c.set(cx + 2, g - 4, .bodyShade); c.set(cx + 2, g - 2, .bodyShade)
        c.hline(cx + 1, cx + 4, g, sk)
        c.hline(cx - 8, cx - 5, g, sk)
        switch q.coat {
        case .tuxedo: c.rect(cx + 1, top + 2, 3, 6, .belly)
        case .tabby: c.rect(cx + 1, top + 3, 2, 4, .belly)
        case .calico:
            c.patch(.mark) { x, y in x <= cx - 4 && y >= g - 7 && y <= g - 3 }
            c.patch(.mark2) { x, y in x >= cx - 3 && x <= cx && y >= top + 1 && y <= top + 3 }
        case .spots:
            for (dx, dy) in [(-6, 8), (-2, 3), (-4, 11), (1, 6)] { c.set(cx + dx, top + dy, .mark); c.set(cx + dx + 1, top + dy, .mark) }
        case .points:
            break
        }
        if q.coat == .tabby { for y in [top + 4, top + 7] { c.hline(cx - 4, cx - 2, y, .mark) } }
        if wrap {
            c.thick(cx - 9, g, cx + 5, g, 1, q.tail == .fluffy ? .mark : .body)
            c.rect(cx + 5, g - (sin(p.tail) > 0 ? 2 : 1), 1, 2, q.tail == .fluffy ? .mark : .body)
        }
        hx = cx - 3 + p.headDX
        ht = top - 7 + p.headDY
        shoulder = (cx + 2, top + 3)
        if p.prop == .laptop { drawLaptop(&c, lx: cx + 6, g: g) }
        if p.prop == .popcorn { drawPopcorn(&c, bx: cx + 6, g: g) }

    case .upright:
        c.polyline([(cx - 2, g - 1), (cx - 7, g), (cx - 11 + Int(sin(p.tail) * 2), g - 1)], 2, .body)
        c.spans(cx, g - 14, [(-2, 2), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-4, 3), (-4, 4), (-4, 4), (-4, 4), (-3, 3)], .body)
        c.spans(cx, g - 12, [(1, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 2)], .belly)
        c.rect(cx + 3, g - 12, 2, 2, .body); c.rect(cx + 3, g - 9, 2, 2, .body)
        c.hline(cx - 3, cx + 3, g, sk)
        hx = cx - 4 + p.headDX
        ht = g - 21 + p.headDY
        shoulder = (cx + 2, g - 11)

    case .lie:
        let x0 = cx - q.half, x1 = cx + 5
        if q.tail == .cat || q.tail == .fluffy {
            c.hline(x0 - 3, x0 + 4, g, q.tail == .fluffy ? .mark : .body)
            c.rect(x0 - 3, g - 2 + (sin(p.tail) > 0 ? 0 : 1), 1, 2, q.tail == .fluffy ? .mark : .body)
        } else {
            sideTail(&c, q, bx: x0 + 1, by: g - 4, p)
        }
        c.spans(x0, g - 6, [(3, x1 - x0 - 3), (1, x1 - x0 - 1), (0, x1 - x0), (0, x1 - x0), (0, x1 - x0), (0, x1 - x0), (1, x1 - x0 - 1)], .body)
        sideCoat(&c, q, x0, x1, g - 6, g)
        if sp.family == .cat {
            c.hline(cx + 3, cx + 5, g, sk == .body ? .belly : sk)
            hx = cx - 1 + p.headDX; ht = g - 11 + p.headDY
        } else {
            c.rect(cx + 3, g - 1, 7, 2, .body)
            c.hline(cx + 8, cx + 9, g, sk)
            c.set(cx + 6, g - 1, .bodyShade)
            hx = cx + p.headDX; ht = g - 12 + p.headDY
        }

    case .curl:
        c.spans(cx, g - 6, [(-6, 4), (-8, 6), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-8, 6)], .body)
        sideCoat(&c, q, cx - 9, cx + 7, g - 6, g)
        hx = cx - 2 + p.headDX
        ht = g - 8 + p.headDY

    case .stretch:
        let x0 = cx - q.half
        sideTail(&c, q, bx: x0 + 1, by: g - 12, p)
        c.rect(x0 + 3, g - 7, 2, 8, .bodyShade)
        c.rect(x0 + 1, g - 7, 2, 8, .body)
        c.thick(x0, g - 12, cx + 4, g - 7, 5, .body)
        c.rect(cx + 3, g - 1, 9, 2, .body)
        c.hline(cx + 10, cx + 11, g, sk)
        hx = cx + 4 + p.headDX
        ht = g - 10 + p.headDY

    case .leap, .fly:
        let r0 = g - 13 + p.bob
        sideTail(&c, q, bx: cx - 9, by: r0 + 2, p)
        c.thick(cx - 8, r0 + 4, cx - 13, r0 + 8, 2, .bodyShade)
        c.thick(cx - 7, r0 + 4, cx - 12, r0 + 9, 2, .body)
        c.spans(cx, r0, [(-7, 5), (-9, 8), (-10, 9), (-10, 9), (-9, 8), (-7, 5)], .body)
        c.hline(cx - 6, cx + 4, r0 + 5, .belly)
        if q.coat == .tabby { for x in [cx - 6, cx - 3, cx, cx + 3] { c.paint(.body, .mark) { xx, y in xx == x && y >= r0 && y <= r0 + 1 } } }
        if q.coat == .spots { for (dx, dy) in [(-6, 1), (-2, 3), (2, 1)] { c.set(cx + dx, r0 + dy, .mark) } }
        c.thick(cx + 6, r0 + 4, cx + 11, r0 + 7, 2, .bodyShade)
        c.thick(cx + 7, r0 + 4, cx + 13, r0 + 8, 2, .body)
        hx = cx + 6 + p.headDX
        ht = r0 - 6 + p.headDY

    case .umbrella, .held:
        return drawQuadFront(&c, sp, q, p, cx: cx)
    }

    quadHead(&c, sp, hx, ht, p)

    if p.stance == .curl {
        c.thick(cx - 9, g, cx + 7, g, 1, q.tail == .fluffy ? .mark : .body)
        c.rect(cx + 7, g - 2, 2, 2, q.tail == .fluffy ? .mark : .body)
    }
    if let sh = shoulder {
        var to: (Int, Int)?
        switch p.arm {
        case .tap: to = (cx + 7, g - 2)
        case .forward: to = (cx + 6, g - 4)
        case .scoop: to = (cx + 8, g - 8)
        case .toMouth, .lick: to = (hx + 5, ht + 6)
        case .raised: to = (cx + 5, ht + 1)
        case .hold: to = (cx + 5, g - 10)
        default: break
        }
        if p.prop == .calendar { drawCalendar(&c, x: cx + 3, y: g - 14) }
        if let to {
            c.thick(sh.0, sh.1, to.0, to.1, 2, .body)
            c.set(to.0, to.1, sk == .body ? .belly : sk)
        }
    }
    return quadAnchors(hx, ht)
}

/// Seen from the front: gliding down with an umbrella, or held up.
private func drawQuadFront(_ c: inout Canvas, _ sp: Species, _ q: QuadSpec, _ p: Pose, cx: Int) -> Anchors {
    let g = c.h - 2
    let ht = g - 18
    let hx = cx - 4
    let s = sin(p.phase)
    let sk = sock(q)
    let bb = ht + 16

    let sw = Int((sin(p.tail) * 2).rounded())
    switch q.tail {
    case .cat: c.polyline([(cx + 2, bb - 2), (cx + 6, bb - 4), (cx + 7 + sw, bb - 9)], 2, .body)
    case .fluffy: c.polyline([(cx + 2, bb - 2), (cx + 6, bb - 4), (cx + 7 + sw, bb - 9)], 3, .mark)
    case .thin: c.polyline([(cx + 2, bb - 1), (cx + 6, bb + 1), (cx + 8 + sw, bb - 1)], 2, .body)
    }
    let k = s > 0 ? 1 : 0
    c.rect(cx - 3, bb, 2, 2 + k, .body); c.hline(cx - 3, cx - 2, bb + 1 + k, sk)
    c.rect(cx + 1, bb, 2, 3 - k, .body); c.hline(cx + 1, cx + 2, bb + 2 - k, sk)
    c.spans(cx, ht + 7, [(-3, 2), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-3, 2), (-2, 1)], .body)
    switch q.coat {
    case .spots: for (dx, dy) in [(-3, 9), (2, 10), (-1, 13)] { c.set(cx + dx, ht + dy, .mark) }
    case .calico: c.patch(.mark) { x, y in y > ht + 7 && y < ht + 11 && x < cx - 1 }
    default: c.spans(cx, ht + 8, [(-1, 0), (-2, 1), (-2, 1), (-2, 1), (-2, 1), (-2, 1), (-1, 0)], .belly)
    }
    var lp = (cx - 5, ht + 13 + k), rp = (cx + 4, ht + 14 - k)
    if p.stance == .umbrella {
        lp = (cx - 6, ht + 14)
        rp = (cx + 6, ht - 2)
        drawUmbrella(&c, ux: cx + 6, top: ht - 11, handleTo: (cx + 6, ht - 2))
    }
    c.thick(cx - 4, ht + 9, lp.0, lp.1, 2, .body)
    c.thick(cx + 3, ht + 9, rp.0, rp.1, 2, .body)
    c.hline(lp.0, lp.0 + 1, lp.1, sk == .body ? .belly : sk)
    c.hline(rp.0, rp.0 + 1, rp.1, sk == .body ? .belly : sk)
    quadHead(&c, sp, hx, ht, p)
    return quadAnchors(hx, ht)
}

// MARK: - Outfits & extras

private let hatArt: [Hat: ([String], [Character: Col])] = [
    .topHat: (["..KKK..", "..KKK..", "..KKK..", "..RRR..", "KKKKKKK"], ["K": .hatBlack, "R": .hatBand]),
    .crown: (["Y.Y.Y", "YYRYY", "YYYYY"], ["Y": .gold, "R": .ruby]),
    .party: (["..S..", "..P..", ".PBP.", ".BPB.", "PBPBP"], ["S": .star, "P": .partyPink, "B": .partyBlue]),
    .beanie: (["..W...", ".BBBB.", "BBBBBB", "DDDDDD"], ["W": .white, "B": .beanie, "D": .beanieDark]),
    .witch: (["K.......", "KK......", ".KK.....", ".KKK....", ".KKKK...", ".PPPP...", "KKKKKKKK"], ["K": .witch, "P": .witchBand]),
    .cowboy: (["...CCC...", "..CCCCC..", "..DDDDD..", "C.CCCCC.C", ".CCCCCCC."], ["C": .cowboy, "D": .cowboyDark]),
    .bow: (["PP.PP", "PPDPP", "PP.PP"], ["P": .bowPink, "D": .bowDark]),
    .flower: ([".W.", "WYW", ".W."], ["W": .petal, "Y": .popYellow]),
]

private func drawExtras(_ c: inout Canvas, _ p: Pose, _ a: Anchors) {
    let o = p.outfit
    let hx = a.headX, top = a.headTop
    let half = a.headW / 2
    let (nx, ny) = a.neck
    let nh = a.profile ? 2 : 3
    switch o.neck {
    case .none: break
    case .scarf:
        c.rect(nx - nh, ny, nh * 2 + 1, 2, .scarf)
        for x in stride(from: nx - nh + 1, through: nx + nh, by: 2) { c.set(x, ny, .scarfStripe) }
        c.rect(nx - nh - (a.profile ? 1 : 0), ny + 1, 2, 3, .scarf)
    case .bowtie:
        if a.profile { c.sprite(nx + 1, ny, ["X.X", "XXX", "X.X"], ["X": .ruby]) }
        else { c.sprite(nx - 2, ny, ["XX.XX", "XXXXX", "XX.XX"], ["X": .ruby]) }
    case .bell:
        c.hline(nx - nh, nx + nh, ny, .collar)
        c.rect(a.profile ? nx + 1 : nx - 1, ny + 1, a.profile ? 2 : 3, 2, .gold)
    case .bandana:
        if a.profile { c.sprite(nx - 1, ny, ["BBBB", ".BWB", "..BB", "...B"], ["B": .bandana, "W": .white]) }
        else { c.sprite(nx - 3, ny, ["BBBBBBB", ".BWBBB.", "..BBB..", "...B..."], ["B": .bandana, "W": .white]) }
    }
    for (ex, ey) in a.eyes {
        if a.profile {
            switch o.glasses {
            case .none: break
            case .shades: c.rect(ex - 1, ey, 3, 2, .lens); c.hline(ex - 3, ex - 2, ey, .frame)
            case .hearts: c.rect(ex - 1, ey, 3, 2, .lensPink); c.set(ex, ey + 2, .lensPink); c.hline(ex - 3, ex - 2, ey, .frame)
            case .round:
                c.hline(ex - 1, ex + 1, ey - 1, .frame); c.set(ex - 1, ey, .frame); c.set(ex + 1, ey, .frame)
                c.hline(ex - 1, ex + 1, ey + 1, .frame); c.hline(ex - 3, ex - 2, ey, .frame)
            }
        } else {
            switch o.glasses {
            case .none: break
            case .shades: c.rect(ex - 1, ey, 3, 2, .lens); c.rect(ex, ey, 2, 2, .lens)
            case .hearts: c.rect(ex - 1, ey, 3, 2, .lensPink); c.set(ex, ey + 2, .lensPink)
            case .round:
                c.hline(ex - 1, ex + 2, ey - 1, .frame); c.hline(ex - 1, ex + 2, ey + 2, .frame)
                c.rect(ex - 1, ey, 1, 2, .frame); c.rect(ex + 2, ey, 1, 2, .frame)
            }
        }
    }
    if !a.profile && o.glasses != .none, a.eyes.count == 2 { c.hline(a.eyes[0].0 + 2, a.eyes[1].0 - 1, a.eyes[0].1, .frame) }
    if p.phones {
        if a.profile {
            c.hline(hx - 2, hx + 2, top - 1, .phones)
            c.rect(hx - 2, top + 1, 2, 3, .phonesPad)
            c.set(hx - 2, top, .phones)
        } else {
            c.hline(hx - half - 1, hx + half + 1, top - 2, .phones)
            c.rect(hx - half - 1, top - 1, 1, 2, .phones); c.rect(hx + half + 1, top - 1, 1, 2, .phones)
            c.rect(hx - half - 2, top + 1, 2, 3, .phonesPad); c.rect(hx + half + 1, top + 1, 2, 3, .phonesPad)
        }
    }
    if p.nightcap {
        let l = a.profile ? hx - 2 : hx - half + 1
        c.hline(l, l + (a.profile ? 5 : 7), top - 1, .white)
        c.hline(l, l + (a.profile ? 4 : 6), top - 2, .cap)
        c.hline(l - 1, l + 3, top - 3, .cap)
        c.hline(l - 2, l + 1, top - 4, .cap)
        c.rect(l - 4, top - 4, 2, 2, .white)
        return
    }
    guard o.hat != .none, let (rows, map) = hatArt[o.hat] else { return }
    let w = rows.map { $0.count }.max() ?? 0
    var x0: Int, y0: Int
    switch o.hat {
    case .bow: x0 = a.profile ? hx - 4 : hx + 1; y0 = a.profile ? top - 1 : top - 3
    case .flower: x0 = a.profile ? hx - 1 : hx - half - 1; y0 = a.profile ? top - 2 : top - 3
    default:
        x0 = (a.profile ? hx - 1 : hx) - w / 2
        y0 = top - rows.count
    }
    c.sprite(x0, y0, rows, map)
}

// MARK: - Bat

/// Drawn standing on its feet; on the top edge the whole picture is turned over, so it hangs head-down.
/// Wings wrap the body at rest and spread (flapping with `phase`) when it flies, is thrown or is held.
private func drawBat(_ c: inout Canvas, _ p: Pose, cx: Int) -> Anchors {
    let g = c.h - 2
    let flying = [.leap, .held, .fly, .umbrella, .squash].contains(p.stance)
    let wig = p.stance == .walk ? (sin(p.phase) > 0 ? 1 : 0) : 0
    let bodyTop: Int, ht: Int
    if flying {
        bodyTop = g - 14
        ht = bodyTop - 7
        // wings: from the shoulders out to the tips, with a scalloped trailing edge and finger bones
        let lift = 0.15 + 0.5 * sin(p.phase)
        let sy = bodyTop + 1
        for dx in 0...14 {
            let top = sy - Int((Double(dx) * lift).rounded())
            let depth = max(1, 9 - dx / 2 - (dx % 5 == 4 ? 3 : 0))
            for y in top...(top + depth) {
                let col: Col = y == top || (dx % 5 == 0 && dx > 0) ? .wingDark : .wing
                c.set(cx + 4 + dx, y, col)
                c.set(cx - 5 - dx, y, col)
            }
        }
        c.spans(cx, bodyTop, [(-4, 3), (-4, 3), (-5, 4), (-5, 4), (-5, 4), (-5, 4), (-4, 3), (-4, 3), (-3, 2), (-2, 1)], .body)
        c.spans(cx, bodyTop + 1, [(-2, 1), (-3, 2), (-3, 2), (-3, 2), (-2, 1)], .belly)
        c.set(cx - 2, bodyTop + 10, .mark); c.set(cx + 1, bodyTop + 10, .mark)
    } else {
        // hanging: a round bundle of wings wrapped like a cloak, feet gripping
        bodyTop = g - 13 + wig
        ht = bodyTop - 7
        c.spans(cx, bodyTop, [(-5, 4), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-5, 4), (-5, 4), (-4, 3), (-2, 1)], .wing)
        for y in (bodyTop + 1)...(bodyTop + 9) { c.set(cx - 4, y, .wingDark); c.set(cx + 3, y, .wingDark) }
        c.spans(cx, bodyTop, [(-2, 1), (-3, 2), (-3, 2), (-2, 1), (-1, 0)], .belly)
        c.set(cx - 2, g, .mark); c.set(cx - 2, g - 1, .mark); c.set(cx + 1, g, .mark); c.set(cx + 1, g - 1, .mark)
    }
    // head (flowing into the body) and big ears
    c.spans(cx, ht, [(-3, 2), (-4, 3), (-5, 4), (-5, 4), (-5, 4), (-5, 4), (-5, 4)], .body)
    for (i, row) in [(-4, -4), (-5, -4), (-5, -3), (-5, -3), (-5, -2), (-5, -2)].enumerated() {
        let y = ht - 6 + i
        c.hline(cx + row.0, cx + row.1, y, .body)
        c.hline(cx - 1 - row.1, cx - 1 - row.0, y, .body)
        if i >= 2 && i <= 4 { c.set(cx - 4, y, .inner); c.set(cx + 3, y, .inner) }
    }
    // face
    let ey = ht + 2
    // big round eyes, three wide, pupils in the middle
    let eyes = [(cx - 4, ey), (cx + 1, ey)]
    for (n, (ex, _)) in eyes.enumerated() {
        switch p.eyes {
        case .closed: c.hline(ex, ex + 2, ey + 1, .eye)
        case .happy: c.set(ex, ey + 1, .eye); c.set(ex + 1, ey, .eye); c.set(ex + 2, ey + 1, .eye)
        case .half: c.hline(ex, ex + 2, ey, .bodyShade); c.hline(ex, ex + 2, ey + 1, .eyeHi); c.set(ex + 1, ey + 1, .eye)
        case .dizzy, .angry, .sad: c.set(ex, ey, .eye); c.set(ex + 1, ey + 1, .eye); c.set(ex + 2, ey, .eye)
        case .up: c.rect(ex, ey, 3, 2, .eyeHi); c.set(ex + 1, ey, .eye)
        default: c.rect(ex, ey, 3, 2, .eyeHi); c.set(ex + 1, ey + 1, .eye)
        }
        if p.blush { c.set(n == 0 ? ex - 1 : ex + 3, ey + 2, .blush) }
    }
    c.set(cx - 1, ey + 2, .nose); c.set(cx, ey + 2, .nose)
    if p.mouth == .open || p.mouth == .tongue { c.hline(cx - 1, cx, ey + 3, .mouth) }
    c.set(cx - 2, ey + 4, .white); c.set(cx + 1, ey + 4, .white)          // little fangs
    return Anchors(headX: cx, headTop: ht, headW: 9, eyes: eyes, profile: false, neck: (cx, ht + 7))
}

/// One accessory alone, on an invisible stand-in head so it sits the way it does on a pet.
func drawAccessory(_ c: inout Canvas, _ o: Outfit) {
    let cx = c.w / 2, ht = 12
    var p = Pose()
    p.outfit = o
    drawExtras(&c, p, Anchors(headX: cx, headTop: ht, headW: 11, eyes: [(cx - 4, ht + 4), (cx + 2, ht + 4)], profile: false, neck: (cx, ht + 10)))
}

/// Draws any pet with its extras.
@discardableResult
func drawPet(_ c: inout Canvas, _ sp: Species, _ p: Pose, cx: Int) -> Anchors {
    let a = sp == .goose ? drawGoose(&c, p, cx: cx) : sp == .bat ? drawBat(&c, p, cx: cx) : drawQuad(&c, sp, p, cx: cx)
    drawExtras(&c, p, a)
    return a
}

// MARK: - Particles

enum PKind { case heart, z, star, bang, question, kernel, crumb, drop, puff, note }

struct Particle {
    var kind: PKind
    var x: Double, y: Double
    var vx: Double, vy: Double
    var life: Double
    var gravity: Double
    var size: Int
}

let SPR_STAR = [".X.", "XXX", ".X."]

func drawParticle(_ c: inout Canvas, _ p: Particle) {
    let ix = Int(p.x.rounded()), iy = Int(p.y.rounded())
    switch p.kind {
    case .heart: c.sprite(ix - 2, iy - 2, ["XX.XX", "XXXXX", ".XXX.", "..X.."], ["X": .heart])
    case .z: c.sprite(ix - 2, iy - 2, p.size > 0 ? ["XXXXX", "...X.", "..X..", ".X...", "XXXXX"] : ["XXXX", "..X.", ".X..", "XXXX"], ["X": .zzz])
    case .star: c.sprite(ix - 1, iy - 1, SPR_STAR, ["X": .star])
    case .bang: c.sprite(ix, iy - 2, ["X", "X", "X", ".", "X"], ["X": .heart])
    case .question: c.sprite(ix - 1, iy - 2, ["XX.", "..X", ".X.", "...", ".X."], ["X": .zzz])
    case .kernel: c.rect(ix, iy, 2, 2, .popCream); c.set(ix + 1, iy, .popYellow)
    case .crumb: c.set(ix, iy, .crust)
    case .drop: c.sprite(ix, iy, [".X", "XX"], ["X": .sweat])
    case .puff: c.sprite(ix - 2, iy - 1, [".XX.", "XXXX", ".XX."], ["X": .white])
    case .note: c.sprite(ix - 2, iy - 2, [".XXX", ".X.X", ".X..", "XX..", "XX.."], ["X": .note])
    }
}
