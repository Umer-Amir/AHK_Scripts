#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut

; ============================================================================
; Work & Activity Tracker — AutoHotkey v2
; Tracks weekdays only. A day runs from 00:00:00 through 23:59:59.
; ============================================================================

global APP_NAME := "Work & Activity Tracker"
global IDLE_LIMIT_MS := 60000
global PULSE_INTERVAL_MS := 1000
global CHECKPOINT_INTERVAL_MS := 30000

global DATA_DIR := A_ScriptDir "\WorkTimerData"
global STATE_FILE := DATA_DIR "\WorkTimerState.ini"
global DAILY_LOG_FILE := DATA_DIR "\Work_Time_Log.csv"
global SESSION_LOG_FILE := DATA_DIR "\Work_Sessions.csv"
global ERROR_LOG_FILE := DATA_DIR "\WorkTimer_Errors.log"

global WM_WTSSESSION_CHANGE := 0x02B1
global WM_POWERBROADCAST := 0x0218
global NOTIFY_FOR_THIS_SESSION := 0

global NTFY_URL := LoadNtfyUrl()

; Live session state
global WorkSessionActive := false
global WorkStartTick := 0
global WorkStartTime := ""
global SessionActivityStartMs := 0
global LastPulseTick := 0
global ActivityRunning := false
global ActivityPauseNotified := false
global LastCheckpointTick := 0

; Persisted daily/cumulative state
global TrackingDate := ""
global WeekKey := ""
global MonthKey := ""
global YearKey := ""
global WorkDayMs := 0
global WorkWeekMs := 0
global WorkMonthMs := 0
global WorkYearMs := 0
global WorkAllMs := 0
global ActivityDayMs := 0
global BreakDayMs := 0
global PendingBreakStart := ""
global LastBreakMs := 0

Initialize()
Persistent


Initialize() {
    global DATA_DIR, DAILY_LOG_FILE, SESSION_LOG_FILE
    global WM_WTSSESSION_CHANGE, WM_POWERBROADCAST, NOTIFY_FOR_THIS_SESSION
    global PULSE_INTERVAL_MS

    DirCreate(DATA_DIR)
    EnsureLogHeaders()
    LoadState()
    EnsureCurrentDay()

    OnMessage(WM_WTSSESSION_CHANGE, SessionChange)
    OnMessage(WM_POWERBROADCAST, PowerChange)

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
            "Work & Activity Tracker",
            "Iconx"
        )
        ExitApp
    }

    OnExit(Cleanup)
    SetTimer(ActivityPulse, PULSE_INTERVAL_MS)

    ; This script is normally launched after Windows login.
    if IsWeekday()
        StartWorkSession()
}


PowerChange(eventType, eventData, *) {
    switch eventType {
        case 0x4:   ; PBT_APMSUSPEND
            SetTimer(EndWorkSession, -25)

        case 0x7, 0x12:  ; PBT_APMRESUMESUSPEND / PBT_APMRESUMEAUTOMATIC
            SetTimer(StartWorkSession, -250)
    }
    return true
}


SessionChange(eventType, sessionId, *) {
    switch eventType {
        case 0x5:  ; WTS_SESSION_LOGON
            SetTimer(StartWorkSession, -25)

        case 0x6:  ; WTS_SESSION_LOGOFF
            SetTimer(EndWorkSession, -25)

        case 0x7:  ; WTS_SESSION_LOCK
            SetTimer(EndWorkSession, -25)

        case 0x8:  ; WTS_SESSION_UNLOCK
            SetTimer(StartWorkSession, -25)
    }
}


StartWorkSession() {
    global WorkSessionActive, WorkStartTick, WorkStartTime
    global SessionActivityStartMs, LastPulseTick, ActivityRunning
    global ActivityPauseNotified, LastCheckpointTick
    global PendingBreakStart, LastBreakMs, BreakDayMs, ActivityDayMs

    EnsureCurrentDay()

    if !IsWeekday() || WorkSessionActive
        return

    now := A_Now
    currentDate := FormatTime(now, "yyyy-MM-dd")
    hadConfirmedBreak := false

    if PendingBreakStart != "" {
        pendingDate := FormatTime(PendingBreakStart, "yyyy-MM-dd")

        ; A break is confirmed only by returning on the same weekday.
        if pendingDate = currentDate {
            LastBreakMs := Max(0, DateDiff(now, PendingBreakStart, "Seconds") * 1000)
            BreakDayMs += LastBreakMs
            hadConfirmedBreak := true
        } else {
            LastBreakMs := 0
        }

        PendingBreakStart := ""
    }

    WorkSessionActive := true
    WorkStartTick := A_TickCount
    WorkStartTime := now
    SessionActivityStartMs := ActivityDayMs
    LastPulseTick := A_TickCount
    LastCheckpointTick := A_TickCount
    ActivityRunning := A_TimeIdlePhysical < 60000
    ActivityPauseNotified := !ActivityRunning

    SaveState()

    if hadConfirmedBreak {
        message := "WORK`n"
            . "Resumed: " FormatTime(now, "yyyy-MM-dd HH:mm:ss") "`n"
            . "Last break: " FormatDuration(LastBreakMs) "`n"
            . "Total breaks today: " FormatDuration(BreakDayMs) "`n"
            . "Total work today: " FormatDuration(GetLiveWorkDayMs()) "`n"
            . "Activity today: " FormatDuration(ActivityDayMs)
    } else {
        message := "WORK`n"
            . "First session today`n"
            . "Started: " FormatTime(now, "yyyy-MM-dd HH:mm:ss") "`n"
            . "Previous non-working time: Ignored"
    }

    QueueNtfy(message)
}


EndWorkSession(sendNotification := true) {
    global WorkSessionActive, WorkStartTick, WorkStartTime
    global WorkDayMs, WorkWeekMs, WorkMonthMs, WorkYearMs, WorkAllMs
    global ActivityDayMs, SessionActivityStartMs, PendingBreakStart
    global ActivityRunning, ActivityPauseNotified, LastPulseTick
    global BreakDayMs

    if !WorkSessionActive
        return

    ActivityPulse(false)

    endTime := A_Now
    sessionStartTime := WorkStartTime
    sessionWorkMs := Max(0, A_TickCount - WorkStartTick)
    sessionActivityMs := Max(0, ActivityDayMs - SessionActivityStartMs)

    WorkDayMs += sessionWorkMs
    WorkWeekMs += sessionWorkMs
    WorkMonthMs += sessionWorkMs
    WorkYearMs += sessionWorkMs
    WorkAllMs += sessionWorkMs

    AppendSessionLog(sessionStartTime, endTime, sessionWorkMs, sessionActivityMs)

    ; This remains pending. It becomes a break only if work resumes today.
    PendingBreakStart := endTime

    WorkSessionActive := false
    WorkStartTick := 0
    WorkStartTime := ""
    ActivityRunning := false
    ActivityPauseNotified := false
    LastPulseTick := 0

    UpdateDailyLog()
    SaveState()

    if sendNotification {
        activityPercent := GetActivityPercent(ActivityDayMs, WorkDayMs)
        message := "BREAK`n"
            . "Current session: " FormatDuration(sessionWorkMs) "`n"
            . "Total work today: " FormatDuration(WorkDayMs) "`n"
            . "Activity today: " FormatDuration(ActivityDayMs)
            . " (" activityPercent ")`n"
            . "Confirmed breaks today: " FormatDuration(BreakDayMs) "`n"
            . "Started: " FormatTime(sessionStartTime, "yyyy-MM-dd HH:mm:ss") "`n"
            . "Ended: " FormatTime(endTime, "yyyy-MM-dd HH:mm:ss")

        QueueNtfy(message)
    }
}


ActivityPulse(allowCheckpoint := true) {
    global WorkSessionActive, LastPulseTick, ActivityRunning
    global ActivityPauseNotified, ActivityDayMs
    global LastCheckpointTick, CHECKPOINT_INTERVAL_MS, IDLE_LIMIT_MS

    static busy := false
    if busy
        return

    busy := true

    try {
        EnsureCurrentDay()

        if !WorkSessionActive || !IsWeekday()
            return

        nowTick := A_TickCount
        delta := LastPulseTick > 0 ? Max(0, nowTick - LastPulseTick) : 0
        idleMs := A_TimeIdlePhysical

        if ActivityRunning
            ActivityDayMs += delta

        if idleMs >= IDLE_LIMIT_MS {
            if ActivityRunning {
                ; Keep the first idle minute as normal reading/thinking time,
                ; but remove the small polling overrun beyond exactly 60 seconds.
                ActivityDayMs := Max(0, ActivityDayMs - Max(0, idleMs - IDLE_LIMIT_MS))
                ActivityRunning := false

                if !ActivityPauseNotified {
                    ShowSoftNotification(
                        "Activity tracking paused",
                        "No physical keyboard or mouse input for one minute. Work time continues."
                    )
                    ActivityPauseNotified := true
                }
            }
        } else if !ActivityRunning {
            ActivityRunning := true
            ActivityPauseNotified := false
        }

        LastPulseTick := nowTick

        if allowCheckpoint && (nowTick - LastCheckpointTick >= CHECKPOINT_INTERVAL_MS) {
            LastCheckpointTick := nowTick
            SaveState()
        }
    } catch as error {
        LogError("ActivityPulse", error)
    } finally {
        busy := false
    }
}


EnsureCurrentDay() {
    global TrackingDate, WeekKey, MonthKey, YearKey
    global WorkDayMs, WorkWeekMs, WorkMonthMs, WorkYearMs
    global ActivityDayMs, BreakDayMs, PendingBreakStart, LastBreakMs
    global WorkSessionActive

    static rollingDay := false
    if rollingDay
        return

    today := FormatTime(A_Now, "yyyy-MM-dd")
    thisWeek := GetWeekKey(A_Now)
    thisMonth := FormatTime(A_Now, "yyyy-MM")
    thisYear := FormatTime(A_Now, "yyyy")

    if TrackingDate = "" {
        TrackingDate := today
        WeekKey := thisWeek
        MonthKey := thisMonth
        YearKey := thisYear
        SaveState()
        return
    }

    if TrackingDate = today
        return

    rollingDay := true
    try {
        ; The user does not work across midnight. Close any unexpected open
        ; session at the boundary so time cannot leak into another date.
        if WorkSessionActive
            EndWorkSession(false)

        UpdateDailyLog()

        TrackingDate := today
        WorkDayMs := 0
        ActivityDayMs := 0
        BreakDayMs := 0
        PendingBreakStart := ""
        LastBreakMs := 0

        if WeekKey != thisWeek {
            WeekKey := thisWeek
            WorkWeekMs := 0
        }

        if MonthKey != thisMonth {
            MonthKey := thisMonth
            WorkMonthMs := 0
        }

        if YearKey != thisYear {
            YearKey := thisYear
            WorkYearMs := 0
        }

        SaveState()
    } finally {
        rollingDay := false
    }
}


GetLiveWorkDayMs() {
    global WorkDayMs, WorkSessionActive, WorkStartTick
    return WorkDayMs + (WorkSessionActive ? Max(0, A_TickCount - WorkStartTick) : 0)
}


GetLivePeriodMs(storedMs) {
    global WorkSessionActive, WorkStartTick
    return storedMs + (WorkSessionActive ? Max(0, A_TickCount - WorkStartTick) : 0)
}


IsWeekday(timestamp := "") {
    if timestamp = ""
        timestamp := A_Now

    dayNumber := Integer(FormatTime(timestamp, "WDay"))
    return dayNumber >= 2 && dayNumber <= 6
}


GetWeekKey(timestamp) {
    dayNumber := Integer(FormatTime(timestamp, "WDay"))
    daysSinceMonday := Mod(dayNumber + 5, 7)
    monday := DateAdd(timestamp, -daysSinceMonday, "Days")
    return FormatTime(monday, "yyyy-MM-dd")
}


FormatDuration(milliseconds) {
    totalSeconds := Floor(Max(0, milliseconds) / 1000)
    hours := Floor(totalSeconds / 3600)
    minutes := Floor(Mod(totalSeconds, 3600) / 60)
    seconds := Mod(totalSeconds, 60)
    return Format("{:02}h {:02}m {:02}s", hours, minutes, seconds)
}


FormatCsvDuration(milliseconds) {
    totalSeconds := Floor(Max(0, milliseconds) / 1000)
    hours := Floor(totalSeconds / 3600)
    minutes := Floor(Mod(totalSeconds, 3600) / 60)
    seconds := Mod(totalSeconds, 60)
    return Format("{:02}:{:02}:{:02}", hours, minutes, seconds)
}


GetActivityPercent(activityMs, workMs) {
    if workMs <= 0
        return "0.0%"
    return Format("{:.1f}%", Min(100, activityMs / workMs * 100))
}


EnsureLogHeaders() {
    global DAILY_LOG_FILE, SESSION_LOG_FILE

    if !FileExist(DAILY_LOG_FILE) {
        FileAppend(
            "Date,Hours This Day,Hours This Week,Hours This Month,Hours This Year,All Hours,"
            . "Activity This Day,Activity Percentage,Confirmed Breaks`n",
            DAILY_LOG_FILE,
            "UTF-8"
        )
    }

    if !FileExist(SESSION_LOG_FILE) {
        FileAppend(
            "Date,Session Start,Session End,Working Duration,Activity Duration`n",
            SESSION_LOG_FILE,
            "UTF-8"
        )
    }
}


AppendSessionLog(startTime, endTime, workMs, activityMs) {
    global SESSION_LOG_FILE

    try {
        FileAppend(
            FormatTime(startTime, "yyyy-MM-dd") ","
            . FormatTime(startTime, "HH:mm:ss") ","
            . FormatTime(endTime, "HH:mm:ss") ","
            . FormatCsvDuration(workMs) ","
            . FormatCsvDuration(activityMs) "`n",
            SESSION_LOG_FILE,
            "UTF-8"
        )
    } catch as error {
        LogError("AppendSessionLog", error)
    }
}


UpdateDailyLog() {
    global DAILY_LOG_FILE, TrackingDate
    global WorkDayMs, WorkWeekMs, WorkMonthMs, WorkYearMs, WorkAllMs
    global ActivityDayMs, BreakDayMs

    if TrackingDate = ""
        return

    try {
        newRow := TrackingDate ","
            . FormatCsvDuration(WorkDayMs) ","
            . FormatCsvDuration(WorkWeekMs) ","
            . FormatCsvDuration(WorkMonthMs) ","
            . FormatCsvDuration(WorkYearMs) ","
            . FormatCsvDuration(WorkAllMs) ","
            . FormatCsvDuration(ActivityDayMs) ","
            . GetActivityPercent(ActivityDayMs, WorkDayMs) ","
            . FormatCsvDuration(BreakDayMs)

        contents := FileRead(DAILY_LOG_FILE, "UTF-8")
        lines := StrSplit(StrReplace(contents, "`r", ""), "`n")
        output := ""
        replaced := false

        for index, line in lines {
            if line = ""
                continue

            if index > 1 && SubStr(line, 1, 10) = TrackingDate {
                output .= newRow "`n"
                replaced := true
            } else {
                output .= line "`n"
            }
        }

        if !replaced
            output .= newRow "`n"

        file := FileOpen(DAILY_LOG_FILE, "w", "UTF-8")
        file.Write(output)
        file.Close()
    } catch as error {
        LogError("UpdateDailyLog", error)
    }
}


SaveState() {
    global STATE_FILE, TrackingDate, WeekKey, MonthKey, YearKey
    global WorkDayMs, WorkWeekMs, WorkMonthMs, WorkYearMs, WorkAllMs
    global ActivityDayMs, BreakDayMs, PendingBreakStart, LastBreakMs
    global WorkSessionActive, WorkStartTime

    try {
        text := "TrackingDate=" TrackingDate "`n"
            . "WeekKey=" WeekKey "`n"
            . "MonthKey=" MonthKey "`n"
            . "YearKey=" YearKey "`n"
            . "WorkDayMs=" Floor(GetLiveWorkDayMs()) "`n"
            . "WorkWeekMs=" Floor(GetLivePeriodMs(WorkWeekMs)) "`n"
            . "WorkMonthMs=" Floor(GetLivePeriodMs(WorkMonthMs)) "`n"
            . "WorkYearMs=" Floor(GetLivePeriodMs(WorkYearMs)) "`n"
            . "WorkAllMs=" Floor(GetLivePeriodMs(WorkAllMs)) "`n"
            . "ActivityDayMs=" Floor(ActivityDayMs) "`n"
            . "BreakDayMs=" Floor(BreakDayMs) "`n"
            . "PendingBreakStart=" PendingBreakStart "`n"
            . "LastBreakMs=" Floor(LastBreakMs) "`n"
            . "WasActive=" (WorkSessionActive ? 1 : 0) "`n"
            . "SavedAt=" A_Now "`n"

        file := FileOpen(STATE_FILE, "w", "UTF-8")
        file.Write(text)
        file.Close()
    } catch as error {
        LogError("SaveState", error)
    }
}


LoadState() {
    global STATE_FILE, TrackingDate, WeekKey, MonthKey, YearKey
    global WorkDayMs, WorkWeekMs, WorkMonthMs, WorkYearMs, WorkAllMs
    global ActivityDayMs, BreakDayMs, PendingBreakStart, LastBreakMs

    if !FileExist(STATE_FILE)
        return

    try {
        values := Map()
        for line in StrSplit(StrReplace(FileRead(STATE_FILE, "UTF-8"), "`r", ""), "`n") {
            separator := InStr(line, "=")
            if separator > 0
                values[SubStr(line, 1, separator - 1)] := SubStr(line, separator + 1)
        }

        TrackingDate := values.Get("TrackingDate", "")
        WeekKey := values.Get("WeekKey", "")
        MonthKey := values.Get("MonthKey", "")
        YearKey := values.Get("YearKey", "")
        WorkDayMs := Number(values.Get("WorkDayMs", 0))
        WorkWeekMs := Number(values.Get("WorkWeekMs", 0))
        WorkMonthMs := Number(values.Get("WorkMonthMs", 0))
        WorkYearMs := Number(values.Get("WorkYearMs", 0))
        WorkAllMs := Number(values.Get("WorkAllMs", 0))
        ActivityDayMs := Number(values.Get("ActivityDayMs", 0))
        BreakDayMs := Number(values.Get("BreakDayMs", 0))
        PendingBreakStart := values.Get("PendingBreakStart", "")
        LastBreakMs := Number(values.Get("LastBreakMs", 0))

        ; A saved live session is already included up to SavedAt. Never bridge
        ; computer-off/script-off time. Treat SavedAt as the possible break start.
        if Number(values.Get("WasActive", 0)) = 1
            PendingBreakStart := values.Get("SavedAt", "")
    } catch as error {
        LogError("LoadState", error)
    }
}


LoadNtfyUrl() {
    fallbackTopic := "1982_Gonzo_Opera_Qwerty_20022"
    candidates := [A_ScriptDir "\..\.env", A_ScriptDir "\.env"]

    for envFile in candidates {
        if !FileExist(envFile)
            continue

        try {
            for rawLine in StrSplit(StrReplace(FileRead(envFile, "UTF-8"), "`r", ""), "`n") {
                line := Trim(rawLine)
                if line = "" || SubStr(line, 1, 1) = "#" || SubStr(line, 1, 1) = ";"
                    continue

                if RegExMatch(line, "i)^NTFY_TOPIC\s*=\s*(.+)$", &match) {
                    topic := Trim(match[1], " `t`"'")
                    if topic != ""
                        return InStr(topic, "https://") = 1 ? topic : "https://ntfy.sh/" topic
                }
            }
        }
    }

    return "https://ntfy.sh/" fallbackTopic
}


QueueNtfy(message) {
    ; Session events are infrequent. Deferring the network request keeps the
    ; Windows session callback instantaneous.
    SetTimer(() => SendNtfy(message), -50)
}


SendNtfy(message) {
    global NTFY_URL

    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(3000, 3000, 3000, 5000)
        request.Open("POST", NTFY_URL, false)
        request.SetRequestHeader("Content-Type", "text/plain; charset=utf-8")
        request.SetRequestHeader("Title", "Work Status - " A_ComputerName)
        request.Send(message)

        if request.Status < 200 || request.Status >= 300
            throw Error("ntfy returned HTTP status " request.Status)
    } catch as error {
        LogError("SendNtfy | " StrReplace(message, "`n", " | "), error)
    }
}


ShowSoftNotification(title, text) {
    try TrayTip(text, title, 17)  ; Information icon + muted sound.
}


LogError(context, error) {
    global ERROR_LOG_FILE

    try FileAppend(
        FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        . " | " context
        . " | " error.Message
        . "`n",
        ERROR_LOG_FILE,
        "UTF-8"
    )
}


Cleanup(exitReason, exitCode) {
    global WorkSessionActive

    try SetTimer(ActivityPulse, 0)

    ; Finalize locally without delaying Windows shutdown with a network call.
    if WorkSessionActive
        try EndWorkSession(false)

    try DllCall(
        "Wtsapi32\WTSUnRegisterSessionNotification",
        "Ptr", A_ScriptHwnd
    )
}
