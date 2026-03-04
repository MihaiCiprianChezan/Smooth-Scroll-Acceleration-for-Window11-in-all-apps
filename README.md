
# Smooth Scroll for Windows 11
### *Smooth Scroll for Windows 11 with acceleration across all applications*

You can simply download the Windows 64 binary release (or build yourself, see below) 
[Smooth-Scroll-Acceleration-v5](https://github.com/MihaiCiprianChezan/Smooth-Scroll-Acceleration-for-AutoHotkey-v2/releases/tag/v5.0.0)
 (Free / MIT License)


# Auto-Hot-Key Script - use or compile yourself

This script enhances the standard mouse‑wheel behavior in Windows 11 by introducing adaptive scroll acceleration. Instead of sending a fixed number of scroll lines per wheel notch, the script dynamically adjusts scrolling intensity based on how quickly and how repeatedly you scroll. Gentle wheel movements produce gentle scrolling, while faster or more continuous scrolling results in progressively stronger acceleration. The effect is similar to the natural acceleration and deceleration you experience when dragging to scroll on Android or other touch‑driven systems, but applied to a traditional PC mouse.

The result is a smoother, more responsive, and more intuitive scrolling experience across all applications.

## Features

- Adaptive scroll acceleration based on:
  - Scroll velocity (time between wheel notches)
  - Scroll combo (momentum from repeated scrolling)
- Natural deceleration when scrolling pauses
- Fully configurable tuning constants for sensitivity and smoothness
- Lightweight implementation using only AutoHotkey v2
- Works globally across Windows applications

## How It Works

The script tracks two dynamic factors:

### Scroll Combo  
A short‑term momentum counter that increases when you scroll repeatedly within a defined time window. The more consecutive scrolls you perform, the stronger the combo boost becomes. If you pause, the combo gradually decays.

### Scroll Velocity  
A measure of how quickly the last scroll event occurred relative to the previous one. Faster wheel movements produce higher velocity values, which translate into stronger acceleration.

Both values are combined through adjustable curves and divisors to compute the final scroll output. This output determines how many virtual scroll steps are sent for each physical wheel notch.

These values can be adjusted to achieve anything from subtle smooth scrolling to aggressive high‑speed acceleration.

## Build yourself

1. Install [AutoHotkey v2](https://www.autohotkey.com/)  
2. Load `Smooth-Scroll-Acceleration_Smooth_v.5.ahk`  
3. Run it  
4. Adjust the tuning constants to match your preferred scrolling feel
5. Generate your own executable

