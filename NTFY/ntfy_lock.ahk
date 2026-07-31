#Requires AutoHotkey v2.0
#SingleInstance Force

; Loaded from .env in the same folder as this script.
global NTFY_SERVER := "https://ntfy.sh"
global NTFY_TOPIC := LoadEnvValue("NTFY_TOPIC")

WM_WTSSESSION_CHANGE := 0x02B1
NOTIFY_FOR_THIS_SESSION := 0

global WorkSessionActive := false
global WorkStartTick := 0
global WorkStartTime := ""

OnMessage(WM_WTSSESSION_CHANGE, SessionChange)

registered := DllCall(
    "Wtsapi32\WTSRegisterSessionNotification",
    "Ptr", A_ScriptHwnd,
    "UInt", NOTIFY_FOR_THIS_SESSION,
    "Int"
)

if !registered {
    MsgBox(
        "Could not register for Windows session notifications.`n`n"
        "Windows error: " A_LastError,
        "ntfy Work Timer",
        "Iconx"
    )
    ExitApp
}

OnExit(Cleanup)

; The script normally starts after Windows login,
; so begin the first work session immediately.
StartWorkSession()

Persistent


SessionChange(eventType, sessionId, *) {
    switch eventType {
        case 0x5:  ; WTS_SESSION_LOGON
            SetTimer(StartWorkSession, -10)

        case 0x6:  ; WTS_SESSION_LOGOFF
            SetTimer(EndWorkSession, -10)

        case 0x7:  ; WTS_SESSION_LOCK
            SetTimer(EndWorkSession, -10)

        case 0x8:  ; WTS_SESSION_UNLOCK
            SetTimer(StartWorkSession, -10)
    }
}


StartWorkSession() {
    global WorkSessionActive
    global WorkStartTick
    global WorkStartTime

    ; Prevent duplicate starts from LOGON and UNLOCK events.
    if WorkSessionActive
        return

    WorkSessionActive := true
    WorkStartTick := A_TickCount
    WorkStartTime := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    message :=
        "WORK`n"
        . "Started: " WorkStartTime

    SendNtfy(message)
}


EndWorkSession() {
    global WorkSessionActive
    global WorkStartTick
    global WorkStartTime

    ; Ignore duplicate LOCK or LOGOFF events.
    if !WorkSessionActive
        return

    endTime := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    elapsedMilliseconds := A_TickCount - WorkStartTick
    duration := FormatDuration(elapsedMilliseconds)

    message :=
        "BREAK`n"
        . "Duration: " duration "`n"
        . "Started: " WorkStartTime "`n"
        . "Ended: " endTime

    ; Reset before sending so duplicate events are ignored.
    WorkSessionActive := false
    WorkStartTick := 0
    WorkStartTime := ""

    SendNtfy(message)
}


FormatDuration(milliseconds) {
    totalSeconds := Floor(milliseconds / 1000)

    hours := Floor(totalSeconds / 3600)
    minutes := Floor(Mod(totalSeconds, 3600) / 60)
    seconds := Mod(totalSeconds, 60)

    return Format("{:02}h {:02}m {:02}s", hours, minutes, seconds)
}


SendNtfy(message) {
    global NTFY_SERVER
    global NTFY_TOPIC

    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")

        request.SetTimeouts(
            5000,  ; Resolve
            5000,  ; Connect
            5000,  ; Send
            5000   ; Receive
        )

        url := RTrim(NTFY_SERVER, "/") . "/" . NTFY_TOPIC
        request.Open("POST", url, false)
        request.SetRequestHeader(
            "Content-Type",
            "text/plain; charset=utf-8"
        )
        request.SetRequestHeader(
            "Title",
            "Work Status - " A_ComputerName
        )

        request.Send(message)

        if request.Status < 200 || request.Status >= 300
            throw Error("ntfy returned HTTP status " request.Status)
    }
    catch as error {
        FileAppend(
            FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            . " | "
            . StrReplace(message, "`n", " | ")
            . " | "
            . error.Message
            . "`n",
            A_Temp "\ntfy-work-timer.log",
            "UTF-8"
        )
    }
}


Cleanup(*) {
    try DllCall(
        "Wtsapi32\WTSUnRegisterSessionNotification",
        "Ptr", A_ScriptHwnd
    )
}

; ============================================================
; .ENV SUPPORT
; ============================================================

LoadEnvValue(variableName, envFile := "") {
    if (envFile = "")
        envFile := A_ScriptDir . "\..\.env"

    if !FileExist(envFile)
        throw Error("Missing .env file: " . envFile)

    fileContents := FileRead(envFile, "UTF-8")

    for rawLine in StrSplit(fileContents, "`n", "`r") {
        ; Also removes a possible UTF-8 BOM from the first line.
        line := Trim(rawLine, " `t" . Chr(0xFEFF))

        if (line = "")
            continue

        firstCharacter := SubStr(line, 1, 1)
        if (firstCharacter = "#" || firstCharacter = ";")
            continue

        ; Accept both NTFY_TOPIC=value and export NTFY_TOPIC=value.
        line := RegExReplace(line, "i)^export\s+", "")

        equalsPosition := InStr(line, "=")
        if (equalsPosition = 0)
            continue

        key := Trim(SubStr(line, 1, equalsPosition - 1))
        if (key != variableName)
            continue

        value := Trim(SubStr(line, equalsPosition + 1))

        ; Remove matching single or double quotes around the value.
        if (StrLen(value) >= 2) {
            firstQuote := SubStr(value, 1, 1)
            lastQuote := SubStr(value, StrLen(value), 1)

            if (
                firstQuote = lastQuote
                && (firstQuote = Chr(34) || firstQuote = "'")
            ) {
                value := SubStr(value, 2, StrLen(value) - 2)
            }
        }

        if (value = "")
            throw Error(variableName . " is empty in " . envFile)

        return value
    }

    throw Error(variableName . " was not found in " . envFile)
}
