#Requires AutoHotkey v5.0

; ======= ACCELERATION TUNING =======
basePixels     := 1       ; Minimum pixels per notch (near-zero, ~1-2px)
maxPixels      := 600     ; Maximum pixels per notch (hard cap)
maxCombo       := 6.5       ; Max combo stack (lower = gentler)
comboExp       := 0.6     ; Combo curve (lower = softer)
comboDiv       := 8.5     ; Combo divisor (higher = gentler)
velDiv         := 60      ; Velocity divisor (higher = gentler)
velExp         := 0.6     ; Velocity curve (lower = softer)
velDivisor     := 3.2     ; Extra velocity gentleness
comboDecayTime := 380     ; ms before combo starts fading

; ======= SMOOTH SCROLL TUNING =======
friction       := 0.88    ; Momentum decay per frame (0.80 snappy ~ 0.93 floaty)
minSpeed       := 0.3     ; Stop animating below this px/frame
frameMs        := 8       ; Timer interval (~120fps feel)

; ======= GLOBALS =======
global scrollVelocity := 0.0
global lastTick       := 0
global scrollCombo    := 0.0
global scrollPixels   := 0.0
global timerActive    := false

; Reset combo+velocity if user stops scrolling for idleResetMs
idleResetMs := 600   ; ms of no scrolling before full reset

IdleReset() {
    global scrollVelocity, scrollCombo
    scrollVelocity := 0.0
    scrollCombo    := 0.0
    SetTimer(IdleReset, 0)
}

; ======= MAIN SCROLL HANDLER =======
ScrollAccel(direction) {
    global scrollVelocity, lastTick, scrollCombo, scrollPixels, timerActive
    global basePixels, maxPixels, maxCombo, comboExp, comboDiv
    global velDiv, velExp, velDivisor, comboDecayTime, frameMs

    currentTick := A_TickCount
    delta := currentTick - lastTick
    lastTick := currentTick

    ; --- Reset idle timer on every notch ---
    SetTimer(IdleReset, -idleResetMs)

    ; --- Combo boost (momentum from repeated scrolling) ---
    if (delta < comboDecayTime)
        scrollCombo := Min(scrollCombo + 1, maxCombo)
    else
        scrollCombo := scrollCombo * 0.7

    ; --- Velocity boost (speed of wheel spin) ---
    if (delta < 250) {
        increment := 10000.0 / (delta + 1)
        scrollVelocity := scrollVelocity * 0.6 + increment * 0.4
    } else {
        scrollVelocity := scrollVelocity * 0.7
    }

    ; --- Calculate pixel budget for this notch ---
    comboBoost    := (scrollCombo ** comboExp) / comboDiv
    velocityBoost := ((scrollVelocity / velDiv) ** velExp) / velDivisor
    ; True exponential ramp: starts at 2px, builds hard with momentum
    pixelBudget   := basePixels * (1 + (comboBoost ** 2.2) * 12 + (velocityBoost ** 2.0) * 10)
    pixelBudget   := Clamp(pixelBudget, basePixels, maxPixels)

    ; --- Add to smooth scroll debt ---
    scrollPixels += direction * pixelBudget

    ; --- Start animation timer if not running ---
    if !timerActive {
        timerActive := true
        SetTimer(AnimateScroll, frameMs)
    }
}

; ======= ANIMATION LOOP =======
AnimateScroll() {
    global scrollPixels, timerActive, friction, minSpeed

    if (Abs(scrollPixels) < minSpeed) {
        scrollPixels := 0.0
        timerActive  := false
        SetTimer(AnimateScroll, 0)
        return
    }

    ; Ease-out: take a fixed fraction of remaining debt each frame
    step         := scrollPixels * (1.0 - friction)
    scrollPixels -= step
    pixels       := Integer(Round(step))

    if (pixels = 0)
        return

    ; --- Find scrollable window under cursor ---
    MouseGetPos(&mx, &my)
    hwnd := DllCall("WindowFromPoint", "int64", (my << 32) | (mx & 0xFFFFFFFF), "ptr")

    if !hwnd
        hwnd := WinExist("A")

    ; WM_MOUSEWHEEL = 0x20A
    ; Positive wheelDelta = scroll up, negative = scroll down
    wheelDelta := Integer(Round(pixels * 120 / 20))
    wParam     := (wheelDelta << 16) & 0xFFFFFFFF
    lParam     := Integer((my & 0xFFFF) << 16) | Integer(mx & 0xFFFF)
    PostMessage(0x20A, wParam, lParam,, "ahk_id " hwnd)
}

; ======= UTILITY =======
Clamp(val, mn, mx) {
    if val < mn
        return mn
    if val > mx
        return mx
    return val
}

; ======= HOOKS =======
WheelUp::ScrollAccel(1)
WheelDown::ScrollAccel(-1)
