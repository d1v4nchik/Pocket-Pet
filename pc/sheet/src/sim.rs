// A headless run of the whole world on a pretend 1920x1080 screen with a taskbar: types, goes fullscreen,
// feeds, throws a toy, lets a butterfly out, picks the pet up and throws it, naps, gets a water reminder.
// Prints what the pet does and saves a strip of frames, so the brain can be checked without Windows.

use pocket_pet_core::geom::{pt, Point, Rect};
use pocket_pet_core::image::Image;
use pocket_pet_core::items::ItemKind;
use pocket_pet_core::pet::Mode;
use pocket_pet_core::pets::Species;
use pocket_pet_core::state::Saved;
use pocket_pet_core::world::{Screen, Senses, World};

pub fn run(dir: &str, species: &str) {
    pocket_pet_core::rng::seed(7);
    std::fs::create_dir_all(dir).expect("output folder");
    let screens = vec![Screen { frame: Rect::new(0.0, 0.0, 1920.0, 1080.0), visible: Rect::new(0.0, 48.0, 1920.0, 1032.0) }];
    let k = 1.25;
    let mut st = Saved::default();
    st.water = 120.0;
    let mut w = World::new(&st, screens.clone(), k, 0.0, 1.0e9);
    w.change_species(Species::from_raw(species));
    w.start();
    let mut t = 0.0;
    let mut idle = 0.0;
    let mut last_mode = None;
    let mut frames: Vec<Image> = Vec::new();
    let mut ticks = 0u64;
    let mut mouse = pt(1500.0, 700.0);
    let mut held = false;
    let mut had_card = false;
    while t < 420.0 {
        let fps = w.wanted_fps();
        let dt = 1.0 / fps;
        t += dt;
        ticks += 1;
        let typing = (30.0..40.0).contains(&t);
        idle += dt;
        if typing || (140.0..146.0).contains(&t) { idle = 0.0; }
        let keys = if typing { 2 } else { 0 };
        // scripted moments
        let at = |s: f64| t >= s && t - dt < s;
        if at(80.0) { w.feed(ItemKind::Fish); }
        if at(100.0) { w.throw_ball(); }
        if at(120.0) { w.release_butterfly(); }
        if at(160.0) { w.toggle_nap(); }
        if at(175.0) { w.toggle_nap(); }
        if at(140.0) {
            // grab it by the middle
            let c = w.pet.center_point(&w.env);
            mouse = c;
            w.env.mouse = c;
            w.env.now = t;
            w.pet.mouse_down(&mut w.env);
            held = true;
        }
        if held && t < 141.0 {
            mouse = pt(mouse.x - 900.0 * dt, mouse.y + 500.0 * dt);
            w.env.mouse = mouse;
            w.env.now = t;
            w.pet.mouse_dragged(&mut w.env);
        }
        if held && t >= 141.0 { w.env.now = t; w.pet.mouse_up(&mut w.env); held = false; mouse = pt(1500.0, 700.0); }
        if matches!(w.water_card, Some(_)) && w.pet.mode == Mode::Agenda && w.env.t > 0.0 && ticks % 50 == 0 {
            w.drank_water();
        }
        w.tick(dt, Senses {
            now: t, screens: screens.clone(), px_per_pt: k, mouse, buttons_down: held, idle_secs: idle, keys,
            fullscreen: (60.0..70.0).contains(&t), local_hour: 14, day: "2026-10-29".into(), wall_dt: dt,
        });
        let p = &w.pet;
        assert!(p.x.is_finite() && p.y.is_finite(), "position went bad at {t}");
        let a = w.env.area(Point { x: p.x, y: p.y });
        if matches!(p.mode, Mode::Idle | Mode::Walk | Mode::Sleeping | Mode::Typing) {
            assert!(p.x >= a.min_x() - 1.0 && p.x <= a.max_x() + 1.0, "walked off screen at {t}: {}", p.x);
        }
        if w.water_card.is_some() != had_card { had_card = w.water_card.is_some(); println!("{t:7.2}s  water card {:?}", w.water_card); }
        if last_mode != Some(p.mode) {
            println!("{t:7.2}s  {:?}  at ({:.0}, {:.0}) edge {}  {} fps{}", p.mode, p.x, p.y, p.edge, fps,
                     p.current_bubble(&w.env).map(|b| format!("  says {:?}", b.join(" / "))).unwrap_or_default());
            last_mode = Some(p.mode);
            if frames.len() < 24 { frames.push(w.pet_image()); }
        }
    }
    println!("water progress {:.0} s", w.water_progress());
    println!("{ticks} frames in {t:.0} s of pet time: {:.1} a second on average", ticks as f64 / t);
    println!("food {:.0}, happiness {:.0}, energy {:.0}, glasses today {}", w.pet.fullness, w.pet.happiness, w.pet.energy, w.glasses_today);
    let cell = frames.first().map(|f| f.w).unwrap_or(1);
    let mut strip = Image::new(cell * 6, cell * frames.len().div_ceil(6) as i32);
    strip.fill_rect(0, 0, strip.w, strip.h, 0xfff4efe6);
    for (i, f) in frames.iter().enumerate() { strip.blit(f, (i % 6) as i32 * cell, (i / 6) as i32 * cell); }
    let path = format!("{dir}/sim-{species}.png");
    std::fs::write(&path, strip.png()).expect("write strip");
    println!("wrote {path}");
}
