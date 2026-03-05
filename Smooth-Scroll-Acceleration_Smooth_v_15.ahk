#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
;  Smooth Scroll Acceleration v15.10 —  Hybrid Architecture
;
;  TWO-LAYER DESIGN:
;
;  Layer 1 — ROUTING (Send on real wheel event):
;    Each real wheel notch fires Send("{WheelUp/Down 1}") once.
;    Send() re-injects a genuine synthesized input event into the OS
;    input stream. Windows routes it exactly like a real wheel event —
;    to the window under the cursor on ANY monitor, active or not,
;    Chrome, Edge, Firefox, Win32, Electron, everything.
;    This is what v14 proved works. Don't touch it.
;
;  Layer 2 — SMOOTHNESS (PostMessage WM_MOUSEWHEEL in timer):
;    The remaining notch budget is drained by the animation timer
;    using direct WM_MOUSEWHEEL injection with fractional deltas,
;    giving pixel-level smooth scrolling in apps that support it.
;    By the time the timer fires, the cursor is still on the same
;    window that Layer 1 already routed to — no cross-screen issues.
;
;  DUAL-SCREEN BUG FIX (generation counter):
;    When the user clicks screen B then scrolls, a stale AnimateScroll
;    frame from screen A's scroll might still be in-flight. The generation
;    counter (g_gen) is incremented on every new scroll event. AnimateScroll
;    snapshots it at frame start and bails before posting if it has changed.
;
;  CROSS-SCREEN LAYER 2 FIX:
;    WindowFromPoint was previously used to get a child HWND for Layer 2
;    injection. It has a negative-coordinate packing bug — on non-primary
;    monitors it silently returned the main screen's window. Fix: use the
;    top-level HWND from MouseGetPos directly — correct for all monitors.
;    AnimateScroll checks cursor against the saved window bounding rect
;    (not HWND equality) to kill momentum when the cursor leaves — more
;    reliable since Send() can shift focus and change the HWND returned
;    by MouseGetPos for the same visual window on a non-primary monitor.
;
;  RESULT:
;    - Correct routing on all monitors, all windows ✓  (Layer 1 Send)
;    - Pixel-level smooth momentum animation ✓          (Layer 2)
;    - Momentum stops when cursor moves to new window ✓
;    - No dual-screen scroll on click+scroll ✓          (gen counter)
;    - Acceleration + combo physics ✓
;
;  CONFIG: SmoothScroll.ini auto-created next to the script.
;  Right-click tray icon > Reload to apply changes.
; =====================================================================

; ---- Coordinate mode: screen coords for all mouse operations ----
CoordMode("Mouse", "Screen")

; ---- Animation state ----
global g_debt     := 0.0   ; notch debt remaining (fractional notches)
global g_dir      := 1     ; +1 = up,  -1 = down
global g_timer    := false
global g_srcWin   := 0     ; top-level HWND where scroll started
global g_srcX     := 0     ; cursor X at scroll start (screen coords)
global g_srcY     := 0     ; cursor Y at scroll start (screen coords)
global g_srcL     := 0     ; window rect left   (screen coords)
global g_srcT     := 0     ; window rect top    (screen coords)
global g_srcR     := 0     ; window rect right  (screen coords)
global g_srcB     := 0     ; window rect bottom (screen coords)
global g_gen      := 0     ; generation counter — incremented on every new scroll event
                            ; AnimateScroll captures it at start; if it changes mid-run
                            ; the frame is stale and bails before posting anything

; ---- Combo / velocity state ----
global g_lastTick := 0
global g_combo    := 1.0
global g_velocity := 0.0

; ---- Config ----
global g_ini := A_ScriptDir "\SmoothScroll.ini"

CfgF(key, default) {
    try {
        return Float(IniRead(g_ini, "Settings", key))
    } catch {
        return default
    }
}
CfgI(key, default) {
    try {
        return Integer(IniRead(g_ini, "Settings", key))
    } catch {
        return default
    }
}

if !FileExist(g_ini) {
    iniText := "; ============================================================`n"
        . ";  SmoothScroll.ini  -  Smooth Scroll Acceleration v15`n"
        . "; ============================================================`n"
        . ";  Edit values, then right-click tray icon > Reload.`n"
        . ";  Delete this file to reset to built-in defaults.`n"
        . "; ============================================================`n"
        . "[Settings]`n"
        . "`n"
        . "; Total notch budget per slow single click.`n"
        . "; 1.0 = same as one real notch.  2.0 = double.`n"
        . "baseNotches = 2.0`n"
        . "`n"
        . "; Hard cap on notch budget per click.`n"
        . "maxNotches = 14.0`n"
        . "`n"
        . "; Combo multiplier growth per rapid click.`n"
        . "comboStep = 0.5`n"
        . "`n"
        . "; Maximum combo multiplier.`n"
        . "maxCombo = 4.0`n"
        . "`n"
        . "; Clicks faster than this (ms) build the combo.`n"
        . "comboWindow = 280`n"
        . "`n"
        . "; Momentum friction per frame. 0.78=snappy  0.86=balanced  0.92=floaty`n"
        . "friction = 0.86`n"
        . "`n"
        . "; Stop animating when debt drops below this (notches).`n"
        . "minDebt = 0.01`n"
        . "`n"
        . "; Animation timer interval ms. Lower = smoother.`n"
        . "frameMs = 8`n"
    FileAppend(iniText, g_ini)
}

global g_baseNotches := CfgF("baseNotches", 2.0)
global g_maxNotches  := CfgF("maxNotches",  14.0)
global g_comboStep   := CfgF("comboStep",   0.5)
global g_maxCombo    := CfgF("maxCombo",    4.0)
global g_comboWindow := CfgI("comboWindow", 280)
global g_friction    := CfgF("friction",    0.86)
global g_minDebt     := CfgF("minDebt",     0.01)
global g_frameMs     := CfgI("frameMs",     8)

; =====================================================================
;  PostWheelMsg — inject WM_MOUSEWHEEL directly into a window's queue
;  Used only for Layer 2 (animation frames) — by then the cursor is
;  already on the correct window so cross-screen routing is not an issue.
;  delta: positive=up, negative=down
;  x, y:  screen coordinates (lParam) — always screen coords for WM_MOUSEWHEEL
;  Note:  & 0xFFFF masks to 16 bits, preserving two's-complement sign for
;         negative screen coordinates on monitors left/above primary.
; =====================================================================
PostWheelMsg(hwnd, delta, x, y) {
    wParam := (delta & 0xFFFF) << 16
    lParam := ((y & 0xFFFF) << 16) | (x & 0xFFFF)
    try {
        PostMessage(0x020A, wParam, lParam,, "ahk_id " hwnd)
    } catch {
        ; Window closed mid-animation — ignore
    }
}

; =====================================================================
;  ScrollAccel — fires on every real wheel notch
; =====================================================================
ScrollAccel(dir) {
    global g_debt, g_dir, g_timer, g_srcWin, g_srcX, g_srcY, g_srcL, g_srcT, g_srcR, g_srcB, g_gen
    global g_lastTick, g_combo, g_velocity
    global g_baseNotches, g_maxNotches, g_comboStep, g_maxCombo
    global g_comboWindow, g_frameMs

    now   := A_TickCount
    delta := now - g_lastTick
    g_lastTick := now

    ; Increment generation counter. Any AnimateScroll frame still running
    ; from a previous scroll will see the mismatch and bail before posting.
    g_gen++

    ; Capture cursor position, window, and window bounding rect.
    ; The rect is used in AnimateScroll to check if the cursor is still
    ; over the same window — more reliable than HWND equality, which can
    ; change after Send() shifts focus on non-primary monitors.
    MouseGetPos(&mx, &my, &hWin)
    g_srcWin := hWin
    g_srcX   := mx
    g_srcY   := my
    WinGetPos(&wL, &wT, &wW, &wH, "ahk_id " hWin)
    g_srcL := wL
    g_srcT := wT
    g_srcR := wL + wW
    g_srcB := wT + wH

    ; Direction reversal → kill momentum immediately
    if (dir != g_dir) {
        g_debt     := 0.0
        g_combo    := 1.0
        g_velocity := 0.0
    }
    g_dir := dir

    ; Combo build
    if (delta > 0 && delta < g_comboWindow)
        g_combo := Min(g_combo + g_comboStep, g_maxCombo)
    else
        g_combo := 1.0

    ; Velocity tracking
    if (delta > 0 && delta < 600) {
        spd        := 300.0 / delta
        g_velocity := g_velocity * 0.45 + spd * 0.55
    } else {
        g_velocity := 0.0
    }

    ; Budget calculation
    velContrib := Min(g_velocity, 2.5)
    budget     := g_baseNotches * g_combo * (1.0 + velContrib * 0.35)
    budget     := Min(budget, g_maxNotches)

    ; LAYER 1: Send() re-injects a genuine OS input event.
    ; Windows routes it to the window under the cursor on any monitor,
    ; active or not — exactly like a real hardware wheel event.
    if (dir > 0)
        Send("{WheelUp 1}")
    else
        Send("{WheelDown 1}")

    ; Remaining budget into debt for smooth animation (Layer 2)
    g_debt += Max(budget - 1.0, 0.0)

    SetTimer(AnimateScroll, 0)
    g_timer := false
    if g_debt > g_minDebt {
        g_timer := true
        SetTimer(AnimateScroll, g_frameMs)
    }
}

; =====================================================================
;  AnimateScroll — timer: drains debt via fractional WM_MOUSEWHEEL
; =====================================================================
AnimateScroll() {
    global g_debt, g_dir, g_timer, g_srcWin, g_srcL, g_srcT, g_srcR, g_srcB, g_gen
    global g_friction, g_minDebt

    myGen := g_gen

    ; Get current cursor position and window under cursor.
    ; No DPI wrapper here — toggling thread DPI context in a timer callback
    ; corrupts the restore value and causes MouseGetPos to return -16,-16.
    MouseGetPos(&cx, &cy, &curWin)

    ; Cursor left the original window — kill momentum.
    ; Use rect containment rather than HWND equality: Send() in Layer 1
    ; can shift focus, causing MouseGetPos to return a different HWND for
    ; the same visual window on a non-primary monitor. Rect check is stable.
    if (cx < g_srcL || cx >= g_srcR || cy < g_srcT || cy >= g_srcB) {
            g_debt  := 0.0
        g_timer := false
        SetTimer(AnimateScroll, 0)
        return
    }

    if (g_debt < g_minDebt) {
        g_debt  := 0.0
        g_timer := false
        SetTimer(AnimateScroll, 0)
        return
    }

    chunk  := g_debt * (1.0 - g_friction)
    g_debt -= chunk

    wheelDelta := Integer(Round(chunk * 120))
    if (wheelDelta < 1)
        return

    ; Stale frame — bail before injecting anything
    if (g_gen != myGen)
        return


    ; LAYER 2: PostMessage fractional WM_MOUSEWHEEL directly to curWin.
    if (g_dir > 0)
        PostWheelMsg(curWin,  wheelDelta, cx, cy)
    else
        PostWheelMsg(curWin, -wheelDelta, cx, cy)
}

; =====================================================================
;  Hotkeys
; =====================================================================
WheelUp::ScrollAccel(1)
WheelDown::ScrollAccel(-1)
