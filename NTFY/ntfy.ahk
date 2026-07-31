#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; SETTINGS
; ============================================================

global NTFY_SERVER := "https://ntfy.sh"
global NTFY_TOPIC := LoadEnvValue("NTFY_TOPIC")

; Leave some room below ntfy's message-size limit.
global MAX_MESSAGE_BYTES := 3500

; ============================================================
; GUI VARIABLES
; ============================================================

global MessageGui := ""
global MessageEdit := ""
global StatusText := ""
global SendButton := ""

; Alt + W
!w::ShowMessageWindow()

; ============================================================
; OPEN WINDOW
; ============================================================

ShowMessageWindow() {
    global MessageGui
    global MessageEdit
    global StatusText
    global SendButton

    if IsObject(MessageGui) {
        MessageGui.Show()
        MessageEdit.Focus()
        return
    }

    MessageGui := Gui("+AlwaysOnTop", "Send Message to Phone")
    MessageGui.SetFont("s10", "Segoe UI")
    MessageGui.MarginX := 14
    MessageGui.MarginY := 14

    MessageGui.AddText("xm", "Message:")

    MessageEdit := MessageGui.AddEdit(
        "xm y+6 w560 r14 WantTab"
    )

    SendButton := MessageGui.AddButton(
        "xm y+12 w120 h34 Default",
        "Send"
    )

    clearButton := MessageGui.AddButton(
        "x+10 w120 h34",
        "Clear"
    )

    cancelButton := MessageGui.AddButton(
        "x+10 w120 h34",
        "Cancel"
    )

    StatusText := MessageGui.AddText(
        "xm y+12 w560",
        "Press Alt+W whenever you want to send a message."
    )

    SendButton.OnEvent(
        "Click",
        (*) => SendCurrentMessage()
    )

    clearButton.OnEvent(
        "Click",
        (*) => ClearMessage()
    )

    cancelButton.OnEvent(
        "Click",
        (*) => HideMessageWindow()
    )

    MessageGui.OnEvent(
        "Close",
        (*) => HideMessageWindow()
    )

    MessageGui.OnEvent(
        "Escape",
        (*) => HideMessageWindow()
    )

    MessageGui.Show()
    MessageEdit.Focus()
}

; ============================================================
; BUTTON ACTIONS
; ============================================================

ClearMessage() {
    global MessageEdit
    global StatusText

    MessageEdit.Value := ""
    StatusText.Text := "Message cleared."
    MessageEdit.Focus()
}

HideMessageWindow() {
    global MessageGui

    if IsObject(MessageGui)
        MessageGui.Hide()
}

; ============================================================
; SEND CURRENT MESSAGE
; ============================================================

SendCurrentMessage() {
    global MessageEdit
    global StatusText
    global SendButton
    global MAX_MESSAGE_BYTES

    message := MessageEdit.Value

    if Trim(message) = "" {
        StatusText.Text := "Enter a message first."
        MessageEdit.Focus()
        return
    }

    SendButton.Enabled := false
    StatusText.Text := "Sending..."

    try {
        messageParts := SplitLongMessage(
            message,
            MAX_MESSAGE_BYTES
        )

        totalParts := messageParts.Length

        for partNumber, messagePart in messageParts {
            if totalParts = 1 {
                title := "Message from PC"
            } else {
                title := Format(
                    "Message from PC - {}/{}",
                    partNumber,
                    totalParts
                )
            }

            SendNtfyMessage(
                messagePart,
                title
            )
        }

        if totalParts = 1 {
            StatusText.Text := "Message sent successfully."
        } else {
            StatusText.Text := Format(
                "Long message sent in {} parts.",
                totalParts
            )
        }

        MessageEdit.Value := ""
        MessageEdit.Focus()
    }
    catch as err {
        StatusText.Text := "Failed: " err.Message
    }
    finally {
        SendButton.Enabled := true
    }
}

; ============================================================
; SEND TO NTFY
; ============================================================

SendNtfyMessage(message, title) {
    global NTFY_SERVER
    global NTFY_TOPIC

    url := RTrim(NTFY_SERVER, "/") "/" NTFY_TOPIC

    http := ComObject("WinHttp.WinHttpRequest.5.1")

    http.SetTimeouts(
        5000,
        5000,
        15000,
        15000
    )

    http.Open(
        "POST",
        url,
        false
    )

    http.SetRequestHeader(
        "Content-Type",
        "text/plain; charset=utf-8"
    )

    http.SetRequestHeader(
        "Title",
        title
    )

    http.SetRequestHeader(
        "Priority",
        "default"
    )

    http.SetRequestHeader(
        "Tags",
        "memo"
    )

    http.Send(message)

    statusCode := http.Status

    if statusCode < 200 || statusCode >= 300 {
        throw Error(
            Format(
                "ntfy returned HTTP status {}.",
                statusCode
            )
        )
    }
}

; ============================================================
; LONG-MESSAGE SUPPORT
; ============================================================

SplitLongMessage(text, maximumBytes) {
    parts := []

    while text != "" {
        if GetUtf8ByteLength(text) <= maximumBytes {
            parts.Push(text)
            break
        }

        fittingLength := FindFittingLength(
            text,
            maximumBytes
        )

        cutPosition := FindBreakPosition(
            text,
            fittingLength
        )

        currentPart := RTrim(
            SubStr(text, 1, cutPosition),
            " `t`r`n"
        )

        if currentPart = "" {
            cutPosition := fittingLength
            currentPart := SubStr(
                text,
                1,
                cutPosition
            )
        }

        parts.Push(currentPart)

        text := LTrim(
            SubStr(text, cutPosition + 1),
            " `t`r`n"
        )
    }

    return parts
}

FindFittingLength(text, maximumBytes) {
    low := 1
    high := StrLen(text)
    best := 1

    while low <= high {
        middle := Floor(
            (low + high) / 2
        )

        candidate := SubStr(
            text,
            1,
            middle
        )

        if GetUtf8ByteLength(candidate) <= maximumBytes {
            best := middle
            low := middle + 1
        } else {
            high := middle - 1
        }
    }

    return best
}

FindBreakPosition(text, maximumCharacters) {
    sample := SubStr(
        text,
        1,
        maximumCharacters
    )

    ; Prefer paragraph or line breaks.
    position := InStr(
        sample,
        "`n",
        false,
        -1
    )

    if position > 0
        return position

    ; Otherwise use the last space.
    position := InStr(
        sample,
        " ",
        false,
        -1
    )

    if position > Floor(maximumCharacters * 0.5)
        return position

    return maximumCharacters
}

GetUtf8ByteLength(text) {
    return StrPut(text, "UTF-8") - 1
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
