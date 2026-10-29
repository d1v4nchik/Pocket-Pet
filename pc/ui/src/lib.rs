// Pocket Pet's menu and cards, drawn in software into plain pictures so they look the same on every system and
// can be checked offscreen. Laid out like the Mac app's panel: what the pet is up to and its three needs,
// a row of things to do, then Pets / Closet / Settings. Grayscale pixel pictures, the system's accent color.

pub mod draw;

use draw::{pixel, rrect, rrect_stroke, shadow, Fonts};
use pocket_pet_core::art::{base_palette, gray_palette, make_palette, Canvas};
use pocket_pet_core::image::Image;
use pocket_pet_core::items::{icon_canvas, item_canvas, water_glass_canvas, Icon, ItemKind, BUTTERFLY_PALETTES};
use pocket_pet_core::pet::{face_canvas, Pet};
use pocket_pet_core::pets::{draw_accessory, Family, Glasses, Hat, Neckwear, Outfit, Species};
use pocket_pet_core::world::{Card, World};

/// Light or dark, the accent color and how many device pixels make a point.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Theme {
    pub dark: bool,
    pub accent: u32,      // 0xRRGGBB
    pub k: f32,
}

impl Theme {
    fn ink(&self) -> u32 { if self.dark { 0xebffffff } else { 0xe0000000 } }
    fn ink2(&self) -> u32 { if self.dark { 0x8cffffff } else { 0x80000000 } }
    fn bg(&self) -> u32 { if self.dark { 0xf72b2b2e } else { 0xf8ffffff } }
    fn border(&self) -> u32 { if self.dark { 0x1fffffff } else { 0x14000000 } }
    fn fill(&self) -> u32 { if self.dark { 0x30ffffff } else { 0x0f000000 } }
    fn fill_hover(&self) -> u32 { if self.dark { 0x42ffffff } else { 0x1a000000 } }
    fn off(&self) -> u32 { if self.dark { 0x2effffff } else { 0x24000000 } }
    fn accent(&self, a: u8) -> u32 { (a as u32) << 24 | (self.accent & 0xff_ffff) }
    fn p(&self, v: f32) -> f32 { (v * self.k).round() }
    fn pi(&self, v: f32) -> i32 { (v * self.k).round() as i32 }
}

/// Everything the menu and cards can do when clicked.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action {
    Feed(ItemKind), Toy, Butterfly, Nap, ComeHere,
    Tab(u8), Species(Species), ClosetPart(u8), Outfit(Outfit), Surprise, Undress,
    Gravity(bool), Size(i32), NapsAfter(i32), Water(i32), DrankWater, Sound(bool), Autostart(bool), EditName,
    Hide, Show, Quit,
    WaterLater, WaterDrank, DismissToast,
}

#[derive(Clone, Copy, Debug)]
pub struct Hit { pub x: i32, pub y: i32, pub w: i32, pub h: i32, pub action: Action }

/// A drawn menu or card: the picture (with room for its shadow), where its card sits inside it, and what's clickable.
pub struct Frame {
    pub img: Image,
    pub card: (i32, i32, i32, i32),
    pub hits: Vec<Hit>,
}

impl Frame {
    pub fn hit(&self, x: i32, y: i32) -> Option<Action> {
        self.hits.iter().find(|h| x >= h.x && y >= h.y && x < h.x + h.w && y < h.y + h.h).map(|h| h.action)
    }
}

/// What the menu remembers between redraws.
#[derive(Default)]
pub struct PanelState {
    pub tab: u8,
    pub closet_part: u8,
    pub editing: bool,
    pub draft: String,
    /// The pointer, in the frame's pixels.
    pub hover: Option<(i32, i32)>,
}

/// Things outside the world the menu shows.
pub struct PanelInfo { pub autostart: bool, pub version: &'static str }

const SHADOW: f32 = 22.0;

struct Ui<'a> {
    img: Image,
    th: Theme,
    f: &'a mut Fonts,
    hits: Vec<Hit>,
    tips: Vec<(usize, String)>,
    hover: Option<(i32, i32)>,
    x0: f32,            // content left edge, px
}

impl Ui<'_> {
    fn text(&mut self, s: &str, x: f32, y: f32, size: f32, bold: bool, color: u32) -> f32 {
        let px = size * self.th.k;
        self.f.draw(&mut self.img, s, x, y, px, bold, color)
    }
    fn width(&mut self, s: &str, size: f32, bold: bool) -> f32 { self.f.width(s, size * self.th.k, bold) }
    fn hovered(&self, x: f32, y: f32, w: f32, h: f32) -> bool {
        self.hover.map(|(hx, hy)| hx as f32 >= x && (hy as f32) >= y && (hx as f32) < x + w && (hy as f32) < y + h).unwrap_or(false)
    }
    fn hit(&mut self, x: f32, y: f32, w: f32, h: f32, action: Action, tip: &str) {
        self.hits.push(Hit { x: x as i32, y: y as i32, w: w.ceil() as i32, h: h.ceil() as i32, action });
        if !tip.is_empty() { self.tips.push((self.hits.len() - 1, tip.to_string())); }
    }

    /// A small rounded button showing a pixel picture; `selected` gets the accent outline.
    fn tile(&mut self, x: f32, y: f32, size: f32, pad: f32, pic: &Canvas, pal: &pocket_pet_core::art::Palette, selected: Option<bool>, action: Action, tip: &str) {
        let th = self.th;
        let s = th.p(size);
        let r = (s * 0.3).round();
        let on = selected == Some(true);
        let hot = self.hovered(x, y, s, s);
        rrect(&mut self.img, x, y, s, s, r, if hot && !on { th.fill_hover() } else { th.fill() });
        if on {
            rrect(&mut self.img, x, y, s, s, r, th.accent(56));
            rrect_stroke(&mut self.img, x, y, s, s, r, (1.5 * th.k).max(1.0), th.accent(230));
        }
        // just enough room around the picture for a whole-pixel scale, so it stays crisp
        let pad = th.p(pad);
        pixel(&mut self.img, pic, pal, (x + pad) as i32, (y + pad) as i32, (s - 2.0 * pad) as i32, (s - 2.0 * pad) as i32);
        self.hit(x, y, s, s, action, tip);
    }

    /// A capsule button; `strong` is filled with the accent color.
    fn pill(&mut self, label: &str, x: f32, y: f32, strong: bool, action: Action) -> f32 {
        let th = self.th;
        let size = 11.5;
        let tw = self.width(label, size, true);
        let w = tw + th.p(22.0);
        let h = th.p(24.0);
        let hot = self.hovered(x, y, w, h);
        let fill = if strong { th.accent(if hot { 220 } else { 255 }) } else if hot { th.fill_hover() } else { th.fill() };
        rrect(&mut self.img, x, y, w, h, h / 2.0, fill);
        let ty = y + (h - size * th.k * 1.2) / 2.0;
        self.text(label, x + th.p(11.0), ty, size, true, if strong { 0xffffffff } else { th.ink() });
        self.hit(x, y, w, h, action, "");
        w
    }

    /// Choices side by side in a track, the current one raised.
    fn segmented(&mut self, opts: &[(&str, Action)], current: usize, right: f32, y: f32) {
        let th = self.th;
        let size = 11.0;
        let pad = th.p(9.0);
        let ws: Vec<f32> = opts.iter().map(|o| self.width(o.0, size, false) + 2.0 * pad).collect();
        let total: f32 = ws.iter().sum::<f32>() + th.p(4.0);
        let h = th.p(24.0);
        let mut x = right - total;
        rrect(&mut self.img, x, y, total, h, th.p(7.0), th.fill());
        x += th.p(2.0);
        for (i, (label, action)) in opts.iter().enumerate() {
            let (sx, sy, sw, sh) = (x, y + th.p(2.0), ws[i], h - th.p(4.0));
            if i == current {
                rrect(&mut self.img, sx, sy, sw, sh, th.p(5.5), if th.dark { 0xff5a5a5e } else { 0xffffffff });
                rrect_stroke(&mut self.img, sx, sy, sw, sh, th.p(5.5), 1.0, th.border());
            } else if self.hovered(sx, sy, sw, sh) {
                rrect(&mut self.img, sx, sy, sw, sh, th.p(5.5), th.fill());
            }
            let tw = self.width(label, size, i == current);
            self.text(label, sx + (sw - tw) / 2.0, sy + (sh - size * th.k * 1.2) / 2.0, size, i == current, th.ink());
            self.hit(sx, sy, sw, sh, *action, "");
            x += sw;
        }
    }

    /// A Windows-style switch.
    fn toggle(&mut self, on: bool, right: f32, y: f32, action: Action) {
        let th = self.th;
        let (w, h) = (th.p(36.0), th.p(18.0));
        let x = right - w;
        if on { rrect(&mut self.img, x, y, w, h, h / 2.0, th.accent(255)); }
        else {
            rrect(&mut self.img, x, y, w, h, h / 2.0, th.fill());
            rrect_stroke(&mut self.img, x, y, w, h, h / 2.0, 1.0, th.ink2());
        }
        let d = h - th.p(8.0);
        let kx = if on { x + w - th.p(4.0) - d } else { x + th.p(4.0) };
        rrect(&mut self.img, kx, y + th.p(4.0), d, d, d / 2.0, if on { 0xffffffff } else { th.ink2() });
        self.hit(x, y, w, h, action, "");
    }

    /// A settings row: label on the left; returns the row's top.
    fn label(&mut self, y: f32, label: &str) {
        let th = self.th;
        let x0 = self.x0;
        self.text(label, x0, y + th.p(4.0), 12.0, false, th.ink());
    }
}

fn gray_item(k: ItemKind) -> (Canvas, pocket_pet_core::art::Palette) {
    // the monarch reads best in gray
    let pal = if k == ItemKind::Butterfly { gray_palette(&make_palette(&BUTTERFLY_PALETTES[5])) } else { gray_palette(base_palette()) };
    (item_canvas(k, 0, 0, 0).trimmed(0), pal)
}

fn gray_icon(i: Icon) -> (Canvas, pocket_pet_core::art::Palette) { (icon_canvas(i).trimmed(0), gray_palette(base_palette())) }

/// Wraps content into a card: soft shadow, rounded background, a hairline border.
fn finish(content: Image, cw: i32, ch: i32, th: &Theme, hits: Vec<Hit>, radius: f32) -> Frame {
    let m = th.pi(SHADOW);
    let mut img = Image::new(cw + 2 * m, ch + 2 * m);
    let r = th.p(radius);
    shadow(&mut img, m as f32, m as f32 + th.p(4.0), cw as f32, ch as f32, r, th.pi(16.0), if th.dark { 0x8c000000 } else { 0x38000000 });
    rrect(&mut img, m as f32, m as f32, cw as f32, ch as f32, r, th.bg());
    rrect_stroke(&mut img, m as f32, m as f32, cw as f32, ch as f32, r, 1.0, th.border());
    img.blit(&content, m, m);
    let hits = hits.into_iter().map(|h| Hit { x: h.x + m, y: h.y + m, ..h }).collect();
    Frame { img, card: (m, m, cw, ch), hits }
}

/// The menu: what the pet is up to, its needs, things to do, then Pets / Closet / Settings.
pub fn panel(world: &World, st: &PanelState, info: &PanelInfo, th: Theme, fonts: &mut Fonts) -> Frame {
    let pet = &world.pet;
    let w = th.pi(318.0);
    let m = th.pi(SHADOW);
    let pad = th.p(16.0);
    let mut ui = Ui { img: Image::new(w, th.pi(900.0)), th, f: fonts, hits: Vec::new(), tips: Vec::new(),
                      hover: st.hover.map(|(x, y)| (x - m, y - m)), x0: pad };
    let right = w as f32 - pad;
    let mut y = pad;

    // header: mood, and the three needs as little game-style meters
    ui.text(&world.mood(), pad, y, 14.0, true, th.ink());
    if world.env.hidden {
        let lw = ui.width("Show pet", 11.5, true) + th.p(22.0);
        ui.pill("Show pet", right - lw, y - th.p(3.0), true, Action::Show);
    }
    y += th.p(26.0);
    let meters: [((Canvas, pocket_pet_core::art::Palette), f64, &str); 3] =
        [(gray_item(ItemKind::Fish), pet.fullness, "Food"), (gray_icon(Icon::Heart), pet.happiness, "Happiness"), (gray_icon(Icon::Bolt), pet.energy, "Energy")];
    let mut x = pad;
    for (pic, value, name) in meters.iter() {
        let s = th.p(20.0);
        pixel(&mut ui.img, &pic.0, &pic.1, x as i32, y as i32, s as i32, s as i32);
        let lit = (value / 100.0 * 6.0).ceil() as i32;
        let bx = x + s + th.p(5.0);
        let b = th.p(8.0);
        for i in 0..6 {
            let col = if i < lit { th.accent(if lit <= 1 { 140 } else { 255 }) } else { th.off() };
            rrect(&mut ui.img, bx + i as f32 * (b + th.p(2.0)), y + (s - b) / 2.0, b, b, th.p(1.5), col);
        }
        let mw = s + th.p(5.0) + 6.0 * b + 5.0 * th.p(2.0);
        ui.hit(x, y, mw, s, Action::Tab(255), &format!("{name}: {}%", value.round() as i32));
        x += mw + th.p(12.0);
    }
    y += th.p(20.0) + th.p(12.0);

    // things to do: these close the menu so you see the pet act right away
    let toy = if pet.family() == Family::Cat { ItemKind::Yarn } else { ItemKind::Ball };
    let tiles: [((Canvas, pocket_pet_core::art::Palette), Action, String); 7] = [
        (gray_item(ItemKind::Fish), Action::Feed(ItemKind::Fish), "Feed: Fish".into()),
        (gray_item(ItemKind::Bone), Action::Feed(ItemKind::Bone), "Feed: Bone".into()),
        (gray_item(ItemKind::Cookie), Action::Feed(ItemKind::Cookie), "Feed: Cookie".into()),
        (gray_item(toy), Action::Toy, "Throw a toy".into()),
        (gray_item(ItemKind::Butterfly), Action::Butterfly, "Let a butterfly out".into()),
        (gray_icon(if pet.is_asleep() { Icon::Sun } else { Icon::Moon }), Action::Nap, if pet.is_asleep() { "Wake up".into() } else { "Nap".into() }),
        (gray_icon(Icon::Pin), Action::ComeHere, "Come here: follows your cursor for a minute".into()),
    ];
    let mut x = pad;
    for (pic, action, tip) in tiles.iter() {
        ui.tile(x, y, 34.0, 2.0, &pic.0, &pic.1, None, *action, tip);
        x += th.p(34.0) + th.p(7.0);
    }
    y += th.p(34.0) + th.p(14.0);

    // tabs
    let mut x = pad;
    for (i, title) in ["Pets", "Closet", "Settings"].iter().enumerate() {
        let sel = st.tab == i as u8;
        let tw = ui.width(title, 12.0, sel);
        let hot = ui.hovered(x, y, tw, th.p(20.0));
        ui.text(title, x, y, 12.0, sel, if sel || hot { th.ink() } else { th.ink2() });
        if sel { rrect(&mut ui.img, x, y + th.p(17.0), tw, th.p(2.0), th.p(1.0), th.accent(255)); }
        ui.hit(x, y - th.p(3.0), tw, th.p(24.0), Action::Tab(i as u8), "");
        x += tw + th.p(16.0);
    }
    y += th.p(19.0) + th.p(14.0);

    match st.tab {
        0 => {
            // rows of five, so every pet fits
            let size = th.p(48.0);
            let gap = (right - pad - 5.0 * size) / 4.0;
            for (i, sp) in Species::ALL.iter().enumerate() {
                let (cx, cy) = (pad + (i % 5) as f32 * (size + gap), y + (i / 5) as f32 * (size + th.p(8.0)));
                let face = face_canvas(*sp, Outfit::default(), false);
                ui.tile(cx, cy, 48.0, 5.0, &face, &gray_palette(&make_palette(sp.colors())), Some(pet.species == *sp), Action::Species(*sp), sp.title());
            }
            y += 2.0 * size + th.p(8.0);
        }
        1 => {
            // dress-up: your pet big on the left in its outfit, one kind of item at a time on the right
            let (bw, bh) = (th.p(78.0), th.p(104.0));
            rrect(&mut ui.img, pad, y, bw, bh, th.p(16.0), th.fill());
            let body = Pet::portrait_canvas(pet.species, pet.outfit).trimmed(1);
            pixel(&mut ui.img, &body, &gray_palette(&make_palette(pet.species.colors())), (pad + th.p(10.0)) as i32, (y + th.p(10.0)) as i32,
                  (bw - th.p(20.0)) as i32, (bh - th.p(20.0)) as i32);
            let rx = pad + bw + th.p(12.0);
            let mut px = rx;
            for (i, name) in ["Hats", "Glasses", "Neck"].iter().enumerate() {
                px += ui.pill(name, px, y, st.closet_part == i as u8, Action::ClosetPart(i as u8)) + th.p(5.0);
            }
            let gy = y + th.p(24.0) + th.p(9.0);
            let o = pet.outfit;
            let choices: Vec<(Outfit, Outfit, bool, &str)> = match st.closet_part {
                0 => Hat::ALL.iter().map(|h| (Outfit { hat: *h, ..o }, Outfit { hat: *h, ..Outfit::default() }, o.hat == *h, h.title())).collect(),
                1 => Glasses::ALL.iter().map(|g| (Outfit { glasses: *g, ..o }, Outfit { glasses: *g, ..Outfit::default() }, o.glasses == *g, g.title())).collect(),
                _ => Neckwear::ALL.iter().map(|n| (Outfit { neck: *n, ..o }, Outfit { neck: *n, ..Outfit::default() }, o.neck == *n, n.title())).collect(),
            };
            let size = th.p(40.0);
            let gap = th.p(6.0);
            for (i, (outfit, alone, picked, title)) in choices.iter().enumerate() {
                let (cx, cy) = (rx + (i % 4) as f32 * (size + gap), gy + (i / 4) as f32 * (size + gap));
                let mut c = Canvas::new(32, 28);
                draw_accessory(&mut c, *alone);
                if c.bounds().is_some() {
                    c.outline();
                    ui.tile(cx, cy, 40.0, 6.0, &c.trimmed(1), &gray_palette(base_palette()), Some(*picked), Action::Outfit(*outfit), title);
                } else {
                    // "none": an empty circle with a slash
                    let mut none = Canvas::new(9, 9);
                    none.ellipse(4.0, 4.0, 4.0, 4.0, pocket_pet_core::art::Col::Outline);
                    none.ellipse(4.0, 4.0, 3.0, 3.0, pocket_pet_core::art::Col::Clear);
                    none.thick(6, 2, 2, 6, 1, pocket_pet_core::art::Col::Outline);
                    ui.tile(cx, cy, 40.0, 11.0, &none, &gray_palette(base_palette()), Some(*picked), Action::Outfit(*outfit), title);
                }
            }
            let rows = choices.len().div_ceil(4) as f32;
            let by = gy + rows * size + (rows - 1.0) * gap + th.p(9.0);
            let sw = ui.pill("Surprise me", rx, by, false, Action::Surprise);
            ui.pill("Undress", rx + sw + th.p(5.0), by, false, Action::Undress);
            y = (by + th.p(24.0)).max(y + bh);
        }
        _ => {
            let row = th.p(30.0);
            ui.label(y, "Gravity");
            ui.toggle(world.env.gravity, right, y + th.p(3.0), Action::Gravity(!world.env.gravity));
            y += row;
            ui.label(y, "Size");
            let size_i = match world.env.size_setting { 3 => 0, 5 => 2, _ => 1 };
            ui.segmented(&[("S", Action::Size(3)), ("M", Action::Size(4)), ("L", Action::Size(5))], size_i, right, y);
            y += row;
            ui.label(y, "Naps after");
            let naps = [60, 120, 300, 600];
            let cur = naps.iter().position(|n| *n as f64 == world.env.sleep_after).unwrap_or(1);
            ui.segmented(&[("1 min", Action::NapsAfter(60)), ("2", Action::NapsAfter(120)), ("5", Action::NapsAfter(300)), ("10", Action::NapsAfter(600))], cur, right, y);
            y += row;
            ui.label(y, "Water reminders");
            let every = [0, 1800, 3600, 7200];
            let cur = every.iter().position(|n| *n as f64 == world.env.water_every).unwrap_or(2);
            ui.segmented(&[("Off", Action::Water(0)), ("30 min", Action::Water(1800)), ("1 h", Action::Water(3600)), ("2 h", Action::Water(7200))], cur, right, y);
            y += row;
            ui.label(y, &format!("Water today: {} of {}", world.glasses_today, pocket_pet_core::world::WATER_GOAL));
            let lw = ui.width("+1 glass", 11.5, true) + th.p(22.0);
            ui.pill("+1 glass", right - lw, y, false, Action::DrankWater);
            ui.tips.push((ui.hits.len() - 1, "Had a glass of water? Count it".into()));
            y += row;
            ui.label(y, "Name");
            let (fw, fh) = (th.p(140.0), th.p(24.0));
            let fx = right - fw;
            rrect(&mut ui.img, fx, y, fw, fh, th.p(6.0), th.fill());
            if st.editing {
                rrect_stroke(&mut ui.img, fx, y, fw, fh, th.p(6.0), (1.5 * th.k).max(1.0), th.accent(255));
                let shown = st.draft.clone();
                let tw = ui.text(&shown, fx + th.p(8.0), y + th.p(4.5), 12.0, false, th.ink());
                rrect(&mut ui.img, fx + th.p(8.0) + tw + 1.0, y + th.p(5.0), (th.k).max(1.0), th.p(14.0), 0.0, th.accent(255));
            } else {
                let name = ui.f.fit(&pet.name, 12.0 * th.k, false, fw - th.p(16.0));
                ui.text(&name, fx + th.p(8.0), y + th.p(4.5), 12.0, false, th.ink());
            }
            ui.hit(fx, y, fw, fh, Action::EditName, "Click to rename, Enter to keep it");
            y += row;
            ui.label(y, "Sounds");
            ui.toggle(world.env.sound_on, right, y + th.p(3.0), Action::Sound(!world.env.sound_on));
            y += row;
            ui.label(y, "Start with Windows");
            ui.toggle(info.autostart, right, y + th.p(3.0), Action::Autostart(!info.autostart));
            y += row + th.p(2.0);
            let hide = if world.env.hidden { ("Show pet", Action::Show) } else { ("Hide pet", Action::Hide) };
            ui.pill(hide.0, pad, y, false, hide.1);
            ui.tips.push((ui.hits.len() - 1, "Ctrl+Alt+P brings your pet back (or opens this menu)".into()));
            let qw = ui.width("Quit", 11.5, true) + th.p(22.0);
            ui.pill("Quit", right - qw, y, false, Action::Quit);
            y += th.p(24.0);
        }
    }

    // footer: what the thing under the pointer does, otherwise the version
    y += th.p(12.0);
    let tip = ui.hover.and_then(|(hx, hy)| {
        ui.hits.iter().position(|h| hx >= h.x && hy >= h.y && hx < h.x + h.w && hy < h.y + h.h)
            .and_then(|i| ui.tips.iter().find(|t| t.0 == i).map(|t| t.1.clone()))
    });
    let line = tip.unwrap_or_else(|| format!("Pocket Pet {}", info.version));
    let line = ui.f.fit(&line, 10.5 * th.k, false, right - pad);
    ui.text(&line, pad, y, 10.5, false, th.ink2());
    y += th.p(14.0) + pad;

    let h = y.ceil() as i32;
    let mut content = Image::new(w, h);
    content.blit(&ui.img, 0, 0);
    let hits: Vec<Hit> = ui.hits.into_iter().filter(|h| h.action != Action::Tab(255)).collect();
    finish(content, w, h, &th, hits, 16.0)
}

/// A card by the pet: the water reminder, or a short note.
pub fn card(c: &Card, th: Theme, fonts: &mut Fonts, hover: Option<(i32, i32)>) -> Frame {
    let m = th.pi(SHADOW);
    match c {
        Card::Water { title, glasses, goal, done } => {
            let w = th.pi(262.0);
            let mut ui = Ui { img: Image::new(w, th.pi(200.0)), th, f: fonts, hits: Vec::new(), tips: Vec::new(),
                              hover: hover.map(|(x, y)| (x - m, y - m)), x0: th.p(13.0) };
            let glass = water_glass_canvas(*glasses, *goal);
            let gs = ((th.k * 4.0).round() as i32).max(2);
            let (gw, gh) = (glass.w * gs, glass.h * gs);
            let tx = th.p(13.0) + gw as f32 + th.p(12.0);
            let mut y = th.p(11.0);
            let head = if *done { if glasses >= goal { format!("All {goal} glasses!") } else { "Nice, keep it up!".into() } } else { title.clone() };
            ui.text(&head, tx, y, 12.5, true, th.ink());
            y += th.p(19.0);
            let sub = if *glasses == 0 { "Your first glass today".to_string() } else { format!("{glasses} of {goal} glasses today") };
            ui.text(&sub, tx, y, 11.0, false, th.ink2());
            y += th.p(18.0);
            for i in 0..*goal {
                let col = if i < *glasses { 0xff3d9bf0 } else { th.off() };
                rrect(&mut ui.img, tx + i as f32 * th.p(16.0), y, th.p(13.0), th.p(4.0), th.p(2.0), col);
            }
            y += th.p(4.0);
            if !*done {
                y += th.p(8.0);
                let lw = ui.pill("Later", tx, y, false, Action::WaterLater);
                ui.pill("I drank some", tx + lw + th.p(6.0), y, true, Action::WaterDrank);
                y += th.p(24.0);
            }
            y += th.p(11.0);
            let h = (y.ceil() as i32).max(gh + th.pi(22.0));
            glass.draw(&mut ui.img, th.pi(13.0), (h - gh) / 2, gs, base_palette());
            let mut content = Image::new(w, h);
            content.blit(&ui.img, 0, 0);
            finish(content, w, h, &th, ui.hits, 16.0)
        }
        Card::Toast { title, detail } => {
            let w = th.pi(240.0);
            let mut ui = Ui { img: Image::new(w, th.pi(200.0)), th, f: fonts, hits: Vec::new(), tips: Vec::new(), hover: None, x0: th.p(13.0) };
            let mut y = th.p(10.0);
            ui.text(title, th.p(13.0), y, 12.5, true, th.ink());
            y += th.p(18.0);
            let lines = ui.f.wrap(detail, 11.0 * th.k, false, w as f32 - th.p(26.0));
            for l in lines { ui.text(&l, th.p(13.0), y, 11.0, false, th.ink2()); y += th.p(14.5); }
            y += th.p(10.0);
            let h = y.ceil() as i32;
            let mut content = Image::new(w, h);
            content.blit(&ui.img, 0, 0);
            finish(content, w, h, &th, vec![Hit { x: 0, y: 0, w, h, action: Action::DismissToast }], 16.0)
        }
    }
}

/// The tray icon: the pet's face in full color, `size` pixels square.
pub fn tray_icon(sp: Species, size: i32) -> Image {
    let face = face_canvas(sp, Outfit::default(), false).trimmed(0);
    let mut img = Image::new(size, size);
    let pal = make_palette(sp.colors());
    let s = (size / face.w.max(face.h)).max(1);
    if s * face.w.max(face.h) <= size {
        face.draw(&mut img, (size - face.w * s) / 2, (size - face.h * s) / 2, s, &pal);
    }
    img
}
