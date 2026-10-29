// The pets themselves: species, coats, and how each one is drawn in every pose.
// Style: slim silhouettes, flat colors and crisp outlines (like the original cats).
// A line-for-line port of the Mac app's Pets.swift.

use crate::art::{iround, Canvas, Col};
use crate::items::ItemKind;
use crate::rng;
use std::f64::consts::PI;

pub const CANVAS_W: i32 = 64;
pub const CANVAS_H: i32 = 52;

// MARK: - Poses

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Stance {
    Stand, Walk, Sit, Lie, Curl, Stretch, Crouch, Leap, Upright, Eat, Squash,
    Fly,                                    // birds in the air
    Umbrella, Held,                         // seen from the front (gliding down, held up)
}
impl Stance {
    pub const ALL: [Stance; 14] = [Stance::Stand, Stance::Walk, Stance::Sit, Stance::Lie, Stance::Curl, Stance::Stretch,
        Stance::Crouch, Stance::Leap, Stance::Upright, Stance::Eat, Stance::Squash, Stance::Fly, Stance::Umbrella, Stance::Held];
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Eyes { Open, Closed, Happy, Wide, Angry, Dizzy, Sad, Up, Half }
impl Eyes {
    pub const ALL: [Eyes; 9] = [Eyes::Open, Eyes::Closed, Eyes::Happy, Eyes::Wide, Eyes::Angry, Eyes::Dizzy, Eyes::Sad, Eyes::Up, Eyes::Half];
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Mouth { Closed, Open, Tongue }
impl Mouth {
    pub const ALL: [Mouth; 3] = [Mouth::Closed, Mouth::Open, Mouth::Tongue];
}

/// Wing (birds) or front paw (four-legged pets).
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Arm { Rest, Raised, Forward, Tap, Down, Scoop, ToMouth, Lick, Hold }
impl Arm {
    pub const ALL: [Arm; 9] = [Arm::Rest, Arm::Raised, Arm::Forward, Arm::Tap, Arm::Down, Arm::Scoop, Arm::ToMouth, Arm::Lick, Arm::Hold];
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Prop { None, Laptop, Popcorn, Calendar, Glass }
impl Prop {
    pub const ALL: [Prop; 5] = [Prop::None, Prop::Laptop, Prop::Popcorn, Prop::Calendar, Prop::Glass];
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Hat { None, Bow, Flower, Crown, TopHat, Party, Witch, Cowboy, Santa }
impl Hat {
    pub const ALL: [Hat; 9] = [Hat::None, Hat::Bow, Hat::Flower, Hat::Crown, Hat::TopHat, Hat::Party, Hat::Witch, Hat::Cowboy, Hat::Santa];
    /// Wide hats sit on top of the head, so ears tip out to the sides underneath them.
    pub fn wide(self) -> bool { matches!(self, Hat::TopHat | Hat::Witch | Hat::Cowboy | Hat::Santa) }
    pub fn raw(self) -> &'static str {
        ["none", "bow", "flower", "crown", "topHat", "party", "witch", "cowboy", "santa"][self as usize]
    }
    /// Hats that were retired (the beanie) come off instead of losing the whole outfit.
    pub fn from_raw(s: &str) -> Hat { Hat::ALL.iter().copied().find(|h| h.raw() == s).unwrap_or(Hat::None) }
    pub fn title(self) -> &'static str {
        ["No hat", "Bow", "Flower", "Crown", "Top hat", "Party hat", "Witch hat", "Cowboy hat", "Santa hat"][self as usize]
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Glasses { None, Shades, Hearts, Round }
impl Glasses {
    pub const ALL: [Glasses; 4] = [Glasses::None, Glasses::Shades, Glasses::Hearts, Glasses::Round];
    pub fn raw(self) -> &'static str { ["none", "shades", "hearts", "round"][self as usize] }
    pub fn from_raw(s: &str) -> Glasses { Glasses::ALL.iter().copied().find(|h| h.raw() == s).unwrap_or(Glasses::None) }
    pub fn title(self) -> &'static str { ["No glasses", "Shades", "Heart glasses", "Round glasses"][self as usize] }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Neckwear { None, Scarf, Bowtie, Bell, Bandana }
impl Neckwear {
    pub const ALL: [Neckwear; 5] = [Neckwear::None, Neckwear::Scarf, Neckwear::Bowtie, Neckwear::Bell, Neckwear::Bandana];
    pub fn raw(self) -> &'static str { ["none", "scarf", "bowtie", "bell", "bandana"][self as usize] }
    pub fn from_raw(s: &str) -> Neckwear { Neckwear::ALL.iter().copied().find(|h| h.raw() == s).unwrap_or(Neckwear::None) }
    pub fn title(self) -> &'static str { ["Nothing", "Scarf", "Bow tie", "Bell collar", "Bandana"][self as usize] }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, Default)]
pub struct Outfit {
    pub hat: Hat,
    pub glasses: Glasses,
    pub neck: Neckwear,
}
impl Default for Hat { fn default() -> Hat { Hat::None } }
impl Default for Glasses { fn default() -> Glasses { Glasses::None } }
impl Default for Neckwear { fn default() -> Neckwear { Neckwear::None } }

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Pose {
    pub stance: Stance,
    pub phase: f64,          // walk / flap cycle
    pub bob: i32,
    pub head_dx: i32,
    pub head_dy: i32,
    pub eyes: Eyes,
    pub mouth: Mouth,
    pub arm: Arm,
    pub tail: f64,           // tail sway phase
    pub tail_up: bool,
    pub ears_flat: bool,
    pub prop: Prop,
    pub blush: bool,
    pub nightcap: bool,
    pub phones: bool,
    pub wiggle: i32,
    pub outfit: Outfit,
}

impl Default for Pose {
    fn default() -> Pose {
        Pose {
            stance: Stance::Stand, phase: 0.0, bob: 0, head_dx: 0, head_dy: 0, eyes: Eyes::Open, mouth: Mouth::Closed,
            arm: Arm::Rest, tail: 0.0, tail_up: true, ears_flat: false, prop: Prop::None, blush: false, nightcap: false,
            phones: false, wiggle: 0, outfit: Outfit::default(),
        }
    }
}

/// Where the head ended up, so outfits, bubbles and particles can follow it.
#[derive(Clone, Debug)]
pub struct Anchors {
    pub head_x: i32,
    pub head_top: i32,
    pub head_w: i32,
    pub eyes: Vec<(i32, i32)>,     // top-left cell of each eye
    pub profile: bool,             // side-view bird head: one eye, beak to the right
    pub neck: (i32, i32),
    pub hat_dx: i32,               // hats sit further forward (the goose's head-down poses)
}

// MARK: - Species

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Family { Bird, Cat, Dog, Bat }
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Ears { Cat, Flop }
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Tail { Cat, Fluffy, Thin, Brush }       // brush: a fox's big tail with a white tip
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Coat { Tabby, Points, TabbyWhite, Calico, Spots, Fox }

#[derive(Clone, Copy, Debug)]
pub struct QuadSpec {
    pub ears: Ears,
    pub tail: Tail,
    pub coat: Coat,
    pub half: i32,      // body half-length
    pub leg_h: i32,
    pub body_h: i32,
}
impl QuadSpec {
    fn new(ears: Ears, tail: Tail, coat: Coat) -> QuadSpec { QuadSpec { ears, tail, coat, half: 9, leg_h: 4, body_h: 7 } }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Species { Goose, Parrot, Ginger, Siamese, Tuxedo, Calico, Dalmatian, Fox, Bat }

impl Species {
    pub const ALL: [Species; 9] = [Species::Goose, Species::Parrot, Species::Ginger, Species::Siamese, Species::Tuxedo,
        Species::Calico, Species::Dalmatian, Species::Fox, Species::Bat];

    pub fn raw(self) -> &'static str {
        ["goose", "parrot", "ginger", "siamese", "tuxedo", "calico", "dalmatian", "fox", "bat"][self as usize]
    }

    /// Old names from earlier versions carry over.
    pub fn from_raw(raw: &str) -> Species {
        match raw {
            "duck" | "mallard" | "whiteDuck" => Species::Goose,
            "corgi" | "collie" | "aussie" => Species::Dalmatian,
            "weasel" => Species::Ginger,
            "midnight" => Species::Tuxedo,
            "smokey" => Species::Siamese,
            _ => Species::ALL.iter().copied().find(|s| s.raw() == raw).unwrap_or(Species::Goose),
        }
    }

    pub fn family(self) -> Family {
        match self {
            Species::Goose | Species::Parrot => Family::Bird,
            Species::Dalmatian | Species::Fox => Family::Dog,
            Species::Bat => Family::Bat,
            _ => Family::Cat,
        }
    }
    pub fn is_bird(self) -> bool { self.family() == Family::Bird }

    pub fn title(self) -> &'static str {
        match self {
            Species::Goose => "Goose",
            Species::Parrot => "Parrot",
            Species::Ginger => "Ginger cat",
            Species::Siamese => "Siamese",
            Species::Tuxedo => "Tabby cat",        // the case keeps its old name so saved pets carry over
            Species::Calico => "Calico",
            Species::Dalmatian => "Dalmatian",
            Species::Fox => "Fox",
            Species::Bat => "Bat",
        }
    }

    pub fn default_name(self) -> &'static str {
        match self {
            Species::Goose => "Honk",
            Species::Parrot => "Kiwi",
            Species::Ginger => "Mango",
            Species::Siamese => "Mochi",
            Species::Tuxedo => "Pebble",
            Species::Calico => "Patches",
            Species::Dalmatian => "Domino",
            Species::Fox => "Ember",
            Species::Bat => "Luna",
        }
    }

    /// (word, sound)
    pub fn vocal(self) -> (&'static str, &'static str) {
        if self == Species::Parrot { return (*rng::pick(&["HELLO!", "SQUAWK!", "HI THERE", "PRETTY BIRD"]), "squawk"); }
        if self == Species::Fox { return ("YIP", "woof"); }
        match self.family() {
            Family::Bird => ("HONK", "honk"),
            Family::Dog => ("WOOF", "woof"),
            Family::Cat => ("MEOW", "meow"),
            Family::Bat => ("SQUEAK", "chirp"),
        }
    }

    /// Snacks this pet loves the most.
    pub fn favorites(self) -> &'static [ItemKind] {
        if self == Species::Parrot { return &[ItemKind::Berry, ItemKind::Cookie]; }
        if self == Species::Fox { return &[ItemKind::Berry, ItemKind::Sausage, ItemKind::Bone]; }
        match self.family() {
            Family::Bird => &[ItemKind::Bread, ItemKind::Cookie, ItemKind::Berry],
            Family::Cat => &[ItemKind::Fish],
            Family::Dog => &[ItemKind::Bone, ItemKind::Sausage],
            Family::Bat => &[ItemKind::Cookie, ItemKind::Berry],
        }
    }

    pub fn quad(self) -> QuadSpec {
        match self {
            Species::Siamese => QuadSpec::new(Ears::Cat, Tail::Fluffy, Coat::Points),
            Species::Tuxedo => QuadSpec::new(Ears::Cat, Tail::Cat, Coat::TabbyWhite),
            Species::Fox => QuadSpec { half: 9, leg_h: 4, body_h: 6, ..QuadSpec::new(Ears::Cat, Tail::Brush, Coat::Fox) },
            Species::Calico => QuadSpec::new(Ears::Cat, Tail::Cat, Coat::Calico),
            Species::Dalmatian => QuadSpec { half: 9, leg_h: 5, body_h: 6, ..QuadSpec::new(Ears::Flop, Tail::Thin, Coat::Spots) },
            _ => QuadSpec::new(Ears::Cat, Tail::Cat, Coat::Tabby),
        }
    }

    pub fn colors(self) -> &'static [(Col, u32)] {
        use Col::*;
        match self {
            Species::Goose => &[(Body, 0xffffff), (BodyShade, 0xdfe3ea), (Wing, 0xeef1f5), (WingDark, 0xa9b3c1)],
            Species::Ginger => &[(Body, 0xffa04a), (BodyShade, 0xe0823a), (Mark, 0xdd7a2c), (Belly, 0xfff1d8), (Nose, 0xff9db4), (Inner, 0xff9db4)],
            Species::Siamese => &[(Body, 0xf6eee2), (BodyShade, 0xe0d4c4), (Mark, 0x6f5c58), (Belly, 0xfffaf2), (Eye, 0x5fa0e6),
                                  (Nose, 0x5a4846), (Inner, 0x8f7a76)],
            // a grey tabby with a cream blaze, chest and toes
            Species::Tuxedo => &[(Body, 0x7e7168), (BodyShade, 0x6c6058), (Mark, 0x5d5047), (Belly, 0xd8d1b5), (Eye, 0x392c24),
                                 (Nose, 0xe0889a), (Inner, 0xd8d1b5), (Mouth, 0xc9677a), (Tongue, 0xe0889a), (Outline, 0x392c24), (Whisker, 0x392c24)],
            Species::Fox => &[(Body, 0xfd921e), (BodyShade, 0xe27c12), (Mark, 0xfd921e), (Mark2, 0x5b5257), (Belly, 0xffffff),
                              (Eye, 0x2b2738), (Nose, 0x2b2738), (Inner, 0xffffff)],
            // green, with a red head, yellow cheeks and blue flight feathers
            Species::Parrot => &[(Body, 0x5cc24c), (BodyShade, 0x46a33c), (Belly, 0xa9df63), (Mark, 0xea4a3f), (Accent, 0xffd447),
                                 (Wing, 0x4cb047), (WingDark, 0x2f6fd6), (Beak, 0xf2e6cc), (BeakDark, 0x3a3340), (Feet, 0x8d929c),
                                 (Ring, 0xffffff), (Speculum, 0xea4a3f)],
            Species::Calico => &[(Body, 0xffffff), (BodyShade, 0xdfe0e8), (Mark, 0xf4a24a), (Mark2, 0x3b3645), (Belly, 0xffffff)],
            Species::Dalmatian => &[(Body, 0xffffff), (BodyShade, 0xe6e3ee), (Mark, 0x3a3440), (Belly, 0xffffff), (Nose, 0x3a3440)],
            Species::Bat => &[(Body, 0x4f4166), (BodyShade, 0x3d3252), (Wing, 0x6a5785), (WingDark, 0x392e4e), (Belly, 0x6f5f88),
                              (Witch, 0x2a2533),   // a dark witch hat, so it doesn't melt into the purple bat
                              (Inner, 0xf08aac), (Mark, 0x241f2e), (Eye, 0x241f2e), (EyeHi, 0xffffff), (Nose, 0x241f2e), (Outline, 0x18141f)],
        }
    }
}

// MARK: - Props

pub fn draw_laptop(c: &mut Canvas, lx: i32, g: i32) {
    c.thick(lx + 9, g - 2, lx + 11, g - 11, 1, Col::Screen);
    c.thick(lx + 10, g - 1, lx + 12, g - 11, 2, Col::LapDark);
    c.hline(lx, lx + 10, g, Col::LapDark);
    c.hline(lx, lx + 9, g - 1, Col::LapLight);
}

pub fn draw_popcorn(c: &mut Canvas, bx: i32, g: i32) {
    let bt = g - 7;
    let rows = [(0, 6), (0, 6), (0, 6), (1, 5), (1, 5), (1, 5), (1, 5), (1, 5)];
    for (i, sp) in rows.iter().enumerate() {
        for xx in sp.0..=sp.1 { c.set(bx + xx, bt + i as i32, if i == 0 || xx % 2 == 0 { Col::PopRed } else { Col::PopCream }); }
    }
    use Col::{PopCream as C, PopYellow as Y};
    let corn = [(0, -1, C), (1, -1, Y), (2, -1, C), (3, -1, C), (4, -1, Y), (5, -1, C), (6, -1, C), (1, -2, C),
                (2, -2, Y), (4, -2, C), (5, -2, C), (3, -3, C)];
    for (dx, dy, col) in corn { c.set(bx + dx, bt + dy, col); }
}

pub fn draw_calendar(c: &mut Canvas, x: i32, y: i32) {
    c.rect(x, y, 7, 7, Col::Page);
    c.rect(x, y, 7, 2, Col::PageRed);
    c.set(x + 1, y - 1, Col::LapDark); c.set(x + 5, y - 1, Col::LapDark);
    c.hline(x + 1, x + 5, y + 3, Col::LapLight);
    c.hline(x + 1, x + 4, y + 5, Col::LapLight);
}

/// A glass of water, held up for the water reminder.
pub fn draw_glass(c: &mut Canvas, x: i32, y: i32) {
    c.sprite(x, y, &["G...G", "GLLLG", "GWwWG", "GWwWG", "GWWWG", ".GGG."],
             &[(b'G', Col::GlassEdge), (b'L', Col::WaterLight), (b'W', Col::Water), (b'w', Col::White)]);
}

pub fn draw_umbrella(c: &mut Canvas, ux: i32, top: i32, handle_to: (i32, i32)) {
    c.thick(ux, top + 5, handle_to.0, handle_to.1, 1, Col::Handle);
    c.set(ux, top, Col::Handle);
    let rows = [(-2, 2), (-4, 4), (-6, 6), (-7, 7)];
    let stripe = |x: i32| if ((x + 8) / 3) % 2 == 0 { Col::UmbA } else { Col::UmbB };
    for (i, sp) in rows.iter().enumerate() {
        for x in sp.0..=sp.1 { c.set(ux + x, top + 1 + i as i32, stripe(x)); }
    }
    for x in [-7, -6, -5, -1, 0, 1, 5, 6, 7] { c.set(ux + x, top + 5, stripe(x)); }
}

// MARK: - Goose

fn profile_eye(c: &mut Canvas, e: Eyes, ex: i32, ey: i32) {
    match e {
        Eyes::Open | Eyes::Half => c.set(ex, ey, Col::Eye),
        Eyes::Up => c.set(ex + 1, ey - 1, Col::Eye),
        Eyes::Closed => c.hline(ex - 1, ex, ey + 1, Col::Eye),
        Eyes::Happy => { c.set(ex - 1, ey + 1, Col::Eye); c.set(ex, ey, Col::Eye); c.set(ex + 1, ey + 1, Col::Eye); }
        Eyes::Wide => { c.rect(ex, ey, 2, 2, Col::Eye); c.set(ex, ey, Col::EyeHi); }
        Eyes::Angry => { c.set(ex, ey + 1, Col::Eye); c.set(ex, ey, Col::Eye); c.set(ex - 1, ey - 1, Col::Eye); }
        Eyes::Sad => { c.set(ex, ey + 1, Col::Eye); c.set(ex, ey, Col::Eye); c.set(ex + 1, ey - 1, Col::Eye); }
        Eyes::Dizzy => { for (dx, dy) in [(-1, 0), (1, 0), (0, 1), (-1, 2), (1, 2)] { c.set(ex + dx, ey + dy, Col::Eye); } }
    }
}

fn bird_wing(c: &mut Canvas, arm: Arm, cx: i32, r0: i32) {
    let (w, wd) = (Col::Wing, Col::WingDark);
    match arm {
        Arm::Raised => c.region(cx, r0 - 6, &[(-11, -10), (-12, -8), (-12, -6), (-11, -4), (-10, -2), (-9, 0), (-8, 1), (-7, 1), (-5, 0)], w, wd),
        Arm::Forward | Arm::Scoop | Arm::ToMouth | Arm::Hold => c.region(cx, r0 + 3, &[(-6, 3), (-7, 8), (-7, 10), (-6, 9), (-4, 5)], w, wd),
        Arm::Tap => c.region(cx, r0 + 3, &[(-6, 3), (-7, 7), (-7, 8), (-6, 9), (-4, 10), (7, 11), (9, 11)], w, wd),
        Arm::Down => c.region(cx, r0 + 5, &[(-6, 2), (-7, 2), (-7, 1), (-7, 0), (-6, -1), (-6, -2), (-5, -3), (-5, -4)], w, wd),
        _ => c.region(cx, r0 + 2, &[(-6, 0), (-8, 2), (-9, 3), (-9, 3), (-8, 2), (-6, 0)], w, wd),
    }
}

/// Long-necked goose, side view facing right.
fn draw_goose(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let st = p.stance;
    let sitting = matches!(st, Stance::Sit | Stance::Lie | Stance::Curl);
    let airborne = matches!(st, Stance::Fly | Stance::Held | Stance::Umbrella | Stance::Leap);
    let leg_len = if st == Stance::Squash { 1 } else { 3 };
    let bb = if sitting { g } else if airborne { g - 5 } else { g - leg_len - 1 };
    let r0 = bb - 10 + p.bob;

    if st == Stance::Fly {
        c.hline(cx - 7, cx - 5, bb + 1, Col::Feet);
        c.hline(cx - 4, cx - 2, bb + 1, Col::Feet);
    } else if !sitting {
        for (i, lx) in [cx - 3, cx + 1].into_iter().enumerate() {
            if airborne {
                let len = if (p.phase as i64) % 2 == i as i64 { 4 } else { 3 };
                for yy in (bb + 1)..=(bb + len) { c.set(lx, yy, Col::Feet); }
                c.set(lx + 1, bb + len, Col::Feet);
            } else {
                let sv = if st == Stance::Walk { (p.phase + if i == 0 { 0.0 } else { PI }).sin() } else { 0.0 };
                let lifted = sv > 0.5;
                let fx = lx + iround(sv * 1.2);
                let foot_y = if lifted { g - 1 } else { g };
                if foot_y - 1 >= bb + 1 { for yy in (bb + 1)..=(foot_y - 1) { c.set(lx, yy, Col::Feet); } }
                c.hline(fx, fx + 2, foot_y, Col::Feet);
            }
        }
    }

    let w = if st == Stance::Squash { 1 } else { 0 };
    c.hline(cx - 12, cx - 11, r0 - 1, Col::Body);
    c.hline(cx - 12 - w, cx - 6, r0, Col::Body);
    c.hline(cx - 11 - w, cx - 8, r0 + 1, Col::Body);
    let body = [(-5, 3), (-7, 5), (-8, 6), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-8, 6), (-6, 4)];
    for (i, sp) in body.iter().enumerate() {
        c.hline(cx + sp.0 - w, cx + sp.1 + w, r0 + i as i32, if i >= 9 { Col::BodyShade } else { Col::Body });
    }

    if p.prop == Prop::Laptop { draw_laptop(c, cx + 9, g); }
    if p.prop == Prop::Popcorn { draw_popcorn(c, cx + 9, g); }
    if p.prop == Prop::Calendar { draw_calendar(c, cx + 8, r0 + 1); }
    if p.prop == Prop::Glass { draw_glass(c, cx + 9, r0 + 2); }
    bird_wing(c, p.arm, cx, r0);

    let hx = cx + 3 + p.head_dx;
    let ht = r0 - 15 + p.head_dy;
    let nby = r0 + 1;
    c.thick(cx + 3, nby, hx + 1, if ht + 4 <= nby { ht + 3 } else { ht + 1 }, 3, Col::Body);
    c.spans(hx, ht, &[(1, 4), (0, 5), (0, 5), (0, 5), (0, 4)], Col::Body);
    if p.mouth != Mouth::Closed {
        c.hline(hx + 6, hx + 8, ht + 1, Col::Beak); c.hline(hx + 6, hx + 7, ht + 2, Col::Beak);
        c.set(hx + 6, ht + 3, Col::Mouth); c.hline(hx + 6, hx + 7, ht + 4, Col::Beak);
    } else {
        c.hline(hx + 6, hx + 8, ht + 2, Col::Beak); c.hline(hx + 6, hx + 7, ht + 3, Col::BeakDark);
    }
    profile_eye(c, p.eyes, hx + 3, ht + 1);
    if p.blush { c.hline(hx + 3, hx + 4, ht + 3, Col::Blush); }
    Anchors { head_x: hx + 2, head_top: ht, head_w: 6, eyes: vec![(hx + 3, ht + 1)], profile: true, neck: (hx + 2, ht + 5),
              hat_dx: if p.head_dy >= 9 { 2 } else { 0 } }
}

// MARK: - Cats and the dalmatian

fn sock(q: &QuadSpec) -> Col {
    match q.coat {
        Coat::TabbyWhite => Col::Belly,
        Coat::Points => Col::Mark,
        Coat::Fox => Col::Mark2,
        _ => Col::Body,
    }
}

/// Front-facing head, 9 wide. hx/ht = top-left of the head itself; ears sit above, floppy ears at the sides.
fn quad_head(c: &mut Canvas, sp: Species, hx: i32, ht: i32, p: &Pose) {
    let q = sp.quad();
    let dog = sp.family() == Family::Dog;
    let ear_col = if q.coat == Coat::Points { Col::Mark } else { Col::Body };
    let left_ear = if q.coat == Coat::Calico { Col::Mark2 } else { ear_col };
    let right_ear = if q.coat == Coat::Calico { Col::Mark } else { ear_col };
    if q.ears == Ears::Cat {
        if p.outfit.hat.wide() && !p.ears_flat {
            // under a wide hat the ears tip out to the sides, so the hat sits on the head instead of on the ears
            c.hline(hx - 1, hx, ht, left_ear); c.set(hx - 2, ht - 1, left_ear); c.set(hx - 1, ht - 1, left_ear);
            c.hline(hx + 8, hx + 9, ht, right_ear); c.set(hx + 10, ht - 1, right_ear); c.set(hx + 9, ht - 1, right_ear);
            c.set(hx - 1, ht, Col::Inner); c.set(hx + 9, ht, Col::Inner);
        } else if p.ears_flat {
            c.hline(hx - 2, hx + 1, ht + 1, left_ear); c.set(hx - 2, ht + 2, left_ear);
            c.hline(hx + 7, hx + 10, ht + 1, right_ear); c.set(hx + 10, ht + 2, right_ear);
        } else {
            c.set(hx + 1, ht - 3, left_ear); c.hline(hx + 1, hx + 2, ht - 2, left_ear); c.hline(hx + 1, hx + 3, ht - 1, left_ear);
            c.set(hx + 7, ht - 3, right_ear); c.hline(hx + 6, hx + 7, ht - 2, right_ear); c.hline(hx + 5, hx + 7, ht - 1, right_ear);
            c.set(hx + 2, ht - 1, Col::Inner); c.set(hx + 6, ht - 1, Col::Inner);
            if q.coat == Coat::Fox {        // dark ear tips
                c.set(hx + 1, ht - 3, Col::Mark2); c.hline(hx + 1, hx + 2, ht - 2, Col::Mark2);
                c.set(hx + 7, ht - 3, Col::Mark2); c.hline(hx + 6, hx + 7, ht - 2, Col::Mark2);
            }
        }
    }
    let shape: &[(i32, i32)] = if dog {
        &[(1, 7), (0, 8), (0, 8), (0, 8), (0, 8), (0, 8), (1, 7), (2, 6)]
    } else {
        &[(1, 7), (0, 8), (0, 8), (0, 8), (0, 8), (1, 7), (2, 6)]
    };
    c.spans(hx, ht, shape, Col::Body);

    match q.coat {
        Coat::Tabby => {
            for x in [hx + 3, hx + 5] { c.set(x, ht, Col::Mark); c.set(x, ht + 1, Col::Mark); }
            c.set(hx, ht + 3, Col::Mark); c.set(hx + 8, ht + 3, Col::Mark);
        }
        Coat::Points => c.ellipse(hx as f64 + 4.0, ht as f64 + 3.6, 3.2, 2.4, Col::Mark),
        Coat::TabbyWhite => {
            // like the reference cat: forehead stripes, a cream blaze down the nose, whiskers out to the sides
            for x in [hx + 3, hx + 5] { c.set(x, ht, Col::Mark); c.set(x, ht + 1, Col::Mark); }
            c.set(hx, ht + 3, Col::Mark); c.set(hx + 8, ht + 3, Col::Mark);
            c.set(hx + 4, ht + 2, Col::Belly); c.set(hx + 4, ht + 3, Col::Belly);
            for y in [ht + 2, ht + 4] { c.hline(hx - 2, hx - 1, y, Col::Whisker); c.hline(hx + 9, hx + 10, y, Col::Whisker); }
        }
        Coat::Fox => {}
        Coat::Calico => {
            c.rect(hx, ht, 3, 2, Col::Mark2); c.set(hx, ht + 2, Col::Mark2);
            c.hline(hx + 6, hx + 8, ht, Col::Mark);
        }
        Coat::Spots => { c.set(hx + 6, ht + 1, Col::Mark); c.set(hx + 2, ht, Col::Mark); }
    }
    if q.ears == Ears::Flop {
        let lift = if p.ears_flat { 1 } else { 0 };
        c.spans(hx, ht + lift, &[(-1, 0), (-3, -1), (-3, -1), (-3, -1), (-3, -1), (-2, -1)], Col::Mark);
        c.spans(hx, ht + lift, &[(8, 9), (9, 11), (9, 11), (9, 11), (9, 11), (9, 10)], Col::Mark);
    }

    // face
    let (l, r, ey) = (hx + 1, hx + 6, ht + 2);
    let e = Col::Eye;
    match p.eyes {
        Eyes::Open if q.coat == Coat::TabbyWhite => { c.rect(l + 1, ey, 1, 2, e); c.rect(r, ey, 1, 2, e); }       // narrow, like the reference
        Eyes::Open => {
            c.rect(l, ey, 2, 2, e); c.rect(r, ey, 2, 2, e);
            c.set(l, ey, Col::EyeHi); c.set(r, ey, Col::EyeHi);
        }
        Eyes::Half => { c.hline(l, l + 1, ey + 1, e); c.hline(r, r + 1, ey + 1, e); }
        Eyes::Up => {
            c.rect(l, ey - 1, 2, 2, e); c.rect(r, ey - 1, 2, 2, e);
            c.set(l + 1, ey - 1, Col::EyeHi); c.set(r + 1, ey - 1, Col::EyeHi);
        }
        Eyes::Wide => {
            c.rect(l, ey - 1, 2, 3, e); c.rect(r, ey - 1, 2, 3, e);
            c.set(l, ey - 1, Col::EyeHi); c.set(r, ey - 1, Col::EyeHi);
        }
        Eyes::Closed => { c.hline(l, l + 1, ey + 1, e); c.hline(r, r + 1, ey + 1, e); }
        Eyes::Happy => {
            c.set(l - 1, ey + 1, e); c.set(l, ey, e); c.set(l + 1, ey + 1, e);
            c.set(r, ey + 1, e); c.set(r + 1, ey, e); c.set(r + 2, ey + 1, e);
        }
        Eyes::Angry => {
            c.hline(l, l + 1, ey + 1, e); c.hline(r, r + 1, ey + 1, e);
            c.set(l, ey, e); c.set(r + 1, ey, e);
        }
        Eyes::Sad => {
            c.hline(l, l + 1, ey + 1, e); c.hline(r, r + 1, ey + 1, e);
            c.set(l + 1, ey, e); c.set(r, ey, e);
        }
        Eyes::Dizzy => {
            for (dx, dy) in [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)] { c.set(l - 1 + dx, ey - 1 + dy, e); c.set(r - 1 + dx, ey - 1 + dy, e); }
        }
    }
    let fox = q.coat == Coat::Fox;
    if q.coat != Coat::Points { c.rect(hx + 2, ht + 4, 5, if fox { 3 } else { 2 }, Col::Belly); }
    c.set(hx + 4, ht + 4, Col::Nose);
    if dog && !fox { c.set(hx + 3, ht + 4, Col::Nose); c.set(hx + 5, ht + 4, Col::Nose); }
    let my = ht + 5;
    match p.mouth {
        Mouth::Closed => { if !fox { c.set(hx + 3, my, Col::BodyShade); c.set(hx + 5, my, Col::BodyShade); } }
        Mouth::Open => { c.hline(hx + 3, hx + 5, my, Col::Mouth); c.set(hx + 4, my + 1, Col::Mouth); }
        Mouth::Tongue => {
            if dog { c.hline(hx + 3, hx + 5, my, Col::Mouth); c.rect(hx + 4, my + 1, 1, 2, Col::Tongue); }
            else { c.set(hx + 3, my, Col::Mouth); c.set(hx + 5, my, Col::Mouth); c.set(hx + 4, my + 1, Col::Tongue); }
        }
    }
    if p.blush { c.set(hx + 1, ht + 4, Col::Blush); c.set(hx + 7, ht + 4, Col::Blush); }
}

fn quad_anchors(hx: i32, ht: i32) -> Anchors {
    Anchors { head_x: hx + 4, head_top: ht, head_w: 9, eyes: vec![(hx + 1, ht + 2), (hx + 6, ht + 2)], profile: false,
              neck: (hx + 4, ht + 7), hat_dx: 0 }
}

/// Coat markings on a side-view body spanning x0...x1, rows r0...rb.
fn side_coat(c: &mut Canvas, q: &QuadSpec, x0: i32, x1: i32, r0: i32, rb: i32) {
    let in_body = |x: i32, y: i32| -> bool { x >= x0 - 1 && x <= x1 + 1 && y >= r0 && y <= rb };
    match q.coat {
        Coat::Tabby => {
            let mut x = x0 + 3;
            while x <= x1 - 3 { c.paint(Col::Body, Col::Mark, |xx, y| xx == x && y >= r0 && y <= r0 + 2); x += 3; }
        }
        Coat::Calico => {
            c.patch(Col::Mark, |x, y| in_body(x, y) && x <= x0 + 5 && y <= r0 + 3);
            c.patch(Col::Mark2, |x, y| in_body(x, y) && x >= x0 + 9 && x <= x0 + 13 && y <= r0 + 2);
        }
        Coat::Spots => {
            for (dx, dy) in [(2, 1), (6, 3), (9, 1), (12, 3), (4, 4), (15, 1)] {
                if x0 + dx < x1 { c.paint(Col::Body, Col::Mark, |x, y| (x == x0 + dx || x == x0 + dx + 1) && y == r0 + dy); }
            }
        }
        _ => {}
    }
    if q.coat == Coat::TabbyWhite || q.coat == Coat::Fox {
        if q.coat == Coat::TabbyWhite {
            let mut x = x0 + 3;
            while x <= x1 - 4 { c.paint(Col::Body, Col::Mark, |xx, y| xx == x && y >= r0 && y <= r0 + 2); x += 3; }
        }
        // white chest and belly
        c.patch(Col::Belly, |x, y| in_body(x, y) && ((y == rb && x >= x0 + 2 && x <= x1 - 1) || (x >= x1 - 2 && y >= r0 + 2)));
    } else {
        c.paint(Col::Body, Col::Belly, |x, y| (y == rb && x >= x0 + 3 && x <= x1 - 3) || (y == rb - 1 && x >= x0 + 5 && x <= x1 - 5));
    }
}

fn side_tail(c: &mut Canvas, q: &QuadSpec, bx: i32, by: i32, p: &Pose) {
    let sw = iround(p.tail.sin() * 2.0);
    let sw2 = iround((p.tail - 0.8).sin() * 1.4);
    match q.tail {
        Tail::Cat => {
            if p.tail_up { c.polyline(&[(bx, by), (bx - 3, by - 3), (bx - 3 + sw2, by - 7), (bx - 2 + sw, by - 10)], 2, Col::Body); }
            else { c.polyline(&[(bx, by + 1), (bx - 4, by + 3), (bx - 7 + sw2, by + 5)], 2, Col::Body); }
            if q.coat == Coat::Tabby { c.paint(Col::Body, Col::Mark, |x, y| y < by - 3 && y % 3 == 0 && x < bx); }
        }
        Tail::Fluffy => c.polyline(&[(bx, by), (bx - 3, by - 3), (bx - 3 + sw2, by - 7), (bx - 2 + sw, by - 10)], 3, Col::Mark),
        Tail::Thin => c.polyline(&[(bx, by), (bx - 3, by - 2), (bx - 5 + sw, by - 5)], 2, Col::Body),
        Tail::Brush => {
            let pts: Vec<(i32, i32)> = if p.tail_up {
                vec![(bx, by), (bx - 4, by - 2), (bx - 6 + sw2, by - 6), (bx - 5 + sw, by - 9)]
            } else {
                vec![(bx, by + 1), (bx - 4, by + 3), (bx - 8 + sw2, by + 4)]
            };
            c.polyline(&pts, 3, Col::Body);
            white_tip(c, *pts.last().unwrap());
        }
    }
}

/// The white tip of a fox's tail, around the last point of its line (drawn 3 cells thick to the right and down).
fn white_tip(c: &mut Canvas, end: (i32, i32)) {
    c.paint(Col::Body, Col::Belly, |x, y| x >= end.0 - 1 && x <= end.0 + 3 && y >= end.1 - 1 && y <= end.1 + 2);
}

/// Swift's `Int(x)`: toward zero.
#[inline(always)]
fn itrunc(x: f64) -> i32 { x as i32 }

fn draw_quad(c: &mut Canvas, sp: Species, p: &Pose, cx: i32) -> Anchors {
    let q = sp.quad();
    let g = c.h - 2;
    let sk = sock(&q);
    let mut hx: i32;
    let mut ht: i32;
    let mut shoulder: Option<(i32, i32)> = None;

    match p.stance {
        Stance::Stand | Stance::Walk | Stance::Crouch | Stance::Squash | Stance::Eat => {
            let crouch = p.stance == Stance::Crouch;
            let leg_h = if crouch { 1 } else if p.stance == Stance::Squash { 1.max(q.leg_h - 2) } else { q.leg_h };
            let rb = g - leg_h;                      // bottom row of the body
            let r0 = rb - q.body_h + 1 + p.bob;
            let x0 = cx - q.half + if crouch { p.wiggle } else { 0 };
            let x1 = cx + q.half - 1;
            side_tail(c, &q, x0 + 1, r0 + 1, p);
            let leg_x = [x0 + 1, x0 + 3, x1 - 4, x1 - 2];
            let offs = [0.0, PI, 0.0, PI];
            for i in [1usize, 2, 0, 3] {
                let walk = p.stance == Stance::Walk;
                let sv = if walk { (p.phase + offs[i]).sin() } else { 0.0 };
                let lift = if walk && (p.phase + offs[i]).cos() > 0.35 { 1 } else { 0 };
                let lx = leg_x[i] + iround(sv * 1.3);
                let far = i == 1 || i == 2;
                c.rect(lx, rb, 2, g - lift - rb + 1, if far { Col::BodyShade } else { Col::Body });
                c.hline(lx, lx + 1, g - lift, if far && sk == Col::Body { Col::BodyShade } else { sk });
                if q.coat == Coat::Fox { c.rect(lx, g - lift - 2, 2, 2, Col::Mark2); }
            }
            let mut rows: Vec<(i32, i32)> = vec![(2, -3), (1, -1)];
            for _ in 0..(q.body_h - 3) { rows.push((0, 0)); }
            rows.push((1, -1));
            for (i, s) in rows.iter().enumerate() { c.hline(x0 + s.0, x1 + s.1, r0 + i as i32, Col::Body); }
            side_coat(c, &q, x0, x1, r0, rb);
            hx = x1 - 4 + p.head_dx;
            ht = r0 - 6 + p.head_dy;
            if crouch { hx += 2; ht += 2; }
            if p.stance == Stance::Eat { hx = x1 - 2 + p.head_dx; ht = g - 7 + p.head_dy; }
        }

        Stance::Sit => {
            let top = g - 13 + p.bob;
            let wrap = matches!(q.tail, Tail::Cat | Tail::Fluffy | Tail::Brush) && !p.tail_up;
            if !wrap {
                match q.tail {
                    Tail::Cat | Tail::Fluffy => {
                        let fl = q.tail == Tail::Fluffy;
                        c.polyline(&[(cx - 7, g - 3), (cx - 10, g - 7), (cx - 10 + itrunc((p.tail - 0.8).sin() * 1.4), g - 11),
                                     (cx - 9 + itrunc(p.tail.sin() * 2.0), g - 14)], if fl { 3 } else { 2 }, if fl { Col::Mark } else { Col::Body });
                    }
                    Tail::Brush => {
                        let end = (cx - 10 + itrunc(p.tail.sin() * 2.0), g - 13);
                        c.polyline(&[(cx - 7, g - 3), (cx - 11, g - 6), (cx - 12 + itrunc((p.tail - 0.8).sin() * 1.4), g - 10), end], 3, Col::Body);
                        white_tip(c, end);
                    }
                    Tail::Thin => c.polyline(&[(cx - 6, g - 1), (cx - 10, g), (cx - 13 + itrunc(p.tail.sin() * 2.0), g)], 2, Col::Body),
                }
            }
            let torso = [(-2, 2), (-3, 3), (-4, 3), (-5, 4), (-6, 4), (-6, 4), (-7, 4), (-7, 4), (-8, 4), (-8, 4), (-8, 4), (-8, 4), (-7, 4)];
            c.spans(cx, top, &torso, Col::Body);
            c.hline(cx - 8, cx - 1, g, Col::Body);
            c.rect(cx + 1, g - 5, 2, 6, Col::Body);
            c.rect(cx + 3, g - 5, 2, 6, Col::Body);
            c.set(cx + 2, g - 4, Col::BodyShade); c.set(cx + 2, g - 2, Col::BodyShade);
            c.hline(cx + 1, cx + 4, g, sk);
            c.hline(cx - 8, cx - 5, g, sk);
            match q.coat {
                Coat::Fox => c.rect(cx + 1, top + 2, 3, 6, Col::Belly),
                Coat::Tabby | Coat::TabbyWhite => c.rect(cx + 1, top + 3, 2, if q.coat == Coat::TabbyWhite { 6 } else { 4 }, Col::Belly),
                Coat::Calico => {
                    c.patch(Col::Mark, |x, y| x <= cx - 4 && y >= g - 7 && y <= g - 3);
                    c.patch(Col::Mark2, |x, y| x >= cx - 3 && x <= cx && y >= top + 1 && y <= top + 3);
                }
                Coat::Spots => {
                    for (dx, dy) in [(-6, 8), (-2, 3), (-4, 11), (1, 6)] { c.set(cx + dx, top + dy, Col::Mark); c.set(cx + dx + 1, top + dy, Col::Mark); }
                }
                Coat::Points => {}
            }
            if q.coat == Coat::Tabby || q.coat == Coat::TabbyWhite { for y in [top + 4, top + 7] { c.hline(cx - 4, cx - 2, y, Col::Mark); } }
            if wrap && q.tail == Tail::Brush {
                // the big tail curls round the front paws, white tip last
                c.thick(cx - 10, g - 1, cx + 4, g - 1, 2, Col::Body);
                white_tip(c, (cx + 3, g - 1));
            } else if wrap {
                let col = if q.tail == Tail::Fluffy { Col::Mark } else { Col::Body };
                c.thick(cx - 9, g, cx + 5, g, 1, col);
                c.rect(cx + 5, g - if p.tail.sin() > 0.0 { 2 } else { 1 }, 1, 2, col);
            }
            hx = cx - 3 + p.head_dx;
            ht = top - 7 + p.head_dy;
            shoulder = Some((cx + 2, top + 3));
            if p.prop == Prop::Laptop { draw_laptop(c, cx + 6, g); }
            if p.prop == Prop::Popcorn { draw_popcorn(c, cx + 6, g); }
        }

        Stance::Upright => {
            c.polyline(&[(cx - 2, g - 1), (cx - 7, g), (cx - 11 + itrunc(p.tail.sin() * 2.0), g - 1)], 2, Col::Body);
            c.spans(cx, g - 14, &[(-2, 2), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-3, 3), (-4, 3), (-4, 4), (-4, 4), (-4, 4), (-3, 3)], Col::Body);
            c.spans(cx, g - 12, &[(1, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 2)], Col::Belly);
            c.rect(cx + 3, g - 12, 2, 2, Col::Body); c.rect(cx + 3, g - 9, 2, 2, Col::Body);
            c.hline(cx - 3, cx + 3, g, sk);
            hx = cx - 4 + p.head_dx;
            ht = g - 21 + p.head_dy;
            shoulder = Some((cx + 2, g - 11));
        }

        Stance::Lie => {
            let x0 = cx - q.half;
            let x1 = cx + 5;
            if q.tail == Tail::Brush {
                c.thick(x0 - 6, g - 1, x0 + 3, g - 1, 2, Col::Body);
                white_tip(c, (x0 - 7, g - 1));
            } else if q.tail == Tail::Cat || q.tail == Tail::Fluffy {
                let col = if q.tail == Tail::Fluffy { Col::Mark } else { Col::Body };
                c.hline(x0 - 3, x0 + 4, g, col);
                c.rect(x0 - 3, g - 2 + if p.tail.sin() > 0.0 { 0 } else { 1 }, 1, 2, col);
            } else {
                side_tail(c, &q, x0 + 1, g - 4, p);
            }
            c.spans(x0, g - 6, &[(3, x1 - x0 - 3), (1, x1 - x0 - 1), (0, x1 - x0), (0, x1 - x0), (0, x1 - x0), (0, x1 - x0), (1, x1 - x0 - 1)], Col::Body);
            side_coat(c, &q, x0, x1, g - 6, g);
            if sp.family() == Family::Cat {
                c.hline(cx + 3, cx + 5, g, if sk == Col::Body { Col::Belly } else { sk });
                hx = cx - 1 + p.head_dx; ht = g - 11 + p.head_dy;
            } else {
                c.rect(cx + 3, g - 1, 7, 2, Col::Body);
                c.hline(cx + 8, cx + 9, g, sk);
                c.set(cx + 6, g - 1, Col::BodyShade);
                hx = cx + p.head_dx; ht = g - 12 + p.head_dy;
            }
        }

        Stance::Curl if q.coat == Coat::Fox => return draw_sleeping_fox(c, p, cx),

        Stance::Curl => {
            c.spans(cx, g - 6, &[(-6, 4), (-8, 6), (-9, 7), (-9, 7), (-9, 7), (-9, 7), (-8, 6)], Col::Body);
            side_coat(c, &q, cx - 9, cx + 7, g - 6, g);
            hx = cx - 2 + p.head_dx;
            ht = g - 8 + p.head_dy;
        }

        Stance::Stretch => {
            let x0 = cx - q.half;
            side_tail(c, &q, x0 + 1, g - 12, p);
            c.rect(x0 + 3, g - 7, 2, 8, Col::BodyShade);
            c.rect(x0 + 1, g - 7, 2, 8, Col::Body);
            c.thick(x0, g - 12, cx + 4, g - 7, 5, Col::Body);
            c.rect(cx + 3, g - 1, 9, 2, Col::Body);
            c.hline(cx + 10, cx + 11, g, sk);
            hx = cx + 4 + p.head_dx;
            ht = g - 10 + p.head_dy;
        }

        Stance::Leap | Stance::Fly => {
            let r0 = g - 13 + p.bob;
            side_tail(c, &q, cx - 9, r0 + 2, p);
            c.thick(cx - 8, r0 + 4, cx - 13, r0 + 8, 2, Col::BodyShade);
            c.thick(cx - 7, r0 + 4, cx - 12, r0 + 9, 2, Col::Body);
            c.spans(cx, r0, &[(-7, 5), (-9, 8), (-10, 9), (-10, 9), (-9, 8), (-7, 5)], Col::Body);
            c.hline(cx - 6, cx + 4, r0 + 5, Col::Belly);
            if q.coat == Coat::Tabby { for x in [cx - 6, cx - 3, cx, cx + 3] { c.paint(Col::Body, Col::Mark, |xx, y| xx == x && y >= r0 && y <= r0 + 1); } }
            if q.coat == Coat::Spots { for (dx, dy) in [(-6, 1), (-2, 3), (2, 1)] { c.set(cx + dx, r0 + dy, Col::Mark); } }
            c.thick(cx + 6, r0 + 4, cx + 11, r0 + 7, 2, Col::BodyShade);
            c.thick(cx + 7, r0 + 4, cx + 13, r0 + 8, 2, Col::Body);
            hx = cx + 6 + p.head_dx;
            ht = r0 - 6 + p.head_dy;
        }

        Stance::Umbrella | Stance::Held => return draw_quad_front(c, sp, &q, p, cx),
    }

    quad_head(c, sp, hx, ht, p);

    if p.stance == Stance::Curl {
        let col = if q.tail == Tail::Fluffy { Col::Mark } else { Col::Body };
        c.thick(cx - 9, g, cx + 7, g, 1, col);
        c.rect(cx + 7, g - 2, 2, 2, col);
    }
    if let Some(sh) = shoulder {
        let to: Option<(i32, i32)> = match p.arm {
            Arm::Tap => Some((cx + 7, g - 2)),
            Arm::Forward => Some((cx + 6, g - 4)),
            Arm::Scoop => Some((cx + 8, g - 8)),
            Arm::ToMouth | Arm::Lick => Some((hx + 5, ht + 6)),
            Arm::Raised => Some((cx + 5, ht + 1)),
            Arm::Hold => Some((cx + 5, g - 10)),
            _ => None,
        };
        if p.prop == Prop::Calendar { draw_calendar(c, cx + 3, g - 14); }
        if p.prop == Prop::Glass {
            let tm = p.arm == Arm::ToMouth;
            draw_glass(c, if tm { hx + 5 } else { cx + 4 }, if tm { ht + 4 } else { g - 13 });
        }
        if let Some(to) = to {
            c.thick(sh.0, sh.1, to.0, to.1, 2, Col::Body);
            c.set(to.0, to.1, if sk == Col::Body { Col::Belly } else { sk });
        }
    }
    quad_anchors(hx, ht)
}

/// Seen from the front: gliding down with an umbrella, or held up.
fn draw_quad_front(c: &mut Canvas, sp: Species, q: &QuadSpec, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let ht = g - 18;
    let hx = cx - 4;
    let s = p.phase.sin();
    let sk = sock(q);
    let bb = ht + 16;

    let sw = iround(p.tail.sin() * 2.0);
    match q.tail {
        Tail::Cat => c.polyline(&[(cx + 2, bb - 2), (cx + 6, bb - 4), (cx + 7 + sw, bb - 9)], 2, Col::Body),
        Tail::Fluffy => c.polyline(&[(cx + 2, bb - 2), (cx + 6, bb - 4), (cx + 7 + sw, bb - 9)], 3, Col::Mark),
        Tail::Thin => c.polyline(&[(cx + 2, bb - 1), (cx + 6, bb + 1), (cx + 8 + sw, bb - 1)], 2, Col::Body),
        Tail::Brush => {
            c.polyline(&[(cx + 2, bb - 2), (cx + 6, bb - 4), (cx + 7 + sw, bb - 9)], 3, Col::Body);
            white_tip(c, (cx + 7 + sw, bb - 9));
        }
    }
    let k = if s > 0.0 { 1 } else { 0 };
    c.rect(cx - 3, bb, 2, 2 + k, Col::Body); c.hline(cx - 3, cx - 2, bb + 1 + k, sk);
    c.rect(cx + 1, bb, 2, 3 - k, Col::Body); c.hline(cx + 1, cx + 2, bb + 2 - k, sk);
    c.spans(cx, ht + 7, &[(-3, 2), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-4, 3), (-3, 2), (-2, 1)], Col::Body);
    match q.coat {
        Coat::Spots => { for (dx, dy) in [(-3, 9), (2, 10), (-1, 13)] { c.set(cx + dx, ht + dy, Col::Mark); } }
        Coat::Calico => c.patch(Col::Mark, |x, y| y > ht + 7 && y < ht + 11 && x < cx - 1),
        _ => c.spans(cx, ht + 8, &[(-1, 0), (-2, 1), (-2, 1), (-2, 1), (-2, 1), (-2, 1), (-1, 0)], Col::Belly),
    }
    let mut lp = (cx - 5, ht + 13 + k);
    let mut rp = (cx + 4, ht + 14 - k);
    if p.stance == Stance::Umbrella {
        lp = (cx - 6, ht + 14);
        rp = (cx + 6, ht - 2);
        draw_umbrella(c, cx + 6, ht - 11, (cx + 6, ht - 2));
    }
    c.thick(cx - 4, ht + 9, lp.0, lp.1, 2, Col::Body);
    c.thick(cx + 3, ht + 9, rp.0, rp.1, 2, Col::Body);
    let paw = if sk == Col::Body { Col::Belly } else { sk };
    c.hline(lp.0, lp.0 + 1, lp.1, paw);
    c.hline(rp.0, rp.0 + 1, rp.1, paw);
    quad_head(c, sp, hx, ht, p);
    quad_anchors(hx, ht)
}

// MARK: - Fox asleep

/// The fox asleep, drawn from its reference picture at the pets' pixel size: head down on the left with closed
/// eyes and a white muzzle, body behind it, the big tail curled round with its white tip, grey paws tucked under.
/// O fur, W white, G grey, K the lines inside the outline (the outline itself is added like every pet's).
const FOX_ASLEEP: [&str; 7] = [
    "..G.....G...OOOO.....",
    ".WG.....GWKOOOOOOOKO.",
    ".WOOOOOOOWKOOOOOOOKO.",
    ".OOOOOOOOOKOOOOOOOKOO",
    ".OKKOWOKKOKOOOOOOOKOW",
    "OOOOWKWOOOKOOOOOOGKWW",
    "OOOOWWWOOOKOOG.......",
];

fn draw_sleeping_fox(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let ox = cx - 10;
    let oy = c.h - 2 - (FOX_ASLEEP.len() as i32 - 1);
    c.sprite(ox, oy, &FOX_ASLEEP, &[(b'O', Col::Body), (b'W', Col::Belly), (b'G', Col::Mark2), (b'K', Col::Outline)]);
    if !matches!(p.eyes, Eyes::Closed | Eyes::Half | Eyes::Happy) {          // waking up: eyes open
        for ex in [ox + 2, ox + 7] { c.rect(ex, oy + 3, 2, 2, Col::Eye); c.set(ex, oy + 3, Col::EyeHi); }
    }
    if p.blush { c.set(ox + 1, oy + 5, Col::Blush); c.set(ox + 9, oy + 5, Col::Blush); }
    Anchors { head_x: ox + 5, head_top: oy + 2, head_w: 9, eyes: vec![(ox + 2, oy + 4), (ox + 7, oy + 4)], profile: false,
              neck: (ox + 5, oy + 6), hat_dx: 0 }
}

// MARK: - Parrot

fn parrot_wing(c: &mut Canvas, arm: Arm, cx: i32, top: i32) {
    let (w, wd) = (Col::Wing, Col::WingDark);
    match arm {
        Arm::Raised => c.region(cx - 1, top - 7, &[(-6, -4), (-7, -2), (-7, -1), (-6, 0), (-5, 1), (-4, 1), (-3, 1), (-2, 1), (-1, 1)], w, wd),
        Arm::Down => c.region(cx - 1, top + 3, &[(-1, 1), (-2, 1), (-3, 1), (-4, 0), (-5, -1), (-6, -2), (-7, -3), (-7, -5)], w, wd),
        Arm::Forward | Arm::Scoop | Arm::ToMouth | Arm::Hold | Arm::Tap => c.region(cx, top + 3, &[(-2, 1), (-2, 2), (-2, 3), (-1, 4), (0, 4)], w, wd),
        // folded along its side, the tips over the tail
        _ => c.region(cx, top + 2, &[(-3, 0), (-4, 1), (-4, 1), (-4, 1), (-4, 1), (-5, 0), (-5, -1), (-6, -2), (-6, -3)], w, wd),
    }
}

/// A parrot, side view facing right: upright, green with a red head and yellow cheek, blue-edged wings,
/// a long blue and red tail and a hooked beak.
fn draw_parrot(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let st = p.stance;
    let sitting = matches!(st, Stance::Sit | Stance::Lie | Stance::Curl);
    let airborne = matches!(st, Stance::Fly | Stance::Held | Stance::Umbrella | Stance::Leap);
    let bb = if sitting { g } else if airborne { g - 4 } else { g - 2 };            // bottom row of the body
    let top = bb - 11 + if st == Stance::Squash { 2 } else { 0 } + p.bob;

    // tail first, out behind and down to the ground (or trailing, in the air)
    let tip = if airborne { (cx - 12, bb + 4) } else { (cx - 11, g) };
    c.thick(cx - 3, bb - 3, tip.0, tip.1 - 1, 2, Col::WingDark);
    c.thick(cx - 3, bb - 4, tip.0 + 1, tip.1 - 2, 1, Col::Speculum);
    if !sitting {
        if airborne { c.set(cx - 1, bb + 1, Col::Feet); c.set(cx + 1, bb + 1, Col::Feet); }
        else { for fx in [cx - 1, cx + 2] { c.set(fx, g - 1, Col::Feet); c.hline(fx - 1, fx + 1, g, Col::Feet); } }
    }
    // body: an upright oval, lighter breast
    let widths = [(-2, 2), (-3, 3), (-4, 3), (-4, 4), (-4, 4), (-4, 4), (-4, 4), (-4, 4), (-4, 3), (-3, 3), (-3, 2), (-2, 1)];
    for (i, w) in widths.iter().enumerate() {
        if top + i as i32 <= bb { c.hline(cx + w.0, cx + w.1, top + i as i32, Col::Body); }
    }
    c.paint(Col::Body, Col::Belly, |x, y| x >= cx + 1 && y >= top + 3 && y <= bb - 1);

    if p.prop == Prop::Laptop { draw_laptop(c, cx + 7, g); }
    if p.prop == Prop::Popcorn { draw_popcorn(c, cx + 7, g); }
    if p.prop == Prop::Calendar { draw_calendar(c, cx + 6, top + 1); }
    if p.prop == Prop::Glass { draw_glass(c, cx + 6, top + 2); }
    parrot_wing(c, p.arm, cx, top);

    // head, on a short neck; pecking and eating bring it down to the ground in front
    let mut hx = cx - 1 + (-3).max(4.min(p.head_dx));
    let mut ht = top - 5 + (-3).max(10.min(p.head_dy));
    if st == Stance::Eat { hx = cx + 3 + 0.max(p.head_dx); ht = g - 6; }
    c.thick(cx - 1, top + 1, hx + 1, ht + 3, 3, Col::Body);
    c.spans(hx, ht, &[(1, 4), (0, 5), (0, 5), (0, 5), (1, 4)], Col::Mark);
    c.hline(hx + 1, hx + 2, ht + 3, Col::Accent);                         // yellow cheek
    for (dx, dy) in [(2, 1), (4, 1), (3, 0), (3, 2)] { c.set(hx + dx, ht + dy, Col::Ring); }
    profile_eye(c, p.eyes, hx + 3, ht + 1);
    // hooked beak
    c.hline(hx + 6, hx + 7, ht + 1, Col::Beak);
    c.hline(hx + 6, hx + 8, ht + 2, Col::Beak);
    if p.mouth == Mouth::Closed {
        c.set(hx + 8, ht + 3, Col::Beak); c.hline(hx + 6, hx + 7, ht + 3, Col::BeakDark);
    } else {
        c.set(hx + 8, ht + 3, Col::Beak); c.set(hx + 6, ht + 3, Col::Mouth); c.hline(hx + 6, hx + 7, ht + 4, Col::BeakDark);
    }
    if p.blush { c.set(hx + 2, ht + 3, Col::Blush); }
    Anchors { head_x: hx + 2, head_top: ht, head_w: 6, eyes: vec![(hx + 3, ht + 1)], profile: true, neck: (hx + 2, ht + 5), hat_dx: 0 }
}

// MARK: - Outfits & extras

type Art = (&'static [&'static str], &'static [(u8, Col)]);

fn hat_art(h: Hat) -> Option<Art> {
    use Col::*;
    Some(match h {
        Hat::TopHat => (&[".KKKKH.", ".KKKKH.", ".KKKKH.", ".RRRRR.", "HKKKKKH"], &[(b'K', HatBlack), (b'H', HatShine), (b'R', HatBand)]),
        Hat::Crown => (&["Y.Y.Y", "YYRYY", "YYYYY"], &[(b'Y', Gold), (b'R', Ruby)]),
        Hat::Party => (&["..S..", ".SSS.", "..P..", ".PBP.", ".BPB.", "PBPBP"], &[(b'S', Star), (b'P', PartyPink), (b'B', PartyBlue)]),
        Hat::Witch => (&["K.......", "KK......", ".KK.....", ".KKK....", ".KKKK...", ".PPPP...", "KKKKKKKK"], &[(b'K', Witch), (b'P', WitchBand)]),
        Hat::Cowboy => (&["...CCC...", "..CCCCC..", "..DDDDD..", "C.CCCCC.C", ".CCCCCCC."], &[(b'C', Cowboy), (b'D', CowboyDark)]),
        Hat::Bow => (&["PP.PP", "PPDPP", "PP.PP"], &[(b'P', BowPink), (b'D', BowDark)]),
        Hat::Flower => (&[".W.", "WYW", ".W."], &[(b'W', Petal), (b'Y', PopYellow)]),
        Hat::Santa => (&["......RWW", ".....RRWW", "....RRR..", "...RRRR..", "..RRRRRR.", "WWWWWWWWW"], &[(b'R', HatBand), (b'W', White)]),
        Hat::None => return None,
    })
}

/// Narrower side views of the wide hats, for the goose's small profile head (tips flop backwards).
fn hat_art_profile(h: Hat) -> Option<Art> {
    use Col::*;
    Some(match h {
        Hat::Santa => (&["WW....", "WRR...", ".RRRR.", ".RRRRR", "WWWWWW"], &[(b'R', HatBand), (b'W', White)]),
        Hat::Witch => (&["K.....", "KK....", ".KK...", ".KKK..", ".PPPP.", "KKKKKK"], &[(b'K', Witch), (b'P', WitchBand)]),
        Hat::Cowboy => (&["..CCC..", ".CCCCC.", ".DDDDD.", "CCCCCCC"], &[(b'C', Cowboy), (b'D', CowboyDark)]),
        Hat::TopHat => (&[".KKH.", ".KKH.", ".KKH.", ".RRR.", "HKKKH"], &[(b'K', HatBlack), (b'H', HatShine), (b'R', HatBand)]),
        _ => return None,
    })
}

fn draw_extras(c: &mut Canvas, p: &Pose, a: &Anchors) {
    let o = p.outfit;
    let hx = a.head_x;
    let top = a.head_top;
    let half = a.head_w / 2;
    let (nx, ny) = a.neck;
    let nh = if a.profile { 2 } else { 3 };
    match o.neck {
        Neckwear::None => {}
        Neckwear::Scarf => {
            c.rect(nx - nh, ny, nh * 2 + 1, 2, Col::Scarf);
            let mut x = nx - nh + 1;
            while x <= nx + nh { c.set(x, ny, Col::ScarfStripe); x += 2; }
            c.rect(nx - nh - if a.profile { 1 } else { 0 }, ny + 1, 2, 3, Col::Scarf);
        }
        Neckwear::Bowtie => {
            if a.profile { c.sprite(nx + 1, ny, &["X.X", "XXX", "X.X"], &[(b'X', Col::Ruby)]); }
            else { c.sprite(nx - 2, ny, &["XX.XX", "XXXXX", "XX.XX"], &[(b'X', Col::Ruby)]); }
        }
        Neckwear::Bell => {
            c.hline(nx - nh, nx + nh, ny, Col::Collar);
            c.rect(if a.profile { nx + 1 } else { nx - 1 }, ny + 1, if a.profile { 2 } else { 3 }, 2, Col::Gold);
        }
        Neckwear::Bandana => {
            let map = [(b'B', Col::Bandana), (b'W', Col::White)];
            if a.profile { c.sprite(nx - 1, ny, &["BBBB", ".BWB", "..BB", "...B"], &map); }
            else { c.sprite(nx - 3, ny, &["BBBBBBB", ".BWBBB.", "..BBB..", "...B..."], &map); }
        }
    }
    for &(ex, ey) in &a.eyes {
        if a.profile {
            match o.glasses {
                Glasses::None => {}
                Glasses::Shades => { c.rect(ex - 1, ey, 3, 2, Col::Lens); c.hline(ex - 3, ex - 2, ey, Col::Frame); }
                Glasses::Hearts => { c.rect(ex - 1, ey, 3, 2, Col::LensPink); c.set(ex, ey + 2, Col::LensPink); c.hline(ex - 3, ex - 2, ey, Col::Frame); }
                Glasses::Round => {
                    c.hline(ex - 1, ex + 1, ey - 1, Col::Frame); c.set(ex - 1, ey, Col::Frame); c.set(ex + 1, ey, Col::Frame);
                    c.hline(ex - 1, ex + 1, ey + 1, Col::Frame); c.hline(ex - 3, ex - 2, ey, Col::Frame);
                }
            }
        } else {
            match o.glasses {
                Glasses::None => {}
                Glasses::Shades => { c.rect(ex - 1, ey, 3, 2, Col::Lens); c.rect(ex, ey, 2, 2, Col::Lens); }
                Glasses::Hearts => { c.rect(ex - 1, ey, 3, 2, Col::LensPink); c.set(ex, ey + 2, Col::LensPink); }
                Glasses::Round => {
                    c.hline(ex - 1, ex + 2, ey - 1, Col::Frame); c.hline(ex - 1, ex + 2, ey + 2, Col::Frame);
                    c.rect(ex - 1, ey, 1, 2, Col::Frame); c.rect(ex + 2, ey, 1, 2, Col::Frame);
                }
            }
        }
    }
    if !a.profile && o.glasses != Glasses::None && a.eyes.len() == 2 { c.hline(a.eyes[0].0 + 2, a.eyes[1].0 - 1, a.eyes[0].1, Col::Frame); }
    if p.phones {
        let band = o.hat == Hat::None || p.nightcap;        // with a hat on, the band goes under it: only the pads show
        if a.profile {
            if band { c.hline(hx - 2, hx + 2, top - 1, Col::Phones); }
            c.rect(hx - 2, top + 1, 2, 3, Col::PhonesPad);
            c.set(hx - 2, top, Col::Phones);
        } else {
            if band { c.hline(hx - half - 1, hx + half + 1, top - 2, Col::Phones); }
            let (y, h) = if band { (top - 1, 2) } else { (top, 1) };
            c.rect(hx - half - 1, y, 1, h, Col::Phones); c.rect(hx + half + 1, y, 1, h, Col::Phones);
            c.rect(hx - half - 2, top + 1, 2, 3, Col::PhonesPad); c.rect(hx + half + 1, top + 1, 2, 3, Col::PhonesPad);
        }
    }
    if p.nightcap {
        let l = if a.profile { hx - 2 } else { hx - half + 1 };
        c.hline(l, l + if a.profile { 5 } else { 7 }, top - 1, Col::White);
        c.hline(l, l + if a.profile { 4 } else { 6 }, top - 2, Col::Cap);
        c.hline(l - 1, l + 3, top - 3, Col::Cap);
        c.hline(l - 2, l + 1, top - 4, Col::Cap);
        c.rect(l - 4, top - 4, 2, 2, Col::White);
        return;
    }
    if o.hat == Hat::None { return; }
    let art = (if a.profile { hat_art_profile(o.hat) } else { None }).or_else(|| hat_art(o.hat));
    let Some((rows, map)) = art else { return };
    let w = rows.iter().map(|r| r.len() as i32).max().unwrap_or(0);
    let (x0, y0) = match o.hat {
        Hat::Bow => (if a.profile { hx - 4 } else { hx + 1 }, if a.profile { top - 1 } else { top - 3 }),
        Hat::Flower => (if a.profile { hx - 1 } else { hx - half - 1 }, if a.profile { top - 2 } else { top - 3 }),
        _ => ((if a.profile { hx - 1 } else { hx }) - w / 2, top - rows.len() as i32),
    };
    c.sprite(x0 + a.hat_dx, y0, rows, map);
}

// MARK: - Bat

/// Drawn standing on its feet; on the top edge the whole picture is turned over, so it hangs head-down.
/// Wings wrap the body at rest and spread (flapping with `phase`) when it flies, is thrown or is held.
fn draw_bat(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let flying = matches!(p.stance, Stance::Leap | Stance::Held | Stance::Fly | Stance::Umbrella | Stance::Squash);
    let wig = if p.stance == Stance::Walk { if p.phase.sin() > 0.0 { 1 } else { 0 } } else { 0 };
    let body_top;
    let ht;
    if flying {
        body_top = g - 14;
        ht = body_top - 7;
        // wings: from the shoulders out to the tips, with a scalloped trailing edge and finger bones
        let lift = 0.15 + 0.5 * p.phase.sin();
        let sy = body_top + 1;
        for dx in 0..=14 {
            let top = sy - iround(dx as f64 * lift);
            let depth = 1.max(9 - dx / 2 - if dx % 5 == 4 { 3 } else { 0 });
            for y in top..=(top + depth) {
                let col = if y == top || (dx % 5 == 0 && dx > 0) { Col::WingDark } else { Col::Wing };
                c.set(cx + 4 + dx, y, col);
                c.set(cx - 5 - dx, y, col);
            }
        }
        c.spans(cx, body_top, &[(-4, 3), (-4, 3), (-5, 4), (-5, 4), (-5, 4), (-5, 4), (-4, 3), (-4, 3), (-3, 2), (-2, 1)], Col::Body);
        c.spans(cx, body_top + 1, &[(-2, 1), (-3, 2), (-3, 2), (-3, 2), (-2, 1)], Col::Belly);
        c.set(cx - 2, body_top + 10, Col::Mark); c.set(cx + 1, body_top + 10, Col::Mark);
    } else {
        // hanging: a round bundle of wings wrapped like a cloak, feet gripping
        body_top = g - 13 + wig;
        ht = body_top - 7;
        c.spans(cx, body_top, &[(-5, 4), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-6, 5), (-5, 4), (-5, 4), (-4, 3), (-2, 1)], Col::Wing);
        for y in (body_top + 1)..=(body_top + 9) { c.set(cx - 4, y, Col::WingDark); c.set(cx + 3, y, Col::WingDark); }
        c.spans(cx, body_top, &[(-2, 1), (-3, 2), (-3, 2), (-2, 1), (-1, 0)], Col::Belly);
        c.set(cx - 2, g, Col::Mark); c.set(cx - 2, g - 1, Col::Mark); c.set(cx + 1, g, Col::Mark); c.set(cx + 1, g - 1, Col::Mark);
    }
    // head (flowing into the body) and big ears; under a hat the ears tip out to the sides so the hat sits on the head
    c.spans(cx, ht, &[(-3, 2), (-4, 3), (-5, 4), (-5, 4), (-5, 4), (-5, 4), (-5, 4)], Col::Body);
    let hatted = p.outfit.hat != Hat::None || p.nightcap;
    let ears: &[(i32, i32)] = if hatted { &[(-8, -7), (-7, -5), (-6, -4), (-5, -4)] } else { &[(-4, -4), (-5, -4), (-5, -3), (-5, -3), (-5, -2), (-5, -2)] };
    let ear_top = if hatted { ht - 1 } else { ht - 6 };
    for (i, row) in ears.iter().enumerate() {
        let y = ear_top + i as i32;
        c.hline(cx + row.0, cx + row.1, y, Col::Body);
        c.hline(cx - 1 - row.1, cx - 1 - row.0, y, Col::Body);
    }
    if hatted { for (dx, dy) in [(-6, 0), (-5, 1)] { c.set(cx + dx, ht + dy, Col::Inner); c.set(cx - 1 - dx, ht + dy, Col::Inner); } }
    else { for y in (ht - 4)..=(ht - 2) { c.set(cx - 4, y, Col::Inner); c.set(cx + 3, y, Col::Inner); } }
    // face
    let ey = ht + 2;
    // big round eyes, three wide, pupils in the middle
    let eyes = vec![(cx - 4, ey), (cx + 1, ey)];
    for (n, &(ex, _)) in eyes.iter().enumerate() {
        match p.eyes {
            Eyes::Closed => c.hline(ex, ex + 2, ey + 1, Col::Eye),
            Eyes::Happy => { c.set(ex, ey + 1, Col::Eye); c.set(ex + 1, ey, Col::Eye); c.set(ex + 2, ey + 1, Col::Eye); }
            Eyes::Half => { c.hline(ex, ex + 2, ey, Col::BodyShade); c.hline(ex, ex + 2, ey + 1, Col::EyeHi); c.set(ex + 1, ey + 1, Col::Eye); }
            Eyes::Dizzy | Eyes::Angry | Eyes::Sad => { c.set(ex, ey, Col::Eye); c.set(ex + 1, ey + 1, Col::Eye); c.set(ex + 2, ey, Col::Eye); }
            Eyes::Up => { c.rect(ex, ey, 3, 2, Col::EyeHi); c.set(ex + 1, ey, Col::Eye); }
            _ => { c.rect(ex, ey, 3, 2, Col::EyeHi); c.set(ex + 1, ey + 1, Col::Eye); }
        }
        if p.blush { c.set(if n == 0 { ex - 1 } else { ex + 3 }, ey + 2, Col::Blush); }
    }
    c.set(cx - 1, ey + 2, Col::Nose); c.set(cx, ey + 2, Col::Nose);
    if p.mouth == Mouth::Open || p.mouth == Mouth::Tongue { c.hline(cx - 1, cx, ey + 3, Col::Mouth); }
    c.set(cx - 2, ey + 4, Col::White); c.set(cx + 1, ey + 4, Col::White);          // little fangs
    Anchors { head_x: cx, head_top: ht, head_w: 9, eyes, profile: false, neck: (cx, ht + 7), hat_dx: 0 }
}

/// One accessory alone, on an invisible stand-in head so it sits the way it does on a pet.
pub fn draw_accessory(c: &mut Canvas, o: Outfit) {
    let cx = c.w / 2;
    let ht = 12;
    let p = Pose { outfit: o, ..Pose::default() };
    draw_extras(c, &p, &Anchors { head_x: cx, head_top: ht, head_w: 11, eyes: vec![(cx - 4, ht + 4), (cx + 2, ht + 4)], profile: false,
                                  neck: (cx, ht + 10), hat_dx: 0 });
}

/// Draws any pet with its extras.
pub fn draw_pet(c: &mut Canvas, sp: Species, p: &Pose, cx: i32) -> Anchors {
    let a = match sp {
        Species::Goose => draw_goose(c, p, cx),
        Species::Parrot => draw_parrot(c, p, cx),
        Species::Bat => draw_bat(c, p, cx),
        _ => draw_quad(c, sp, p, cx),
    };
    draw_extras(c, p, &a);
    a
}

// MARK: - Particles

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PKind { Heart, Z, Star, Bang, Question, Kernel, Crumb, Drop, Puff, Note }
impl PKind {
    pub const ALL: [PKind; 10] = [PKind::Heart, PKind::Z, PKind::Star, PKind::Bang, PKind::Question, PKind::Kernel, PKind::Crumb,
                                  PKind::Drop, PKind::Puff, PKind::Note];
}

#[derive(Clone, Copy, Debug)]
pub struct Particle {
    pub kind: PKind,
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub life: f64,
    pub gravity: f64,
    pub size: i32,
}

pub const SPR_STAR: [&str; 3] = [".X.", "XXX", ".X."];

pub fn draw_particle(c: &mut Canvas, p: &Particle) {
    let ix = iround(p.x);
    let iy = iround(p.y);
    let one = |col: Col| [(b'X', col)];
    match p.kind {
        PKind::Heart => c.sprite(ix - 2, iy - 2, &["XX.XX", "XXXXX", ".XXX.", "..X.."], &one(Col::Heart)),
        PKind::Z => {
            if p.size > 0 { c.sprite(ix - 2, iy - 2, &["XXXXX", "...X.", "..X..", ".X...", "XXXXX"], &one(Col::Zzz)) }
            else { c.sprite(ix - 2, iy - 2, &["XXXX", "..X.", ".X..", "XXXX"], &one(Col::Zzz)) }
        }
        PKind::Star => c.sprite(ix - 1, iy - 1, &SPR_STAR, &one(Col::Star)),
        PKind::Bang => c.sprite(ix, iy - 2, &["X", "X", "X", ".", "X"], &one(Col::Heart)),
        PKind::Question => c.sprite(ix - 1, iy - 2, &["XX.", "..X", ".X.", "...", ".X."], &one(Col::Zzz)),
        PKind::Kernel => { c.rect(ix, iy, 2, 2, Col::PopCream); c.set(ix + 1, iy, Col::PopYellow); }
        PKind::Crumb => c.set(ix, iy, Col::Crust),
        PKind::Drop => c.sprite(ix, iy, &[".X", "XX"], &one(Col::Sweat)),
        PKind::Puff => c.sprite(ix - 2, iy - 1, &[".XX.", "XXXX", ".XX."], &one(Col::White)),
        PKind::Note => c.sprite(ix - 2, iy - 2, &[".XXX", ".X.X", ".X..", "XX..", "XX.."], &one(Col::Note)),
    }
}
