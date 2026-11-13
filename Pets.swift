// The pets themselves: species, coats, and how each one is drawn in every pose.
// Style: slim silhouettes, flat colors and crisp outlines (like the original cats).

import Cocoa

// MARK: - Poses

enum Stance {
    case stand, walk, sit, lie, curl, stretch, crouch, leap, upright, eat, squash,
         fly,                                    // birds in the air
         umbrella, held,                         // seen from the front (gliding down, held up)
         front                                   // facing you, a paw pressed against the screen
}
enum Eyes { case open, closed, happy, wide, angry, dizzy, sad, up, half }
enum Mouth { case closed, open, tongue }
/// Wing (birds) or front paw (four-legged pets).
enum Arm { case rest, raised, forward, tap, down, scoop, toMouth, lick, hold }
enum Prop { case none, laptop, popcorn, calendar, glass, book }

enum Hat: String, Codable, CaseIterable {
    case none, bow, flower, crown, topHat, party, witch, cowboy, santa
    /// Hats that were retired (the beanie) come off instead of losing the whole outfit.
    init(from decoder: Decoder) throws { self = Hat(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .none }
    /// Wide hats sit on top of the head, so ears tip out to the sides underneath them.
    var wide: Bool { [.topHat, .witch, .cowboy, .santa].contains(self) }
}
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
    var thinking = false     // study mode, thinking very hard: a loading spinner over the head
    var spin = 0.0
    var turn = -1.0          // study mode: a page turning over, 0 (lifting on the right) to 1 (landed on the left); -1 none
}

/// Where the head ended up, so outfits, bubbles and particles can follow it.
struct Anchors {
    var headX: Int
    var headTop: Int
    var headW: Int
    var eyes: [(Int, Int)]     // top-left cell of each eye
    var profile: Bool          // side-view bird head: one eye, beak to the right
    var neck: (Int, Int)
    var hatDX = 0              // hats sit further forward (the goose's head-down poses)
}

// MARK: - Species

enum Family { case bird, cat, dog, bat, turtle }
enum Ears { case cat, flop }
enum Tail { case cat, fluffy, thin, brush, ringed }  // brush: a fox's big tail with a white tip; ringed: a red panda's
enum Coat { case tabby, points, tabbyWhite, calico, spots, fox, redPanda }

struct QuadSpec {
    var ears: Ears
    var tail: Tail
    var coat: Coat
    var half: Int = 9      // body half-length
    var legH: Int = 4
    var bodyH: Int = 7
}

enum Species: String, CaseIterable, Identifiable, Codable {
    case goose, parrot, ginger, siamese, tuxedo, calico, dalmatian, fox, turtle, redPanda, bat
    /// The pets you can pick (the red panda is shelved for now).
    static var lineup: [Species] { allCases.filter { $0 != .redPanda } }
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
        case .goose, .parrot: return .bird
        case .dalmatian, .fox: return .dog
        case .bat: return .bat
        case .turtle: return .turtle
        default: return .cat
        }
    }
    var isBird: Bool { family == .bird }

    var title: String {
        switch self {
        case .goose: return "Goose"
        case .parrot: return "Parrot"
        case .ginger: return "Ginger cat"
        case .siamese: return "Siamese"
        case .tuxedo: return "Tabby cat"        // the case keeps its old name so saved pets carry over
        case .calico: return "Calico"
        case .dalmatian: return "Dalmatian"
        case .fox: return "Fox"
        case .redPanda: return "Red panda"
        case .turtle: return "Turtle"
        case .bat: return "Bat"
        }
    }

    var defaultName: String {
        switch self {
        case .goose: return "Honk"
        case .parrot: return "Kiwi"
        case .ginger: return "Mango"
        case .siamese: return "Mochi"
        case .tuxedo: return "Pebble"
        case .calico: return "Patches"
        case .dalmatian: return "Domino"
        case .fox: return "Ember"
        case .redPanda: return "Maple"
        case .turtle: return "Mossy"
        case .bat: return "Luna"
        }
    }

    var vocal: (word: String, sound: String) {
        if self == .parrot { return (["HELLO!", "SQUAWK!", "HI THERE", "PRETTY BIRD"].randomElement()!, "squawk") }
        if self == .fox { return ("YIP", "woof") }
        if self == .redPanda { return ("EEP", "chirp") }          // a red panda's twitter
        switch family {
        case .bird: return ("HONK", "honk")
        case .dog: return ("WOOF", "woof")
        case .cat: return ("MEOW", "meow")
        case .bat: return ("SQUEAK", "chirp")
        case .turtle: return ("HMM", "pop")
        }
    }

    /// Snacks this pet loves the most.
    var favorites: Set<ItemKind> {
        if self == .parrot { return [.berry, .cookie] }
        if self == .fox { return [.berry, .sausage, .bone] }
        if self == .redPanda { return [.bamboo, .berry, .cookie] }   // bamboo is nearly all a red panda eats
        switch family {
        case .bird: return [.bread, .cookie, .berry]
        case .cat: return [.fish]
        case .dog: return [.bone, .sausage]
        case .bat: return [.berry, .cookie]           // a fruit bat: fruit first
        case .turtle: return [.fish, .berry]          // fish and strawberries
        }
    }

    var quad: QuadSpec {
        switch self {
        case .siamese: return QuadSpec(ears: .cat, tail: .fluffy, coat: .points)
        case .tuxedo: return QuadSpec(ears: .cat, tail: .cat, coat: .tabbyWhite)
        case .fox: return QuadSpec(ears: .cat, tail: .brush, coat: .fox, half: 9, legH: 4, bodyH: 6)
        case .redPanda: return QuadSpec(ears: .cat, tail: .ringed, coat: .redPanda, half: 9, legH: 4, bodyH: 7)
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
        case .tuxedo:       // a grey tabby with a cream blaze, chest and toes
            return [.body: 0x7e7168, .bodyShade: 0x6c6058, .mark: 0x5d5047, .belly: 0xd8d1b5, .eye: 0x392c24,
                    .nose: 0xe0889a, .inner: 0xd8d1b5, .mouth: 0xc9677a, .tongue: 0xe0889a, .outline: 0x392c24, .whisker: 0x392c24]
        case .fox:
            return [.body: 0xfd921e, .bodyShade: 0xe27c12, .mark: 0xfd921e, .mark2: 0x5b5257, .belly: 0xffffff,
                    .eye: 0x2b2738, .nose: 0x2b2738, .inner: 0xffffff]
        case .redPanda:     // the reference's rust orange, cream face, plum-black legs and belly, red-brown tear marks
            return [.body: 0xcc7846, .bodyShade: 0xa85f38, .bodyLight: 0xdc8c5a, .belly: 0xf0d8c4, .bellyShade: 0xdcbfa9,
                    .mark: 0x332a34, .markShade: 0x241e27, .mark2: 0xebcdb3, .accent: 0x84543c,
                    .eye: 0x241e27, .nose: 0x241e27, .inner: 0x332a34, .mouth: 0x6a3038, .tongue: 0xe58a95, .outline: 0x3c1e30]
        case .turtle:       // the reference picture's colours: olive skin, brown shell, a blue nightcap with yellow dots
            return [.body: 0xa8a848, .bodyShade: 0x607818, .bodyLight: 0xb4b456, .mark: 0xa87830, .markShade: 0xa86030,
                    .mark2: 0xc0a860, .accent: 0x784800, .inner: 0xc07848, .belly: 0xc0a848, .bellyShade: 0xa89038,
                    .wing: 0x4878f0, .wingDark: 0x3a62cc, .ring: 0xf0d848, .tongue: 0x900000, .mouth: 0x161616,
                    .eye: 0x161616, .eyeHi: 0xffffff, .outline: 0x161616, .blush: 0xf09090]
        case .parrot:       // green, with a red head, yellow cheeks and blue flight feathers
            return [.body: 0x5cc24c, .bodyShade: 0x46a33c, .belly: 0xa9df63, .mark: 0xea4a3f, .accent: 0xffd447,
                    .wing: 0x4cb047, .wingDark: 0x2f6fd6, .beak: 0xf2e6cc, .beakDark: 0x3a3340, .feet: 0x8d929c,
                    .ring: 0xffffff, .speculum: 0xea4a3f]
        case .calico:
            return [.body: 0xffffff, .bodyShade: 0xdfe0e8, .mark: 0xf4a24a, .mark2: 0x3b3645, .belly: 0xffffff]
        case .dalmatian:
            return [.body: 0xffffff, .bodyShade: 0xe6e3ee, .mark: 0x3a3440, .belly: 0xffffff, .nose: 0x3a3440]
        case .bat:
            return [.body: 0x4f4166, .bodyShade: 0x3d3252, .wing: 0x6a5785, .wingDark: 0x392e4e, .belly: 0x6f5f88,
                    .witch: 0x2a2533,   // a dark witch hat, so it doesn't melt into the purple bat
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

/// A big open book lying on the floor, pages curling up at the ends, navy cover underneath; now and then a page lifts,
/// arcs over the spine and settles on the other side (study mode).
/// x, y: its top-left; it's 17 wide and 5 tall, so y = the floor row - 4.
func drawBook(_ c: inout Canvas, x: Int, y: Int, turn: Double = -1) {
    c.sprite(x, y, ["..PPP.......PPP..", ".PPPPPPPKPPPPPPP.", "PPLLLPPPKPPLLLPPP", "NNNNNNNNNNNNNNNNN", ".NNNNNNNNNNNNNNN."],
             ["P": .page, "K": .lapLight, "L": .lapLight, "N": .bookCover])
    if turn >= 0 {
        let a = Double.pi * min(1, turn), sx = x + 8, sy = y + 1
        let ex = sx + Int((7 * cos(a)).rounded()), ey = sy - Int((6 * sin(a)).rounded())
        let mx = sx + Int((4 * cos(a)).rounded()), my = sy - Int((5 * sin(a)).rounded()) - 1     // the page bows as it goes over
        c.thick(sx, sy, mx, my, 1, .page); c.thick(mx, my, ex, ey, 1, .page)
    }
}

func drawCalendar(_ c: inout Canvas, x: Int, y: Int) {
    c.rect(x, y, 7, 7, .page)
    c.rect(x, y, 7, 2, .pageRed)
    c.set(x + 1, y - 1, .lapDark); c.set(x + 5, y - 1, .lapDark)
    c.hline(x + 1, x + 5, y + 3, .lapLight)
    c.hline(x + 1, x + 4, y + 5, .lapLight)
}

/// A glass of water, held up for the water reminder.
func drawGlass(_ c: inout Canvas, x: Int, y: Int) {
    c.sprite(x, y, ["G...G", "GLLLG", "GWwWG", "GWwWG", "GWWWG", ".GGG."], ["G": .glassEdge, "L": .waterLight, "W": .water, "w": .white])
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
    case .up: c.set(ex + 1, ey, .eye)          // looking up and ahead (a row higher, the outline would swallow it)
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
    if p.prop == .book { drawBook(&c, x: cx + 1, y: c.h - 6, turn: p.turn) }
    if p.prop == .glass { drawGlass(&c, x: cx + 9, y: r0 + 2) }
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
    return Anchors(headX: hx + 2, headTop: ht, headW: 6, eyes: [(hx + 3, ht + 1)], profile: true, neck: (hx + 2, ht + 5),
                   hatDX: p.headDY >= 9 ? 2 : 0)
}

// MARK: - Cats and the dalmatian

private func sock(_ q: QuadSpec) -> Col {
    switch q.coat {
    case .tabbyWhite: return .belly
    case .points: return .mark
    case .fox: return .mark2
    case .redPanda: return .mark
    default: return .body
    }
}

/// Legs: a red panda's are black all the way up.
private func legCol(_ q: QuadSpec, far: Bool) -> Col {
    q.coat == .redPanda ? (far ? .markShade : .mark) : (far ? .bodyShade : .body)
}

/// A red panda's tail: thick and bushy, in red and buff rings, with a dark brown tip. Drawn in one go, then each cell
/// is coloured by how far along the tail it sits, so the rings go straight across it whichever way it bends.
private func ringedTail(_ c: inout Canvas, _ pts: [(Int, Int)], _ w: Int, edge: Bool = false) {
    c.polyline(pts, w, .ring)                     // a stand-in colour no four-legged pet uses
    var segs: [(ax: Double, ay: Double, dx: Double, dy: Double, len: Double, start: Double)] = []
    var total = 0.0
    for i in 0..<(pts.count - 1) {
        let ax = Double(pts[i].0), ay = Double(pts[i].1), dx = Double(pts[i + 1].0) - ax, dy = Double(pts[i + 1].1) - ay
        let len = max(0.001, hypot(dx, dy))
        segs.append((ax, ay, dx, dy, len, total))
        total += len
    }
    let xs = pts.map(\.0), ys = pts.map(\.1)
    if edge {
        // lying in front of the body: a dark line along its top, so it reads as a tail and not more body
        for y in max(1, ys.min()! - w - 1)...min(c.h - 1, ys.max()! + w + 1) {
            for x in max(0, xs.min()! - w - 1)...min(c.w - 1, xs.max()! + w + 1) where c.get(x, y) == Col.ring.rawValue {
                let above = c.get(x, y - 1)
                if above == Col.body.rawValue || above == Col.mark.rawValue || above == Col.markShade.rawValue { c.set(x, y - 1, .outline) }
            }
        }
    }
    for y in max(0, ys.min()! - w - 1)...min(c.h - 1, ys.max()! + w + 1) {
        for x in max(0, xs.min()! - w - 1)...min(c.w - 1, xs.max()! + w + 1) where c.get(x, y) == Col.ring.rawValue {
            var best = Double.infinity, along = 0.0
            for sg in segs {
                let t = max(0, min(1, ((Double(x) - sg.ax) * sg.dx + (Double(y) - sg.ay) * sg.dy) / (sg.len * sg.len)))
                let d = hypot(Double(x) - (sg.ax + sg.dx * t), Double(y) - (sg.ay + sg.dy * t))
                if d < best { best = d; along = sg.start + sg.len * t }
            }
            let col: Col = along > total - 1.5 ? .accent : (along.truncatingRemainder(dividingBy: 4) < 2.4 ? .body : .mark2)
            c.set(x, y, col)
        }
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
        if p.outfit.hat.wide && !p.earsFlat {
            // under a wide hat the ears tip out to the sides, so the hat sits on the head instead of on the ears
            c.hline(hx - 1, hx, ht, leftEar); c.set(hx - 2, ht - 1, leftEar); c.set(hx - 1, ht - 1, leftEar)
            c.hline(hx + 8, hx + 9, ht, rightEar); c.set(hx + 10, ht - 1, rightEar); c.set(hx + 9, ht - 1, rightEar)
            c.set(hx - 1, ht, .inner); c.set(hx + 9, ht, .inner)
        } else if p.earsFlat {
            c.hline(hx - 2, hx + 1, ht + 1, leftEar); c.set(hx - 2, ht + 2, leftEar)
            c.hline(hx + 7, hx + 10, ht + 1, rightEar); c.set(hx + 10, ht + 2, rightEar)
        } else if q.coat == .redPanda {
            // big pointed ears with white rims and dark insides
            c.set(hx, ht - 4, .belly); c.hline(hx, hx + 1, ht - 3, .belly); c.hline(hx, hx + 2, ht - 2, .belly); c.hline(hx + 1, hx + 3, ht - 1, .body)
            c.set(hx + 1, ht - 2, .inner); c.set(hx + 1, ht - 1, .inner); c.set(hx + 2, ht - 1, .inner)
            c.set(hx + 8, ht - 4, .belly); c.hline(hx + 7, hx + 8, ht - 3, .belly); c.hline(hx + 6, hx + 8, ht - 2, .belly); c.hline(hx + 5, hx + 7, ht - 1, .body)
            c.set(hx + 7, ht - 2, .inner); c.set(hx + 7, ht - 1, .inner); c.set(hx + 6, ht - 1, .inner)
        } else {
            c.set(hx + 1, ht - 3, leftEar); c.hline(hx + 1, hx + 2, ht - 2, leftEar); c.hline(hx + 1, hx + 3, ht - 1, leftEar)
            c.set(hx + 7, ht - 3, rightEar); c.hline(hx + 6, hx + 7, ht - 2, rightEar); c.hline(hx + 5, hx + 7, ht - 1, rightEar)
            c.set(hx + 2, ht - 1, .inner); c.set(hx + 6, ht - 1, .inner)
            if q.coat == .fox {        // dark ear tips
                c.set(hx + 1, ht - 3, .mark2); c.hline(hx + 1, hx + 2, ht - 2, .mark2)
                c.set(hx + 7, ht - 3, .mark2); c.hline(hx + 6, hx + 7, ht - 2, .mark2)
            }
        }
    }
    let shape: [(Int, Int)] = dog || q.coat == .redPanda        // a red panda's big round head
        ? [(1, 7), (0, 8), (0, 8), (0, 8), (0, 8), (0, 8), (1, 7), (2, 6)]
        : [(1, 7), (0, 8), (0, 8), (0, 8), (0, 8), (1, 7), (2, 6)]
    c.spans(hx, ht, shape, .body)

    switch q.coat {
    case .tabby:
        for x in [hx + 3, hx + 5] { c.set(x, ht, .mark); c.set(x, ht + 1, .mark) }
        c.set(hx, ht + 3, .mark); c.set(hx + 8, ht + 3, .mark)
    case .points:
        c.ellipse(Double(hx) + 4, Double(ht) + 3.6, 3.2, 2.4, .mark)
    case .tabbyWhite:
        // like the reference cat: forehead stripes, a cream blaze down the nose, whiskers out to the sides
        for x in [hx + 3, hx + 5] { c.set(x, ht, .mark); c.set(x, ht + 1, .mark) }
        c.set(hx, ht + 3, .mark); c.set(hx + 8, ht + 3, .mark)
        c.set(hx + 4, ht + 2, .belly); c.set(hx + 4, ht + 3, .belly)
        for y in [ht + 2, ht + 4] { c.hline(hx - 2, hx - 1, y, .whisker); c.hline(hx + 9, hx + 10, y, .whisker) }
    case .fox:
        // white cheeks that flare out past the face, dark backs to the ears
        c.hline(hx - 1, hx + 1, ht + 4, .belly); c.hline(hx + 7, hx + 9, ht + 4, .belly)
        c.set(hx - 1, ht + 5, .belly); c.set(hx + 9, ht + 5, .belly); c.hline(hx, hx + 1, ht + 5, .belly); c.hline(hx + 7, hx + 8, ht + 5, .belly)
    case .redPanda:
        // white brows, cheeks and muzzle; red-brown tear marks from the eyes to the corners of the mouth
        c.set(hx + 2, ht + 1, .belly); c.set(hx + 6, ht + 1, .belly)
        c.hline(hx, hx + 1, ht + 4, .belly); c.hline(hx + 7, hx + 8, ht + 4, .belly)
        c.set(hx, ht + 5, .belly); c.set(hx + 8, ht + 5, .belly)
        c.rect(hx + 2, ht + 4, 5, 4, .belly)
        c.hline(hx + 2, hx + 2, ht + 4, .accent); c.set(hx + 6, ht + 4, .accent)
        c.set(hx + 3, ht + 5, .accent); c.set(hx + 5, ht + 5, .accent)
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
    case .open where q.coat == .tabbyWhite:
        c.rect(L + 1, ey, 1, 2, .eye); c.rect(R, ey, 1, 2, .eye)       // narrow, like the reference
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
    let fox = q.coat == .fox
    if q.coat != .points && q.coat != .redPanda { c.rect(hx + 2, ht + 4, 5, fox ? 3 : 2, .belly) }
    c.set(hx + 4, ht + 4, .nose)
    if dog && !fox { c.set(hx + 3, ht + 4, .nose); c.set(hx + 5, ht + 4, .nose) }
    let my = ht + 5
    switch p.mouth {
    case .closed:
        if !fox && q.coat != .redPanda { c.set(hx + 3, my, .bodyShade); c.set(hx + 5, my, .bodyShade) }
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
    case .redPanda:
        // black belly and chest under the red back
        c.paint(.body, .mark) { x, y in inBody(x, y) && ((y == rb && x >= x0 + 1) || (y == rb - 1 && x >= x0 + 4 && x <= x1 - 3) || (x >= x1 - 1 && y >= r0 + 3)) }
    case .spots:
        for (dx, dy) in [(2, 1), (6, 3), (9, 1), (12, 3), (4, 4), (15, 1)] where x0 + dx < x1 {
            c.paint(.body, .mark) { x, y in (x == x0 + dx || x == x0 + dx + 1) && y == r0 + dy }
        }
    default:
        break
    }
    if q.coat == .redPanda { return }
    if q.coat == .tabbyWhite || q.coat == .fox {
        if q.coat == .tabbyWhite { for x in stride(from: x0 + 3, through: x1 - 4, by: 3) { c.paint(.body, .mark) { xx, y in xx == x && y >= r0 && y <= r0 + 2 } } }
        // white chest and belly
        c.patch(.belly) { x, y in inBody(x, y) && ((y == rb && x >= x0 + 2 && x <= x1 - 1) || (x >= x1 - 2 && y >= r0 + 2)) }
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
    case .brush:
        let pts = p.tailUp ? [(bx, by), (bx - 4, by - 2), (bx - 6 + sw2, by - 6), (bx - 5 + sw, by - 9)]
                           : [(bx, by + 1), (bx - 4, by + 3), (bx - 8 + sw2, by + 4)]
        c.polyline(pts, 3, .body)
        whiteTip(&c, pts.last!)
    case .ringed:
        // carried out behind, a little raised, a lazy sway
        let pts = p.tailUp ? [(bx, by + 1), (bx - 4, by), (bx - 8, by - 1 + sw2), (bx - 11, by - 3 + sw)]
                           : [(bx, by + 1), (bx - 4, by + 3), (bx - 8, by + 4 + sw2 / 2), (bx - 11, by + 4)]
        ringedTail(&c, pts, 4)
    }
}

/// The white tip of a fox's tail, around the last point of its line (drawn 3 cells thick to the right and down).
private func whiteTip(_ c: inout Canvas, _ end: (Int, Int)) {
    c.paint(.body, .belly) { x, y in x >= end.0 - 1 && x <= end.0 + 3 && y >= end.1 - 1 && y <= end.1 + 2 }
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
            c.rect(lx, rb, 2, g - lift - rb + 1, legCol(q, far: far))
            c.hline(lx, lx + 1, g - lift, far && sk == .body ? .bodyShade : sk)
            if q.coat == .fox { c.rect(lx, g - lift - 2, 2, 2, .mark2) }
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
        let wrap = (q.tail == .cat || q.tail == .fluffy || q.tail == .brush || q.tail == .ringed) && !p.tailUp
        if !wrap {
            switch q.tail {
            case .ringed:
                ringedTail(&c, [(cx - 6, g - 2), (cx - 10, g - 4), (cx - 13 + Int(sin(p.tail - 0.8) * 1.4), g - 9), (cx - 12 + Int(sin(p.tail) * 2), g - 14)], 4)
            case .cat, .fluffy:
                c.polyline([(cx - 7, g - 3), (cx - 10, g - 7), (cx - 10 + Int(sin(p.tail - 0.8) * 1.4), g - 11), (cx - 9 + Int(sin(p.tail) * 2), g - 14)], q.tail == .fluffy ? 3 : 2, q.tail == .fluffy ? .mark : .body)
            case .brush:
                let end = (cx - 10 + Int(sin(p.tail) * 2), g - 13)
                c.polyline([(cx - 7, g - 3), (cx - 11, g - 6), (cx - 12 + Int(sin(p.tail - 0.8) * 1.4), g - 10), end], 3, .body)
                whiteTip(&c, end)
            case .thin:
                c.polyline([(cx - 6, g - 1), (cx - 10, g), (cx - 13 + Int(sin(p.tail) * 2), g)], 2, .body)
            }
        }
        let torso: [(Int, Int)] = q.coat == .redPanda        // plump and round, like the reference
            ? [(-3, 2), (-5, 3), (-6, 4), (-7, 4), (-8, 5), (-8, 5), (-9, 5), (-9, 5), (-9, 5), (-9, 5), (-9, 5), (-9, 5), (-8, 4)]
            : [(-2, 2), (-3, 3), (-4, 3), (-5, 4), (-6, 4), (-6, 4), (-7, 4), (-7, 4), (-8, 4), (-8, 4), (-8, 4), (-8, 4), (-7, 4)]
        c.spans(cx, top, torso, .body)
        c.hline(cx - 8, cx - 1, g, .body)
        c.rect(cx + 1, g - 5, 2, 6, legCol(q, far: false))
        c.rect(cx + 3, g - 5, 2, 6, legCol(q, far: false))
        c.set(cx + 2, g - 4, legCol(q, far: true)); c.set(cx + 2, g - 2, legCol(q, far: true))
        c.hline(cx + 1, cx + 4, g, sk)
        c.hline(cx - 8, cx - 5, g, sk)
        switch q.coat {
        case .fox: c.rect(cx + 1, top + 2, 3, 6, .belly)
        case .redPanda:
            // black chest down to the front legs, rounded at the top
            c.paint(.body, .mark) { x, y in x >= cx + 1 && x <= cx + 5 && y >= top + (x <= cx + 1 ? 6 : 4) && y <= g - 5 }
            c.hline(cx - 8, cx - 4, g, .mark)                              // hind foot
        case .tabby, .tabbyWhite: c.rect(cx + 1, top + 3, 2, q.coat == .tabbyWhite ? 6 : 4, .belly)
        case .calico:
            c.patch(.mark) { x, y in x <= cx - 4 && y >= g - 7 && y <= g - 3 }
            c.patch(.mark2) { x, y in x >= cx - 3 && x <= cx && y >= top + 1 && y <= top + 3 }
        case .spots:
            for (dx, dy) in [(-6, 8), (-2, 3), (-4, 11), (1, 6)] { c.set(cx + dx, top + dy, .mark); c.set(cx + dx + 1, top + dy, .mark) }
        case .points:
            break
        }
        if q.coat == .tabby || q.coat == .tabbyWhite { for y in [top + 4, top + 7] { c.hline(cx - 4, cx - 2, y, .mark) } }
        if wrap && q.tail == .ringed {
            // like the reference: the big ringed tail wraps round the front, over the paws, dark tip last
            ringedTail(&c, [(cx - 9, g - 4), (cx - 11, g - 2), (cx - 5, g - 1), (cx + 6, g - 1)], 4, edge: true)
        } else if wrap && q.tail == .brush {
            // the big tail curls round the front paws, white tip last
            c.thick(cx - 10, g - 1, cx + 4, g - 1, 2, .body)
            whiteTip(&c, (cx + 3, g - 1))
        } else if wrap {
            c.thick(cx - 9, g, cx + 5, g, 1, q.tail == .fluffy ? .mark : .body)
            c.rect(cx + 5, g - (sin(p.tail) > 0 ? 2 : 1), 1, 2, q.tail == .fluffy ? .mark : .body)
        }
        hx = cx - 3 + p.headDX
        ht = top - 7 + p.headDY
        shoulder = (cx + 2, top + 3)
        if p.prop == .laptop { drawLaptop(&c, lx: cx + 6, g: g) }
        if p.prop == .popcorn { drawPopcorn(&c, bx: cx + 6, g: g) }

    case .upright where q.coat == .redPanda:
        return drawStandingRedPanda(&c, sp, p, cx: cx)

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
        if q.tail == .ringed {
            ringedTail(&c, [(x0 + 3, g - 2), (x0 - 4, g - 1), (x0 - 10, g - 1)], 4)
        } else if q.tail == .brush {
            c.thick(x0 - 6, g - 1, x0 + 3, g - 1, 2, .body)
            whiteTip(&c, (x0 - 7, g - 1))
        } else if q.tail == .cat || q.tail == .fluffy {
            c.hline(x0 - 3, x0 + 4, g, q.tail == .fluffy ? .mark : .body)
            c.rect(x0 - 3, g - 2 + (sin(p.tail) > 0 ? 0 : 1), 1, 2, q.tail == .fluffy ? .mark : .body)
        } else if q.tail == .thin && !p.tailUp {
            c.polyline([(x0 + 1, g - 2), (x0 - 3, g - 1), (x0 - 6 + Int((sin(p.tail) * 1.5).rounded()), g)], 2, .body)   // lying along the floor
        } else {
            sideTail(&c, q, bx: x0 + 1, by: g - 4, p)
        }
        c.spans(x0, g - 6, [(3, x1 - x0 - 3), (1, x1 - x0 - 1), (0, x1 - x0), (0, x1 - x0), (0, x1 - x0), (0, x1 - x0), (1, x1 - x0 - 1)], .body)
        sideCoat(&c, q, x0, x1, g - 6, g)
        if sp.family == .cat {
            if q.coat == .redPanda { c.rect(cx + 3, g - 1, 3, 2, .mark) }      // black front paws
            c.hline(cx + 3, cx + 5, g, sk == .body ? .belly : sk)
            hx = cx - 1 + p.headDX; ht = g - 11 + p.headDY
        } else {
            c.rect(cx + 3, g - 1, 7, 2, .body)
            c.hline(cx + 8, cx + 9, g, sk)
            c.set(cx + 6, g - 1, .bodyShade)
            hx = cx + p.headDX; ht = g - 12 + p.headDY
        }

    case .curl where q.coat == .fox:
        return drawSleepingFox(&c, p, cx: cx)

    case .curl where q.coat == .redPanda:
        return drawSleepingRedPanda(&c, p, cx: cx)

    case .curl:
        c.spans(cx, g - 6, [(-6, 4), (-8, 6), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-8, 6)], .body)
        sideCoat(&c, q, cx - 9, cx + 7, g - 6, g)
        hx = cx - 2 + p.headDX
        ht = g - 8 + p.headDY

    case .stretch:
        let x0 = cx - q.half
        sideTail(&c, q, bx: x0 + 1, by: g - 12, p)
        c.rect(x0 + 3, g - 7, 2, 8, legCol(q, far: true))
        c.rect(x0 + 1, g - 7, 2, 8, legCol(q, far: false))
        c.thick(x0, g - 12, cx + 4, g - 7, 5, .body)
        c.rect(cx + 3, g - 1, 9, 2, legCol(q, far: false))
        c.hline(cx + 10, cx + 11, g, sk)
        hx = cx + 4 + p.headDX
        ht = g - 10 + p.headDY

    case .leap, .fly:
        let r0 = g - 13 + p.bob
        sideTail(&c, q, bx: cx - 9, by: r0 + 2, p)
        c.thick(cx - 8, r0 + 4, cx - 13, r0 + 8, 2, legCol(q, far: true))
        c.thick(cx - 7, r0 + 4, cx - 12, r0 + 9, 2, legCol(q, far: false))
        c.spans(cx, r0, [(-7, 5), (-9, 8), (-10, 9), (-10, 9), (-9, 8), (-7, 5)], .body)
        c.hline(cx - 6, cx + 4, r0 + 5, q.coat == .redPanda ? .mark : .belly)
        if q.coat == .tabby { for x in [cx - 6, cx - 3, cx, cx + 3] { c.paint(.body, .mark) { xx, y in xx == x && y >= r0 && y <= r0 + 1 } } }
        if q.coat == .spots { for (dx, dy) in [(-6, 1), (-2, 3), (2, 1)] { c.set(cx + dx, r0 + dy, .mark) } }
        c.thick(cx + 6, r0 + 4, cx + 11, r0 + 7, 2, legCol(q, far: true))
        c.thick(cx + 7, r0 + 4, cx + 13, r0 + 8, 2, legCol(q, far: false))
        hx = cx + 6 + p.headDX
        ht = r0 - 6 + p.headDY

    case .front:
        return drawGlassPress(&c, sp, cx: cx)

    case .umbrella, .held:
        return drawQuadFront(&c, sp, q, p, cx: cx)
    }

    if p.prop == .book { drawBook(&c, x: cx - 2, y: g - 4, turn: p.turn) }
    if p.prop == .book && p.turn >= 0 && p.turn < 0.7 && p.stance == .lie {
        // turning the page: a front paw reaches out, catches the page and sweeps it over the spine
        let a = Double.pi * min(1, p.turn), sx = cx + 6, sy = g - 3
        let tx = sx + Int((7 * cos(a)).rounded()), ty = sy - Int((6 * sin(a)).rounded())
        c.thick(cx + 3, g - 4, tx, ty, 2, legCol(q, far: false))
        c.set(tx, ty, sk == .body ? .belly : q.coat == .redPanda ? .markShade : sk)
    }         // on the floor in front; the head stays above it (or rests on it)
    if q.coat == .redPanda { redPandaHead(&c, hx, ht, p) } else { quadHead(&c, sp, hx, ht, p) }

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
        if p.prop == .glass { drawGlass(&c, x: p.arm == .toMouth ? hx + 5 : cx + 4, y: p.arm == .toMouth ? ht + 4 : g - 13) }
        if let to {
            c.thick(sh.0, sh.1, to.0, to.1, 2, legCol(q, far: false))
            c.set(to.0, to.1, sk == .body ? .belly : q.coat == .redPanda ? .markShade : sk)
        }
    }
    return q.coat == .redPanda ? redPandaAnchors(hx, ht) : quadAnchors(hx, ht)
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
    case .brush:
        c.polyline([(cx + 2, bb - 2), (cx + 6, bb - 4), (cx + 7 + sw, bb - 9)], 3, .body)
        whiteTip(&c, (cx + 7 + sw, bb - 9))
    case .ringed:
        ringedTail(&c, [(cx + 2, bb - 1), (cx + 7, bb - 3), (cx + 9 + sw, bb - 9)], 4)
    }
    let k = s > 0 ? 1 : 0
    c.rect(cx - 3, bb, 2, 2 + k, legCol(q, far: false)); c.hline(cx - 3, cx - 2, bb + 1 + k, sk)
    c.rect(cx + 1, bb, 2, 3 - k, legCol(q, far: false)); c.hline(cx + 1, cx + 2, bb + 2 - k, sk)
    c.spans(cx, ht + 7, [(-3, 2), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-3, 2), (-2, 1)], .body)
    switch q.coat {
    case .spots: for (dx, dy) in [(-3, 9), (2, 10), (-1, 13)] { c.set(cx + dx, ht + dy, .mark) }
    case .calico: c.patch(.mark) { x, y in y > ht + 7 && y < ht + 11 && x < cx - 1 }
    case .redPanda: c.spans(cx, ht + 8, [(-2, 1), (-3, 2), (-3, 2), (-3, 2), (-3, 2), (-3, 2), (-3, 2), (-2, 1)], .mark)
    default: c.spans(cx, ht + 8, [(-1, 0), (-2, 1), (-2, 1), (-2, 1), (-2, 1), (-2, 1), (-1, 0)], .belly)
    }
    var lp = (cx - 5, ht + 13 + k), rp = (cx + 4, ht + 14 - k)
    if p.stance == .front { lp = (cx - 5, ht + 15); rp = (cx + 8, ht + 4) }       // one paw up against the glass
    if p.stance == .umbrella {
        lp = (cx - 6, ht + 14)
        rp = (cx + 6, ht - 2)
        drawUmbrella(&c, ux: cx + 6, top: ht - 11, handleTo: (cx + 6, ht - 2))
    }
    c.thick(cx - 4, ht + 9, lp.0, lp.1, 2, legCol(q, far: false))
    c.thick(cx + 3, ht + 9, rp.0, rp.1, 2, legCol(q, far: false))
    c.hline(lp.0, lp.0 + 1, lp.1, sk == .body ? .belly : sk)
    c.hline(rp.0, rp.0 + 1, rp.1, sk == .body ? .belly : sk)
    let anchors: Anchors
    if q.coat == .redPanda { redPandaHead(&c, hx, ht, p); anchors = redPandaAnchors(hx, ht) }
    else { quadHead(&c, sp, hx, ht, p); anchors = quadAnchors(hx, ht) }
    if p.stance == .front {
        // the paw flat against the screen, in front of everything, pink toe beans showing
        let fur: Col = q.coat == .redPanda ? .mark : (sk == .body ? .belly : sk)
        c.sprite(rp.0 - 2, rp.1 - 4, [".F.F.F.", "FPFPFPF", "FFFFFFF", "FFPPPFF", "FPPPPPF", "FFPPPFF", ".FFFFF."], ["F": fur, "P": .blush])
    }
    return anchors
}

// MARK: - Fox asleep

/// The fox asleep, drawn from its reference picture at the pets' pixel size: head down on the left with closed
/// eyes and a white muzzle, body behind it, the big tail curled round with its white tip, grey paws tucked under.
/// O fur, W white, G grey, K the lines inside the outline (the outline itself is added like every pet's).
private let foxAsleep = [
    "..G.....G...OOOO.....",
    ".WG.....GWKOOOOOOOKO.",
    ".WOOOOOOOWKOOOOOOOKO.",
    ".OOOOOOOOOKOOOOOOOKOO",
    ".OKKOWOKKOKOOOOOOOKOW",
    "OOOOWKWOOOKOOOOOOGKWW",
    "OOOOWWWOOOKOOG.......",
]

private func drawSleepingFox(_ c: inout Canvas, _ p: Pose, cx: Int) -> Anchors {
    let ox = cx - 10, oy = c.h - 2 - (foxAsleep.count - 1)
    c.sprite(ox, oy, foxAsleep, ["O": .body, "W": .belly, "G": .mark2, "K": .outline])
    if ![.closed, .half, .happy].contains(p.eyes) {          // waking up: eyes open
        for ex in [ox + 2, ox + 7] { c.rect(ex, oy + 3, 2, 2, .eye); c.set(ex, oy + 3, .eyeHi) }
    }
    if p.blush { c.set(ox + 1, oy + 5, .blush); c.set(ox + 9, oy + 5, .blush) }
    return Anchors(headX: ox + 5, headTop: oy + 2, headW: 9, eyes: [(ox + 2, oy + 4), (ox + 7, oy + 4)], profile: false, neck: (ox + 5, oy + 6))
}

/// Thinking very hard: round yellow ring eyes, and a loading spinner going round above the head.
private func drawThinking(_ c: inout Canvas, _ p: Pose, _ a: Anchors) {
    // a loading spinner: eight short rays going round, the newest dark and the rest fading (thin, no outline)
    let sx = a.headX, sy = a.headTop - (p.outfit.hat == .none ? 7 : 12)
    // a little round ring of dots: the newest a deep lavender, the ones behind it fading
    let ring = [(0, -3), (2, -2), (3, 0), (2, 2), (0, 3), (-2, 2), (-3, 0), (-2, -2)]
    let lead = Int(p.spin) % ring.count
    for (i, d) in ring.enumerated() {
        let behind = (lead - i + ring.count) % ring.count
        c.set(sx + d.0, sy + d.1, behind == 0 ? .spin1 : behind < 3 ? .spin2 : .spin3)
    }
}

// MARK: - Paw on the glass

/// Right up against your screen, after the reference picture: a big close-up of the face, one eye squeezed shut, a
/// little "w" mouth, both front paws pressed on the glass with their pink toe beans. W fur, V patches, P pink, K lines,
/// H the shine in the eyes. Recoloured for each pet (its fur, its markings).
private let glassPress = [
    ".........................WWW............",
    "......................WPPPPP............",
    "....................WPPPPPP.............",
    "..................WWPPPPPPP.............",
    ".................WWPPPPPPPW.............",
    "................WWWWPPPPPWW.............",
    "..............WWWWWWWWWWWWW.............",
    ".............WWWWWWWWWWWWWWW............",
    "............WWWWWWWWWWWWWWWWW...........",
    "...........WWWWWWWWWWWWWWWWWWWW.........",
    "..........WWWWWWWWWWWWWWWWWWWWWWW.......",
    "........WWWWKKWWWKWWWWWWWWWWWWWWW.......",
    ".......WWWWWWWKKWWKWWWWWWWWWWWWWWW......",
    ".......WWWWVVVVWKWKKKKWWWWWWWWWWWWW.....",
    "......WWWWVVVKKVWWWKHKKWWWWWWWWWWWW.....",
    "......WWWVVVVVVKVWWKKKKWWWWWWWWWWWWW....",
    "......WWWVVVKKKVVVWKKKKWWWWWWWWWWWWWWWW.",
    "......WWVVKKVVVKKVWWKKKWWWWWWWWWWWWWPPPW",
    "......WWVVVVVVVVVVWWKKWWWWWWWWWWWWWWPPPW",
    ".....KWWWVVVVVVVVVWWKWWWWWWWWWWWWWWWPPP.",
    "...WWWKWWVVVVVVVVVWWKWWWWWWWWWVKVWWWPP..",
    "..WWPPWPWVVVVVVVVVWWWWWWWWWWWWKKKWWWP...",
    ".WPWPPWWWVVVVVVVVVWWWKWWWWWWWWHHKWWW....",
    ".PPWWWWPPVVVVVVVVWWWWKWWWWWWWWKKKWW.....",
    ".PWPPPWPKVWWVVVVWWWWWWKWKKWWWWKKKWW.....",
    ".WPPPPPWKVWWWWWWWWWWWWWKWWKWKWWKWW......",
    ".WPPPPPWKWWWWWWWWWWWWWWWWWWKWWWWWK......",
    ".WPPPPPWKWWWWWWWWWWWWWWWWWWWWWWWWWK.....",
    "WWWPPPWWKWWWWVVVVWWWWWWWWWWWWWKKKKK.....",
    "WWWWWWWWKWWWVVVVVVWWWWWWWWWWWKWWPWWK....",
    "WWWWWWWWKWWVVVVVVVWWWWWWWWWWKWWWWWWWK...",
    "WWWVWWWWKVVVVVVVVVVVWWWWWWWWKPWWWWWPK...",
    "WWVVVWWWKVVVVVVVVVVVWWWWWWWWKWWPPPWWK...",
    "WVVVVVWWKPVVVVVVVVVVVWWWWWWWKWPPPPPWK...",
    "WVVVVVVWKPVVVVVVVVVVVWWWWWWWKWPPPPPWK..."
]

private func drawGlassPress(_ c: inout Canvas, _ sp: Species, cx: Int) -> Anchors {
    let g = c.h - 2
    let w = glassPress[0].count, h = glassPress.count
    let ox = cx - w / 2, oy = g - (h - 1)
    // each coat keeps its own look up close
    let coat = sp.quad.coat
    func eyePatch(_ x: Int, _ y: Int) -> Bool { y >= 13 && y <= 27 && x >= 8 && x <= 18 }
    func corner(_ x: Int, _ y: Int) -> Bool { x <= 8 && y >= 27 }
    func paw(_ x: Int, _ y: Int) -> Bool { (x <= 8 && y >= 19 && y <= 27) || (x >= 28 && y >= 28) }
    func ear(_ x: Int, _ y: Int) -> Bool { (y <= 5 && x >= 16) || (y >= 15 && y <= 20 && x >= 35) }
    let stripes: Set<Int> = [9 * 100 + 17, 10 * 100 + 17, 9 * 100 + 20, 10 * 100 + 20, 11 * 100 + 20, 9 * 100 + 23, 10 * 100 + 23,
                             12 * 100 + 7, 13 * 100 + 7, 15 * 100 + 33, 16 * 100 + 33]
    let spots: Set<Int> = [8 * 100 + 22, 8 * 100 + 23, 11 * 100 + 27, 12 * 100 + 27, 29 * 100 + 23, 30 * 100 + 23, 31 * 100 + 4, 26 * 100 + 30]
    for (y, row) in glassPress.enumerated() {
        for (x, ch) in row.enumerated() where ch != "." {
            let col: Col
            switch ch {
            case "K": col = .outline
            case "H": col = .eyeHi
            case "P": col = .blush
            case "V":
                switch coat {
                case .calico: col = eyePatch(x, y) || corner(x, y) ? .mark2 : .mark       // black and orange patches
                case .points: col = eyePatch(x, y) ? .mark : .body                         // the dark mask
                case .tabby, .tabbyWhite, .fox: col = eyePatch(x, y) ? .body : .belly       // a cream or white chest
                default: col = eyePatch(x, y) ? .body : .mark                              // dalmatian spots (not over the eye)
                }
            default:
                switch coat {
                case .points where paw(x, y) || ear(x, y): col = .mark                     // dark points: ears and paws
                case .fox where paw(x, y) || (ear(x, y) && (y <= 3 || x >= 37)): col = .mark2      // dark socks and ear tips
                case .fox where pow(Double(x - 26) / 7.5, 2) + pow(Double(y - 27) / 5.5, 2) <= 1: col = .belly   // a soft white muzzle
                case .tabby, .tabbyWhite where stripes.contains(y * 100 + x): col = .mark   // forehead stripes
                case .spots where spots.contains(y * 100 + x): col = .mark
                default: col = .body
                }
            }
            c.set(ox + x, oy + y, col)
        }
    }
    if sp.family == .dog && coat == .spots {
        // a dog, not a cat: no pointy ears; soft floppy ears hanging down the sides, a dog's nose and a little tongue
        for (y, row) in glassPress.enumerated() { for (x, ch) in row.enumerated() where ch != "." && (ear(x, y) || (y <= 22 && x >= 35 && ch == "P")) && !(y >= 15 && x < 37 && ch == "W") {
            c.set(ox + x, oy + y, .clear)
        } }
        let leftEar: [(Int, Int, Int)] = [(6, 13, 16), (7, 12, 16), (8, 11, 16), (9, 10, 15), (10, 9, 15), (11, 8, 14), (12, 8, 13), (13, 8, 12), (14, 9, 11)]
        let rightEar: [(Int, Int, Int)] = [(13, 33, 36), (14, 33, 37), (15, 33, 37), (16, 34, 37), (17, 34, 37), (18, 34, 37), (19, 34, 36), (20, 35, 36)]
        for (y, a, b) in leftEar + rightEar { for x in a...b { c.set(ox + x, oy + y, .mark) } }
        c.rect(ox + 24, oy + 23, 2, 2, .nose); c.set(ox + 23, oy + 23, .nose)
        c.set(ox + 25, oy + 26, .tongue); c.set(ox + 25, oy + 27, .tongue); c.set(ox + 26, oy + 26, .tongue)
    }
    if coat == .fox { c.rect(ox + 24, oy + 23, 2, 2, .nose) }                       // a fox's little black nose
    return Anchors(headX: ox + 20, headTop: oy + 6, headW: 18, eyes: [(ox + 20, oy + 14), (ox + 30, oy + 21)], profile: false, neck: (ox + 20, oy + 30))
}

// MARK: - Turtle

/// The turtle asleep, exactly like the reference picture: head down in a blue nightcap with yellow dots, a white brim
/// and pompom, eye shut, mouth open with a little tongue; the domed brown shell with its plates and orange rim; chunky
/// green legs. Head on the left as in the picture; flipped when drawn so the head is at the front.
/// G skin, D dark skin, M/S/L/E shell (mid, dark, light, lines), R rim, P belly, B/Y/W nightcap, T tongue, K lines.
private let turtleAsleep = [
    ".....................SMMM.........",
    "...................LLLMELLL.......",
    "..................MMELLLLEMM......",
    ".....BYYBBB......MMELLMELLEMM.....",
    "...YYBYYBBYY....MMMELMMMELEMMM....",
    "..BBBBBBBWWW....MMMELMMMELEMMM....",
    "..BYYBBWWWGGG..SMMEELMMMELEEEEM...",
    ".BBYYBWWGGGGGGKLLLLLLMMMELLLLLE...",
    ".BBBWWWGGKKGGGGRRRRLLLLLLRRRRLLL..",
    ".YBWWGGGGGGGGGGKKKRRRLLRRRRRRRRL..",
    ".YKWGGGGGGGGGGGKGGKKRRRRKKRKKKRKK.",
    "WWKKGGKGGGGGGGKGGGGGKRRKGGKGGGKGKG",
    "WW..DGKGGGKTGKGGGGGGKKKKGGGGGGKGGD",
    ".....DGGGGKTGKGGGGGKPPPKGGGGGGKDD.",
    "......DGGGGGDKDGGGGKLLPKGGGGGDD...",
    ".......DDDDD..DDDDD.....DDDDDD...."
]

/// Awake: the same shell and legs, with the head drawn on its own so it can look about, eat, and pull in.
private let turtleBody = [
    ".....................SMMM.........",
    "...................LLLMELLL.......",
    "..................MMELLLLEMM......",
    ".................MMELLMELLEMM.....",
    "................MMMELMMMELEMMM....",
    "................MMMELMMMELEMMM....",
    "...............SMMEELMMMELEEEEM...",
    "..............KLLLLLLMMMELLLLLE...",
    "..............GRRRRLLLLLLRRRRLLL..",
    "..............GKKKRRRLLRRRRRRRRL..",
    "..............GKGGKKRRRRKKRKKKRKK.",
    "..............KGGGGGKRRKGGKGGGKGKG",
    "..............GGGGGGKKKKGGGGGGKGGD",
    "..............GGGGGKPPPKGGGGGGKDD.",
    "..............DGGGGKLLPKGGGGGDD...",
    "..............DDDDD.....DDDDDD...."
]

/// The awake head: small, round and low by the shell like the sleepy one; the same columns as the body (the neck
/// meets the shell at column 14).
private let turtleHead = [
    "......GGGG.....",
    ".....GGGGGG....",
    "....GGGGGGGG...",
    "....GGGGGGGGGG.",
    "....GGGGGGGGGGG",
    "....GGGGGGGGGGG",
    ".....GGGGGGGGG.",
    "......DDDDDD...",
]

private let turtleColors: [Character: Col] = ["G": .body, "D": .bodyShade, "M": .mark, "S": .markShade, "L": .mark2, "E": .accent,
    "R": .inner, "P": .belly, "B": .wing, "Y": .ring, "W": .white, "T": .tongue, "K": .outline]

/// Every pose of the turtle. It's slow, it pulls into its shell when startled or picked up, and it always sleeps in
/// its nightcap.
private func drawTurtle(_ c: inout Canvas, _ p: Pose, cx: Int) -> Anchors {
    let g = c.h - 2
    let w = turtleBody[0].count, h = turtleBody.count
    let ox = cx - w / 2, oy = g - (h - 1)
    func blit(_ grid: [[Character]], dy: Int = 0) {
        c.sprite(ox, oy + dy, grid.map { String($0.reversed()) }, turtleColors)
    }
    func at(_ col: Int) -> Int { ox + (w - 1 - col) }          // a column of the head-left drawings, on the canvas
    let headAnchors = { (dx: Int, dy: Int) -> Anchors in
        Anchors(headX: at(8) + dx, headTop: oy + 4 + dy, headW: 9, eyes: [(at(7) + dx, oy + 6 + dy)], profile: true, neck: (at(10) + dx, oy + 11 + dy))
    }
    switch p.stance {
    case .curl:
        if p.prop == .book { drawBook(&c, x: at(10), y: g - 4) }      // dozed off over its book (its head rests on the pages)
        blit(turtleAsleep.map(Array.init))
        if p.blush { c.set(at(6), oy + 11, .blush) }
        return headAnchors(0, 6)
    case .squash, .crouch, .held, .umbrella:
        // tucked into its shell: just the shell on the ground, two eyes peeking out of the front
        var shell = turtleBody.prefix(11).map { Array($0) }
        for r in 0..<shell.count { for x in 0..<15 where x < shell[r].count { shell[r][x] = "." } }
        blit(shell, dy: 5 - (p.stance == .held ? 3 : 0))
        if ![.closed, .happy].contains(p.eyes) { c.set(at(15), oy + 13 + p.wiggle - (p.stance == .held ? 3 : 0), .eye); c.set(at(15), oy + 12 - (p.stance == .held ? 3 : 0), .eye) }
        if p.stance == .umbrella { drawUmbrella(&c, ux: at(24), top: oy - 6, handleTo: (at(24), oy + 6)) }
        return headAnchors(0, 6)
    default:
        break
    }
    var grid = turtleBody.map { Array($0) }
    if p.stance == .walk {
        // one foot up, then the other; slow and steady
        let front = sin(p.phase) > 0
        for x in (front ? 14...19 : 24...30) where x < w { grid[h - 1][x] = "." }
    }
    // the head: up and looking, down to eat or rest, stretched up high
    var hdx = -p.headDX, hdy = p.headDY
    switch p.stance {
    case .eat: hdx -= 2; hdy += 3
    case .lie: hdy += 2
    case .stretch, .upright: hdy -= 2; hdx -= 1
    default: break
    }
    let top = 4 + hdy
    for (r, row) in turtleHead.enumerated() {
        let y = top + r
        guard y >= 0 && y < h else { continue }
        for (x, ch) in row.enumerated() where ch != "." {
            let gx = x + hdx
            if gx >= 0 && gx < w { grid[y][gx] = ch }
        }
    }
    // eye, nostril and mouth (head-left: the face is at column 0)
    func put(_ x: Int, _ y: Int, _ ch: Character) { let gx = x + hdx, gy = y + top; if gx >= 0 && gx < w && gy >= 0 && gy < h { grid[gy][gx] = ch } }
    switch p.mouth {
    case .closed: put(5, 5, "K"); put(6, 5, "K")
    case .open, .tongue: put(5, 5, "K"); put(6, 5, "T"); put(6, 6, "T")
    }
    let front0 = at(4 + hdx) + 1
    if p.prop == .book { drawBook(&c, x: front0 - 9, y: g - 4, turn: p.turn) }    // under its chin: it reads over the pages
    blit(grid, dy: p.bob)
    let ex = at(6 + hdx), ey = oy + top + 2 + p.bob
    switch p.eyes {
    case .open, .up: c.rect(ex - 1, ey + (p.eyes == .up ? -1 : 0), 2, 2, .eye); c.set(ex - 1, ey + (p.eyes == .up ? -1 : 0), .eyeHi)
    case .wide: c.rect(ex - 1, ey - 1, 2, 3, .eye); c.set(ex - 1, ey - 1, .eyeHi)
    case .closed, .half, .sad: c.hline(ex - 1, ex, ey + 1, .eye)
    case .happy: c.set(ex - 1, ey + 1, .eye); c.set(ex, ey, .eye); c.set(ex + 1, ey + 1, .eye)
    case .angry: c.hline(ex - 1, ex, ey + 1, .eye); c.set(ex, ey, .eye)
    case .dizzy: for (dx, dy) in [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)] { c.set(ex + dx, ey + dy, .eye) }
    }
    if p.blush { c.set(at(8 + hdx), oy + top + 5, .blush) }
    // props, out in front of the face
    let front = at(4 + hdx) + 1
    if p.prop == .laptop { drawLaptop(&c, lx: front - 1, g: g) }
    if p.prop == .popcorn { drawPopcorn(&c, bx: front, g: g) }
    if p.prop == .calendar { drawCalendar(&c, x: front, y: g - 15) }
    if p.prop == .glass { drawGlass(&c, x: p.arm == .toMouth ? front - 2 : front, y: oy + top + (p.arm == .toMouth ? 1 : 3)) }
    return headAnchors(-hdx, hdy + p.bob)
}

// MARK: - Red panda

/// Standing up on its hind legs, like the first reference picture: black chest and legs, the ringed tail out to one side.
/// Arms raised is the red panda's "look how big I am" stance (startled, or squaring up to play); otherwise its front
/// paws hang in front of its chest.
private func drawStandingRedPanda(_ c: inout Canvas, _ sp: Species, _ p: Pose, cx: Int) -> Anchors {
    let q = sp.quad
    let g = c.h - 2
    let sw = Int((sin(p.tail) * 2).rounded())
    ringedTail(&c, [(cx - 2, g - 2), (cx - 7, g - 2), (cx - 11, g - 6), (cx - 11 + sw, g - 12)], 4)
    c.spans(cx, g - 14, [(-3, 3), (-4, 4), (-5, 4), (-5, 5), (-5, 5), (-5, 5), (-5, 5), (-5, 5), (-5, 5), (-5, 5), (-5, 5), (-4, 4), (-4, 4), (-3, 3), (-3, 3)], .mark)
    c.paint(.mark, .body) { x, y in (x <= cx - 5 || x >= cx + 5) && y < g - 6 }        // red fur down the sides
    c.hline(cx - 5, cx - 1, g, .markShade); c.hline(cx + 1, cx + 5, g, .markShade)    // feet
    let hx = cx - 4 + p.headDX, ht = g - 22 + p.headDY
    if p.arm == .raised {
        let up = Int(sin(p.phase * 0.5) > 0 ? 0 : 1)
        c.thick(cx - 3, g - 12, cx - 8, g - 17 - up, 2, .mark); c.set(cx - 8, g - 17 - up, .markShade)
        c.thick(cx + 3, g - 12, cx + 8, g - 17 - up, 2, .mark); c.set(cx + 8, g - 17 - up, .markShade)
    } else {
        c.thick(cx - 3, g - 12, cx - 2, g - 8, 2, .markShade)
        c.thick(cx + 2, g - 12, cx + 3, g - 8, 2, .markShade)
    }
    redPandaHead(&c, hx, ht, p)
    return redPandaAnchors(hx, ht)
}

/// A red panda's head, after the references: big, round and wide, rounded ears with cream rims and dark insides,
/// big white brows over small dark eyes, white cheeks and muzzle, red-brown tear marks running down to a little smile.
/// hx/ht are where a cat's 9-wide head would go; this one is 11 wide, one cell wider each side and one taller.
private let redPandaFace = [
    ".WW.....WW.",
    "WIIW...WIIW",
    "WIOOOOOOOIW",
    "OOOOOOOOOOO",
    "OOWWOOOWWOO",
    "OOOOOOOOOOO",
    "OOOOOOOOOOO",
    "WWBWWNWWBWW",
    "WWWBWWWBWWW",
    ".WWWWWWWWW.",
    "..WWWWWWW..",
]

private func redPandaHead(_ c: inout Canvas, _ hx: Int, _ ht: Int, _ p: Pose) {
    let L = hx - 1, T = ht - 3
    var rows = redPandaFace
    if p.earsFlat || p.outfit.hat.wide {
        // ears back (or under a wide hat): just their cream rims at the sides
        rows[0] = "..........."; rows[1] = "..........."; rows[2] = "WOOOOOOOOOW"
    }
    c.sprite(L, T, rows, ["O": .body, "W": .belly, "I": .inner, "B": .accent, "N": .nose])
    let l = L + 2, r = L + 7, ey = ht + 2
    switch p.eyes {
    case .open:
        c.rect(l, ey, 2, 2, .eye); c.rect(r, ey, 2, 2, .eye); c.set(l, ey, .eyeHi); c.set(r, ey, .eyeHi)
    case .half, .closed:
        c.hline(l, l + 1, ey + 1, .eye); c.hline(r, r + 1, ey + 1, .eye)
    case .up:
        c.rect(l, ey - 1, 2, 2, .eye); c.rect(r, ey - 1, 2, 2, .eye); c.set(l + 1, ey - 1, .eyeHi); c.set(r + 1, ey - 1, .eyeHi)
    case .wide:
        c.rect(l, ey - 1, 2, 3, .eye); c.rect(r, ey - 1, 2, 3, .eye); c.set(l, ey - 1, .eyeHi); c.set(r, ey - 1, .eyeHi)
    case .happy:
        c.set(l - 1, ey + 1, .eye); c.set(l, ey, .eye); c.set(l + 1, ey + 1, .eye)
        c.set(r, ey + 1, .eye); c.set(r + 1, ey, .eye); c.set(r + 2, ey + 1, .eye)
    case .angry:
        c.hline(l, l + 1, ey + 1, .eye); c.hline(r, r + 1, ey + 1, .eye); c.set(l, ey, .eye); c.set(r + 1, ey, .eye)
    case .sad:
        c.hline(l, l + 1, ey + 1, .eye); c.hline(r, r + 1, ey + 1, .eye); c.set(l + 1, ey, .eye); c.set(r, ey, .eye)
    case .dizzy:
        for (dx, dy) in [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)] { c.set(l - 1 + dx, ey - 1 + dy, .eye); c.set(r - 1 + dx, ey - 1 + dy, .eye) }
    default:
        c.rect(l, ey, 2, 2, .eye); c.rect(r, ey, 2, 2, .eye); c.set(l, ey, .eyeHi); c.set(r, ey, .eyeHi)
    }
    // the little smile at the ends of the tear marks
    let my = ht + 6
    switch p.mouth {
    case .closed: c.set(L + 4, my, .accent); c.set(L + 6, my, .accent)
    case .open: c.hline(L + 4, L + 6, my, .mouth); c.set(L + 5, my + 1, .mouth)
    case .tongue: c.set(L + 4, my, .mouth); c.set(L + 6, my, .mouth); c.set(L + 5, my + 1, .tongue)
    }
    if p.blush { c.set(L + 1, ht + 4, .blush); c.set(L + 9, ht + 4, .blush) }
}

private func redPandaAnchors(_ hx: Int, _ ht: Int) -> Anchors {
    Anchors(headX: hx + 4, headTop: ht - 1, headW: 11, eyes: [(hx + 1, ht + 2), (hx + 6, ht + 2)], profile: false, neck: (hx + 4, ht + 8))
}

/// Asleep the way red pandas sleep in the cold: curled up, head down, the ringed tail wrapped round the front and its
/// dark tip laid over the nose. O fur, W white, I ear insides, K lines, B tear marks, R buff rings, T the tail's dark tip,
/// D black paws.
private let redPandaAsleep = [
    ".WW....WW..OOOOOO....",
    "WIIW..WIIW.OOOOOOOO..",
    "OOOOOOOOOOKOOOOOOOOO.",
    "OWWOOOOWWOKOOOOOOOOOR",
    "OKKOOOOKKOKOOOOOOOORR",
    "WBWWNNWWBWKOOOOOOOORO",
    "TTRROOORROOORROOORROO",
    ".TRROOORROOORROOORRO.",
]

private func drawSleepingRedPanda(_ c: inout Canvas, _ p: Pose, cx: Int) -> Anchors {
    let ox = cx - 10, oy = c.h - 2 - (redPandaAsleep.count - 1)
    c.sprite(ox, oy, redPandaAsleep, ["O": .body, "W": .belly, "I": .inner, "K": .outline, "B": .accent, "R": .mark2, "T": .accent, "N": .nose])
    if ![.closed, .half, .happy].contains(p.eyes) {          // waking up: eyes open
        for ex in [ox + 1, ox + 7] { c.hline(ex, ex + 1, oy + 4, .eye); if p.eyes == .wide { c.hline(ex, ex + 1, oy + 3, .eye) } }
    }
    if p.blush { c.set(ox, oy + 5, .blush); c.set(ox + 9, oy + 5, .blush) }
    return Anchors(headX: ox + 5, headTop: oy + 2, headW: 10, eyes: [(ox + 1, oy + 4), (ox + 7, oy + 4)], profile: false, neck: (ox + 5, oy + 5))
}

// MARK: - Parrot

private func parrotWing(_ c: inout Canvas, _ arm: Arm, cx: Int, top: Int) {
    switch arm {
    case .raised:
        c.region(cx - 1, top - 7, [(-6, -4), (-7, -2), (-7, -1), (-6, 0), (-5, 1), (-4, 1), (-3, 1), (-2, 1), (-1, 1)], fill: .wing, edge: .wingDark)
    case .down:
        c.region(cx - 1, top + 3, [(-1, 1), (-2, 1), (-3, 1), (-4, 0), (-5, -1), (-6, -2), (-7, -3), (-7, -5)], fill: .wing, edge: .wingDark)
    case .forward, .scoop, .toMouth, .hold, .tap:
        c.region(cx, top + 3, [(-2, 1), (-2, 2), (-2, 3), (-1, 4), (0, 4)], fill: .wing, edge: .wingDark)
    default:        // folded along its side, the tips over the tail
        c.region(cx, top + 2, [(-3, 0), (-4, 1), (-4, 1), (-4, 1), (-4, 1), (-5, 0), (-5, -1), (-6, -2), (-6, -3)], fill: .wing, edge: .wingDark)
    }
}

/// A parrot, side view facing right: upright, green with a red head and yellow cheek, blue-edged wings,
/// a long blue and red tail and a hooked beak.
private func drawParrot(_ c: inout Canvas, _ p: Pose, cx: Int) -> Anchors {
    let g = c.h - 2
    let st = p.stance
    let sitting = st == .sit || st == .lie || st == .curl
    let airborne = st == .fly || st == .held || st == .umbrella || st == .leap
    let bb = sitting ? g : (airborne ? g - 4 : g - 2)            // bottom row of the body
    let top = bb - 11 + (st == .squash ? 2 : 0) + p.bob

    // tail first, out behind and down to the ground (or trailing, in the air)
    let tip = airborne ? (cx - 12, bb + 4) : (cx - 11, g)
    c.thick(cx - 3, bb - 3, tip.0, tip.1 - 1, 2, .wingDark)
    c.thick(cx - 3, bb - 4, tip.0 + 1, tip.1 - 2, 1, .speculum)
    if !sitting {
        if airborne { c.set(cx - 1, bb + 1, .feet); c.set(cx + 1, bb + 1, .feet) }
        else { for fx in [cx - 1, cx + 2] { c.set(fx, g - 1, .feet); c.hline(fx - 1, fx + 1, g, .feet) } }
    }
    // body: an upright oval, lighter breast
    let widths: [(Int, Int)] = [(-2, 2), (-3, 3), (-4, 3), (-4, 4), (-4, 4), (-4, 4), (-4, 4), (-4, 4), (-4, 3), (-3, 3), (-3, 2), (-2, 1)]
    for (i, w) in widths.enumerated() where top + i <= bb { c.hline(cx + w.0, cx + w.1, top + i, .body) }
    c.paint(.body, .belly) { x, y in x >= cx + 1 && y >= top + 3 && y <= bb - 1 }

    if p.prop == .laptop { drawLaptop(&c, lx: cx + 6, g: g) }
    if p.prop == .popcorn { drawPopcorn(&c, bx: cx + 7, g: g) }
    if p.prop == .calendar { drawCalendar(&c, x: cx + 6, y: top + 1) }
    if p.prop == .book { drawBook(&c, x: cx, y: c.h - 6, turn: p.turn) }
    if p.prop == .glass { drawGlass(&c, x: cx + 6, y: top + 2) }
    if p.prop == .laptop && (p.arm == .tap || p.arm == .forward) {
        // typing: the near wing reaches down to the keys and taps them
        parrotWing(&c, .rest, cx: cx, top: top)
        let tip = (cx + 6, g - (p.arm == .tap ? 2 : 3))
        c.thick(cx, top + 3, tip.0 - 1, tip.1, 2, .wing)
        c.hline(tip.0 - 1, tip.0 + 1, tip.1 + 1, .wingDark)
    } else {
        parrotWing(&c, p.arm, cx: cx, top: top)
    }

    // head, on a short neck; pecking and eating bring it down to the ground in front
    var hx = cx - 1 + max(-3, min(4, p.headDX)), ht = top - 5 + max(-3, min(10, p.headDY))
    if st == .eat { hx = cx + 3 + max(0, p.headDX); ht = g - 6 }
    c.thick(cx - 1, top + 1, hx + 1, ht + 3, 3, .body)
    c.spans(hx, ht, [(1, 4), (0, 5), (0, 5), (0, 5), (1, 4)], .mark)
    c.hline(hx + 1, hx + 2, ht + 3, .accent)                         // yellow cheek
    // a round, shiny eye like the other pets' (a lone dot in a white ring looked like it was staring)
    switch p.eyes {
    case .open, .wide, .up: c.rect(hx + 3, ht + 1, 2, 2, .eye); c.set(hx + 3, ht + 1, .eyeHi)
    case .half: c.hline(hx + 3, hx + 4, ht + 2, .eye)
    default: profileEye(&c, p.eyes, hx + 3, ht + 1)
    }
    // hooked beak
    c.hline(hx + 6, hx + 7, ht + 1, .beak)
    c.hline(hx + 6, hx + 8, ht + 2, .beak)
    if p.mouth == .closed {
        c.set(hx + 8, ht + 3, .beak); c.hline(hx + 6, hx + 7, ht + 3, .beakDark)
    } else {
        c.set(hx + 8, ht + 3, .beak); c.set(hx + 6, ht + 3, .mouth); c.hline(hx + 6, hx + 7, ht + 4, .beakDark)
    }
    if p.blush { c.hline(hx + 2, hx + 3, ht + 3, .blush) }
    return Anchors(headX: hx + 2, headTop: ht, headW: 6, eyes: [(hx + 3, ht + 1)], profile: true, neck: (hx + 2, ht + 5))
}

// MARK: - Outfits & extras

private let hatArt: [Hat: ([String], [Character: Col])] = [
    .topHat: ([".KKKKH.", ".KKKKH.", ".KKKKH.", ".RRRRR.", "HKKKKKH"], ["K": .hatBlack, "H": .hatShine, "R": .hatBand]),
    .crown: (["Y.Y.Y", "YYRYY", "YYYYY"], ["Y": .gold, "R": .ruby]),
    .party: (["..S..", ".SSS.", "..P..", ".PBP.", ".BPB.", "PBPBP"], ["S": .star, "P": .partyPink, "B": .partyBlue]),
    .witch: (["K.......", "KK......", ".KK.....", ".KKK....", ".KKKK...", ".PPPP...", "KKKKKKKK"], ["K": .witch, "P": .witchBand]),
    .cowboy: (["...CCC...", "..CCCCC..", "..DDDDD..", "C.CCCCC.C", ".CCCCCCC."], ["C": .cowboy, "D": .cowboyDark]),
    .bow: (["PP.PP", "PPDPP", "PP.PP"], ["P": .bowPink, "D": .bowDark]),
    .flower: ([".W.", "WYW", ".W."], ["W": .petal, "Y": .popYellow]),
    .santa: (["......RWW", ".....RRWW", "....RRR..", "...RRRR..", "..RRRRRR.", "WWWWWWWWW"], ["R": .hatBand, "W": .white]),
]

/// Narrower side views of the wide hats, for the goose's small profile head (tips flop backwards).
private let hatArtProfile: [Hat: ([String], [Character: Col])] = [
    .santa: (["WW....", "WRR...", ".RRRR.", ".RRRRR", "WWWWWW"], ["R": .hatBand, "W": .white]),
    .witch: (["K.....", "KK....", ".KK...", ".KKK..", ".PPPP.", "KKKKKK"], ["K": .witch, "P": .witchBand]),
    .cowboy: (["..CCC..", ".CCCCC.", ".DDDDD.", "CCCCCCC"], ["C": .cowboy, "D": .cowboyDark]),
    .topHat: ([".KKH.", ".KKH.", ".KKH.", ".RRR.", "HKKKH"], ["K": .hatBlack, "H": .hatShine, "R": .hatBand]),
]

private func drawExtras(_ c: inout Canvas, _ p: Pose, _ a: Anchors) {
    defer { if p.thinking { drawThinking(&c, p, a) } }
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
        let band = o.hat == .none || p.nightcap        // with a hat on, the band goes under it: only the pads show
        if a.profile {
            if band { c.hline(hx - 2, hx + 2, top - 1, .phones) }
            c.rect(hx - 2, top + 1, 2, 3, .phonesPad)
            c.set(hx - 2, top, .phones)
        } else {
            if band { c.hline(hx - half - 1, hx + half + 1, top - 2, .phones) }
            c.rect(hx - half - 1, top - (band ? 1 : 0), 1, band ? 2 : 1, .phones); c.rect(hx + half + 1, top - (band ? 1 : 0), 1, band ? 2 : 1, .phones)
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
    guard o.hat != .none, let (rows, map) = (a.profile ? hatArtProfile[o.hat] : nil) ?? hatArt[o.hat] else { return }
    let w = rows.map { $0.count }.max() ?? 0
    var x0: Int, y0: Int
    switch o.hat {
    case .bow: x0 = a.profile ? hx - 4 : hx + 1; y0 = a.profile ? top - 1 : top - 3
    case .flower: x0 = a.profile ? hx - 1 : hx - half - 1; y0 = a.profile ? top - 2 : top - 3
    default:
        x0 = (a.profile ? hx - 1 : hx) - w / 2
        y0 = top - rows.count
    }
    c.sprite(x0 + a.hatDX, y0, rows, map)
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
    // head (flowing into the body) and big ears; under a hat the ears tip out to the sides so the hat sits on the head
    c.spans(cx, ht, [(-3, 2), (-4, 3), (-5, 4), (-5, 4), (-5, 4), (-5, 4), (-5, 4)], .body)
    let hatted = p.outfit.hat != .none || p.nightcap
    let ears: [(Int, Int)] = hatted ? [(-8, -7), (-7, -5), (-6, -4), (-5, -4)] : [(-4, -4), (-5, -4), (-5, -3), (-5, -3), (-5, -2), (-5, -2)]
    let earTop = hatted ? ht - 1 : ht - 6
    for (i, row) in ears.enumerated() {
        let y = earTop + i
        c.hline(cx + row.0, cx + row.1, y, .body)
        c.hline(cx - 1 - row.1, cx - 1 - row.0, y, .body)
    }
    if hatted { for (dx, dy) in [(-6, 0), (-5, 1)] { c.set(cx + dx, ht + dy, .inner); c.set(cx - 1 - dx, ht + dy, .inner) } }
    else { for y in (ht - 4)...(ht - 2) { c.set(cx - 4, y, .inner); c.set(cx + 3, y, .inner) } }
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
    if p.prop == .book && !flying { drawBook(&c, x: cx - 8, y: g - 4, turn: p.turn) }     // studying on the floor, its big book in front
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
    var p = p
    if sp == .turtle && p.stance == .curl { p.nightcap = false; p.outfit.hat = .none }    // it has its own nightcap
    if p.stance == .front { p.outfit = Outfit(); p.nightcap = false; p.phones = false }   // the close-up: just the face
    let a: Anchors
    switch sp {
    case .goose: a = drawGoose(&c, p, cx: cx)
    case .parrot: a = drawParrot(&c, p, cx: cx)
    case .bat: a = drawBat(&c, p, cx: cx)
    case .turtle: a = drawTurtle(&c, p, cx: cx)
    default: a = drawQuad(&c, sp, p, cx: cx)
    }
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
