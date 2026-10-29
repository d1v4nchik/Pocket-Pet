// Snacks, toys and butterflies out in the world: how they fall, bounce, get carried and fly.
// A port of the Item class in the Mac app's World.swift; each one lives in its own little window.

use crate::art::{base_palette, Canvas, Palette};
use crate::geom::{clamp, pt, Point, Rect};
use crate::items::{item_canvas, random_butterfly_palette, ItemKind};
use crate::pet::Pet;
use crate::rng;
use crate::world::Env;

pub struct Item {
    pub id: u64,
    pub kind: ItemKind,
    pub x: f64,
    pub y: f64,
    pub vx: f64,
    pub vy: f64,
    pub scale: f64,
    pub bites: i32,
    pub claimed: bool,
    pub refused_by: bool,
    pub held: bool,
    pub on_ground: bool,
    pub gone: bool,
    pub leaving: bool,
    pub landed: bool,
    pub born: f64,
    pub life: f64,                   // snacks disappear when nobody eats them
    pub spin: f64,
    pub flap: f64,
    pub variant: i32,                // a butterfly's wing pattern
    pub target: Option<Point>,
    pub retarget: f64,
    pub grab: Point,
    pub down_at: Option<Point>,
    pub samples: Vec<(f64, Point)>,
    pub blink_hidden: bool,
    pub palette: Palette,
    /// The window's bottom-left corner, snapped to whole device pixels.
    pub origin: Point,
    /// Takes clicks right now (the window lets them through otherwise).
    pub catches_mouse: bool,
}

impl Item {
    pub fn new(id: u64, kind: ItemKind, x: f64, y: f64, scale: f64, t: f64) -> Item {
        let mut it = Item {
            id, kind, x, y, vx: 0.0, vy: 0.0, scale, bites: 0, claimed: false, refused_by: false, held: false, on_ground: false,
            gone: false, leaving: false, landed: false, born: t,
            life: if kind == ItemKind::Butterfly { 40.0 } else if matches!(kind, ItemKind::Ball | ItemKind::Yarn) { 60.0 } else { 45.0 },
            spin: 0.0, flap: 0.0, variant: rng::int(0, 3), target: None, retarget: 0.0, grab: Point::default(), down_at: None,
            samples: Vec::new(), blink_hidden: false,
            palette: if kind == ItemKind::Butterfly { random_butterfly_palette() } else { *base_palette() },
            origin: Point::default(), catches_mouse: false,
        };
        it.place(1.0);
        it
    }

    pub fn is_food(&self) -> bool { !matches!(self.kind, ItemKind::Ball | ItemKind::Yarn | ItemKind::Butterfly) }
    pub fn is_ball(&self) -> bool { matches!(self.kind, ItemKind::Ball | ItemKind::Yarn) }
    pub fn value(&self) -> f64 {
        match self.kind { ItemKind::Bread | ItemKind::Sausage => 30.0, ItemKind::Cookie => 18.0, _ => 24.0 }
    }
    pub fn frame(&self) -> i32 { if self.is_ball() { self.spin.floor() as i32 } else { (self.flap * 10.0) as i32 % 4 } }
    pub fn resting(&self) -> bool {
        self.kind != ItemKind::Butterfly && !self.held && self.down_at.is_none() && self.vx.abs() < 1.0 && self.vy.abs() < 1.0
            && (self.on_ground || self.vx == 0.0)
    }

    /// The window: 14x14 cells, the item standing on its bottom row.
    pub fn frame_rect(&self) -> Rect { Rect::new(self.origin.x, self.origin.y, 14.0 * self.scale, 14.0 * self.scale) }

    /// What to draw right now (nothing while it blinks out).
    pub fn canvas(&self) -> Option<Canvas> {
        if self.blink_hidden { return None; }
        Some(item_canvas(self.kind, self.bites, self.frame(), self.variant))
    }

    /// Changes whenever the picture does, so the window only repaints then.
    pub fn draw_key(&self) -> (i32, i32, bool) { (self.frame(), self.bites, self.blink_hidden) }

    pub fn resize(&mut self, s: f64) { self.scale = s; }

    fn place(&mut self, k: f64) {
        let snap = |v: f64| (v * k).round() / k;
        self.origin = pt(snap(self.x - 7.0 * self.scale), snap(self.y - self.scale));
    }

    pub fn close(&mut self) { self.gone = true; }

    pub fn update(&mut self, dt: f64, w: &mut Env, pet: &Pet) {
        let s = self.scale;
        let age = w.t - self.born;
        if self.kind != ItemKind::Butterfly && !self.claimed && !self.held && age > self.life {
            w.poofs.push(pt(self.x, self.y + 5.0 * s));
            self.close();
            return;
        }
        self.blink_hidden = self.kind != ItemKind::Butterfly && !self.claimed && age > self.life - 4.0 && (age * 6.0) as i64 % 2 == 0;
        if self.kind == ItemKind::Butterfly {
            self.fly(dt, w, pet);
        } else if !self.held {
            let a = w.area(pt(self.x, self.y + 4.0));
            if w.gravity && !pet.wall_mode(w) {   // a pet up on the edges gets its food floated over
                if !(self.on_ground && self.vx.abs() < 1.0) {
                    self.vy -= 2100.0 * dt * s / 4.0;
                    self.x += self.vx * dt;
                    self.y += self.vy * dt;
                }
                let (lo, hi) = w.x_range(7.0 * s);
                if self.x < lo { self.x = lo; self.vx = self.vx.abs() * 0.6; }
                if self.x > hi { self.x = hi; self.vx = -self.vx.abs() * 0.6; }
                let fl = w.floor_y(self.x, self.y);
                if self.y <= fl {
                    self.y = fl;
                    if self.vy < -260.0 {
                        if !self.landed || self.is_ball() && self.vy < -500.0 { w.play(if self.is_ball() { "kick" } else { "pop" }); }
                        self.landed = true;
                        self.vy = -self.vy * if self.is_ball() { 0.6 } else { 0.22 };
                    } else {
                        self.vy = 0.0;
                    }
                    self.vx *= (if self.is_ball() { 0.45f64 } else { 0.002 }).powf(dt);
                    if self.vx.abs() < 2.0 { self.vx = 0.0; }
                }
                self.on_ground = self.y <= fl + 0.5 && self.vy.abs() < 1.0;
            } else {
                if self.is_food() && pet.food == Some(self.id) && age > 0.6 {
                    let m = pet.mouth_point(w);
                    let dx = m.x - self.x;
                    let dy = m.y - self.y;
                    let d = dx.hypot(dy).max(1.0);
                    let sp = (170.0 * s / 4.0).min(d * 3.0);
                    self.vx += (dx / d * sp - self.vx) * (dt * 4.0).min(1.0);
                    self.vy += (dy / d * sp - self.vy) * (dt * 4.0).min(1.0);
                } else {
                    let damp = (if self.is_ball() { 0.85f64 } else { 0.5 }).powf(dt);
                    self.vx *= damp;
                    self.vy *= damp;
                    if self.vx.hypot(self.vy) < 2.0 { self.vx = 0.0; self.vy = 0.0; }
                }
                self.x += self.vx * dt;
                self.y += self.vy * dt;
                if self.x < a.min_x() + 7.0 * s { self.x = a.min_x() + 7.0 * s; self.vx = self.vx.abs() * 0.8; }
                if self.x > a.max_x() - 7.0 * s { self.x = a.max_x() - 7.0 * s; self.vx = -self.vx.abs() * 0.8; }
                if self.y < a.min_y() { self.y = a.min_y(); self.vy = self.vy.abs() * 0.8; }
                if self.y > a.max_y() - 14.0 * s { self.y = a.max_y() - 14.0 * s; self.vy = -self.vy.abs() * 0.8; }
                self.on_ground = false;
            }
            if self.is_ball() {
                let v = if w.gravity { self.vx } else { self.vx.hypot(self.vy) * if self.vx < 0.0 { -1.0 } else { 1.0 } };
                self.spin += v * dt / (4.0 * s);
            }
        }
        self.place(w.px_per_pt);
        let m = w.mouse;
        self.catches_mouse = self.kind != ItemKind::Butterfly && (self.held || self.down_at.is_some() || self.frame_rect().inset(s, s).contains(m));
    }

    fn fly(&mut self, dt: f64, w: &mut Env, pet: &Pet) {
        let s = self.scale;
        self.flap += dt;
        let a = w.area(pt(self.x, self.y));
        let age = w.t - self.born;
        if age > 22.0 && !self.leaving {
            self.leaving = true;
            self.target = Some(pt(self.x + if rng::coin() { 1400.0 } else { -1400.0 }, a.min_y() + 700.0));
        }
        let near = (pet.x - self.x).hypot(pet.y - self.y) < 90.0 * s / 4.0;
        if !self.leaving && (self.target.is_none() || w.t > self.retarget || near) {
            if near {
                let tx = self.x + if self.x > pet.x { 1.0 } else { -1.0 } * rng::range(140.0, 240.0);
                self.target = Some(pt(clamp(tx, a.min_x() + 30.0, a.max_x() - 30.0),
                                      clamp(self.y + rng::range(60.0, 160.0) * s / 4.0, a.min_y() + 40.0, a.max_y() - 40.0)));
            } else {
                let base = if w.gravity && !pet.wall_mode(w) { a.min_y() } else { pet.y };
                self.target = Some(pt(clamp(pet.x + rng::range(-320.0, 320.0), a.min_x() + 30.0, a.max_x() - 30.0),
                                      clamp(base + rng::range(45.0, 210.0) * s / 4.0, a.min_y() + 30.0, a.max_y() - 40.0)));
            }
            self.retarget = w.t + rng::range(1.5, 3.5);
        }
        if let Some(tg) = self.target {
            let dx = tg.x - self.x;
            let dy = tg.y - self.y;
            let d = dx.hypot(dy).max(1.0);
            let sp = (if self.leaving { 170.0 } else if near { 150.0 } else { 70.0 }) * s / 4.0;
            let step = d.min(sp * dt);
            self.x += dx / d * step;
            self.y += dy / d * step + (self.flap * 9.0).sin() * 0.9;
        }
        if self.leaving {
            let all = w.screens.iter().fold(None::<Rect>, |acc, sc| Some(acc.map_or(sc.frame, |r| r.union(&sc.frame))));
            let inside = all.map(|r| r.inset(-60.0, -60.0).contains(pt(self.x, self.y))).unwrap_or(false);
            if !inside || age > 34.0 { self.close(); }
        }
    }

    pub fn mouse_down(&mut self, m: Point, now: f64) {
        self.down_at = Some(m);
        self.grab = pt(m.x - self.x, m.y - self.y);
        self.samples = vec![(now, m)];
    }

    pub fn mouse_dragged(&mut self, m: Point, now: f64) {
        let Some(d) = self.down_at else { return };
        if !self.held && (m.x - d.x).hypot(m.y - d.y) > 3.0 { self.held = true; self.vx = 0.0; self.vy = 0.0; self.on_ground = false; }
        if !self.held { return; }
        self.x = m.x - self.grab.x;
        self.y = m.y - self.grab.y;
        self.samples.push((now, m));
        self.samples.retain(|smp| now - smp.0 <= 0.1);
    }

    pub fn mouse_up(&mut self) {
        if self.held {
            self.held = false;
            if let (Some(f), Some(l)) = (self.samples.first(), self.samples.last()) {
                if l.0 - f.0 > 0.01 {
                    self.vx = clamp((l.1.x - f.1.x) / (l.0 - f.0), -2400.0, 2400.0);
                    self.vy = clamp((l.1.y - f.1.y) / (l.0 - f.0), -2400.0, 2400.0);
                }
            }
        } else if self.is_ball() {
            self.vy = 480.0 * self.scale / 4.0;
            self.vx = rng::range(-220.0, 220.0);
            self.on_ground = false;
        }
        self.down_at = None;
    }
}
