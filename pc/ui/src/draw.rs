// Drawing for the menu and cards: anti-aliased rounded shapes, soft shadows, text and crisp pixel pictures.

use fontdue::{Font, FontSettings, Metrics};
use pocket_pet_core::art::{Canvas, Palette};
use pocket_pet_core::image::{over, with_coverage, Image};
use std::collections::HashMap;

pub struct Fonts {
    regular: Font,
    bold: Font,
    cache: HashMap<(bool, char, u32), (Metrics, Vec<u8>)>,
}

impl Fonts {
    pub fn load(regular: &[u8], bold: &[u8]) -> Option<Fonts> {
        let regular = Font::from_bytes(regular, FontSettings::default()).ok()?;
        let bold = Font::from_bytes(bold, FontSettings::default()).ok()?;
        Some(Fonts { regular, bold, cache: HashMap::new() })
    }

    fn font(&self, bold: bool) -> &Font { if bold { &self.bold } else { &self.regular } }

    fn glyph(&mut self, bold: bool, ch: char, px: f32) -> &(Metrics, Vec<u8>) {
        let key = (bold, ch, px.to_bits());
        if !self.cache.contains_key(&key) {
            if self.cache.len() > 4000 { self.cache.clear(); }
            let g = self.font(bold).rasterize(ch, px);
            self.cache.insert(key, g);
        }
        &self.cache[&key]
    }

    pub fn ascent(&self, px: f32, bold: bool) -> f32 {
        self.font(bold).horizontal_line_metrics(px).map(|m| m.ascent).unwrap_or(px * 0.8)
    }

    pub fn width(&mut self, s: &str, px: f32, bold: bool) -> f32 {
        let mut w = 0.0;
        let mut prev: Option<char> = None;
        for ch in s.chars() {
            if let Some(p) = prev { w += self.font(bold).horizontal_kern(p, ch, px).unwrap_or(0.0); }
            w += self.glyph(bold, ch, px).0.advance_width;
            prev = Some(ch);
        }
        w
    }

    /// Draws one line with its top at `y`; returns its width.
    pub fn draw(&mut self, img: &mut Image, s: &str, x: f32, y: f32, px: f32, bold: bool, color: u32) -> f32 {
        let base = (y + self.ascent(px, bold)).round() as i32;
        let mut pen = x;
        let mut prev: Option<char> = None;
        for ch in s.chars() {
            if let Some(p) = prev { pen += self.font(bold).horizontal_kern(p, ch, px).unwrap_or(0.0); }
            let (m, cov) = self.glyph(bold, ch, px).clone();
            let gx = pen.round() as i32 + m.xmin;
            let gy = base - (m.height as i32 + m.ymin);
            for row in 0..m.height {
                for col in 0..m.width {
                    let c = cov[row * m.width + col];
                    if c == 0 { continue; }
                    img.blend(gx + col as i32, gy + row as i32, with_coverage(color, c as f32 / 255.0));
                }
            }
            pen += m.advance_width;
            prev = Some(ch);
        }
        pen - x
    }

    /// Shortens a line with an ellipsis until it fits.
    pub fn fit(&mut self, s: &str, px: f32, bold: bool, max: f32) -> String {
        if self.width(s, px, bold) <= max { return s.to_string(); }
        let mut t: Vec<char> = s.chars().collect();
        while !t.is_empty() {
            t.pop();
            let cand: String = t.iter().collect::<String>() + "…";
            if self.width(&cand, px, bold) <= max { return cand; }
        }
        String::new()
    }

    /// Breaks text into lines no wider than `max`.
    pub fn wrap(&mut self, s: &str, px: f32, bold: bool, max: f32) -> Vec<String> {
        let mut lines = Vec::new();
        let mut cur = String::new();
        for word in s.split(' ') {
            let cand = if cur.is_empty() { word.to_string() } else { format!("{cur} {word}") };
            if self.width(&cand, px, bold) <= max || cur.is_empty() { cur = cand; } else { lines.push(cur); cur = word.to_string(); }
        }
        if !cur.is_empty() { lines.push(cur); }
        lines
    }
}

/// Coverage of a pixel by a rounded rectangle (signed distance, one pixel of soft edge).
fn rrect_cov(px: f32, py: f32, x: f32, y: f32, w: f32, h: f32, r: f32) -> f32 {
    let cx = x + w / 2.0;
    let cy = y + h / 2.0;
    let r = r.min(w / 2.0).min(h / 2.0);
    let qx = (px - cx).abs() - (w / 2.0 - r);
    let qy = (py - cy).abs() - (h / 2.0 - r);
    let outside = qx.max(0.0).hypot(qy.max(0.0));
    let d = outside + qx.max(qy).min(0.0) - r;
    (0.5 - d).clamp(0.0, 1.0)
}

/// Fills a rounded rectangle with a straight 0xAARRGGBB color.
pub fn rrect(img: &mut Image, x: f32, y: f32, w: f32, h: f32, r: f32, color: u32) {
    let (x0, y0) = ((x.floor() as i32).max(0), (y.floor() as i32).max(0));
    let (x1, y1) = (((x + w).ceil() as i32).min(img.w), ((y + h).ceil() as i32).min(img.h));
    for yy in y0..y1 {
        for xx in x0..x1 {
            let c = rrect_cov(xx as f32 + 0.5, yy as f32 + 0.5, x, y, w, h, r);
            if c > 0.0 { img.blend(xx, yy, with_coverage(color, c)); }
        }
    }
}

/// A rounded outline `t` pixels wide, inside the rectangle.
pub fn rrect_stroke(img: &mut Image, x: f32, y: f32, w: f32, h: f32, r: f32, t: f32, color: u32) {
    let (x0, y0) = ((x.floor() as i32).max(0), (y.floor() as i32).max(0));
    let (x1, y1) = (((x + w).ceil() as i32).min(img.w), ((y + h).ceil() as i32).min(img.h));
    for yy in y0..y1 {
        for xx in x0..x1 {
            let (px, py) = (xx as f32 + 0.5, yy as f32 + 0.5);
            let c = rrect_cov(px, py, x, y, w, h, r) - rrect_cov(px, py, x + t, y + t, w - 2.0 * t, h - 2.0 * t, (r - t).max(0.0));
            if c > 0.0 { img.blend(xx, yy, with_coverage(color, c)); }
        }
    }
}

/// A soft shadow under a rounded rectangle: its shape, blurred.
pub fn shadow(img: &mut Image, x: f32, y: f32, w: f32, h: f32, r: f32, blur: i32, color: u32) {
    let (iw, ih) = (img.w as usize, img.h as usize);
    let mut a = vec![0f32; iw * ih];
    for yy in 0..ih {
        for xx in 0..iw { a[yy * iw + xx] = rrect_cov(xx as f32 + 0.5, yy as f32 + 0.5, x, y, w, h, r); }
    }
    // three box blurs come close to a gaussian
    let rad = (blur / 3).max(1) as usize;
    let mut tmp = vec![0f32; iw * ih];
    for _ in 0..3 {
        for yy in 0..ih {
            let mut acc = 0.0;
            for xx in 0..(iw + rad) {
                if xx < iw { acc += a[yy * iw + xx]; }
                if xx >= 2 * rad + 1 { acc -= a[yy * iw + xx - 2 * rad - 1]; }
                if xx >= rad && xx - rad < iw { tmp[yy * iw + xx - rad] = acc / (2 * rad + 1) as f32; }
            }
        }
        for xx in 0..iw {
            let mut acc = 0.0;
            for yy in 0..(ih + rad) {
                if yy < ih { acc += tmp[yy * iw + xx]; }
                if yy >= 2 * rad + 1 { acc -= tmp[(yy - 2 * rad - 1) * iw + xx]; }
                if yy >= rad && yy - rad < ih { a[(yy - rad) * iw + xx] = acc / (2 * rad + 1) as f32; }
            }
        }
    }
    for (i, p) in img.px.iter_mut().enumerate() {
        if a[i] > 0.002 { *p = over(*p, with_coverage(color, a[i])); }
    }
}

/// A pixel picture as large as fits in the box at a whole scale (so it stays crisp), centered.
pub fn pixel(img: &mut Image, c: &Canvas, pal: &Palette, x: i32, y: i32, w: i32, h: i32) {
    let s = (w / c.w.max(1)).min(h / c.h.max(1)).max(1);
    c.draw(img, x + (w - c.w * s) / 2, y + (h - c.h * s) / 2, s, pal);
}
