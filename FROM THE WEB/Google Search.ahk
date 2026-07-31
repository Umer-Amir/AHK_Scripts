!g:: {
    ; Save clipboard contents, clear it, copy selected text
    OldClip := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if ClipWait(1) {
        ; Open default browser with the search query
        Run("https://www.google.com/search?q=" . DownloadString(A_Clipboard))
    }
    A_Clipboard := OldClip ; Restore original clipboard
}

; Helper function to format text cleanly for a URL string
DownloadString(str) {
    return RegExReplace(str, "\s+", "+")
}