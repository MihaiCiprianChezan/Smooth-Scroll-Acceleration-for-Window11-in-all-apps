#Requires AutoHotkey v2.0

; ======= SCROLL TUNING CONSTANTS =======
baseLines      := 1       ; Minimum scroll lines per notch
maxLines       := 20      ; Maximum lines per scroll 20
maxCombo       := 6      ; Max "combo" boost (lower = gentler) 12
comboExp       := 0.6    ; Combo boost curve (lower = softer) 1.03
comboDiv       := 8.5     ; Combo divisor (higher = gentler) 2.5 
velDiv         := 60      ; Velocity divisor (higher = gentler) 28 
velExp         := 0.8    ; Velocity curve (lower = softer) 1.04
velDivisor     := 3.2     ; Velocity divisor for extra gentleness 2.7
comboDecayTime := 380     ; ms until combo starts to fade

global scrollVelocity := 0.0
global lastTick := 0
global scrollCombo := 0.0

ScrollAccel(direction) {
    global scrollVelocity, lastTick, scrollCombo
    global baseLines, maxLines, maxCombo, comboExp, comboDiv, velDiv, velExp, velDivisor, comboDecayTime

    currentTick := A_TickCount
    delta := currentTick - lastTick
    lastTick := currentTick

    ; Combo boost (momentum from repeated scrolling)
    if (delta < comboDecayTime) {
        scrollCombo := Min(scrollCombo + 1, maxCombo)
    } else {
        scrollCombo := scrollCombo * 0.7
    }

    ; Velocity boost (speed of your latest scroll movement)
    if (delta < 250) {
        increment := 10000.0 / (delta + 1)
        scrollVelocity := scrollVelocity * 0.6 + increment * 0.4
    } else {
        scrollVelocity := scrollVelocity * 0.7
    }

    ; Sensitivity and smoothness!
    comboBoost := (scrollCombo ** comboExp) / comboDiv
    velocityBoost := ((scrollVelocity / velDiv) ** velExp) / velDivisor
    scrollAmount := Floor(baseLines + comboBoost + velocityBoost)
    scrollAmount := Clamp(scrollAmount, baseLines, maxLines)

    Loop scrollAmount
        Send (direction > 0 ? "{WheelUp}" : "{WheelDown}")
}

Clamp(val, min, max) {
    if val < min
        return min
    if val > max
        return max
    return val
}

WheelUp::ScrollAccel(1)
WheelDown::ScrollAccel(-1)
