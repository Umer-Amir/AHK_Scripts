#Requires AutoHotkey v2.0
#SingleInstance Force

; Press Ctrl + Shift + V to run the split-paste action
^+b::
{
    ; Check if clipboard has text and contains an underscore
    if (A_Clipboard != "" && InStr(A_Clipboard, "_"))
    {
        ; Split the clipboard text at the first underscore
        parts := StrSplit(A_Clipboard, "_", , 2)
        part1 := parts[1]
        part2 := parts[2]
        
        ; 1. Paste the first part into the current Excel cell
        SendInput("{Text}" part1)
        Sleep(50) ; Tiny pause to let Excel process the keystroke
        
        ; 2. Move one cell to the right
        SendInput("{Tab}")
        Sleep(50)
        
        ; 3. Paste the second part into the new cell
        SendInput("{Text}" part2)
    }
    else
    {
        ; Fallback: If there is no underscore, just do a normal paste
        SendInput("^v")
    }
}