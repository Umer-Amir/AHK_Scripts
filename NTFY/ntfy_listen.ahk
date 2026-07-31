#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; SETTINGS
; ============================================================

global NTFY_SERVER := "https://ntfy.sh"

; Loaded from .env in the same folder as this script.
global NTFY_TOPIC := LoadEnvValue("NTFY_TOPIC")

; How often the laptop checks for messages.
global POLL_INTERVAL_MS := 2000

; Automatically copy every received message.
global AUTO_COPY_MESSAGE := true

; Received messages are also saved here.
global INBOX_LOG_FILE := A_ScriptDir . "\Phone Inbox.txt"

; ============================================================
; INTERNAL STATE
; ============================================================

global LastMessageCursor := ""
global MessageQueue := []

global PopupGui := ""
global PopupIsOpen := false

global CurrentMessage := ""
global CurrentUrl := ""
global CurrentStatusText := ""

; ============================================================
; STARTUP
; ============================================================

InitializePhoneReceiver()

; Check every two seconds.
SetTimer(CheckForPhoneMessages, POLL_INTERVAL_MS)

; Optional manual shortcuts:
; Ctrl + Alt + R = check immediately
; Ctrl + Alt + I = open message history

^!r::CheckForPhoneMessages()
^!i::OpenInboxLog()

; ============================================================
; INITIALIZATION
; ============================================================

InitializePhoneReceiver() {
    global NTFY_TOPIC
    global LastMessageCursor
    global POLL_INTERVAL_MS

    ; Establish a starting position without displaying
    ; previously cached messages.
    LastMessageCursor := GetInitialMessageCursor()

    ; Replace the normal tray menu.
    A_TrayMenu.Delete()

    A_TrayMenu.Add(
        "Check now",
        (*) => CheckForPhoneMessages()
    )

    A_TrayMenu.Add(
        "Open inbox history",
        (*) => OpenInboxLog()
    )

    A_TrayMenu.Add()

    A_TrayMenu.Add(
        "Exit receiver",
        (*) => ExitApp()
    )

    TrayTip(
        "Listening for phone messages every "
        . Round(POLL_INTERVAL_MS / 1000)
        . " seconds.",
        "ntfy Receiver"
    )
}

GetInitialMessageCursor() {
    global NTFY_SERVER
    global NTFY_TOPIC

    url := RTrim(NTFY_SERVER, "/")
        . "/"
        . NTFY_TOPIC
        . "/json?poll=1&since=latest"

    try {
        response := HttpGet(url)
        messages := ParseNtfyResponse(response)

        if (messages.Length > 0) {
            latestMessage := messages[messages.Length]
            return latestMessage["id"]
        }
    }
    catch {
        ; If initialization cannot reach ntfy, start from
        ; the current time instead.
    }

    return GetCurrentUnixTime()
}

GetCurrentUnixTime() {
    return DateDiff(
        A_NowUTC,
        "19700101000000",
        "Seconds"
    )
}

; ============================================================
; POLLING
; ============================================================

CheckForPhoneMessages(*) {
    global NTFY_SERVER
    global NTFY_TOPIC
    global LastMessageCursor

    static CheckIsRunning := false
    static PreviousError := ""

    if CheckIsRunning
        return

    CheckIsRunning := true

    try {
        url := RTrim(NTFY_SERVER, "/")
            . "/"
            . NTFY_TOPIC
            . "/json?poll=1&since="
            . LastMessageCursor

        response := HttpGet(url)
        messages := ParseNtfyResponse(response)

        for messageNumber, messageData in messages {
            LastMessageCursor := messageData["id"]
            HandleIncomingMessage(messageData)
        }

        PreviousError := ""
    }
    catch as error {
        ; Avoid displaying the same network error every
        ; two seconds.
        if (error.Message != PreviousError) {
            PreviousError := error.Message

            TrayTip(
                error.Message,
                "ntfy Receiver Error",
                2
            )
        }
    }
    finally {
        CheckIsRunning := false
    }
}

HttpGet(url) {
    http := ComObject(
        "WinHttp.WinHttpRequest.5.1"
    )

    http.SetTimeouts(
        5000,
        5000,
        10000,
        10000
    )

    http.Open(
        "GET",
        url,
        false
    )

    http.Send()

    statusCode := http.Status

    if (
        statusCode < 200
        || statusCode >= 300
    ) {
        throw Error(
            Format(
                "ntfy returned HTTP status {}.",
                statusCode
            )
        )
    }

    return http.ResponseText
}

; ============================================================
; PARSE NTFY RESPONSE
; ============================================================

ParseNtfyResponse(response) {
    messages := []

    responseLines := StrSplit(
        response,
        "`n",
        "`r"
    )

    for lineNumber, jsonLine in responseLines {
        jsonLine := Trim(jsonLine)

        if (jsonLine = "")
            continue

        eventType := JsonGetString(
            jsonLine,
            "event"
        )

        if (eventType != "message")
            continue

        messageId := JsonGetString(
            jsonLine,
            "id"
        )

        if (messageId = "")
            continue

        messageText := JsonGetString(
            jsonLine,
            "message"
        )

        messageTitle := JsonGetString(
            jsonLine,
            "title"
        )

        clickUrl := JsonGetString(
            jsonLine,
            "click"
        )

        if (messageTitle = "")
            messageTitle := "Message from Phone"

        messages.Push(
            Map(
                "id", messageId,
                "title", messageTitle,
                "message", messageText,
                "click", clickUrl
            )
        )
    }

    return messages
}

JsonGetString(jsonText, propertyName) {
    quote := Chr(34)

    pattern := quote
        . propertyName
        . quote
        . "\s*:\s*"
        . quote
        . "((?:\\.|[^"
        . quote
        . "\\])*)"
        . quote

    if RegExMatch(
        jsonText,
        pattern,
        &match
    ) {
        return JsonUnescape(match[1])
    }

    return ""
}

JsonUnescape(value) {
    result := ""
    position := 1
    textLength := StrLen(value)

    while (position <= textLength) {
        character := SubStr(
            value,
            position,
            1
        )

        if (character != "\") {
            result .= character
            position += 1
            continue
        }

        if (position = textLength) {
            result .= "\"
            break
        }

        escapedCharacter := SubStr(
            value,
            position + 1,
            1
        )

        switch escapedCharacter {
            case Chr(34):
                result .= Chr(34)
                position += 2

            case "\":
                result .= "\"
                position += 2

            case "/":
                result .= "/"
                position += 2

            case "b":
                result .= Chr(8)
                position += 2

            case "f":
                result .= Chr(12)
                position += 2

            case "n":
                result .= "`n"
                position += 2

            case "r":
                result .= "`r"
                position += 2

            case "t":
                result .= "`t"
                position += 2

            case "u":
                hexValue := SubStr(
                    value,
                    position + 2,
                    4
                )

                if RegExMatch(
                    hexValue,
                    "i)^[0-9a-f]{4}$"
                ) {
                    unicodeValue := Integer(
                        "0x" . hexValue
                    )

                    ; Support Unicode surrogate pairs,
                    ; including many emoji.
                    if (
                        unicodeValue >= 0xD800
                        && unicodeValue <= 0xDBFF
                        && SubStr(
                            value,
                            position + 6,
                            2
                        ) = "\u"
                    ) {
                        lowHexValue := SubStr(
                            value,
                            position + 8,
                            4
                        )

                        if RegExMatch(
                            lowHexValue,
                            "i)^[0-9a-f]{4}$"
                        ) {
                            lowUnicodeValue := Integer(
                                "0x" . lowHexValue
                            )

                            if (
                                lowUnicodeValue >= 0xDC00
                                && lowUnicodeValue <= 0xDFFF
                            ) {
                                completeUnicodeValue :=
                                    0x10000
                                    + (
                                        (
                                            unicodeValue
                                            - 0xD800
                                        ) << 10
                                    )
                                    + (
                                        lowUnicodeValue
                                        - 0xDC00
                                    )

                                result .= Chr(
                                    completeUnicodeValue
                                )

                                position += 12
                                continue
                            }
                        }
                    }

                    result .= Chr(unicodeValue)
                    position += 6
                } else {
                    result .= "\u"
                    position += 2
                }

            default:
                result .= escapedCharacter
                position += 2
        }
    }

    return result
}

; ============================================================
; HANDLE RECEIVED MESSAGE
; ============================================================

HandleIncomingMessage(messageData) {
    global AUTO_COPY_MESSAGE
    global INBOX_LOG_FILE
    global MessageQueue
    global PopupIsOpen

    messageText := messageData["message"]
    messageTitle := messageData["title"]
    clickUrl := messageData["click"]

    if AUTO_COPY_MESSAGE
        A_Clipboard := messageText

    if (clickUrl = "")
        clickUrl := FindFirstUrl(messageText)

    messageData["url"] := clickUrl

    SaveMessageToInbox(
        messageTitle,
        messageText
    )

    MessageQueue.Push(messageData)

    if !PopupIsOpen
        ShowNextMessage()
}

SaveMessageToInbox(title, message) {
    global INBOX_LOG_FILE

    receivedTime := FormatTime(
        ,
        "yyyy-MM-dd HH:mm:ss"
    )

    logEntry := "["
        . receivedTime
        . "] "
        . title
        . "`r`n"
        . message
        . "`r`n"
        . "--------------------------------------------------"
        . "`r`n`r`n"

    try {
        FileAppend(
            logEntry,
            INBOX_LOG_FILE,
            "UTF-8"
        )
    }
}

FindFirstUrl(message) {
    pattern := "i)\bhttps?://[^\s<>]+"

    if RegExMatch(message, pattern, &match) {
        ; Remove punctuation that may appear after the URL.
        return RTrim(match[0], ".,;:!?)]}")
    }

    return ""
}

; ============================================================
; MESSAGE POPUP
; ============================================================

ShowNextMessage() {
    global MessageQueue
    global PopupGui
    global PopupIsOpen
    global CurrentMessage
    global CurrentUrl
    global CurrentStatusText
    global AUTO_COPY_MESSAGE

    if (MessageQueue.Length = 0) {
        PopupIsOpen := false
        return
    }

    messageData := MessageQueue.RemoveAt(1)

    CurrentMessage := messageData["message"]
    CurrentUrl := messageData["url"]
    PopupIsOpen := true

    PopupGui := Gui(
        "+AlwaysOnTop +Resize",
        messageData["title"]
    )

    PopupGui.SetFont(
        "s10",
        "Segoe UI"
    )

    PopupGui.MarginX := 15
    PopupGui.MarginY := 15

    PopupGui.AddText(
        "xm w620",
        messageData["title"]
    ).SetFont("s11 Bold")

    PopupGui.AddEdit(
        "xm y+10 w620 r15 ReadOnly",
        CurrentMessage
    )

    copyButton := PopupGui.AddButton(
        "xm y+12 w120 h34 Default",
        "Copy"
    )

    openButton := PopupGui.AddButton(
        "x+10 w120 h34",
        "Open Link"
    )

    dismissButton := PopupGui.AddButton(
        "x+10 w120 h34",
        "Dismiss"
    )

    if (CurrentUrl = "")
        openButton.Enabled := false

    statusMessage := AUTO_COPY_MESSAGE
        ? "Message copied to clipboard automatically."
        : "Message received."

    CurrentStatusText := PopupGui.AddText(
        "xm y+12 w620",
        statusMessage
    )

    copyButton.OnEvent(
        "Click",
        (*) => CopyCurrentMessage()
    )

    openButton.OnEvent(
        "Click",
        (*) => OpenCurrentLink()
    )

    dismissButton.OnEvent(
        "Click",
        (*) => DismissCurrentMessage()
    )

    PopupGui.OnEvent(
        "Close",
        (*) => DismissCurrentMessage()
    )

    PopupGui.OnEvent(
        "Escape",
        (*) => DismissCurrentMessage()
    )

    PopupGui.Show()

    TrayTip(
        CurrentMessage,
        messageData["title"]
    )
}

CopyCurrentMessage() {
    global CurrentMessage
    global CurrentStatusText

    A_Clipboard := CurrentMessage
    CurrentStatusText.Text := "Copied to clipboard."
}

OpenCurrentLink() {
    global CurrentUrl
    global CurrentStatusText

    if (CurrentUrl = "") {
        CurrentStatusText.Text :=
            "No web link was found in this message."

        return
    }

    try {
        Run(CurrentUrl)
        CurrentStatusText.Text := "Link opened."
    }
    catch as error {
        CurrentStatusText.Text :=
            "Could not open link: " . error.Message
    }
}

DismissCurrentMessage() {
    global PopupGui
    global PopupIsOpen
    global MessageQueue

    if IsObject(PopupGui) {
        try {
            PopupGui.Destroy()
        }
    }

    PopupGui := ""
    PopupIsOpen := false

    if (MessageQueue.Length > 0)
        ShowNextMessage()
}

; ============================================================
; HISTORY
; ============================================================

OpenInboxLog() {
    global INBOX_LOG_FILE

    if !FileExist(INBOX_LOG_FILE) {
        FileAppend(
            "",
            INBOX_LOG_FILE,
            "UTF-8"
        )
    }

    Run(INBOX_LOG_FILE)
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
