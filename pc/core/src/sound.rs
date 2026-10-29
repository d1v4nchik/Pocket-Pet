// A tiny synth so the pets can honk, meow and purr without any audio files. A port of the Mac app's Sound.swift:
// every sound is made once, as a little WAV in memory, and the platform plays it.

use crate::rng;
use std::f64::consts::PI;

const RATE: f64 = 44100.0;
const VOLUME: f64 = 0.55;          // the Mac's mixer volume

fn make(dur: f64, mut f: impl FnMut(f64, f64) -> f64) -> Vec<f32> {
    let n = (dur * RATE) as usize;
    (0..n).map(|i| { let t = i as f64 / RATE; f(t, t / dur) as f32 }).collect()
}

fn honk(dur: f64, f0: f64) -> Vec<f32> {
    let (mut ph, mut lp) = (0.0f64, 0.0f64);
    make(dur, move |t, p| {
        let f = f0 * (1.0 - 0.22 * p) * (1.0 + 0.03 * (2.0 * PI * 28.0 * t).sin());
        ph += f / RATE;
        ph -= ph.floor();
        let x = 0.55 * (2.0 * ph - 1.0) + 0.45 * if ph < 0.42 { 1.0 } else { -1.0 };
        lp += (x - lp) * 0.28;
        lp * (t / 0.012).min(1.0) * if p > 0.75 { (1.0 - p) / 0.25 } else { 1.0 } * 0.32
    })
}

fn tone(f: f64, dur: f64) -> Vec<f32> { make(dur, |t, p| (2.0 * PI * f * t).sin() * (-p * 3.0).exp() * 0.2) }
fn silence(dur: f64) -> Vec<f32> { make(dur, |_, _| 0.0) }
fn noise() -> f64 { rng::range(-1.0, 1.0) }

fn samples(name: &str) -> Option<Vec<f32>> {
    let tau = 2.0 * PI;
    Some(match name {
        "honk" => honk(0.2, 520.0),
        "squawk" => honk(0.12, 720.0),
        "honk2" => [honk(0.16, 560.0), silence(0.05), honk(0.2, 500.0)].concat(),
        "quack" => [honk(0.09, 760.0), silence(0.03), honk(0.12, 700.0)].concat(),
        "meow" => { let mut ph = 0.0; make(0.42, move |_, p| {
            ph += (560.0 + 360.0 * (PI * p).sin().powf(0.8)) / RATE;
            let x = 0.6 * (tau * ph).sin() + 0.3 * (2.0 * tau * ph).sin() * (PI * p).sin() + 0.12 * (3.0 * tau * ph).sin();
            x * (PI * p).sin().powf(0.5) * (1.0 - p.powi(4)) * 0.2
        }) }
        "mrrp" => { let mut ph = 0.0; make(0.2, move |t, p| {
            ph += (620.0 + 120.0 * p) / RATE;
            (tau * ph).sin() * (0.6 + 0.4 * (tau * 32.0 * t).sin()) * (PI * p).sin() * 0.18
        }) }
        "woof" => { let (mut ph, mut lpw) = (0.0f64, 0.0); make(0.17, move |t, p| {
            ph += (300.0 - 130.0 * p) / RATE;
            ph -= ph.floor();
            lpw += (noise() - lpw) * 0.3;
            let x = if ph < 0.45 { 1.0 } else { -1.0 } * 0.55 + lpw * 0.6;
            x * (t / 0.008).min(1.0) * (1.0 - p) * (1.0 - p) * 0.3
        }) }
        "purr" => { let mut lp = 0.0; make(0.9, move |t, p| {
            lp += (noise() - lp) * 0.05;
            lp * (0.55 + 0.45 * (tau * 24.0 * t).sin()) * (PI * p).sin() * 2.2
        }) }
        "hiss" => { let mut lp = 0.0; make(0.5, move |_, p| {
            let n = noise();
            lp += (n - lp) * 0.3;
            (n - lp) * (PI * (p * 3.0).min(1.0)).sin() * (1.0 - p) * 0.3
        }) }
        "pop" => { let mut ph = 0.0; make(0.05, move |_, p| { ph += (700.0 + 900.0 * p) / RATE; (tau * ph).sin() * (-p * 4.0).exp() * 0.25 }) }
        "chomp" => { let mut lp = 0.0; make(0.07, move |_, p| { lp += (noise() - lp) * 0.2; lp * (1.0 - p) * 1.2 }) }
        "chime" => [tone(988.0, 0.1), tone(1319.0, 0.18)].concat(),
        "chirp" => { let mut ph = 0.0; make(0.16, move |_, p| { ph += (1100.0 + 700.0 * (PI * p).sin()) / RATE; (tau * ph).sin() * (PI * p).sin() * 0.16 }) }
        "kick" => { let mut ph = 0.0; make(0.09, move |_, p| { ph += (150.0 - 90.0 * p) / RATE; (tau * ph).sin() * (1.0 - p) * 0.45 + noise() * 0.04 * (1.0 - p) }) }
        "yawn" => { let (mut ph, mut lp) = (0.0f64, 0.0f64); make(0.7, move |t, p| {
            ph += (330.0 - 140.0 * p + 6.0 * (tau * 5.0 * t).sin()) / RATE;
            lp += (noise() - lp) * 0.1;
            (0.7 * (tau * ph).sin() + 0.6 * lp) * (PI * p).sin() * 0.14
        }) }
        "poof" => { let mut lp = 0.0; make(0.18, move |_, p| { lp += (noise() - lp) * 0.45; lp * (1.0 - p) * (1.0 - p) * 0.5 }) }
        _ => return None,
    })
}

pub const NAMES: [&str; 16] = ["honk", "squawk", "honk2", "quack", "meow", "mrrp", "woof", "purr", "hiss", "pop", "chomp", "chime", "chirp",
                               "kick", "yawn", "poof"];

/// The sound as a complete 16-bit mono WAV file, ready to hand to the system player.
pub fn wav(name: &str) -> Option<Vec<u8>> {
    let s = samples(name)?;
    let data: Vec<u8> = s.iter().flat_map(|v| (((*v as f64) * VOLUME).clamp(-1.0, 1.0) * 32767.0).round().to_le_bytes_i16()).collect();
    let mut out = Vec::with_capacity(44 + data.len());
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data.len() as u32).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());          // PCM
    out.extend_from_slice(&1u16.to_le_bytes());          // mono
    out.extend_from_slice(&(RATE as u32).to_le_bytes());
    out.extend_from_slice(&(RATE as u32 * 2).to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(&data);
    Some(out)
}

trait I16Bytes { fn to_le_bytes_i16(self) -> [u8; 2]; }
impl I16Bytes for f64 { fn to_le_bytes_i16(self) -> [u8; 2] { (self as i16).to_le_bytes() } }
