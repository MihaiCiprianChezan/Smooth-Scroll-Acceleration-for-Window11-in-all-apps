#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
;  Smooth Scroll Acceleration v1.15.10 —  Hybrid Architecture
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
        val := Trim(IniRead(g_ini, "Settings", key))
        return Float(val)
    } catch {
        return default
    }
}
CfgI(key, default) {
    try {
        val := Trim(IniRead(g_ini, "Settings", key))
        return Integer(val)
    } catch {
        return default
    }
}

ReloadConfig() {
    global g_baseNotches, g_maxNotches, g_comboStep, g_maxCombo
    global g_comboWindow, g_friction, g_minDebt, g_frameMs
    global g_velInfluence, g_velSmoothing, g_velCap, g_velTimeout
    g_baseNotches  := CfgF("baseNotches",  2.0)
    g_maxNotches   := CfgF("maxNotches",   14.0)
    g_comboStep    := CfgF("comboStep",    0.5)
    g_maxCombo     := CfgF("maxCombo",     4.0)
    g_comboWindow  := CfgI("comboWindow",  280)
    g_friction     := CfgF("friction",     0.86)
    g_minDebt      := CfgF("minDebt",      0.01)
    g_frameMs      := CfgI("frameMs",      8)
    g_velInfluence := CfgF("velInfluence", 0.35)
    g_velSmoothing := CfgF("velSmoothing", 0.45)
    g_velCap       := CfgF("velCap",       2.5)
    g_velTimeout   := CfgI("velTimeout",   600)
    TrayTip("Smooth Scroll", "Config reloaded from SmoothScroll.ini", 2)
}

if !FileExist(g_ini) {
    iniText := "; ================================================================`n"
        . ";  SmoothScroll.ini  —  Smooth Scroll Acceleration v15`n"
        . "; ================================================================`n"
        . ";  Edit values below, save file, then right-click the tray icon`n"
        . ";  and choose Reload Config to apply changes instantly.`n"
        . ";  Delete this file entirely to reset everything to defaults.`n"
        . ";`n"
        . "; ----------------------------------------------------------------`n"
        . ";  QUICK PRESETS — paste the values you want into [Settings] below`n"
        . "; ----------------------------------------------------------------`n"
        . ";`n"
        . ";  GENTLE  — for high-DPI / hair-trigger mice (e.g. Alienware, Razer)`n"
        . ";    One wheel click scrolls a small, controlled amount.`n"
        . ";    Fast spinning builds very little extra momentum.`n"
        . ";    baseNotches=1.0  maxNotches=6.0   comboStep=0.2  maxCombo=2.0`n"
        . ";    comboWindow=200  friction=0.80    minDebt=0.02   frameMs=8`n"
        . ";    velInfluence=0.2 velSmoothing=0.6 velCap=1.5     velTimeout=400`n"
        . ";`n"
        . ";  BALANCED — smooth and natural for most mice  (DEFAULT)`n"
        . ";    baseNotches=1.5  maxNotches=10.0  comboStep=0.3  maxCombo=3.0`n"
        . ";    comboWindow=250  friction=0.83    minDebt=0.02   frameMs=8`n"
        . ";    velInfluence=0.35 velSmoothing=0.45 velCap=2.5   velTimeout=600`n"
        . ";`n"
        . ";  FLOATY  — for slow scroll wheels or trackballs`n"
        . ";    One click scrolls a lot. Fast spinning builds strong momentum`n"
        . ";    that glides for a long time before stopping.`n"
        . ";    baseNotches=3.0  maxNotches=20.0  comboStep=0.8  maxCombo=6.0`n"
        . ";    comboWindow=350  friction=0.92    minDebt=0.005  frameMs=8`n"
        . ";    velInfluence=0.5 velSmoothing=0.3 velCap=4.0     velTimeout=800`n"
        . ";`n"
        . "; ================================================================`n"
        . "[Settings]`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW MUCH DOES ONE WHEEL CLICK SCROLL?`n"
        . ";`n"
        . "; Each physical click of your scroll wheel is one step.`n"
        . "; This controls how many scroll steps are sent per click`n"
        . "; when scrolling slowly and casually (no speed, no momentum).`n"
        . ";`n"
        . ";   1.0 = one click scrolls exactly as Windows normally would`n"
        . ";   1.5 = one click scrolls 1.5x the normal amount`n"
        . ";   2.0 = one click scrolls twice the normal amount`n"
        . ";`n"
        . "; Lower this if even slow scrolling feels too fast.`n"
        . "; ----------------------------------------------------------------`n"
        . "baseNotches=1.5`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; MAXIMUM SCROLL AMOUNT PER CLICK (hard ceiling)`n"
        . ";`n"
        . "; No matter how fast you spin the wheel or how much momentum`n"
        . "; has built up, a single wheel click will never scroll more`n"
        . "; than this many steps. This prevents runaway scrolling.`n"
        . ";`n"
        . ";   6.0  = gentle cap, good for sensitive mice`n"
        . ";   10.0 = moderate cap`n"
        . ";   20.0 = very high, almost no ceiling`n"
        . ";`n"
        . "; Lower this if fast scrolling still feels out of control.`n"
        . "; ----------------------------------------------------------------`n"
        . "maxNotches=10.0`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW FAST DOES MOMENTUM BUILD WHEN SPINNING QUICKLY?`n"
        . ";`n"
        . "; When you spin the wheel rapidly, each successive click adds`n"
        . "; a momentum boost on top of the previous one — like pushing`n"
        . "; a swing repeatedly. This controls how big each boost is.`n"
        . ";`n"
        . ";   0.1 = very gradual buildup (many clicks to reach full speed)`n"
        . ";   0.3 = moderate buildup`n"
        . ";   0.8 = aggressive buildup (momentum surges after just a few clicks)`n"
        . ";`n"
        . "; Lower this if a few fast clicks already feel too powerful.`n"
        . "; ----------------------------------------------------------------`n"
        . "comboStep=0.3`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; MAXIMUM MOMENTUM MULTIPLIER (combo ceiling)`n"
        . ";`n"
        . "; The momentum boost from spinning quickly (see comboStep above)`n"
        . "; is capped at this multiplier. It stacks on top of baseNotches.`n"
        . ";`n"
        . "; Example: baseNotches=1.5 and maxCombo=3.0 means the fastest`n"
        . "; spinning scrolls at most 1.5 x 3.0 = 4.5 steps per click`n"
        . "; (before the hard ceiling maxNotches also kicks in).`n"
        . ";`n"
        . ";   2.0 = subtle maximum boost`n"
        . ";   4.0 = strong maximum boost`n"
        . ";   8.0 = extreme — scrolling becomes very aggressive at speed`n"
        . "; ----------------------------------------------------------------`n"
        . "maxCombo=3.0`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW LONG CAN A PAUSE BE AND STILL KEEP THE MOMENTUM GOING? (ms)`n"
        . ";`n"
        . "; If you click the wheel again within this many milliseconds of`n"
        . "; the previous click, the momentum keeps building (combo continues).`n"
        . "; If you wait longer than this, momentum resets on the next click.`n"
        . ";`n"
        . ";   150 = only very fast continuous spinning builds combo`n"
        . ";   250 = moderate — normal scrolling pace can build some combo`n"
        . ";   400 = wide window — even leisurely scrolling builds momentum`n"
        . ";`n"
        . "; Lower this if momentum builds even when scrolling slowly.`n"
        . "; ----------------------------------------------------------------`n"
        . "comboWindow=250`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW QUICKLY DOES THE GLIDE SLOW DOWN AND STOP?`n"
        . ";`n"
        . "; After you stop spinning the wheel, the scroll glides to a stop.`n"
        . "; This controls how quickly that happens — like friction on ice.`n"
        . ";`n"
        . ";   0.75 = high friction — stops very quickly, snappy feel`n"
        . ";   0.83 = medium friction — smooth, controlled stop`n"
        . ";   0.91 = low friction — long glide, floaty feel`n"
        . ";`n"
        . "; Lower this if scrolling keeps going too long after you stop.`n"
        . "; ----------------------------------------------------------------`n"
        . "friction=0.83`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; MINIMUM GLIDE THRESHOLD`n"
        . ";`n"
        . "; The glide animation stops completely once the remaining momentum`n"
        . "; drops below this value. Raise it to cut off the glide earlier`n"
        . "; (fewer tiny micro-scroll steps at the tail end of the animation).`n"
        . ";`n"
        . ";   0.01 = very long tail, animates almost to zero`n"
        . ";   0.02 = clean cutoff, recommended`n"
        . ";   0.05 = short tail, stops noticeably sooner`n"
        . "; ----------------------------------------------------------------`n"
        . "minDebt=0.02`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; ANIMATION SMOOTHNESS (timer interval in milliseconds)`n"
        . ";`n"
        . "; How often the glide animation updates. Lower = smoother but`n"
        . "; uses slightly more CPU. 8ms (~120fps) is imperceptible to the`n"
        . "; human eye. No reason to change this unless you have performance`n"
        . "; concerns on a very old machine.`n"
        . ";`n"
        . ";   8  = very smooth (~120 updates/sec)`n"
        . ";   16 = smooth (~60 updates/sec), lighter on CPU`n"
        . "; ----------------------------------------------------------------`n"
        . "frameMs=8`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW MUCH DOES SPINNING SPEED AMPLIFY THE SCROLL?`n"
        . ";`n"
        . "; The faster you spin the wheel, the more each click scrolls —`n"
        . "; on top of the combo boost. This controls how strongly that`n"
        . "; speed amplification kicks in.`n"
        . ";`n"
        . "; Formula: budget = baseNotches x combo x (1 + speed x velInfluence)`n"
        . ";`n"
        . ";   0.1  = speed has very little extra effect`n"
        . ";   0.35 = moderate speed amplification (default)`n"
        . ";   0.6  = fast spinning significantly boosts each click`n"
        . ";`n"
        . "; Lower this if fast spinning feels disproportionately powerful`n"
        . "; compared to slow scrolling.`n"
        . "; ----------------------------------------------------------------`n"
        . "velInfluence=0.35`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW STICKY IS THE SPEED MEMORY? (velocity smoothing)`n"
        . ";`n"
        . "; The script tracks how fast you are spinning and smooths it`n"
        . "; over time so sudden jerky movements don't spike the scroll`n"
        . "; amount. This controls the balance between old and new readings.`n"
        . ";`n"
        . "; Formula: smoothedSpeed = (old x velSmoothing) + (new x (1-velSmoothing))`n"
        . ";`n"
        . ";   0.2  = reacts quickly to speed changes, less smoothing`n"
        . ";   0.45 = balanced smoothing (default)`n"
        . ";   0.7  = very smooth, slow to respond to speed changes`n"
        . ";`n"
        . "; Raise this if scrolling speed feels erratic or spiky.`n"
        . "; Lower this if acceleration feels sluggish to respond.`n"
        . "; ----------------------------------------------------------------`n"
        . "velSmoothing=0.45`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; MAXIMUM SPEED CONTRIBUTION (velocity cap)`n"
        . ";`n"
        . "; The speed reading fed into the budget formula is capped at this`n"
        . "; value, no matter how fast you spin. This prevents extreme`n"
        . "; high-DPI mice or fast flicks from producing absurd scroll amounts.`n"
        . ";`n"
        . ";   1.0 = tight cap — fast spinning not much stronger than moderate`n"
        . ";   2.5 = moderate cap (default)`n"
        . ";   5.0 = loose cap — very fast spinning can produce strong bursts`n"
        . ";`n"
        . "; Lower this if ultra-fast flicks feel completely out of control.`n"
        . "; ----------------------------------------------------------------`n"
        . "velCap=2.5`n"
        . "`n"
        . "; ----------------------------------------------------------------`n"
        . "; HOW LONG A PAUSE RESETS THE SPEED READING? (ms)`n"
        . ";`n"
        . "; If you pause scrolling longer than this many milliseconds,`n"
        . "; the speed memory resets to zero — so your next scroll starts`n"
        . "; fresh with no carry-over velocity from before the pause.`n"
        . ";`n"
        . ";   300 = short pause resets speed (more responsive)`n"
        . ";   600 = moderate pause (default)`n"
        . ";   900 = long pause — speed carries over even after a long gap`n"
        . ";`n"
        . "; Lower this if residual speed from a previous scroll unexpectedly`n"
        . "; makes the next scroll too fast.`n"
        . "; ----------------------------------------------------------------`n"
        . "velTimeout=600`n"
    FileAppend(iniText, g_ini)
}

global g_baseNotches  := CfgF("baseNotches",  2.0)
global g_maxNotches   := CfgF("maxNotches",   14.0)
global g_comboStep    := CfgF("comboStep",    0.5)
global g_maxCombo     := CfgF("maxCombo",     4.0)
global g_comboWindow  := CfgI("comboWindow",  280)
global g_friction     := CfgF("friction",     0.86)
global g_minDebt      := CfgF("minDebt",      0.01)
global g_frameMs      := CfgI("frameMs",      8)
global g_velInfluence := CfgF("velInfluence", 0.35)
global g_velSmoothing := CfgF("velSmoothing", 0.45)
global g_velCap       := CfgF("velCap",       2.5)
global g_velTimeout   := CfgI("velTimeout",   600)

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
    global g_velInfluence, g_velSmoothing, g_velCap, g_velTimeout

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
    if (delta > 0 && delta < g_velTimeout) {
        spd        := 300.0 / delta
        g_velocity := g_velocity * g_velSmoothing + spd * (1.0 - g_velSmoothing)
    } else {
        g_velocity := 0.0
    }

    ; Budget calculation
    velContrib := Min(g_velocity, g_velCap)
    budget     := g_baseNotches * g_combo * (1.0 + velContrib * g_velInfluence)
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
;  Tray menu
; =====================================================================
A_TrayMenu.Add("Reload Config", (*) => ReloadConfig())
A_TrayMenu.Add("Edit Config", (*) => Run("notepad.exe `"" g_ini "`""))
A_TrayMenu.Add()
A_TrayMenu.Add("Reload Script", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())

; =====================================================================
;  Hotkeys
; =====================================================================
WheelUp::ScrollAccel(1)
WheelDown::ScrollAccel(-1)
