// PNG sheets of the art, for looking at it without Windows.

use pocket_pet_core::art::{base_palette, make_palette, Canvas, Palette};
use pocket_pet_core::image::Image;
use pocket_pet_core::items::{icon_canvas, item_canvas, water_glass_canvas, Icon, ItemKind, BUTTERFLY_PALETTES};
use pocket_pet_core::pets::*;

const BG: u32 = 0xfff4efe6;

fn pet(sp: Species, p: &Pose, mirror: bool) -> Canvas {
    let mut c = Canvas::new(CANVAS_W, CANVAS_H);
    draw_pet(&mut c, sp, p, CANVAS_W / 2);
    if mirror { c.mirror(CANVAS_W / 2); }
    c.outline();
    c
}

fn save(dir: &str, name: &str, img: &Image) {
    let path = format!("{dir}/{name}.png");
    std::fs::write(&path, img.png()).unwrap_or_else(|e| panic!("can't write {path}: {e}"));
    println!("wrote {path}");
}

/// Cells in a grid, each `cw`x`ch` cells, scaled by `s`.
fn grid(cells: &[(Canvas, Palette)], cols: usize, cw: i32, ch: i32, s: i32) -> Image {
    let rows = cells.len().div_ceil(cols) as i32;
    let mut img = Image::new(cols as i32 * cw * s, rows * ch * s);
    img.fill_rect(0, 0, img.w, img.h, BG);
    for (i, (c, pal)) in cells.iter().enumerate() {
        let x = (i % cols) as i32 * cw * s + (cw - c.w) / 2 * s;
        let y = (i / cols) as i32 * ch * s + (ch - c.h) * s;
        c.draw(&mut img, x, y, s, pal);
    }
    img
}

pub fn write_all(dir: &str) {
    std::fs::create_dir_all(dir).expect("output folder");
    let pal = |sp: Species| make_palette(sp.colors());

    // the lineup: every pet standing and sitting
    let mut cells = Vec::new();
    for sp in Species::ALL {
        let stand = Pose::default();
        let sit = Pose { stance: if sp.is_bird() { Stance::Stand } else { Stance::Sit }, tail_up: false,
                         mouth: if sp.family() == Family::Dog { Mouth::Tongue } else { Mouth::Closed }, ..Pose::default() };
        cells.push((pet(sp, &stand, false).trimmed(1), pal(sp)));
        cells.push((pet(sp, &sit, false).trimmed(1), pal(sp)));
    }
    save(dir, "lineup", &grid(&cells, 6, 48, 40, 6));

    // every stance for every pet
    let mut cells = Vec::new();
    for sp in Species::ALL {
        for st in Stance::ALL {
            let p = Pose { stance: st, phase: 1.0, tail: 0.6, eyes: if st == Stance::Curl { Eyes::Closed } else { Eyes::Open }, ..Pose::default() };
            cells.push((pet(sp, &p, false), pal(sp)));
        }
    }
    save(dir, "stances", &grid(&cells, 14, CANVAS_W, CANVAS_H, 3));

    // faces
    let mut cells = Vec::new();
    for sp in Species::ALL {
        for e in Eyes::ALL {
            let p = Pose { stance: if sp.is_bird() { Stance::Stand } else { Stance::Sit }, eyes: e, ..Pose::default() };
            cells.push((pet(sp, &p, false), pal(sp)));
        }
    }
    save(dir, "faces", &grid(&cells, 9, CANVAS_W, CANVAS_H, 3));

    // the closet: every hat, glasses and neckwear on every pet
    let mut cells = Vec::new();
    for sp in Species::ALL {
        for h in Hat::ALL {
            let p = Pose { stance: if sp.is_bird() { Stance::Stand } else { Stance::Sit }, tail_up: false,
                           outfit: Outfit { hat: h, ..Outfit::default() }, ..Pose::default() };
            cells.push((pet(sp, &p, false), pal(sp)));
        }
        for (i, g) in Glasses::ALL.iter().enumerate() {
            let p = Pose { stance: if sp.is_bird() { Stance::Stand } else { Stance::Sit }, tail_up: false,
                           outfit: Outfit { glasses: *g, neck: Neckwear::ALL[(i + 1) % 5], ..Outfit::default() }, ..Pose::default() };
            cells.push((pet(sp, &p, false), pal(sp)));
        }
    }
    save(dir, "closet", &grid(&cells, 13, CANVAS_W, CANVAS_H, 3));

    // moments: typing, popcorn, water, asleep (the fox curled up), umbrella, held, headphones
    let mut cells = Vec::new();
    for sp in Species::ALL {
        let bird = sp.is_bird();
        let moments = [
            Pose { stance: Stance::Sit, prop: Prop::Laptop, arm: Arm::Tap, tail_up: false, head_dx: if sp == Species::Goose { 2 } else { 0 },
                   head_dy: if sp == Species::Goose { 8 } else { 1 }, ..Pose::default() },
            Pose { stance: Stance::Sit, prop: Prop::Popcorn, arm: if bird { Arm::Forward } else { Arm::Rest }, eyes: Eyes::Up, tail_up: false, ..Pose::default() },
            Pose { stance: Stance::Sit, prop: Prop::Glass, arm: if bird { Arm::Forward } else { Arm::Hold }, tail_up: false, ..Pose::default() },
            Pose { stance: if bird { Stance::Sit } else { Stance::Curl }, eyes: Eyes::Closed, nightcap: true,
                   head_dy: if sp == Species::Goose { 12 } else if bird { 3 } else { 0 }, ..Pose::default() },
            Pose { stance: Stance::Umbrella, eyes: Eyes::Happy, phase: 1.0, ..Pose::default() },
            Pose { stance: Stance::Held, eyes: Eyes::Wide, phase: 2.0, mouth: Mouth::Open, ..Pose::default() },
            Pose { stance: Stance::Walk, phase: 2.3, phones: true, eyes: Eyes::Happy, ..Pose::default() },
        ];
        for p in moments { cells.push((pet(sp, &p, false), pal(sp))); }
    }
    save(dir, "moments", &grid(&cells, 7, CANVAS_W, CANVAS_H, 3));

    // snacks, toys, butterflies, icons, the water glass
    let mut cells = Vec::new();
    for k in ItemKind::ALL { cells.push((item_canvas(k, 0, 0, 0), *base_palette())); }
    for k in [ItemKind::Fish, ItemKind::Cookie, ItemKind::Bone] { for b in 1..=2 { cells.push((item_canvas(k, b, 0, 0), *base_palette())); } }
    for (i, bp) in BUTTERFLY_PALETTES.iter().enumerate() { cells.push((item_canvas(ItemKind::Butterfly, 0, (i % 2) as i32, i as i32), make_palette(bp))); }
    for ic in Icon::ALL { cells.push((icon_canvas(ic), *base_palette())); }
    for g in [0, 3, 8] { cells.push((water_glass_canvas(g, 8), *base_palette())); }
    save(dir, "items", &grid(&cells, 10, 18, 18, 6));
}
