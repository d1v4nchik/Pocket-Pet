// Snack, toy and butterfly sprites, and the panel's pixel icons. A port of the Mac app's ItemArt.swift.

use crate::art::{base_palette, iround, Canvas, Col, Palette, make_palette};
use crate::image::Image;
use crate::rng;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum ItemKind { Fish, Bone, Milk, Bread, Cheese, Berry, Sausage, Cookie, Ball, Yarn, Butterfly }
impl ItemKind {
    pub const ALL: [ItemKind; 11] = [ItemKind::Fish, ItemKind::Bone, ItemKind::Milk, ItemKind::Bread, ItemKind::Cheese, ItemKind::Berry,
        ItemKind::Sausage, ItemKind::Cookie, ItemKind::Ball, ItemKind::Yarn, ItemKind::Butterfly];
}

type Art = (&'static [&'static str], &'static [(u8, Col)]);

fn sprite(kind: ItemKind) -> Option<Art> {
    use Col::*;
    Some(match kind {
        ItemKind::Fish => (&[
            "....DDD......",
            "..DDDDDD...tt",
            ".fffLLfff.ttt",
            "ffkDffffffft.",
            "DffDfDffffft.",
            ".LLLLLLLL.ttt",
            "..LLLLLL...tt",
        ], &[(b'D', FishDark), (b'f', Fish), (b'L', FishLight), (b'k', Outline), (b't', FishDark)]),
        ItemKind::Bone => (&[
            ".HH......HW.",
            "HWWW....WWWS",
            ".WWHHHHHHWS.",
            ".SWWWWWWWWS.",
            "WWWS....SWSS",
            ".SS......SS.",
        ], &[(b'W', Bone), (b'S', BoneShade), (b'H', BoneLight)]),
        ItemKind::Milk => (&[
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
        ], &[(b'S', MilkShade), (b'M', Milk), (b'B', MilkBlue), (b'W', White)]),
        ItemKind::Bread => (&[
            "...CCCCCC...",
            ".CCLCCLCCLC.",
            "CCcCCcCCcCCC",
            "CCCCCCCCCCCC",
            "CBBBBBBBBBBC",
            "DDDDDDDDDDDD",
        ], &[(b'C', Crust), (b'c', CrustDark), (b'L', Bread), (b'B', Bread), (b'D', CrustDark)]),
        ItemKind::Cheese => (&[
            "......YY..",
            "....YYLYY.",
            "..YYLLYYYY",
            "YYYYYYYYYY",
            "YhYYYYYhYY",
            "YYYYhYYYYY",
            "DDDDDDDDDD",
        ], &[(b'Y', Cheese), (b'L', CheeseLight), (b'h', CheeseDark), (b'D', CheeseDark)]),
        ItemKind::Berry => (&[
            ".g.g.g.",
            "..GgG..",
            ".rLrrr.",
            "rLyrryr",
            "rrrrrrr",
            ".ryrrD.",
            "..rrD..",
            "...D...",
        ], &[(b'g', Leaf), (b'G', LeafDark), (b'r', Berry), (b'L', BerryLight), (b'y', Seed), (b'D', BerryDark)]),
        ItemKind::Sausage => (&[
            ".SSSSSSSSS.",
            "SLLLLLLLLLS",
            "SSSSSSSSSSS",
            "DSSSSSSSSSD",
            ".DDDDDDDDD.",
        ], &[(b'S', Sausage), (b'L', SausageLight), (b'D', SausageDark)]),
        ItemKind::Cookie => (&[
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
        ], &[(b'c', Cookie), (b'L', Bread), (b'k', Choc), (b'K', Choc), (b'D', CookieDark)]),
        _ => return None,
    })
}

/// Butterfly colors: A forewings, D hindwings, B the edges and veins, C spots, E the eyespots on the hindwings.
pub const BUTTERFLY_PALETTES: [[(Col, u32); 5]; 8] = {
    use Col::*;
    [
        [(BfA, 0x2a2632), (BfD, 0x2a2632), (BfB, 0x16131b), (BfC, 0x4f8dff), (BfE, 0x9ccbff)],   // black with blue
        [(BfA, 0xf0452e), (BfD, 0xff7a30), (BfB, 0x5a1a12), (BfC, 0xffd9a0), (BfE, 0x2a1410)],   // red
        [(BfA, 0x5d5a24), (BfD, 0x6e6a2a), (BfB, 0x2a2812), (BfC, 0xd6e85a), (BfE, 0xf3ff9a)],   // olive and lime
        [(BfA, 0x5fe0a8), (BfD, 0x26b2a0), (BfB, 0x174238), (BfC, 0xd8fff0), (BfE, 0x0f6a5c)],   // green
        [(BfA, 0xffd23a), (BfD, 0xffae2a), (BfB, 0x3b2d20), (BfC, 0x221a14), (BfE, 0x4f8dff)],   // yellow swallowtail
        [(BfA, 0xf28a2a), (BfD, 0xf6a23a), (BfB, 0x26180f), (BfC, 0xffffff), (BfE, 0xffffff)],   // monarch
        [(BfA, 0x3fb8ff), (BfD, 0x2f86f0), (BfB, 0x10203a), (BfC, 0xffffff), (BfE, 0xb6f0ff)],   // blue morpho
        [(BfA, 0xb06cff), (BfD, 0xff7ec8), (BfB, 0x3a1f52), (BfC, 0xfff0a8), (BfE, 0xffffff)],   // purple and pink
    ]
};

/// A butterfly's look: one of the presets, or (half the time) a random bright color scheme.
pub fn random_butterfly_palette() -> Palette {
    if rng::coin() { return make_palette(rng::pick(&BUTTERFLY_PALETTES)); }
    let h = rng::unit();
    fn hsv(h: f64, s: f64, v: f64) -> u32 {
        let hh = ((h % 1.0) + 1.0) % 1.0 * 6.0;
        let i = hh as i32;
        let f = hh - i as f64;
        let p = v * (1.0 - s);
        let q = v * (1.0 - s * f);
        let t = v * (1.0 - s * (1.0 - f));
        let (r, g, b) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][(i % 6) as usize];
        ((r * 255.0) as u32) << 16 | ((g * 255.0) as u32) << 8 | (b * 255.0) as u32
    }
    let spot = *rng::pick(&[0xffffff, 0xfff1a0, hsv(h + 0.5, 0.65, 1.0)]);
    make_palette(&[(Col::BfA, hsv(h, 0.72, 1.0)), (Col::BfD, hsv(h + rng::range(-0.12, 0.12), 0.8, 0.92)),
                   (Col::BfB, hsv(h, 0.65, 0.22)), (Col::BfC, spot), (Col::BfE, hsv(h + 0.5, 0.75, 1.0))])
}

/// Wing patterns: spots, veins, two-tone tips, eyespots. Frames: open, half, edge-on, half.
const BUTTERFLY_OPEN: [[&str; 8]; 4] = [
    ["BBB.k.k.BBB", "BAABBkBBAAB", "BACAAkAACAB", "BAAAAkAAAAB", ".BBAAkAABB.", "..BDDkDDB..", ".BDEDkDEDB.", ".BBB.k.BBB."],
    ["BBB.k.k.BBB", "BABBBkBBBAB", "BAABAkABAAB", "BABAAkAABAB", ".BBABkBABB.", "..BDBkBDB..", ".BDDDkDDDB.", ".BBB.k.BBB."],
    ["BBB.k.k.BBB", "BCCBBkBBCCB", "BCAAAkAAACB", "BAAAAkAAAAB", ".BBAAkAABB.", "..BDDkDDB..", ".BDDDkDDDB.", ".BBB.k.BBB."],
    ["BBB.k.k.BBB", "BAABBkBBAAB", "BAAAAkAAAAB", "BACAAkAACAB", ".BBAAkAABB.", ".BDDDkDDDB.", ".BECDkDCEB.", ".BBB.k.BBB."],
];
const BUTTERFLY_HALF: [&str; 8] = ["....k.k....", "..BABkBAB..", "..BACkCAB..", "..BAAkAAB..", "...BAkAB...", "...BDkDB...", "...BEkEB...", "....BkB...."];
const BUTTERFLY_EDGE: [&str; 8] = ["....k.k....", ".....k.....", "....BAB....", "....BAB....", "....BDB....", "....BDB....", ".....k.....", "..........."];

/// The water card's glass: fills a step for every glass you've had today (an empty glass shows a sip of water).
pub fn water_glass_canvas(glasses: i32, goal: i32) -> Canvas {
    let mut c = Canvas::new(14, 16);
    let water = 2 + 10.min(iround(glasses as f64 / 1.max(goal) as f64 * 10.0));   // rows of water, of 12
    for y in 1..=13 {
        let inset = if y >= 12 { y - 11 } else { 0 };
        let l = 1 + inset;
        let r = 12 - inset;
        if y == 13 { c.hline(l, r, y, Col::GlassEdge); continue; }
        c.set(l, y, Col::GlassEdge); c.set(r, y, Col::GlassEdge);
        if l + 1 > r - 1 { continue; }
        let wet = y > 13 - water;
        // empty glass is tinted, so the outline stays outside
        c.hline(l + 1, r - 1, y, if wet { if y == 14 - water { Col::WaterLight } else { Col::Water } } else { Col::Glass });
        if wet && y > 14 - water && y < 11 { c.set(l + 2, y, Col::White); }        // a glint
    }
    c.outline();
    c.trimmed(0)
}

pub fn water_glass_image(glasses: i32, goal: i32) -> Image { water_glass_canvas(glasses, goal).image(base_palette(), 4) }

fn ball_rows(kind: ItemKind, frame: i32) -> Vec<String> {
    let spans = [(2, 5), (1, 6), (0, 7), (0, 7), (0, 7), (0, 7), (1, 6), (2, 5)];
    let f = ((frame % 4) + 4) % 4;
    let hl = [(2, 1), (4, 1), (4, 4), (2, 4)][f as usize];
    spans.iter().enumerate().map(|(r, sp)| {
        let r = r as i32;
        (0..8).map(|i: i32| -> char {
            if !(i >= sp.0 && i <= sp.1) { return '.'; }
            if kind == ItemKind::Yarn { return if (i + r + f) % 3 == 0 { 'd' } else if r <= 1 { 'l' } else { 'r' }; }
            if (i == hl.0 || i == hl.0 + 1) && (r == hl.1 || r == hl.1 + 1) { return 'w'; }
            if r >= 6 || i >= 7 { 'd' } else { 'r' }
        }).collect()
    }).collect()
}

pub fn item_canvas(kind: ItemKind, bites: i32, frame: i32, variant: i32) -> Canvas {
    let mut c = Canvas::new(14, 14);
    let owned: Vec<String>;
    let rows: Vec<&str>;
    let map: &[(u8, Col)];
    match kind {
        ItemKind::Butterfly => {
            let n = BUTTERFLY_OPEN.len() as i32;
            let open = &BUTTERFLY_OPEN[(((variant % n) + n) % n) as usize];
            rows = [open, &BUTTERFLY_HALF, &BUTTERFLY_EDGE, &BUTTERFLY_HALF][(((frame % 4) + 4) % 4) as usize].to_vec();
            map = &[(b'A', Col::BfA), (b'B', Col::BfB), (b'C', Col::BfC), (b'D', Col::BfD), (b'E', Col::BfE), (b'k', Col::BfBody)];
        }
        ItemKind::Ball | ItemKind::Yarn => {
            owned = ball_rows(kind, frame);
            rows = owned.iter().map(|s| s.as_str()).collect();
            map = if kind == ItemKind::Yarn { &[(b'r', Col::Yarn), (b'd', Col::YarnDark), (b'l', Col::YarnLight)] }
                  else { &[(b'r', Col::BallRed), (b'd', Col::BallRedDark), (b'w', Col::White)] };
        }
        _ => {
            let (r, m) = sprite(kind).unwrap_or((&[], &[]));
            rows = r.to_vec();
            map = m;
        }
    }
    let sw = rows.iter().map(|r| r.len() as i32).max().unwrap_or(0);
    let sh = rows.len() as i32;
    let ox = (14 - sw) / 2;
    let oy = 14 - 1 - sh;
    c.sprite(ox, oy, &rows, map);
    if kind == ItemKind::Yarn { c.hline(ox + 7, ox + 10, oy + 7, Col::YarnDark); }
    if bites > 0 {
        for r in 0..sh {
            let cut = sw - bites * 2.max(sw / 4) + if r % 3 == 1 { 1 } else { 0 };
            if cut < sw { for i in 0.max(cut)..sw { c.set(ox + i, oy + r, Col::Clear); } }
        }
    }
    c.outline();
    c
}

/// Pixel icons for the menu's buttons, drawn like the snacks (outlined, shaded).
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Icon { Moon, Sun, Pin, Heart, Bolt, Bell }
impl Icon {
    pub const ALL: [Icon; 6] = [Icon::Moon, Icon::Sun, Icon::Pin, Icon::Heart, Icon::Bolt, Icon::Bell];
}

pub fn icon_canvas(icon: Icon) -> Canvas {
    let mut c = Canvas::new(14, 14);
    let dist = |x: i32, y: i32, cx: f64, cy: f64| (x as f64 - cx).hypot(y as f64 - cy);
    match icon {
        Icon::Moon => {
            // a crescent opening to the right, with a twinkle beside it
            for y in 1..12 { for x in 1..11 {
                let in_big = dist(x, y, 5.5, 6.5) <= 5.0;
                let in_bite = dist(x, y, 8.6, 5.0) <= 4.3;
                if !(in_big && !in_bite) { continue; }
                c.set(x, y, if dist(x, y, 8.6, 5.0) <= 5.4 { Col::MoonShade } else { Col::Moon });
            } }
            c.set(3, 5, Col::MoonShade); c.set(4, 8, Col::MoonShade);
            for (x, y) in [(11, 1), (10, 2), (11, 2), (12, 2), (11, 3)] { c.set(x, y, Col::Star); }
        }
        Icon::Sun => {
            // rays first, joined to the disc so the outline wraps one shape
            for k in 0..8 {
                let a = k as f64 * std::f64::consts::PI / 4.0;
                for d in [3.9, 4.8, 5.6] {
                    if !(k % 2 == 0 || d < 5.5) { continue; }
                    c.set((6.5 + d * a.cos()).floor() as i32, (6.5 + d * a.sin()).floor() as i32, Col::SunDark);
                }
            }
            for y in 0..14 { for x in 0..14 {
                let d = dist(x, y, 6.5, 6.5);
                if d <= 3.6 { c.set(x, y, if x + y >= 15 && d > 1.8 { Col::SunDark } else { Col::Sun }); }
            } }
            c.set(5, 4, Col::White); c.set(4, 5, Col::White);
        }
        Icon::Bell => {
            c.sprite(2, 1, &["....BB....", "...BBBB...", "..BLBBBB..", "..BLBBBB..", "..BLBBBB..", ".BBLBBBBB.", ".BBBBBBBB.",
                             "BBBBBBBBBB", "DDDDDDDDDD", "....CC...."], &[(b'B', Col::Star), (b'L', Col::White), (b'D', Col::SunDark), (b'C', Col::Handle)]);
        }
        Icon::Heart => {
            c.sprite(3, 4, &[".HH.HH.", "HWHHHHH", "HHHHHHH", ".HHHHH.", "..HHH..", "...H..."], &[(b'H', Col::Heart), (b'W', Col::White)]);
        }
        Icon::Bolt => {
            c.sprite(4, 2, &["....YY", "...YY.", "..YY..", ".YYYYY", "YYYYY.", "...YY.", "..YY..", ".YY...", "YY...."], &[(b'Y', Col::Star)]);
        }
        Icon::Pin => {
            // a map pin: round head with a hole, tapering to a point
            for y in 0..13 { for x in 0..13 {
                let head = dist(x, y, 6.0, 4.6) <= 4.0;
                let tail = (6..=12).contains(&y) && (x as f64 - 6.0).abs() <= 3.6 * (12 - y) as f64 / 6.0;
                if !(head || tail) { continue; }
                c.set(x, y, if x >= 8 && y >= 3 { Col::PinDark } else { Col::Pin });
            } }
            for y in 3..=5 { for x in 5..=7 { c.set(x, y, Col::White); } }
            c.set(4, 2, Col::BerryLight); c.set(3, 3, Col::BerryLight); c.set(3, 4, Col::BerryLight);
        }
    }
    c.outline();
    c
}
