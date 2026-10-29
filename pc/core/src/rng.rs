// A tiny random number generator (wyrand): plenty for a pet's whims, and nothing to depend on.

use std::cell::Cell;

thread_local! {
    static STATE: Cell<u64> = Cell::new({
        let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1);
        t ^ 0x9e37_79b9_7f4a_7c15
    });
}

/// Starts the sequence over, for repeatable offscreen renders.
pub fn seed(s: u64) { STATE.with(|c| c.set(s)); }

pub fn next_u64() -> u64 {
    STATE.with(|c| {
        let s = c.get().wrapping_add(0xa076_1d64_78bd_642f);
        c.set(s);
        let t = (s as u128).wrapping_mul((s ^ 0xe703_7ed1_a0b4_28db) as u128);
        (t >> 64) as u64 ^ t as u64
    })
}

/// 0 ..< 1
pub fn unit() -> f64 { (next_u64() >> 11) as f64 / (1u64 << 53) as f64 }

/// a ... b, like Swift's `Double.random(in: a...b)`.
pub fn range(a: f64, b: f64) -> f64 { a + (b - a) * unit() }

/// a ... b inclusive.
pub fn int(a: i32, b: i32) -> i32 { a + (next_u64() % ((b - a + 1) as u64)) as i32 }

pub fn coin() -> bool { next_u64() & 1 == 1 }

pub fn chance(p: f64) -> bool { unit() < p }

pub fn pick<T>(xs: &[T]) -> &T { &xs[(next_u64() % xs.len() as u64) as usize] }
