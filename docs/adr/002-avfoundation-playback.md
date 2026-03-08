# ADR 002 — AVFoundation for Audio/Video Output

**Status:** Accepted
**Date:** 2026-03-08

## Context

Audio output could be handled by Rust via `cpal` (cross-platform audio I/O) or by the native macOS `AVFoundation` / `AVAudioEngine` stack.

## Decision

Use `AVAudioEngine` for all real-time audio processing and output. Use `AVPlayer` for video. Rust handles pre-processing (effects computation, analysis) and can feed PCM into an `AVAudioPCMBuffer` for output.

## Rationale

- `AVAudioEngine` provides hardware-accelerated DSP on Apple Silicon (via AUv3)
- `installTap(onBus:)` provides a real-time PCM tap for the Metal visualizer at 60fps
- `AVAudioUnitEQ` and `AVAudioUnitDynamicsProcessor` map exactly to the spec EQ and compressor
- `AVAudioUnitTimePitch` enables tempo/pitch control with no additional Rust code
- `AVPlayer` uses VideoToolbox for hardware H.264/HEVC/ProRes decode (zero-copy on M1)
- Sandbox-compatible: no separate process, no extra entitlements

## Alternative Considered

Pure Rust `cpal` pipeline: Higher control but requires manually bridging to CoreAudio, managing audio session interruptions, and implementing all DSP nodes from scratch. The gap between `cpal` and `AVAudioEngine` for our effect set would require 6–8 weeks more engineering with no user-visible benefit.

## Technical Debt

This decision locks audio output to macOS. If cross-platform is ever needed, see `TECHNICAL_DEBT.md #1`.
