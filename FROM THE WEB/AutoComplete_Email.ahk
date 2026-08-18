#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; .env is one directory above this script.
global ENV_FILE := A_ScriptDir "\..\.env"
global Config := ""
global IsSending := false
global ActiveChords := Map()
global RegisteredHotkeys := Map()

if !FileExist(ENV_FILE) {
    MsgBox("Could not find .env file:`n`n" ENV_FILE, "AHK AutoComplete", "Iconx")
    ExitApp
}

try Config := ParseEnv()
catch as err {
    MsgBox("Could not read .env:`n`n" err.Message, "AHK AutoComplete", "Iconx")
    ExitApp
}

RegisterDefinitions()
Persistent

; Alt+1: edit .env. Alt+2: fully restart after one second.
!1::OpenEnvFile()
!2::RestartThisScript()

OpenEnvFile() {
    global ENV_FILE
    if FileExist(ENV_FILE)
        Run('notepad.exe "' ENV_FILE '"')
}

RestartThisScript() {
    restartCommand := A_ComSpec
        . ' /d /c "timeout /t 1 /nobreak >nul & start "" "'
        . A_AhkPath . '" "' . A_ScriptFullPath . '""'
    Run(restartCommand, , "Hide")
    ExitApp
}

RegisterDefinitions() {
    global Config, RegisteredHotkeys

    ; Autocomplete definitions become ;email, ;password, etc.
    for envKey, value in Config.AutoComplete {
        suffix := RegExReplace(envKey, "i)^AUTOCOMPLETE_", "")
        if (suffix != envKey)
            Hotstring("::;" StrLower(suffix), AutoCompleteHandler.Bind(value))
    }

    ; Native hotstrings reliably handle AA=..., SS=..., etc. The pair is
    ; erased by AHK itself and the replacement is pasted from the clipboard.
    ; No ending character is required, and matching remains case-insensitive.
    for pair, value in Config.DoubleTap
        Hotstring(":*:" StrLower(pair), AutoCompleteHandler.Bind(value))

    ; One physical-only hook per key. Unlike AHK custom combinations, these
    ; hooks do not turn normal letters into prefix keys.
    trackedKeys := Map()
    for key, _ in Config.ConsecutiveDouble {
        ; If AA and DOUBLE A both exist, AA is the unambiguous native
        ; hotstring and takes precedence for that key.
        if !Config.DoubleTap.Has(StrUpper(key key))
            trackedKeys[key] := true
    }
    for _, chord in Config.Chords {
        trackedKeys[chord.Key1] := true
        trackedKeys[chord.Key2] := true
    }

    for key, _ in trackedKeys {
        hotkeyName := "~*$" key
        Hotkey(hotkeyName, PhysicalKeyHandler.Bind(key))
        RegisteredHotkeys[hotkeyName] := true
    }

    for hotkeyName, value in Config.Hotkeys {
        Hotkey(hotkeyName, CustomHotkeyHandler.Bind(value))
        RegisteredHotkeys[hotkeyName] := true
    }
}

AutoCompleteHandler(value, *) {
    SafeSendText(value)
}

CustomHotkeyHandler(value, *) {
    SafeSendText(value)
}

SafeSendText(value) {
    global IsSending
    if IsSending
        return

    IsSending := true
    try {
        ; Give the physical trigger/terminator time to be released, then paste
        ; the value through the clipboard instead of generating letter keys.
        Sleep(20)
        PasteTextPreservingClipboard(value)
    }
    finally IsSending := false
}

PasteTextPreservingClipboard(value) {
    if (value = "")
        return

    previousClipboard := ClipboardAll()
    try {
        A_Clipboard := ""
        A_Clipboard := value
        if !ClipWait(1)
            throw Error("Could not place the autocomplete value on the clipboard.")

        Send("^v")

        ; Some applications process Ctrl+V asynchronously. Restoring too soon
        ; can make them paste the old clipboard value instead.
        Sleep(200)
    }
    finally {
        A_Clipboard := previousClipboard
        previousClipboard := ""
    }
}

PhysicalKeyHandler(key, *) {
    global Config, IsSending
    if IsSending
        return

    ; A chord wins over a double-press rule when its other key is held.
    if TryTriggerChord(key)
        return

    isConsecutive := (StrLower(A_PriorKey) = StrLower(key))

    if (isConsecutive && Config.ConsecutiveDouble.Has(key)) {
        SetTimer(ReplaceTypedKeys.Bind(2, Config.ConsecutiveDouble[key]), -20)
        return
    }
}

TryTriggerChord(pressedKey) {
    global Config, ActiveChords

    for chordId, chord in Config.Chords {
        if (pressedKey != chord.Key1 && pressedKey != chord.Key2)
            continue

        otherKey := (pressedKey = chord.Key1) ? chord.Key2 : chord.Key1
        if !GetKeyState(otherKey, "P")
            continue

        ; Holding the keys must not repeatedly retrigger the chord.
        if ActiveChords.Has(chordId)
            return true

        ActiveChords[chordId] := true
        SetTimer(ReplaceTypedKeys.Bind(2, chord.Value), -20)
        SetTimer(ReleaseChordLatch.Bind(chordId, chord.Key1, chord.Key2), -25)

        generation := A_TickCount
        chord.Generation := generation
        Config.Chords[chordId] := chord
        SetTimer(ExpireChordValue.Bind(chordId, generation, chord.Value),
            -Max(1, Round(chord.Seconds * 1000)))
        return true
    }
    return false
}

ReleaseChordLatch(chordId, key1, key2, *) {
    global ActiveChords
    if GetKeyState(key1, "P") || GetKeyState(key2, "P") {
        SetTimer(ReleaseChordLatch.Bind(chordId, key1, key2), -25)
        return
    }
    if ActiveChords.Has(chordId)
        ActiveChords.Delete(chordId)
}

ReplaceTypedKeys(characterCount, value, *) {
    global IsSending
    if IsSending
        return
    IsSending := true
    try {
        SendLevel(0)
        Send("{Backspace " characterCount "}")
        PasteTextPreservingClipboard(value)
    }
    finally IsSending := false
}

ExpireChordValue(chordId, generation, value, *) {
    global Config, IsSending
    if !Config.Chords.Has(chordId)
        return
    chord := Config.Chords[chordId]
    if !chord.HasOwnProp("Generation") || chord.Generation != generation
        return

    ; Only erase when the caret is still immediately after the inserted value.
    ; Blind delayed backspacing could otherwise delete unrelated later typing.
    ; The value therefore remains if the user has typed anything afterward.
    if (A_TimeIdleKeyboard < Max(50, Round(chord.Seconds * 1000) - 50))
        return

    if IsSending
        return
    IsSending := true
    try Send("{Backspace " StrLen(value) "}")
    finally IsSending := false
}

ParseEnv() {
    global ENV_FILE
    parsedDefinitions := {
        AutoComplete: Map(), DoubleTap: Map(), ConsecutiveDouble: Map(),
        Chords: Map(), Hotkeys: Map()
    }

    fileContents := FileRead(ENV_FILE, "UTF-8")
    currentSection := ""
    currentHotkey := ""

    for rawLine in StrSplit(fileContents, "`n", "`r") {
        line := Trim(rawLine, " `t" Chr(0xFEFF))
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        if (SubStr(line, 1, 1) = "#") {
            header := Trim(SubStr(line, 2))
            headerLower := StrLower(header)
            if (headerLower = "autocomplete") {
                currentSection := "AUTOCOMPLETE", currentHotkey := ""
                continue
            }
            if (headerLower = "double tap" || headerLower = "doubletap") {
                currentSection := "DOUBLETAP", currentHotkey := ""
                continue
            }
            possibleHotkey := HeaderToHotkey(header)
            if (possibleHotkey != "") {
                currentSection := "HOTKEY", currentHotkey := possibleHotkey
                parsedDefinitions.Hotkeys[currentHotkey] := ""
            }
            continue
        }

        if RegExMatch(line, "i)^DOUBLE\s+([^\s=]+)\s*=\s*(.*)$", &m) {
            key := NormalizeKeyName(StrUpper(Trim(m[1])))
            if (key != "")
                parsedDefinitions.ConsecutiveDouble[key] := RemoveQuotes(Trim(m[2]))
            continue
        }

        if RegExMatch(line,
            "i)^([^\s~=]+)\s*~\s*([^\s=]+)\s+([0-9]+(?:\.[0-9]+)?)\s*=\s*(.*)$", &m) {
            key1 := NormalizeKeyName(StrUpper(Trim(m[1])))
            key2 := NormalizeKeyName(StrUpper(Trim(m[2])))
            seconds := m[3] + 0
            if (key1 != "" && key2 != "" && key1 != key2 && seconds > 0) {
                chordId := key1 "~" key2
                parsedDefinitions.Chords[chordId] := {
                    Key1: key1, Key2: key2, Seconds: seconds,
                    Value: RemoveQuotes(Trim(m[4]))
                }
            }
            continue
        }

        equalsPosition := InStr(line, "=")
        if equalsPosition {
            leftSide := Trim(SubStr(line, 1, equalsPosition - 1))
            possibleHotkey := HeaderToHotkey(leftSide)
            if (possibleHotkey != "") {
                parsedDefinitions.Hotkeys[possibleHotkey] := RemoveQuotes(
                    Trim(SubStr(line, equalsPosition + 1)))
                continue
            }

            ; AA=..., SS=..., etc. work anywhere in the file and do not
            ; depend on the current section heading.
            if RegExMatch(leftSide, "i)^([A-Z0-9])\1$") {
                parsedDefinitions.DoubleTap[StrUpper(leftSide)] := RemoveQuotes(
                    Trim(SubStr(line, equalsPosition + 1)))
                continue
            }
        }

        if (currentSection = "AUTOCOMPLETE" && equalsPosition) {
            key := Trim(SubStr(line, 1, equalsPosition - 1))
            value := RemoveQuotes(Trim(SubStr(line, equalsPosition + 1)))
            if RegExMatch(key, "i)^AUTOCOMPLETE_")
                parsedDefinitions.AutoComplete[key] := value
            continue
        }

        if (currentSection = "DOUBLETAP" && equalsPosition) {
            key := StrUpper(Trim(SubStr(line, 1, equalsPosition - 1)))
            value := RemoveQuotes(Trim(SubStr(line, equalsPosition + 1)))
            if RegExMatch(key, "i)^([A-Z0-9])\1$")
                parsedDefinitions.DoubleTap[key] := value
            continue
        }

        if (currentSection = "HOTKEY" && currentHotkey != "") {
            value := RemoveQuotes(line)
            parsedDefinitions.Hotkeys[currentHotkey] .=
                (parsedDefinitions.Hotkeys[currentHotkey] = "" ? "" : "`n") value
        }
    }
    return parsedDefinitions
}

HeaderToHotkey(header) {
    parts := StrSplit(header, "+")
    hasCtrl := false, hasAlt := false, hasShift := false, hasWin := false
    key := ""

    for part in parts {
        item := StrUpper(Trim(part))
        switch item {
            case "CTRL", "CONTROL": hasCtrl := true
            case "ALT": hasAlt := true
            case "SHIFT": hasShift := true
            case "WIN", "WINDOWS": hasWin := true
            default: key := NormalizeKeyName(item)
        }
    }

    if !(hasCtrl || hasAlt || hasShift || hasWin) || key = ""
        return ""
    return (hasCtrl ? "^" : "") . (hasAlt ? "!" : "")
        . (hasShift ? "+" : "") . (hasWin ? "#" : "") . key
}

NormalizeKeyName(key) {
    switch key {
        case "SPACE": return "Space"
        case "ENTER": return "Enter"
        case "TAB": return "Tab"
        case "ESC", "ESCAPE": return "Esc"
        case "DELETE", "DEL": return "Delete"
        case "BACKSPACE": return "Backspace"
        case "UP": return "Up"
        case "DOWN": return "Down"
        case "LEFT": return "Left"
        case "RIGHT": return "Right"
    }
    if RegExMatch(key, "^F([1-9]|1[0-9]|2[0-4])$")
        return key
    return (StrLen(key) = 1) ? StrLower(key) : ""
}

RemoveQuotes(value) {
    if (StrLen(value) < 2)
        return value
    first := SubStr(value, 1, 1), last := SubStr(value, -1)
    if (first = last && (first = Chr(34) || first = "'"))
        return SubStr(value, 2, StrLen(value) - 2)
    return value
}
