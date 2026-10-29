// Offscreen renders of the menu and cards, light and dark, at 100% and 150%, with sample data.

use pocket_pet_core::geom::Rect;
use pocket_pet_core::image::Image;
use pocket_pet_core::pets::{Glasses, Hat, Neckwear, Outfit, Species};
use pocket_pet_core::state::Saved;
use pocket_pet_core::world::{Card, Screen, World};
use pocket_pet_ui::draw::Fonts;
use pocket_pet_ui::{card, panel, PanelInfo, PanelState, Theme};

pub fn run(dir: &str, regular: &str, bold: &str) {
    std::fs::create_dir_all(dir).expect("output folder");
    let mut fonts = Fonts::load(&std::fs::read(regular).expect("regular font"), &std::fs::read(bold).expect("bold font")).expect("fonts");
    let screens = vec![Screen { frame: Rect::new(0.0, 0.0, 1920.0, 1080.0), visible: Rect::new(0.0, 48.0, 1920.0, 1032.0) }];
    let mut w = World::new(&Saved::default(), screens, 1.0, 0.0, 1.0e9);
    w.change_species(Species::Tuxedo);
    w.pet.outfit = Outfit { hat: Hat::Party, glasses: Glasses::Round, neck: Neckwear::Scarf };
    w.pet.fullness = 22.0;
    w.pet.happiness = 88.0;
    w.pet.energy = 64.0;
    w.glasses_today = 3;
    let info = PanelInfo { autostart: true, version: "0.1.0" };
    for (dark, k) in [(false, 1.0f32), (true, 1.0), (false, 1.5)] {
        let th = Theme { dark, accent: 0x0067c0, k };
        let mut frames: Vec<Image> = Vec::new();
        for tab in 0..3u8 {
            let st = PanelState { tab, closet_part: 0, hover: if tab == 0 { Some(((60.0 * k) as i32, (110.0 * k) as i32)) } else { None }, ..Default::default() };
            frames.push(panel(&w, &st, &info, th, &mut fonts).img);
        }
        frames.push(card(&Card::Water { title: "Water break?".into(), glasses: 3, goal: 8, done: false }, th, &mut fonts, None).img);
        frames.push(card(&Card::Toast { title: "Pebble is hidden".into(), detail: "Press Ctrl+Alt+P, or click Pocket Pet's tray icon, to bring them back.".into() }, th, &mut fonts, None).img);
        let width: i32 = frames.iter().map(|f| f.w).sum();
        let height = frames.iter().map(|f| f.h).max().unwrap_or(1);
        let mut sheet = Image::new(width, height);
        sheet.fill_rect(0, 0, width, height, if dark { 0xff1c2a3a } else { 0xfff6ead8 });
        let mut x = 0;
        for f in &frames { sheet.blit(f, x, 0); x += f.w; }
        let path = format!("{dir}/menu-{}-{}.png", if dark { "dark" } else { "light" }, (k * 100.0) as i32);
        std::fs::write(&path, sheet.png()).expect("write");
        println!("wrote {path}");
    }
}
