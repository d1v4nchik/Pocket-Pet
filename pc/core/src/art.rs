// Pixel art basics: palette, canvas (with soft auto-shading), pixel font and speech bubbles.
// A line-for-line port of the Mac app's Art.swift, so every pet is drawn cell for cell the same.

use crate::image::Image;

// MARK: - Palette

macro_rules! colors {
    ($($name:ident),* $(,)?) => {
        #[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
        #[repr(u8)]
        pub enum Col { $($name),* }
        impl Col {
            pub const ALL: &'static [Col] = &[$(Col::$name),*];
        }
    };
}

colors! {
    Clear, Outline, White,
    // pet coat (overridden per species)
    Body, BodyShade, BodyLight, Belly, BellyShade, Mark, MarkShade, Mark2, Accent,
    Nose, Eye, EyeHi, Inner, Blush, Mouth, Tongue,
    Wing, WingDark, Beak, BeakDark, Feet, Ring, Speculum,
    // effects & props
    Heart, LapDark, LapLight, Screen, PopRed, PopCream, PopYellow,
    Star, Zzz, Sweat, Note, Ink2,
    UmbA, UmbB, Handle, Phones, PhonesPad, Page, PageRed,
    // outfits
    Gold, Ruby, HatBlack, HatBand, PartyPink, PartyBlue, BowPink, BowDark, Petal,
    Witch, WitchBand, Cowboy, CowboyDark, Lens, LensPink, Frame,
    Scarf, ScarfStripe, Collar, Bandana, Cap,
    // snacks & toys
    Fish, FishDark, FishLight, Crust, CrustDark, Bread, Cheese, CheeseDark, CheeseLight,
    Berry, BerryDark, BerryLight, Leaf, LeafDark, Seed, Sausage, SausageDark, SausageLight,
    Cookie, CookieDark, Choc, Milk, MilkShade, MilkBlue, BallRed, BallRedDark,
    Yarn, YarnDark, YarnLight, BfA, BfB, BfC, BfD, BfE, BfBody,
    Bone, BoneShade, BoneLight, Moon, MoonShade, Pin, PinDark, Sun, SunDark,
    HatShine, Glass, GlassEdge, Water, WaterLight,
    Whisker,                // drawn like the outline, but gets no outline of its own (thin whiskers)
}

pub const NCOL: usize = Col::ALL.len();

impl Col {
    #[inline(always)]
    pub fn raw(self) -> u8 { self as u8 }
}

fn base_hex(c: Col) -> u32 {
    use Col::*;
    match c {
        Clear => 0xff00ff,
        Outline => 0x2b2738, White => 0xffffff,
        Body => 0xffffff, BodyShade => 0xe3dfe6, BodyLight => 0xffffff, Belly => 0xfff8ee, BellyShade => 0xefe4d6,
        Mark => 0x8a6a5a, MarkShade => 0x6e5246, Mark2 => 0x4a3f45, Accent => 0xd9a066,
        Nose => 0xf29aa6, Eye => 0x3b2d2f, EyeHi => 0xffffff, Inner => 0xffb8c4, Blush => 0xffb3b8,
        Mouth => 0x8a3b45, Tongue => 0xff8a9b,
        Wing => 0xeef1f5, WingDark => 0xa9b3c1, Beak => 0xff9a2e, BeakDark => 0xd36f12, Feet => 0xff9a2e,
        Ring => 0xffffff, Speculum => 0x4f7be0,
        Heart => 0xff5f80, LapDark => 0x4b5161, LapLight => 0x9aa3b5, Screen => 0x8fe3ff,
        PopRed => 0xe5504f, PopCream => 0xfff4d6, PopYellow => 0xffcf4a,
        Star => 0xffe066, Zzz => 0x9fb0ff, Sweat => 0x7cc8ff, Note => 0xa57cff, Ink2 => 0x7a6f7e,
        UmbA => 0xff7f9b, UmbB => 0xfff0f5, Handle => 0x7a5236, Phones => 0x4a4458, PhonesPad => 0xff7fb2,
        Page => 0xfffaf2, PageRed => 0xe5504f,
        Gold => 0xffd23f, Ruby => 0xff4566, HatBlack => 0x3a3340, HatBand => 0xe5504f, PartyPink => 0xff8fbf,
        PartyBlue => 0x7ccbff, BowPink => 0xff9cc6, BowDark => 0xe0609e, Petal => 0xffd9ea,
        Witch => 0x7b52c7, WitchBand => 0xffaa47, Cowboy => 0xb9824e, CowboyDark => 0x8a5c35,
        Lens => 0x2c2632, LensPink => 0xff6aa8, Frame => 0x3b3346, Scarf => 0xe8565a, ScarfStripe => 0xfff4e0,
        Collar => 0xe8565a, Bandana => 0x6a95ef, Cap => 0x6a84e0,
        Fish => 0x8fb9d9, FishDark => 0x5f88b0, FishLight => 0xd3e8f5, Crust => 0xc98a45, CrustDark => 0x9c6532,
        Bread => 0xf5d7a1, Cheese => 0xffd25e, CheeseDark => 0xe0a93a, CheeseLight => 0xffe9a6,
        Berry => 0xf2545b, BerryDark => 0xc23a45, BerryLight => 0xff8a8a, Leaf => 0x6cbf5a, LeafDark => 0x3f9447,
        Seed => 0xffefa8, Sausage => 0xc9634a, SausageDark => 0x9c4433, SausageLight => 0xe8917a,
        Cookie => 0xdca162, CookieDark => 0xb87b42, Choc => 0x5e3b28, Milk => 0xfbfbf7, MilkShade => 0xdcdcd6,
        MilkBlue => 0x6f9be0, BallRed => 0xff6b6b, BallRedDark => 0xd64c55,
        Yarn => 0xff9fca, YarnDark => 0xd9689f, YarnLight => 0xffcde3,
        BfA => 0xff9a3d, BfB => 0x3d5ea8, BfC => 0xfff3e0, BfD => 0xff9a3d, BfE => 0xfff3e0, BfBody => 0x3b2d2f,
        Bone => 0xf4ecdc, BoneShade => 0xcfc2a8, BoneLight => 0xffffff, Moon => 0xfff0b0, MoonShade => 0xe2c56a,
        Pin => 0xe5534b, PinDark => 0xb03a3a, Sun => 0xffd04a, SunDark => 0xf0a030,
        HatShine => 0x6c6378, Whisker => 0x2b2738, Glass => 0xeef7ff, GlassEdge => 0x9cc6ea, Water => 0x3d9bf0,
        WaterLight => 0x8fd0ff,
    }
}

/// Opaque colors as 0xRRGGBB, one per `Col`.
pub type Palette = [u32; NCOL];

pub fn make_palette(overrides: &[(Col, u32)]) -> Palette {
    let mut p = [0u32; NCOL];
    for (i, c) in Col::ALL.iter().enumerate() {
        p[i] = overrides.iter().rev().find(|o| o.0 == *c).map(|o| o.1).unwrap_or_else(|| base_hex(*c));
    }
    p
}

pub fn base_palette() -> &'static Palette {
    static P: std::sync::OnceLock<Palette> = std::sync::OnceLock::new();
    P.get_or_init(|| make_palette(&[]))
}

/// The same colors in shades of gray, for the black-and-white panel.
pub fn gray_palette(pal: &Palette) -> Palette {
    let mut out = *pal;
    for v in out.iter_mut() {
        let r = ((*v >> 16) & 0xff) as f64 / 255.0;
        let g = ((*v >> 8) & 0xff) as f64 / 255.0;
        let b = (*v & 0xff) as f64 / 255.0;
        let l = ((0.299 * r + 0.587 * g + 0.114 * b) * 255.0).round().clamp(0.0, 255.0) as u32;
        *v = l << 16 | l << 8 | l;
    }
    out
}

/// Which colors get a darker bottom edge and a lighter top edge.
pub fn pet_shading(v: u8) -> Option<(u8, u8)> {
    use Col::*;
    match v {
        x if x == Body.raw() => Some((BodyShade.raw(), BodyLight.raw())),
        x if x == Belly.raw() => Some((BellyShade.raw(), Belly.raw())),
        x if x == Mark.raw() => Some((MarkShade.raw(), Mark.raw())),
        x if x == Wing.raw() => Some((WingDark.raw(), Wing.raw())),
        _ => None,
    }
}

// MARK: - Pixel canvas

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Canvas {
    pub w: i32,
    pub h: i32,
    pub px: Vec<u8>,
}

/// Swift's `Int(x.rounded())`: halves round away from zero.
#[inline(always)]
pub fn iround(x: f64) -> i32 { x.round() as i32 }

impl Canvas {
    pub fn new(w: i32, h: i32) -> Canvas { Canvas { w, h, px: vec![0; (w * h) as usize] } }

    #[inline(always)]
    pub fn get(&self, x: i32, y: i32) -> u8 {
        if x < 0 || y < 0 || x >= self.w || y >= self.h { 0 } else { self.px[(y * self.w + x) as usize] }
    }

    #[inline(always)]
    pub fn set(&mut self, x: i32, y: i32, c: Col) {
        if x < 0 || y < 0 || x >= self.w || y >= self.h { return; }
        self.px[(y * self.w + x) as usize] = c.raw();
    }

    pub fn hline(&mut self, x0: i32, x1: i32, y: i32, c: Col) {
        let lo = 0.max(x0.min(x1));
        let hi = (self.w - 1).min(x0.max(x1));
        if y < 0 || y >= self.h || lo > hi { return; }
        for x in lo..=hi { self.px[(y * self.w + x) as usize] = c.raw(); }
    }

    pub fn rect(&mut self, x: i32, y: i32, rw: i32, rh: i32, c: Col) {
        if rw <= 0 || rh <= 0 { return; }
        for yy in y..(y + rh) { self.hline(x, x + rw - 1, yy, c); }
    }

    pub fn spans(&mut self, ox: i32, oy: i32, s: &[(i32, i32)], c: Col) {
        for (r, sp) in s.iter().enumerate() { self.hline(ox + sp.0, ox + sp.1, oy + r as i32, c); }
    }

    /// Fills rows of spans (relative to ox, starting at row oy); boundary cells get `edge`.
    pub fn region(&mut self, ox: i32, oy: i32, s: &[(i32, i32)], fill: Col, edge: Col) {
        let inside = |x: i32, y: i32| -> bool {
            let r = y - oy;
            if r < 0 || r >= s.len() as i32 { return false; }
            x >= ox + s[r as usize].0 && x <= ox + s[r as usize].1
        };
        for (r, sp) in s.iter().enumerate() {
            let y = oy + r as i32;
            for x in (ox + sp.0)..=(ox + sp.1) {
                let e = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1);
                self.set(x, y, if e { edge } else { fill });
            }
        }
    }

    pub fn ellipse(&mut self, cx: f64, cy: f64, rx: f64, ry: f64, c: Col) {
        let y0 = (cy - ry).ceil() as i32;
        let y1 = (cy + ry).floor() as i32;
        if y0 > y1 { return; }
        for y in y0..=y1 {
            let dy = (y as f64 - cy) / ry;
            let hw = rx * (1.0 - dy * dy).max(0.0).sqrt();     // rounding can leave a hair below zero at the very edge
            let a = iround(cx - hw);
            let b = iround(cx + hw);
            if a <= b { self.hline(a, b, y, c); }
        }
    }

    /// Rounded rectangle with pixel-art corners.
    pub fn blob(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, r: i32, c: Col) {
        if y0 > y1 { return; }
        for y in y0..=y1 {
            let d = (y - y0).min(y1 - y);
            let mut inset = 0;
            if d < r {
                let k = (r - d) as f64;
                inset = r - iround(((r * r) as f64 - k * k).sqrt());
            }
            self.hline(x0 + inset, x1 - inset, y, c);
        }
    }

    pub fn sprite(&mut self, x: i32, y: i32, rows: &[&str], map: &[(u8, Col)]) {
        for (r, row) in rows.iter().enumerate() {
            for (i, ch) in row.bytes().enumerate() {
                if let Some(m) = map.iter().find(|m| m.0 == ch) { self.set(x + i as i32, y + r as i32, m.1); }
            }
        }
    }

    /// Recolors cells of one color inside a rule.
    pub fn paint(&mut self, from: Col, to: Col, rule: impl Fn(i32, i32) -> bool) {
        for y in 0..self.h {
            for x in 0..self.w {
                let i = (y * self.w + x) as usize;
                if self.px[i] == from.raw() && rule(x, y) { self.px[i] = to.raw(); }
            }
        }
    }

    /// Paints `to` over any drawn coat cell (body/belly/mark) inside the rule.
    pub fn patch(&mut self, to: Col, rule: impl Fn(i32, i32) -> bool) {
        let coat = [Col::Body.raw(), Col::Belly.raw(), Col::Mark.raw(), Col::Mark2.raw()];
        for y in 0..self.h {
            for x in 0..self.w {
                let i = (y * self.w + x) as usize;
                if coat.contains(&self.px[i]) && rule(x, y) { self.px[i] = to.raw(); }
            }
        }
    }

    /// A pixel line `t` cells thick, filled as connected runs.
    pub fn thick(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, t: i32, c: Col) {
        let dx = x1 - x0;
        let dy = y1 - y0;
        if dy.abs() >= dx.abs() {
            let n = dy.abs();
            if n == 0 { self.rect(x0, y0, t, t, c); return; }
            for i in 0..=n {
                let y = y0 + if dy > 0 { i } else { -i };
                let xa = x0 + iround(dx as f64 * i as f64 / n as f64);
                let xb = x0 + iround(dx as f64 * (i + 1).min(n) as f64 / n as f64);
                self.hline(xa.min(xb), xa.max(xb) + t - 1, y, c);
            }
        } else {
            let n = dx.abs();
            for i in 0..=n {
                let x = x0 + if dx > 0 { i } else { -i };
                let ya = y0 + iround(dy as f64 * i as f64 / n as f64);
                let yb = y0 + iround(dy as f64 * (i + 1).min(n) as f64 / n as f64);
                for y in ya.min(yb)..=(ya.max(yb) + t - 1) { self.set(x, y, c); }
            }
        }
    }

    pub fn polyline(&mut self, pts: &[(i32, i32)], t: i32, c: Col) {
        for i in 0..(pts.len() - 1) { self.thick(pts[i].0, pts[i].1, pts[i + 1].0, pts[i + 1].1, t, c); }
    }

    pub fn mirror(&mut self, m: i32) {
        let mut out = vec![0u8; (self.w * self.h) as usize];
        for y in 0..self.h {
            for x in 0..self.w {
                let v = self.px[(y * self.w + x) as usize];
                let nx = 2 * m - x;
                if v != 0 && nx >= 0 && nx < self.w { out[(y * self.w + nx) as usize] = v; }
            }
        }
        self.px = out;
    }

    /// Upside down, resting on the same bottom row (for a dog rolling over).
    pub fn flip_v(&mut self) {
        let Some(b) = self.bounds() else { return };
        let mut out = vec![0u8; (self.w * self.h) as usize];
        for y in b.1..=b.3 {
            let ny = b.1 + b.3 - y;
            for x in 0..self.w { out[(ny * self.w + x) as usize] = self.px[(y * self.w + x) as usize]; }
        }
        self.px = out;
    }

    /// Soft volume: darker bottom edges, lighter top edges.
    pub fn shade(&mut self) {
        let mut out = self.px.clone();
        for y in 0..self.h {
            for x in 0..self.w {
                let v = self.px[(y * self.w + x) as usize];
                if v == 0 { continue; }
                let Some((dark, light)) = pet_shading(v) else { continue };
                if self.get(x, y + 1) == 0
                    || (self.get(x, y + 2) == 0 && self.get(x, y + 1) == v && self.get(x - 1, y + 1) != 0
                        && self.get(x + 1, y + 1) != 0 && y % 2 == 0 && x % 2 == 0)
                {
                    out[(y * self.w + x) as usize] = dark;
                } else if self.get(x, y - 1) == 0 {
                    out[(y * self.w + x) as usize] = light;
                }
            }
        }
        self.px = out;
    }

    /// Adds a 1-cell outline around everything drawn (whiskers excepted, so they stay one cell thin).
    pub fn outline(&mut self) { self.outline_with(Col::Outline) }

    pub fn outline_with(&mut self, c: Col) {
        let mut out = self.px.clone();
        let wh = Col::Whisker.raw();
        let solid = |x: i32, y: i32| { let v = self.get(x, y); v != 0 && v != wh };
        for y in 0..self.h {
            for x in 0..self.w {
                if self.px[(y * self.w + x) as usize] != 0 { continue; }
                if solid(x - 1, y) || solid(x + 1, y) || solid(x, y - 1) || solid(x, y + 1) {
                    out[(y * self.w + x) as usize] = c.raw();
                }
            }
        }
        self.px = out;
    }

    /// (minX, minY, maxX, maxY) of drawn cells.
    pub fn bounds(&self) -> Option<(i32, i32, i32, i32)> {
        let (mut a, mut b, mut c, mut d) = (self.w, self.h, -1, -1);
        for y in 0..self.h {
            for x in 0..self.w {
                if self.px[(y * self.w + x) as usize] == 0 { continue; }
                if x < a { a = x }
                if x > c { c = x }
                if y < b { b = y }
                d = y;
            }
        }
        if c < 0 { None } else { Some((a, b, c, d)) }
    }

    pub fn cropped(&self, x0: i32, y0: i32, x1: i32, y1: i32) -> Canvas {
        let mut out = Canvas::new((x1 - x0 + 1).max(1), (y1 - y0 + 1).max(1));
        for y in 0..out.h {
            for x in 0..out.w { out.px[(y * out.w + x) as usize] = self.get(x0 + x, y0 + y); }
        }
        out
    }

    pub fn trimmed(&self, pad: i32) -> Canvas {
        let Some(b) = self.bounds() else { return self.clone() };
        self.cropped(b.0 - pad, b.1 - pad, b.2 + pad, b.3 + pad)
    }

    /// Draws into an image at (ox, oy), `s` pixels per cell.
    pub fn draw(&self, img: &mut Image, ox: i32, oy: i32, s: i32, pal: &Palette) {
        for y in 0..self.h {
            for x in 0..self.w {
                let v = self.px[(y * self.w + x) as usize];
                if v == 0 { continue; }
                img.fill_rect(ox + x * s, oy + y * s, s, s, 0xff00_0000 | pal[v as usize]);
            }
        }
    }

    pub fn image(&self, pal: &Palette, scale: i32) -> Image {
        let mut img = Image::new(self.w * scale, self.h * scale);
        self.draw(&mut img, 0, 0, scale, pal);
        img
    }
}

// MARK: - Pixel font

pub fn glyph(ch: char) -> Option<&'static [&'static str]> {
    Some(match ch {
        'A' => &[".X.", "X.X", "XXX", "X.X", "X.X"], 'B' => &["XX.", "X.X", "XX.", "X.X", "XX."],
        'C' => &[".XX", "X..", "X..", "X..", ".XX"], 'D' => &["XX.", "X.X", "X.X", "X.X", "XX."],
        'E' => &["XXX", "X..", "XX.", "X..", "XXX"], 'F' => &["XXX", "X..", "XX.", "X..", "X.."],
        'G' => &[".XX", "X..", "X.X", "X.X", ".XX"], 'H' => &["X.X", "X.X", "XXX", "X.X", "X.X"],
        'I' => &["XXX", ".X.", ".X.", ".X.", "XXX"], 'J' => &["..X", "..X", "..X", "X.X", ".X."],
        'K' => &["X.X", "X.X", "XX.", "X.X", "X.X"], 'L' => &["X..", "X..", "X..", "X..", "XXX"],
        'M' => &["X...X", "XX.XX", "X.X.X", "X...X", "X...X"], 'N' => &["X..X", "XX.X", "X.XX", "X..X", "X..X"],
        'O' => &[".X.", "X.X", "X.X", "X.X", ".X."], 'P' => &["XX.", "X.X", "XX.", "X..", "X.."],
        'Q' => &[".X.", "X.X", "X.X", "XX.", ".XX"], 'R' => &["XX.", "X.X", "XX.", "X.X", "X.X"],
        'S' => &[".XX", "X..", ".X.", "..X", "XX."], 'T' => &["XXX", ".X.", ".X.", ".X.", ".X."],
        'U' => &["X.X", "X.X", "X.X", "X.X", "XXX"], 'V' => &["X.X", "X.X", "X.X", "X.X", ".X."],
        'W' => &["X...X", "X...X", "X.X.X", "XX.XX", "X...X"], 'X' => &["X.X", "X.X", ".X.", "X.X", "X.X"],
        'Y' => &["X.X", "X.X", ".X.", ".X.", ".X."], 'Z' => &["XXX", "..X", ".X.", "X..", "XXX"],
        '0' => &["XXX", "X.X", "X.X", "X.X", "XXX"], '1' => &[".X.", "XX.", ".X.", ".X.", "XXX"],
        '2' => &["XX.", "..X", ".X.", "X..", "XXX"], '3' => &["XX.", "..X", ".X.", "..X", "XX."],
        '4' => &["X.X", "X.X", "XXX", "..X", "..X"], '5' => &["XXX", "X..", "XX.", "..X", "XX."],
        '6' => &[".XX", "X..", "XXX", "X.X", "XXX"], '7' => &["XXX", "..X", ".X.", ".X.", ".X."],
        '8' => &["XXX", "X.X", "XXX", "X.X", "XXX"], '9' => &["XXX", "X.X", "XXX", "..X", "XX."],
        '!' => &["X", "X", "X", ".", "X"], '?' => &["XX.", "..X", ".X.", "...", ".X."],
        '.' => &[".", ".", ".", ".", "X"], ',' => &["..", "..", "..", ".X", "X."],
        ':' => &[".", "X", ".", "X", "."], '-' => &["...", "...", "XXX", "...", "..."],
        '+' => &["...", ".X.", "XXX", ".X.", "..."], '/' => &["..X", "..X", ".X.", "X..", "X.."],
        '\'' => &["X", "X", ".", ".", "."], '~' => &["....", ".X.X", "X.X.", "....", "...."],
        '&' => &[".X..", "X.X.", ".X..", "X.XX", ".XX."], '(' => &[".X", "X.", "X.", "X.", ".X"], ')' => &["X.", ".X", ".X", ".X", "X."],
        ' ' => &["..", "..", "..", "..", ".."], '♥' => &[".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."],
        '♪' => &[".XXX", ".X.X", ".X..", "XX..", "XX.."],
        _ => return None,
    })
}

/// Latin letters with accents, down to their plain letter (like Swift's diacritic-insensitive folding).
fn fold(ch: char) -> char {
    match ch {
        'À'..='Å' | 'à'..='å' | 'Ā' | 'ā' | 'Ă' | 'ă' | 'Ą' | 'ą' => 'A',
        'Ç' | 'ç' | 'Ć' | 'ć' | 'Č' | 'č' | 'Ĉ' | 'ĉ' | 'Ċ' | 'ċ' => 'C',
        'Ď' | 'ď' => 'D',
        'È'..='Ë' | 'è'..='ë' | 'Ē' | 'ē' | 'Ė' | 'ė' | 'Ę' | 'ę' | 'Ě' | 'ě' => 'E',
        'Ğ' | 'ğ' | 'Ĝ' | 'ĝ' | 'Ġ' | 'ġ' | 'Ģ' | 'ģ' => 'G',
        'Ì'..='Ï' | 'ì'..='ï' | 'Ī' | 'ī' | 'Į' | 'į' | 'İ' => 'I',
        'Ķ' | 'ķ' => 'K',
        'Ĺ' | 'ĺ' | 'Ļ' | 'ļ' | 'Ľ' | 'ľ' => 'L',
        'Ñ' | 'ñ' | 'Ń' | 'ń' | 'Ņ' | 'ņ' | 'Ň' | 'ň' => 'N',
        'Ò'..='Ö' | 'ò'..='ö' | 'Ō' | 'ō' | 'Ő' | 'ő' => 'O',
        'Ŕ' | 'ŕ' | 'Ř' | 'ř' => 'R',
        'Ś' | 'ś' | 'Š' | 'š' | 'Ş' | 'ş' | 'Ș' | 'ș' => 'S',
        'Ť' | 'ť' | 'Ţ' | 'ţ' | 'Ț' | 'ț' => 'T',
        'Ù'..='Ü' | 'ù'..='ü' | 'Ū' | 'ū' | 'Ů' | 'ů' | 'Ű' | 'ű' | 'Ų' | 'ų' => 'U',
        'Ý' | 'ý' | 'ÿ' | 'Ÿ' => 'Y',
        'Ź' | 'ź' | 'Ż' | 'ż' | 'Ž' | 'ž' => 'Z',
        _ => ch,
    }
}

pub fn sanitize(s: &str) -> String {
    s.chars().flat_map(|c| fold(c).to_uppercase()).filter(|c| glyph(*c).is_some()).collect()
}

pub fn text_width(s: &str) -> i32 {
    let mut w = 0;
    for ch in s.chars() { w += glyph(ch).map(|g| g[0].len() as i32).unwrap_or(3) + 1; }
    0.max(w - 1)
}

pub fn draw_text(img: &mut Image, s: &str, x: i32, y: i32, px: i32, col: u32) {
    let mut cx = x;
    for ch in s.chars() {
        let g = glyph(ch).unwrap_or_else(|| glyph('?').unwrap());
        for (r, row) in g.iter().enumerate() {
            for (i, c) in row.bytes().enumerate() {
                if c == b'X' { img.fill_rect(cx + i as i32 * px, y + r as i32 * px, px, px, col); }
            }
        }
        cx += (g[0].len() as i32 + 1) * px;
    }
}

/// Size of a bubble (without its tail) in pixels.
pub fn bubble_size(lines: &[String], px: i32) -> (i32, i32) {
    let tw = lines.iter().map(|l| text_width(l)).max().unwrap_or(0);
    let n = lines.len() as i32;
    ((tw + 8) * px, (n * 5 + (n - 1) * 2 + 6) * px)
}

/// Draws a bubble at (bx, by) with its tail at tipX, pointing down (or up when `tail_up`).
pub fn draw_bubble(img: &mut Image, lines: &[String], bx: i32, by: i32, tip_x: f64, px: i32, tail_up: bool) {
    let (bw, bh) = bubble_size(lines, px);
    let snap = |v: f64| -> i32 { (v / px as f64).round() as i32 * px };
    let tx = snap(tip_x).max(bx + 3 * px).min(bx + bw - 4 * px);
    let pal = base_palette();
    let ink = 0xff00_0000 | pal[Col::Outline as usize];
    let paper = 0xff00_0000 | pal[Col::White as usize];
    let ink2 = 0xff00_0000 | pal[Col::Ink2 as usize];
    let t0 = if tail_up { by } else { by + bh - px };
    let dir = if tail_up { -1 } else { 1 };
    img.fill_rect(bx + px, by, bw - 2 * px, bh, ink);
    img.fill_rect(bx, by + px, bw, bh - 2 * px, ink);
    img.fill_rect(tx - 2 * px, t0, 5 * px, px, ink);
    img.fill_rect(tx - px, t0 + dir * px, 3 * px, px, ink);
    img.fill_rect(tx, t0 + dir * 2 * px, px, px, ink);
    img.fill_rect(bx + px, by + px, bw - 2 * px, bh - 2 * px, paper);
    img.fill_rect(tx - px, t0, 3 * px, px, paper);
    img.fill_rect(tx, t0 + dir * px, px, px, paper);
    for (i, l) in lines.iter().enumerate() {
        let w = text_width(l) * px;
        draw_text(img, l, snap((bx as f64) + (bw - w) as f64 / 2.0), by + 3 * px + i as i32 * 7 * px, px,
                  if i == 0 { ink } else { ink2 });
    }
}
