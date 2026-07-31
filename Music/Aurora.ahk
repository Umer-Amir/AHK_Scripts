#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; AURORA SYSTEM AUDIO SCOPE — STABLE RENDERER
; AutoHotkey v2 — dependency-free Windows playback meter visualizer
;
; Stable renderer changes:
;   • No child drawing control
;   • No WS_EX_COMPOSITED
;   • WM_PAINT reuses the same complete back buffer
;   • Background erase suppressed to prevent flashes
;
; Quality-of-life additions:
;   • Current playback-device name
;   • Minimize control for the frameless window
;   • Mouse-wheel and keyboard gain controls
;   • Pause, reset, topmost and close keyboard commands
;   • dBFS peak readout and clearer on-screen control hints
;
; Visual language:
;   • Near-black foundation
;   • Dark green illumination on the left
;   • Dark purple illumination on the right
;   • Teal interactive accent
;   • Cyan → blue → purple → magenta waveform spectrum
;   • Thin borders, restrained glow, tracked uppercase typography
;
; AUDIO NOTE:
; Windows IAudioMeterInformation exposes playback peak amplitude, not raw PCM
; samples. This program therefore renders a polished mirrored amplitude envelope
; rather than a sample-accurate audio-frequency waveform.
; ============================================================================

DllCall("user32\SetProcessDPIAware")

; --------------------------------- Settings ---------------------------------
global TARGET_FPS       := 60
global WINDOW_WIDTH     := 1040
global WINDOW_HEIGHT    := 590
global SCOPE_X          := 40
global SCOPE_Y          := 138
global SCOPE_WIDTH      := 960
global SCOPE_HEIGHT     := 300
global PIXELS_PER_FRAME := 4
global GAIN             := 2.25
global SMOOTHING        := 0.32

; Controls while the Aurora window is active:
;   Mouse wheel / Up / Plus  — increase gain
;   Down / Minus             — decrease gain
;   Space                    — pause or resume
;   R                        — clear the signal history
;   T                        — toggle always-on-top
;   M                        — minimize
;   Escape                   — exit

; ---------------------------------- Audio -----------------------------------
global IID_METER := "{C02216F6-8C67-4B5B-9D00-D008E73E0064}"
global AudioMeter := 0
global AudioDeviceName := "DEFAULT PLAYBACK ENDPOINT"

; ---------------------------------- State -----------------------------------
global Running := true
global Paused := false
global ScopeGui := 0
global WindowHwnd := 0
global History := []
global HistoryHead := 1
global PreviousAmplitude := 0.0
global SmoothedPeak := 0.0
global LatestPeak := 0.0
global HeldPeak := 0.0
global ActualFps := 0.0
global FrameCount := 0
global FpsStartTime := 0.0
global TimerResolutionEnabled := false
global HoverButton := ""
global MouseTracking := false
global AlwaysOnTop := true

; ------------------------------ Hit-test areas ------------------------------
global MinimizeRect  := {x: 936, y: 24,  w: 32,  h: 32}
global CloseRect     := {x: 980, y: 24,  w: 32,  h: 32}
global GainMinusRect := {x: 744, y: 518, w: 42,  h: 38}
global GainPlusRect  := {x: 850, y: 518, w: 42,  h: 38}
global PauseRect     := {x: 906, y: 518, w: 94,  h: 38}

; ----------------------------------- GDI ------------------------------------
global MemDC := 0
global BackBitmap := 0
global OldBitmap := 0
global PaintRect := 0
global NoPen := 0
global NoBrush := 0

global BaseBrush := 0
global PanelBrush := 0
global InnerPanelBrush := 0
global ChipBrush := 0
global ButtonBrush := 0
global ButtonHoverBrush := 0
global ButtonActiveBrush := 0
global DangerHoverBrush := 0
global MeterInactiveBrush := 0
global TealBrush := 0
global TealGlowBrush1 := 0
global TealGlowBrush2 := 0

global BorderPen := 0
global InnerBorderPen := 0
global GridPen := 0
global FineGridPen := 0
global CentrePen := 0
global TealPen := 0
global TealDimPen := 0

global WaveColors := []
global WaveCorePens := []
global WaveGlowPens := []
global WaveBarPens := []
global WaveMeterBrushes := []
global UpperWavePoints := 0
global LowerWavePoints := 0

global FontTitle := 0
global FontLabel := 0
global FontSmall := 0
global FontValue := 0
global FontButton := 0

OnExit(Cleanup)

if !ConnectAudioMeter() {
    MsgBox(
        "Unable to access the default Windows playback device.`n`n"
        . "Confirm that an active output device is selected and try again.",
        "Aurora Audio Scope",
        "Iconx"
    )
    ExitApp()
}

BuildGui()
InitializeHistory()
InitializeGraphics()
RegisterMouseHandlers()

if (DllCall("winmm\timeBeginPeriod", "UInt", 1, "UInt") = 0)
    TimerResolutionEnabled := true

FpsStartTime := QpcSeconds()
RunFrameLoop()


; ============================================================================
; Audio
; ============================================================================

ConnectAudioMeter() {
    global AudioMeter, IID_METER

    if AudioMeter {
        try ObjRelease(AudioMeter)
        AudioMeter := 0
    }

    try {
        AudioMeter := SoundGetInterface(IID_METER)
        if AudioMeter
            RefreshAudioDeviceName()
        return AudioMeter != 0
    } catch {
        AudioMeter := 0
        return false
    }
}

RefreshAudioDeviceName() {
    global AudioDeviceName

    try {
        name := Trim(SoundGetName())
        AudioDeviceName := name != "" ? name : "DEFAULT PLAYBACK ENDPOINT"
    } catch {
        AudioDeviceName := "DEFAULT PLAYBACK ENDPOINT"
    }
}

ReadPeakLevel() {
    global AudioMeter
    peak := 0.0

    try {
        ; IAudioMeterInformation::GetPeakValue — COM method index 3.
        ComCall(3, AudioMeter, "Float*", &peak)
    } catch {
        ; A default-device switch can invalidate the interface.
        if ConnectAudioMeter() {
            try ComCall(3, AudioMeter, "Float*", &peak)
            catch
                peak := 0.0
        }
    }

    return Max(0.0, Min(1.0, peak))
}


; ============================================================================
; GUI and interaction
; ============================================================================

BuildGui() {
    global ScopeGui, WindowHwnd, WINDOW_WIDTH, WINDOW_HEIGHT

    ; Draw directly into the top-level window. A child Text control caused
    ; Windows and the script to repaint the same pixels independently.
    ScopeGui := Gui(
        "+AlwaysOnTop -Caption +ToolWindow",
        "Aurora System Audio Scope"
    )
    ScopeGui.BackColor := "07090D"
    ScopeGui.MarginX := 0
    ScopeGui.MarginY := 0
    ScopeGui.OnEvent("Close", StopApplication)
    ScopeGui.Show("w" WINDOW_WIDTH " h" WINDOW_HEIGHT)

    WindowHwnd := ScopeGui.Hwnd
}

RegisterMouseHandlers() {
    OnMessage(0x000F, HandlePaint)       ; WM_PAINT
    OnMessage(0x0014, HandleEraseBkgnd)  ; WM_ERASEBKGND
    OnMessage(0x0200, HandleMouseMove)   ; WM_MOUSEMOVE
    OnMessage(0x0201, HandleLButtonDown) ; WM_LBUTTONDOWN
    OnMessage(0x020A, HandleMouseWheel)  ; WM_MOUSEWHEEL
    OnMessage(0x0100, HandleKeyDown)     ; WM_KEYDOWN
    OnMessage(0x02A3, HandleMouseLeave)  ; WM_MOUSELEAVE
}

HandlePaint(wParam, lParam, msg, hwnd) {
    global WindowHwnd, MemDC, WINDOW_WIDTH, WINDOW_HEIGHT

    if (hwnd != WindowHwnd || !MemDC)
        return

    psSize := A_PtrSize = 8 ? 72 : 64
    paintStruct := Buffer(psSize, 0)
    paintDC := DllCall("user32\BeginPaint", "Ptr", hwnd, "Ptr", paintStruct.Ptr, "Ptr")

    if paintDC {
        BlitFrame(paintDC)
        DllCall("user32\EndPaint", "Ptr", hwnd, "Ptr", paintStruct.Ptr)
    }

    return 0
}

HandleEraseBkgnd(wParam, lParam, msg, hwnd) {
    global WindowHwnd

    ; The complete client area is supplied by the back buffer.
    if (hwnd = WindowHwnd)
        return 1
}

HandleMouseMove(wParam, lParam, msg, hwnd) {
    global WindowHwnd, HoverButton, MouseTracking

    if (hwnd != WindowHwnd)
        return

    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF
    newHover := ButtonAt(x, y)

    if (newHover != HoverButton) {
        HoverButton := newHover

        if (HoverButton != "")
            SetSystemCursor(32649) ; IDC_HAND
        else
            SetSystemCursor(32512) ; IDC_ARROW
    }

    if !MouseTracking {
        TrackMouseLeave(hwnd)
        MouseTracking := true
    }
}

HandleMouseLeave(*) {
    global HoverButton, MouseTracking
    HoverButton := ""
    MouseTracking := false
    SetSystemCursor(32512)
}

HandleLButtonDown(wParam, lParam, msg, hwnd) {
    global WindowHwnd, ScopeGui
    global MinimizeRect, CloseRect, GainMinusRect, GainPlusRect, PauseRect

    if (hwnd != WindowHwnd)
        return

    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF

    if PointInRect(x, y, CloseRect) {
        StopApplication()
        return 0
    }

    if PointInRect(x, y, MinimizeRect) {
        MinimizeWindow()
        return 0
    }

    if PointInRect(x, y, GainMinusRect) {
        DecreaseGain()
        return 0
    }

    if PointInRect(x, y, GainPlusRect) {
        IncreaseGain()
        return 0
    }

    if PointInRect(x, y, PauseRect) {
        TogglePause()
        return 0
    }

    ; The upper strip behaves like a custom title bar.
    if (y < 96) {
        DllCall("user32\ReleaseCapture")
        DllCall(
            "user32\SendMessage",
            "Ptr", ScopeGui.Hwnd,
            "UInt", 0x00A1, ; WM_NCLBUTTONDOWN
            "Ptr", 2,       ; HTCAPTION
            "Ptr", 0
        )
    }

    return 0
}

HandleMouseWheel(wParam, lParam, msg, hwnd) {
    global WindowHwnd

    if (hwnd != WindowHwnd)
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta & 0x8000)
        delta -= 0x10000

    if (delta > 0)
        IncreaseGain()
    else if (delta < 0)
        DecreaseGain()

    return 0
}

HandleKeyDown(wParam, lParam, msg, hwnd) {
    global WindowHwnd

    if (hwnd != WindowHwnd)
        return

    switch wParam {
        case 0x1B: ; Escape
            StopApplication()
        case 0x20: ; Space
            TogglePause()
        case 0x26, 0xBB, 0x6B: ; Up, OEM plus, numpad plus
            IncreaseGain()
        case 0x28, 0xBD, 0x6D: ; Down, OEM minus, numpad minus
            DecreaseGain()
        case 0x52: ; R
            ResetSignal()
        case 0x54: ; T
            ToggleAlwaysOnTop()
        case 0x4D: ; M
            MinimizeWindow()
    }

    return 0
}

ButtonAt(x, y) {
    global MinimizeRect, CloseRect, GainMinusRect, GainPlusRect, PauseRect

    if PointInRect(x, y, CloseRect)
        return "close"
    if PointInRect(x, y, MinimizeRect)
        return "minimize"
    if PointInRect(x, y, GainMinusRect)
        return "minus"
    if PointInRect(x, y, GainPlusRect)
        return "plus"
    if PointInRect(x, y, PauseRect)
        return "pause"
    return ""
}

PointInRect(x, y, rect) {
    return x >= rect.x
        && x < rect.x + rect.w
        && y >= rect.y
        && y < rect.y + rect.h
}

TrackMouseLeave(hwnd) {
    size := A_PtrSize = 8 ? 24 : 16
    tme := Buffer(size, 0)
    NumPut("UInt", size, tme, 0)
    NumPut("UInt", 0x00000002, tme, 4) ; TME_LEAVE
    NumPut("Ptr", hwnd, tme, 8)
    NumPut("UInt", 0, tme, 8 + A_PtrSize)
    DllCall("user32\TrackMouseEvent", "Ptr", tme.Ptr)
}

SetSystemCursor(cursorId) {
    cursor := DllCall(
        "user32\LoadCursor",
        "Ptr", 0,
        "Ptr", cursorId,
        "Ptr"
    )
    if cursor
        DllCall("user32\SetCursor", "Ptr", cursor)
}

TogglePause(*) {
    global Paused
    Paused := !Paused
}

IncreaseGain(*) {
    global GAIN
    GAIN := Min(5.00, Round(GAIN + 0.25, 2))
}

DecreaseGain(*) {
    global GAIN
    GAIN := Max(0.25, Round(GAIN - 0.25, 2))
}

ResetSignal(*) {
    global LatestPeak, SmoothedPeak, HeldPeak, PreviousAmplitude

    InitializeHistory()
    LatestPeak := 0.0
    SmoothedPeak := 0.0
    HeldPeak := 0.0
    PreviousAmplitude := 0.0
}

ToggleAlwaysOnTop(*) {
    global ScopeGui, AlwaysOnTop

    AlwaysOnTop := !AlwaysOnTop
    ScopeGui.Opt(AlwaysOnTop ? "+AlwaysOnTop" : "-AlwaysOnTop")
}

MinimizeWindow(*) {
    global WindowHwnd
    WinMinimize("ahk_id " WindowHwnd)
}

StopApplication(*) {
    global Running
    Running := false
}


; ============================================================================
; Frame pacing
; ============================================================================

RunFrameLoop() {
    global Running, TARGET_FPS

    frameDuration := 1.0 / TARGET_FPS
    nextFrameTime := QpcSeconds()

    while Running {
        now := QpcSeconds()

        if (now >= nextFrameTime) {
            UpdateAndRender(now)
            nextFrameTime += frameDuration

            ; Skip a catch-up burst after a long OS stall.
            if (now - nextFrameTime > frameDuration * 3)
                nextFrameTime := now + frameDuration
        }

        remaining := nextFrameTime - QpcSeconds()

        if (remaining > 0.002) {
            sleepMs := Floor((remaining - 0.001) * 1000)
            if (sleepMs > 0)
                DllCall("kernel32\Sleep", "UInt", sleepMs)
        } else {
            DllCall("kernel32\Sleep", "UInt", 0)
        }

        ; Dispatch pending GUI messages and event callbacks.
        Sleep(-1)
    }

    ExitApp()
}

QpcSeconds() {
    static frequency := GetQpcFrequency()
    counter := 0
    DllCall("kernel32\QueryPerformanceCounter", "Int64*", &counter)
    return counter / frequency
}

GetQpcFrequency() {
    frequency := 0
    DllCall("kernel32\QueryPerformanceFrequency", "Int64*", &frequency)
    return frequency
}


; ============================================================================
; Signal processing
; ============================================================================

InitializeHistory() {
    global History, HistoryHead, SCOPE_WIDTH

    History := []
    Loop SCOPE_WIDTH
        History.Push(0.0)

    HistoryHead := 1
}

UpdateAndRender(now) {
    global Paused, LatestPeak, SmoothedPeak, HeldPeak
    global GAIN, SMOOTHING
    global FrameCount, FpsStartTime, ActualFps

    if !Paused {
        LatestPeak := ReadPeakLevel()
        SmoothedPeak += (LatestPeak - SmoothedPeak) * SMOOTHING
        HeldPeak := Max(LatestPeak, HeldPeak * 0.965)
        AppendAmplitude(Min(1.0, SmoothedPeak * GAIN))
    } else {
        HeldPeak *= 0.985
    }

    DrawInterface()

    FrameCount += 1
    elapsed := now - FpsStartTime

    if (elapsed >= 1.0) {
        ActualFps := FrameCount / elapsed
        FrameCount := 0
        FpsStartTime := now
    }
}

AppendAmplitude(amplitude) {
    global History, HistoryHead, PreviousAmplitude
    global PIXELS_PER_FRAME, SCOPE_WIDTH

    Loop PIXELS_PER_FRAME {
        t := A_Index / PIXELS_PER_FRAME
        point := PreviousAmplitude + (amplitude - PreviousAmplitude) * t
        History[HistoryHead] := point
        HistoryHead := Mod(HistoryHead, SCOPE_WIDTH) + 1
    }

    PreviousAmplitude := amplitude
}

HistoryValue(logicalIndex) {
    global History, HistoryHead, SCOPE_WIDTH
    physicalIndex := Mod(HistoryHead + logicalIndex - 2, SCOPE_WIDTH) + 1
    return History[physicalIndex]
}


; ============================================================================
; Rendering
; ============================================================================

DrawInterface() {
    global MemDC, PaintRect, WINDOW_WIDTH, WINDOW_HEIGHT
    global BaseBrush, PanelBrush, InnerPanelBrush, BorderPen, InnerBorderPen
    global NoBrush

    ; Base.
    DllCall("user32\FillRect", "Ptr", MemDC, "Ptr", PaintRect.Ptr, "Ptr", BaseBrush)

    ; Opposing ambient illumination.
    GradientRect(MemDC, 0, 0, 470, WINDOW_HEIGHT, RGB(5, 34, 27), RGB(7, 9, 13))
    GradientRect(MemDC, 570, 0, WINDOW_WIDTH, WINDOW_HEIGHT, RGB(7, 9, 13), RGB(34, 12, 43))

    ; Extremely restrained top spectral line.
    DrawSpectrumLine(MemDC, 0, 0, WINDOW_WIDTH, 2)

    ; Main shell.
    SelectGdiObject(MemDC, PanelBrush)
    SelectGdiObject(MemDC, BorderPen)
    DllCall("gdi32\RoundRect", "Ptr", MemDC, "Int", 14, "Int", 14,
        "Int", WINDOW_WIDTH - 14, "Int", WINDOW_HEIGHT - 14, "Int", 20, "Int", 20)

    ; Inner shell border.
    SelectGdiObject(MemDC, NoBrush)
    SelectGdiObject(MemDC, InnerBorderPen)
    DllCall("gdi32\RoundRect", "Ptr", MemDC, "Int", 20, "Int", 20,
        "Int", WINDOW_WIDTH - 20, "Int", WINDOW_HEIGHT - 20, "Int", 16, "Int", 16)

    DrawHeader()
    DrawScopePanel()
    DrawFooter()
    PresentFrame()
}

DrawHeader() {
    global MemDC, FontTitle, FontLabel, FontSmall
    global TealBrush, NoPen, HoverButton, MinimizeRect, CloseRect, InnerBorderPen
    global AudioDeviceName, Paused

    ; Live indicator.
    SelectGdiObject(MemDC, NoPen)
    SelectGdiObject(MemDC, TealBrush)
    DllCall("gdi32\Ellipse", "Ptr", MemDC, "Int", 42, "Int", 38, "Int", 50, "Int", 46)

    DrawTrackedText(MemDC, "AURORA", 64, 31, 4, FontTitle, RGB(245, 248, 250))
    DrawTrackedText(MemDC, "SYSTEM AUDIO SCOPE", 65, 62, 2, FontSmall, RGB(126, 139, 151))

    DrawChip(646, 35, 106, 28, "LOOPBACK", RGB(46, 224, 177))
    DrawChip(764, 35, 70, 28, "60 HZ", RGB(51, 194, 255))
    DrawChip(846, 35, 72, 28, Paused ? "PAUSED" : "LIVE",
        Paused ? RGB(172, 113, 255) : RGB(216, 68, 228))

    ; Frameless window controls.
    DrawIconButton(MinimizeRect, "−", HoverButton = "minimize")
    DrawIconButton(CloseRect, "×", HoverButton = "close", true)

    ; Fine divider.
    SelectGdiObject(MemDC, InnerBorderPen)
    DrawLine(MemDC, 40, 96, 1000, 96)

    deviceLabel := FitTrackedText(MemDC, StrUpper(AudioDeviceName), 520, 1, FontLabel)
    DrawTrackedText(MemDC, deviceLabel, 40, 108, 1, FontLabel, RGB(147, 160, 171))
    DrawTrackedTextRight(MemDC, "PEAK AMPLITUDE / MIRRORED ENVELOPE", 1000, 108, 1, FontLabel, RGB(91, 105, 118))
}

DrawScopePanel() {
    global MemDC, SCOPE_X, SCOPE_Y, SCOPE_WIDTH, SCOPE_HEIGHT
    global InnerPanelBrush, InnerBorderPen, GridPen, FineGridPen, CentrePen
    global NoPen, TealBrush, HeldPeak, SmoothedPeak, GAIN
    global FontSmall, FontLabel

    left := SCOPE_X
    top := SCOPE_Y
    right := SCOPE_X + SCOPE_WIDTH
    bottom := SCOPE_Y + SCOPE_HEIGHT

    ; Scope well.
    SelectGdiObject(MemDC, InnerPanelBrush)
    SelectGdiObject(MemDC, InnerBorderPen)
    DllCall("gdi32\RoundRect", "Ptr", MemDC, "Int", left, "Int", top,
        "Int", right, "Int", bottom, "Int", 14, "Int", 14)

    ; Subtle left/right internal illumination.
    GradientRect(MemDC, left + 2, top + 2, left + 300, bottom - 2,
        RGB(7, 31, 26), RGB(8, 14, 19))
    GradientRect(MemDC, right - 300, top + 2, right - 2, bottom - 2,
        RGB(8, 14, 19), RGB(29, 12, 39))

    ; Fine grid.
    SelectGdiObject(MemDC, FineGridPen)
    x := left + 24
    while (x < right) {
        DrawLine(MemDC, x, top + 18, x, bottom - 18)
        x += 32
    }

    y := top + 26
    while (y < bottom) {
        DrawLine(MemDC, left + 18, y, right - 18, y)
        y += 30
    }

    ; Major grid.
    SelectGdiObject(MemDC, GridPen)
    x := left + 64
    while (x < right) {
        DrawLine(MemDC, x, top + 14, x, bottom - 14)
        x += 128
    }

    y := top + 60
    while (y < bottom) {
        DrawLine(MemDC, left + 14, y, right - 14, y)
        y += 60
    }

    centreY := top + Floor(SCOPE_HEIGHT / 2)
    SelectGdiObject(MemDC, CentrePen)
    DrawLine(MemDC, left + 14, centreY, right - 14, centreY)

    ; Scale marks.
    DrawTrackedText(MemDC, "+1.0", left + 15, top + 12, 1, FontSmall, RGB(76, 94, 106))
    DrawTrackedText(MemDC, "0.0", left + 15, centreY - 20, 1, FontSmall, RGB(76, 94, 106))
    DrawTrackedText(MemDC, "-1.0", left + 15, bottom - 30, 1, FontSmall, RGB(76, 94, 106))

    BuildWavePointBuffers()
    DrawEnvelopeBars()
    DrawWavePass(true)
    DrawWavePass(false)
    DrawCurrentPoint()

    ; Peak hold marker at the far right.
    peakY := centreY - Round(Min(1.0, HeldPeak * GAIN) * (SCOPE_HEIGHT * 0.40))
    SelectGdiObject(MemDC, NoPen)
    SelectGdiObject(MemDC, TealBrush)
    DllCall("gdi32\Rectangle", "Ptr", MemDC,
        "Int", right - 18, "Int", peakY - 1, "Int", right - 8, "Int", peakY + 1)
}

DrawEnvelopeBars() {
    global MemDC, SCOPE_X, SCOPE_Y, SCOPE_WIDTH, SCOPE_HEIGHT
    global WaveBarPens, WaveColors

    centreY := SCOPE_Y + Floor(SCOPE_HEIGHT / 2)
    maxHeight := Floor(SCOPE_HEIGHT * 0.40)
    colorCount := WaveColors.Length

    i := 1
    while (i <= SCOPE_WIDTH) {
        amplitude := HistoryValue(i)
        height := Round(amplitude * maxHeight)
        colorIndex := Min(colorCount, Floor((i - 1) * colorCount / SCOPE_WIDTH) + 1)
        SelectGdiObject(MemDC, WaveBarPens[colorIndex])
        x := SCOPE_X + i - 1
        DrawLine(MemDC, x, centreY - height, x, centreY + height)
        i += 5
    }
}

BuildWavePointBuffers() {
    global UpperWavePoints, LowerWavePoints
    global SCOPE_X, SCOPE_Y, SCOPE_WIDTH, SCOPE_HEIGHT

    centreY := SCOPE_Y + Floor(SCOPE_HEIGHT / 2)
    maxHeight := Floor(SCOPE_HEIGHT * 0.40)

    Loop SCOPE_WIDTH {
        i := A_Index
        x := SCOPE_X + i - 1
        height := Round(HistoryValue(i) * maxHeight)
        offset := (i - 1) * 8

        NumPut("Int", x, UpperWavePoints, offset)
        NumPut("Int", centreY - height, UpperWavePoints, offset + 4)
        NumPut("Int", x, LowerWavePoints, offset)
        NumPut("Int", centreY + height, LowerWavePoints, offset + 4)
    }
}

DrawWavePass(useGlow) {
    global MemDC, SCOPE_WIDTH
    global WaveCorePens, WaveGlowPens, WaveColors
    global UpperWavePoints, LowerWavePoints

    pens := useGlow ? WaveGlowPens : WaveCorePens
    colorCount := WaveColors.Length
    segmentSize := Ceil(SCOPE_WIDTH / colorCount)

    Loop colorCount {
        i := A_Index
        startPoint := 1 + (i - 1) * segmentSize
        endPoint := Min(SCOPE_WIDTH, i * segmentSize)

        if (startPoint > SCOPE_WIDTH)
            break

        ; Overlap one point so adjacent color segments remain connected.
        if (i > 1)
            startPoint -= 1

        pointCount := endPoint - startPoint + 1
        byteOffset := (startPoint - 1) * 8

        SelectGdiObject(MemDC, pens[i])
        DllCall(
            "gdi32\Polyline",
            "Ptr", MemDC,
            "Ptr", UpperWavePoints.Ptr + byteOffset,
            "Int", pointCount
        )
        DllCall(
            "gdi32\Polyline",
            "Ptr", MemDC,
            "Ptr", LowerWavePoints.Ptr + byteOffset,
            "Int", pointCount
        )
    }
}

DrawCurrentPoint() {
    global MemDC, SCOPE_X, SCOPE_Y, SCOPE_WIDTH, SCOPE_HEIGHT
    global TealGlowBrush1, TealGlowBrush2, TealBrush, NoPen

    amplitude := HistoryValue(SCOPE_WIDTH)
    centreY := SCOPE_Y + Floor(SCOPE_HEIGHT / 2)
    maxHeight := Floor(SCOPE_HEIGHT * 0.40)
    x := SCOPE_X + SCOPE_WIDTH - 1
    y := centreY - Round(amplitude * maxHeight)

    SelectGdiObject(MemDC, NoPen)

    SelectGdiObject(MemDC, TealGlowBrush1)
    DllCall("gdi32\Ellipse", "Ptr", MemDC, "Int", x - 10, "Int", y - 10, "Int", x + 10, "Int", y + 10)

    SelectGdiObject(MemDC, TealGlowBrush2)
    DllCall("gdi32\Ellipse", "Ptr", MemDC, "Int", x - 6, "Int", y - 6, "Int", x + 6, "Int", y + 6)

    SelectGdiObject(MemDC, TealBrush)
    DllCall("gdi32\Ellipse", "Ptr", MemDC, "Int", x - 2, "Int", y - 2, "Int", x + 3, "Int", y + 3)
}

DrawFooter() {
    global MemDC, Paused, ActualFps, LatestPeak, SmoothedPeak, GAIN, TARGET_FPS
    global AlwaysOnTop
    global FontLabel, FontSmall, FontValue, FontButton
    global HoverButton, GainMinusRect, GainPlusRect, PauseRect
    global InnerBorderPen

    ; Section separator.
    SelectGdiObject(MemDC, InnerBorderPen)
    DrawLine(MemDC, 40, 472, 1000, 472)

    DrawTrackedText(MemDC, "SIGNAL", 40, 491, 2, FontLabel, RGB(106, 121, 132))
    DrawMeter(40, 521, 330, 10, Min(1.0, SmoothedPeak * GAIN))

    DrawTrackedText(MemDC, "PEAK", 404, 491, 2, FontLabel, RGB(106, 121, 132))
    DrawSimpleText(MemDC, Format("{:.3f}", LatestPeak), 404, 518, FontValue, RGB(241, 245, 247))
    DrawTrackedText(MemDC, Format("{:.1f} DBFS", PeakToDbfs(LatestPeak)),
        404, 544, 1, FontSmall, RGB(106, 121, 132))

    DrawTrackedText(MemDC, "FRAME RATE", 514, 491, 2, FontLabel, RGB(106, 121, 132))
    fpsColor := ActualFps >= TARGET_FPS - 2 ? RGB(46, 224, 177) : RGB(255, 93, 170)
    DrawSimpleText(MemDC, Format("{:.1f}", ActualFps), 514, 518, FontValue, fpsColor)
    DrawTrackedText(MemDC, "FPS", 574, 528, 1, FontSmall, RGB(106, 121, 132))

    DrawTrackedText(MemDC, "GAIN", 660, 491, 2, FontLabel, RGB(106, 121, 132))
    DrawIconButton(GainMinusRect, "−", HoverButton = "minus")
    DrawSimpleTextCentered(MemDC, Format("{:.2f}", GAIN), 790, 521, 56, FontButton, RGB(238, 244, 246))
    DrawIconButton(GainPlusRect, "+", HoverButton = "plus")

    pauseLabel := Paused ? "RESUME" : "PAUSE"
    DrawTextButton(PauseRect, pauseLabel, HoverButton = "pause", Paused)

    stateText := Paused ? "SUSPENDED" : "RENDERING LIVE"
    if AlwaysOnTop
        stateText .= " / PINNED"
    stateColor := Paused ? RGB(172, 113, 255) : RGB(46, 224, 177)
    DrawTrackedTextRight(MemDC, stateText, 1000, 562, 1, FontSmall, stateColor)
    DrawTrackedText(MemDC, "SPACE PAUSE  •  WHEEL/↑↓ GAIN  •  R CLEAR  •  T PIN",
        40, 562, 1, FontSmall, RGB(68, 82, 94))
}

PeakToDbfs(amplitude) {
    if (amplitude <= 0.000001)
        return -60.0

    return Max(-60.0, 20.0 * Log(amplitude) / Log(10.0))
}

DrawMeter(x, y, width, height, value) {
    global MemDC, MeterInactiveBrush, WaveMeterBrushes, NoPen

    segmentCount := 28
    gap := 3
    segmentWidth := Floor((width - (segmentCount - 1) * gap) / segmentCount)
    activeCount := Round(value * segmentCount)
    colorCount := WaveMeterBrushes.Length

    SelectGdiObject(MemDC, NoPen)

    Loop segmentCount {
        i := A_Index
        left := x + (i - 1) * (segmentWidth + gap)
        right := left + segmentWidth

        if (i <= activeCount) {
            colorIndex := Min(colorCount, Floor((i - 1) * colorCount / segmentCount) + 1)
            SelectGdiObject(MemDC, WaveMeterBrushes[colorIndex])
        } else {
            SelectGdiObject(MemDC, MeterInactiveBrush)
        }

        DllCall("gdi32\RoundRect", "Ptr", MemDC,
            "Int", left, "Int", y, "Int", right, "Int", y + height,
            "Int", 4, "Int", 4)
    }
}

DrawChip(x, y, width, height, label, accentColor) {
    global MemDC, ChipBrush, InnerBorderPen, FontSmall

    SelectGdiObject(MemDC, ChipBrush)
    SelectGdiObject(MemDC, InnerBorderPen)
    DllCall("gdi32\RoundRect", "Ptr", MemDC,
        "Int", x, "Int", y, "Int", x + width, "Int", y + height,
        "Int", 10, "Int", 10)

    DrawSimpleTextCentered(MemDC, label, x, y + 7, width, FontSmall, accentColor)
}

DrawIconButton(rect, label, hovered, danger := false) {
    global MemDC, ButtonBrush, ButtonHoverBrush, DangerHoverBrush
    global InnerBorderPen, FontButton

    brush := hovered ? (danger ? DangerHoverBrush : ButtonHoverBrush) : ButtonBrush
    color := hovered && danger ? RGB(255, 96, 157) : RGB(202, 213, 220)

    SelectGdiObject(MemDC, brush)
    SelectGdiObject(MemDC, InnerBorderPen)
    DllCall("gdi32\RoundRect", "Ptr", MemDC,
        "Int", rect.x, "Int", rect.y,
        "Int", rect.x + rect.w, "Int", rect.y + rect.h,
        "Int", 10, "Int", 10)

    DrawSimpleTextCentered(MemDC, label, rect.x, rect.y + 8, rect.w, FontButton, color)
}

DrawTextButton(rect, label, hovered, active) {
    global MemDC, ButtonBrush, ButtonHoverBrush, ButtonActiveBrush
    global InnerBorderPen, FontButton

    brush := active ? ButtonActiveBrush : (hovered ? ButtonHoverBrush : ButtonBrush)
    color := active ? RGB(54, 232, 185) : RGB(230, 237, 241)

    SelectGdiObject(MemDC, brush)
    SelectGdiObject(MemDC, InnerBorderPen)
    DllCall("gdi32\RoundRect", "Ptr", MemDC,
        "Int", rect.x, "Int", rect.y,
        "Int", rect.x + rect.w, "Int", rect.y + rect.h,
        "Int", 12, "Int", 12)

    DrawSimpleTextCentered(MemDC, label, rect.x, rect.y + 11, rect.w, FontButton, color)
}

DrawSpectrumLine(dc, x, y, width, height) {
    colors := [
        RGB(38, 219, 166),
        RGB(39, 210, 225),
        RGB(48, 158, 255),
        RGB(98, 99, 255),
        RGB(167, 67, 255),
        RGB(235, 61, 198)
    ]

    segmentWidth := Ceil(width / colors.Length)
    Loop colors.Length {
        i := A_Index
        left := x + (i - 1) * segmentWidth
        right := Min(x + width, left + segmentWidth)
        nextColor := i < colors.Length ? colors[i + 1] : colors[i]
        GradientRect(dc, left, y, right, y + height, colors[i], nextColor)
    }
}

PresentFrame() {
    global WindowHwnd

    targetDC := DllCall("user32\GetDC", "Ptr", WindowHwnd, "Ptr")
    if !targetDC
        return

    BlitFrame(targetDC)
    DllCall("user32\ReleaseDC", "Ptr", WindowHwnd, "Ptr", targetDC)
}

BlitFrame(targetDC) {
    global MemDC, WINDOW_WIDTH, WINDOW_HEIGHT

    DllCall(
        "gdi32\BitBlt",
        "Ptr", targetDC,
        "Int", 0,
        "Int", 0,
        "Int", WINDOW_WIDTH,
        "Int", WINDOW_HEIGHT,
        "Ptr", MemDC,
        "Int", 0,
        "Int", 0,
        "UInt", 0x00CC0020 ; SRCCOPY
    )
}


; ============================================================================
; GDI initialization and helpers
; ============================================================================

InitializeGraphics() {
    global WindowHwnd, MemDC, BackBitmap, OldBitmap, PaintRect
    global WINDOW_WIDTH, WINDOW_HEIGHT, SCOPE_WIDTH
    global NoPen, NoBrush
    global BaseBrush, PanelBrush, InnerPanelBrush, ChipBrush
    global ButtonBrush, ButtonHoverBrush, ButtonActiveBrush, DangerHoverBrush
    global MeterInactiveBrush, TealBrush, TealGlowBrush1, TealGlowBrush2
    global BorderPen, InnerBorderPen, GridPen, FineGridPen, CentrePen
    global TealPen, TealDimPen
    global WaveColors, WaveCorePens, WaveGlowPens, WaveBarPens, WaveMeterBrushes
    global UpperWavePoints, LowerWavePoints
    global FontTitle, FontLabel, FontSmall, FontValue, FontButton

    windowDC := DllCall("user32\GetDC", "Ptr", WindowHwnd, "Ptr")
    if !windowDC
        throw Error("Unable to obtain the Aurora drawing context.")

    MemDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", windowDC, "Ptr")
    BackBitmap := DllCall(
        "gdi32\CreateCompatibleBitmap",
        "Ptr", windowDC,
        "Int", WINDOW_WIDTH,
        "Int", WINDOW_HEIGHT,
        "Ptr"
    )
    OldBitmap := SelectGdiObject(MemDC, BackBitmap)
    DllCall("user32\ReleaseDC", "Ptr", WindowHwnd, "Ptr", windowDC)

    NoPen := DllCall("gdi32\GetStockObject", "Int", 8, "Ptr")    ; NULL_PEN
    NoBrush := DllCall("gdi32\GetStockObject", "Int", 5, "Ptr") ; NULL_BRUSH

    BaseBrush := CreateBrush(RGB(7, 9, 13))
    PanelBrush := CreateBrush(RGB(9, 12, 17))
    InnerPanelBrush := CreateBrush(RGB(8, 14, 19))
    ChipBrush := CreateBrush(RGB(12, 18, 24))
    ButtonBrush := CreateBrush(RGB(13, 20, 27))
    ButtonHoverBrush := CreateBrush(RGB(17, 35, 39))
    ButtonActiveBrush := CreateBrush(RGB(13, 43, 37))
    DangerHoverBrush := CreateBrush(RGB(43, 18, 34))
    MeterInactiveBrush := CreateBrush(RGB(22, 31, 38))
    TealBrush := CreateBrush(RGB(46, 224, 177))
    TealGlowBrush1 := CreateBrush(RGB(11, 62, 54))
    TealGlowBrush2 := CreateBrush(RGB(18, 111, 91))

    BorderPen := CreatePen(RGB(27, 38, 47), 1)
    InnerBorderPen := CreatePen(RGB(21, 31, 39), 1)
    GridPen := CreatePen(RGB(24, 39, 46), 1)
    FineGridPen := CreatePen(RGB(15, 27, 33), 1, 2)
    CentrePen := CreatePen(RGB(45, 67, 76), 1, 2)
    TealPen := CreatePen(RGB(46, 224, 177), 1)
    TealDimPen := CreatePen(RGB(15, 69, 59), 1)

    WaveColors := [
        RGB(46, 224, 177),
        RGB(38, 226, 207),
        RGB(45, 195, 255),
        RGB(67, 139, 255),
        RGB(105, 99, 255),
        RGB(157, 76, 255),
        RGB(215, 63, 228),
        RGB(255, 76, 176)
    ]

    glowColors := [
        RGB(12, 80, 65),
        RGB(11, 80, 75),
        RGB(12, 65, 88),
        RGB(19, 48, 91),
        RGB(34, 33, 91),
        RGB(55, 27, 91),
        RGB(76, 25, 80),
        RGB(90, 27, 65)
    ]

    barColors := [
        RGB(16, 76, 63),
        RGB(14, 76, 72),
        RGB(15, 61, 82),
        RGB(22, 46, 82),
        RGB(36, 32, 82),
        RGB(53, 27, 82),
        RGB(68, 25, 72),
        RGB(78, 27, 59)
    ]

    Loop WaveColors.Length {
        i := A_Index
        WaveCorePens.Push(CreatePen(WaveColors[i], 2))
        WaveGlowPens.Push(CreatePen(glowColors[i], 5))
        WaveBarPens.Push(CreatePen(barColors[i], 1))
        WaveMeterBrushes.Push(CreateBrush(WaveColors[i]))
    }

    UpperWavePoints := Buffer(SCOPE_WIDTH * 8, 0)
    LowerWavePoints := Buffer(SCOPE_WIDTH * 8, 0)

    FontTitle := CreateFont(25, 650, "Segoe UI")
    FontLabel := CreateFont(10, 600, "Segoe UI")
    FontSmall := CreateFont(10, 500, "Segoe UI")
    FontValue := CreateFont(18, 600, "Segoe UI")
    FontButton := CreateFont(12, 650, "Segoe UI")

    PaintRect := Buffer(16, 0)
    NumPut("Int", 0, PaintRect, 0)
    NumPut("Int", 0, PaintRect, 4)
    NumPut("Int", WINDOW_WIDTH, PaintRect, 8)
    NumPut("Int", WINDOW_HEIGHT, PaintRect, 12)
}

CreateBrush(color) {
    return DllCall("gdi32\CreateSolidBrush", "UInt", color, "Ptr")
}

CreatePen(color, width := 1, style := 0) {
    return DllCall(
        "gdi32\CreatePen",
        "Int", style,
        "Int", width,
        "UInt", color,
        "Ptr"
    )
}

CreateFont(pixelHeight, weight := 400, face := "Segoe UI") {
    return DllCall(
        "gdi32\CreateFontW",
        "Int", -pixelHeight,
        "Int", 0,
        "Int", 0,
        "Int", 0,
        "Int", weight,
        "UInt", 0,
        "UInt", 0,
        "UInt", 0,
        "UInt", 1,
        "UInt", 0,
        "UInt", 0,
        "UInt", 5,
        "UInt", 0,
        "Str", face,
        "Ptr"
    )
}

GradientRect(dc, left, top, right, bottom, startColor, endColor) {
    vertices := Buffer(32, 0)
    mesh := Buffer(8, 0)

    PutGradientVertex(vertices, 0, left, top, startColor)
    PutGradientVertex(vertices, 16, right, bottom, endColor)
    NumPut("UInt", 0, mesh, 0)
    NumPut("UInt", 1, mesh, 4)

    DllCall(
        "msimg32\GradientFill",
        "Ptr", dc,
        "Ptr", vertices.Ptr,
        "UInt", 2,
        "Ptr", mesh.Ptr,
        "UInt", 1,
        "UInt", 0 ; GRADIENT_FILL_RECT_H
    )
}

PutGradientVertex(buffer, offset, x, y, color) {
    red := color & 0xFF
    green := (color >> 8) & 0xFF
    blue := (color >> 16) & 0xFF

    NumPut("Int", x, buffer, offset)
    NumPut("Int", y, buffer, offset + 4)
    NumPut("UShort", red * 257, buffer, offset + 8)
    NumPut("UShort", green * 257, buffer, offset + 10)
    NumPut("UShort", blue * 257, buffer, offset + 12)
    NumPut("UShort", 0, buffer, offset + 14)
}

DrawTrackedText(dc, text, x, y, spacing, font, color) {
    SelectGdiObject(dc, font)
    DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
    DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", color)

    cursorX := x
    Loop Parse text {
        char := A_LoopField
        DllCall("gdi32\TextOutW", "Ptr", dc, "Int", cursorX, "Int", y,
            "Str", char, "Int", StrLen(char))
        cursorX += MeasureTextWidth(dc, char) + spacing
    }
}

FitTrackedText(dc, text, maxWidth, spacing, font) {
    if (MeasureTrackedText(dc, text, spacing, font) <= maxWidth)
        return text

    suffix := "..."
    trimmed := text

    while (StrLen(trimmed) > 1) {
        trimmed := SubStr(trimmed, 1, -1)
        candidate := RTrim(trimmed) . suffix
        if (MeasureTrackedText(dc, candidate, spacing, font) <= maxWidth)
            return candidate
    }

    return suffix
}

DrawTrackedTextRight(dc, text, rightX, y, spacing, font, color) {
    width := MeasureTrackedText(dc, text, spacing, font)
    DrawTrackedText(dc, text, rightX - width, y, spacing, font, color)
}

MeasureTrackedText(dc, text, spacing, font) {
    SelectGdiObject(dc, font)
    total := 0
    count := 0

    Loop Parse text {
        total += MeasureTextWidth(dc, A_LoopField)
        count += 1
    }

    if (count > 1)
        total += (count - 1) * spacing

    return total
}

DrawSimpleText(dc, text, x, y, font, color) {
    SelectGdiObject(dc, font)
    DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
    DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", color)
    DllCall("gdi32\TextOutW", "Ptr", dc, "Int", x, "Int", y,
        "Str", text, "Int", StrLen(text))
}

DrawSimpleTextCentered(dc, text, x, y, width, font, color) {
    SelectGdiObject(dc, font)
    textWidth := MeasureTextWidth(dc, text)
    DrawSimpleText(dc, text, x + Floor((width - textWidth) / 2), y, font, color)
}

MeasureTextWidth(dc, text) {
    size := Buffer(8, 0)
    DllCall(
        "gdi32\GetTextExtentPoint32W",
        "Ptr", dc,
        "Str", text,
        "Int", StrLen(text),
        "Ptr", size.Ptr
    )
    return NumGet(size, 0, "Int")
}

SelectGdiObject(dc, objectHandle) {
    return DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", objectHandle, "Ptr")
}

MoveTo(dc, x, y) {
    DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", x, "Int", y, "Ptr", 0)
}

LineTo(dc, x, y) {
    DllCall("gdi32\LineTo", "Ptr", dc, "Int", x, "Int", y)
}

DrawLine(dc, x1, y1, x2, y2) {
    MoveTo(dc, x1, y1)
    LineTo(dc, x2, y2)
}

RGB(red, green, blue) {
    ; Win32 COLORREF uses 0x00BBGGRR.
    return red | (green << 8) | (blue << 16)
}


; ============================================================================
; Cleanup
; ============================================================================

Cleanup(*) {
    global AudioMeter, TimerResolutionEnabled
    global MemDC, BackBitmap, OldBitmap
    global BaseBrush, PanelBrush, InnerPanelBrush, ChipBrush
    global ButtonBrush, ButtonHoverBrush, ButtonActiveBrush, DangerHoverBrush
    global MeterInactiveBrush, TealBrush, TealGlowBrush1, TealGlowBrush2
    global BorderPen, InnerBorderPen, GridPen, FineGridPen, CentrePen
    global TealPen, TealDimPen
    global WaveCorePens, WaveGlowPens, WaveBarPens, WaveMeterBrushes
    global FontTitle, FontLabel, FontSmall, FontValue, FontButton

    if TimerResolutionEnabled {
        DllCall("winmm\timeEndPeriod", "UInt", 1, "UInt")
        TimerResolutionEnabled := false
    }

    if MemDC {
        ; GDI objects cannot be deleted while selected into a device context.
        stockPen := DllCall("gdi32\GetStockObject", "Int", 7, "Ptr")    ; BLACK_PEN
        stockBrush := DllCall("gdi32\GetStockObject", "Int", 0, "Ptr")  ; WHITE_BRUSH
        stockFont := DllCall("gdi32\GetStockObject", "Int", 13, "Ptr")  ; SYSTEM_FONT

        if stockPen
            SelectGdiObject(MemDC, stockPen)
        if stockBrush
            SelectGdiObject(MemDC, stockBrush)
        if stockFont
            SelectGdiObject(MemDC, stockFont)
        if OldBitmap
            SelectGdiObject(MemDC, OldBitmap)
    }

    DeleteGdiObject(BaseBrush)
    DeleteGdiObject(PanelBrush)
    DeleteGdiObject(InnerPanelBrush)
    DeleteGdiObject(ChipBrush)
    DeleteGdiObject(ButtonBrush)
    DeleteGdiObject(ButtonHoverBrush)
    DeleteGdiObject(ButtonActiveBrush)
    DeleteGdiObject(DangerHoverBrush)
    DeleteGdiObject(MeterInactiveBrush)
    DeleteGdiObject(TealBrush)
    DeleteGdiObject(TealGlowBrush1)
    DeleteGdiObject(TealGlowBrush2)

    DeleteGdiObject(BorderPen)
    DeleteGdiObject(InnerBorderPen)
    DeleteGdiObject(GridPen)
    DeleteGdiObject(FineGridPen)
    DeleteGdiObject(CentrePen)
    DeleteGdiObject(TealPen)
    DeleteGdiObject(TealDimPen)

    for pen in WaveCorePens
        DeleteGdiObject(pen)
    for pen in WaveGlowPens
        DeleteGdiObject(pen)
    for pen in WaveBarPens
        DeleteGdiObject(pen)
    for brush in WaveMeterBrushes
        DeleteGdiObject(brush)

    DeleteGdiObject(FontTitle)
    DeleteGdiObject(FontLabel)
    DeleteGdiObject(FontSmall)
    DeleteGdiObject(FontValue)
    DeleteGdiObject(FontButton)

    if BackBitmap
        DeleteGdiObject(BackBitmap)
    if MemDC
        DllCall("gdi32\DeleteDC", "Ptr", MemDC)

    if AudioMeter {
        try ObjRelease(AudioMeter)
        AudioMeter := 0
    }
}

DeleteGdiObject(handle) {
    if handle
        DllCall("gdi32\DeleteObject", "Ptr", handle)
}
