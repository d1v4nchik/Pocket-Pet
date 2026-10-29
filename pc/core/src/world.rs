// Everything around the pet: senses (typing, idle, fullscreen), snacks and toys, settings, saving,
// water reminders and the cards. A port of the platform-free parts of the Mac app's World.swift.
// The platform fills in the senses and draws; the world decides.

use crate::geom::{clamp, pt, Point, Rect};
use crate::image::Image;
use crate::item::Item;
use crate::items::ItemKind;
use crate::pet::{Mode, Pet, PetRecord};
use crate::pets::{Family, Glasses, Hat, Neckwear, Outfit, Species, CANVAS_H, CANVAS_W};
use crate::rng;
use crate::state;

/// One display: its whole frame and the part apps get (without the taskbar), in points, y up.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Screen { pub frame: Rect, pub visible: Rect }

/// A card by the pet.
#[derive(Clone, Debug, PartialEq)]
pub enum Card {
    /// The water reminder ("I drank some" / "Later"), or the glass filling up after a sip (`done`).
    Water { title: String, glasses: i32, goal: i32, done: bool },
    /// A short note, e.g. how to bring a hidden pet back. Tap to dismiss.
    Toast { title: String, detail: String },
}

pub struct Env {
    pub t: f64,
    /// Real seconds (for drag speeds); the pet's own clock `t` skips long pauses.
    pub now: f64,
    pub screens: Vec<Screen>,
    /// Device pixels per point on the main screen.
    pub px_per_pt: f64,
    pub items: Vec<Item>,
    next_item_id: u64,
    sounds: Vec<&'static str>,
    pub poofs: Vec<Point>,
    /// The pet wants open menus and cards closed (picked up, or dragged along the top).
    pub close_menus: bool,

    // settings
    pub gravity: bool,
    pub size_setting: i32,
    pub sleep_after: f64,
    pub sound_on: bool,
    pub hidden: bool,
    pub water_every: f64,             // seconds at the computer between water reminders, 0 = off
    pub first_run: bool,
    pub away_seconds: f64,

    // senses
    pub mouse: Point,
    pub buttons_down: bool,
    pub idle_secs: f64,
    recent_keys: Vec<f64>,
    pub last_key_t: f64,
    pub tap_until: f64,
    pub fullscreen: bool,
    pub music_playing: bool,
    pub last_video_seen: f64,
    pub video_frame: Option<Rect>,
    pub is_night: bool,
    pub last_play: f64,

    // what's open
    pub popover_open: bool,
    pub menu_open: bool,
}

impl Env {
    pub fn scale(&self) -> f64 {
        // whole device pixels per cell, so the pixel art stays crisp
        (self.size_setting as f64 * self.px_per_pt).round().max(1.0) / self.px_per_pt
    }
    /// Device pixels per cell.
    pub fn cell_px(&self) -> i32 { (self.size_setting as f64 * self.px_per_pt).round().max(1.0) as i32 }

    pub fn play(&mut self, name: &'static str) { if self.sound_on { self.sounds.push(name); } }
    pub fn typing_now(&self) -> bool { self.recent_keys.len() >= 3 }
    pub fn typing_recently(&self) -> bool { self.t - self.last_key_t < 4.0 }
    pub fn video_playing(&self) -> bool { false }
    /// Fullscreen for anything but a video: pets head for the top edge.
    pub fn fullscreen_app(&self) -> bool { self.fullscreen && !(self.video_playing() || self.t - self.last_video_seen < 20.0) }

    pub fn main_screen(&self) -> Screen {
        self.screens.first().copied().unwrap_or(Screen { frame: Rect::new(0.0, 0.0, 1280.0, 800.0), visible: Rect::new(0.0, 40.0, 1280.0, 760.0) })
    }

    pub fn screen_at(&self, px: f64, py: f64) -> Screen {
        let col: Vec<&Screen> = self.screens.iter().filter(|s| px >= s.frame.min_x() && px < s.frame.max_x()).collect();
        if let Some(sc) = col.iter().find(|s| py >= s.frame.min_y() - 8.0 && py < s.frame.max_y()).or(col.first()) { return **sc; }
        self.screens.iter().min_by(|a, b| (a.frame.mid_x() - px).abs().total_cmp(&(b.frame.mid_x() - px).abs()))
            .copied().unwrap_or_else(|| self.main_screen())
    }

    pub fn area(&self, p: Point) -> Rect {
        let sc = self.screen_at(p.x, p.y);
        if self.fullscreen { sc.frame } else { sc.visible }
    }

    pub fn floor_y(&self, px: f64, py: f64) -> f64 { self.area(pt(px, py)).min_y() }

    pub fn x_range(&self, m: f64) -> (f64, f64) {
        let fs: Vec<Rect> = self.screens.iter().map(|s| if self.fullscreen { s.frame } else { s.visible }).collect();
        let lo = fs.iter().map(|r| r.min_x()).fold(f64::INFINITY, f64::min);
        let hi = fs.iter().map(|r| r.max_x()).fold(f64::NEG_INFINITY, f64::max);
        let lo = if lo.is_finite() { lo } else { 0.0 } + m;
        let hi = if hi.is_finite() { hi } else { 1000.0 } - m;
        (lo, lo.max(hi))
    }

    fn add_item(&mut self, kind: ItemKind, x: f64, y: f64) -> usize {
        self.next_item_id += 1;
        let s = self.scale();
        self.items.push(Item::new(self.next_item_id, kind, x, y, s, self.t));
        self.items.len() - 1
    }
}

/// Everything the platform needs to know about the water card's answer.
pub const WATER_GOAL: i32 = 8;

pub struct World {
    pub env: Env,
    pub pet: Pet,

    pub water_card: Option<(Card, f64)>,     // the card and when it closes by itself
    pub toast: Option<(Card, f64)>,
    pub glasses_today: i32,
    pub water_day: String,
    active_since_drink: f64,
    next_water_try: f64,
    water_snoozes: i32,
    later_celebrate: Option<(f64, &'static str)>,

    fps: f64,
    low_since: f64,
    next_save: f64,
    next_butterfly: f64,
    pub needs_save: bool,
    last_fullscreen_app: bool,
}

/// What the platform measured since the last tick.
pub struct Senses {
    pub now: f64,
    pub screens: Vec<Screen>,
    pub px_per_pt: f64,
    pub mouse: Point,
    pub buttons_down: bool,
    pub idle_secs: f64,
    /// Key presses since the last tick (only how many, never which).
    pub keys: u32,
    pub fullscreen: bool,
    pub local_hour: u32,
    pub day: String,
    /// Real seconds since the last tick (for water reminders, which count real time at the computer).
    pub wall_dt: f64,
}

impl World {
    pub fn new(st: &state::Saved, screens: Vec<Screen>, px_per_pt: f64, now: f64, wall_clock: f64) -> World {
        let away = if st.saved_at > 0.0 { wall_clock - st.saved_at } else { 0.0 };
        let mut rec = st.pet.clone().unwrap_or_else(|| PetRecord {
            id: format!("{:016x}", rng::next_u64()), species: Species::Goose, name: "Honk".into(), outfit: Outfit::default(),
            fullness: 80.0, happiness: 80.0, energy: 90.0, x: 0.0,
        });
        if away > 60.0 {
            rec.fullness = clamp(rec.fullness - away * 100.0 / (6.0 * 3600.0) * 0.5, 5.0, 100.0);
            rec.happiness = clamp(rec.happiness - away * 100.0 / (8.0 * 3600.0) * 0.5, 15.0, 100.0);
            if away > 3600.0 { rec.energy = 100.0; }
        }
        let env = Env {
            t: 0.0, now, screens, px_per_pt, items: Vec::new(), next_item_id: 0, sounds: Vec::new(), poofs: Vec::new(), close_menus: false,
            gravity: st.gravity, size_setting: st.size, sleep_after: st.sleep_after, sound_on: st.sound, hidden: false,
            water_every: st.water, first_run: st.pet.is_none(), away_seconds: away.max(0.0),
            mouse: Point::default(), buttons_down: false, idle_secs: 0.0, recent_keys: Vec::new(), last_key_t: -1000.0, tap_until: 0.0,
            fullscreen: false, music_playing: false, last_video_seen: -1000.0, video_frame: None, is_night: false, last_play: 0.0,
            popover_open: false, menu_open: false,
        };
        let pet = Pet::new(&rec);
        World {
            env, pet, water_card: None, toast: None,
            glasses_today: st.glasses, water_day: st.water_day.clone(), active_since_drink: 0.0, next_water_try: 0.0, water_snoozes: 0,
            later_celebrate: None, fps: 30.0, low_since: 0.0, next_save: 30.0, next_butterfly: 500.0, needs_save: false,
            last_fullscreen_app: false,
        }
    }

    pub fn start(&mut self) {
        let (pet, env) = (&mut self.pet, &mut self.env);
        pet.spawn_in(env);
    }

    pub fn saved(&self, wall_clock: f64) -> state::Saved {
        state::Saved {
            gravity: self.env.gravity, size: self.env.size_setting, sleep_after: self.env.sleep_after, sound: self.env.sound_on,
            water: self.env.water_every, saved_at: wall_clock, pet: Some(self.pet.record()),
            glasses: self.glasses_today, water_day: self.water_day.clone(),
        }
    }

    /// Sounds to play now.
    pub fn take_sounds(&mut self) -> Vec<&'static str> { std::mem::take(&mut self.env.sounds) }

    pub fn water_progress(&self) -> f64 { self.active_since_drink }

    pub fn menu_open(&self) -> bool { self.env.popover_open || self.water_card.is_some() }

    /// Takes in what the platform sensed. The system keystroke count says *that* you typed, never *what*.
    fn sense(&mut self, s: Senses) {
        let e = &mut self.env;
        e.now = s.now;
        if s.screens != e.screens || (s.px_per_pt - e.px_per_pt).abs() > 1e-9 {
            e.screens = s.screens;
            e.px_per_pt = s.px_per_pt;
            let sc = e.scale();
            for it in e.items.iter_mut() { it.resize(sc); }
            let (pet, env) = (&mut self.pet, &mut self.env);
            pet.environment_changed(env);
        }
        let e = &mut self.env;
        e.mouse = s.mouse;
        e.buttons_down = s.buttons_down;
        e.idle_secs = s.idle_secs;
        if s.keys > 0 && s.keys < 200 {
            e.last_key_t = e.t;
            for _ in 0..s.keys.min(6) { e.recent_keys.push(e.t); }
            e.tap_until = e.t + 0.1;
        }
        let t = e.t;
        e.recent_keys.retain(|k| t - k <= 3.0);
        e.fullscreen = s.fullscreen;
        e.is_night = s.local_hour >= 22 || s.local_hour < 7;
        if s.day != self.water_day && !self.water_day.is_empty() { self.glasses_today = 0; }
        self.water_day = s.day;
        // Water: counted in real minutes at the computer (the pet's own clock slows down while it naps).
        let real = s.wall_dt.clamp(0.0, 10.0);
        if self.env.water_every > 0.0 && self.env.idle_secs < 90.0 && !self.env.hidden { self.active_since_drink += real; }
    }

    pub fn tick(&mut self, dt: f64, s: Senses) {
        let dt = dt.min(0.2);
        self.env.t += dt;
        self.sense(s);
        self.update_stats(dt);
        self.env.menu_open = self.menu_open();
        if !self.env.hidden {
            let (pet, env) = (&mut self.pet, &mut self.env);
            pet.update(env, dt);
        }
        let mut items = std::mem::take(&mut self.env.items);
        for it in items.iter_mut().filter(|i| !i.gone) { it.update(dt, &mut self.env, &self.pet); }
        items.retain(|i| !i.gone);
        items.append(&mut self.env.items);
        self.env.items = items;
        for p in std::mem::take(&mut self.env.poofs) { self.poof(p); }
        let t = self.env.t;
        if t > self.next_butterfly {
            self.next_butterfly = t + rng::range(600.0, 1500.0);
            if rng::chance(0.6) && !self.env.hidden && matches!(self.pet.mode, Mode::Idle | Mode::Walk | Mode::Fly) { self.release_butterfly(); }
        }
        if let Some((at, text)) = self.later_celebrate {
            if t >= at { self.later_celebrate = None; let (pet, env) = (&mut self.pet, &mut self.env); pet.celebrate(env, text); }
        }
        // Water: never skipped: if now's a bad moment (a menu is open, the pet is held), it waits a minute and asks then.
        if self.env.water_every > 0.0 && self.active_since_drink >= self.env.water_every && t > self.next_water_try && self.water_card.is_none() {
            self.next_water_try = t + 60.0;
            if !self.env.popover_open && self.toast.is_none() && !self.env.hidden && self.pet.mode != Mode::Held && self.env.idle_secs < 90.0 {
                self.remind_water();
            }
        }
        if let Some((_, until)) = &self.water_card { if t > *until || self.env.hidden { self.snooze_water(true); } }
        if let Some((_, until)) = &self.toast { if t > *until { self.toast = None; } }
        let fa = self.env.fullscreen_app();
        if fa != self.last_fullscreen_app {
            self.last_fullscreen_app = fa;
            let (pet, env) = (&mut self.pet, &mut self.env);
            pet.environment_changed(env);
        }
        if t > self.next_save { self.next_save = t + 30.0; self.needs_save = true; }
    }

    /// How many frames a second to run at now: only as fast as the pet needs, slowing down only after a moment.
    pub fn wanted_fps(&mut self) -> f64 {
        let busy_items = self.env.items.iter().any(|i| !i.resting());
        let want = if self.env.hidden { 1.0 } else { self.pet.wants_fps().max(if busy_items { 20.0 } else { 0.0 }) };
        let t = self.env.t;
        if want > self.fps { self.fps = want; self.low_since = t; }
        else if want < self.fps { if t - self.low_since > 1.5 { self.fps = want; } }
        else { self.low_since = t; }
        self.fps
    }

    fn update_stats(&mut self, dt: f64) {
        let p = &mut self.pet;
        let asleep = matches!(p.mode, Mode::Sleeping | Mode::Catnap);
        p.fullness -= dt * if asleep { 0.5 } else { 1.0 } * 100.0 / (6.0 * 3600.0);
        p.energy += if asleep { dt * 100.0 / (15.0 * 60.0) } else { -dt * 100.0 / (10.0 * 3600.0) };
        let mut hap = -dt * 100.0 / (8.0 * 3600.0) * if p.fullness < 20.0 { 2.0 } else { 1.0 };
        if matches!(p.mode, Mode::Typing | Mode::Watching | Mode::Listening) { hap += dt * 100.0 / (3.0 * 3600.0); }
        p.happiness += hap;
        p.fullness = clamp(p.fullness, 0.0, 100.0);
        p.energy = clamp(p.energy, 0.0, 100.0);
        p.happiness = clamp(p.happiness, 0.0, 100.0);
    }

    fn poof(&mut self, at: Point) {
        self.env.play("poof");
        if self.pet.edge != 0 { return; }
        let o = self.pet.cell_to_screen(&self.env, 0.0, 0.0);
        let s = self.env.scale();
        let cx = (at.x - o.x) / s;
        let cy = (o.y - at.y) / s;
        if !(cx > 0.0 && cx < CANVAS_W as f64 && cy > 0.0 && cy < CANVAS_H as f64) { return; }
        for _ in 0..4 {
            self.pet.spawn(crate::pets::PKind::Puff, cx + rng::range(-3.0, 3.0), cy + rng::range(-3.0, 1.0), rng::range(-3.0, 3.0), rng::range(-4.0, -1.0), 0.6, 0.0, 0);
        }
    }

    // MARK: Water

    /// The pet sits up with a glass of water and a card asks whether you've had some.
    pub fn remind_water(&mut self) {
        let title = if self.water_snoozes > 0 { *rng::pick(&["Still thirsty?", "Water time, for real"]) }
                    else { *rng::pick(&["Water break?", "Time for a sip", "Stay hydrated!", "Thirsty?", "Glug glug?"]) };
        let (pet, env) = (&mut self.pet, &mut self.env);
        pet.offer_water(env, 60.0);
        env.play("pop");
        for i in 0..3 { pet.later_drops.push(env.t + i as f64 * 0.35); }
        self.water_card = Some((Card::Water { title: title.into(), glasses: self.glasses_today, goal: WATER_GOAL, done: false }, self.env.t + 60.0));
    }

    pub fn drank_water(&mut self) {
        let n = self.glasses_today + 1;
        self.glasses_today = n;
        self.active_since_drink = 0.0;
        self.water_snoozes = 0;
        self.needs_save = true;
        let (pet, env) = (&mut self.pet, &mut self.env);
        pet.drink(env);
        env.play("chomp");
        if self.env.popover_open { self.water_card = None; return; }          // counted from the menu: no card on top of it
        self.water_card = Some((Card::Water { title: String::new(), glasses: n, goal: WATER_GOAL, done: true }, self.env.t + 2.2));
        if n == WATER_GOAL { self.later_celebrate = Some((self.env.t + 1.6, "HYDRATED!")); }
    }

    /// "Later" (or the card left alone): asks again in 15 minutes.
    pub fn snooze_water(&mut self, quietly: bool) {
        let done = matches!(self.water_card, Some((Card::Water { done: true, .. }, _)));
        self.water_card = None;
        if done { return; }
        self.pet.put_away(&self.env);
        self.water_snoozes += 1;
        self.active_since_drink = (self.env.water_every - 15.0 * 60.0).max(0.0);
        if !quietly { self.pet.say(&["OKAY, IN A BIT!"], 1.6, &self.env); }
    }

    pub fn set_water(&mut self, every: f64) {
        self.env.water_every = every;
        self.active_since_drink = 0.0;
        self.needs_save = true;
    }

    // MARK: Actions

    pub fn feed(&mut self, kind: ItemKind) {
        self.env.last_play = self.env.t;
        self.show_if_hidden();
        let e = &mut self.env;
        let p = &mut self.pet;
        let s = e.scale();
        let a = e.area(pt(p.x, p.y));
        if e.gravity {
            let fx = clamp(p.x + p.facing as f64 * rng::range(110.0, 240.0) * s / 4.0, a.min_x() + 40.0, a.max_x() - 40.0);
            let y = e.area(pt(fx, p.y)).max_y() - 14.0 * s;
            e.add_item(kind, fx, y);
        } else {
            let i = e.add_item(kind, a.mid_x() + rng::range(-200.0, 200.0), a.mid_y() + rng::range(-100.0, 100.0));
            e.items[i].vx = rng::range(-80.0, 80.0);
            e.items[i].vy = rng::range(-80.0, 80.0);
            e.items[i].claimed = true;
            p.food = Some(e.items[i].id);
            p.begin(e, Mode::Eating);
        }
    }

    pub fn throw_ball(&mut self) {
        self.env.last_play = self.env.t;
        self.show_if_hidden();
        // already out: bring it back instead of ignoring the press
        self.env.items.retain(|i| !i.is_ball());
        let e = &mut self.env;
        let p = &self.pet;
        let s = e.scale();
        let kind = if p.family() == Family::Cat { ItemKind::Yarn } else { ItemKind::Ball };
        let a = e.area(pt(p.x, p.y));
        if e.gravity {
            e.add_item(kind, clamp(p.x + p.facing as f64 * 150.0 * s / 4.0, a.min_x() + 40.0, a.max_x() - 40.0), p.y + 300.0);
        } else {
            let i = e.add_item(kind, a.mid_x(), a.mid_y());
            e.items[i].vx = rng::range(-300.0, 300.0);
            e.items[i].vy = rng::range(-300.0, 300.0);
        }
    }

    pub fn release_butterfly(&mut self) {
        self.env.last_play = self.env.t;
        self.show_if_hidden();
        if self.env.items.iter().any(|i| i.kind == ItemKind::Butterfly) { return; }
        let e = &mut self.env;
        let p = &self.pet;
        let vf = e.area(pt(p.x, p.y));
        let left = p.x - vf.min_x() > vf.max_x() - p.x;
        let s = e.scale();
        e.add_item(ItemKind::Butterfly, if left { vf.min_x() + 10.0 } else { vf.max_x() - 10.0 }, vf.min_y() + 160.0 * s / 4.0);
    }

    pub fn toggle_nap(&mut self) { let (pet, env) = (&mut self.pet, &mut self.env); pet.toggle_nap(env); }
    pub fn come_here(&mut self) { self.show_if_hidden(); let (pet, env) = (&mut self.pet, &mut self.env); pet.come_here(env); }

    pub fn set_gravity(&mut self, on: bool) {
        if on == self.env.gravity { return; }
        self.env.gravity = on;
        let (pet, env) = (&mut self.pet, &mut self.env);
        pet.environment_changed(env);
        self.needs_save = true;
    }

    pub fn set_size(&mut self, n: i32) {
        self.env.size_setting = n;
        let s = self.env.scale();
        for it in self.env.items.iter_mut() { it.resize(s); }
        self.pet.dirty = true;
        self.needs_save = true;
    }

    pub fn set_sound(&mut self, on: bool) { self.env.sound_on = on; self.needs_save = true; }

    pub fn change_species(&mut self, sp: Species) {
        if self.pet.species == sp { return; }
        if self.pet.name == self.pet.species.default_name() { self.pet.name = sp.default_name().into(); }
        self.pet.set_species(sp);
        let (pet, env) = (&mut self.pet, &mut self.env);
        pet.transformed(env);
        self.needs_save = true;
    }

    pub fn set_outfit(&mut self, o: Outfit) {
        if self.pet.outfit == o { return; }
        self.pet.outfit = o;
        let (pet, env) = (&mut self.pet, &mut self.env);
        pet.admire(env);
        self.needs_save = true;
    }

    pub fn surprise_outfit(&mut self) {
        self.set_outfit(Outfit { hat: *rng::pick(&Hat::ALL), glasses: *rng::pick(&Glasses::ALL), neck: *rng::pick(&Neckwear::ALL) });
    }

    pub fn rename(&mut self, name: &str) {
        let n = name.trim();
        if n.is_empty() { return; }
        self.pet.name = n.chars().take(20).collect();
        let line = format!("I'M {}!", crate::art::sanitize(&self.pet.name));
        self.pet.say(&[&line], 2.0, &self.env);
        self.pet.hearts(2);
        self.needs_save = true;
    }

    pub fn set_hidden(&mut self, hidden: bool, quietly: bool) {
        if hidden == self.env.hidden { return; }
        self.env.hidden = hidden;
        if hidden {
            self.water_card = None;
            if !quietly {
                self.toast = Some((Card::Toast { title: format!("{} is hidden", self.pet.name),
                    detail: "Press Ctrl+Alt+P, or click Pocket Pet's tray icon, to bring them back.".into() }, self.env.t + 6.0));
            }
        } else {
            self.toast = None;
            self.pet.dirty = true;
        }
    }

    pub fn show_if_hidden(&mut self) { if self.env.hidden { self.set_hidden(false, false); } }

    /// Ctrl+Alt+P, or opening the app again, when it's hidden.
    pub fn bring_back(&mut self) {
        self.set_hidden(false, false);
        self.pet.say(&["I'M BACK!"], 1.6, &self.env);
    }

    /// What the pet is up to, for the top of the panel.
    pub fn mood(&self) -> String {
        if self.env.hidden { return "Hidden".into(); }
        let p = &self.pet;
        let m = match p.mode {
            Mode::Sleeping | Mode::Yawning | Mode::Catnap => "sleeping",
            Mode::Typing => "typing with you",
            Mode::Watching => "watching with you",
            Mode::Listening => "listening to music",
            Mode::Eating => "munching",
            Mode::Ball | Mode::Butterfly | Mode::Zoomies | Mode::Hunt => "playing",
            Mode::Held => "being held",
            Mode::Glide => "floating down",
            Mode::Fly => "flying",
            _ => {
                if p.fullness < 25.0 { "hungry" } else if p.energy < 25.0 { "sleepy" } else if p.happiness > 70.0 { "happy" } else { "chilling" }
            }
        };
        let mut c = m.chars();
        c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
    }

    // MARK: Pictures for the panel

    /// The pet's window picture: the canvas turned onto its edge, `cell_px` device pixels per cell.
    pub fn pet_image(&self) -> Image {
        let w = &self.env;
        let p = &self.pet;
        let cell = w.cell_px();
        let side_px = (p.cw.max(p.chh) + 4) * cell;
        let mut img = Image::new(side_px, side_px);
        let k = cell as f64 / w.scale();          // device pixels per point
        let pal = &p.palette;
        for y in 0..p.canvas.h {
            for x in 0..p.canvas.w {
                let v = p.canvas.px[(y * p.canvas.w + x) as usize];
                if v == 0 { continue; }
                let a = p.to_view(w, x as f64, y as f64);
                let b = p.to_view(w, x as f64 + 1.0, y as f64 + 1.0);
                let x0 = (a.x.min(b.x) * k).round() as i32;
                let y0 = (a.y.min(b.y) * k).round() as i32;
                img.fill_rect(x0, y0, cell, cell, 0xff00_0000 | pal[v as usize]);
            }
        }
        img
    }
}
