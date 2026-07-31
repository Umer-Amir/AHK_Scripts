#Requires AutoHotkey v2.0
#SingleInstance Force

!w:: {
    SavedClipboard := ClipboardAll()
    A_Clipboard := ""

    Send("^c")

    if !ClipWait(1) {
        A_Clipboard := SavedClipboard
        return
    }

    SelectedText := Trim(A_Clipboard, " `t`r`n")

    A_Clipboard := "TRIM(" SelectedText ") AS " SelectedText
    ClipWait(1)

    Send("^v")
    Sleep(150)

    A_Clipboard := SavedClipboard
}