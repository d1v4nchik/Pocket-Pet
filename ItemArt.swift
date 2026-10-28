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

let butterflyPalettes: [[Col: UInt32]] = [
    [.bfA: 0xff8a3d, .bfB: 0x2e4a8a, .bfC: 0xfff1d6],
    [.bfA: 0xfff8ec, .bfB: 0x4a3f45, .bfC: 0xe2d6c4],
    [.bfA: 0x3b3540, .bfB: 0x1f1a24, .bfC: 0x8fb0c8],
    [.bfA: 0xffd04a, .bfB: 0xb07a2a, .bfC: 0xfff1a8],
    [.bfA: 0xf3e3b8, .bfB: 0x3b3540, .bfC: 0xc9a25a],
    [.bfA: 0xd98a4a, .bfB: 0x5a4038, .bfC: 0xf3d9b0],
]

func itemCanvas(_ kind: ItemKind, bites: Int, frame: Int) -> Canvas {
    var c = Canvas(14, 14)
    var rows: [String]
    var map: [Character: Col]
    switch kind {
    case .butterfly:
        let frames: [[String]] = [
            ["BB.....BB", "BAAB.BAAB", "BAAAkAAAB", ".BACkCAB.", "..BBkBB..", "...B.B..."],
            [".B.....B.", ".BAB.BAB.", "..BAkAB..", "..BCkCB..", "...BkB...", "....B...."],
            ["...B.B...", "...BkB...", "...AkA...", "...BkB...", "....k....", "........."],
            [".B.....B.", ".BAB.BAB.", "..BAkAB..", "..BCkCB..", "...BkB...", "....B...."],
        ]
        rows = frames[((frame % 4) + 4) % 4]
        map = ["A": .bfA, "B": .bfB, "C": .bfC, "k": .bfBody]
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
enum Icon { case moon, sun, pin, heart, bolt, bell }

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
