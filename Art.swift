// Pixel art basics: palette, canvas (with soft auto-shading), pixel font and speech bubbles.

import Cocoa

// MARK: - Palette

enum Col: UInt8, CaseIterable {
    case clear = 0, outline, white,
         // pet coat (overridden per species)
         body, bodyShade, bodyLight, belly, bellyShade, mark, markShade, mark2, accent,
         nose, eye, eyeHi, inner, blush, mouth, tongue,
         wing, wingDark, beak, beakDark, feet, ring, speculum,
         // effects & props
         heart, lapDark, lapLight, screen, popRed, popCream, popYellow,
         star, zzz, sweat, note, ink2,
         umbA, umbB, handle, phones, phonesPad, page, pageRed,
         // outfits
         gold, ruby, hatBlack, hatBand, partyPink, partyBlue, bowPink, bowDark, petal,
         beanie, beanieDark, witch, witchBand, cowboy, cowboyDark, lens, lensPink, frame,
         scarf, scarfStripe, collar, bandana, cap,
         // snacks & toys
         fish, fishDark, fishLight, crust, crustDark, bread, cheese, cheeseDark, cheeseLight,
         berry, berryDark, berryLight, leaf, leafDark, seed, sausage, sausageDark, sausageLight,
         cookie, cookieDark, choc, milk, milkShade, milkBlue, ballRed, ballRedDark,
         yarn, yarnDark, yarnLight, bfA, bfB, bfC, bfBody,
         bone, boneShade, boneLight, moon, moonShade, pin, pinDark, sun, sunDark
}

private let baseHex: [Col: UInt32] = [
    .outline: 0x2b2738, .white: 0xffffff,
    .body: 0xffffff, .bodyShade: 0xe3dfe6, .bodyLight: 0xffffff, .belly: 0xfff8ee, .bellyShade: 0xefe4d6,
    .mark: 0x8a6a5a, .markShade: 0x6e5246, .mark2: 0x4a3f45, .accent: 0xd9a066,
    .nose: 0xf29aa6, .eye: 0x3b2d2f, .eyeHi: 0xffffff, .inner: 0xffb8c4, .blush: 0xffb3b8,
    .mouth: 0x8a3b45, .tongue: 0xff8a9b,
    .wing: 0xeef1f5, .wingDark: 0xa9b3c1, .beak: 0xff9a2e, .beakDark: 0xd36f12, .feet: 0xff9a2e,
    .ring: 0xffffff, .speculum: 0x4f7be0,
    .heart: 0xff5f80, .lapDark: 0x4b5161, .lapLight: 0x9aa3b5, .screen: 0x8fe3ff,
    .popRed: 0xe5504f, .popCream: 0xfff4d6, .popYellow: 0xffcf4a,
    .star: 0xffe066, .zzz: 0x9fb0ff, .sweat: 0x7cc8ff, .note: 0xa57cff, .ink2: 0x7a6f7e,
    .umbA: 0xff7f9b, .umbB: 0xfff0f5, .handle: 0x7a5236, .phones: 0x4a4458, .phonesPad: 0xff7fb2,
    .page: 0xfffaf2, .pageRed: 0xe5504f,
    .gold: 0xffd23f, .ruby: 0xff4566, .hatBlack: 0x3a3340, .hatBand: 0xe5504f, .partyPink: 0xff8fbf,
    .partyBlue: 0x7ccbff, .bowPink: 0xff9cc6, .bowDark: 0xe0609e, .petal: 0xffd9ea, .beanie: 0x79c9a8,
    .beanieDark: 0x56a585, .witch: 0x60468f, .witchBand: 0xffaa47, .cowboy: 0xb9824e, .cowboyDark: 0x8a5c35,
    .lens: 0x2c2632, .lensPink: 0xff6aa8, .frame: 0x3b3346, .scarf: 0xe8565a, .scarfStripe: 0xfff4e0,
    .collar: 0xe8565a, .bandana: 0x6a95ef, .cap: 0x6a84e0,
    .fish: 0x8fb9d9, .fishDark: 0x5f88b0, .fishLight: 0xd3e8f5, .crust: 0xc98a45, .crustDark: 0x9c6532,
    .bread: 0xf5d7a1, .cheese: 0xffd25e, .cheeseDark: 0xe0a93a, .cheeseLight: 0xffe9a6,
    .berry: 0xf2545b, .berryDark: 0xc23a45, .berryLight: 0xff8a8a, .leaf: 0x6cbf5a, .leafDark: 0x3f9447,
    .seed: 0xffefa8, .sausage: 0xc9634a, .sausageDark: 0x9c4433, .sausageLight: 0xe8917a,
    .cookie: 0xdca162, .cookieDark: 0xb87b42, .choc: 0x5e3b28, .milk: 0xfbfbf7, .milkShade: 0xdcdcd6,
    .milkBlue: 0x6f9be0, .ballRed: 0xff6b6b, .ballRedDark: 0xd64c55,
    .yarn: 0xff9fca, .yarnDark: 0xd9689f, .yarnLight: 0xffcde3,
    .bfA: 0xff9a3d, .bfB: 0x3d5ea8, .bfC: 0xfff3e0, .bfBody: 0x3b2d2f,
    .bone: 0xf4ecdc, .boneShade: 0xcfc2a8, .boneLight: 0xffffff, .moon: 0xfff0b0, .moonShade: 0xe2c56a,
    .pin: 0xe5534b, .pinDark: 0xb03a3a, .sun: 0xffd04a, .sunDark: 0xf0a030,
]

func cgColor(_ h: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255,
            blue: CGFloat(h & 0xff) / 255, alpha: 1)
}

func makePalette(_ overrides: [Col: UInt32] = [:]) -> [CGColor] {
    Col.allCases.map { cgColor(overrides[$0] ?? baseHex[$0] ?? 0xff00ff) }
}

let basePalette = makePalette()

/// The same colors in shades of gray, for the black-and-white panel.
func grayPalette(_ pal: [CGColor]) -> [CGColor] {
    pal.map { c in
        let k = c.components ?? [0, 0, 0, 1]
        let l = k.count >= 3 ? 0.299 * k[0] + 0.587 * k[1] + 0.114 * k[2] : k[0]
        return CGColor(srgbRed: l, green: l, blue: l, alpha: 1)
    }
}

/// Which colors get a darker bottom edge and a lighter top edge.
let petShading: [UInt8: (UInt8, UInt8)] = [
    Col.body.rawValue: (Col.bodyShade.rawValue, Col.bodyLight.rawValue),
    Col.belly.rawValue: (Col.bellyShade.rawValue, Col.belly.rawValue),
    Col.mark.rawValue: (Col.markShade.rawValue, Col.mark.rawValue),
    Col.wing.rawValue: (Col.wingDark.rawValue, Col.wing.rawValue),
]

// MARK: - Pixel canvas

struct Canvas {
    let w: Int, h: Int
    var px: [UInt8]

    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        px = .init(repeating: 0, count: w * h)
    }

    @inline(__always) func get(_ x: Int, _ y: Int) -> UInt8 {
        (x < 0 || y < 0 || x >= w || y >= h) ? 0 : px[y * w + x]
    }

    @inline(__always) mutating func set(_ x: Int, _ y: Int, _ c: Col) {
        guard x >= 0, y >= 0, x < w, y < h else { return }
        px[y * w + x] = c.rawValue
    }

    mutating func hline(_ x0: Int, _ x1: Int, _ y: Int, _ c: Col) {
        let lo = max(0, min(x0, x1)), hi = min(w - 1, max(x0, x1))
        guard y >= 0, y < h, lo <= hi else { return }
        for x in lo...hi { px[y * w + x] = c.rawValue }
    }

    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: Col) {
        guard rw > 0, rh > 0 else { return }
        for yy in y..<(y + rh) { hline(x, x + rw - 1, yy, c) }
    }

    mutating func spans(_ ox: Int, _ oy: Int, _ s: [(Int, Int)], _ c: Col) {
        for (r, sp) in s.enumerated() { hline(ox + sp.0, ox + sp.1, oy + r, c) }
    }

    /// Fills rows of spans (relative to ox, starting at row oy); boundary cells get `edge`.
    mutating func region(_ ox: Int, _ oy: Int, _ s: [(Int, Int)], fill: Col, edge: Col) {
        func inside(_ x: Int, _ y: Int) -> Bool {
            let r = y - oy
            guard r >= 0, r < s.count else { return false }
            return x >= ox + s[r].0 && x <= ox + s[r].1
        }
        for (r, sp) in s.enumerated() {
            let y = oy + r
            for x in (ox + sp.0)...(ox + sp.1) {
                let e = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
                set(x, y, e ? edge : fill)
            }
        }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Col) {
        let y0 = Int((cy - ry).rounded(.up)), y1 = Int((cy + ry).rounded(.down))
        guard y0 <= y1 else { return }
        for y in y0...y1 {
            let dy = (Double(y) - cy) / ry
            let hw = rx * (1 - dy * dy).squareRoot()
            let a = Int((cx - hw).rounded()), b = Int((cx + hw).rounded())
            if a <= b { hline(a, b, y, c) }
        }
    }

    /// Rounded rectangle with pixel-art corners.
    mutating func blob(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, r: Int, _ c: Col) {
        guard y0 <= y1 else { return }
        for y in y0...y1 {
            let d = min(y - y0, y1 - y)
            var inset = 0
            if d < r {
                let k = Double(r - d)
                inset = r - Int((Double(r * r) - k * k).squareRoot().rounded())
            }
            hline(x0 + inset, x1 - inset, y, c)
        }
    }

    mutating func sprite(_ x: Int, _ y: Int, _ rows: [String], _ map: [Character: Col]) {
        for (r, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                if let c = map[ch] { set(x + i, y + r, c) }
            }
        }
    }

    /// Recolors cells of one color inside a rule.
    mutating func paint(_ from: Col, _ to: Col, where rule: (Int, Int) -> Bool) {
        for y in 0..<h {
            for x in 0..<w where px[y * w + x] == from.rawValue && rule(x, y) { px[y * w + x] = to.rawValue }
        }
    }

    /// Paints `to` over any drawn coat cell (body/belly/mark) inside the rule.
    mutating func patch(_ to: Col, where rule: (Int, Int) -> Bool) {
        let coat: Set<UInt8> = [Col.body.rawValue, Col.belly.rawValue, Col.mark.rawValue, Col.mark2.rawValue]
        for y in 0..<h {
            for x in 0..<w where coat.contains(px[y * w + x]) && rule(x, y) { px[y * w + x] = to.rawValue }
        }
    }

    /// A pixel line `t` cells thick, filled as connected runs.
    mutating func thick(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ t: Int, _ c: Col) {
        let dx = x1 - x0, dy = y1 - y0
        if abs(dy) >= abs(dx) {
            let n = abs(dy)
            if n == 0 { rect(x0, y0, t, t, c); return }
            for i in 0...n {
                let y = y0 + (dy > 0 ? i : -i)
                let xa = x0 + Int((Double(dx) * Double(i) / Double(n)).rounded())
                let xb = x0 + Int((Double(dx) * Double(min(i + 1, n)) / Double(n)).rounded())
                hline(min(xa, xb), max(xa, xb) + t - 1, y, c)
            }
        } else {
            let n = abs(dx)
            for i in 0...n {
                let x = x0 + (dx > 0 ? i : -i)
                let ya = y0 + Int((Double(dy) * Double(i) / Double(n)).rounded())
                let yb = y0 + Int((Double(dy) * Double(min(i + 1, n)) / Double(n)).rounded())
                for y in min(ya, yb)...(max(ya, yb) + t - 1) { set(x, y, c) }
            }
        }
    }

    mutating func polyline(_ pts: [(Int, Int)], _ t: Int, _ c: Col) {
        for i in 0..<(pts.count - 1) { thick(pts[i].0, pts[i].1, pts[i + 1].0, pts[i + 1].1, t, c) }
    }

    mutating func mirror(around m: Int) {
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let v = px[y * w + x]
                let nx = 2 * m - x
                if v != 0, nx >= 0, nx < w { out[y * w + nx] = v }
            }
        }
        px = out
    }

    /// Upside down, resting on the same bottom row (for a dog rolling over).
    mutating func flipV() {
        guard let b = bounds() else { return }
        var out = [UInt8](repeating: 0, count: w * h)
        for y in b.1...b.3 {
            let ny = b.1 + b.3 - y
            for x in 0..<w { out[ny * w + x] = px[y * w + x] }
        }
        px = out
    }

    /// Soft volume: darker bottom edges, lighter top edges.
    mutating func shade(_ map: [UInt8: (UInt8, UInt8)] = petShading) {
        var out = px
        for y in 0..<h {
            for x in 0..<w {
                let v = px[y * w + x]
                guard v != 0, let (dark, light) = map[v] else { continue }
                if get(x, y + 1) == 0 || (get(x, y + 2) == 0 && get(x, y + 1) == v && get(x - 1, y + 1) != 0 && get(x + 1, y + 1) != 0 && y % 2 == 0 && x % 2 == 0) {
                    out[y * w + x] = dark
                } else if get(x, y - 1) == 0 {
                    out[y * w + x] = light
                }
            }
        }
        px = out
    }

    /// Adds a 1-cell outline around everything drawn.
    mutating func outline(_ c: Col = .outline) {
        var out = px
        for y in 0..<h {
            for x in 0..<w where px[y * w + x] == 0 {
                if get(x - 1, y) != 0 || get(x + 1, y) != 0 || get(x, y - 1) != 0 || get(x, y + 1) != 0 {
                    out[y * w + x] = c.rawValue
                }
            }
        }
        px = out
    }

    /// (minX, minY, maxX, maxY) of drawn cells.
    func bounds() -> (Int, Int, Int, Int)? {
        var a = w, b = h, c = -1, d = -1
        for y in 0..<h {
            for x in 0..<w where px[y * w + x] != 0 {
                if x < a { a = x }
                if x > c { c = x }
                if y < b { b = y }
                d = y
            }
        }
        return c < 0 ? nil : (a, b, c, d)
    }

    func cropped(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Canvas {
        var out = Canvas(max(1, x1 - x0 + 1), max(1, y1 - y0 + 1))
        for y in 0..<out.h { for x in 0..<out.w { out.px[y * out.w + x] = get(x0 + x, y0 + y) } }
        return out
    }

    func trimmed(_ pad: Int = 1) -> Canvas {
        guard let b = bounds() else { return self }
        return cropped(b.0 - pad, b.1 - pad, b.2 + pad, b.3 + pad)
    }

    /// Draws into a y-down context.
    func draw(_ ctx: CGContext, _ ox: CGFloat, _ oy: CGFloat, _ s: CGFloat, _ pal: [CGColor] = basePalette) {
        var buckets = [[CGRect]](repeating: [], count: pal.count)
        for y in 0..<h {
            var x = 0
            while x < w {
                let v = px[y * w + x]
                if v == 0 { x += 1; continue }
                var run = 1
                while x + run < w && px[y * w + x + run] == v { run += 1 }
                buckets[Int(v)].append(CGRect(x: ox + CGFloat(x) * s, y: oy + CGFloat(y) * s,
                                              width: CGFloat(run) * s, height: s))
                x += run
            }
        }
        for (i, rects) in buckets.enumerated() where !rects.isEmpty {
            ctx.setFillColor(pal[i])
            ctx.fill(rects)
        }
    }

    func image(_ pal: [CGColor] = basePalette, scale: Int = 1) -> NSImage {
        let W = w * scale, H = h * scale
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage() }
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx, 0, 0, CGFloat(scale), pal)
        guard let cg = ctx.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: W, height: H))
    }
}

// MARK: - Pixel font

let glyphs: [Character: [String]] = [
    "A": [".X.", "X.X", "XXX", "X.X", "X.X"], "B": ["XX.", "X.X", "XX.", "X.X", "XX."],
    "C": [".XX", "X..", "X..", "X..", ".XX"], "D": ["XX.", "X.X", "X.X", "X.X", "XX."],
    "E": ["XXX", "X..", "XX.", "X..", "XXX"], "F": ["XXX", "X..", "XX.", "X..", "X.."],
    "G": [".XX", "X..", "X.X", "X.X", ".XX"], "H": ["X.X", "X.X", "XXX", "X.X", "X.X"],
    "I": ["XXX", ".X.", ".X.", ".X.", "XXX"], "J": ["..X", "..X", "..X", "X.X", ".X."],
    "K": ["X.X", "X.X", "XX.", "X.X", "X.X"], "L": ["X..", "X..", "X..", "X..", "XXX"],
    "M": ["X...X", "XX.XX", "X.X.X", "X...X", "X...X"], "N": ["X..X", "XX.X", "X.XX", "X..X", "X..X"],
    "O": [".X.", "X.X", "X.X", "X.X", ".X."], "P": ["XX.", "X.X", "XX.", "X..", "X.."],
    "Q": [".X.", "X.X", "X.X", "XX.", ".XX"], "R": ["XX.", "X.X", "XX.", "X.X", "X.X"],
    "S": [".XX", "X..", ".X.", "..X", "XX."], "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
    "U": ["X.X", "X.X", "X.X", "X.X", "XXX"], "V": ["X.X", "X.X", "X.X", "X.X", ".X."],
    "W": ["X...X", "X...X", "X.X.X", "XX.XX", "X...X"], "X": ["X.X", "X.X", ".X.", "X.X", "X.X"],
    "Y": ["X.X", "X.X", ".X.", ".X.", ".X."], "Z": ["XXX", "..X", ".X.", "X..", "XXX"],
    "0": ["XXX", "X.X", "X.X", "X.X", "XXX"], "1": [".X.", "XX.", ".X.", ".X.", "XXX"],
    "2": ["XX.", "..X", ".X.", "X..", "XXX"], "3": ["XX.", "..X", ".X.", "..X", "XX."],
    "4": ["X.X", "X.X", "XXX", "..X", "..X"], "5": ["XXX", "X..", "XX.", "..X", "XX."],
    "6": [".XX", "X..", "XXX", "X.X", "XXX"], "7": ["XXX", "..X", ".X.", ".X.", ".X."],
    "8": ["XXX", "X.X", "XXX", "X.X", "XXX"], "9": ["XXX", "X.X", "XXX", "..X", "XX."],
    "!": ["X", "X", "X", ".", "X"], "?": ["XX.", "..X", ".X.", "...", ".X."],
    ".": [".", ".", ".", ".", "X"], ",": ["..", "..", "..", ".X", "X."],
    ":": [".", "X", ".", "X", "."], "-": ["...", "...", "XXX", "...", "..."],
    "+": ["...", ".X.", "XXX", ".X.", "..."], "/": ["..X", "..X", ".X.", "X..", "X.."],
    "'": ["X", "X", ".", ".", "."], "~": ["....", ".X.X", "X.X.", "....", "...."],
    "&": [".X..", "X.X.", ".X..", "X.XX", ".XX."], "(": [".X", "X.", "X.", "X.", ".X"], ")": ["X.", ".X", ".X", ".X", "X."],
    " ": ["..", "..", "..", "..", ".."], "♥": [".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."],
    "♪": [".XXX", ".X.X", ".X..", "XX..", "XX.."],
]

func sanitize(_ s: String) -> String {
    let folded = s.folding(options: [.diacriticInsensitive], locale: nil).uppercased()
    return String(folded.filter { glyphs[$0] != nil })
}

func textWidth(_ s: String) -> Int {
    var w = 0
    for ch in s { w += (glyphs[ch]?.first?.count ?? 3) + 1 }
    return max(0, w - 1)
}

func drawText(_ s: String, _ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ px: CGFloat, _ col: CGColor) {
    ctx.setFillColor(col)
    var cx = x
    for ch in s {
        let g = glyphs[ch] ?? glyphs["?"]!
        var rects: [CGRect] = []
        for (r, row) in g.enumerated() {
            for (i, c) in row.enumerated() where c == "X" {
                rects.append(CGRect(x: cx + CGFloat(i) * px, y: y + CGFloat(r) * px, width: px, height: px))
            }
        }
        ctx.fill(rects)
        cx += CGFloat((g.first?.count ?? 3) + 1) * px
    }
}

/// Size of a bubble (without its tail) in points.
func bubbleSize(_ lines: [String], px: CGFloat) -> CGSize {
    let tw = lines.map { textWidth($0) }.max() ?? 0
    return CGSize(width: CGFloat(tw + 8) * px, height: CGFloat(lines.count * 5 + (lines.count - 1) * 2 + 6) * px)
}

/// Draws a bubble at (bx, by) with its tail at tipX, pointing down (or up when `tailUp`).
func drawBubble(_ ctx: CGContext, _ lines: [String], bx: CGFloat, by: CGFloat, tipX: CGFloat, px: CGFloat, tailUp: Bool) {
    let sz = bubbleSize(lines, px: px)
    let bw = sz.width, bh = sz.height
    let snap = { (v: CGFloat) -> CGFloat in (v / px).rounded() * px }
    let tx = clamp(snap(tipX), bx + 3 * px, bx + bw - 4 * px)
    let ink = basePalette[Int(Col.outline.rawValue)], paper = basePalette[Int(Col.white.rawValue)]
    let t0 = tailUp ? by : by + bh - px
    let dir: CGFloat = tailUp ? -1 : 1
    ctx.setFillColor(ink)
    ctx.fill([CGRect(x: bx + px, y: by, width: bw - 2 * px, height: bh),
              CGRect(x: bx, y: by + px, width: bw, height: bh - 2 * px),
              CGRect(x: tx - 2 * px, y: t0, width: 5 * px, height: px),
              CGRect(x: tx - px, y: t0 + dir * px, width: 3 * px, height: px),
              CGRect(x: tx, y: t0 + dir * 2 * px, width: px, height: px)])
    ctx.setFillColor(paper)
    ctx.fill([CGRect(x: bx + px, y: by + px, width: bw - 2 * px, height: bh - 2 * px),
              CGRect(x: tx - px, y: t0, width: 3 * px, height: px),
              CGRect(x: tx, y: t0 + dir * px, width: px, height: px)])
    for (i, l) in lines.enumerated() {
        let w = CGFloat(textWidth(l)) * px
        drawText(l, ctx, snap(bx + (bw - w) / 2), by + 3 * px + CGFloat(i * 7) * px, px,
                 i == 0 ? ink : basePalette[Int(Col.ink2.rawValue)])
    }
}
