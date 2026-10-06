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
;  Right-click the tray icon > Settings... to edit and apply changes.
; =====================================================================

; ---- Coordinate mode: screen coords for all mouse operations ----
CoordMode("Mouse", "Screen")

; ---- User interface language ----
; A_Language uses the Windows locale identifier. Japanese is 0411.
global g_languageMode := "auto"

L(english, japanese) {
    global g_languageMode
    useJapanese := g_languageMode = "ja" || (g_languageMode = "auto" && A_Language = "0411")
    return useJapanese ? japanese : english
}

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
global g_settingsGui := 0
global g_settingControls := Map()
global g_profileSelector := 0
global g_runningAppSelector := 0
global g_disableProfileCheckbox := 0
global g_profileNames := []
global g_profiles := Map()
global g_disabledApps := Map()
global g_defaultRuntimeSettings := Map()
global g_activeApp := ""
global g_previousApp := ""
global g_activeFriction := 0.83
global g_activeMinDebt := 0.02

LoadLanguageMode() {
    global g_ini, g_languageMode
    try mode := StrLower(Trim(IniRead(g_ini, "UI", "language", "auto")))
    catch
        mode := "auto"
    g_languageMode := (mode = "ja" || mode = "en") ? mode : "auto"
}

SetLanguageMode(mode, *) {
    global g_ini
    if (mode != "auto" && mode != "ja" && mode != "en")
        return
    try IniWrite(mode, g_ini, "UI", "language")
    catch as err {
        MsgBox(err.Message, L("Could not save language setting", "言語設定を保存できませんでした"), "Iconx")
        return
    }
    Reload()
}

DefaultSettings() {
    return Map(
        "baseNotches", 1.5,
        "maxNotches", 10.0,
        "comboStep", 0.3,
        "maxCombo", 3.0,
        "comboWindow", 250,
        "friction", 0.83,
        "minDebt", 0.02,
        "frameMs", 8,
        "velInfluence", 0.35,
        "velSmoothing", 0.45,
        "velCap", 2.5,
        "velTimeout", 600
    )
}

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
    defaults := DefaultSettings()
    g_baseNotches  := CfgF("baseNotches",  defaults["baseNotches"])
    g_maxNotches   := CfgF("maxNotches",   defaults["maxNotches"])
    g_comboStep    := CfgF("comboStep",    defaults["comboStep"])
    g_maxCombo     := CfgF("maxCombo",     defaults["maxCombo"])
    g_comboWindow  := CfgI("comboWindow",  defaults["comboWindow"])
    g_friction     := CfgF("friction",     defaults["friction"])
    g_minDebt      := CfgF("minDebt",      defaults["minDebt"])
    g_frameMs      := CfgI("frameMs",      defaults["frameMs"])
    g_velInfluence := CfgF("velInfluence", defaults["velInfluence"])
    g_velSmoothing := CfgF("velSmoothing", defaults["velSmoothing"])
    g_velCap       := CfgF("velCap",       defaults["velCap"])
    g_velTimeout   := CfgI("velTimeout",   defaults["velTimeout"])
    RefreshSettingsCache()
    TrayTip("Smooth Scroll", L("Config reloaded from SmoothScroll.ini", "SmoothScroll.ini から設定を再読み込みしました"), 1)
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
        . "`n"
        . "[UI]`n"
        . "; auto = follow Windows language, ja = Japanese, en = English`n"
        . "language=auto`n"
    FileAppend(iniText, g_ini)
}

LoadLanguageMode()

global g_defaults     := DefaultSettings()
global g_baseNotches  := CfgF("baseNotches",  g_defaults["baseNotches"])
global g_maxNotches   := CfgF("maxNotches",   g_defaults["maxNotches"])
global g_comboStep    := CfgF("comboStep",    g_defaults["comboStep"])
global g_maxCombo     := CfgF("maxCombo",     g_defaults["maxCombo"])
global g_comboWindow  := CfgI("comboWindow",  g_defaults["comboWindow"])
global g_friction     := CfgF("friction",     g_defaults["friction"])
global g_minDebt      := CfgF("minDebt",      g_defaults["minDebt"])
global g_frameMs      := CfgI("frameMs",      g_defaults["frameMs"])
global g_velInfluence := CfgF("velInfluence", g_defaults["velInfluence"])
global g_velSmoothing := CfgF("velSmoothing", g_defaults["velSmoothing"])
global g_velCap       := CfgF("velCap",       g_defaults["velCap"])
global g_velTimeout   := CfgI("velTimeout",   g_defaults["velTimeout"])

CurrentDefaultSettings() {
    global g_baseNotches, g_maxNotches, g_comboStep, g_maxCombo
    global g_comboWindow, g_friction, g_minDebt, g_frameMs
    global g_velInfluence, g_velSmoothing, g_velCap, g_velTimeout
    return Map(
        "baseNotches", g_baseNotches,
        "maxNotches", g_maxNotches,
        "comboStep", g_comboStep,
        "maxCombo", g_maxCombo,
        "comboWindow", g_comboWindow,
        "friction", g_friction,
        "minDebt", g_minDebt,
        "frameMs", g_frameMs,
        "velInfluence", g_velInfluence,
        "velSmoothing", g_velSmoothing,
        "velCap", g_velCap,
        "velTimeout", g_velTimeout
    )
}

NormalizeAppName(name) {
    return StrLower(Trim(name))
}

LoadProfiles() {
    global g_ini, g_profiles, g_disabledApps, g_defaultRuntimeSettings
    profiles := Map()
    disabledApps := Map()
    try profileIndex := IniRead(g_ini, "Profiles")
    catch
        profileIndex := ""

    loop parse profileIndex, "`n", "`r" {
        separator := InStr(A_LoopField, "=")
        if !separator
            continue
        appName := NormalizeAppName(SubStr(A_LoopField, 1, separator - 1))
        enabled := Trim(SubStr(A_LoopField, separator + 1))
        if (appName = "" || (enabled != "0" && enabled != "1"))
            continue

        section := "Profile:" appName
        values := Map()
        for definition in SettingDefinitions() {
            key := definition[1]
            fallback := g_defaultRuntimeSettings[key]
            values[key] := definition[6] ? CfgProfileI(section, key, fallback) : CfgProfileF(section, key, fallback)
        }
        profiles[appName] := values
        if (enabled = "0")
            disabledApps[appName] := true
    }
    g_profiles := profiles
    g_disabledApps := disabledApps
}

CfgProfileF(section, key, default) {
    global g_ini
    try return Float(Trim(IniRead(g_ini, section, key)))
    catch
        return default
}

CfgProfileI(section, key, default) {
    global g_ini
    try return Integer(Trim(IniRead(g_ini, section, key)))
    catch
        return default
}

RefreshSettingsCache() {
    global g_defaultRuntimeSettings, g_previousApp
    g_defaultRuntimeSettings := CurrentDefaultSettings()
    LoadProfiles()
    g_previousApp := ""
}

GetScrollSettings(hwnd) {
    global g_profiles, g_defaultRuntimeSettings, g_activeApp
    try appName := NormalizeAppName(WinGetProcessName("ahk_id " hwnd))
    catch
        appName := ""
    g_activeApp := appName
    return g_profiles.Has(appName) ? g_profiles[appName] : g_defaultRuntimeSettings
}

IsAppDisabled(hwnd) {
    global g_disabledApps
    try appName := NormalizeAppName(WinGetProcessName("ahk_id " hwnd))
    catch
        return false
    return g_disabledApps.Has(appName)
}

StopScrollMomentum() {
    global g_debt, g_timer, g_combo, g_velocity, g_gen
    g_gen++
    g_debt := 0.0
    g_timer := false
    g_combo := 1.0
    g_velocity := 0.0
    SetTimer(AnimateScroll, 0)
}

ShouldAccelerateScroll() {
    MouseGetPos(,, &hWin)
    if IsAppDisabled(hWin) {
        StopScrollMomentum()
        return false
    }
    return true
}

RefreshSettingsCache()

; =====================================================================
;  Settings GUI
; =====================================================================
SettingDefinitions() {
    return [
        ["baseNotches",  L("Slow scroll amount", "低速時のスクロール量"),       L("Normal wheel notches per click", "ホイール1目盛りあたりの基本量"),       0.1, 20.0, false],
        ["maxNotches",   L("Maximum scroll amount", "最大スクロール量"),        L("Hard limit per wheel click", "ホイール1目盛りあたりの上限"),           1.0, 100.0, false],
        ["comboStep",    L("Momentum build-up", "加速の増加量"),               L("Boost added by each rapid click", "連続操作ごとに加わる加速量"),          0.0, 5.0, false],
        ["maxCombo",     L("Maximum momentum", "最大加速倍率"),                L("Maximum combo multiplier", "連続操作による加速倍率の上限"),           1.0, 20.0, false],
        ["comboWindow",  L("Combo interval (ms)", "連続判定時間 (ms)"),        L("Time in which clicks build momentum", "この時間内の操作で加速を継続"),     50, 2000, true],
        ["friction",     L("Glide / friction", "滑らかさ／摩擦"),              L("Higher values glide for longer", "大きいほど長く滑らかに動く"),          0.5, 0.99, false],
        ["minDebt",      L("Stop threshold", "停止しきい値"),                 L("Higher values stop the tail earlier", "大きいほど余韻を早く停止"),         0.001, 1.0, false],
        ["frameMs",      L("Frame interval (ms)", "フレーム間隔 (ms)"),        L("8 = ~120 Hz, 16 = ~60 Hz", "8 = 約120 Hz、16 = 約60 Hz"),            1, 100, true],
        ["velInfluence", L("Speed influence", "速度の影響度"),                 L("How strongly wheel speed accelerates", "ホイール速度による加速の強さ"),      0.0, 5.0, false],
        ["velSmoothing", L("Speed smoothing", "速度の平滑化"),                 L("Higher values react more gradually", "大きいほど緩やかに速度が変化"),       0.0, 0.99, false],
        ["velCap",       L("Maximum speed boost", "速度加速の上限"),            L("Limit for speed-based acceleration", "速度による加速量の上限"),            0.0, 20.0, false],
        ["velTimeout",   L("Speed reset delay (ms)", "速度リセット時間 (ms)"), L("Pause before speed memory is cleared", "速度の記憶を消去するまでの停止時間"), 50, 5000, true]
    ]
}

ReadCurrentSettings() {
    defaults := DefaultSettings()
    values := Map()
    for definition in SettingDefinitions() {
        key := definition[1]
        values[key] := definition[6] ? CfgI(key, defaults[key]) : CfgF(key, defaults[key])
    }
    return values
}

GetSelectedProfile() {
    global g_profileSelector, g_profileNames
    if !IsObject(g_profileSelector)
        return ""
    index := g_profileSelector.Value
    return (index >= 1 && index <= g_profileNames.Length) ? g_profileNames[index] : ""
}

RefreshProfileSelector(selectedApp := "") {
    global g_profileSelector, g_profileNames, g_profiles, g_disabledApps
    if !IsObject(g_profileSelector)
        return

    selectedApp := NormalizeAppName(selectedApp)
    labels := [L("Default (all applications)", "既定（すべてのアプリ）")]
    g_profileNames := [""]
    selectedIndex := 1
    for appName, settings in g_profiles {
        label := appName
        if g_disabledApps.Has(appName)
            label .= L(" (disabled)", "（無効）")
        labels.Push(label)
        g_profileNames.Push(appName)
        if (appName = selectedApp)
            selectedIndex := labels.Length
    }

    g_profileSelector.Delete()
    g_profileSelector.Add(labels)
    g_profileSelector.Choose(selectedIndex)
}

RefreshRunningApps(*) {
    global g_runningAppSelector
    if !IsObject(g_runningAppSelector)
        return

    seen := Map()
    appNames := []
    for hwnd in WinGetList() {
        try appName := NormalizeAppName(WinGetProcessName("ahk_id " hwnd))
        catch
            continue
        if (appName = "" || seen.Has(appName))
            continue
        seen[appName] := true
        appNames.Push(appName)
    }

    g_runningAppSelector.Delete()
    if appNames.Length {
        g_runningAppSelector.Add(appNames)
        g_runningAppSelector.Choose(1)
    } else {
        g_runningAppSelector.Add([L("No running applications found", "実行中のアプリが見つかりません")])
        g_runningAppSelector.Choose(1)
    }
}

ProfileSelectionChanged(*) {
    global g_profiles, g_disabledApps, g_disableProfileCheckbox, g_settingControls
    appName := GetSelectedProfile()
    if (appName != "" && g_profiles.Has(appName))
        FillSettingsForm(g_profiles[appName])
    else
        FillSettingsForm(ReadCurrentSettings())

    isAppProfile := appName != ""
    disabled := isAppProfile && g_disabledApps.Has(appName)
    if IsObject(g_disableProfileCheckbox) {
        g_disableProfileCheckbox.Enabled := isAppProfile
        g_disableProfileCheckbox.Value := disabled
    }
    for key, control in g_settingControls
        control.Enabled := !disabled
}

ProfileDisabledChanged(*) {
    global g_disableProfileCheckbox, g_settingControls
    disabled := IsObject(g_disableProfileCheckbox) && g_disableProfileCheckbox.Value
    for key, control in g_settingControls
        control.Enabled := !disabled
}

AddApplicationProfile(*) {
    global g_ini, g_runningAppSelector, g_profiles
    if !IsObject(g_runningAppSelector) || !g_runningAppSelector.Value
        return
    appName := NormalizeAppName(g_runningAppSelector.Text)
    if (appName = "" || appName = NormalizeAppName(L("No running applications found", "実行中のアプリが見つかりません")))
        return

    if !g_profiles.Has(appName) {
        try {
            IniWrite(1, g_ini, "Profiles", appName)
            for key, value in CurrentDefaultSettings()
                IniWrite(value, g_ini, "Profile:" appName, key)
            ReloadConfig()
        } catch as err {
            MsgBox(err.Message, L("Could not create profile", "プロファイルを作成できませんでした"), "Iconx")
            return
        }
    }

    RefreshProfileSelector(appName)
    ProfileSelectionChanged()
}

DeleteApplicationProfile(*) {
    global g_ini
    appName := GetSelectedProfile()
    if (appName = "") {
        MsgBox(L("The default profile cannot be deleted.", "既定のプロファイルは削除できません。"), "Smooth Scroll", "Iconi")
        return
    }

    answer := MsgBox(L("Delete the profile for " appName "?", appName " のプロファイルを削除しますか？"),
        L("Delete application profile", "アプリ別プロファイルの削除"), "YesNo Icon?")
    if (answer != "Yes")
        return

    try {
        IniDelete(g_ini, "Profiles", appName)
        IniDelete(g_ini, "Profile:" appName)
        ReloadConfig()
    } catch as err {
        MsgBox(err.Message, L("Could not delete profile", "プロファイルを削除できませんでした"), "Iconx")
        return
    }
    RefreshProfileSelector()
    ProfileSelectionChanged()
}

PresetSettings(name) {
    switch name {
        case "Gentle":
            return Map("baseNotches", 1.0, "maxNotches", 6.0, "comboStep", 0.2, "maxCombo", 2.0,
                "comboWindow", 200, "friction", 0.80, "minDebt", 0.02, "frameMs", 8,
                "velInfluence", 0.2, "velSmoothing", 0.6, "velCap", 1.5, "velTimeout", 400)
        case "Floaty":
            return Map("baseNotches", 3.0, "maxNotches", 20.0, "comboStep", 0.8, "maxCombo", 6.0,
                "comboWindow", 350, "friction", 0.92, "minDebt", 0.005, "frameMs", 8,
                "velInfluence", 0.5, "velSmoothing", 0.3, "velCap", 4.0, "velTimeout", 800)
        default:
            return DefaultSettings()
    }
}

FillSettingsForm(values) {
    global g_settingControls
    for key, value in values
        g_settingControls[key].Value := value
}

ApplySettingsPreset(name, *) {
    FillSettingsForm(PresetSettings(name))
}

ParseSetting(definition) {
    global g_settingControls
    key := definition[1]
    label := definition[2]
    minimum := definition[4]
    maximum := definition[5]
    isInteger := definition[6]
    raw := Trim(g_settingControls[key].Value)

    pattern := isInteger ? "^\d+$" : "^(?:\d+(?:\.\d*)?|\.\d+)$"
    if !RegExMatch(raw, pattern)
        throw Error(L(label " must be a valid " (isInteger ? "whole number." : "number."),
            label "には有効な" (isInteger ? "整数" : "数値") "を入力してください。"))

    value := isInteger ? Integer(raw) : Float(raw)
    if (value < minimum || value > maximum)
        throw Error(L(label " must be between " minimum " and " maximum ".",
            label "は " minimum "～" maximum " の範囲で入力してください。"))
    return value
}

SaveSettings(*) {
    global g_ini, g_disableProfileCheckbox
    try {
        values := Map()
        for definition in SettingDefinitions()
            values[definition[1]] := ParseSetting(definition)

        if (values["maxNotches"] < values["baseNotches"])
            throw Error(L("Maximum scroll amount must be at least the slow scroll amount.",
                "最大スクロール量は低速時のスクロール量以上にしてください。"))

        appName := GetSelectedProfile()
        section := appName = "" ? "Settings" : "Profile:" appName
        if (appName != "")
            IniWrite(g_disableProfileCheckbox.Value ? 0 : 1, g_ini, "Profiles", appName)
        for key, value in values
            IniWrite(value, g_ini, section, key)

        ReloadConfig()
        RefreshProfileSelector(appName)
        ProfileSelectionChanged()
        target := appName = "" ? L("the default profile", "既定のプロファイル") : appName
        MsgBox(L("Settings for " target " were saved and applied immediately.",
            target " の設定を保存し、すぐに適用しました。"), "Smooth Scroll", "Iconi")
    } catch as err {
        MsgBox(err.Message, L("Invalid setting", "設定値が正しくありません"), "Iconx")
    }
}

ResetSettings(*) {
    appName := GetSelectedProfile()
    if (appName = "") {
        prompt := L("Restore all fields to the built-in Balanced defaults?", "すべての項目を内蔵の「標準」設定に戻しますか？")
        values := DefaultSettings()
    } else {
        prompt := L("Copy the current default profile into the fields for " appName "?",
            "現在の既定プロファイルの値を " appName " にコピーしますか？")
        values := CurrentDefaultSettings()
    }
    answer := MsgBox(prompt "`n`n" L("Changes are not saved until you click Save && Apply.",
        "［保存して適用］を押すまで変更は保存されません。"),
        L("Restore settings", "設定を復元"), "YesNo Icon?")
    if (answer = "Yes")
        FillSettingsForm(values)
}

HideSettings(*) {
    global g_settingsGui
    g_settingsGui.Hide()
}

ShowSettings(*) {
    global g_settingsGui, g_settingControls, g_profileSelector, g_runningAppSelector, g_disableProfileCheckbox

    if IsObject(g_settingsGui) {
        selectedApp := GetSelectedProfile()
        RefreshProfileSelector(selectedApp)
        RefreshRunningApps()
        ProfileSelectionChanged()
        g_settingsGui.Show()
        return
    }

    g_settingsGui := Gui("+MinSize700x720", L("Smooth Scroll Settings", "Smooth Scroll 設定"))
    g_settingsGui.SetFont("s9", "Segoe UI")
    g_settingsGui.OnEvent("Close", HideSettings)
    g_settingsGui.OnEvent("Escape", HideSettings)

    g_settingsGui.SetFont("s15 w600")
    g_settingsGui.AddText("xm ym", L("Smooth Scroll Settings", "Smooth Scroll 設定"))
    g_settingsGui.SetFont("s9 w400")
    g_settingsGui.AddText("xm y+4 c666666", L("Create per-application profiles or tune the default used by every other application.",
        "アプリ別プロファイルを作成するか、すべてのアプリで使う既定値を調整します。"))

    g_settingsGui.AddGroupBox("xm y+14 w680 h128", L("Application profile", "アプリ別プロファイル"))
    g_settingsGui.AddText("x30 yp+23 w300", L("Profile being edited", "編集中のプロファイル"))
    g_profileSelector := g_settingsGui.AddDropDownList("x30 y+3 w300", [L("Default (all applications)", "既定（すべてのアプリ）")])
    deleteProfileButton := g_settingsGui.AddButton("x345 yp-1 w145", L("Delete profile", "プロファイルを削除"))
    g_disableProfileCheckbox := g_settingsGui.AddCheckBox("x505 yp+4 w155", L("Disable for this app", "このアプリでは無効"))

    g_settingsGui.AddText("x30 y+15 w300", L("Create a profile for a running application", "実行中のアプリ用プロファイルを作成"))
    g_runningAppSelector := g_settingsGui.AddDropDownList("x30 y+3 w300", [L("Scanning...", "検索中...")])
    refreshAppsButton := g_settingsGui.AddButton("x345 yp-1 w100", L("Refresh", "更新"))
    addProfileButton := g_settingsGui.AddButton("x455 yp w190", L("Create application profile", "プロファイルを作成"))

    g_profileSelector.OnEvent("Change", ProfileSelectionChanged)
    deleteProfileButton.OnEvent("Click", DeleteApplicationProfile)
    g_disableProfileCheckbox.OnEvent("Click", ProfileDisabledChanged)
    refreshAppsButton.OnEvent("Click", RefreshRunningApps)
    addProfileButton.OnEvent("Click", AddApplicationProfile)

    g_settingsGui.AddGroupBox("xm y+14 w680 h62", L("Presets for the selected profile", "選択したプロファイルのプリセット"))
    gentleButton := g_settingsGui.AddButton("xp+14 yp+24 w105", L("Gentle", "控えめ"))
    balancedButton := g_settingsGui.AddButton("x+10 w105", L("Balanced", "標準"))
    floatyButton := g_settingsGui.AddButton("x+10 w105", L("Floaty", "ゆったり"))
    gentleButton.OnEvent("Click", ApplySettingsPreset.Bind("Gentle"))
    balancedButton.OnEvent("Click", ApplySettingsPreset.Bind("Balanced"))
    floatyButton.OnEvent("Click", ApplySettingsPreset.Bind("Floaty"))

    g_settingControls := Map()
    definitions := SettingDefinitions()
    loop 2 {
        column := A_Index
        startX := column = 1 ? 20 : 360
        rowStart := column = 1 ? 1 : 7
        rowEnd := column = 1 ? 6 : 12
        y := 292
        loop rowEnd - rowStart + 1 {
            definition := definitions[rowStart + A_Index - 1]
            key := definition[1]
            g_settingsGui.SetFont("s9 w600")
            g_settingsGui.AddText("x" startX " y" y " w195", definition[2])
            g_settingsGui.SetFont("s9 w400")
            g_settingControls[key] := g_settingsGui.AddEdit("x" (startX + 205) " y" (y - 3) " w75", "")
            g_settingsGui.AddText("x" startX " y+2 w280 c666666", definition[3])
            y += 62
        }
    }

    saveButton := g_settingsGui.AddButton("xm y670 w130 h34 Default", L("Save && Apply", "保存して適用"))
    resetButton := g_settingsGui.AddButton("x+10 w160 h34", L("Use default values", "既定値を使用"))
    cancelButton := g_settingsGui.AddButton("x+230 w130 h34", L("Close", "閉じる"))
    saveButton.OnEvent("Click", SaveSettings)
    resetButton.OnEvent("Click", ResetSettings)
    cancelButton.OnEvent("Click", HideSettings)

    RefreshProfileSelector()
    RefreshRunningApps()
    ProfileSelectionChanged()
    g_settingsGui.Show("w700 h720")
}

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
    global g_activeApp, g_previousApp, g_activeFriction, g_activeMinDebt

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
    settings := GetScrollSettings(hWin)
    if (g_activeApp != g_previousApp) {
        g_debt := 0.0
        g_combo := 1.0
        g_velocity := 0.0
        delta := 0
        g_previousApp := g_activeApp
    }
    baseNotches := settings["baseNotches"]
    maxNotches := settings["maxNotches"]
    comboStep := settings["comboStep"]
    maxCombo := settings["maxCombo"]
    comboWindow := settings["comboWindow"]
    frameMs := settings["frameMs"]
    velInfluence := settings["velInfluence"]
    velSmoothing := settings["velSmoothing"]
    velCap := settings["velCap"]
    velTimeout := settings["velTimeout"]
    g_activeFriction := settings["friction"]
    g_activeMinDebt := settings["minDebt"]
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
    if (delta > 0 && delta < comboWindow)
        g_combo := Min(g_combo + comboStep, maxCombo)
    else
        g_combo := 1.0

    ; Velocity tracking
    if (delta > 0 && delta < velTimeout) {
        spd        := 300.0 / delta
        g_velocity := g_velocity * velSmoothing + spd * (1.0 - velSmoothing)
    } else {
        g_velocity := 0.0
    }

    ; Budget calculation
    velContrib := Min(g_velocity, velCap)
    budget     := baseNotches * g_combo * (1.0 + velContrib * velInfluence)
    budget     := Min(budget, maxNotches)

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
    if g_debt > g_activeMinDebt {
        g_timer := true
        SetTimer(AnimateScroll, frameMs)
    }
}

; =====================================================================
;  AnimateScroll — timer: drains debt via fractional WM_MOUSEWHEEL
; =====================================================================
AnimateScroll() {
    global g_debt, g_dir, g_timer, g_srcWin, g_srcL, g_srcT, g_srcR, g_srcB, g_gen
    global g_activeFriction, g_activeMinDebt

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

    if (g_debt < g_activeMinDebt) {
        g_debt  := 0.0
        g_timer := false
        SetTimer(AnimateScroll, 0)
        return
    }

    chunk  := g_debt * (1.0 - g_activeFriction)
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
A_TrayMenu.Add(L("Settings...", "設定..."), ShowSettings)
A_TrayMenu.Default := L("Settings...", "設定...")
A_TrayMenu.Add()
A_TrayMenu.Add(L("Reload Config", "設定を再読み込み"), (*) => ReloadConfig())
A_TrayMenu.Add(L("Edit Config", "設定ファイルを編集"), (*) => Run("notepad.exe `"" g_ini "`""))
A_TrayMenu.Add()
languageMenu := Menu()
autoLanguageLabel := L("Automatic (Windows setting)", "自動（Windows の設定）")
japaneseLanguageLabel := L("Japanese", "日本語")
englishLanguageLabel := L("English", "英語")
languageMenu.Add(autoLanguageLabel, SetLanguageMode.Bind("auto"))
languageMenu.Add(japaneseLanguageLabel, SetLanguageMode.Bind("ja"))
languageMenu.Add(englishLanguageLabel, SetLanguageMode.Bind("en"))
selectedLanguageLabel := g_languageMode = "ja" ? japaneseLanguageLabel
    : g_languageMode = "en" ? englishLanguageLabel : autoLanguageLabel
languageMenu.Check(selectedLanguageLabel)
A_TrayMenu.Add(L("Language", "言語"), languageMenu)
A_TrayMenu.Add()
A_TrayMenu.Add(L("Reload Script", "スクリプトを再起動"), (*) => Reload())
A_TrayMenu.Add(L("Exit", "終了"), (*) => ExitApp())

; =====================================================================
;  Hotkeys
; =====================================================================
#HotIf ShouldAccelerateScroll()
WheelUp::ScrollAccel(1)
WheelDown::ScrollAccel(-1)
#HotIf
