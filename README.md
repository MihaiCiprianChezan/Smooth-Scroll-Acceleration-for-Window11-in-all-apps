![](./Images/Mouse.jpg)

# Smooth Scroll Acceleration for Windows 11
### *Physics-based smooth scroll with momentum and acceleration — works across all applications and all monitors*

Download a Windows 64-bit build from a completed workflow run:
[Build Windows executable](https://github.com/MihaiCiprianChezan/Smooth-Scroll-Acceleration-for-Window11-in-all-apps/actions/workflows/build-windows.yml)
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
- **Built-in settings window** — choose a preset or tune every value from the tray icon
- **Japanese UI support** — menus, settings, notifications, and validation messages automatically follow the Windows display language
- **Per-application profiles** — automatically use different scroll behavior for each executable
- **Per-application disable switch** — leave selected applications on completely native Windows scrolling
- **Live tuning** — GUI changes apply immediately; direct `.ini` editing remains available
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
A momentum multiplier that grows when you scroll repeatedly within a short time window (default: 250 ms). Each rapid notch adds `+0.3×` to the multiplier, up to a cap of `3×`. If you pause, the combo resets to `1×` on the next notch.

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
baseNotches = 1.5

; Hard cap on notch budget per click.
maxNotches = 10.0

; Combo multiplier growth per rapid click.
comboStep = 0.3

; Maximum combo multiplier.
maxCombo = 3.0

; Clicks faster than this (ms) build the combo.
comboWindow = 250

; Momentum friction per frame. 0.78=snappy  0.86=balanced  0.92=floaty
friction = 0.83

; Stop animating when debt drops below this (notches).
minDebt = 0.02

; Animation timer interval ms. Lower = smoother, higher = lighter CPU.
frameMs = 8

; How strongly wheel speed amplifies scrolling.
velInfluence = 0.35

; Higher values smooth speed changes more heavily.
velSmoothing = 0.45

; Maximum velocity contribution.
velCap = 2.5

; Pause in ms before velocity memory resets.
velTimeout = 600
```

Right-click the tray icon and choose **Settings...** to edit these values in the built-in GUI. The **Gentle**, **Balanced**, and **Floaty** presets provide useful starting points; **Save & Apply** writes the values to `SmoothScroll.ini` and applies them immediately without restarting.

### Display language

Open the tray menu and choose **Language** to select **Automatic (Windows setting)**, **Japanese**, or **English**. The choice is saved in `SmoothScroll.ini` and remains active after restarting the application. Automatic mode uses Japanese when the Windows language is Japanese and English otherwise.

### Per-application profiles

The settings window detects the executable names of currently running applications. To create an application-specific profile:

1. Start the application you want to configure.
2. Open **Settings...** from the Smooth Scroll tray icon.
3. Select the executable under **Create a profile for a running application** and click **Create application profile**.
4. Adjust its values or choose a preset, then click **Save & Apply**.

Enable **Disable for this app** when an application should bypass Smooth Scroll completely. Its wheel input is then left untouched and uses the application's normal Windows scrolling behavior. Clear the checkbox and save again to restore acceleration for that application.

Whenever the mouse wheel is used, Smooth Scroll identifies the executable under the cursor and applies its profile automatically. Applications without a profile use **Default (all applications)**. Momentum is reset when moving between applications so one application's scroll state does not leak into another.

Profiles are stored in the same `SmoothScroll.ini` file under `[Profiles]` and `[Profile:application.exe]` sections.

Direct `.ini` editing is still supported: edit any value, then right-click the tray icon → **Reload Config**. Delete the file to reset to built-in defaults.

---

## Usage

### Option A — Run the binary
Download the `Smooth-Scroll-Acceleration-Windows-x64` artifact from a completed [Build Windows executable](https://github.com/MihaiCiprianChezan/Smooth-Scroll-Acceleration-for-Window11-in-all-apps/actions/workflows/build-windows.yml) workflow run, extract it, and run `Smooth-Scroll-Acceleration.exe`. No installation is needed.

To start automatically with Windows: place a shortcut to the `.exe` in your Startup folder (`Win + R` → `shell:startup`).

### Option B — Run or compile the script
1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Double-click `Smooth-Scroll-Acceleration_Smooth_v_15.ahk` to run directly
3. Or right-click → **Compile Script** to produce your own `.exe`
4. Open **Settings...** from the tray icon, or tune `SmoothScroll.ini` directly

### Option C — Build a standalone Windows executable

On a Windows 10 or 11 PC, double-click `build-windows.cmd`. It downloads verified copies of AutoHotkey v2 and the official Ahk2Exe compiler, then creates:

```text
dist\Smooth-Scroll-Acceleration.exe
```

The generated 64-bit executable runs without installing AutoHotkey. PowerShell 5.1 or later and an internet connection are required for the first build. Because the executable is not code-signed, Windows SmartScreen may show an unknown-publisher warning.

The included GitHub Actions workflow also builds the executable automatically. Open a completed **Build Windows executable** workflow run and download the `Smooth-Scroll-Acceleration-Windows-x64` artifact.

---

## Requirements

- Windows 10 / 11 (64-bit)
- AutoHotkey v2.0+ *(only if running the script directly)*

---

## License

MIT — free to use, modify, and distribute.
