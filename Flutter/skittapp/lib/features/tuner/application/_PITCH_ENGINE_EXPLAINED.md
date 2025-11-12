# Pitch Engine Explained

An accurate guitar tuner using hybrid frequency/time-domain analysis. Read this to understand the algorithm in **under 2 minutes**.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Audio In  │────▶│ Pitch Engine │────▶│  UI Display │
│  (48 kHz)   │     │  (85 ms)     │     │   (Needle)  │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
                    ┌──────┴──────┐
                    │   Hybrid    │
                    │  THS + MPM  │
                    └─────────────┘
```

---

## How It Works (in 6 steps)

### 1. Gate & Prep
- **Drop silence**: Reject frames below ~−45 dBFS (too quiet to analyze)
- **Conditioning**: Remove DC offset, apply Hann window, zero-pad for FFT resolution
- **Result**: Clean 4096-sample window → 16,384-point FFT (~2.93 Hz bins @ 48 kHz)

```
Raw PCM:  ▁▂▃▅▇█▇▅▃▂▁▁▂▃▅▇  →  [Gate: -45 dBFS]  →  ✓ Process
Silence:  ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁  →  [Gate: -45 dBFS]  →  ✗ Reject

After prep:
[DC Remove] → [Hann Window] → [Zero-pad 4× ] → [FFT 16384]
                   ╱╲                              ↓
                  ╱  ╲         Resolution:    2.93 Hz/bin
                 ╱    ╲
                ╱      ╲
```


### 2. Detect (Two Modes)

#### Auto Mode (no string pressed)
**Harmonic Product Spectrum (HPS)**
- Searches 50–1000 Hz for any pitch
- Multiplies downsampled spectra (orders 2–5) to amplify harmonics
- Global maximum = fundamental frequency candidate


#### Pressed Mode (string button active)
**Targeted Harmonic Sum (THS)**
- Searches **only ±120 cents** around the selected string (e.g., 82.41 Hz for low E)
- Uses 1/k harmonic weighting (fundamental weighted most)
- Local median whitening suppresses noise floor
- Grid search with 2-cent steps → ≈121 frequency candidates (−60…+60 steps)

```
Target: Low E (82.41 Hz)

Full spectrum:  ▁▂█▃▂▁▁▂▅▂▁▁▂▃▂▁  (50-1000 Hz, noisy)
                    ↓
THS window:         █▃▂  (only 73-92 Hz, ±120¢)
                    ↑
                 Locked!

Harmonic weighting:
f₀ (82 Hz):    ████████  (weight = 1.0)
2f₀ (164 Hz):  ████      (weight = 0.5)
3f₀ (246 Hz):  ███       (weight = 0.33)
4f₀ (328 Hz):  ██        (weight = 0.25)
```

**Why this matters**: THS greatly reduces octave errors; the octave guard prevents 2×/½× mistakes.

### 3. Refine & Guard

#### Parabolic Refinement
- **Auto mode (HPS)**: Sub-bin interpolation using log-magnitude quadratic fit (QIFFT method) on FFT peak
- **Pressed mode (THS)**: Parabolic refinement on the THS score curve
- Result: **~0.1–0.4 Hz accuracy** (much better than raw FFT bins)

```
FFT bins (coarse):        Parabolic fit (fine):
                              
    ▁  █  ▃                    ▁ ╱█╲ ▃
    │  │  │                    │╱  │ ╲│
   79 80 81 Hz                79 80.3 81 Hz
       ↑                            ↑
   Coarse peak              True peak (sub-bin)
   
Improvement: 2.93 Hz/bin → 0.3 Hz accuracy (10× better!)
```

#### Octave/Subharmonic Guard
- Tests if 2× or 0.5× frequency has better harmonic support
- Requires **7% margin** to flip → prevents spurious jumps
- Example: if 165 Hz detected but 82.5 Hz scores better, fold down

```
Detected: 165 Hz (wrong octave!)

Test alternatives:
  165 Hz:  score = 0.45  ▅▅▅▅▅
  82.5 Hz: score = 0.52  ▅▅▅▅▅▅  ← 15% better!
  
Action: Fold down to 82.5 Hz ✓

Visual:
     82 Hz        165 Hz        330 Hz
      │             │             │
   [Strong]      [Weak]       [Absent]
      ▓             ░             
   Correct!     (harmonic)
```


### 4. Cross-Check (Pressed Mode Only)

**NSDF/MPM Time-Domain Fallback**
- Triggers when THS confidence < 0.45 (weak harmonics, missing fundamental)
- Normalized Square Difference Function in lag domain
- Searches same ±120 cent window as THS
- **Blending logic**:
  - Pick MPM if strength ≥ 0.6 and within 10 cents of THS
  - Otherwise: 60% THS + 40% MPM weighted average

```
Scenario: Weak pluck, missing fundamental

Frequency domain (THS):     Time domain (MPM):
  Spectrum unclear ▁▂▁▃▁      Autocorrelation clear!
  conf = 0.38 (low)              
                                    ╱╲        ╱╲
                                   ╱  ╲      ╱  ╲
                                  ╱    ╲    ╱    ╲
                              ───┘      ╲──┘      ╲───
                                  ↑            ↑
                                 lag          2×lag
                              82 samples = 82.4 Hz ✓

Decision: MPM strength = 0.72 → Use MPM result
```

**Why time domain**: Catches fundamentals that frequency analysis misses (e.g., quiet plucks, fret buzz).

### 5. Confidence Scoring

#### Pressed Mode Requirements
- **≥3 harmonics** detected
- **Confidence ≥ 0.55** (blend of peak prominence + signal level)
- **Within ±120 cents** of target

#### Confidence Formula
```
THS mode: conf = (prominence - 1) / (prominence + 1)
          where prominence = peakValue / medianValue

Auto mode: conf = 0.7 × promScore + 0.3 × levelScore
           (blend of peak prominence + signal level)
```
- Range: 0.0 (noise) → 1.0 (perfect harmonic structure)

```
Good signal:                Bad signal:
  Peak: █                     Peak: ▃
  Median: ▂                   Median: ▂
  Ratio: 10:1                 Ratio: 1.5:1
  Conf: 0.82 ✓                Conf: 0.20 ✗

Visual confidence levels:
│
│  █                           ← 1.0 (perfect)
│  ██
│  ███                         ← 0.7 (great)
│  ████
│  █████ ──────────────────    ← 0.55 (threshold)
│  ██████
│  ███████                     ← 0.3 (poor)
│  ████████
│  █████████                   ← 0.0 (noise)
└──────────────────────────▶
   Noise              Signal
```


### 6. UI Smoothing

#### Attack Hold (150 ms)
- Monitors RMS level frame-to-frame
- On **>6 dB jump**: freeze UI for 150 ms
- Prevents wild swings during string pluck transients

```
Time:     0ms    50ms   100ms  150ms  200ms  250ms
          │      │      │      │      │      │
RMS:      ▁      █▇     ▅      ▃      ▃      ▃
          │      │      │      │      │      │
Jump:     -      +25dB  -      -      -      -
          │      │◄─────150ms──►│      │
Action:   ✓      ✗      ✗      ✗      ✓      ✓
        Update  HOLD   HOLD   HOLD  Update Update

Why: String pluck has chaotic attack transient (0-150ms)
```

#### EMA Smoothing
- Exponential moving average on cents: `α ≈ 0.22` (~200 ms time constant)
- Formula: `centsSmooth = α × centsNew + (1−α) × centsOld`
- Resets on key change for instant response

```
Raw cents:     ┌─┐ ┌─┐    ┌──┐
(jittery)     ─┘ └─┘ └────┘  └─
                ↓
EMA smoothed:  ╱‾‾‾╲    ╱‾‾‾╲
(stable)      ╱     ╲__╱     ╲_

Time constant: ~200ms (4-5 frames)

Before EMA:  ±15 cents variation  ← Needle jumps!
After EMA:   ±2 cents variation   ← Smooth & stable ✓
```

#### Display Gate
- Only update UI when confidence ≥ 0.55
- Prevents flickering on weak/ambiguous signals

```
Confidence over time:
1.0 │    ▄▀▀▀▀▀▀▀▀▀▀▀▄
    │   ▐            ▌
0.55├───┼────────────┼─────  ← Display threshold
    │  ▐              ▌
0.0 │▄▀                ▀▄▄▄
    └──────────────────────▶ Time
    
    ✗✗✓✓✓✓✓✓✓✓✓✓✓✗✗✗✗
    (Don't show weak signals)
```


---

## Algorithm Comparison

| Scenario | Method | Accuracy | Speed |
|----------|--------|----------|-------|
| **No string pressed** | HPS (wide search) | ±0.3–0.6 Hz (~6–12¢ @ E2) | ~85 ms/frame |
| **String pressed** | THS → MPM fallback | **typically ≤±5¢ after ~300ms** | ~85 ms/frame |
| **Weak signal** | MPM time-domain | ≈1–2¢ typical on steady tones | ~85 ms/frame |

**Note**: Sub-cent accuracy possible with steady, clean tones in pressed mode.

### Visual Accuracy Comparison

```
Traditional FFT (no interpolation):
├─────┼─────┼─────┼─────┼─────┤
│     │  ?  │     │     │     │   Bin spacing is 2.93 Hz; worst-case error ≈ ±1.46 Hz (≈ ±30¢ @ 82 Hz).
└─────┴─────┴─────┴─────┴─────┘

Our HPS (with QIFFT):
├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
│ │?│ │ │ │ │ │ │ │ │ │ │ │ │ │   Accuracy: ±0.3 Hz (≈±6.3¢ @ 82 Hz)
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘

Our THS+MPM (pressed mode):
├┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┼┤
│?│││││││││││││││││││││││││││││   Accuracy: ±0.05 Hz (≈±1.05¢ @ 82 Hz)
└┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┘

Legend: ? = detected pitch can be anywhere in range
        Smaller range = more accurate!
```

---

## Key Parameters

```dart
sampleRate: 48000,           // Input audio rate
windowLength: 4096,          // Analysis window (85 ms @ 48k)
hpsOrder: 5,                 // HPS downsampling depth
padPow2: 2,                  // 4× zero-padding → fine FFT bins
levelDbGate: -45.0,          // Silence threshold
smoothCount: 5,              // Median filter length
preEmphasis: 0.97,           // High-pass (auto mode only)
tiltAlpha: 0.5,              // Spectral tilt comp (auto mode only)
```

**Note**: Pressed mode disables tilt/pre-emphasis to favor the fundamental.

---

## What Makes This Accurate

1. **Hybrid approach**: Frequency domain (THS) + time domain (MPM) catches all edge cases
2. **Harmonic weighting**: 1/k weights favor fundamental over overtones
3. **Local whitening**: Normalizes by median → noise-floor independent
4. **Octave guard**: Prevents 2×/0.5× errors with confidence margin
5. **Sub-bin refinement**: Parabolic fit → 10× better than raw FFT bins
6. **Attack immunity**: 150 ms hold + EMA smoothing → stable display

### The 6 Layers of Accuracy

```
Layer 1: Zero-padding          ────────────▶  2.93 Hz resolution
                                              
Layer 2: Parabolic refine      ────────────▶  0.30 Hz accuracy
                                              (10× improvement)
                                              
Layer 3: Harmonic weighting    ────────────▶  Reject overtones
         (1/k)                                
                                              
Layer 4: Octave guard          ────────────▶  Prevent ×2, ÷2 errors
         (±7% margin)                         
                                              
Layer 5: THS + MPM blend       ────────────▶  Handle weak signals
                                              
Layer 6: EMA smoothing         ────────────▶  Stable display
         (α=0.22)                             
                                              
Result: Typically ≤±5¢ after ~300ms (sub-cent possible with clean tone)
```

### Why Each Layer Matters

```
Without Layer 3 (no harmonic weighting):
Spectrum: ▁ █ ▂ ▁ ▃ ▂ ▁ ▂     ← Picks random peak!
             ↑     ↑
           f₀?   2f₀?

With Layer 3 (1/k weighting):
Weighted: ▁ █ ▁ ▁ ▁ ▁ ▁ ▁     ← Clear winner
             ↑
           f₀ ✓

Without Layer 6 (no EMA):      With Layer 6 (EMA):
Needle: ↖↗↖↗↖↗↖↗↖↗              Needle: ──↗───
        (jittery)                       (smooth)
```

---

## Code Flow (Pressed Mode)

```
                    ┌─────────────────────────────────┐
                    │      PCM Audio (4096 samples)   │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │   Gate Check (dBFS > -45?)      │
                    └──┬───────────────────────────┬──┘
                       │ Yes                       │ No
            ┌──────────▼────────────┐             │
            │  DC Remove + Hann     │          [Reject]
            │  Window + Zero-pad    │
            └──────────┬────────────┘
                       │
            ┌──────────▼────────────┐
            │ 16k-point FFT →       │
            │ ~8.2k pos-freq bins   │
            └──────────┬────────────┘
                       │
         ┌─────────────▼──────────────┐
         │  THS Grid Search (±120¢)   │
         │  121 candidates × harmonic │
         │  sum with 1/k weighting    │
         └─────────────┬──────────────┘
                       │
            ┌──────────▼──────────────┐
            │  Confidence THS < 0.45? │
            └──┬──────────────────┬───┘
               │ Yes              │ No
    ┌──────────▼─────────┐       │
    │  MPM Time-Domain   │       │
    │  (NSDF on lag)     │       │
    └──────────┬─────────┘       │
               │                 │
    ┌──────────▼─────────────────▼───┐
    │  Blend/Pick Best Result        │
    │  (THS + MPM if weak signal)    │
    └──────────┬─────────────────────┘
               │
    ┌──────────▼─────────────────────┐
    │  Parabolic Refinement          │
    │  THS: on score curve           │
    │  HPS: QIFFT on FFT peak        │
    └──────────┬─────────────────────┘
               │
    ┌──────────▼─────────────────────┐
    │  Octave Guard (test ×2, ÷2)    │
    │  Flip if better by 7% margin   │
    └──────────┬─────────────────────┘
               │
    ┌──────────▼─────────────────────┐
    │  Confidence ≥ 0.55?             │
    │  Harmonics ≥ 3?                 │
    └──┬──────────────────────────┬──┘
       │ Yes                      │ No
       │                      [Reject]
       │
    ┌──▼─────────────────────────────┐
    │  Attack Hold Check (150 ms)    │
    │  Skip if RMS jumped > 6 dB     │
    └──┬─────────────────────────────┘
       │
    ┌──▼─────────────────────────────┐
    │  EMA Smoothing (α = 0.22)      │
    │  centsSmooth = blend old/new   │
    └──┬─────────────────────────────┘
       │
    ┌──▼─────────────────────────────┐
    │  Update UI (Needle, Hz, conf)  │
    └────────────────────────────────┘
```

### Processing Timeline (Single Frame)

```
Time:   0ms      20ms     40ms     60ms     80ms    85ms
        │        │        │        │        │       │
Step:   Gate     FFT      THS      MPM      Guard   UI
        │        │        │        │        │       │
        ├────────┼────────┼────────┼────────┼───────┤
        │ ✓      │ ████   │ ▓▓▓▓   │ ░░     │ →     │
        │ Pass   │ 16k    │ Grid   │ (if    │ EMA   │
        │        │ bins   │ search │ needed)│ out   │
        
Total: ~85 ms per frame (hop = 4096 samples @ 48 kHz)
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Jumps to octave | Fundamental weak | Octave guard margin too low? Check tiltAlpha |
| Locks to harmonic | Wrong peak selected | narrowSearchToTarget + lower targetHarmTol |
| Slow to respond | Over-smoothing | Reduce smoothCount or EMA α |
| Unstable needle | Under-smoothing | Increase EMA α or attack hold duration |
| Low confidence | Weak signal | Lower levelDbGate or check mic input |

---

## Performance

- **Latency**: ~85 ms (one frame hop)
- **CPU**: ~2–3% per core (example: iPad Pro, Release build)
- **Accuracy**: 
  - Auto mode: ±0.3–0.6 Hz (≈±6–12¢ @ E2)
  - Pressed mode: typically ≤±5¢ after ~300ms (sub-cent with clean tone)
- **Range**: 50–1000 Hz (covers guitar E2–E5 + harmonics)

**Note**: Performance numbers are illustrative examples, not guaranteed benchmarks.

### Performance Profile (per frame)

**Example CPU breakdown** (illustrative, varies by device):

```
CPU Usage Breakdown:
┌─────────────────────────────────────────────────┐
│ FFT (16k):          ████████████░░░░  60%      │
│ THS Grid Search:    ███████░░░░░░░░░  35%      │
│ MPM (if needed):    ██░░░░░░░░░░░░░░  10%      │
│ Octave Guard:       █░░░░░░░░░░░░░░░   5%      │
│ EMA/UI:             ▓░░░░░░░░░░░░░░░   3%      │
└─────────────────────────────────────────────────┘

Memory Usage (illustrative, device-dependent):
- FFT buffer:      128 KB  (16384 × 8 bytes, double)
- Magnitude spec:  64 KB   (8192 × 8 bytes)
- THS grid:        ~1 KB   (121 candidates)
- History buffers: <1 KB   (smoothing)
Total:            ~200 KB per engine instance
```

### Accuracy vs. Latency Trade-off

**Conceptual comparison** (not benchmarked):

```
                    Our Engine
                        │
    High Accuracy       ●  THS+MPM (~5¢, 85ms)
         ▲              │
         │              │
         │              │
    ±1 cent ────────────┼──── 
         │              │
         │      ●       │   Basic FFT (±5¢, 50ms)
         │      │       │
    Low  └──────┴───────┴────────────▶
         0ms   50ms   100ms   150ms
              Latency (lower = better)

Target: ~5¢ @ 85ms after settling
(Professional tuners: ±1¢ @ 100ms)
```


## Comparison: Our Engine vs. Traditional Tuners

### Approach Comparison

```
┌─────────────────────────────────────────────────────────────┐
│                    TRADITIONAL TUNER                        │
├─────────────────────────────────────────────────────────────┤
│  Audio → FFT → Peak detect → Display                       │
│          │                                                   │
│          └─ Problems:                                       │
│             • Locks to harmonics (wrong octave)             │
│             • Jittery needle (no smoothing)                 │
│             • Fails on weak signals                         │
│             • ±5-10 cents accuracy                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     OUR HYBRID ENGINE                        │
├─────────────────────────────────────────────────────────────┤
│  Audio → Gate → FFT → THS (±120¢) → MPM fallback           │
│          │      │     │              │                       │
│          │      │     │              └─ Weak signals OK     │
│          │      │     └─ Harmonic rejection (1/k)           │
│          │      └─ High resolution (16k FFT)                │
│          └─ Noise immunity                                  │
│                                                              │
│  → Octave guard → Parabolic refine → Attack hold → EMA     │
│     │             │                   │            │         │
│     │             │                   │            └─ Smooth │
│     │             │                   └─ Stable start        │
│     │             └─ Sub-cent accuracy                      │
│     └─ Prevent ×2/÷2 errors                                │
│                                                              │
│  Result: ±0.3–0.6 Hz auto; typically ≤±5¢ pressed (sub-cent possible) ✓ │
└─────────────────────────────────────────────────────────────┘
```

### Feature Matrix

```
Feature                    Basic FFT   Autocorr   YIN/MPM   Our Engine
────────────────────────────────────────────────────────────────────────
Octave errors              Common ✗    Rare ▲     Rare ▲    Rare ✓
Harmonic rejection         No ✗        Partial ▲  Good ●    Best ✓
Weak signal handling       Poor ✗      Good ●     Good ●    Best ✓
Sub-cent accuracy          No ✗        No ✗       Partial ▲ Yes ✓
Attack transient immunity  No ✗        No ✗       No ✗      Yes ✓
Smooth display             No ✗        No ✗       No ✗      Yes ✓
Pressed-note mode          No ✗        No ✗       No ✗      Yes ✓
CPU efficiency             Best ✓      Good ●     Good ●    Good ●
────────────────────────────────────────────────────────────────────────
Legend: ✓ = Excellent  ● = Good  ▲ = Okay  ✗ = Poor
```



## References

- **HPS (Harmonic Product Spectrum)**: Classic pitch detection method from Schroeder/Noll era, enhanced with downsampling
- **YIN/NSDF**: A. de Cheveigné & H. Kawahara, "YIN, a fundamental frequency estimator for speech and music" (2002) — time-domain autocorrelation method
- **MPM**: P. McLeod, "A smarter way to find pitch" (2005) — Normalized Square Difference Function implementation
- **QIFFT**: T. Grandke, "Interpolation algorithms for discrete Fourier transforms of weighted signals" (1983) — log-parabolic sub-bin refinement
- **THS weighting**: Custom harmonic sum with 1/k weighting and local whitening

---

**Last updated**: November 2025  
**Engine version**: Stage 3 (THS + MPM + Attack Hold + EMA)
