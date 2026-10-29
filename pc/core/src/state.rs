// What's kept between runs, as a small JSON file: settings, the pet, and today's glasses of water.
// Field names match the Mac app's (pet record included), so the two read alike.

use crate::pet::PetRecord;
use crate::pets::{Glasses, Hat, Neckwear, Outfit, Species};
use std::collections::BTreeMap;

#[derive(Clone, Debug)]
pub struct Saved {
    pub gravity: bool,
    pub size: i32,
    pub sleep_after: f64,
    pub sound: bool,
    pub water: f64,
    pub saved_at: f64,
    pub pet: Option<PetRecord>,
    pub glasses: i32,
    pub water_day: String,
}

impl Default for Saved {
    fn default() -> Saved {
        Saved { gravity: true, size: 4, sleep_after: 120.0, sound: true, water: 3600.0, saved_at: 0.0, pet: None, glasses: 0, water_day: String::new() }
    }
}

// MARK: - A very small JSON

#[derive(Clone, Debug, PartialEq)]
pub enum Json { Null, Bool(bool), Num(f64), Str(String), Arr(Vec<Json>), Obj(BTreeMap<String, Json>) }

impl Json {
    fn get(&self, k: &str) -> Option<&Json> { if let Json::Obj(m) = self { m.get(k) } else { None } }
    fn num(&self, k: &str) -> Option<f64> { if let Some(Json::Num(n)) = self.get(k) { Some(*n) } else { None } }
    fn bool(&self, k: &str) -> Option<bool> { if let Some(Json::Bool(b)) = self.get(k) { Some(*b) } else { None } }
    fn str(&self, k: &str) -> Option<&str> { if let Some(Json::Str(s)) = self.get(k) { Some(s) } else { None } }
}

struct Parser<'a> { s: &'a [u8], i: usize }

impl Parser<'_> {
    fn ws(&mut self) { while self.i < self.s.len() && (self.s[self.i] as char).is_ascii_whitespace() { self.i += 1; } }
    fn eat(&mut self, c: u8) -> Option<()> { self.ws(); if self.s.get(self.i) == Some(&c) { self.i += 1; Some(()) } else { None } }
    fn value(&mut self) -> Option<Json> {
        self.ws();
        match *self.s.get(self.i)? {
            b'{' => {
                self.i += 1;
                let mut m = BTreeMap::new();
                if self.eat(b'}').is_some() { return Some(Json::Obj(m)); }
                loop {
                    self.ws();
                    let Json::Str(k) = self.string()? else { return None };
                    self.eat(b':')?;
                    let v = self.value()?;
                    m.insert(k, v);
                    if self.eat(b',').is_some() { continue; }
                    self.eat(b'}')?;
                    return Some(Json::Obj(m));
                }
            }
            b'[' => {
                self.i += 1;
                let mut a = Vec::new();
                if self.eat(b']').is_some() { return Some(Json::Arr(a)); }
                loop {
                    a.push(self.value()?);
                    if self.eat(b',').is_some() { continue; }
                    self.eat(b']')?;
                    return Some(Json::Arr(a));
                }
            }
            b'"' => self.string(),
            b't' if self.s[self.i..].starts_with(b"true") => { self.i += 4; Some(Json::Bool(true)) }
            b'f' if self.s[self.i..].starts_with(b"false") => { self.i += 5; Some(Json::Bool(false)) }
            b'n' if self.s[self.i..].starts_with(b"null") => { self.i += 4; Some(Json::Null) }
            _ => {
                let st = self.i;
                while self.i < self.s.len() && matches!(self.s[self.i], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') { self.i += 1; }
                std::str::from_utf8(&self.s[st..self.i]).ok()?.parse().ok().map(Json::Num)
            }
        }
    }
    fn string(&mut self) -> Option<Json> {
        if self.s.get(self.i) != Some(&b'"') { return None; }
        self.i += 1;
        let mut out = String::new();
        loop {
            let c = *self.s.get(self.i)?;
            self.i += 1;
            match c {
                b'"' => return Some(Json::Str(out)),
                b'\\' => {
                    let e = *self.s.get(self.i)?;
                    self.i += 1;
                    match e {
                        b'n' => out.push('\n'), b't' => out.push('\t'), b'r' => out.push('\r'),
                        b'u' => {
                            let h = std::str::from_utf8(self.s.get(self.i..self.i + 4)?).ok()?;
                            self.i += 4;
                            out.push(char::from_u32(u32::from_str_radix(h, 16).ok()?).unwrap_or('?'));
                        }
                        other => out.push(other as char),
                    }
                }
                _ => {
                    // copy the whole UTF-8 sequence
                    let st = self.i - 1;
                    let len = match c { 0xf0..=0xff => 4, 0xe0..=0xef => 3, 0xc0..=0xdf => 2, _ => 1 };
                    self.i = st + len;
                    out.push_str(std::str::from_utf8(self.s.get(st..st + len)?).ok()?);
                }
            }
        }
    }
}

pub fn parse(text: &str) -> Option<Json> { Parser { s: text.as_bytes(), i: 0 }.value() }

fn quote(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""), '\\' => o.push_str("\\\\"), '\n' => o.push_str("\\n"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn num(v: f64) -> String { if v.is_finite() { format!("{v}") } else { "0".into() } }

impl Saved {
    pub fn to_json(&self) -> String {
        let mut s = String::from("{\n");
        s += &format!("  \"gravity\": {},\n  \"size\": {},\n  \"sleepAfter\": {},\n  \"sound\": {},\n  \"water\": {},\n  \"savedAt\": {},\n",
                      self.gravity, self.size, num(self.sleep_after), self.sound, num(self.water), num(self.saved_at));
        s += &format!("  \"glasses\": {},\n  \"waterDay\": {},\n", self.glasses, quote(&self.water_day));
        if let Some(p) = &self.pet {
            s += &format!("  \"pet\": {{ \"id\": {}, \"species\": {}, \"name\": {}, \"outfit\": {{ \"hat\": {}, \"glasses\": {}, \"neck\": {} }}, ",
                          quote(&p.id), quote(p.species.raw()), quote(&p.name), quote(p.outfit.hat.raw()), quote(p.outfit.glasses.raw()), quote(p.outfit.neck.raw()));
            s += &format!("\"fullness\": {}, \"happiness\": {}, \"energy\": {}, \"x\": {} }}\n", num(p.fullness), num(p.happiness), num(p.energy), num(p.x));
        } else {
            s += "  \"pet\": null\n";
        }
        s += "}\n";
        s
    }

    /// Anything missing or odd falls back to the defaults, so an old or hand-edited file never stops the pet.
    pub fn from_json(text: &str) -> Saved {
        let d = Saved::default();
        let Some(j) = parse(text) else { return d };
        let pet = j.get("pet").and_then(|p| {
            let species = Species::from_raw(p.str("species")?);
            let o = p.get("outfit");
            let outfit = Outfit {
                hat: Hat::from_raw(o.and_then(|o| o.str("hat")).unwrap_or("none")),
                glasses: Glasses::from_raw(o.and_then(|o| o.str("glasses")).unwrap_or("none")),
                neck: Neckwear::from_raw(o.and_then(|o| o.str("neck")).unwrap_or("none")),
            };
            Some(PetRecord {
                id: p.str("id").unwrap_or("pet").into(), species,
                name: p.str("name").filter(|n| !n.trim().is_empty()).unwrap_or(species.default_name()).chars().take(20).collect(),
                outfit, fullness: p.num("fullness").unwrap_or(80.0).clamp(0.0, 100.0), happiness: p.num("happiness").unwrap_or(80.0).clamp(0.0, 100.0),
                energy: p.num("energy").unwrap_or(90.0).clamp(0.0, 100.0), x: p.num("x").unwrap_or(0.0),
            })
        });
        Saved {
            gravity: j.bool("gravity").unwrap_or(d.gravity),
            size: j.num("size").map(|n| (n as i32).clamp(2, 6)).unwrap_or(d.size),
            sleep_after: j.num("sleepAfter").filter(|n| *n >= 10.0).unwrap_or(d.sleep_after),
            sound: j.bool("sound").unwrap_or(d.sound),
            water: j.num("water").filter(|n| *n >= 0.0).unwrap_or(d.water),
            saved_at: j.num("savedAt").unwrap_or(0.0),
            glasses: j.num("glasses").map(|n| n as i32).unwrap_or(0),
            water_day: j.str("waterDay").unwrap_or("").into(),
            pet,
        }
    }
}
