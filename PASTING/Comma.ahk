^!,:: ; Hotkey: Ctrl + Alt + Comma
{
    ; Send Ctrl+C to copy selected text
    A_Clipboard := ""
    Send("^c")
    if !ClipWait(1)
        return

    ; Process clipboard text
    text := A_Clipboard
    lines := StrSplit(text, "`n", "`r")
    output := ""

    for index, line in lines {
        if (line != "") {
            output .= line . ",`n"
        }
    }

    ; Trim trailing newline and update clipboard
    A_Clipboard := RTrim(output, "`n")
    
    ; Paste the modified text
    Send("^v")
}