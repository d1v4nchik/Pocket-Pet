// A plain 32-bit picture: premultiplied alpha, 0xAARRGGBB per pixel, top row first.
// That's the layout Windows layered windows take as is, and it writes out to PNG for checking art offscreen.

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Image {
    pub w: i32,
    pub h: i32,
    pub px: Vec<u32>,
}

/// Straight (not premultiplied) 0xAARRGGBB to premultiplied.
#[inline]
pub fn premul(c: u32) -> u32 {
    let a = c >> 24;
    if a == 255 { return c; }
    if a == 0 { return 0; }
    let m = |v: u32| (v * a + 127) / 255;
    a << 24 | m((c >> 16) & 0xff) << 16 | m((c >> 8) & 0xff) << 8 | m(c & 0xff)
}

/// Source-over for premultiplied pixels.
#[inline]
pub fn over(dst: u32, src: u32) -> u32 {
    let sa = src >> 24;
    if sa == 255 { return src; }
    if sa == 0 { return dst; }
    let k = 255 - sa;
    let ch = |s: u32, d: u32| (s + (d * k + 127) / 255).min(255);
    ch(src >> 24, dst >> 24) << 24
        | ch((src >> 16) & 0xff, (dst >> 16) & 0xff) << 16
        | ch((src >> 8) & 0xff, (dst >> 8) & 0xff) << 8
        | ch(src & 0xff, dst & 0xff)
}

/// A straight color with its alpha scaled by `cov` (0...1), premultiplied.
#[inline]
pub fn with_coverage(c: u32, cov: f32) -> u32 {
    let a = ((c >> 24) as f32 * cov.clamp(0.0, 1.0)).round() as u32;
    premul(a << 24 | (c & 0xff_ffff))
}

impl Image {
    pub fn new(w: i32, h: i32) -> Image {
        Image { w: w.max(0), h: h.max(0), px: vec![0; (w.max(0) * h.max(0)) as usize] }
    }

    pub fn clear(&mut self) { self.px.iter_mut().for_each(|p| *p = 0); }

    #[inline]
    pub fn get(&self, x: i32, y: i32) -> u32 {
        if x < 0 || y < 0 || x >= self.w || y >= self.h { 0 } else { self.px[(y * self.w + x) as usize] }
    }

    #[inline]
    pub fn put(&mut self, x: i32, y: i32, c: u32) {
        if x < 0 || y < 0 || x >= self.w || y >= self.h { return; }
        self.px[(y * self.w + x) as usize] = c;
    }

    /// Blends a premultiplied color over one pixel.
    #[inline]
    pub fn blend(&mut self, x: i32, y: i32, c: u32) {
        if x < 0 || y < 0 || x >= self.w || y >= self.h { return; }
        let i = (y * self.w + x) as usize;
        self.px[i] = over(self.px[i], c);
    }

    /// Fills a rectangle with a straight color (opaque colors just overwrite).
    pub fn fill_rect(&mut self, x: i32, y: i32, w: i32, h: i32, c: u32) {
        let x0 = x.max(0);
        let y0 = y.max(0);
        let x1 = (x + w).min(self.w);
        let y1 = (y + h).min(self.h);
        if x0 >= x1 || y0 >= y1 { return; }
        let p = premul(c);
        let opaque = p >> 24 == 255;
        for yy in y0..y1 {
            let row = (yy * self.w) as usize;
            for xx in x0..x1 {
                let i = row + xx as usize;
                self.px[i] = if opaque { p } else { over(self.px[i], p) };
            }
        }
    }

    /// Draws another image over this one at (x, y).
    pub fn blit(&mut self, src: &Image, x: i32, y: i32) {
        for sy in 0..src.h {
            let dy = y + sy;
            if dy < 0 || dy >= self.h { continue; }
            for sx in 0..src.w {
                let dx = x + sx;
                if dx < 0 || dx >= self.w { continue; }
                let s = src.px[(sy * src.w + sx) as usize];
                if s >> 24 == 0 { continue; }
                let i = (dy * self.w + dx) as usize;
                self.px[i] = over(self.px[i], s);
            }
        }
    }

    /// Nearest-neighbour scaled copy (pixel art stays crisp).
    pub fn scaled(&self, k: i32) -> Image {
        let mut out = Image::new(self.w * k, self.h * k);
        for y in 0..out.h {
            for x in 0..out.w { out.px[(y * out.w + x) as usize] = self.px[((y / k) * self.w + x / k) as usize]; }
        }
        out
    }

    /// Every pixel's alpha multiplied by `a` (0...1).
    pub fn fade(&mut self, a: f32) {
        if a >= 1.0 { return; }
        let k = (a.clamp(0.0, 1.0) * 256.0) as u32;
        for p in self.px.iter_mut() {
            let c = *p;
            let f = |v: u32| (v * k) >> 8;
            *p = f(c >> 24) << 24 | f((c >> 16) & 0xff) << 16 | f((c >> 8) & 0xff) << 8 | f(c & 0xff);
        }
    }

    /// Straight RGBA bytes, for PNG files.
    pub fn rgba(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.px.len() * 4);
        for &c in &self.px {
            let a = c >> 24;
            let un = |v: u32| if a == 0 { 0 } else { ((v * 255 + a / 2) / a).min(255) as u8 };
            out.extend_from_slice(&[un((c >> 16) & 0xff), un((c >> 8) & 0xff), un(c & 0xff), a as u8]);
        }
        out
    }

    pub fn png(&self) -> Vec<u8> { crate::png::encode(self.w as u32, self.h as u32, &self.rgba()) }
}
