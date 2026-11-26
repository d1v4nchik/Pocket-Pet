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
    pub chomp: bool,         // the shark: its jaws follow `mouth` (chattering, cross, wriggling, munching), not just asleep
    pub asleep: bool,        // settled down to sleep (the shark lies flat on its belly for it)
}

impl Default for Pose {
    fn default() -> Pose {
        Pose {
            stance: Stance::Stand, phase: 0.0, bob: 0, head_dx: 0, head_dy: 0, eyes: Eyes::Open, mouth: Mouth::Closed,
            arm: Arm::Rest, tail: 0.0, tail_up: true, ears_flat: false, prop: Prop::None, blush: false, nightcap: false,
            phones: false, wiggle: 0, outfit: Outfit::default(), chomp: false, asleep: false,
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
pub enum Species { Goose, Parrot, Ginger, Siamese, Tuxedo, Calico, Dalmatian, Fox, Bat, Shark }

impl Species {
    pub const ALL: [Species; 10] = [Species::Goose, Species::Parrot, Species::Ginger, Species::Siamese, Species::Tuxedo,
        Species::Calico, Species::Dalmatian, Species::Fox, Species::Bat, Species::Shark];

    pub fn raw(self) -> &'static str {
        ["goose", "parrot", "ginger", "siamese", "tuxedo", "calico", "dalmatian", "fox", "bat", "shark"][self as usize]
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
            Species::Goose | Species::Parrot | Species::Shark => Family::Bird,   // the shark flops on the ground and swims where birds fly
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
            Species::Shark => "Shark",
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
            Species::Shark => "Bubbles",
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
            // a scarlet macaw, the reference's colours: red, a pale face, yellow and blue wings, a blue-edged tail
            Species::Parrot => &[(Body, 0xe15635), (BodyShade, 0x9c3435), (Mark, 0xd42e30), (MarkShade, 0x783c44), (Belly, 0xdac7b9),
                                 (Accent, 0xffdd3d), (Mark2, 0xffc10c), (Wing, 0x378ada), (WingDark, 0x275fac), (Speculum, 0x67b1d8),
                                 (Ring, 0x23b14b), (Beak, 0xfaf6ed), (BeakDark, 0x434a52), (Nose, 0xf0dcaa), (Inner, 0xd2a665),
                                 (Feet, 0x525d7d), (Eye, 0x434a52), (Outline, 0x351f12)],
            // the reference's soft blues, cream lips, a rosy mouth and a peachy belly
            Species::Shark => &[(Body, 0x6496b8), (BodyShade, 0x4a74a0), (BodyLight, 0x8ab8d6), (Belly, 0xf0ece2), (Mouth, 0x9a5a64),
                                (Tongue, 0xe07a68), (Mark, 0xe8c4b4), (Blush, 0xf4a0a8), (Outline, 0x3a4560), (Eye, 0x3a4560)],
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
fn side_coat(c: &mut Canvas, q: &QuadSpec, x0: i32, x1: i32, r0: i32, rb: i32, lying: bool) {
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
        let belly = !(lying && q.coat == Coat::Fox);
        c.patch(Col::Belly, |x, y| in_body(x, y) && ((belly && y == rb && x >= x0 + 2 && x <= x1 - 1) || (x >= x1 - 2 && y >= r0 + 2)));
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
            side_coat(c, &q, x0, x1, r0, rb, false);
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
            side_coat(c, &q, x0, x1, g - 6, g, true);
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
            side_coat(c, &q, cx - 9, cx + 7, g - 6, g, false);
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

// A scarlet macaw facing right, copied cell for cell from the reference picture. O red, R bright red, D dark red,
// M plum, F pale face, W/c/T beak (white, cream, tan), G lower beak, Y/y yellow coverts, B/N/L blues, V the green
// feather, S legs, K lines. Rows 0-9 are the head (it nods as one piece), the body hangs under it.
const MACAW_HEAD: [&str; 10] = [
    "........RO.....",
    ".....DROOOO....",
    "....DROOOOOD...",
    "....RROFFOOD...",
    "....ROFFFFOTT..",
    "....DOFFFFcWWT.",
    "....MOFFFFOWWW.",
    "....DRRFFDGcWW.",
    "....DODDDDGGGc.",
    "...DOOODDGGG...",
];
const MACAW_BODY: [&str; 7] = [
    "..DOOBBVDMN....",
    "..yYOYBVDDDN...",
    "..yYYYYBDODB...",
    "..yYBYBBRORB...",
    "..yBLBLROORB...",
    ".LNLLNBRRRB....",
    "LLNLLDRRRK.....",
];
const MACAW_BODY_BARE: [&str; 7] = [
    "..DOORRODMN....",
    "..DOOORODDDN...",
    "..DDOORRDODB...",
    "..DDOOORRORB...",
    "..DDDOROORRB...",
    "..DDDDDRRRB....",
    "...DDDRRRK.....",
];
const MACAW_TAIL_HANGING: [&str; 11] = [
    "..KSDDDK.......",
    "...SDDS........",
    "..BDDDS........",
    "..BDDDB........",
    ".BBRDDB........",
    ".LBRDK.........",
    "..RRD..........",
    "..ROD..........",
    "..ROD..........",
    "..ROD..........",
    "..DR...........",
];
const MACAW_TAIL_GROUND: [&str; 4] = [
    "........BBBDDD",
    ".....BBLRRRDDD",
    "..BBLRROOODD..",
    "LLRRROOODD....",
];
const MACAW_WING_UP: [&str; 9] = [
    "L.......",
    "LB......",
    "LBN.....",
    ".LBN....",
    ".LBBY...",
    "..LBYY..",
    "..LBYYO.",
    "...BYYOO",
    "....YOOO",
];

const MACAW_MAP: &[(u8, Col)] = &[(b'O', Col::Body), (b'D', Col::BodyShade), (b'R', Col::Mark), (b'M', Col::MarkShade), (b'F', Col::Belly),
    (b'G', Col::BeakDark), (b'W', Col::Beak), (b'c', Col::Nose), (b'T', Col::Inner), (b'B', Col::Wing), (b'N', Col::WingDark),
    (b'L', Col::Speculum), (b'Y', Col::Accent), (b'y', Col::Mark2), (b'V', Col::Ring), (b'S', Col::Feet), (b'K', Col::Outline)];

fn draw_parrot(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let st = p.stance;
    let sitting = matches!(st, Stance::Sit | Stance::Lie | Stance::Curl);
    let airborne = matches!(st, Stance::Fly | Stance::Held | Stance::Umbrella | Stance::Leap);
    let ox = cx - 8;
    // the body's bottom row: on its feet, sat on the ground, or in the air with the tail hanging down to the ground row
    let bottom = (if sitting { g } else if airborne { g - 11 } else { g - 3 }) + if st == Stance::Squash { 1 } else { 0 };
    let oy = bottom - 16 + p.bob;

    if airborne {
        c.sprite(ox, oy + 17, &MACAW_TAIL_HANGING, MACAW_MAP);
    } else {
        c.sprite(ox - 10, g - 3, &MACAW_TAIL_GROUND, MACAW_MAP);
        if !sitting {
            let step = if st == Stance::Walk { if p.phase.sin() > 0.0 { 1 } else { 0 } } else { 0 };
            for (i, fx) in [ox + 5, ox + 8].into_iter().enumerate() {
                let lift = if i == step && st == Stance::Walk { 1 } else { 0 };
                c.rect(fx + 1, g - 2, 1, 2 - lift, Col::Feet); c.hline(fx, fx + 2, g - lift, Col::Feet);
            }
        }
    }
    let wing_up = p.arm == Arm::Raised;
    c.sprite(ox, oy + 10, if wing_up { &MACAW_BODY_BARE } else { &MACAW_BODY }, MACAW_MAP);

    if p.prop == Prop::Laptop { draw_laptop(c, cx + 9, g); }
    if p.prop == Prop::Popcorn { draw_popcorn(c, cx + 9, g); }
    if p.prop == Prop::Calendar { draw_calendar(c, cx + 9, oy + 10); }
    if p.prop == Prop::Glass { draw_glass(c, cx + 9, oy + 11); }

    // the head: nods and pecks move it a few cells, its bottom rows drawn along the way so the neck stays joined
    let (mut dx, mut dy) = ((-2).max(3.min(p.head_dx)), (-3).max(3.min(p.head_dy)));
    if st == Stance::Eat { dx = 2; dy = 3; }
    let n = dx.abs().max(dy.abs());
    let neck = &MACAW_HEAD[MACAW_HEAD.len() - 3..];
    for k in 0..n {
        let (sx, sy) = (iround(f64::from(dx * k) / f64::from(n)), iround(f64::from(dy * k) / f64::from(n)));
        c.sprite(ox + sx, oy + 7 + sy, neck, MACAW_MAP);
    }
    c.sprite(ox + dx, oy + dy, &MACAW_HEAD, MACAW_MAP);
    let (hx, hy) = (ox + dx, oy + dy);
    profile_eye(c, p.eyes, hx + 8, hy + 5);
    if p.mouth != Mouth::Closed {
        c.hline(hx + 10, hx + 12, hy + 8, Col::Mouth);                 // the lower beak drops open
        c.hline(hx + 10, hx + 12, hy + 9, Col::BeakDark); c.hline(hx + 10, hx + 11, hy + 10, Col::BeakDark);
    }
    if p.blush { c.hline(hx + 7, hx + 8, hy + 7, Col::Blush); }
    if p.phones {
        // headphones fitted to its head: the pad over its ear behind the eye, the band up round the back of its crown
        if p.outfit.hat == Hat::None || p.nightcap {
            for (x, y) in [(4, 3), (4, 2), (5, 1), (6, 0), (7, 0), (8, -1), (9, -1), (10, 0)] { c.set(hx + x, hy + y, Col::Phones); }
        }
        c.rect(hx + 4, hy + 4, 2, 3, Col::PhonesPad);
        c.set(hx + 3, hy + 5, Col::Phones);
    }
    match p.arm {
        Arm::Raised => c.sprite(ox - 2, oy + 1, &MACAW_WING_UP, MACAW_MAP),
        Arm::Forward | Arm::Tap | Arm::Hold | Arm::Scoop | Arm::ToMouth => {
            // reaching forward (typing, holding): the wing stretches out in front, blue tips last
            let tip = if p.prop == Prop::Laptop { (cx + 10, g - if p.arm == Arm::Tap { 2 } else { 3 }) } else { (ox + 12, oy + 14) };
            c.thick(ox + 5, oy + 11, tip.0 - 1, tip.1, 2, Col::Wing);
            c.hline(tip.0 - 1, tip.0 + 1, tip.1 + 1, Col::WingDark);
        }
        _ => {}
    }
    Anchors { head_x: hx + 8, head_top: hy, head_w: 8, eyes: vec![(hx + 8, hy + 5)], profile: true, neck: (hx + 7, hy + 10), hat_dx: 0 }
}

// MARK: - Shark

/// A little shark facing right, leaping with its mouth open in a big happy gape, copied cell for cell from the reference
/// picture: its dorsal fin swept back, the cream face plate with a row of teeth top and bottom, the tail behind.
/// B blue, D deep blue, W cream, R inside its mouth, O tongue, P peachy belly, K lines.
const SHARK_ART: [&str; 23] = [
    "......................BBBBBB..",
    "....................BBBBBBBB..",
    "..................BBBBBBWWWW..",
    "................BBBBBBWWWWWWW.",
    "........BBBBBB.BBBBBBWWWWWWWW.",
    "......BBBBBBBKBBKWKBWWKKKKKKW.",
    "......DBBBBBKBBBKKKWWKWWWWWKW.",
    ".......DDDBBKBBBKKKWKWRWRRWKW.",
    "........DDDKBBBBBBWKRWRRRRRKW.",
    ".........DKBBBBBBWWKRRRRRRKWW.",
    "..B......DKBBBBBBWKRRRRRRRKW..",
    "..DD......BBBBBBWWKOROOORKKW..",
    "...DD....KBBBBBBWWKWOWOWOKWW..",
    "...DDD..DDBBBBBBBWWKWWOWWKW...",
    "....DDKDDDDBBBBBBWWWKKWWKWW...",
    "....DDDDDDDKDDDBBWWWWWKKWW....",
    ".....DDDDDKDDDDDKWWWWWWWWW....",
    ".....DKDDDKDDDDDKPWWWWWPWK....",
    "....KDKKPPKDDDDDKPWWWWPPKK....",
    "....DD.KPPKDDDDKPPPPPPPKDDD...",
    "...DD....KKDDDDKPPPPPPKKDDK...",
    "...D......DDDDKPPPPPP..KKDD...",
    "..........DD.............KK...",
];

/// The same with its mouth shut in a smile (asleep, or chewing).
const SHARK_ART_SHUT: [&str; 23] = [
    "......................BBBBBB..",
    "....................BBBBBBBB..",
    "..................BBBBBBWWWW..",
    "................BBBBBBWWWWWWW.",
    "........BBBBBB.BBBBBBWWWWWWWW.",
    "......BBBBBBBKBBKWKBWWWWWWWWW.",
    "......DBBBBBKBBBKKKWWWWWWWWWW.",
    ".......DDDBBKBBBKKKWWWWWWWWWW.",
    "........DDDKBBBBBBWWWWWWWWWWW.",
    ".........DKBBBBBBWWKWWWWWWKWW.",
    "..B......DKBBBBBBWWWKKKKKKWW..",
    "..DD......BBBBBBWWWWWWWWWWWW..",
    "...DD....KBBBBBBWWWWWWWWWWWW..",
    "...DDD..DDBBBBBBBWWWWWWWWWW...",
    "....DDKDDDDBBBBBBWWWWWWWWWW...",
    "....DDDDDDDKDDDBBWWWWWWWWW....",
    ".....DDDDDKDDDDDKWWWWWWWWW....",
    ".....DKDDDKDDDDDKPWWWWWPWK....",
    "....KDKKPPKDDDDDKPWWWWPPKK....",
    "....DD.KPPKDDDDKPPPPPPPKDDD...",
    "...DD....KKDDDDKPPPPPPKKDDK...",
    "...D......DDDDKPPPPPP..KKDD...",
    "..........DD.............KK...",
];

const SHARK_MAP: &[(u8, Col)] = &[(b'B', Col::Body), (b'D', Col::BodyShade), (b'W', Col::Belly), (b'R', Col::Mouth), (b'O', Col::Tongue),
    (b'P', Col::Mark), (b'K', Col::Outline)];

/// Bubbles the shark, side on. (The Mac app also has it seen from above while it swims, and facing you behind its book
/// when it studies; this port has neither swimming nor study mode, so it's always side on.)
/// Asleep, drawn exactly after the user's picture: lying flat out on the floor, its tail resting low on the left,
/// a big rounded back rising to its dorsal fin, its front fin swept back along its side, its white belly along the
/// floor, gill marks and a little mouth at its snout. B body, W belly, K lines.
const SHARK_SLEEPING: [&str; 18] = [
    ".......................BBB................",
    "......................BBBBB...............",
    ".....................BBBBBBBB.............",
    ".....................BBBBBBBBB............",
    "....................BBBBBBBBBBB...........",
    "..................BBBBBBBBBBBBBB..........",
    "...............BBBBBBBBBBBBBBBBBBBB.......",
    ".BBBBB.......BBBBBBBBBBBBBBBBBBBBBBBBB....",
    ".BBBBBBB....BBBBBBBBBBBBBBBBBBBBBBBBBBBB..",
    ".BBBBBBBBBKBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.",
    ".BBBBBBBBKBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.",
    ".BBBBBBBKBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
    ".BBBBBBKBBBBBBBBBBBBBBBBBKBBBBBBBBBBBBBBBB",
    ".BBBBBKBBBBBBBBBBBBBBBBKKBBBBBBBBBBBBBBBBB",
    ".BBBBKBBBBBBBBBBBBBBBKKBBBBBBBBBBBBBBBBBBB",
    "BBBBBKBBBBBBBBBBBBBBKBBBBBBBBBBBBBBBBBWWWW",
    "BBBBBKWWWWWWWWWWWWWKBBBBBBBBBKBKBBWWWWWWKK",
    "BBBBBKWWWWWWWWWWWWWKBBBBBBBBBKBKWWWWWWWWK.",
];

/// The sleeping shark's own nightcap, sat on the slope of its head (C cap, W white).
const SHARK_SLEEPING_CAP: [&str; 6] = [
    ".....CCCC......",
    "...CCCCCCCC....",
    "..CCCCCCCCCCCC.",
    ".CCCCCCCCCCCCCC",
    "WWWWWWCCCC...WW",
    "......WWWW...WW",
];

/// The shark fast asleep: its eye a sleepy little dash, popping open when something wakes it.
fn draw_sleeping_shark(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let (ox, oy) = (cx - 21, g - (SHARK_SLEEPING.len() as i32 - 1));
    c.sprite(ox, oy, &SHARK_SLEEPING, &[(b'B', Col::Body), (b'W', Col::Belly), (b'K', Col::Outline)]);
    if p.eyes == Eyes::Wide {
        c.rect(ox + 35, oy + 14, 2, 2, Col::Outline); c.set(ox + 35, oy + 14, Col::Belly);    // its eye pops open
    } else {
        c.hline(ox + 35, ox + 36, oy + 15, Col::Outline);                                       // eye shut
    }
    if p.nightcap {
        // its nightcap pulled on over its head, the tip flopping down in front of its nose
        c.sprite(ox + 31, oy + 2, &SHARK_SLEEPING_CAP, &[(b'C', Col::Cap), (b'W', Col::White)]);
    }
    if p.outfit.hat != Hat::None && !p.nightcap { shark_hat(c, p.outfit.hat, ox + 35, oy + 6); }
    let o = &p.outfit;
    // glasses over its eye, the arm running back along its head
    let lens = match o.glasses { Glasses::Shades => Some(Col::Lens), Glasses::Hearts => Some(Col::LensPink), _ => None };
    if let Some(l) = lens {
        c.rect(ox + 34, oy + 14, 4, 2, l);
        if o.glasses == Glasses::Hearts { c.set(ox + 36, oy + 14, Col::Body); c.set(ox + 35, oy + 14, Col::White); }
    } else if o.glasses == Glasses::Round {
        c.hline(ox + 34, ox + 37, oy + 13, Col::Frame); c.set(ox + 33, oy + 14, Col::Frame); c.set(ox + 38, oy + 14, Col::Frame);
        c.hline(ox + 34, ox + 37, oy + 16, Col::Frame);
    }
    if o.glasses != Glasses::None { c.hline(ox + 30, ox + 33, oy + 13, Col::Frame); }
    // its collar wraps round it behind its head, the bow tie, bell or bandana knot low down at its throat
    if o.neck != Neckwear::None && o.neck != Neckwear::Bowtie {
        let wide = if o.neck == Neckwear::Scarf { 3 } else { 2 };
        for y in 0..16 {
            for x in 31..31 + wide {
                if SHARK_SLEEPING[y as usize].as_bytes()[x as usize] == b'.' { continue; }
                let col = match o.neck {
                    Neckwear::Scarf => if y % 3 == 0 { Col::ScarfStripe } else { Col::Scarf },
                    Neckwear::Bandana => if y % 3 == 1 { Col::White } else { Col::HatBand },
                    _ => if x == 31 { Col::Collar } else { Col::HatBand },
                };
                c.set(ox + x, oy + y, col);
            }
        }
    }
    let art: (&[&str], &[(u8, Col)]) = match o.neck {
        Neckwear::Bowtie => (&["RR.RR", "RRKRR", "RR.RR"], &[(b'R', Col::Ruby), (b'K', Col::Outline)]),
        Neckwear::Bell => (&[".G.", "GWG", "GGG", ".K."], &[(b'G', Col::Gold), (b'W', Col::White), (b'K', Col::Outline)]),
        Neckwear::Bandana => (&["BBBB", "BWB.", "BB.."], &[(b'B', Col::HatBand), (b'W', Col::White)]),
        Neckwear::Scarf => (&["SSS", "SWS", "S.S"], &[(b'S', Col::Scarf), (b'W', Col::ScarfStripe)]),
        Neckwear::None => (&[], &[]),
    };
    let (kx, ky) = match o.neck { Neckwear::Bowtie => (30, 11), Neckwear::Bell => (31, 12), Neckwear::Bandana => (28, 13), _ => (28, 14) };
    c.sprite(ox + kx, oy + ky, art.0, art.1);
    Anchors { head_x: ox + 34, head_top: oy + 7, head_w: 8, eyes: vec![(ox + 35, oy + 15)], profile: true, neck: (ox + 30, oy + 10), hat_dx: 0 }
}

/// The shark sitting facing you, typing like the turtle (the Mac app also reads this way): fin on top, a round blue
/// head, shiny eyes set wide, rosy cheeks, a tiny open chomp in a cream face, fins out to the sides, peachy belly.
const SHARK_FRONT: [&str; 19] = [
    "..........B..........",
    ".........BBB.........",
    ".......BBBBBBB.......",
    ".....BBBBBBBBBBB.....",
    "....BBBBBBBBBBBBB....",
    "...BBBBBBBBBBBBBBB...",
    "...BBBBBBBBBBBBBBB...",
    "..BBBWKBBBBBBBWKBBB..",
    "..BDBKKBBBBBBBKKBDB..",
    "..BDBKKWWWWWWWKKBDB..",
    ".DBBWWWWKKKKKWWWWBBD.",
    "DDBWWWWKWRRRWKWWWWBDD",
    "DDBWWWWWKRORKWWWWWBDD",
    "D.BWWWWWWKKKWWWWWWB.D",
    "...BWWWWWWWWWWWWWB...",
    "...DBWWWWWWWWWWWBD...",
    "...DPPPPPPPPPPPPPD...",
    "...DDPPPPPPPPPPPDD...",
    "...DD.DDD...DDD.DD...",
];
/// The same with its mouth shut in a smile.
const SHARK_FRONT_SHUT: [&str; 19] = [
    "..........B..........",
    ".........BBB.........",
    ".......BBBBBBB.......",
    ".....BBBBBBBBBBB.....",
    "....BBBBBBBBBBBBB....",
    "...BBBBBBBBBBBBBBB...",
    "...BBBBBBBBBBBBBBB...",
    "..BBBWKBBBBBBBWKBBB..",
    "..BDBKKBBBBBBBKKBDB..",
    "..BDBKKWWWWWWWKKBDB..",
    ".DBBWWWWWWWWWWWWWBBD.",
    "DDBWWWWKWWWWWKWWWWBDD",
    "DDBWWWWWKKKKKWWWWWBDD",
    "D.BWWWWWWWWWWWWWWWB.D",
    "...BWWWWWWWWWWWWWB...",
    "...DBWWWWWWWWWWWBD...",
    "...DPPPPPPPPPPPPPD...",
    "...DDPPPPPPPPPPPDD...",
    "...DD.DDD...DDD.DD...",
];

fn draw_shark_front(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let (ox, oy) = (cx - 10, g - (SHARK_FRONT.len() as i32 - 1));
    let shut = p.mouth == Mouth::Closed && matches!(p.eyes, Eyes::Closed | Eyes::Half);
    let map = [(b'B', Col::Body), (b'D', Col::BodyShade), (b'W', Col::Belly), (b'R', Col::Mouth), (b'O', Col::Tongue), (b'P', Col::Mark), (b'K', Col::Outline)];
    c.sprite(ox, oy, if shut { &SHARK_FRONT_SHUT } else { &SHARK_FRONT }, &map);
    let eyes = vec![(ox + 5, oy + 7), (ox + 14, oy + 7)];
    for &(ex, ey) in &eyes {
        match p.eyes {
            Eyes::Closed | Eyes::Half => {                                    // sleepy, curved down
                c.rect(ex, ey, 2, 3, Col::Body); c.set(ex - 1, ey + 1, Col::Outline); c.hline(ex, ex + 1, ey + 2, Col::Outline); c.set(ex + 2, ey + 1, Col::Outline);
            }
            Eyes::Happy => {                                                  // ^ ^
                c.rect(ex, ey, 2, 3, Col::Body); c.set(ex - 1, ey + 2, Col::Outline); c.hline(ex, ex + 1, ey + 1, Col::Outline); c.set(ex + 2, ey + 2, Col::Outline);
            }
            Eyes::Angry | Eyes::Sad | Eyes::Dizzy => c.set(ex, ey, Col::Outline),   // no shine
            _ => {}
        }
    }
    c.hline(ox + 4, ox + 5, oy + 10, Col::Blush); c.hline(ox + 15, ox + 16, oy + 10, Col::Blush);   // rosy cheeks
    if p.phones {
        if p.outfit.hat == Hat::None || p.nightcap {
            for (x, y) in [(2, 4), (3, 3), (4, 2), (5, 1), (6, 1), (14, 1), (15, 1), (16, 2), (17, 3), (18, 4)] { c.set(ox + x, oy + y, Col::Phones); }
            c.hline(ox + 7, ox + 13, oy, Col::Phones);
        }
        c.rect(ox + 1, oy + 5, 2, 4, Col::PhonesPad); c.rect(ox + 18, oy + 5, 2, 4, Col::PhonesPad);
    }
    // (head_dy 99: just its face, for the pet picker)
    if p.head_dy == 99 { return Anchors { head_x: cx, head_top: oy + 2, head_w: 13, eyes, profile: false, neck: (cx, oy + 16), hat_dx: 0 }; }
    // typing: the laptop in front of it, the back of its screen towards you; it peeks over and taps with both fins
    let tap = p.arm == Arm::Tap;
    c.rect(cx - 6, g - 8, 13, 6, Col::LapDark);
    c.hline(cx - 6, cx + 6, g - 8, Col::LapLight); c.set(cx, g - 5, Col::LapLight);
    c.rect(cx - 8, g - 2, 17, 2, Col::LapLight);
    let up = ((p.phase * 10.0) as i32) % 2 == 0;
    c.rect(cx - 9, g - 4 - if tap && up { 1 } else { 0 }, 3, 2, Col::Body); c.rect(cx + 7, g - 4 - if tap && !up { 1 } else { 0 }, 3, 2, Col::Body);
    Anchors { head_x: cx, head_top: oy + 2, head_w: 13, eyes, profile: false, neck: (cx, oy + 16), hat_dx: 0 }
}

/// Lying asleep on the floor (drawn with `draw_sleeping_shark`).
fn shark_sleeps(p: &Pose) -> bool {
    (p.asleep || (p.nightcap && p.eyes == Eyes::Closed)) && !matches!(p.stance, Stance::Fly | Stance::Held | Stance::Umbrella | Stance::Leap | Stance::Walk)
}

fn draw_shark(c: &mut Canvas, p: &Pose, cx: i32) -> Anchors {
    let g = c.h - 2;
    let st = p.stance;
    let airborne = matches!(st, Stance::Fly | Stance::Held | Stance::Umbrella | Stance::Leap);
    if shark_sleeps(p) { return draw_sleeping_shark(c, p, cx); }
    if p.prop == Prop::Laptop && !airborne { return draw_shark_front(c, p, cx); }   // typing: sat facing you, like the turtle
    let ox = cx - 15;
    let oy = g - (SHARK_ART.len() as i32 - 1) + p.bob - if airborne { 3 } else { 0 } + if st == Stance::Squash { 1 } else { 0 };
    // always grinning, mouth wide open, except when it's asleep, chomping (eyes squeezed shut) or chewing
    // crawling, it snaps its jaws shut every few strides; it chomps along with its mouth when chattering or cross
    let snap = st == Stance::Walk && (p.phase * 0.25).sin() > 0.85;
    let shut = snap || (p.mouth == Mouth::Closed && (matches!(p.eyes, Eyes::Closed | Eyes::Half) || st == Stance::Eat || p.chomp));
    // flopping and swimming: the tail swishes and the whole body tips nose up and nose down
    let (mut tilt, mut tail_dy) = (0.0, 0);
    match st {
        Stance::Fly | Stance::Leap => {
            let s = (p.phase * 0.5).sin();
            tail_dy = iround(s * 1.4); tilt = s * 0.06;
        }
        Stance::Held | Stance::Umbrella => tilt = (p.phase * 1.6).sin() * 0.3,
        Stance::Eat => tilt = -0.2,                 // nose down to its snack
        Stance::Sit | Stance::Stand => tail_dy = iround(p.tail.sin() * 1.2),   // sat about, its tail sways lazily
        _ => {}
    }
    if p.arm == Arm::Raised && !matches!(st, Stance::Walk | Stance::Fly | Stance::Leap) { tail_dy = -2; }   // a flick of the tail
    if st == Stance::Umbrella { draw_umbrella(c, cx + 2, oy - 10, (cx + 2, oy + 6)); }   // the handle tucked behind it
    // crawling like a real shark out of water, in four clean beats: its tail (moved as one piece, so no pixels tear) sweeps
    // side to side, swinging towards you and away so it looks shorter, and up and down; the body slides forward on its belly
    let crawl = st == Stance::Walk;
    let beat = ((p.phase / (PI / 2.0)).floor() as i64).rem_euclid(4) as usize;
    let tail_beat = [(0, 0), (1, -1), (0, 0), (1, 1)][beat];
    let surge = if crawl { [0, 0, 1, 1][beat] } else { 0 };
    let at = |x: i32, y: i32| -> (i32, i32) {
        if crawl { return if x < 10 { (ox + x + surge + tail_beat.0, oy + y + tail_beat.1) } else { (ox + x + surge, oy + y) }; }
        (ox + x, oy + y - iround(tilt * f64::from(x - 15)) + if x < 10 { tail_dy } else { 0 })
    };
    let art: &[&str] = if shut { &SHARK_ART_SHUT } else { &SHARK_ART };
    for tail in [true, false] {                                     // the tail first, so the body covers the seam
        for (y, row) in art.iter().enumerate() {
            for (x, ch) in row.bytes().enumerate() {
                if (x < 10) != tail { continue; }
                if let Some(&(_, col)) = SHARK_MAP.iter().find(|m| m.0 == ch) {
                    let q = at(x as i32, y as i32);
                    c.set(q.0, q.1, col);
                }
            }
        }
    }
    if p.prop == Prop::Laptop { draw_laptop(c, cx + 15, g); }
    if p.prop == Prop::Popcorn { draw_popcorn(c, cx + 16, g); }
    if p.prop == Prop::Calendar { draw_calendar(c, cx + 16, oy + 4); }
    if p.prop == Prop::Glass { draw_glass(c, cx + 16, oy + 5); }

    // its eye: a dark square with a shine at the top, like the picture; a curve when shut or smiling
    let e = at(17, 6);
    let mut lid = |cells: &[(i32, i32)]| {
        for dy in -1..=1 { for dx in -1..=1 { c.set(e.0 + dx, e.1 + dy, Col::Body); } }
        for &(dx, dy) in cells { c.set(e.0 + dx, e.1 + dy, Col::Outline); }
    };
    match p.eyes {
        Eyes::Closed | Eyes::Half => lid(&[(-1, -1), (-1, 0), (0, 1), (1, 0), (1, -1)]),
        Eyes::Happy => lid(&[(-1, 1), (-1, 0), (0, -1), (1, 0), (1, 1)]),
        Eyes::Angry => {                                                  // narrowed, under a cross brow
            c.set(e.0 - 1, e.1 - 1, Col::Body); c.set(e.0, e.1 - 1, Col::Outline);
            for (dx, dy) in [(-2, -3), (-1, -3), (0, -2), (1, -2)] { c.set(e.0 + dx, e.1 + dy, Col::Outline); }
        }
        Eyes::Sad => {                                                    // a worried brow, no shine
            c.set(e.0, e.1 - 1, Col::Outline);
            for (dx, dy) in [(-2, -2), (-1, -3), (0, -3)] { c.set(e.0 + dx, e.1 + dy, Col::Outline); }
        }
        Eyes::Dizzy => lid(&[(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)]),
        Eyes::Wide => {                                                   // startled: the white of its eye round a tiny pupil
            for dy in -1..=1 { for dx in -1..=1 { c.set(e.0 + dx, e.1 + dy, Col::Belly); } }
            c.set(e.0, e.1, Col::Outline);
        }
        _ => {}
    }
    if p.blush { let b = at(15, 9); c.hline(b.0, b.0 + 1, b.1, Col::Blush); }
    if p.phones {
        // headphones fitted to its head: the pad behind its eye, the band over the top of its head
        if p.outfit.hat == Hat::None || p.nightcap {
            for (x, y) in [(14, 3), (15, 2), (16, 2), (17, 1), (18, 1), (19, 0), (20, 0), (21, -1), (22, -1), (23, -1), (24, -1)] {
                let q = at(x, y); c.set(q.0, q.1, Col::Phones);
            }
        }
        let pad = at(13, 4);
        c.rect(pad.0, pad.1, 2, 3, Col::PhonesPad);
    }
    shark_side_outfit(c, &p.outfit, art, &at);
    if p.outfit.hat != Hat::None && !p.nightcap { let h = at(22, 0); shark_hat(c, p.outfit.hat, h.0, h.1); }
    // hats sit on top of its head, above its eye, well back from its nose
    let (top, neck) = (at(20, 2), at(13, 10));
    Anchors { head_x: top.0, head_top: top.1, head_w: 8, eyes: vec![e], profile: true, neck, hat_dx: 0 }
}

/// Glasses and neckwear made for the shark's side view (`draw_pet` then leaves them off): the glasses sit over its eye
/// with the arm running back along its head; a shark has no neck, so a collar wraps right round its body behind its
/// gills, with the bow tie, bell or bandana knot at its throat.
fn shark_side_outfit(c: &mut Canvas, o: &Outfit, art: &[&str], at: &dyn Fn(i32, i32) -> (i32, i32)) {
    let mut put = |x: i32, y: i32, col: Col| { let q = at(x, y); c.set(q.0, q.1, col); };
    let _solid = |x: i32, y: i32| art.get(y as usize).and_then(|r| r.as_bytes().get(x as usize)).map_or(false, |&b| b != b'.');
    match o.glasses {
        Glasses::None => {}
        Glasses::Shades => {
            // a bar across the top, a rounded dark lens with a glint, the arm running back
            for x in 11..=20 { put(x, 5, Col::Frame); }
            for y in 6..=7 { for x in 15..=19 { put(x, y, Col::Lens); } }
            for x in 16..=18 { put(x, 8, Col::Lens); }
            put(16, 6, Col::White);
        }
        Glasses::Hearts => {
            for (x, y) in [(15, 5), (16, 5), (18, 5), (19, 5), (15, 6), (16, 6), (17, 6), (18, 6), (19, 6), (16, 7), (17, 7), (18, 7), (17, 8)] { put(x, y, Col::LensPink); }
            put(16, 5, Col::White); for x in 11..=14 { put(x, 5, Col::Frame); }
        }
        Glasses::Round => {
            // a big round frame with light glass round its eye, so the eye still shows through
            for x in 16..=18 { put(x, 3, Col::Frame); put(x, 9, Col::Frame); }
            for y in [4, 8] { put(15, y, Col::Frame); put(19, y, Col::Frame); }
            for y in 5..=7 { put(14, y, Col::Frame); put(20, y, Col::Frame); }
            for y in 4..=8 { for x in 15..=19 { if (x == 15 || x == 19) && (y == 4 || y == 8) { continue; } put(x, y, Col::Page); } }
            for (x, y) in [(17, 5), (18, 5), (17, 6), (18, 6), (17, 7), (18, 7)] { put(x, y, Col::Outline); }   // its eye through the glass
            put(17, 5, Col::White);
            for x in 11..=13 { put(x, 5, Col::Frame); }
        }
    }
    if o.neck == Neckwear::None { return; }
    // the collar hugs its throat just under its jaw, curving down round the front of it like a necklace
    const CURVE: [(i32, i32); 11] = [(15, 15), (16, 16), (17, 16), (18, 17), (19, 17), (20, 17), (21, 17), (22, 17), (23, 16), (24, 16), (25, 15)];
    let band = |rows: i32, put: &mut dyn FnMut(i32, i32, Col), col: &dyn Fn(i32, i32) -> Col| {
        for &(x, y) in &CURVE { for k in 0..rows { put(x, y + k - (rows - 2), col(x, k)); } }
    };
    let stamp = |rows: &[&str], x0: i32, y0: i32, put: &mut dyn FnMut(i32, i32, Col), map: &dyn Fn(u8) -> Option<Col>| {
        for (j, row) in rows.iter().enumerate() {
            for (i, ch) in row.bytes().enumerate() { if let Some(col) = map(ch) { put(x0 + i as i32, y0 + j as i32, col); } }
        }
    };
    match o.neck {
        Neckwear::Scarf => {
            // a chunky striped scarf wrapped round its throat, its end hanging down its front
            band(3, &mut put, &|x, k| if k == 1 && x % 3 == 0 { Col::ScarfStripe } else { Col::Scarf });
            stamp(&["SS", "WW", "SS", "S.S"], 19, 19, &mut put, &|ch| match ch { b'S' => Some(Col::Scarf), b'W' => Some(Col::ScarfStripe), _ => None });
        }
        Neckwear::Bowtie => stamp(&["RR.RR", "RRKRR", "RR.RR"], 18, 16, &mut put, &|ch| match ch { b'R' => Some(Col::Ruby), b'K' => Some(Col::Outline), _ => None }),
        Neckwear::Bell => {
            band(2, &mut put, &|_, k| if k == 0 { Col::Collar } else { Col::HatBand });
            stamp(&[".G.", "GWG", "GGG", ".K."], 19, 19, &mut put, &|ch| match ch { b'G' => Some(Col::Gold), b'W' => Some(Col::White), b'K' => Some(Col::Outline), _ => None });
        }
        Neckwear::Bandana => {
            // red with white spots, so it shows up on its blue
            band(2, &mut put, &|x, k| if k == 0 && x % 3 == 1 { Col::White } else { Col::HatBand });
            stamp(&["RRRRR", "RWRWR", ".RRR.", "..R.."], 18, 19, &mut put, &|ch| match ch { b'R' => Some(Col::HatBand), b'W' => Some(Col::White), _ => None });
        }
        Neckwear::None => {}
    }
}

/// A hat sat snug on the shark's head: centred on `at`, its bottom row on `bottom`, with the gap under its brim
/// filled in so it never floats over the slope of its head.
fn shark_hat(c: &mut Canvas, hat: Hat, x: i32, bottom: i32) {
    let art = hat_art_profile(hat).or_else(|| hat_art(hat));
    let Some((rows, map)) = art else { return };
    let w = rows.iter().map(|r| r.len() as i32).max().unwrap_or(0);
    let (x0, y0) = (x - w / 2, bottom - rows.len() as i32 + 1);
    let last = rows[rows.len() - 1].as_bytes();
    for (i, &ch) in last.iter().enumerate() {
        if ch == b'.' { continue; }
        let hx = x0 + i as i32;
        for y in bottom + 1..bottom + 2 {
            if c.get(hx, y) != Col::Clear.raw() { break; }
            c.set(hx, y, Col::Body);
        }
    }
    c.sprite(x0, y0, rows, map);
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
    let mut p = *p;
    let p = &mut p;
    let a = match sp {
        Species::Goose => draw_goose(c, p, cx),
        Species::Parrot => { let a = draw_parrot(c, p, cx); p.phones = false; a }          // it wears its own, fitted round its head
        Species::Shark => {
            let a = draw_shark(c, p, cx);
            p.phones = false;
            if shark_sleeps(p) { p.nightcap = false; p.outfit = Outfit::default(); }      // drawn to fit already
            else if a.profile { let night = p.nightcap; p.outfit = Outfit::default(); p.nightcap = night; }   // drawn to fit already
            else if p.prop == Prop::Laptop { p.outfit.neck = Neckwear::None; }            // behind the laptop
            a
        }
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
