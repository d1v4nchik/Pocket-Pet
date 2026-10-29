// Offscreen tools for checking the art without Windows:
//   check <oracle.txt>   compares every drawing the Mac app dumped (tools/oracle) with this port, cell for cell
//   sheet <dir>          writes PNG sheets of every pet, pose, outfit, snack and icon

use pocket_pet_core::art::{base_palette, draw_bubble, make_palette, sanitize, text_width, Canvas};
use pocket_pet_core::image::Image;
use pocket_pet_core::items::{icon_canvas, item_canvas, Icon, ItemKind};
use pocket_pet_core::pets::*;
use std::process::exit;

mod sheets;
mod sim;
mod menus;

fn rle(px: &[u8]) -> String {
    let mut s = String::new();
    let mut i = 0;
    while i < px.len() {
        let mut n = 1;
        while i + n < px.len() && px[i + n] == px[i] { n += 1; }
        s += &format!("{}*{} ", px[i], n);
        i += n;
    }
    s
}

fn rle32(px: &[u32]) -> String {
    let mut s = String::new();
    let mut i = 0;
    while i < px.len() {
        let mut n = 1;
        while i + n < px.len() && px[i + n] == px[i] { n += 1; }
        s += &format!("{:x}*{} ", px[i], n);
        i += n;
    }
    s
}

fn f(bits: &str) -> f64 { f64::from_bits(u64::from_str_radix(bits, 16).expect("double bits")) }

fn check(path: &str) {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| { eprintln!("can't read {path}: {e}"); exit(2) });
    let (mut ok, mut bad) = (0, 0);
    let mut first_bad: Vec<String> = Vec::new();
    for line in text.lines() {
        let Some((head, want)) = line.split_once(" | ") else { continue };
        let a: Vec<&str> = head.split(' ').collect();
        let n = |i: usize| -> i32 { a[i].parse().unwrap() };
        let got = match a[0] {
            "P" => {
                let sp = Species::ALL[n(1) as usize];
                let p = Pose {
                    stance: Stance::ALL[n(2) as usize], eyes: Eyes::ALL[n(3) as usize], mouth: Mouth::ALL[n(4) as usize],
                    arm: Arm::ALL[n(5) as usize], prop: Prop::ALL[n(6) as usize], phase: f(a[7]), tail: f(a[8]),
                    bob: n(9), head_dx: n(10), head_dy: n(11), tail_up: n(12) == 1, ears_flat: n(13) == 1, blush: n(14) == 1,
                    nightcap: n(15) == 1, phones: n(16) == 1, wiggle: n(17),
                    outfit: Outfit { hat: Hat::ALL[n(18) as usize], glasses: Glasses::ALL[n(19) as usize], neck: Neckwear::ALL[n(20) as usize] },
                };
                let mut c = Canvas::new(CANVAS_W, CANVAS_H);
                let an = draw_pet(&mut c, sp, &p, CANVAS_W / 2);
                if n(21) == 1 { c.mirror(CANVAS_W / 2); }
                if n(22) == 1 { c.flip_v(); }
                c.outline();
                if an.head_x != n(23) || an.head_top != n(24) {
                    format!("anchors {} {}", an.head_x, an.head_top)
                } else { rle(&c.px) }
            }
            "I" => rle(&item_canvas(ItemKind::ALL[n(1) as usize], n(2), n(3), n(4)).px),
            "N" => rle(&icon_canvas(Icon::ALL[n(1) as usize]).px),
            "A" => {
                let mut c = Canvas::new(32, 28);
                draw_accessory(&mut c, Outfit { hat: Hat::ALL[n(1) as usize], glasses: Glasses::ALL[n(2) as usize], neck: Neckwear::ALL[n(3) as usize] });
                c.outline();
                rle(&c.px)
            }
            "X" => {
                let mut c = Canvas::new(CANVAS_W, CANVAS_H);
                draw_particle(&mut c, &Particle { kind: PKind::ALL[n(1) as usize], x: f(a[3]), y: f(a[4]), vx: 0.0, vy: 0.0, life: 1.0, gravity: 0.0, size: n(2) });
                rle(&c.px)
            }
            "B" => {
                let sets: [&[&str]; 8] = [&["HI!"], &["HONK"], &["HI! I'M HONK", "DRAG ME AROUND!"], &["MY FAVORITE!"], &["♥"], &["A", "B", "C"], &["GOOD MORNING!"], &["?"]];
                let lines: Vec<String> = sets[n(1) as usize].iter().map(|s| s.to_string()).collect();
                let px = n(2);
                let mut img = Image::new(n(5), n(6));
                draw_bubble(&mut img, &lines, 0, if n(4) == 1 { 3 * px } else { 0 }, f(a[3]), px, n(4) == 1);
                rle32(&img.px)
            }
            "T" => {
                let s: String = a[1].split(',').map(|h| char::from_u32(u32::from_str_radix(h, 16).unwrap()).unwrap()).collect();
                let san = sanitize(&s);
                let w = text_width(&san);
                let want_parts: Vec<&str> = want.split(" | ").collect();
                if want_parts.len() == 2 && want_parts[0] == san && want_parts[1].trim() == w.to_string() { ok += 1; continue; }
                bad += 1;
                if first_bad.len() < 12 { first_bad.push(format!("{head} => got {san:?} {w}, want {want}")); }
                continue;
            }
            _ => continue,
        };
        if got.trim_end() == want.trim_end() { ok += 1 } else {
            bad += 1;
            if first_bad.len() < 12 { first_bad.push(head.to_string()); }
        }
    }
    println!("{ok} drawings match the Mac app, {bad} differ");
    for b in &first_bad { println!("  differs: {b}"); }
    if bad > 0 || ok == 0 { exit(1); }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("check") if args.len() > 2 => check(&args[2]),
        Some("sheet") if args.len() > 2 => sheets::write_all(&args[2]),
        Some("menus") if args.len() > 4 => menus::run(&args[2], &args[3], &args[4]),
        Some("sim") if args.len() > 2 => sim::run(&args[2], args.get(3).map(|s| s.as_str()).unwrap_or("goose")),
        _ => { eprintln!("usage: pocket-pet-sheet check <oracle.txt> | sheet <dir>"); exit(2) }
    }
    let _ = (base_palette(), make_palette(&[]));
}
