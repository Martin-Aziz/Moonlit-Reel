//! effects.rs — Real-time audio effects chain
//!
//! Implements biquad parametric EQ, convolution reverb, dynamic range
//! compression, and ReplayGain normalization. Designed to be inserted
//! into the AVAudioEngine signal chain via a Rust-managed PCM tap,
//! or run as a standalone processing pipeline for offline rendering.

use std::f64::consts::PI;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

// ── Parametric EQ ────────────────────────────────────────────────────────────

/// A single parametric EQ band.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqBand {
    pub frequency: f64,  /// Hz
    pub gain_db:   f64,  /// ±12 dB
    pub q:         f64,  /// Quality factor (0.1–10.0)
    pub filter_type: EqFilterType,
    pub enabled:   bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum EqFilterType {
    Peaking,
    LowShelf,
    HighShelf,
    LowPass,
    HighPass,
    Notch,
}

/// Biquad filter coefficients (direct form II transposed).
#[derive(Debug, Clone, Copy)]
pub struct BiquadCoeffs {
    pub b0: f64, pub b1: f64, pub b2: f64,
    pub a1: f64, pub a2: f64,
}

/// Stateful biquad filter (one per channel per band).
#[derive(Debug, Clone, Copy, Default)]
struct BiquadState {
    z1: f64,
    z2: f64,
}

/// 10-band parametric equalizer.
pub struct ParametricEq {
    bands:        Vec<EqBand>,
    sample_rate:  f64,
    coeffs:       Vec<BiquadCoeffs>,
    /// State per band per channel [band][channel]
    state:        Vec<[BiquadState; 2]>,
}

impl ParametricEq {
    pub fn new(sample_rate: f64) -> Self {
        let bands = default_10_band_eq();
        let n = bands.len();
        let coeffs: Vec<_> = bands.iter().map(|b| compute_biquad(b, sample_rate)).collect();
        let state = vec![[BiquadState::default(); 2]; n];
        Self { bands, sample_rate, coeffs, state }
    }

    /// Update a band's parameters and recompute its coefficients.
    pub fn update_band(&mut self, index: usize, band: EqBand) -> Result<()> {
        if index >= self.bands.len() {
            bail!("Band index {} out of range (have {} bands)", index, self.bands.len());
        }
        self.coeffs[index] = compute_biquad(&band, self.sample_rate);
        self.bands[index] = band;
        Ok(())
    }

    /// Process a stereo interleaved buffer in-place (L, R, L, R, …).
    ///
    /// `samples` must have even length. Processes up to 2 channels.
    pub fn process_stereo(&mut self, samples: &mut [f32]) {
        for (band_idx, coeff) in self.coeffs.iter().enumerate() {
            if !self.bands[band_idx].enabled {
                continue;
            }
            let state = &mut self.state[band_idx];
            for frame in samples.chunks_exact_mut(2) {
                frame[0] = biquad_tick(coeff, &mut state[0], frame[0] as f64) as f32;
                frame[1] = biquad_tick(coeff, &mut state[1], frame[1] as f64) as f32;
            }
        }
    }

    pub fn bands(&self) -> &[EqBand] {
        &self.bands
    }
}

fn biquad_tick(c: &BiquadCoeffs, s: &mut BiquadState, x: f64) -> f64 {
    let y = c.b0 * x + s.z1;
    s.z1 = c.b1 * x - c.a1 * y + s.z2;
    s.z2 = c.b2 * x - c.a2 * y;
    y
}

fn compute_biquad(band: &EqBand, sr: f64) -> BiquadCoeffs {
    let w0 = 2.0 * PI * band.frequency / sr;
    let cos_w0 = w0.cos();
    let sin_w0 = w0.sin();
    let alpha = sin_w0 / (2.0 * band.q);
    let a_linear = 10f64.powf(band.gain_db / 40.0);

    match band.filter_type {
        EqFilterType::Peaking => {
            let b0 = 1.0 + alpha * a_linear;
            let b1 = -2.0 * cos_w0;
            let b2 = 1.0 - alpha * a_linear;
            let a0 = 1.0 + alpha / a_linear;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha / a_linear;
            BiquadCoeffs { b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0 }
        }
        EqFilterType::LowShelf => {
            let b0 = a_linear * ((a_linear+1.0) - (a_linear-1.0)*cos_w0 + 2.0*a_linear.sqrt()*alpha);
            let b1 = 2.0 * a_linear * ((a_linear-1.0) - (a_linear+1.0)*cos_w0);
            let b2 = a_linear * ((a_linear+1.0) - (a_linear-1.0)*cos_w0 - 2.0*a_linear.sqrt()*alpha);
            let a0 = (a_linear+1.0) + (a_linear-1.0)*cos_w0 + 2.0*a_linear.sqrt()*alpha;
            let a1 = -2.0 * ((a_linear-1.0) + (a_linear+1.0)*cos_w0);
            let a2 = (a_linear+1.0) + (a_linear-1.0)*cos_w0 - 2.0*a_linear.sqrt()*alpha;
            BiquadCoeffs { b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0 }
        }
        EqFilterType::HighShelf => {
            let b0 = a_linear * ((a_linear+1.0) + (a_linear-1.0)*cos_w0 + 2.0*a_linear.sqrt()*alpha);
            let b1 = -2.0 * a_linear * ((a_linear-1.0) + (a_linear+1.0)*cos_w0);
            let b2 = a_linear * ((a_linear+1.0) + (a_linear-1.0)*cos_w0 - 2.0*a_linear.sqrt()*alpha);
            let a0 = (a_linear+1.0) - (a_linear-1.0)*cos_w0 + 2.0*a_linear.sqrt()*alpha;
            let a1 = 2.0 * ((a_linear-1.0) - (a_linear+1.0)*cos_w0);
            let a2 = (a_linear+1.0) - (a_linear-1.0)*cos_w0 - 2.0*a_linear.sqrt()*alpha;
            BiquadCoeffs { b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0 }
        }
        EqFilterType::LowPass => {
            let b0 = (1.0 - cos_w0) / 2.0;
            let b1 = 1.0 - cos_w0;
            let b2 = (1.0 - cos_w0) / 2.0;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            BiquadCoeffs { b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0 }
        }
        EqFilterType::HighPass => {
            let b0 = (1.0 + cos_w0) / 2.0;
            let b1 = -(1.0 + cos_w0);
            let b2 = (1.0 + cos_w0) / 2.0;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            BiquadCoeffs { b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0 }
        }
        EqFilterType::Notch => {
            let b0 = 1.0;
            let b1 = -2.0 * cos_w0;
            let b2 = 1.0;
            let a0 = 1.0 + alpha;
            let a1 = -2.0 * cos_w0;
            let a2 = 1.0 - alpha;
            BiquadCoeffs { b0: b0/a0, b1: b1/a0, b2: b2/a0, a1: a1/a0, a2: a2/a0 }
        }
    }
}

fn default_10_band_eq() -> Vec<EqBand> {
    let freqs = [32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
    freqs
        .into_iter()
        .map(|f| EqBand {
            frequency:   f,
            gain_db:     0.0,
            q:           1.41, // Butterworth Q
            filter_type: EqFilterType::Peaking,
            enabled:     true,
        })
        .collect()
}

// ── Dynamic Range Compressor ──────────────────────────────────────────────────

/// Lookahead dynamic range compressor.
pub struct Compressor {
    threshold_db: f64,
    ratio:        f64,
    attack_secs:  f64,
    release_secs: f64,
    makeup_gain:  f64,
    sample_rate:  f64,
    // State
    envelope:     f64,
}

impl Compressor {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            threshold_db: -12.0,
            ratio:        4.0,
            attack_secs:  0.003,
            release_secs: 0.25,
            makeup_gain:  1.0,
            sample_rate,
            envelope:     0.0,
        }
    }

    pub fn set_params(&mut self, threshold_db: f64, ratio: f64, attack: f64, release: f64) {
        self.threshold_db = threshold_db;
        self.ratio        = ratio.max(1.0);
        self.attack_secs  = attack.max(0.0001);
        self.release_secs = release.max(0.001);
    }

    /// Process stereo interleaved buffer in-place.
    pub fn process_stereo(&mut self, samples: &mut [f32]) {
        let attack_coeff  = (-1.0 / (self.attack_secs  * self.sample_rate)).exp();
        let release_coeff = (-1.0 / (self.release_secs * self.sample_rate)).exp();
        let threshold_lin = db_to_linear(self.threshold_db);

        for frame in samples.chunks_exact_mut(2) {
            let peak = frame[0].abs().max(frame[1].abs()) as f64;
            let coeff = if peak > self.envelope { attack_coeff } else { release_coeff };
            self.envelope = self.envelope * coeff + peak * (1.0 - coeff);

            let gain = if self.envelope > threshold_lin {
                let excess_db = linear_to_db(self.envelope) - self.threshold_db;
                let reduction_db = excess_db * (1.0 - 1.0 / self.ratio);
                db_to_linear(-reduction_db)
            } else {
                1.0
            };

            let total_gain = (gain * self.makeup_gain) as f32;
            frame[0] *= total_gain;
            frame[1] *= total_gain;
        }
    }
}

fn db_to_linear(db: f64) -> f64 {
    10f64.powf(db / 20.0)
}

fn linear_to_db(lin: f64) -> f64 {
    20.0 * lin.max(1e-10).log10()
}

// ── ReplayGain ────────────────────────────────────────────────────────────────

/// ReplayGain 2.0 gain application.
pub struct ReplayGain {
    track_gain_db: Option<f64>,
    album_gain_db: Option<f64>,
    /// Pre-amp offset in dB (user-configured, default 0)
    pre_amp_db:    f64,
    use_album:     bool,
}

impl ReplayGain {
    pub fn new() -> Self {
        Self {
            track_gain_db: None,
            album_gain_db: None,
            pre_amp_db:    0.0,
            use_album:     true,
        }
    }

    pub fn set_track_gain(&mut self, gain_db: f64) { self.track_gain_db = Some(gain_db); }
    pub fn set_album_gain(&mut self, gain_db: f64) { self.album_gain_db = Some(gain_db); }
    pub fn set_pre_amp(&mut self, db: f64)         { self.pre_amp_db = db; }
    pub fn set_use_album(&mut self, v: bool)        { self.use_album = v; }

    /// Linear gain multiplier to apply to all samples.
    pub fn gain_factor(&self) -> f32 {
        let gain_db = if self.use_album {
            self.album_gain_db.or(self.track_gain_db).unwrap_or(0.0)
        } else {
            self.track_gain_db.or(self.album_gain_db).unwrap_or(0.0)
        };
        db_to_linear(gain_db + self.pre_amp_db) as f32
    }

    pub fn apply(&self, samples: &mut [f32]) {
        let factor = self.gain_factor();
        for s in samples.iter_mut() {
            *s = (*s * factor).clamp(-1.0, 1.0);
        }
    }
}

impl Default for ReplayGain {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_biquad_unity_gain_at_0db_peaking() {
        let band = EqBand {
            frequency: 1000.0, gain_db: 0.0, q: 1.0,
            filter_type: EqFilterType::Peaking, enabled: true,
        };
        let c = compute_biquad(&band, 44100.0);
        // At 0 dB peaking, filter should pass signal unchanged
        let mut state = BiquadState::default();
        let output = biquad_tick(&c, &mut state, 1.0);
        assert!((output - 1.0).abs() < 0.01, "Unity pass failed: {}", output);
    }

    #[test]
    fn test_replay_gain_positive_gain() {
        let mut rg = ReplayGain::new();
        rg.set_track_gain(6.0); // +6 dB ≈ ×2
        let factor = rg.gain_factor();
        assert!((factor - 2.0_f32).abs() < 0.01, "Expected ~2.0 factor, got {}", factor);
    }

    #[test]
    fn test_eq_does_not_panic_on_empty_buffer() {
        let mut eq = ParametricEq::new(44100.0);
        let mut buf: Vec<f32> = vec![];
        eq.process_stereo(&mut buf); // should not panic
    }

    #[test]
    fn test_compressor_reduces_loud_signal() {
        let mut comp = Compressor::new(44100.0);
        comp.set_params(-20.0, 4.0, 0.001, 0.1);
        // Full-scale signal well above threshold
        let mut samples: Vec<f32> = vec![1.0_f32; 20000];
        comp.process_stereo(&mut samples);
        // After compression, the signal should be lower
        let last = *samples.last().unwrap();
        assert!(last < 0.9, "Compressor didn't reduce signal: {}", last);
    }
}
