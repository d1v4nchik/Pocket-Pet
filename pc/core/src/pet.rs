// The pet: its body, brain, drawing and how it reacts to the mouse.
// A port of the Mac app's Pet.swift. Positions are screen points, y up; `x, y` is where it touches the floor.

use crate::art::{iround, make_palette, sanitize, Canvas, Palette};
use crate::geom::{clamp, pt, Point, Rect};
use crate::items::ItemKind;
use crate::pets::*;
use crate::rng::{self, chance};
use crate::world::Env;
use std::f64::consts::PI;

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Mode {
    Fly, Glide, Drift, Landing, Dizzy, Held,
    Idle, Walk, Typing, Watching, Listening, Yawning, Sleeping, Waking, Catnap,
    Eating, Refusing, Ball, Tired, Butterfly, Vocal, Angry, Petted, Beg, Zoomies, Hunt, Agenda,
}
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum IdleAct { Stand, Look, Preen, Peck, Sit, Vocal, Yawn, Flap, Hop, Gaze, Lie, Groom, Stretch, Beg }
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FlyGoal { Wander, Land }

const EDGE_ANGLE: [f64; 4] = [0.0, -PI / 2.0, PI, PI / 2.0];

/// Things a pet has to be on the floor for.
fn ground_mode(m: Mode) -> bool {
    use Mode::*;
    matches!(m, Typing | Watching | Listening | Yawning | Sleeping | Waking | Catnap | Tired | Beg | Zoomies | Hunt | Walk | Refusing | Agenda)
}

fn rnd(a: f64, b: f64) -> f64 { rng::range(a, b) }

#[derive(Clone, Debug)]
pub struct PetRecord {
    pub id: String,
    pub species: Species,
    pub name: String,
    pub outfit: Outfit,
    pub fullness: f64,
    pub happiness: f64,
    pub energy: f64,
    pub x: f64,
}

pub struct Pet {
    pub id: String,
    pub species: Species,
    pub name: String,
    pub outfit: Outfit,
    pub palette: Palette,
    pub fullness: f64,
    pub happiness: f64,
    pub energy: f64,

    pub cw: i32,
    pub chh: i32,
    pub cx: i32,

    // body: (x, y) is where the pet touches the floor/wall/ceiling, in screen points
    pub x: f64,
    pub y: f64,
    pub p: f64,                 // position around the screen edge (zero gravity)
    pub edge: usize,            // 0 floor, 1 right wall, 2 ceiling, 3 left wall
    pub vx: f64,
    pub vy: f64,
    pub hop_y: f64,
    pub hop_v: f64,
    pub leap_v: f64,
    pub facing: i32,
    pub turn_at: f64,
    pub apex_y: f64,
    pub in_air: bool,           // birds flying
    pub umbrella: bool,
    pub moving: bool,
    pub running: bool,
    pub walk_t: f64,
    pub flap_t: f64,

    // brain
    pub mode: Mode,
    pub mode_t: f64,
    pub act: IdleAct,
    pub act_t: f64,
    pub act_dur: f64,
    pub walk_target: f64,
    pub fly_goal: FlyGoal,
    pub after_land: Option<Mode>,
    pub fly_target: Option<Point>,
    pub next_fly_pick: f64,
    pub next_blink: f64,
    pub blink_until: f64,
    pub blush_until: f64,
    pub greeted: bool,
    pub forced_nap: bool,
    pub slept_at: f64,
    pub nap_end: f64,
    pub seated: bool,
    pub pop_t: f64,
    pub next_react: f64,
    pub next_beg: f64,
    pub next_peck: f64,
    pub peck_start: f64,
    pub next_kick: f64,
    pub kick_until: f64,
    pub kicks: i32,
    pub refuse_facing: i32,
    pub food: Option<u64>,
    pub celebrate_text: String,
    pub celebrate_until: f64,
    pub bubble_lines: Vec<String>,
    pub bubble_until: f64,
    pub particles: Vec<Particle>,
    pub canvas: Canvas,
    pub hit_cells: Option<(i32, i32, i32, i32)>,
    pub head: (i32, i32),
    pub next_z: f64,
    pub next_sweat: f64,
    pub next_note: f64,
    pub zoom_left: i32,
    pub hunt_phase: i32,
    pub hunt_t: f64,
    pub agenda_until: f64,
    pub agenda_prop: Prop,          // what it holds up: the calendar, or a glass of water
    pub drink_until: f64,
    pub quick_drop: bool,
    pub noticed_until: f64,
    pub play_until: f64,            // playing with a toy you just gave it: typing waits a moment
    pub sliding: bool,              // dragged along the top edge in fullscreen
    pub follow_until: f64,          // "come here": tags along after the cursor until then
    pub last_stance: Stance,
    pub transition_until: f64,
    pub drawn_edge: i32,
    /// Little things that happen a moment later (water drops after a sip).
    pub later_drops: Vec<f64>,

    // mouse
    pub down_at: Option<Point>,
    pub grab: Point,
    pub dragging: bool,
    pub samples: Vec<(f64, Point)>,
    pub shake: i32,
    pub last_dir: i32,
    pub clicks: Vec<f64>,
    pub stroke_dist: f64,
    pub stroke_idle: f64,
    pub last_mouse: Point,
    pub pet_cooldown: f64,
    pub cursor_moved_at: f64,
    pub mouse_inside: bool,

    /// The window's bottom-left corner in screen points (its side is `side()`).
    pub origin: Point,
    /// Set whenever the picture changed and the window needs repainting.
    pub dirty: bool,
}

impl Pet {
    pub fn new(r: &PetRecord) -> Pet {
        Pet {
            id: r.id.clone(), species: r.species, name: r.name.clone(), outfit: r.outfit, palette: make_palette(r.species.colors()),
            fullness: r.fullness, happiness: r.happiness, energy: r.energy,
            cw: CANVAS_W, chh: CANVAS_H, cx: CANVAS_W / 2,
            x: r.x, y: 0.0, p: 0.0, edge: 0, vx: 0.0, vy: 0.0, hop_y: 0.0, hop_v: 0.0, leap_v: 0.0, facing: 1, turn_at: -10.0,
            apex_y: 0.0, in_air: false, umbrella: false, moving: false, running: false, walk_t: 0.0, flap_t: 0.0,
            mode: Mode::Glide, mode_t: 0.0, act: IdleAct::Stand, act_t: 0.0, act_dur: 2.0, walk_target: 0.0,
            fly_goal: FlyGoal::Land, after_land: None, fly_target: None, next_fly_pick: 0.0,
            next_blink: 2.0, blink_until: 0.0, blush_until: 0.0, greeted: false, forced_nap: false, slept_at: 0.0, nap_end: 0.0,
            seated: false, pop_t: 0.0, next_react: 0.0, next_beg: 90.0, next_peck: 0.0, peck_start: -10.0,
            next_kick: 0.0, kick_until: 0.0, kicks: 0, refuse_facing: 1, food: None,
            celebrate_text: String::new(), celebrate_until: 0.0, bubble_lines: Vec::new(), bubble_until: 0.0,
            particles: Vec::new(), canvas: Canvas::new(CANVAS_W, CANVAS_H), hit_cells: None, head: (32, 10),
            next_z: 0.0, next_sweat: 0.0, next_note: 0.0, zoom_left: 0, hunt_phase: 0, hunt_t: 0.0, agenda_until: 0.0,
            agenda_prop: Prop::Calendar, drink_until: 0.0, quick_drop: false, noticed_until: -10.0, play_until: -10.0,
            sliding: false, follow_until: 0.0, last_stance: Stance::Stand, transition_until: 0.0, drawn_edge: -1,
            later_drops: Vec::new(),
            down_at: None, grab: Point::default(), dragging: false, samples: Vec::new(), shake: 0, last_dir: 0, clicks: Vec::new(),
            stroke_dist: 0.0, stroke_idle: 0.0, last_mouse: Point::default(), pet_cooldown: 0.0, cursor_moved_at: -10.0,
            mouse_inside: false, origin: Point::default(), dirty: true,
        }
    }

    pub fn record(&self) -> PetRecord {
        PetRecord { id: self.id.clone(), species: self.species, name: self.name.clone(), outfit: self.outfit,
                    fullness: self.fullness, happiness: self.happiness, energy: self.energy, x: self.x }
    }

    pub fn set_species(&mut self, sp: Species) {
        self.species = sp;
        self.palette = make_palette(sp.colors());
        self.dirty = true;
    }

    pub fn family(&self) -> Family { self.species.family() }
    pub fn is_bird(&self) -> bool { self.species.is_bird() }
    /// Walking the screen edges instead of the floor: zero gravity, or a fullscreen app (then only the top edge).
    pub fn wall_mode(&self, w: &Env) -> bool { !self.is_bird() && (!w.gravity || w.fullscreen_app() || self.family() == Family::Bat) }
    pub fn fly_mode(&self, w: &Env) -> bool { self.is_bird() && (!w.gravity || w.fullscreen_app()) }
    /// A fullscreen app: four-legged pets get spooked, leap to the top edge and hang out there upside down.
    /// Bats always live up there, hanging.
    pub fn ceiling_mode(&self, w: &Env) -> bool { !self.is_bird() && (w.fullscreen_app() || self.family() == Family::Bat) }
    pub fn is_asleep(&self) -> bool { matches!(self.mode, Mode::Sleeping | Mode::Yawning | Mode::Catnap) }
    pub fn sleep_threshold(&self, w: &Env) -> f64 { w.sleep_after * if self.energy < 25.0 { 0.5 } else { 1.0 } }
    pub fn following(&self, w: &Env) -> bool { w.t < self.follow_until }
    /// Holds still while any of its menus or cards is open, so they stay with it.
    pub fn frozen(&self, w: &Env) -> bool { w.popover_open || w.menu_open }

    /// How often this pet needs to be redrawn right now (lower = less CPU).
    pub fn wants_fps(&self) -> f64 {
        // As few frames as each moment needs: being dragged or thrown is the only thing that gets 30.
        if matches!(self.mode, Mode::Held | Mode::Glide | Mode::Drift) || self.hop_y > 0.0 { return 30.0; }
        if self.in_air || self.running { return 20.0; }
        if self.moving { return 15.0; }                  // its pixels are 4 pt wide, so walking looks the same at 15
        if matches!(self.mode, Mode::Sleeping | Mode::Catnap) { return 4.0; }   // drifting Zzz read fine at 4
        if !self.particles.is_empty() { return 12.0; }   // hearts and notes float slowly
        match self.mode {
            Mode::Idle | Mode::Listening | Mode::Watching | Mode::Agenda | Mode::Beg => 8.0,
            Mode::Typing => 12.0,
            _ => 16.0,
        }
    }

    // MARK: Window & geometry

    /// Points per cell.
    pub fn s(&self, w: &Env) -> f64 { w.scale() }
    /// The window is a square this many points wide.
    pub fn side(&self, w: &Env) -> f64 { (self.cw.max(self.chh) + 4) as f64 * w.scale() }

    /// Where the feet sit inside the (square) window for the current edge, y down from its top.
    pub fn anchor_view(&self, w: &Env) -> Point {
        let s = w.scale();
        let side = self.side(w);
        match self.edge {
            1 => pt(side - s, side / 2.0),
            2 => pt(side / 2.0, s),
            3 => pt(s, side / 2.0),
            _ => pt(side / 2.0, side - s),
        }
    }

    /// Canvas cell -> point inside the window (y down). The canvas is turned onto walls and the ceiling.
    pub fn to_view(&self, w: &Env, cxp: f64, cyp: f64) -> Point {
        let s = w.scale();
        let dx = (cxp - (self.cx as f64 + 0.5)) * s;
        let dy = (cyp - (self.chh - 1) as f64) * s;
        let a = EDGE_ANGLE[self.edge];
        let c = a.cos().round();
        let sn = a.sin().round();
        let av = self.anchor_view(w);
        pt(av.x + dx * c - dy * sn, av.y + dx * sn + dy * c)
    }

    pub fn cell_to_screen(&self, w: &Env, cxp: f64, cyp: f64) -> Point {
        let v = self.to_view(w, cxp, cyp);
        pt(self.origin.x + v.x, self.origin.y + self.side(w) - v.y)
    }

    pub fn local_x(&self, lx: i32) -> f64 { (if self.facing > 0 { lx } else { 2 * self.cx - lx }) as f64 }
    pub fn mouth_point(&self, w: &Env) -> Point {
        if self.family() == Family::Bat { self.cell_to_screen(w, self.cx as f64, (self.head.1 + 6) as f64) }
        else { self.cell_to_screen(w, self.local_x(self.cx + 12), (self.chh - 6) as f64) }
    }
    pub fn center_point(&self, w: &Env) -> Point { self.cell_to_screen(w, self.cx as f64, (self.chh - 12) as f64) }

    pub fn hit_rect_screen(&self, w: &Env) -> Option<Rect> {
        let hc = self.hit_cells?;
        // Symmetric around the body so turning around never changes the clickable area.
        let reach = (self.cx - hc.0).max(hc.2 - self.cx);
        let cx = self.cx;
        let pts = [self.cell_to_screen(w, (cx - reach) as f64, hc.1 as f64), self.cell_to_screen(w, (cx + reach + 1) as f64, hc.1 as f64),
                   self.cell_to_screen(w, (cx - reach) as f64, (hc.3 + 1) as f64), self.cell_to_screen(w, (cx + reach + 1) as f64, (hc.3 + 1) as f64)];
        let x0 = pts.iter().map(|p| p.x).fold(f64::INFINITY, f64::min);
        let x1 = pts.iter().map(|p| p.x).fold(f64::NEG_INFINITY, f64::max);
        let y0 = pts.iter().map(|p| p.y).fold(f64::INFINITY, f64::min);
        let y1 = pts.iter().map(|p| p.y).fold(f64::NEG_INFINITY, f64::max);
        Some(Rect::new(x0, y0, x1 - x0, y1 - y0))
    }

    pub fn place(&mut self, w: &Env) {
        let av = self.anchor_view(w);
        let up = self.up_vec();
        let side = self.side(w);
        let k = w.px_per_pt;
        let snap = |v: f64| (v * k).round() / k;
        self.origin = pt(snap(self.x + up.0 * self.hop_y - av.x), snap(self.y + up.1 * self.hop_y - (side - av.y)));
    }

    pub fn up_vec(&self) -> (f64, f64) { [(0.0, 1.0), (-1.0, 0.0), (0.0, -1.0), (1.0, 0.0)][self.edge] }
    pub fn fwd_vec(&self) -> (f64, f64) { [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)][self.edge] }

    pub fn area(&self, w: &Env) -> Rect {
        let up = self.up_vec();
        w.area(pt(self.x + up.0 * 10.0, self.y + up.1 * 10.0))
    }

    pub fn margin(&self, w: &Env) -> f64 { 17.0 * w.scale() }

    fn perimeter(&self, w: &Env, a: Rect) -> (Rect, f64) {
        let m = self.margin(w);
        let r = a.inset(m, m);
        (r, 2.0 * (r.width() + r.height()))
    }

    pub fn place_on_perimeter(&mut self, w: &Env) {
        let a = self.area(w);
        let (r, l) = self.perimeter(w, a);
        if l <= 0.0 { return; }
        let mut q = self.p % l;
        if q < 0.0 { q += l; }
        self.p = q;
        if q < r.width() { self.edge = 0; self.x = r.min_x() + q; self.y = a.min_y(); }
        else if q < r.width() + r.height() { self.edge = 1; self.x = a.max_x(); self.y = r.min_y() + (q - r.width()); }
        else if q < 2.0 * r.width() + r.height() { self.edge = 2; self.x = r.max_x() - (q - r.width() - r.height()); self.y = a.max_y(); }
        else { self.edge = 3; self.x = a.min_x(); self.y = r.max_y() - (q - 2.0 * r.width() - r.height()); }
    }

    pub fn perimeter_p(&self, w: &Env, px: f64, py: f64) -> f64 {
        let a = self.area(w);
        let (r, _) = self.perimeter(w, a);
        let d_b = (py - a.min_y()).abs();
        let d_t = (a.max_y() - py).abs();
        let d_l = (px - a.min_x()).abs();
        let d_r = (a.max_x() - px).abs();
        let m = d_b.min(d_t).min(d_l).min(d_r);
        if m == d_b { return clamp(px, r.min_x(), r.max_x()) - r.min_x(); }
        if m == d_r { return r.width() + clamp(py, r.min_y(), r.max_y()) - r.min_y(); }
        if m == d_t { return r.width() + r.height() + (r.max_x() - clamp(px, r.min_x(), r.max_x())); }
        2.0 * r.width() + r.height() + (r.max_y() - clamp(py, r.min_y(), r.max_y()))
    }

    pub fn track_delta(&self, w: &Env, target: f64) -> f64 {
        if !self.wall_mode(w) { return target - self.x; }
        let l = self.perimeter(w, self.area(w)).1;
        if l <= 0.0 { return 0.0; }
        let mut d = (target - self.p) % l;
        if d > l / 2.0 { d -= l; }
        if d < -l / 2.0 { d += l; }
        d
    }

    /// Walk along the floor (or climb around the walls) toward a track position.
    pub fn go(&mut self, w: &Env, target: f64, speed: f64, dt: f64, run: bool) -> bool {
        let d = self.track_delta(w, target);
        if d.abs() < 3.0 { return true; }
        self.facing = if d > 0.0 { 1 } else { -1 };
        let v = speed * w.scale() / 4.0 * if self.fullness < 15.0 { 0.7 } else { 1.0 } * dt;
        if self.wall_mode(w) { self.p += self.facing as f64 * d.abs().min(v); } else { self.x += self.facing as f64 * d.abs().min(v); }
        self.moving = true;
        self.running = run;
        self.walk_t += dt;
        false
    }

    pub fn floor_target(&self, w: &Env, px: f64, _py: f64) -> f64 {
        if self.ceiling_mode(w) {
            let (lo, hi) = self.top_span(w);
            return clamp(self.perimeter_p(w, px, self.area(w).max_y()), lo, hi);
        }
        if self.wall_mode(w) { self.perimeter_p(w, px, self.area(w).min_y()) } else { px }
    }

    pub fn fly_to(&mut self, w: &Env, tp: Point, speed: f64, dt: f64) -> bool {
        let dx = tp.x - self.x;
        let dy = tp.y - self.y;
        let d = dx.hypot(dy);
        let sp = (speed * w.scale() / 4.0).min(d * 3.0);
        let tvx = if d > 0.1 { dx / d * sp } else { 0.0 };
        let tvy = if d > 0.1 { dy / d * sp } else { 0.0 };
        let k = (dt * 3.0).min(1.0);
        self.vx += (tvx - self.vx) * k;
        self.vy += (tvy - self.vy) * k;
        self.x += self.vx * dt;
        self.y += self.vy * dt;
        if self.vx.abs() > 8.0 { self.facing = if self.vx > 0.0 { 1 } else { -1 }; }
        self.flap_t += dt * if self.vy > 20.0 || self.vx.abs() > 60.0 { 1.6 } else { 1.0 };
        d < 6.0
    }

    pub fn fly_bounds(&self, w: &Env) -> Rect {
        let a = self.area(w);
        let m = self.margin(w);
        Rect::new(a.min_x() + m, a.min_y() + 10.0, (a.width() - 2.0 * m).max(1.0), (a.height() - self.chh as f64 * w.scale() - 20.0).max(1.0))
    }

    /// Turn toward a point, with a dead zone and a short cooldown so it never flickers.
    pub fn face(&mut self, w: &Env, toward: Point, dead: f64) {
        if w.t - self.turn_at <= 0.8 { return; }
        let f = self.fwd_vec();
        let d = (toward.x - self.x) * f.0 + (toward.y - self.y) * f.1;
        if d.abs() <= dead { return; }
        let nf = if d > 0.0 { 1 } else { -1 };
        if nf != self.facing { self.facing = nf; self.turn_at = w.t; }
    }

    // MARK: Lifecycle

    pub fn spawn_in(&mut self, w: &mut Env) {
        let main = w.main_screen();
        let (lo, hi) = w.x_range(self.margin(w));
        if self.x == 0.0 || !(self.x >= lo && self.x <= hi) { self.x = main.visible.mid_x() + rnd(-250.0, 250.0); }
        self.x = clamp(self.x, lo, hi);
        let a = w.area(pt(self.x, main.frame.mid_y()));
        self.y = a.max_y() - self.chh as f64 * w.scale() * 0.9;
        self.apex_y = self.y;
        self.edge = 0;
        self.mode = Mode::Idle;
        if self.is_bird() {
            self.in_air = true; self.vy = -60.0;
            self.fly_goal = if self.fly_mode(w) { FlyGoal::Wander } else { FlyGoal::Land };
            self.set_mode(w, Mode::Fly);
        } else if !self.wall_mode(w) {
            self.set_mode(w, Mode::Glide);
        } else {
            self.y = a.mid_y();
            self.vx = rnd(-160.0, 160.0); self.vy = rnd(-160.0, 160.0);
            self.set_mode(w, Mode::Drift);
        }
    }

    pub fn update(&mut self, w: &mut Env, dt: f64) {
        self.mode_t += dt; self.act_t += dt;
        self.moving = false; self.running = false;
        if w.t > self.next_blink { self.blink_until = w.t + 0.12; self.next_blink = w.t + rnd(2.5, 6.0); }
        if !self.frozen(w) || self.in_air || matches!(self.mode, Mode::Held | Mode::Glide | Mode::Drift) {
            self.think(w, dt);
            self.physics(w, dt);
        }
        let t = w.t;
        if self.later_drops.iter().any(|&d| t >= d) {
            let n = self.later_drops.iter().filter(|&&d| t >= d).count();
            self.later_drops.retain(|&d| t < d);
            for _ in 0..n { self.spawn_drop(); }
        }
        self.update_particles(dt);
        let old = std::mem::take(&mut self.canvas.px);
        self.render_canvas(w);
        self.place(w);
        self.update_mouse(w, dt);
        if self.canvas.px != old || self.edge as i32 != self.drawn_edge {
            self.drawn_edge = self.edge as i32;
            self.dirty = true;
        }
    }

    /// The panel is open on this pet: sit still and look at the person.
    pub fn freeze(&mut self, w: &mut Env) {
        if self.in_air || matches!(self.mode, Mode::Held | Mode::Glide | Mode::Drift) || self.edge != 0 { return; }
        if !self.is_asleep() {
            self.set_mode(w, Mode::Idle);
            self.act = if self.is_bird() { IdleAct::Stand } else { IdleAct::Sit };
            self.act_t = 0.0; self.act_dur = 1.5;
        }
    }

    pub fn environment_changed(&mut self, w: &mut Env) {
        if self.mode == Mode::Held { return; }
        if self.ceiling_mode(w) {
            if self.edge == 2 && self.mode != Mode::Drift { return; }
            if self.family() == Family::Bat { if self.mode != Mode::Drift { self.swoop(w, true); } return; }
            // Startled by the fullscreen app: a jump, and a dash for the top edge.
            self.release_food(w);
            self.spawn_bang();
            self.say(&[if self.family() == Family::Cat { "EEK!" } else { "WHOA!" }], 1.4, w);
            w.play(if self.family() == Family::Cat { "hiss" } else { "woof" });
            self.hop_y = 0.0; self.hop_v = 0.0; self.umbrella = false;
            self.vx = 0.0; self.vy = 1500.0 * w.scale() / 4.0;
            self.set_mode(w, Mode::Drift);
            return;
        }
        if w.gravity {
            if self.is_bird() {
                if self.in_air && !self.fly_mode(w) { self.fly_goal = FlyGoal::Land; self.after_land = None; }
                if !self.in_air && self.fly_mode(w) && matches!(self.mode, Mode::Idle | Mode::Walk) { self.take_off(w); }
            } else if self.edge != 0 || self.mode == Mode::Drift {
                // back from the top edge (fullscreen ended, or gravity turned on): a quick drop, no slow umbrella float
                let a = self.area(w);
                let m = self.margin(w);
                self.x = clamp(self.x, a.min_x() + m, a.max_x() - m);
                self.y = clamp(self.y, a.min_y(), a.max_y() - self.chh as f64 * w.scale() * 0.8);
                self.edge = 0;
                self.start_falling(w);
                self.quick_drop = true;
            }
        } else if self.is_bird() {
            if !self.in_air { self.take_off(w); }
        } else {
            self.p = self.perimeter_p(w, self.x, self.y);
            if self.mode == Mode::Glide { self.umbrella = false; self.set_mode(w, Mode::Drift); }
        }
    }

    pub fn take_off(&mut self, w: &mut Env) {
        self.in_air = true;
        self.edge = 0;
        self.vy = 220.0 * w.scale() / 4.0;
        self.vx = self.facing as f64 * 40.0;
        self.fly_goal = FlyGoal::Wander;
        self.fly_target = None;
        self.after_land = None;
        self.set_mode(w, Mode::Fly);
    }

    pub fn start_falling(&mut self, w: &mut Env) {
        self.apex_y = self.y;
        self.hop_y = 0.0;
        if self.is_bird() {
            self.in_air = true; self.fly_goal = FlyGoal::Land; self.after_land = None;
            self.set_mode(w, Mode::Fly);
        } else {
            self.umbrella = false;
            self.vx = 0.0; self.vy = 0.0;
            self.set_mode(w, Mode::Glide);
        }
    }

    // MARK: Brain

    pub fn set_mode(&mut self, w: &mut Env, m: Mode) {
        if m == self.mode { return; }
        if self.mode == Mode::Eating { self.release_food(w); }
        if self.mode == Mode::Glide { self.umbrella = false; }
        self.mode = m;
        self.mode_t = 0.0;
        let t = w.t;
        match m {
            Mode::Waking => { self.spawn_bang(); w.play("yawn"); }
            Mode::Watching => { self.seated = false; self.next_react = t + rnd(30.0, 60.0); }
            Mode::Ball => self.kicks = 0,
            Mode::Zoomies => self.walk_target = self.far_target(w),
            Mode::Hunt => { self.hunt_phase = 0; self.hunt_t = 0.0; }
            Mode::Catnap => self.next_z = t + 1.0,
            Mode::Sleeping => { self.slept_at = t; self.next_z = t + 0.4; }
            Mode::Listening => self.next_note = t + 0.3,
            _ => {}
        }
    }

    pub fn release_food(&mut self, w: &mut Env) {
        if let Some(id) = self.food {
            if let Some(f) = w.items.iter_mut().find(|i| i.id == id) { f.claimed = false; }
        }
        self.food = None;
    }

    pub fn say(&mut self, lines: &[&str], dur: f64, w: &Env) {
        self.bubble_lines = lines.iter().map(|l| sanitize(l)).filter(|l| !l.is_empty()).collect();
        self.bubble_until = w.t + dur;
    }

    /// Starts a mode, landing or climbing down first if the pet needs the floor for it.
    pub fn begin(&mut self, w: &mut Env, m: Mode) -> bool {
        if self.in_air && (ground_mode(m) || (m == Mode::Eating && w.gravity)) {
            self.fly_goal = FlyGoal::Land;
            self.after_land = Some(m);
            if self.mode != Mode::Fly { self.set_mode(w, Mode::Fly); }
            return true;
        }
        self.set_mode(w, m);
        true
    }

    fn free_food(w: &Env) -> Option<usize> {
        w.items.iter().position(|f| f.is_food() && !f.gone && !f.claimed && !f.refused_by)
    }

    fn claim(&mut self, w: &mut Env, i: usize) {
        w.items[i].claimed = true;
        self.food = Some(w.items[i].id);
    }

    /// High-priority reasons to stop whatever ambient thing the pet is doing.
    pub fn ambient_interrupt(&mut self, w: &mut Env, skip_music: bool) -> bool {
        if w.typing_now() { return self.begin(w, Mode::Typing); }
        if w.video_playing() { return self.begin(w, Mode::Watching); }
        if let Some(i) = Self::free_food(w) {
            self.claim(w, i);
            self.spawn_bang();
            return self.begin(w, Mode::Eating);
        }
        if w.items.iter().any(|i| i.is_ball() && !i.gone) { return self.begin(w, Mode::Ball); }
        if w.items.iter().any(|i| i.kind == ItemKind::Butterfly && !i.leaving && !i.gone) {
            self.spawn_bang();
            return self.begin(w, Mode::Butterfly);
        }
        if !skip_music && !self.following(w) && w.music_playing && w.idle_secs < (self.sleep_threshold(w) * 3.0).max(600.0) {
            return self.begin(w, Mode::Listening);
        }
        if w.idle_secs > self.sleep_threshold(w) { return self.begin(w, Mode::Yawning); }
        false
    }

    pub fn think(&mut self, w: &mut Env, dt: f64) {
        let t = w.t;
        if self.following(w) { self.follow(w); }
        // pressed while on the move: stop and look at you right away (the click's answer follows a beat later)
        if t < self.noticed_until && !self.in_air && matches!(self.mode, Mode::Walk | Mode::Zoomies | Mode::Hunt | Mode::Ball | Mode::Butterfly) {
            self.moving = false;
            self.face(w, w.mouse, 10.0);
            return;
        }
        // food and toys get noticed even mid-typing or mid-movie
        if !self.in_air && matches!(self.mode, Mode::Typing | Mode::Watching | Mode::Listening) {
            if let Some(i) = Self::free_food(w) {
                self.claim(w, i); self.spawn_bang(); self.begin(w, Mode::Eating); return;
            }
            if w.items.iter().any(|i| i.is_ball() && !i.gone) { self.play_until = t + 10.0; self.spawn_bang(); self.begin(w, Mode::Ball); return; }
        }
        // notice typing and videos whatever it's busy with, except moments it can't stop (held, falling, landing, eating)
        use Mode::*;
        let cannot = matches!(self.mode, Held | Glide | Drift | Landing | Dizzy | Eating | Typing | Watching | Waking | Sleeping | Yawning | Catnap | Agenda);
        if !self.in_air && !cannot && !(self.mode == Ball && t < self.play_until) {
            if w.typing_now() { self.begin(w, Typing); return; }
            if w.video_playing() && self.mode != Listening { self.begin(w, Watching); return; }
        }
        match self.mode {
            Held => {}
            Fly => self.fly_think(w, dt),
            Glide => self.glide_think(w, dt),
            Drift => self.drift_think(w, dt),
            Landing => { if self.mode_t > 0.35 { self.greet_or_idle(w); } }
            Dizzy => { if self.mode_t > 2.6 { self.say(&["WOAH..."], 1.6, w); self.greet_or_idle(w); } }
            Idle => self.idle_think(w, dt),
            Walk => {
                if self.ambient_interrupt(w, false) { return; }
                let speed = if self.is_bird() { 55.0 } else if self.family() == Family::Dog { 50.0 } else { 42.0 };
                let run = self.running;
                if self.go(w, self.walk_target, speed, dt, run) {
                    self.set_mode(w, Idle); self.act = IdleAct::Stand; self.act_t = 0.0; self.act_dur = rnd(1.5, 4.0);
                }
            }
            Typing => {
                if !w.typing_recently() {
                    self.set_mode(w, Idle);
                    self.act = if self.is_bird() { IdleAct::Stand } else { IdleAct::Sit }; self.act_t = 0.0; self.act_dur = rnd(2.0, 4.0);
                }
            }
            Watching => self.watch_think(w, dt),
            Listening => self.listen_think(w, dt),
            Yawning => {
                if !self.forced_nap && w.idle_secs < 0.8 && self.mode_t > 0.3 {
                    self.spawn(PKind::Question, self.head.0 as f64, self.head.1 as f64 - 3.0, 0.0, -2.0, 1.0, 0.0, 0);
                    self.set_mode(w, Idle);
                    return;
                }
                if self.mode_t > 2.8 { self.set_mode(w, Sleeping); }
            }
            Sleeping => {
                if t > self.next_z { self.next_z = t + rnd(1.0, 1.6); self.spawn_z(); }
                if self.forced_nap {
                    if self.energy >= 100.0 && self.mode_t > 60.0 { self.forced_nap = false; self.set_mode(w, Waking); }
                } else if w.idle_secs < 0.8 || (w.video_playing() && self.mode_t > 2.0) {
                    self.set_mode(w, Waking);
                }
            }
            Catnap => {
                if t > self.next_z { self.next_z = t + rnd(1.2, 1.8); self.spawn_z(); }
                if t > self.nap_end || w.typing_now() || w.video_playing() || w.items.iter().any(|i| !i.gone && i.kind != ItemKind::Butterfly) {
                    self.set_mode(w, Waking);
                }
            }
            Waking => {
                if self.mode_t > 2.6 {
                    if w.typing_now() { self.set_mode(w, Typing); return; }
                    if t - self.slept_at > 60.0 && self.slept_at > 0.0 {
                        self.say(&[if t - self.slept_at > 1800.0 { "GOOD MORNING!" } else { "HI!" }], 1.8, w);
                    }
                    self.slept_at = 0.0;
                    self.set_mode(w, Idle);
                    self.act = if self.is_bird() { IdleAct::Stand } else { IdleAct::Sit }; self.act_t = 0.0; self.act_dur = 2.0;
                }
            }
            Eating => self.eat_think(w, dt),
            Refusing => {
                self.facing = if self.mode_t < 1.2 && (self.mode_t / 0.2) as i64 % 2 == 1 { -self.refuse_facing } else { self.refuse_facing };
                if self.mode_t > 1.8 { self.set_mode(w, Idle); }
            }
            Ball => self.ball_think(w, dt),
            Tired => {
                if t > self.next_sweat {
                    self.next_sweat = t + 0.7;
                    let f = self.facing as f64;
                    self.spawn(PKind::Drop, self.head.0 as f64 - f * 2.0, self.head.1 as f64, -f * 2.0, -2.0, 0.8, 14.0, 0);
                }
                if self.mode_t > 3.5 { self.energy = (self.energy - 5.0).max(0.0); self.set_mode(w, Idle); }
            }
            Butterfly => self.butterfly_think(w, dt),
            Vocal | Petted => {
                if self.mode_t > if self.mode == Vocal { 0.9 } else { 2.6 } { self.set_mode(w, Idle); }
            }
            Angry => self.angry_think(w, dt),
            Beg => { if self.mode_t > 3.2 { self.set_mode(w, Idle); } }
            Agenda => {
                if t > self.agenda_until || (w.typing_now() && w.last_key_t > t - self.mode_t + 0.5) { self.set_mode(w, Idle); }
            }
            Zoomies => {
                if w.typing_now() || w.video_playing() { self.set_mode(w, Idle); return; }
                if self.go(w, self.walk_target, 250.0, dt, true) {
                    self.zoom_left -= 1;
                    if self.zoom_left <= 0 {
                        self.set_mode(w, Idle);
                        self.act = if self.family() == Family::Cat { IdleAct::Groom } else { IdleAct::Sit }; self.act_t = 0.0; self.act_dur = 3.0;
                        self.say(&["!"], 0.8, w);
                    } else {
                        self.walk_target = self.far_target(w);
                    }
                }
            }
            Hunt => self.hunt_think(w, dt),
        }
    }

    fn greet_or_idle(&mut self, w: &mut Env) {
        self.set_mode(w, Mode::Idle);
        self.act = if self.is_bird() { IdleAct::Stand } else { IdleAct::Sit }; self.act_t = 0.0; self.act_dur = 2.5;
        if self.greeted { return; }
        self.greeted = true;
        if w.first_run {
            let hi = format!("HI! I'M {}", sanitize(&self.name));
            self.say(&[&hi, "DRAG ME AROUND!"], 4.0, w);
        } else if w.away_seconds > 3.0 * 3600.0 {
            self.say(&["MISSED YOU!"], 2.5, w);
            self.hearts(3);
        } else {
            self.say(&["HI!"], 1.8, w);
        }
        w.play(if self.family() == Family::Cat { "mrrp" } else { "chirp" });
    }

    fn idle_think(&mut self, w: &mut Env, dt: f64) {
        let t = w.t;
        if self.in_air {
            self.fly_goal = if self.fly_mode(w) { FlyGoal::Wander } else { FlyGoal::Land };
            self.after_land = None;
            self.set_mode(w, Mode::Fly);
            return;
        }
        if self.ambient_interrupt(w, false) { return; }
        if self.fly_mode(w) && self.mode_t > if t - w.last_play > 180.0 { 20.0 } else { 1.5 } { self.take_off(w); return; }   // calm birds perch a while
        if self.fullness < 25.0 && t > self.next_beg {
            self.next_beg = t + rnd(70.0, 140.0);
            self.set_mode(w, Mode::Beg);
            let word = format!("{}...", self.species.vocal().0);
            self.say(&[if self.is_bird() { "HUNGRY..." } else { &word }], 3.0, w);
            return;
        }
        if self.family() == Family::Cat && self.edge == 0 && !self.ceiling_mode(w) && self.act != IdleAct::Lie && self.act != IdleAct::Stretch {
            let m = w.mouse;
            let near = (m.x - self.x).abs() < 420.0 && m.y - self.y < 170.0 && m.y > self.y - 10.0 && !self.mouse_inside;
            if near && t - self.cursor_moved_at < 0.4 && chance(dt * 0.25) { self.set_mode(w, Mode::Hunt); return; }
        }
        match self.act {
            IdleAct::Look => {
                if (self.act_t / 0.9) as i64 != ((self.act_t - dt) / 0.9) as i64 && chance(0.5) && self.edge == 0 { self.facing = -self.facing; self.turn_at = t; }
            }
            IdleAct::Stand | IdleAct::Gaze | IdleAct::Sit | IdleAct::Lie => {
                let m = w.mouse;
                if !self.mouse_inside && (m.x - self.x).hypot(m.y - self.y) < 500.0 { self.face(w, m, 60.0); }
            }
            _ => {}
        }
        if self.act_t > self.act_dur { self.next_act(w); }
    }

    fn next_act(&mut self, w: &mut Env) {
        use IdleAct::*;
        let t = w.t;
        self.act_t = 0.0;
        let r = rng::unit();
        if self.ceiling_mode(w) {
            // Fullscreen app: pad along the top edge upside down, now and then stopping to look around.
            let (lo, hi) = self.top_span(w);
            if self.edge != 2 || !(self.p >= lo && self.p <= hi) {
                self.walk_target = clamp(self.p, lo, hi); self.running = false; self.set_mode(w, Mode::Walk); return;
            }
            let calm = t - w.last_play > 180.0;
            if self.family() == Family::Bat {
                if r < if calm { 0.06 } else { 0.18 } { self.swoop(w, false); return; }
                if r < if calm { 0.2 } else { 0.4 } { self.start_walk(w); return; }
                self.act = *rng::pick(&[Stand, Stand, Look, Lie]);
                self.act_dur = if calm { rnd(12.0, 30.0) } else { rnd(3.0, 8.0) };
                return;
            }
            if r < if calm { 0.25 } else { 0.5 } { self.start_walk(w); return; }
            self.act = *rng::pick(&[Stand, Look, Stand]);
            self.act_dur = if calm { rnd(8.0, 20.0) } else { rnd(2.0, 6.0) };
            return;
        }
        if t - w.last_play > 180.0 && chance(0.5) {
            // Left alone for a few minutes, pets settle down like real ones: longer rests, fewer walks (and much less power).
            self.act = if self.is_bird() { *rng::pick(&[Sit, Stand, Sit]) }
                       else { *rng::pick(&[Lie, Sit, Lie, if self.family() == Family::Cat { Groom } else { Lie }]) };
            self.act_dur = rnd(10.0, 25.0);
            return;
        }
        if self.wall_mode(w) && self.edge != 0 {
            // clinging to a wall or the ceiling: mostly keep climbing
            if r < 0.6 { self.start_walk(w); } else { self.act = Stand; self.act_dur = rnd(2.0, 5.0); }
            return;
        }
        let s = w.scale();
        match self.family() {
            Family::Bird => {
                if r < 0.34 { self.start_walk(w); return; }
                else if r < 0.48 { self.act = Look; self.act_dur = rnd(2.0, 4.0); }
                else if r < 0.58 { self.act = Sit; self.act_dur = rnd(5.0, 12.0); }
                else if r < 0.66 { self.act = Preen; self.act_dur = rnd(2.0, 3.5); }
                else if r < 0.74 { self.act = Peck; self.act_dur = rnd(1.5, 3.0); }
                else if r < 0.78 { self.act = Vocal; self.act_dur = 0.9; let v = self.species.vocal().0; self.say(&[v], 0.9, w); }
                else if r < 0.83 { self.act = Flap; self.act_dur = 1.0; }
                else if r < 0.87 { self.act = Hop; self.act_dur = 0.8; self.hop_v = 320.0 * s / 4.0; }
                else if r < 0.92 { self.act = Gaze; self.act_dur = rnd(1.5, 3.0); }
                else { self.act = Stand; self.act_dur = rnd(2.0, 5.0); }
            }
            Family::Cat => {
                if r < 0.26 { self.start_walk(w); return; }
                else if r < 0.40 { self.act = Sit; self.act_dur = rnd(5.0, 14.0); }
                else if r < 0.50 { self.act = Lie; self.act_dur = rnd(8.0, 20.0); }
                else if r < 0.60 { self.act = Groom; self.act_dur = rnd(3.0, 6.0); }
                else if r < 0.65 { self.act = Stretch; self.act_dur = 2.2; }
                else if r < 0.71 { self.act = Look; self.act_dur = rnd(2.0, 4.0); }
                else if r < 0.74 { self.act = Vocal; self.act_dur = 1.0; self.say(&[*rng::pick(&["MEOW", "MRRP?", "MEW"])], 1.0, w); }
                else if r < 0.80 {
                    if self.energy < 85.0 { self.nap_end = t + rnd(20.0, 50.0); self.set_mode(w, Mode::Catnap); return; }
                    self.act = Lie; self.act_dur = rnd(6.0, 12.0);
                }
                else if r < 0.84 { self.zoom_left = rng::int(3, 5); self.set_mode(w, Mode::Zoomies); return; }
                else if r < 0.90 { self.act = Gaze; self.act_dur = rnd(2.0, 4.0); }
                else { self.act = Stand; self.act_dur = rnd(2.0, 5.0); }
            }
            Family::Bat => { self.act = Stand; self.act_dur = rnd(3.0, 8.0); }
            Family::Dog => {
                if r < 0.34 { self.start_walk(w); return; }
                else if r < 0.48 { self.act = Sit; self.act_dur = rnd(4.0, 10.0); }
                else if r < 0.58 { self.act = Lie; self.act_dur = rnd(6.0, 16.0); }
                else if r < 0.64 { self.act = Stretch; self.act_dur = 1.8; }
                else if r < 0.70 { self.act = Look; self.act_dur = rnd(2.0, 4.0); }
                else if r < 0.74 { self.act = Vocal; self.act_dur = 0.9; let v = format!("{}!", self.species.vocal().0); self.say(&[&v], 0.9, w); }
                else if r < 0.79 { self.zoom_left = rng::int(3, 4); self.set_mode(w, Mode::Zoomies); return; }
                else if r < 0.84 { self.act = Hop; self.act_dur = 0.8; self.hop_v = 300.0 * s / 4.0; }
                else if r < 0.90 { self.act = Gaze; self.act_dur = rnd(2.0, 4.0); }
                else { self.act = Stand; self.act_dur = rnd(2.0, 5.0); }
            }
        }
        if self.energy < 30.0 && chance(0.3) { self.act = Yawn; self.act_dur = 1.4; }
    }

    /// A bat lets go of the top edge, flutters out in an arc and flies back up (or just flies up, `home`).
    fn swoop(&mut self, w: &mut Env, home: bool) {
        let a = self.area(w);
        let s = w.scale();
        self.edge = 0;
        self.y = self.y.min(a.max_y() - 30.0 * s);
        if home { self.vx = 0.0; self.vy = 300.0 * s / 4.0; }
        else {
            self.vx = if rng::coin() { 1.0 } else { -1.0 } * rnd(380.0, 560.0) * s / 4.0;
            self.vy = -rnd(750.0, 1000.0) * s / 4.0;
            w.play("chirp");
        }
        self.set_mode(w, Mode::Drift);
    }

    fn start_walk(&mut self, w: &mut Env) {
        self.walk_target = self.random_walk_target(w);
        self.running = false;
        self.set_mode(w, Mode::Walk);
    }

    /// The stretch of the edge track along the top of the screen.
    fn top_span(&self, w: &Env) -> (f64, f64) {
        let (r, _) = self.perimeter(w, self.area(w));
        let lo = r.width() + r.height();
        (lo + 4.0, lo + 8.0f64.max(r.width() - 4.0))
    }

    fn random_walk_target(&self, w: &Env) -> f64 {
        if self.ceiling_mode(w) {
            let (lo, hi) = self.top_span(w);
            return clamp(self.p + rnd(-450.0, 450.0), lo, hi);
        }
        if self.wall_mode(w) {
            let l = self.perimeter(w, self.area(w)).1;
            return self.p + rnd(-l * 0.3, l * 0.3);
        }
        let vf = w.area(pt(self.x, self.y));
        let m = self.margin(w);
        let lo = (vf.min_x() + m).max(self.x - 450.0);
        let hi = (vf.max_x() - m).min(self.x + 450.0);
        if lo < hi { rnd(lo, hi) } else { self.x }
    }

    fn far_target(&self, w: &Env) -> f64 {
        if self.ceiling_mode(w) { let (lo, hi) = self.top_span(w); return rnd(lo, hi); }
        if self.wall_mode(w) {
            let l = self.perimeter(w, self.area(w)).1;
            return self.p + if rng::coin() { 1.0 } else { -1.0 } * rnd(l * 0.15, l * 0.4);
        }
        let vf = w.area(pt(self.x, self.y));
        let m = self.margin(w);
        let lo = vf.min_x() + m;
        let hi = vf.max_x() - m;
        if lo >= hi { return self.x; }
        let mid = (lo + hi) / 2.0;
        if self.x > mid { rnd(lo, lo.max(mid)) } else { rnd(hi.min(mid), hi) }
    }

    fn fly_think(&mut self, w: &mut Env, dt: f64) {
        if self.fly_goal == FlyGoal::Wander && (!self.fly_mode(w) || self.shake >= 6) { self.fly_goal = FlyGoal::Land; self.after_land = None; }
        if self.fly_goal == FlyGoal::Wander {
            if self.frozen(w) {   // hover by the open menu
                let here = pt(self.x, self.y);
                self.fly_target = Some(here); self.next_fly_pick = w.t + 1.0; self.fly_to(w, here, 95.0, dt); return;
            }
            if self.ambient_interrupt(w, false) && (self.mode != Mode::Fly || self.fly_goal == FlyGoal::Land) { return; }
            let b = self.fly_bounds(w);
            if self.fly_target.is_none() || w.t > self.next_fly_pick {
                if chance(0.3) {
                    self.fly_target = Some(pt(self.x, self.y));
                } else {
                    self.fly_target = Some(pt(rnd(b.min_x(), b.max_x()), rnd(b.max_y().min(b.min_y() + 40.0), b.max_y())));
                }
                self.next_fly_pick = w.t + rnd(3.0, 7.0);
            }
            let tg = self.fly_target.unwrap();
            self.fly_to(w, tg, 95.0, dt);
            return;
        }
        let fl = w.floor_y(self.x, self.y);
        let (lo, hi) = w.x_range(self.margin(w));
        let tx = clamp(self.x + self.vx * 0.25, lo, hi);
        self.fly_to(w, pt(tx, fl), 130.0, dt);
        if self.y - fl < 4.0 {
            self.y = fl; self.vx = 0.0; self.vy = 0.0;
            self.in_air = false;
            self.edge = 0;
            if self.shake >= 6 {
                self.shake = 0;
                self.set_mode(w, Mode::Dizzy);
                self.stars(5);
            } else if let Some(m) = self.after_land {
                self.after_land = None;
                self.set_mode(w, m);
            } else {
                self.set_mode(w, Mode::Landing);
            }
        }
    }

    /// Gravity on: pop an umbrella and float down.
    fn glide_think(&mut self, w: &mut Env, dt: f64) {
        let s = w.scale();
        let t = w.t;
        let fl = w.floor_y(self.x, self.y);
        if !self.umbrella && !self.quick_drop && self.mode_t > 0.2 && self.vy < 0.0 && self.y - fl > 60.0 {
            self.umbrella = true;
            w.play("pop");
        }
        if self.umbrella {
            self.vy += (-105.0 * s / 4.0 - self.vy) * (dt * 4.0).min(1.0);
            self.vx *= 0.3f64.powf(dt);
            self.x += (t * 2.2).sin() * 22.0 * dt * s / 4.0;
        } else {
            self.vy -= 2200.0 * dt * s / 4.0;
        }
        self.x += self.vx * dt;
        self.y += self.vy * dt;
        self.apex_y = self.apex_y.max(self.y);
        // pushed or thrown off screen: drift back in smoothly instead of snapping to the edge
        let (lo, hi) = w.x_range(self.margin(w));
        let in_x = clamp(self.x, lo, hi);
        if in_x != self.x {
            self.x += (in_x - self.x) * (dt * 6.0).min(1.0);
            if (self.x < in_x && self.vx < 0.0) || (self.x > in_x && self.vx > 0.0) { self.vx *= 0.05f64.powf(dt); }
        }
        let top = w.area(pt(self.x, self.y)).max_y() - self.chh as f64 * s;
        if self.y > top { self.y += (top - self.y) * (dt * 6.0).min(1.0); self.vy = self.vy.min(0.0); }
        if self.y <= fl {
            self.y = fl; self.vx = 0.0; self.vy = 0.0;
            self.quick_drop = false;
            if self.umbrella {
                self.umbrella = false;
                self.spawn(PKind::Puff, self.cx as f64, (self.chh - 30) as f64, 0.0, -2.0, 0.5, 0.0, 0);
            }
            if self.shake >= 6 {
                self.set_mode(w, Mode::Dizzy);
                self.stars(5);
            } else {
                self.set_mode(w, Mode::Landing);
                w.play(if self.family() == Family::Cat { "mrrp" } else { "pop" });
            }
            self.shake = 0;
        }
    }

    /// Zero gravity: zip over to the nearest screen edge and hold on to it.
    fn drift_think(&mut self, w: &mut Env, dt: f64) {
        let a = self.area(w);
        // let go somewhere off screen: glide back inside first, then head for an edge
        let inside = pt(clamp(self.x, a.min_x(), a.max_x()), clamp(self.y, a.min_y(), a.max_y()));
        if (inside.x - self.x).hypot(inside.y - self.y) > 6.0 {
            self.x += (inside.x - self.x) * (dt * 7.0).min(1.0);
            self.y += (inside.y - self.y) * (dt * 7.0).min(1.0);
            self.vx *= 0.1f64.powf(dt); self.vy *= 0.1f64.powf(dt);
            return;
        }
        let d_b = self.y - a.min_y();
        let d_t = a.max_y() - self.y;
        let d_l = self.x - a.min_x();
        let d_r = a.max_x() - self.x;
        let m = d_b.min(d_t).min(d_l).min(d_r);
        let ceiling = self.ceiling_mode(w);
        let dir = if ceiling { (0.0, 1.0) }
            else if m == d_b { (0.0, -1.0) } else if m == d_t { (0.0, 1.0) } else if m == d_l { (-1.0, 0.0) } else { (1.0, 0.0) };
        // straight up to the top edge, fast; a bat's gentler pull turns its swoops into arcs
        let pull = (if self.family() == Family::Bat { 1500.0 } else if ceiling { 5200.0 } else { 2600.0 }) * w.scale() / 4.0 * dt;
        self.vx = self.vx * 0.15f64.powf(dt) + dir.0 * pull;
        self.vy = self.vy * 0.15f64.powf(dt) + dir.1 * pull;
        self.x += self.vx * dt;
        self.y += self.vy * dt;
        if self.x <= a.min_x() || self.x >= a.max_x() || self.y <= a.min_y() || self.y >= a.max_y() {
            self.x = clamp(self.x, a.min_x(), a.max_x());
            self.y = clamp(self.y, a.min_y(), a.max_y());
            if ceiling { let r = self.perimeter(w, a).0; self.x = clamp(self.x, r.min_x() + 4.0, r.max_x() - 4.0); self.y = a.max_y(); }
            self.p = self.perimeter_p(w, self.x, self.y);
            self.vx = 0.0; self.vy = 0.0;
            self.place_on_perimeter(w);
            if self.shake >= 6 { self.shake = 0; self.set_mode(w, Mode::Dizzy); self.stars(5); } else { self.set_mode(w, Mode::Landing); }
        }
    }

    fn watch_think(&mut self, w: &mut Env, dt: f64) {
        if w.typing_now() { self.begin(w, Mode::Typing); return; }
        if !w.video_playing() && w.t - w.last_video_seen > 4.0 {
            self.say(&["THAT WAS FUN!"], 2.2, w);
            self.set_mode(w, Mode::Idle);
            return;
        }
        if let Some(f) = w.video_frame {
            let (lo, hi) = w.x_range(self.margin(w));
            let seat_x = clamp(f.max_x() - 60.0 * w.scale() / 4.0, lo, hi);
            let target = self.floor_target(w, seat_x, self.area(w).min_y());
            if self.seated && self.track_delta(w, target).abs() > 140.0 { self.seated = false; }
            if !self.seated {
                // hurry over so it doesn't miss the start
                let fast = self.track_delta(w, target).abs() > 400.0;
                if self.go(w, target, if fast { 260.0 } else { 160.0 }, dt, true) { self.seated = true; self.pop_t = 0.0; } else { return; }
            }
            if self.edge == 0 { self.facing = if f.mid_x() > self.x { 1 } else { -1 }; }
        } else {
            self.seated = true;
        }
        let before = self.pop_t % 3.4;
        self.pop_t += dt;
        let cyc = self.pop_t % 3.4;
        if before < 2.05 && cyc >= 2.05 && chance(0.35) {
            let f = self.facing as f64;
            self.spawn(PKind::Kernel, self.local_x(self.cx + if self.is_bird() { 12 } else { 10 }), (self.chh - 12) as f64,
                       f * rnd(2.0, 6.0), -rnd(8.0, 12.0), 1.6, 30.0, 0);
        }
        if w.t > self.next_react {
            self.next_react = w.t + rnd(40.0, 100.0);
            self.say(&[*rng::pick(&["OOH", "HAHA", "WOW!", "NICE", "!!"])], 1.6, w);
        }
    }

    fn listen_think(&mut self, w: &mut Env, _dt: f64) {
        if w.typing_now() { self.begin(w, Mode::Typing); return; }
        if w.video_playing() { self.begin(w, Mode::Watching); return; }
        if !w.music_playing { if self.mode_t > 1.0 { self.set_mode(w, Mode::Idle); } return; }
        if self.ambient_interrupt(w, true) { return; }
        if w.t > self.next_note {
            self.next_note = w.t + rnd(1.6, 2.6);
            self.spawn(PKind::Note, self.head.0 as f64 + rnd(-5.0, 5.0), self.head.1 as f64 - 2.0, rnd(-2.5, 2.5), -rnd(3.5, 5.5), 1.8, 0.0, 0);
        }
    }

    fn eat_think(&mut self, w: &mut Env, dt: f64) {
        let s = w.scale();
        let Some(fi) = self.food.and_then(|id| w.items.iter().position(|i| i.id == id && !i.gone)) else {
            self.food = None; self.set_mode(w, Mode::Idle); return;
        };
        if w.gravity && !self.wall_mode(w) {
            let (fx, fy, held, on_ground) = { let f = &w.items[fi]; (f.x, f.y, f.held, f.on_ground) };
            if held || !on_ground {
                self.face(w, pt(fx, fy), 10.0);
                if !held && !self.in_air { let tx = fx - self.facing as f64 * 12.0 * s; self.go(w, tx, 120.0, dt, true); }
                return;
            }
            if self.in_air { self.begin(w, Mode::Eating); return; }
            let dir = if fx >= self.x { 1.0 } else { -1.0 };
            let stand_x = fx - dir * 12.0 * s;
            if (stand_x - self.x).abs() > 3.0 && !self.go(w, stand_x, 130.0, dt, true) { return; }
            self.facing = dir as i32;
        } else {
            let m = self.mouth_point(w);
            let f = &w.items[fi];
            if (f.x - m.x).hypot(f.y - m.y) > 10.0 * s { return; }
        }
        if self.fullness > 90.0 && w.items[fi].bites == 0 {
            w.items[fi].refused_by = true;
            self.release_food(w);
            self.refuse_facing = self.facing;
            self.set_mode(w, Mode::Refusing);
            self.say(&["I'M FULL!"], 2.0, w);
            return;
        }
        if w.t <= self.next_peck { return; }
        self.next_peck = w.t + 0.6;
        self.peck_start = w.t;
        w.items[fi].bites += 1;
        w.play("chomp");
        for _ in 0..3 {
            self.spawn(PKind::Crumb, self.local_x(self.cx + 12) + rnd(-2.0, 2.0), (self.chh - 5) as f64, rnd(-4.0, 4.0), -rnd(4.0, 9.0), 1.2, 30.0, 0);
        }
        if w.items[fi].bites >= 3 {
            let (value, kind) = (w.items[fi].value(), w.items[fi].kind);
            w.items[fi].close();
            self.food = None;
            self.fullness = (self.fullness + value).min(100.0);
            let favorite = self.species.favorites().contains(&kind);
            self.happiness = (self.happiness + if favorite { 12.0 } else { 6.0 }).min(100.0);
            self.hearts(if favorite { 6 } else { 4 });
            self.say(&[if favorite { "MY FAVORITE!" } else { "YUM!" }], 1.8, w);
            w.play(if self.family() == Family::Cat { "purr" } else { "chirp" });
            self.set_mode(w, Mode::Idle);
            self.act = if self.family() == Family::Cat { IdleAct::Groom } else { IdleAct::Stand }; self.act_t = 0.0; self.act_dur = 2.5;
        }
    }

    fn ball_think(&mut self, w: &mut Env, dt: f64) {
        let s = w.scale();
        let Some(bi) = w.items.iter().position(|i| i.is_ball() && !i.gone) else { self.set_mode(w, Mode::Idle); return; };
        if w.typing_now() { self.begin(w, Mode::Typing); return; }
        if w.video_playing() { self.begin(w, Mode::Watching); return; }
        if self.kicks >= 8 || w.t - w.items[bi].born > 50.0 {
            w.items[bi].close();
            w.play("poof");
            self.say(&["PHEW!"], 1.5, w);
            self.begin(w, Mode::Tired);
            return;
        }
        let (bx, by, held) = (w.items[bi].x, w.items[bi].y, w.items[bi].held);
        if held { self.face(w, pt(bx, by), 10.0); return; }
        if w.gravity && !self.wall_mode(w) && !self.in_air {
            let dir = if bx >= self.x { 1.0 } else { -1.0 };
            let kick_x = bx - dir * 9.0 * s;
            if (kick_x - self.x).abs() > 3.0 { self.go(w, kick_x, 150.0, dt, true); }
            self.facing = dir as i32;
            let low = by - w.floor_y(bx, by) < 10.0 * s;
            if low && (bx - (self.x + dir * 9.0 * s)).abs() < 6.0 * s && w.t > self.next_kick { self.kick(w, bi, (dir, 1.0)); }
        } else {
            if self.in_air {
                let tg = pt(bx - self.facing as f64 * 10.0 * s, by);
                self.fly_to(w, tg, 160.0, dt);
            } else {
                let tg = self.perimeter_p(w, bx, by);
                self.go(w, tg, 150.0, dt, true);
            }
            let m = self.mouth_point(w);
            let c = self.center_point(w);
            if (bx - m.x).hypot(by - m.y) < 10.0 * s && w.t > self.next_kick {
                let dx = bx - c.x;
                let dy = by - c.y;
                let d = dx.hypot(dy).max(1.0);
                self.kick(w, bi, (dx / d, dy / d));
            }
        }
    }

    fn kick(&mut self, w: &mut Env, bi: usize, dir: (f64, f64)) {
        let s = w.scale();
        self.next_kick = w.t + 0.7;
        self.kick_until = w.t + 0.25;
        self.kicks += 1;
        let sp = rnd(330.0, 560.0) * s / 4.0;
        let gravity = w.gravity;
        let b = &mut w.items[bi];
        b.vx = dir.0 * sp;
        b.vy = if gravity { rnd(280.0, 540.0) * s / 4.0 } else { dir.1 * sp };
        w.play("kick");
        self.happiness = (self.happiness + 2.0).min(100.0);
        if chance(0.3) { let v = format!("{}!", self.species.vocal().0); self.say(&[&v], 0.8, w); }
    }

    fn butterfly_think(&mut self, w: &mut Env, dt: f64) {
        let s = w.scale();
        if w.typing_now() { self.begin(w, Mode::Typing); return; }
        if w.video_playing() { self.begin(w, Mode::Watching); return; }
        let b = w.items.iter().find(|i| i.kind == ItemKind::Butterfly && !i.gone).filter(|b| !b.leaving).map(|b| (b.x, b.y));
        let Some((bx, by)) = b else {
            self.say(&["BYE BYE!"], 1.5, w);
            self.set_mode(w, Mode::Idle);
            return;
        };
        if self.in_air {
            let tg = pt(bx - self.facing as f64 * 12.0 * s, by - 8.0 * s);
            self.fly_to(w, tg, 120.0, dt);
        } else {
            let tg = self.floor_target(w, bx, by);
            self.go(w, tg, 120.0, dt, true);
            if self.edge == 0 && (bx - self.x).abs() < 40.0 * s / 4.0 && by - self.y < 110.0 * s / 4.0 && self.hop_y == 0.0 && chance(dt * 2.5) {
                self.hop_v = 360.0 * s / 4.0;
            }
        }
    }

    fn angry_think(&mut self, w: &mut Env, dt: f64) {
        let m = w.mouse;
        if self.family() == Family::Cat {
            if self.mode_t > 1.3 { let tg = self.floor_target(w, self.x + if self.x > m.x { 1.0 } else { -1.0 } * 300.0, self.y); self.go(w, tg, 200.0, dt, true); }
            if self.mode_t > 3.0 { self.say(&["HMPH."], 1.5, w); self.set_mode(w, Mode::Idle); }
        } else {
            if self.in_air { self.fly_to(w, pt(m.x, m.y - 20.0), 190.0, dt); }
            else { let tg = self.floor_target(w, m.x, m.y); self.go(w, tg, 190.0, dt, true); }
            if self.mode_t > 3.6 { self.say(&["HMPH."], 1.5, w); self.set_mode(w, Mode::Idle); }
        }
    }

    fn hunt_think(&mut self, w: &mut Env, dt: f64) {
        let s = w.scale();
        if w.typing_now() || w.video_playing() { self.set_mode(w, Mode::Idle); return; }
        let m = w.mouse;
        self.hunt_t += dt;
        match self.hunt_phase {
            0 => {
                self.face(w, m, 20.0);
                let tx = m.x - self.facing as f64 * 80.0 * s / 4.0;
                if self.go(w, tx, 30.0, dt, false) || self.hunt_t > 5.0 { self.hunt_phase = 1; self.hunt_t = 0.0; }
                if (m.x - self.x).abs() > 650.0 || m.y - self.y > 300.0 {
                    self.spawn(PKind::Question, self.head.0 as f64, self.head.1 as f64 - 3.0, 0.0, -2.0, 1.0, 0.0, 0);
                    self.set_mode(w, Mode::Idle);
                }
            }
            1 => {
                self.face(w, m, 20.0);
                if self.hunt_t > 1.3 {
                    self.hunt_phase = 2; self.hunt_t = 0.0;
                    self.hop_v = 380.0 * s / 4.0;
                    self.leap_v = self.facing as f64 * 120.0f64.max(320.0f64.min((m.x - self.x).abs() * 1.6)) * s / 4.0;
                }
            }
            2 => {
                if self.hop_y == 0.0 && self.hunt_t > 0.15 {
                    self.hunt_phase = 3; self.hunt_t = 0.0;
                    let mp = self.mouth_point(w);
                    if (m.x - mp.x).hypot(m.y - mp.y) < 70.0 {
                        self.say(&["GOTCHA!"], 1.2, w);
                        self.hearts(2);
                        self.happiness = (self.happiness + 3.0).min(100.0);
                    } else {
                        self.spawn(PKind::Question, self.head.0 as f64, self.head.1 as f64 - 3.0, 0.0, -2.0, 1.0, 0.0, 0);
                    }
                }
            }
            _ => {
                if self.hunt_t > 1.0 { self.set_mode(w, Mode::Idle); self.act = IdleAct::Sit; self.act_t = 0.0; self.act_dur = rnd(2.0, 4.0); }
            }
        }
    }

    // MARK: Physics

    fn physics(&mut self, w: &mut Env, dt: f64) {
        if self.hop_v != 0.0 || self.hop_y > 0.0 {
            self.hop_v -= 1500.0 * dt * w.scale() / 4.0;
            self.hop_y += self.hop_v * dt;
            if self.hop_y <= 0.0 {
                self.hop_y = 0.0; self.hop_v = 0.0; self.leap_v = 0.0;
            } else if self.leap_v != 0.0 {
                if self.wall_mode(w) { self.p += self.leap_v * dt; } else { self.x += self.leap_v * dt; }
            }
        }
        if matches!(self.mode, Mode::Held | Mode::Glide | Mode::Drift) || self.in_air { return; }
        if self.wall_mode(w) { self.place_on_perimeter(w); return; }
        self.edge = 0;
        let (lo, hi) = w.x_range(self.margin(w));
        self.x = clamp(self.x, lo, hi);
        let fl = w.floor_y(self.x, self.y);
        if self.y > fl + 2.0 { self.start_falling(w); } else { self.y = fl; }
    }

    // MARK: Particles

    #[allow(clippy::too_many_arguments)]
    pub fn spawn(&mut self, k: PKind, px: f64, py: f64, vx: f64, vy: f64, life: f64, g: f64, size: i32) {
        self.particles.push(Particle { kind: k, x: px, y: py, vx, vy, life, gravity: g, size });
        if self.particles.len() > 40 { self.particles.remove(0); }
    }

    pub fn spawn_drop(&mut self) {
        self.spawn(PKind::Drop, self.head.0 as f64 + rnd(-4.0, 4.0), self.head.1 as f64 - 6.0, rnd(-1.0, 1.0), -rnd(2.0, 4.0), 1.2, 0.0, 0);
    }

    pub fn spawn_bang(&mut self) {
        self.spawn(PKind::Bang, self.head.0 as f64 + 1.0, self.head.1 as f64 - 3.0, 0.0, -3.0, 0.9, 0.0, 0);
    }

    fn spawn_z(&mut self) {
        let back = -self.facing as f64;
        let size = if chance(0.5) { 1 } else { 0 };
        self.spawn(PKind::Z, self.head.0 as f64 + back * 2.0, self.head.1 as f64 - 2.0, back * 1.6, -3.2, 2.6, 0.0, size);
    }

    pub fn hearts(&mut self, n: i32) {
        for _ in 0..n {
            self.spawn(PKind::Heart, self.head.0 as f64 + rnd(-4.0, 4.0), self.head.1 as f64 - 2.0 - rnd(0.0, 3.0), rnd(-1.5, 1.5), rnd(-6.0, -3.5), rnd(1.0, 1.6), 0.0, 0);
        }
    }

    pub fn stars(&mut self, n: i32) {
        for _ in 0..n {
            self.spawn(PKind::Star, self.head.0 as f64 + rnd(-3.0, 3.0), self.head.1 as f64 - 2.0, rnd(-9.0, 9.0), rnd(-11.0, -4.0), rnd(0.6, 1.1), 18.0, 0);
        }
    }

    fn update_particles(&mut self, dt: f64) {
        if self.particles.is_empty() { return; }
        let floor_row = (self.chh - 2) as f64;
        for p in self.particles.iter_mut() {
            p.life -= dt;
            p.vy += p.gravity * dt;
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            if p.kind == PKind::Z || p.kind == PKind::Note { p.x += (p.life * 4.0).sin() * 0.05; }
            if p.y > floor_row {
                p.y = floor_row;
                p.vy = 0.0;
                p.vx *= 0.5;
            }
        }
        self.particles.retain(|p| !(p.life <= 0.0 || p.y < -6.0));
    }

    // MARK: Things people do

    pub fn celebrate(&mut self, w: &mut Env, text: &str) {
        self.celebrate_text = text.to_string();
        self.celebrate_until = w.t + 2.4;
        self.stars(8);
        w.play("chime");
        self.happiness = (self.happiness + 3.0).min(100.0);
    }

    pub fn petted(&mut self, w: &mut Env) {
        self.happiness = (self.happiness + 6.0).min(100.0);
        self.blush_until = w.t + 2.5;
        self.hearts(3);
        w.play(if self.family() == Family::Cat { "purr" } else { "chirp" });
        if self.family() == Family::Cat && chance(0.6) { self.say(&["PRRR"], 1.4, w); }
        if matches!(self.mode, Mode::Idle | Mode::Walk | Mode::Beg | Mode::Vocal) {
            self.set_mode(w, Mode::Petted);
            if self.family() != Family::Cat && chance(0.4) { self.say(&["♥"], 1.5, w); }
        }
    }

    pub fn admire(&mut self, w: &mut Env) {
        self.hearts(4);
        self.say(&[*rng::pick(&["CUTE!", "FANCY!", "SO STYLISH", "♥ ♥ ♥"])], 1.6, w);
        w.play("chirp");
        if matches!(self.mode, Mode::Idle | Mode::Walk) { self.set_mode(w, Mode::Petted); }
    }

    pub fn transformed(&mut self, w: &mut Env) {
        for _ in 0..6 {
            self.spawn(PKind::Puff, self.cx as f64 + rnd(-10.0, 10.0), (self.chh - 10) as f64 - rnd(0.0, 14.0), rnd(-4.0, 4.0), rnd(-4.0, 0.0), 0.7, 0.0, 0);
        }
        self.stars(6);
        self.say(&["TA-DA!"], 1.6, w);
        w.play("poof");
        if self.in_air && !self.is_bird() { self.in_air = false; self.start_falling(w); }
        if !self.in_air && self.is_bird() && self.fly_mode(w) { self.take_off(w); }
        if self.wall_mode(w) { self.p = self.perimeter_p(w, self.x, self.y); }
        if self.is_bird() && self.edge != 0 { self.edge = 0; self.start_falling(w); }
    }

    /// Follows the cursor around for a minute.
    pub fn come_here(&mut self, w: &mut Env) {
        w.last_play = w.t;
        self.follow_until = w.t + 60.0;
        self.forced_nap = false;
        if self.is_asleep() { self.set_mode(w, Mode::Waking); }
        else if !self.in_air && matches!(self.mode, Mode::Idle | Mode::Listening | Mode::Agenda) { self.set_mode(w, Mode::Walk); }
        self.say(&["COMING!"], 1.2, w);
    }

    /// Steers toward the cursor, stopping a little to the side of it so it never sits under the pointer and blocks clicks.
    fn follow(&mut self, w: &mut Env) {
        let m = w.mouse;
        let gap = 55.0 * w.scale() / 4.0;
        if self.in_air {
            if self.fly_goal != FlyGoal::Wander { return; }
            let side = if self.x < m.x { -1.0 } else { 1.0 };
            self.fly_target = Some(pt(m.x + side * gap * 1.3, (m.y - 20.0).max(w.floor_y(m.x, m.y) + 10.0)));
            self.next_fly_pick = w.t + 1.0;
            return;
        }
        if !matches!(self.mode, Mode::Idle | Mode::Walk) { return; }
        let raw = if self.ceiling_mode(w) { self.floor_target(w, m.x, m.y) } else if self.wall_mode(w) { self.perimeter_p(w, m.x, m.y) } else { m.x };
        let d = self.track_delta(w, raw);
        let mut target = raw - if d > 0.0 { 1.0 } else { -1.0 } * gap;
        if !self.wall_mode(w) { let (lo, hi) = w.x_range(self.margin(w)); target = clamp(target, lo, hi); }
        let far = self.track_delta(w, target).abs();
        if self.mode == Mode::Idle {
            if far > 40.0 { self.walk_target = target; self.set_mode(w, Mode::Walk); }
            else { self.face(w, m, 40.0); }
        } else {
            self.walk_target = target;
        }
        self.running = far > 220.0;
    }

    pub fn toggle_nap(&mut self, w: &mut Env) {
        if self.is_asleep() {
            self.forced_nap = false;
            self.set_mode(w, Mode::Waking);
        } else {
            self.forced_nap = true;
            self.begin(w, Mode::Yawning);
        }
    }

    pub fn show_agenda(&mut self, w: &mut Env, lines: &[&str], dur: Option<f64>, prop: Prop) {
        self.agenda_prop = prop;
        self.agenda_until = w.t + dur.unwrap_or_else(|| 5.0f64.max(1.6 * lines.len() as f64));
        if !lines.is_empty() { let d = self.agenda_until - w.t; self.say(lines, d, w); }
        if self.in_air { return; }
        self.begin(w, Mode::Agenda);
    }

    /// Water reminder: sits and holds up a glass.
    pub fn offer_water(&mut self, w: &mut Env, dur: f64) { self.show_agenda(w, &[], Some(dur), Prop::Glass); }

    /// You had some water: it has a sip too, happily.
    pub fn drink(&mut self, w: &mut Env) {
        self.drink_until = w.t + 1.6;
        self.show_agenda(w, &[], Some(2.6), Prop::Glass);
        self.hearts(3);
        for i in 0..3 { self.later_drops.push(w.t + 0.3 + i as f64 * 0.3); }
        self.happiness = (self.happiness + 4.0).min(100.0);
    }

    pub fn put_away(&mut self, w: &Env) { if self.mode == Mode::Agenda { self.agenda_until = w.t; } }

    // MARK: Mouse

    pub fn mouse_down(&mut self, w: &mut Env) {
        w.last_play = w.t;
        self.noticed_until = w.t + 0.6;
        let m = w.mouse;
        self.down_at = Some(m);
        self.dragging = false;
        self.grab = pt(m.x - self.x, m.y - self.y);
        self.samples = vec![(w.now, m)];
    }

    pub fn mouse_dragged(&mut self, w: &mut Env) {
        let Some(d) = self.down_at else { return };
        let m = w.mouse;
        let s = w.scale();
        // Fullscreen: it stays up on the top edge; dragging only slides it along
        if self.ceiling_mode(w) && !self.is_bird() && self.family() != Family::Bat && (self.edge == 2 || self.sliding) {
            if !self.dragging && (m.x - d.x).hypot(m.y - d.y) > 9.0 {
                self.dragging = true; self.sliding = true;
                self.release_food(w);
                self.set_mode(w, Mode::Idle); self.act = IdleAct::Stand; self.act_t = 0.0; self.act_dur = 2.0;
                w.close_menus = true;
            }
            if !self.sliding { return; }
            let (lo, hi) = self.top_span(w);
            self.p = clamp(self.perimeter_p(w, m.x, self.area(w).max_y()), lo, hi);
            self.place_on_perimeter(w);
            self.place(w);
            return;
        }
        if !self.dragging && (m.x - d.x).hypot(m.y - d.y) > 9.0 {     // a slightly wobbly click is still a click
            self.dragging = true;
            self.hop_y = 0.0; self.hop_v = 0.0; self.leap_v = 0.0; self.shake = 0; self.last_dir = 0;
            self.forced_nap = false;
            self.release_food(w);
            self.edge = 0;
            self.in_air = false;
            self.umbrella = false;
            self.grab = pt(0.0, if self.is_bird() { 14.0 } else { 22.0 } * s);
            self.set_mode(w, Mode::Held);
            w.play(if self.family() == Family::Cat { "mrrp" } else if self.is_bird() { "squawk" } else { "chirp" });
            self.say(&[if chance(0.5) { "HEY!" } else { "WHEE!" }], 1.2, w);
            w.close_menus = true;
        }
        if !self.dragging { return; }
        self.x = m.x - self.grab.x;
        self.y = m.y - self.grab.y;
        let n = w.now;
        if let Some(last) = self.samples.last() {
            let dx = m.x - last.1.x;
            let dir = if dx > 6.0 { 1 } else if dx < -6.0 { -1 } else { 0 };
            if dir != 0 && dir != self.last_dir {
                if self.last_dir != 0 { self.shake += 1; }
                self.last_dir = dir;
            }
        }
        self.samples.push((n, m));
        self.samples.retain(|smp| n - smp.0 <= 0.12);
        self.place(w);
    }

    /// Returns true when it was a plain click (not the end of a drag).
    pub fn mouse_up(&mut self, w: &mut Env) -> bool {
        let was_down = self.down_at.take().is_some();
        if self.sliding { self.sliding = false; self.dragging = false; return false; }
        if !self.dragging {
            if was_down { self.clicked(w); }
            return was_down;
        }
        self.dragging = false;
        let n = w.now;
        let recent: Vec<&(f64, Point)> = self.samples.iter().filter(|smp| n - smp.0 < 0.1).collect();
        match (recent.first(), recent.last()) {
            (Some(f), Some(l)) if l.0 - f.0 > 0.01 => {
                self.vx = clamp((l.1.x - f.1.x) / (l.0 - f.0), -2200.0, 2200.0);
                self.vy = clamp((l.1.y - f.1.y) / (l.0 - f.0), -2200.0, 2200.0);
            }
            _ => { self.vx = 0.0; self.vy = 0.0; }
        }
        self.apex_y = self.y;
        if self.is_bird() {
            self.in_air = true;
            self.fly_goal = if w.gravity && !w.fullscreen_app() { FlyGoal::Land } else { FlyGoal::Wander };
            self.after_land = None;
            self.set_mode(w, Mode::Fly);
        } else if !self.wall_mode(w) {
            self.umbrella = false;
            self.set_mode(w, Mode::Glide);
        } else {
            self.set_mode(w, Mode::Drift);
        }
        false
    }

    pub fn clicked(&mut self, w: &mut Env) {
        let t = w.t;
        self.clicks.push(t);
        self.clicks.retain(|c| t - c <= 2.5);
        let (word, sound) = self.species.vocal();
        match self.mode {
            Mode::Sleeping | Mode::Yawning | Mode::Catnap => {
                self.forced_nap = false;
                self.set_mode(w, Mode::Waking);
                return;
            }
            Mode::Held => return,
            Mode::Glide | Mode::Drift => { self.say(&["WHEE!"], 0.9, w); return; }
            Mode::Eating => { self.hearts(1); self.say(&["NOM!"], 0.8, w); return; }
            Mode::Landing | Mode::Dizzy | Mode::Waking => { self.spawn_bang(); w.play(sound); return; }
            _ => {}
        }
        let shout = format!("{word}!");
        if self.in_air {                                   // flying: answer without dropping out of the sky
            self.say(&[&shout], 0.9, w);
            w.play(sound);
            return;
        }
        if self.clicks.len() >= 5 {
            self.clicks.clear();
            self.set_mode(w, Mode::Angry);
            let hiss = self.family() == Family::Cat;
            let yell = format!("{word}!!");
            self.say(&[if hiss { "HISS!" } else { &yell }], 1.4, w);
            w.play(if hiss { "hiss" } else if self.is_bird() { "honk2" } else { "woof" });
            self.happiness = (self.happiness - 3.0).max(0.0);
            return;
        }
        self.set_mode(w, Mode::Vocal);
        self.mode_t = 0.0;
        self.say(&[&shout], 0.9, w);
        w.play(sound);
        self.happiness = (self.happiness + 1.0).min(100.0);
    }

    /// Detects petting (stroking with the cursor) and whether the cursor is over the pet.
    fn update_mouse(&mut self, w: &mut Env, dt: f64) {
        let m = w.mouse;
        let moved = (m.x - self.last_mouse.x).hypot(m.y - self.last_mouse.y);
        if moved > 1.5 { self.cursor_moved_at = w.t; }
        self.update_hover(w);
        self.pet_cooldown -= dt;
        if self.mouse_inside && !self.dragging && !w.buttons_down {
            self.stroke_dist += moved;
            self.stroke_idle = 0.0;
            if self.stroke_dist > 280.0 * w.scale() / 4.0 && self.pet_cooldown <= 0.0 {
                self.stroke_dist = 0.0;
                self.pet_cooldown = 1.5;
                self.petted(w);
            }
        } else {
            self.stroke_idle += dt;
            if self.stroke_idle > 0.7 { self.stroke_dist = 0.0; }
        }
        self.last_mouse = m;
    }

    /// Is the cursor over the pet? (with a little extra margin once inside, so the edge never flickers)
    pub fn update_hover(&mut self, w: &Env) {
        let Some(r) = self.hit_rect_screen(w) else { return };
        let g = if self.mouse_inside { -8.0 } else { -2.0 };
        self.mouse_inside = r.inset(g, g).contains(w.mouse);
    }

    // MARK: Drawing

    pub fn make_pose(&self, w: &Env) -> Pose {
        let t = w.t;
        let mut p = Pose::default();
        let blink = t < self.blink_until;
        let flap_fast = (t / 0.09) as i64 % 2 == 0;
        let fam = self.family();
        let bird = self.is_bird();
        let wag = fam == Family::Dog && (matches!(self.mode, Mode::Petted | Mode::Vocal | Mode::Ball | Mode::Eating | Mode::Landing)
            || (self.mode == Mode::Idle && self.happiness > 70.0 && matches!(self.act, IdleAct::Stand | IdleAct::Sit)));
        p.outfit = self.outfit;
        p.phones = w.music_playing;
        p.eyes = if blink { Eyes::Closed } else { Eyes::Open };
        p.tail = t * if wag { 14.0 } else { 1.6 };
        p.bob = if bird { if t % 1.8 < 0.9 { 0 } else { 1 } } else { 0 };
        if fam == Family::Dog && !blink && (wag || self.mode == Mode::Walk) { p.mouth = Mouth::Tongue; }
        if self.moving {
            p.stance = Stance::Walk;
            p.phase = self.walk_t * if self.running { 16.0 } else { 9.0 };
            if bird { p.bob = if (p.phase * 2.0).sin() > 0.3 { 1 } else { 0 }; p.head_dx = if (p.phase * 2.0).sin() > 0.0 { 1 } else { 0 }; }
        }
        if self.in_air {
            p.stance = Stance::Fly;
            p.arm = [Arm::Raised, Arm::Rest, Arm::Down, Arm::Rest][(self.flap_t / 0.08) as usize % 4];
            p.bob = 0; p.head_dx = 0;
        }
        let goose = self.species == Species::Goose;
        let mode_t = self.mode_t;
        match self.mode {
            Mode::Idle => { if !self.in_air { self.idle_pose(&mut p, w); } }
            Mode::Walk | Mode::Fly => {}
            Mode::Typing => {
                let tapping = t < w.tap_until;
                p.stance = Stance::Sit; p.prop = Prop::Laptop; p.bob = 0; p.tail_up = false;
                p.arm = if tapping { Arm::Tap } else { Arm::Forward };
                if goose { p.head_dx = 2; p.head_dy = 7 + if tapping { 1 } else { 0 }; }
                else { p.head_dy = if tapping { 1 } else { 0 }; if fam == Family::Dog { p.mouth = Mouth::Closed; } }
                if t < self.celebrate_until {
                    p.arm = if bird { if flap_fast { Arm::Raised } else { Arm::Rest } } else { Arm::Raised };
                    p.eyes = Eyes::Happy; p.mouth = Mouth::Open; p.head_dy = 0;
                }
            }
            Mode::Watching => {
                if !self.moving {
                    p.stance = Stance::Sit; p.prop = Prop::Popcorn; p.bob = 0; p.tail_up = false;
                    p.arm = if bird { Arm::Forward } else { Arm::Rest };
                    if fam == Family::Dog { p.mouth = Mouth::Closed; }
                    let cyc = self.pop_t % 3.4;
                    if cyc < 2.05 {
                        p.eyes = if blink { Eyes::Closed } else { Eyes::Up };
                        if goose { p.head_dy = -1; }
                        if cyc < 1.0 { p.mouth = if (cyc * 8.0) as i64 % 2 == 0 { Mouth::Open } else { Mouth::Closed }; }
                    } else if cyc < 2.45 {
                        if goose { p.head_dx = 4; p.head_dy = 13; p.eyes = Eyes::Closed; } else { p.arm = Arm::Scoop; }
                    } else {
                        p.eyes = Eyes::Up;
                        if !bird { p.arm = Arm::ToMouth; } else if goose { p.head_dy = -1; }
                        p.mouth = if (cyc * 8.0) as i64 % 2 == 0 { Mouth::Open } else { Mouth::Closed };
                    }
                }
            }
            Mode::Listening => {
                if !self.moving {
                    let beat = (t / 0.42) as i64 % 2;
                    let bar = (t / 1.68) as i64 % 4;
                    p.eyes = if bar % 2 == 0 { Eyes::Happy } else if blink { Eyes::Closed } else { Eyes::Open };
                    if bird {
                        p.stance = if bar == 1 { Stance::Walk } else { Stance::Stand };
                        p.phase = if beat == 0 { 1.2 } else { 4.3 };
                        p.bob = beat as i32; p.head_dx = beat as i32;
                        if bar == 3 { p.arm = if flap_fast { Arm::Raised } else { Arm::Rest }; }
                    } else {
                        p.stance = Stance::Sit; p.tail_up = true; p.tail = t * 4.0;
                        p.head_dy = beat as i32;
                        if bar == 3 { p.arm = if beat == 0 { Arm::Raised } else { Arm::Rest }; }
                    }
                }
            }
            Mode::Agenda => {
                p.stance = Stance::Sit; p.prop = self.agenda_prop; p.arm = if bird { Arm::Forward } else { Arm::Hold }; p.tail_up = false; p.bob = 0;
                if fam == Family::Dog { p.mouth = Mouth::Closed; }
                if self.agenda_prop == Prop::Glass && t < self.drink_until {
                    p.arm = if bird { Arm::Forward } else { Arm::ToMouth }; p.eyes = Eyes::Happy; p.head_dy = if bird { 1 } else { 0 };
                } else if self.agenda_prop == Prop::Glass { p.eyes = Eyes::Open; p.tail = t * 3.0; p.tail_up = true; }
            }
            Mode::Yawning => {
                if bird {
                    if mode_t < 1.2 { p.mouth = Mouth::Open; p.eyes = Eyes::Closed; p.head_dy = -2; p.arm = Arm::Raised; }
                    else {
                        p.stance = Stance::Sit; p.bob = 0;
                        p.eyes = if (mode_t * 5.0) as i64 % 2 == 0 { Eyes::Closed } else { Eyes::Half };
                        self.bird_sleep_head(&mut p, 1.0f64.min((mode_t - 1.2) / 1.2));
                    }
                } else if mode_t < 1.2 { p.stance = Stance::Sit; p.mouth = Mouth::Open; p.eyes = Eyes::Closed; p.tail_up = false; }
                else if mode_t < 2.0 { p.stance = Stance::Lie; p.eyes = if (mode_t * 5.0) as i64 % 2 == 0 { Eyes::Closed } else { Eyes::Half }; }
                else { p.stance = Stance::Curl; p.eyes = Eyes::Closed; }
                p.nightcap = w.is_night && mode_t > 2.0;
            }
            Mode::Sleeping | Mode::Catnap => {
                p.eyes = Eyes::Closed;
                p.bob = if t % 3.2 < 1.6 { 0 } else { 1 };
                if bird { p.stance = Stance::Sit; self.bird_sleep_head(&mut p, 1.0); } else { p.stance = Stance::Curl; }
                p.nightcap = self.mode == Mode::Sleeping && w.is_night;
                p.blush = t < self.blush_until;
            }
            Mode::Waking => {
                let blinky = (mode_t > 1.9 && mode_t < 2.0) || (mode_t > 2.15 && mode_t < 2.25);
                if bird {
                    if mode_t < 0.35 {
                        p.stance = Stance::Sit; self.bird_sleep_head(&mut p, 1.0); p.bob = -1;
                        p.eyes = if mode_t > 0.15 { Eyes::Wide } else { Eyes::Closed }; p.nightcap = w.is_night;
                    }
                    else if mode_t < 1.0 { p.stance = Stance::Sit; p.eyes = Eyes::Wide; p.bob = 0; p.arm = if flap_fast { Arm::Raised } else { Arm::Rest }; }
                    else if mode_t < 1.8 { p.head_dy = -3; p.mouth = Mouth::Open; p.eyes = Eyes::Closed; p.arm = Arm::Raised; p.bob = 0; }
                    else { p.eyes = if blinky { Eyes::Closed } else { Eyes::Open }; }
                } else if mode_t < 0.35 {
                    p.stance = Stance::Curl; p.bob = -1; p.eyes = if mode_t > 0.15 { Eyes::Wide } else { Eyes::Closed }; p.nightcap = w.is_night;
                }
                else if mode_t < 1.0 { p.stance = Stance::Sit; p.eyes = Eyes::Wide; p.tail_up = true; }
                else if mode_t < 1.8 { p.stance = Stance::Stretch; p.eyes = Eyes::Closed; p.mouth = Mouth::Open; }
                else { p.eyes = if blinky { Eyes::Closed } else { Eyes::Open }; }
            }
            Mode::Eating => {
                if self.moving { p.eyes = Eyes::Wide; }
                else {
                    let up_in_air = self.food.and_then(|id| w.items.iter().find(|i| i.id == id))
                        .map(|f| w.gravity && !self.wall_mode(w) && (!f.on_ground || f.held)).unwrap_or(false);
                    if up_in_air { p.eyes = Eyes::Up; if goose { p.head_dy = -2; } }
                    else {
                        let k = t - self.peck_start;
                        let chew = if k < 0.5 && (k * 12.0) as i64 % 2 == 0 { Mouth::Open } else { Mouth::Closed };
                        if goose {
                            if k < 0.22 { p.head_dx = 4; p.head_dy = 24; p.eyes = Eyes::Closed; }
                            else { p.head_dx = 3; p.head_dy = 12; p.eyes = Eyes::Happy; p.mouth = chew; }
                        } else {
                            p.stance = Stance::Eat; p.eyes = Eyes::Happy; p.head_dy = if k < 0.22 { 1 } else { 0 }; p.mouth = chew;
                        }
                    }
                }
            }
            Mode::Refusing => {
                p.eyes = Eyes::Closed;
                if !bird { p.stance = Stance::Sit; p.tail_up = false; p.mouth = Mouth::Closed; } else if goose { p.head_dy = -1; }
            }
            Mode::Ball => {
                if t < self.kick_until {
                    if !bird { p.stance = Stance::Leap; p.eyes = Eyes::Wide; }
                    else if !self.in_air { p.head_dx = 3; p.head_dy = if goose { 5 } else { 2 }; p.mouth = Mouth::Open; p.arm = Arm::Raised; p.eyes = Eyes::Wide; }
                } else if !self.moving {
                    p.eyes = Eyes::Wide;
                }
            }
            Mode::Tired => {
                p.stance = Stance::Sit; p.eyes = Eyes::Closed; p.bob = 0; p.tail_up = false;
                p.mouth = if (t / 0.22) as i64 % 2 == 0 { if fam == Family::Dog { Mouth::Tongue } else { Mouth::Open } } else { Mouth::Closed };
            }
            Mode::Butterfly => {
                p.eyes = Eyes::Up;
                if !bird { p.tail = t * 4.0; }
                else if !self.in_air { if goose { p.head_dy = -3; } if self.hop_y > 0.0 { p.arm = if flap_fast { Arm::Raised } else { Arm::Rest }; } }
            }
            Mode::Vocal => {
                if bird {
                    p.mouth = if (mode_t / 0.15) as i64 % 2 == 0 { Mouth::Open } else { Mouth::Closed };
                    if !self.in_air { p.arm = Arm::Raised; p.head_dx = if goose { 2 } else { 1 }; p.eyes = Eyes::Wide; }
                } else {
                    p.stance = if self.moving { Stance::Walk } else { Stance::Sit };
                    p.mouth = if mode_t < 0.6 { Mouth::Open } else { Mouth::Closed }; p.eyes = Eyes::Happy; p.tail_up = true;
                }
            }
            Mode::Angry => {
                if !bird {
                    if mode_t < 1.3 { p.stance = Stance::Crouch; p.ears_flat = true; p.mouth = Mouth::Open; p.eyes = Eyes::Angry; }
                    else { p.ears_flat = true; p.eyes = Eyes::Angry; p.tail_up = false; p.mouth = Mouth::Closed; }
                } else {
                    p.eyes = Eyes::Angry; p.mouth = if (t / 0.1) as i64 % 2 == 0 { Mouth::Open } else { Mouth::Closed };
                    if !self.in_air {
                        p.head_dx = if goose { 6 } else { 2 }; p.head_dy = if goose { 8 } else { 2 };
                        p.arm = if flap_fast { Arm::Raised } else { Arm::Rest };
                    }
                }
            }
            Mode::Petted => {
                p.eyes = Eyes::Happy; p.blush = true;
                if bird {
                    p.head_dy = 1; p.bob = (t / 0.2) as i32 % 2; p.arm = if (t / 0.25) as i64 % 2 == 0 { Arm::Raised } else { Arm::Rest };
                } else {
                    p.stance = if fam == Family::Dog { Stance::Upright } else { Stance::Sit }; p.tail_up = true; p.head_dx = (t / 0.3) as i32 % 2;
                }
            }
            Mode::Beg => {
                p.eyes = Eyes::Sad;
                if bird {
                    if goose { p.head_dy = 3; p.head_dx = 1; }
                    if self.fullness < 10.0 { p.stance = Stance::Sit; p.bob = 0; }
                } else {
                    p.stance = if fam == Family::Dog { Stance::Upright } else { Stance::Sit }; p.tail_up = false;
                    p.mouth = if mode_t < 0.8 { Mouth::Open } else { Mouth::Closed };
                }
            }
            Mode::Held => {
                p.stance = Stance::Held; p.bob = 0; p.head_dx = 0;
                p.phase = t * 6.0;
                if bird {
                    p.arm = if flap_fast { Arm::Raised } else { Arm::Rest }; p.eyes = Eyes::Wide;
                    p.mouth = if (t / 0.4) as i64 % 3 == 0 { Mouth::Open } else { Mouth::Closed };
                } else {
                    p.eyes = if mode_t < 0.6 { Eyes::Wide } else if (t / 1.5) as i64 % 3 == 0 { Eyes::Closed } else { Eyes::Happy };
                    p.mouth = if mode_t < 0.6 { Mouth::Open } else if fam == Family::Dog { Mouth::Tongue } else { Mouth::Closed };
                }
            }
            Mode::Glide => {
                p.stance = if self.umbrella { Stance::Umbrella } else { Stance::Held }; p.bob = 0;
                p.phase = t * if self.umbrella { 2.0 } else { 10.0 };
                p.eyes = if self.umbrella { Eyes::Happy } else { Eyes::Wide };
                if fam == Family::Dog && self.umbrella { p.mouth = Mouth::Tongue; }
            }
            Mode::Drift => { p.stance = Stance::Leap; p.bob = 0; p.eyes = Eyes::Wide; }
            Mode::Landing => { p.stance = Stance::Squash; p.eyes = Eyes::Closed; p.bob = 0; }
            Mode::Dizzy => {
                p.eyes = Eyes::Dizzy; p.bob = 0; p.head_dx = (t / 0.25) as i32 % 3 - 1;
                if !bird { p.stance = Stance::Sit; p.tail_up = false; p.head_dx = 0; }
            }
            Mode::Zoomies => {
                p.eyes = Eyes::Wide; p.tail_up = false;
                if fam == Family::Dog { p.mouth = Mouth::Tongue; }
            }
            Mode::Hunt => match self.hunt_phase {
                0 => { p.stance = Stance::Crouch; p.eyes = Eyes::Wide; }
                1 => { p.stance = Stance::Crouch; p.eyes = Eyes::Wide; p.wiggle = if (t / 0.08) as i64 % 2 == 0 { 1 } else { -1 }; }
                2 => { p.stance = if self.hop_y > 0.0 { Stance::Leap } else { Stance::Crouch }; p.eyes = Eyes::Wide; }
                _ => { p.stance = Stance::Sit; p.tail_up = true; }
            },
        }
        if matches!(self.mode, Mode::Idle | Mode::Walk) && self.fullness < 15.0 && p.eyes == Eyes::Open { p.eyes = Eyes::Sad; }
        p
    }

    /// Birds tuck their head down to sleep (k = 0...1).
    fn bird_sleep_head(&self, p: &mut Pose, k: f64) {
        if self.species == Species::Goose {
            p.head_dx = iround(-k); p.head_dy = 3 + (9.0 * k) as i32;
        } else {
            p.head_dx = iround(-2.0 * k); p.head_dy = (3.0 * k) as i32;
        }
    }

    fn idle_pose(&self, p: &mut Pose, w: &Env) {
        let t = w.t;
        let act_t = self.act_t;
        let blink = t < self.blink_until;
        let goose = self.species == Species::Goose;
        if self.family() == Family::Bird {
            match self.act {
                IdleAct::Sit => { p.stance = Stance::Sit; p.bob = 0; }
                IdleAct::Preen => {
                    if goose { p.head_dx = -2; p.head_dy = 11 + (t / 0.18) as i32 % 2; } else { p.head_dx = -3; p.head_dy = 2 + (t / 0.18) as i32 % 2; }
                    p.eyes = Eyes::Closed;
                }
                IdleAct::Peck => {
                    let down = act_t % 0.7 < 0.2;
                    if goose { p.head_dx = 4; p.head_dy = if down { 24 } else { 12 }; } else { p.head_dx = 3; p.head_dy = if down { 9 } else { 4 }; }
                }
                IdleAct::Vocal => {
                    p.mouth = if (act_t / 0.15) as i64 % 2 == 0 { Mouth::Open } else { Mouth::Closed }; p.arm = Arm::Raised; p.head_dx = 1; p.head_dy = -1;
                }
                IdleAct::Flap => p.arm = if (act_t / 0.12) as i64 % 2 == 0 { Arm::Raised } else { Arm::Rest },
                IdleAct::Yawn => {
                    p.mouth = if act_t > 0.2 && act_t < 1.1 { Mouth::Open } else { Mouth::Closed }; p.eyes = Eyes::Closed; p.head_dy = -2;
                }
                IdleAct::Gaze => { p.eyes = if blink { Eyes::Closed } else { Eyes::Up }; if goose { p.head_dy = -2; } }
                IdleAct::Hop => {
                    if self.hop_y > 0.0 { p.arm = if (t / 0.08) as i64 % 2 == 0 { Arm::Raised } else { Arm::Rest }; p.stance = Stance::Held; p.phase = t * 6.0; }
                }
                _ => {}
            }
        } else {
            match self.act {
                IdleAct::Sit => { p.stance = Stance::Sit; p.tail_up = false; }
                IdleAct::Lie => {
                    p.stance = Stance::Lie;
                    p.eyes = if act_t % 4.0 < 1.2 { Eyes::Closed } else if blink { Eyes::Closed } else { Eyes::Half };   // the slow blink
                    if self.family() == Family::Dog { p.mouth = Mouth::Closed; }
                }
                IdleAct::Groom => {
                    p.stance = Stance::Sit; p.tail_up = false; p.eyes = Eyes::Closed;
                    let k = (act_t / 0.35) as i64 % 2;
                    p.arm = if k == 0 { Arm::Lick } else { Arm::ToMouth };
                    p.mouth = if k == 0 { Mouth::Tongue } else { Mouth::Closed };
                }
                IdleAct::Stretch => {
                    p.stance = Stance::Stretch; p.eyes = Eyes::Closed;
                    p.mouth = if act_t > 0.6 && act_t < 1.6 { Mouth::Open } else { Mouth::Closed };
                }
                IdleAct::Yawn => {
                    p.stance = Stance::Sit; p.mouth = if act_t > 0.2 && act_t < 1.1 { Mouth::Open } else { Mouth::Closed };
                    p.eyes = Eyes::Closed; p.tail_up = false;
                }
                IdleAct::Gaze => { p.stance = Stance::Sit; p.eyes = if blink { Eyes::Closed } else { Eyes::Up }; p.tail_up = false; }
                IdleAct::Vocal => { p.stance = Stance::Sit; p.mouth = if act_t < 0.6 { Mouth::Open } else { Mouth::Closed }; p.tail_up = true; }
                IdleAct::Hop => { if self.hop_y > 0.0 { p.stance = Stance::Leap; p.eyes = Eyes::Happy; } }
                IdleAct::Beg => p.stance = Stance::Upright,
                _ => {}
            }
        }
    }

    pub fn render_canvas(&mut self, w: &Env) {
        let t = w.t;
        let mut pose = self.make_pose(w);
        // a quick in-between frame when sitting down or getting up, so it doesn't snap
        let low = |s: Stance| matches!(s, Stance::Sit | Stance::Lie | Stance::Curl | Stance::Upright);
        let high = |s: Stance| matches!(s, Stance::Stand | Stance::Walk | Stance::Eat);
        if pose.stance != self.last_stance {
            if (low(pose.stance) && high(self.last_stance)) || (high(pose.stance) && low(self.last_stance)) {
                self.transition_until = t + 0.14;
            }
            self.last_stance = pose.stance;
        }
        if t < self.transition_until && !self.is_bird() && self.family() != Family::Bat { pose.stance = Stance::Crouch; }
        if self.family() == Family::Bat { pose.phase = t * 13.0; }            // wing beats
        let mut c = Canvas::new(self.cw, self.chh);
        let a = draw_pet(&mut c, self.species, &pose, self.cx);
        if self.facing < 0 { c.mirror(self.cx); }
        self.head = (if self.facing < 0 { 2 * self.cx - a.head_x } else { a.head_x }, a.head_top);
        self.hit_cells = c.bounds();
        if self.mode == Mode::Dizzy {
            for i in 0..3 {
                let ang = t * 5.0 + i as f64 * 2.1;
                c.sprite(self.head.0 + iround(ang.cos() * 5.0) - 1, self.head.1 - 4 + iround(ang.sin() * 1.5), &SPR_STAR, &[(b'X', crate::art::Col::Star)]);
            }
        }
        for pt in &self.particles {
            if pt.life < 0.25 && (pt.life * 30.0) as i64 % 2 == 0 { continue; }
            draw_particle(&mut c, pt);
        }
        c.outline();
        self.canvas = c;
    }

    pub fn current_bubble(&self, w: &Env) -> Option<Vec<String>> {
        if w.t < self.celebrate_until { return Some(vec![self.celebrate_text.clone()]); }
        if w.t < self.bubble_until && !self.bubble_lines.is_empty() { return Some(self.bubble_lines.clone()); }
        None
    }

    /// Where speech and cards come from, in screen space so they're never sideways or inside the pet:
    /// just above it, or just below it when it hangs from the top (or a wall leaves no room above).
    pub fn bubble_tip(&self, w: &Env) -> (Point, bool) {
        let h = self.cell_to_screen(w, self.head.0 as f64 + 0.5, self.head.1 as f64);
        let Some(r) = self.hit_rect_screen(w) else { return (h, false) };
        let x = clamp(h.x, r.min_x() + 6.0, (r.min_x() + 6.0).max(r.max_x() - 6.0));
        let room_above = self.area(w).max_y() - r.max_y() > 70.0;
        if self.edge == 2 || (self.edge != 0 && !room_above) { return (pt(x, r.min_y() - 2.0), true); }
        (pt(x, r.max_y() + 2.0), false)
    }

    /// The angle (in quarter turns, clockwise on screen) the canvas is drawn at for the current edge.
    pub fn quarter_turns(&self) -> i32 { [0, 3, 2, 1][self.edge] }

    /// A still portrait, for the panel and the tray icon.
    pub fn portrait_canvas(sp: Species, o: Outfit) -> Canvas {
        let mut c = Canvas::new(CANVAS_W, CANVAS_H);
        let mut pose = Pose { outfit: o, ..Pose::default() };
        if !sp.is_bird() { pose.stance = Stance::Sit; pose.tail_up = false; }
        if sp.family() == Family::Dog { pose.mouth = Mouth::Tongue; }
        draw_pet(&mut c, sp, &pose, CANVAS_W / 2);
        c.outline();
        c
    }
}

/// Just the pet's face (and whatever it's wearing on its head), like the Mac panel's pet picker.
pub fn face_canvas(sp: Species, o: Outfit, room_for_hat: bool) -> Canvas {
    let mut c = Canvas::new(CANVAS_W, CANVAS_H);
    let mut p = Pose { outfit: o, ..Pose::default() };
    if !sp.is_bird() { p.stance = Stance::Sit; p.tail_up = false; }
    if sp.family() == Family::Dog { p.mouth = Mouth::Tongue; }
    let a = draw_pet(&mut c, sp, &p, CANVAS_W / 2);
    c.outline();
    let up = if room_for_hat || sp == Species::Bat { 8 } else { 4 };       // the bat's ears stick up
    if a.profile { c.cropped(a.head_x - 4, a.head_top - up, a.head_x + 8, a.head_top + 7) }
    else { c.cropped(a.head_x - 7, a.head_top - up, a.head_x + 7, a.head_top + 9) }
}

/// A rectangle of the screen, for platforms: the pet's window in screen points.
pub fn window_rect(pet: &Pet, w: &Env) -> Rect { Rect::new(pet.origin.x, pet.origin.y, pet.side(w), pet.side(w)) }
