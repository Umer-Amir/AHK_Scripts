#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; SETTINGS
; ============================================================

; The shared .env file is one directory above this script.
global ENV_FILE := A_ScriptDir . "\..\.env"

global AUTOCOMPLETE_EMAIL := LoadEnvValue(
    "AUTOCOMPLETE_EMAIL",
    ENV_FILE
)

global AUTOCOMPLETE_PASSWORD := LoadEnvValue(
    "AUTOCOMPLETE_PASSWORD",
    ENV_FILE
)

global AUTOCOMPLETE_SELECT := LoadEnvValue(
    "AUTOCOMPLETE_SELECT",
    ENV_FILE
)

; ============================================================
; HOTSTRINGS
; ============================================================

; Type the trigger and then an ending character such as Space or Enter.
Hotstring("::;email", TypeEmail)
Hotstring("::;password", TypePassword)
Hotstring("::;select", TypeSelectQuery)

TypeEmail(*) {
    global AUTOCOMPLETE_EMAIL
    SendText(AUTOCOMPLETE_EMAIL)
}

TypePassword(*) {
    global AUTOCOMPLETE_PASSWORD
    SendText(AUTOCOMPLETE_PASSWORD)
}

TypeSelectQuery(*) {
    global AUTOCOMPLETE_SELECT
    SendText(AUTOCOMPLETE_SELECT)
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

        ; Accept both KEY=value and export KEY=value.
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
