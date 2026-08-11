#Requires AutoHotkey v2.0

; Universal fast paste helper (Excel-safe)
PasteText(text) {
    SavedClip := ClipboardAll()  ; Backup original clipboard state (including formatted text/cells)
    A_Clipboard := ""            ; Clear clipboard so ClipWait can detect new data
    A_Clipboard := text
    ClipWait(1)                  ; Wait up to 1 second for clipboard to register
    
    Send("^v")                   ; Execute Paste
    Sleep(100)                   ; Give Excel time to absorb the paste before restoring clipboard
    
    A_Clipboard := SavedClip     ; Restore previous clipboard
}

; Pipeline Variables
:?*:aa::
{
    PasteText("@pipeline().libraryVariables.FinanceFabricEnvironmentConfiguration_Warehouse_Connection.connectionId")
}

:?*:ss::
{
    PasteText("@pipeline().libraryVariables.FinanceFabricEnvironmentConfiguration_Workspace_ID")
}

:?*:dd::
{
    PasteText("@pipeline().libraryVariables.FinanceFabricEnvironmentConfiguration_Warehouse_ID")
}

:?*:ff::
{
    PasteText("@pipeline().libraryVariables.FinanceFabricEnvironmentConfiguration_Warehouse_SQL_Endpoint")
}

; Status Emojis
:?*:qq::
{
    PasteText("✅")
}

:?*:ww::
{
    PasteText("❌")
}