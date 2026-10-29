// Snack, toy and butterfly sprites.

import Cocoa

enum ItemKind: String { case fish, bone, milk, bread, cheese, berry, sausage, cookie, ball, yarn, butterfly }

private let sprites: [ItemKind: ([String], [Character: Col])] = [
    .fish: ([
        "....DDD......",
        "..DDDDDD...tt",
        ".fffLLfff.ttt",
        "ffkDffffffft.",
        "DffDfDffffft.",
        ".LLLLLLLL.ttt",
        "..LLLLLL...tt",
    ], ["D": .fishDark, "f": .fish, "L": .fishLight, "k": .outline, "t": .fishDark]),
    .bone: ([
        ".HH......HW.",
        "HWWW....WWWS",
        ".WWHHHHHHWS.",
        ".SWWWWWWWWS.",
        "WWWS....SWSS",
        ".SS......SS.",
    ], ["W": .bone, "S": .boneShade, "H": .boneLight]),
    .milk: ([
        "..SSSS..",
        ".SMMMMS.",
        "SMMMMMMS",
        "MMMMMMMM",
        "MBBBBBBM",
        "MBWWWWBM",
        "MBBBBBBM",
        "MMMMMMMM",
        "MMMMMMMS",
        "SSSSSSSS",
    ], ["S": .milkShade, "M": .milk, "B": .milkBlue, "W": .white]),
    .bread: ([
        "...CCCCCC...",
        ".CCLCCLCCLC.",
        "CCcCCcCCcCCC",
        "CCCCCCCCCCCC",
        "CBBBBBBBBBBC",
        "DDDDDDDDDDDD",
    ], ["C": .crust, "c": .crustDark, "L": .bread, "B": .bread, "D": .crustDark]),
    .cheese: ([
        "......YY..",
        "....YYLYY.",
        "..YYLLYYYY",
        "YYYYYYYYYY",
        "YhYYYYYhYY",
        "YYYYhYYYYY",
        "DDDDDDDDDD",
    ], ["Y": .cheese, "L": .cheeseLight, "h": .cheeseDark, "D": .cheeseDark]),
    .berry: ([
        ".g.g.g.",
        "..GgG..",
        ".rLrrr.",
        "rLyrryr",
        "rrrrrrr",
        ".ryrrD.",
        "..rrD..",
        "...D...",
    ], ["g": .leaf, "G": .leafDark, "r": .berry, "L": .berryLight, "y": .seed, "D": .berryDark]),
    .sausage: ([
        ".SSSSSSSSS.",
        "SLLLLLLLLLS",
        "SSSSSSSSSSS",
        "DSSSSSSSSSD",
        ".DDDDDDDDD.",
    ], ["S": .sausage, "L": .sausageLight, "D": .sausageDark]),
    .cookie: ([
        "...cccc...",
        ".cLLccccc.",
        ".cLkkcccc.",
        "cLcccccckc",
        "cckccccccc",
        "ccccckcccD",
        "ccccccccKD",
        ".cckkcccD.",
        ".ccccckDD.",
        "...cDDD...",
    ], ["c": .cookie, "L": .bread, "k": .choc, "K": .choc, "D": .cookieDark]),
]

/// Butterfly colors: A forewings, D hindwings, B the edges and veins, C spots, E the eyespots on the hindwings.
let butterflyPalettes: [[Col: UInt32]] = [
    [.bfA: 0x2a2632, .bfD: 0x2a2632, .bfB: 0x16131b, .bfC: 0x4f8dff, .bfE: 0x9ccbff],   // black with blue
    [.bfA: 0xf0452e, .bfD: 0xff7a30, .bfB: 0x5a1a12, .bfC: 0xffd9a0, .bfE: 0x2a1410],   // red
    [.bfA: 0x5d5a24, .bfD: 0x6e6a2a, .bfB: 0x2a2812, .bfC: 0xd6e85a, .bfE: 0xf3ff9a],   // olive and lime
    [.bfA: 0x5fe0a8, .bfD: 0x26b2a0, .bfB: 0x174238, .bfC: 0xd8fff0, .bfE: 0x0f6a5c],   // green
    [.bfA: 0xffd23a, .bfD: 0xffae2a, .bfB: 0x3b2d20, .bfC: 0x221a14, .bfE: 0x4f8dff],   // yellow swallowtail
    [.bfA: 0xf28a2a, .bfD: 0xf6a23a, .bfB: 0x26180f, .bfC: 0xffffff, .bfE: 0xffffff],   // monarch
    [.bfA: 0x3fb8ff, .bfD: 0x2f86f0, .bfB: 0x10203a, .bfC: 0xffffff, .bfE: 0xb6f0ff],   // blue morpho
    [.bfA: 0xb06cff, .bfD: 0xff7ec8, .bfB: 0x3a1f52, .bfC: 0xfff0a8, .bfE: 0xffffff],   // purple and pink
]

/// A butterfly's look: one of the presets, or (half the time) a random bright color scheme.
func randomButterflyPalette() -> [Col: UInt32] {
    if Bool.random() { return butterflyPalettes.randomElement()! }
    let h = Double.random(in: 0..<1)
    func hsv(_ h: Double, _ s: Double, _ v: Double) -> UInt32 {
        let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let i = Int(hh), f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i % 6]
        return UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
    }
    let spot = [0xffffff, 0xfff1a0, hsv(h + 0.5, 0.65, 1)].randomElement()!
    return [.bfA: hsv(h, 0.72, 1), .bfD: hsv(h + Double.random(in: -0.12...0.12), 0.8, 0.92),
            .bfB: hsv(h, 0.65, 0.22), .bfC: spot, .bfE: hsv(h + 0.5, 0.75, 1)]
}

/// Wing patterns: spots, veins, two-tone tips, eyespots. Frames: open, half, edge-on, half.
private let butterflyOpen: [[String]] = [
    ["BBB.k.k.BBB", "BAABBkBBAAB", "BACAAkAACAB", "BAAAAkAAAAB", ".BBAAkAABB.", "..BDDkDDB..", ".BDEDkDEDB.", ".BBB.k.BBB."],
    ["BBB.k.k.BBB", "BABBBkBBBAB", "BAABAkABAAB", "BABAAkAABAB", ".BBABkBABB.", "..BDBkBDB..", ".BDDDkDDDB.", ".BBB.k.BBB."],
    ["BBB.k.k.BBB", "BCCBBkBBCCB", "BCAAAkAAACB", "BAAAAkAAAAB", ".BBAAkAABB.", "..BDDkDDB..", ".BDDDkDDDB.", ".BBB.k.BBB."],
    ["BBB.k.k.BBB", "BAABBkBBAAB", "BAAAAkAAAAB", "BACAAkAACAB", ".BBAAkAABB.", ".BDDDkDDDB.", ".BECDkDCEB.", ".BBB.k.BBB."],
]
private let butterflyHalf = ["....k.k....", "..BABkBAB..", "..BACkCAB..", "..BAAkAAB..", "...BAkAB...", "...BDkDB...", "...BEkEB...", "....BkB...."]
private let butterflyEdge = ["....k.k....", ".....k.....", "....BAB....", "....BAB....", "....BDB....", "....BDB....", ".....k.....", "..........."]

/// The water card's glass: fills a step for every glass you've had today (an empty glass shows a sip of water).
func waterGlassImage(_ glasses: Int, of goal: Int) -> NSImage {
    var c = Canvas(14, 16)
    let water = 2 + min(10, Int((Double(glasses) / Double(max(1, goal)) * 10).rounded()))   // rows of water, of 12
    for y in 1...13 {
        let inset = y >= 12 ? y - 11 : 0
        let l = 1 + inset, r = 12 - inset
        if y == 13 { c.hline(l, r, y, .glassEdge); continue }
        c.set(l, y, .glassEdge); c.set(r, y, .glassEdge)
        guard l + 1 <= r - 1 else { continue }
        let wet = y > 13 - water
        c.hline(l + 1, r - 1, y, wet ? (y == 14 - water ? .waterLight : .water) : .glass)     // empty glass is tinted, so the outline stays outside
        if wet && y > 14 - water && y < 11 { c.set(l + 2, y, .white) }        // a glint
    }
    c.outline()
    return c.trimmed(0).image(basePalette, scale: 4)
}

func itemCanvas(_ kind: ItemKind, bites: Int, frame: Int, variant: Int = 0) -> Canvas {
    var c = Canvas(14, 14)
    var rows: [String]
    var map: [Character: Col]
    switch kind {
    case .butterfly:
        let open = butterflyOpen[((variant % butterflyOpen.count) + butterflyOpen.count) % butterflyOpen.count]
        rows = [open, butterflyHalf, butterflyEdge, butterflyHalf][((frame % 4) + 4) % 4]
        map = ["A": .bfA, "B": .bfB, "C": .bfC, "D": .bfD, "E": .bfE, "k": .bfBody]
    case .ball, .yarn:
        let spans = [(2, 5), (1, 6), (0, 7), (0, 7), (0, 7), (0, 7), (1, 6), (2, 5)]
        let f = ((frame % 4) + 4) % 4
        let hl = [(2, 1), (4, 1), (4, 4), (2, 4)][f]
        rows = spans.enumerated().map { r, sp in
            String((0..<8).map { i -> Character in
                guard i >= sp.0 && i <= sp.1 else { return "." }
                if kind == .yarn { return (i + r + f) % 3 == 0 ? "d" : (r <= 1 ? "l" : "r") }
                if (i == hl.0 || i == hl.0 + 1) && (r == hl.1 || r == hl.1 + 1) { return "w" }
                return r >= 6 || i >= 7 ? "d" : "r"
            })
        }
        map = kind == .yarn ? ["r": .yarn, "d": .yarnDark, "l": .yarnLight] : ["r": .ballRed, "d": .ballRedDark, "w": .white]
    default:
        (rows, map) = sprites[kind] ?? ([], [:])
    }
    let sw = rows.map { $0.count }.max() ?? 0, sh = rows.count
    let ox = (14 - sw) / 2, oy = 14 - 1 - sh
    c.sprite(ox, oy, rows, map)
    if kind == .yarn { c.hline(ox + 7, ox + 10, oy + 7, .yarnDark) }
    if bites > 0 {
        for r in 0..<sh {
            let cut = sw - bites * max(2, sw / 4) + (r % 3 == 1 ? 1 : 0)
            if cut < sw { for i in max(0, cut)..<sw { c.set(ox + i, oy + r, .clear) } }
        }
    }
    c.outline()
    return c
}

/// Pixel icons for the menu's buttons, drawn like the snacks (outlined, shaded).
enum Icon { case moon, sun, pin, heart, bolt, bell, roam, anchor, still }

func iconCanvas(_ icon: Icon) -> Canvas {
    var c = Canvas(14, 14)
    func dist(_ x: Int, _ y: Int, _ cx: Double, _ cy: Double) -> Double { hypot(Double(x) - cx, Double(y) - cy) }
    switch icon {
    case .moon:
        // a crescent opening to the right, with a twinkle beside it
        for y in 1..<12 { for x in 1..<11 {
            let inBig = dist(x, y, 5.5, 6.5) <= 5.0, inBite = dist(x, y, 8.6, 5.0) <= 4.3
            guard inBig && !inBite else { continue }
            c.set(x, y, dist(x, y, 8.6, 5.0) <= 5.4 ? .moonShade : .moon)
        } }
        c.set(3, 5, .moonShade); c.set(4, 8, .moonShade)
        for (x, y) in [(11, 1), (10, 2), (11, 2), (12, 2), (11, 3)] { c.set(x, y, .star) }
    case .sun:
        // rays first, joined to the disc so the outline wraps one shape
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            for d in [3.9, 4.8, 5.6] where k % 2 == 0 || d < 5.5 {
                c.set(Int((6.5 + d * cos(a)).rounded(.down)), Int((6.5 + d * sin(a)).rounded(.down)), .sunDark)
            }
        }
        for y in 0..<14 { for x in 0..<14 {
            let d = dist(x, y, 6.5, 6.5)
            if d <= 3.6 { c.set(x, y, x + y >= 15 && d > 1.8 ? .sunDark : .sun) }
        } }
        c.set(5, 4, .white); c.set(4, 5, .white)
    case .bell:
        c.sprite(2, 1, ["....BB....", "...BBBB...", "..BLBBBB..", "..BLBBBB..", "..BLBBBB..", ".BBLBBBBB.", ".BBBBBBBB.",
                        "BBBBBBBBBB", "DDDDDDDDDD", "....CC...."], ["B": .star, "L": .white, "D": .sunDark, "C": .handle])
    case .roam:         // stay in place, off: a paw print, free to wander
        c.sprite(1, 2, ["...XX.XX...", "...XX.XX...", ".XX.....XX.", ".XX.....XX.", "....XXX....", "...XXXXX...",
                        "..XXXXXXX..", "..XXXXXXX..", "...XX.XX..."], ["X": .cookie])
    case .anchor:       // stays put: an anchor
        c.sprite(1, 1, ["....XXX....", "....X.X....", "....XXX....", "..XXXXXXX..", ".....X.....", ".....X.....",
                        ".X...X...X.", ".XX..X..XX.", "..XXXXXXX..", "....XXX...."], ["X": .lapLight])
    case .still:        // completely still: frozen, a snowflake
        c.sprite(1, 1, [".....X.....", "...X.X.X...", "....XXX....", ".X..XXX..X.", "..X..X..X..", "XXXXXXXXXXX",
                        "..X..X..X..", ".X..XXX..X.", "....XXX....", "...X.X.X...", ".....X....."], ["X": .zzz])
    case .heart:
        c.sprite(3, 4, [".HH.HH.", "HWHHHHH", "HHHHHHH", ".HHHHH.", "..HHH..", "...H..."], ["H": .heart, "W": .white])
    case .bolt:
        c.sprite(4, 2, ["....YY", "...YY.", "..YY..", ".YYYYY", "YYYYY.", "...YY.", "..YY..", ".YY...", "YY...."], ["Y": .star])
    case .pin:
        // a map pin: round head with a hole, tapering to a point
        for y in 0..<13 { for x in 0..<13 {
            let head = dist(x, y, 6, 4.6) <= 4.0
            let tail = y >= 6 && y <= 12 && abs(Double(x) - 6) <= 3.6 * Double(12 - y) / 6
            guard head || tail else { continue }
            c.set(x, y, x >= 8 && y >= 3 ? .pinDark : .pin)
        } }
        for y in 3...5 { for x in 5...7 { c.set(x, y, .white) } }
        c.set(4, 2, .berryLight); c.set(3, 3, .berryLight); c.set(3, 4, .berryLight)
    }
    c.outline()
    return c
}
