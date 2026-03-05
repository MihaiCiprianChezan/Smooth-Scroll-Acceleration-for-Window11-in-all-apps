# Smooth Scroll Acceleration for Windows 11
### *Physics-based smooth scroll with momentum and acceleration — works across all applications and all monitors*

Download the latest release (Windows 64-bit binary or raw script):  
[Smooth-Scroll-Acceleration-v15.10](https://github.com/MihaiCiprianChezan/Smooth-Scroll-Acceleration-for-Window11-in-all-apps/releases/edit/v.15.3)  
*(Free / MIT License)*

---

## What It Does

Windows scrolls in fixed, mechanical steps. This script replaces that with **physics-based momentum scrolling** — the kind you experience on Android or macOS trackpads, but for any mouse wheel, in any application.

Slow wheel movement produces gentle, precise scrolling. Fast or repeated scrolling builds momentum and glides to a natural stop. Reversing direction kills momentum immediately. Every parameter is tunable via a plain `.ini` file — no recompilation needed.

---

## Features

- **Adaptive acceleration** driven by two physics factors:
  - **Scroll velocity** — how fast you're turning the wheel
  - **Scroll combo** — momentum multiplier that builds with rapid repeated scrolling
- **Natural momentum decay** — scrolling glides to a smooth stop, friction adjustable
- **Direction reversal kills momentum instantly** — no overshoot
- **Works on all monitors in a multi-monitor setup** — hover-to-scroll on any inactive screen
- **Universal application compatibility** — Win32, Chrome, Edge, Firefox, Electron, VS Code, terminals, everything
- **Zero configuration required** — `SmoothScroll.ini` is auto-created with sane defaults on first run
- **Live tuning** — edit the `.ini`, right-click the tray icon → Reload
- **Lightweight** — pure AutoHotkey v2, no dependencies, no background services

---

## How It Works

### Two-Layer Architecture

Each real mouse wheel notch triggers two layers of scroll delivery:

**Layer 1 — Routing**  
A genuine synthesized OS input event (`Send("{WheelUp/Down 1}")`) is injected directly into the Windows input stream. Windows routes this exactly like real hardware — to whichever window is under the cursor, on any monitor, active or inactive. This is what ensures correct behavior across all applications and all screens.

**Layer 2 — Smoothness**  
The remaining scroll budget (based on velocity and combo) is drained by a high-frequency animation timer (~8 ms frames) using direct `WM_MOUSEWHEEL` message injection with fractional deltas. This produces the pixel-level smooth glide after the initial notch.

### Scroll Combo
A momentum multiplier that grows when you scroll repeatedly within a short time window (default: 280 ms). Each rapid notch adds `+0.5×` to the multiplier, up to a cap of `4×`. If you pause, the combo resets to `1×` on the next notch.

### Scroll Velocity
Measures time between wheel notches and translates faster spinning into stronger acceleration. Combined with the combo multiplier, this produces an effect that feels proportional to physical intent — gentle flicks scroll a little, fast spins scroll a lot.

### Multi-Monitor Safety
Two issues unique to multi-monitor setups are specifically handled:

- **Stale frame cancellation** — a generation counter (`g_gen`) is incremented on every new scroll event. Any in-flight animation frame from a previous scroll on a different screen checks the counter before injecting and bails if it has changed.
- **Window tracking by rect** — instead of matching window handles (which can change when focus shifts after a `Send()`), the animation timer checks whether the cursor is still within the bounding rectangle of the window where scrolling started. Stable across focus changes on non-primary monitors.

---

## Configuration

On first run, `SmoothScroll.ini` is created next to the script/executable with these defaults:

```ini
[Settings]

; Total notch budget per slow single click.
; 1.0 = same as one real notch.  2.0 = double.
baseNotches = 2.0

; Hard cap on notch budget per click.
maxNotches = 14.0

; Combo multiplier growth per rapid click.
comboStep = 0.5

; Maximum combo multiplier.
maxCombo = 4.0

; Clicks faster than this (ms) build the combo.
comboWindow = 280

; Momentum friction per frame. 0.78=snappy  0.86=balanced  0.92=floaty
friction = 0.86

; Stop animating when debt drops below this (notches).
minDebt = 0.01

; Animation timer interval ms. Lower = smoother, higher = lighter CPU.
frameMs = 8
```

Edit any value, then **right-click the tray icon → Reload** to apply. Delete the file to reset to built-in defaults.

---

## Usage

### Option A — Run the binary
Download `Smooth-Scroll-Acceleration.exe` from the [latest release](https://github.com/MihaiCiprianChezan/Smooth-Scroll-Acceleration-for-Window11-in-all-apps/releases/tag/v15.10) and run it. No installation needed.

To start automatically with Windows: place a shortcut to the `.exe` in your Startup folder (`Win + R` → `shell:startup`).

### Option B — Run or compile the script
1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Double-click `Smooth-Scroll-Acceleration_Smooth_v_15.ahk` to run directly
3. Or right-click → **Compile Script** to produce your own `.exe`
4. Tune `SmoothScroll.ini` to taste

---

## Requirements

- Windows 10 / 11 (64-bit)
- AutoHotkey v2.0+ *(only if running the script directly)*

---

## License

MIT — free to use, modify, and distribute.
