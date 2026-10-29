// Points and rectangles in screen points, y up from the bottom of the main screen (like the Mac app),
// so the brain's math stays exactly as it is there. Platforms convert at the edge.

#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub struct Point { pub x: f64, pub y: f64 }

pub const fn pt(x: f64, y: f64) -> Point { Point { x, y } }

impl Point {
    pub fn dist(self, o: Point) -> f64 { (self.x - o.x).hypot(self.y - o.y) }
}

#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub struct Rect { pub x: f64, pub y: f64, pub w: f64, pub h: f64 }

impl Rect {
    pub const fn new(x: f64, y: f64, w: f64, h: f64) -> Rect { Rect { x, y, w, h } }
    pub fn min_x(&self) -> f64 { self.x }
    pub fn min_y(&self) -> f64 { self.y }
    pub fn max_x(&self) -> f64 { self.x + self.w }
    pub fn max_y(&self) -> f64 { self.y + self.h }
    pub fn mid_x(&self) -> f64 { self.x + self.w / 2.0 }
    pub fn mid_y(&self) -> f64 { self.y + self.h / 2.0 }
    pub fn width(&self) -> f64 { self.w }
    pub fn height(&self) -> f64 { self.h }
    pub fn inset(&self, dx: f64, dy: f64) -> Rect { Rect::new(self.x + dx, self.y + dy, self.w - 2.0 * dx, self.h - 2.0 * dy) }
    pub fn contains(&self, p: Point) -> bool { p.x >= self.x && p.x < self.max_x() && p.y >= self.y && p.y < self.max_y() }
    pub fn union(&self, o: &Rect) -> Rect {
        let x0 = self.x.min(o.x);
        let y0 = self.y.min(o.y);
        Rect::new(x0, y0, self.max_x().max(o.max_x()) - x0, self.max_y().max(o.max_y()) - y0)
    }
}

pub fn clamp(v: f64, lo: f64, hi: f64) -> f64 { v.max(lo).min(hi) }
