#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; SETTINGS
; ============================================================

; .env is one directory above this script.
global ENV_FILE := A_ScriptDir "\..\.env"

; Maximum time between the two key presses for a "double tap".
global DOUBLE_TAP_MS := 350

; Registered dynamic shortcuts.
global RegisteredHotstrings := Map()
global RegisteredHotkeys := Map()

; Prevents an old expiry timer from deleting a newer chord value.
global ChordGenerations := Map()

; ============================================================
; STARTUP
; ============================================================

if !FileExist(ENV_FILE) {
    MsgBox(
        "Could not find .env file:`n`n" ENV_FILE,
        "AHK AutoComplete",
        "Iconx"
    )
    ExitApp
}

; Load all shortcut definitions.
RefreshDefinitions()

Persistent


; ============================================================
; OPEN .ENV IN NOTEPAD
; ALT + 1
; ============================================================

!1::OpenEnvFile()

OpenEnvFile() {
    global ENV_FILE

    if !FileExist(ENV_FILE) {
        MsgBox(
            "Could not find .env file:`n`n" ENV_FILE,
            "AHK AutoComplete",
            "Iconx"
        )
        return
    }

    Run('notepad.exe "' ENV_FILE '"')
}


; ============================================================
; RESTART THIS SCRIPT AFTER ONE SECOND
; ALT + 2
; ============================================================

!2::RestartThisScript()

RestartThisScript() {
    ; A separate hidden command process survives after ExitApp, waits for one
    ; second, and launches this exact script again with the same AHK runtime.
    restartCommand := A_ComSpec
        . ' /d /c "timeout /t 1 /nobreak >nul & start "" "'
        . A_AhkPath
        . '" "'
        . A_ScriptFullPath
        . '""'

    Run(restartCommand, , "Hide")
    ExitApp
}


; ============================================================
; REGISTER SHORTCUTS
; ============================================================

RefreshDefinitions() {
    global RegisteredHotstrings
    global RegisteredHotkeys

    config := ParseEnv()

    ; --------------------------------------------------------
    ; Remove previously registered hotstrings.
    ; --------------------------------------------------------

    for hotstringName, _ in RegisteredHotstrings {
        try Hotstring(hotstringName, "Off")
    }

    RegisteredHotstrings.Clear()

    ; --------------------------------------------------------
    ; Remove previously registered hotkeys.
    ; --------------------------------------------------------

    for hotkeyName, _ in RegisteredHotkeys {
        try Hotkey(hotkeyName, "Off")
    }

    RegisteredHotkeys.Clear()

    ; --------------------------------------------------------
    ; AUTOCOMPLETE
    ;
    ; AUTOCOMPLETE_EMAIL=hello@example.com
    ;
    ; becomes:
    ;
    ; ;email
    ; --------------------------------------------------------

    for envKey, _ in config.AutoComplete {
        suffix := RegExReplace(
            envKey,
            "i)^AUTOCOMPLETE_",
            ""
        )

        if (suffix = envKey)
            continue

        trigger := ";" StrLower(suffix)

        hotstringName := "::" trigger

        callback := AutoCompleteHandler.Bind(envKey)

        Hotstring(
            hotstringName,
            callback
        )

        RegisteredHotstrings[hotstringName] := true
    }

    ; AA and DOUBLE A use the same physical key, so each key is
    ; registered only once. KeyPressHandler decides which rule wins.
    pressKeys := Map()

    for pair, _ in config.DoubleTap {
        if RegExMatch(pair, "i)^([A-Z0-9])\1$", &match)
            pressKeys[NormalizeKeyName(StrUpper(match[1]))] := true
    }

    for key, _ in config.ConsecutiveDouble {
        normalizedKey := NormalizeKeyName(StrUpper(key))
        if (normalizedKey != "")
            pressKeys[normalizedKey] := true
    }

    for key, _ in pressKeys {
        hotkeyName := "~*" key
        try {
            Hotkey(hotkeyName, KeyPressHandler.Bind(key))
            RegisteredHotkeys[hotkeyName] := true
        }
    }

    ; --------------------------------------------------------
    ; TEMPORARY TWO-KEY CHORD
    ;
    ; A~B 5=QWERTY
    ;
    ; Hold A and press B (or hold B and press A). The inserted
    ; value is removed after the configured number of seconds.
    ; --------------------------------------------------------

    for chordId, chord in config.Chords {
        key1 := NormalizeKeyName(StrUpper(chord.Key1))
        key2 := NormalizeKeyName(StrUpper(chord.Key2))

        if (key1 = "" || key2 = "" || key1 = key2)
            continue

        ; AHK custom combinations support ~ on the prefix key. A
        ; wildcard (*) in this position prevents reliable registration.
        for hotkeyName in ["~" key1 " & " key2, "~" key2 " & " key1] {
            callback := ChordHandler.Bind(chordId)

            try {
                Hotkey(hotkeyName, callback)
                RegisteredHotkeys[hotkeyName] := true
            }
        }
    }

    ; --------------------------------------------------------
    ; CUSTOM HOTKEY SECTIONS
    ;
    ; # SHIFT + ALT + P
    ; Umer Amir
    ;
    ; --------------------------------------------------------

    for hotkeyName, _ in config.Hotkeys {

        callback := CustomHotkeyHandler.Bind(
            hotkeyName
        )

        try {
            Hotkey(
                hotkeyName,
                callback
            )

            RegisteredHotkeys[hotkeyName] := true
        }
    }

}


; ============================================================
; AUTOCOMPLETE HANDLER
; ============================================================

AutoCompleteHandler(envKey, *) {

    ; IMPORTANT:
    ; Read .env again EVERY TIME the shortcut is used.
    config := ParseEnv()

    if !config.AutoComplete.Has(envKey)
        return

    value := config.AutoComplete[envKey]

    SendText(value)
}


; ============================================================
; DOUBLE-PRESS HANDLER
; ============================================================

KeyPressHandler(key, *) {
    global DOUBLE_TAP_MS
    static LastTapTimes := Map()

    now := A_TickCount
    pair := StrUpper(key key)
    config := ParseEnv()
    isConsecutive := (StrLower(A_PriorKey) = StrLower(key))

    ; If both AA and DOUBLE A exist, a quick double press uses AA.
    ; A slower but still consecutive press uses DOUBLE A.
    if (
        isConsecutive
        && config.DoubleTap.Has(pair)
        && LastTapTimes.Has(key)
        && (now - LastTapTimes[key]) <= DOUBLE_TAP_MS
    ) {
        LastTapTimes[key] := 0
        SetTimer(ReplaceDoubleTap.Bind(pair), -25)
        return
    }

    if (isConsecutive && config.ConsecutiveDouble.Has(key)) {
        LastTapTimes[key] := 0
        SetTimer(ReplaceConsecutiveDouble.Bind(key), -25)
        return
    }

    LastTapTimes[key] := now
}


ReplaceDoubleTap(pair, *) {

    ; Read .env fresh every time.
    config := ParseEnv()

    if !config.DoubleTap.Has(pair)
        return

    value := config.DoubleTap[pair]

    ; Remove the two characters that were typed.
    Send("{Backspace 2}")

    SendText(value)
}


ReplaceConsecutiveDouble(key, *) {
    config := ParseEnv()

    if !config.ConsecutiveDouble.Has(key)
        return

    Send("{Backspace 2}")
    SendText(config.ConsecutiveDouble[key])
}


; ============================================================
; TEMPORARY CHORD HANDLER
; ============================================================

ChordHandler(chordId, *) {
    global ChordGenerations

    config := ParseEnv()

    if !config.Chords.Has(chordId)
        return

    chord := config.Chords[chordId]
    value := chord.Value

    ; The prefix key was allowed through by ~, so remove it.
    Send("{Backspace}")
    SendText(value)

    generation := ChordGenerations.Has(chordId)
        ? ChordGenerations[chordId] + 1
        : 1

    ChordGenerations[chordId] := generation

    delayMs := -Max(1, Round(chord.Seconds * 1000))
    SetTimer(ExpireChordValue.Bind(chordId, generation, value), delayMs)
}


ExpireChordValue(chordId, generation, value, *) {
    global ChordGenerations

    if !ChordGenerations.Has(chordId)
        return

    if (ChordGenerations[chordId] != generation)
        return

    Send("{Backspace " StrLen(value) "}")
    ChordGenerations.Delete(chordId)
}


; ============================================================
; CUSTOM HOTKEY HANDLER
; ============================================================

CustomHotkeyHandler(hotkeyName, *) {

    ; Read .env fresh every time.
    config := ParseEnv()

    if !config.Hotkeys.Has(hotkeyName)
        return

    value := config.Hotkeys[hotkeyName]

    SendText(value)
}


; ============================================================
; .ENV PARSER
; ============================================================

ParseEnv() {
    global ENV_FILE

    config := {
        AutoComplete: Map(),
        DoubleTap: Map(),
        ConsecutiveDouble: Map(),
        Chords: Map(),
        Hotkeys: Map()
    }

    if !FileExist(ENV_FILE)
        return config

    fileContents := FileRead(
        ENV_FILE,
        "UTF-8"
    )

    currentSection := ""
    currentHotkey := ""

    for rawLine in StrSplit(
        fileContents,
        "`n",
        "`r"
    ) {
        ; Remove whitespace and possible UTF-8 BOM.
        line := Trim(
            rawLine,
            " `t" Chr(0xFEFF)
        )

        if (line = "")
            continue

        ; ====================================================
        ; COMMENT / SECTION HEADER
        ; ====================================================

        if (SubStr(line, 1, 1) = "#") {

            header := Trim(
                SubStr(line, 2)
            )

            ; -----------------------------------------------
            ; # AutoComplete
            ; -----------------------------------------------

            if (StrLower(header) = "autocomplete") {
                currentSection := "AUTOCOMPLETE"
                currentHotkey := ""
                continue
            }

            ; -----------------------------------------------
            ; # Double TAP
            ; -----------------------------------------------

            if (
                StrLower(header) = "double tap"
                || StrLower(header) = "doubletap"
            ) {
                currentSection := "DOUBLETAP"
                currentHotkey := ""
                continue
            }

            ; -----------------------------------------------
            ; Try interpreting the comment as a hotkey:
            ;
            ; # SHIFT + ALT + P
            ; # CTRL + ALT + T
            ; # WIN + SHIFT + Q
            ; -----------------------------------------------

            possibleHotkey := HeaderToHotkey(
                header
            )

            if (possibleHotkey != "") {
                currentSection := "HOTKEY"
                currentHotkey := possibleHotkey

                ; Create empty value initially.
                config.Hotkeys[currentHotkey] := ""

                continue
            }

            ; Normal comment.
            continue
        }

        ; Also support ; comments.
        if (SubStr(line, 1, 1) = ";")
            continue

        ; ====================================================
        ; INLINE CONSECUTIVE DOUBLE PRESS
        ; DOUBLE A=ABCDEFGHIJ
        ; ====================================================

        if RegExMatch(line, "i)^DOUBLE\s+([^\s=]+)\s*=\s*(.*)$", &doubleMatch) {
            key := Trim(doubleMatch[1])
            normalizedKey := NormalizeKeyName(StrUpper(key))

            if (normalizedKey != "")
                config.ConsecutiveDouble[normalizedKey] := RemoveQuotes(Trim(doubleMatch[2]))

            continue
        }

        ; ====================================================
        ; INLINE TEMPORARY CHORD
        ; A~B 5=QWERTY
        ; Decimal durations such as 0.2 and 1.7 are supported.
        ; ====================================================

        if RegExMatch(line, "i)^([^\s~=]+)\s*~\s*([^\s=]+)\s+([0-9]+(?:\.[0-9]+)?)\s*=\s*(.*)$", &chordMatch) {
            key1 := NormalizeKeyName(StrUpper(Trim(chordMatch[1])))
            key2 := NormalizeKeyName(StrUpper(Trim(chordMatch[2])))
            seconds := chordMatch[3] + 0

            if (key1 != "" && key2 != "" && key1 != key2 && seconds > 0) {
                chordId := key1 "~" key2
                config.Chords[chordId] := {
                    Key1: key1,
                    Key2: key2,
                    Seconds: seconds,
                    Value: RemoveQuotes(Trim(chordMatch[4]))
                }
            }

            continue
        }

        ; ====================================================
        ; ONE-LINE CUSTOM HOTKEY
        ; SHIFT + ALT + P=Umer Amir
        ; ====================================================

        equalsPosition := InStr(line, "=")

        if equalsPosition {
            possibleHeader := Trim(SubStr(line, 1, equalsPosition - 1))
            possibleHotkey := HeaderToHotkey(possibleHeader)

            if (possibleHotkey != "") {
                config.Hotkeys[possibleHotkey] := RemoveQuotes(
                    Trim(SubStr(line, equalsPosition + 1))
                )
                continue
            }
        }

        ; ====================================================
        ; AUTOCOMPLETE
        ; ====================================================

        if (currentSection = "AUTOCOMPLETE") {

            equalsPosition := InStr(
                line,
                "="
            )

            if !equalsPosition
                continue

            key := Trim(
                SubStr(
                    line,
                    1,
                    equalsPosition - 1
                )
            )

            value := Trim(
                SubStr(
                    line,
                    equalsPosition + 1
                )
            )

            value := RemoveQuotes(value)

            config.AutoComplete[key] := value

            continue
        }

        ; ====================================================
        ; DOUBLE TAP
        ; ====================================================

        if (currentSection = "DOUBLETAP") {

            equalsPosition := InStr(
                line,
                "="
            )

            if !equalsPosition
                continue

            key := Trim(
                SubStr(
                    line,
                    1,
                    equalsPosition - 1
                )
            )

            value := Trim(
                SubStr(
                    line,
                    equalsPosition + 1
                )
            )

            value := RemoveQuotes(value)

            config.DoubleTap[key] := value

            continue
        }

        ; ====================================================
        ; CUSTOM HOTKEY VALUE
        ;
        ; Allows:
        ;
        ; # SHIFT + ALT + P
        ; Umer Amir
        ;
        ; Multiple lines are also supported.
        ; ====================================================

        if (
            currentSection = "HOTKEY"
            && currentHotkey != ""
        ) {

            value := RemoveQuotes(line)

            if (
                config.Hotkeys.Has(currentHotkey)
                && config.Hotkeys[currentHotkey] != ""
            ) {
                config.Hotkeys[currentHotkey] .= (
                    "`n" value
                )
            }
            else {
                config.Hotkeys[currentHotkey] := value
            }
        }
    }

    return config
}


; ============================================================
; CONVERT HUMAN-FRIENDLY HEADER TO AHK HOTKEY
; ============================================================

HeaderToHotkey(header) {

    parts := StrSplit(
        header,
        "+"
    )

    hasCtrl := false
    hasAlt := false
    hasShift := false
    hasWin := false

    key := ""

    for part in parts {

        item := StrUpper(
            Trim(part)
        )

        switch item {

            case "CTRL", "CONTROL":
                hasCtrl := true

            case "ALT":
                hasAlt := true

            case "SHIFT":
                hasShift := true

            case "WIN", "WINDOWS":
                hasWin := true

            default:
                key := NormalizeKeyName(item)
        }
    }

    ; We deliberately require at least one modifier.
    ; This prevents normal comments from becoming hotkeys.
    if !(
        hasCtrl
        || hasAlt
        || hasShift
        || hasWin
    )
        return ""

    if (key = "")
        return ""

    hotkey := ""

    if hasCtrl
        hotkey .= "^"

    if hasAlt
        hotkey .= "!"

    if hasShift
        hotkey .= "+"

    if hasWin
        hotkey .= "#"

    hotkey .= key

    return hotkey
}


; ============================================================
; NORMALIZE KEY NAMES
; ============================================================

NormalizeKeyName(key) {

    switch key {

        case "SPACE":
            return "Space"

        case "ENTER":
            return "Enter"

        case "TAB":
            return "Tab"

        case "ESC", "ESCAPE":
            return "Esc"

        case "DELETE", "DEL":
            return "Delete"

        case "BACKSPACE":
            return "Backspace"

        case "UP":
            return "Up"

        case "DOWN":
            return "Down"

        case "LEFT":
            return "Left"

        case "RIGHT":
            return "Right"
    }

    ; F1-F24
    if RegExMatch(
        key,
        "^F([1-9]|1[0-9]|2[0-4])$"
    )
        return key

    ; Normal single character.
    if (StrLen(key) = 1)
        return StrLower(key)

    return ""
}


; ============================================================
; REMOVE OPTIONAL QUOTES
; ============================================================

RemoveQuotes(value) {

    if (StrLen(value) < 2)
        return value

    first := SubStr(
        value,
        1,
        1
    )

    last := SubStr(
        value,
        -1
    )

    if (
        first = last
        && (
            first = Chr(34)
            || first = "'"
        )
    ) {
        return SubStr(
            value,
            2,
            StrLen(value) - 2
        )
    }

    return value
}
