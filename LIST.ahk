#Requires AutoHotkey v2.0
#SingleInstance Force

; ==========================================================
; AHK Advanced Command Center
; ==========================================================

TargetFolder := "D:\Training\AG_Training_Umer\AHK Scripts"

; Leave blank to use Notepad.
; Example:
; EditorPath := "C:\Users\YOUR_NAME\AppData\Local\Programs\Microsoft VS Code\Code.exe"
EditorPath := ""

SettingsFile := A_ScriptDir "\AHK_CommandCenter_Settings.ini"
BackupFolder := A_ScriptDir "\_CommandCenter_Backups"
LogFile := "D:\Training\AG_Training_Umer\AHK Scripts\LIST_LOGS.txt"

RunningScripts := Map()
Scripts := Map()
FavoriteScripts := Map()
StartupScripts := Map()

AllRowPaths := Map()
RunningRowPaths := Map()
FavoriteRowPaths := Map()

ManagerGui := ""
Tabs := ""
SearchBox := ""
AllLV := ""
RunningLV := ""
FavoritesLV := ""
LogBox := ""

ContextPath := ""
LogLines := []

LoadSettings()
RefreshRunningScriptsFromWindows()
AutoRunStartupScripts()

!q::ShowScriptManager()


; ==========================================================
; GUI
; ==========================================================

ShowScriptManager() {
    global ManagerGui, Tabs, SearchBox, AllLV, RunningLV, FavoritesLV, LogBox
    global RunningScripts, FavoriteScripts
    FolderPickerResult := []
    FolderPickerConfirmed := false
    FolderPickerRowPaths := Map()
    

    DeleteConfirmResponse := { confirmed: false, backup: true }

    try {
        if IsObject(ManagerGui)
            ManagerGui.Destroy()
    }

    RefreshRunningScriptsFromWindows()
    BuildScriptIndex()

    MyGui := Gui("+Resize", "AHK Advanced Command Center")
    ManagerGui := MyGui

    MyGui.SetFont("s10", "Segoe UI")
    MyGui.OnEvent("Close", HandleGuiClose)
    MyGui.OnEvent("Escape", HandleGuiClose)

    MyGui.Add("Text", "x10 y12 w60", "Search:")
    SearchBox := MyGui.Add("Edit", "x75 y10 w890")
    SearchBox.OnEvent("Change", (*) => RefreshUI(false))

    Tabs := MyGui.Add("Tab3", "x10 y45 w975 h505", [
        "All Scripts",
        "Running " RunningScripts.Count,
        "Favorites " GetExistingFavoriteCount()
    ])

    ; ======================================================
    ; TAB 1: ALL SCRIPTS
    ; ======================================================
    Tabs.UseTab(1)

    AllLV := MyGui.Add("ListView", "x20 y85 w955 h455 Checked Grid", [
        "Script Name",
        "Category",
        "Status",
        "Shortcut",
        "PID",
        "RAM",
        "Last Modified",
        "Description",
        "Favorite",
        "Startup",
        "Edit"
    ])

    AllLV.ModifyCol(1, 210)
    AllLV.ModifyCol(2, 130)
    AllLV.ModifyCol(3, 80)
    AllLV.ModifyCol(4, 135)
    AllLV.ModifyCol(5, 60)
    AllLV.ModifyCol(6, 75)
    AllLV.ModifyCol(7, 130)
    AllLV.ModifyCol(8, 210)
    AllLV.ModifyCol(9, 70)
    AllLV.ModifyCol(10, 70)
    AllLV.ModifyCol(11, 60)

    AllLV.OnEvent("Click", AllLVClick)
    AllLV.OnEvent("DoubleClick", AllLVDoubleClick)
    AllLV.OnEvent("ContextMenu", AllLVContextMenu)
    

    ; ======================================================
    ; TAB 2: RUNNING
    ; ======================================================
    Tabs.UseTab(2)

    RunningLV := MyGui.Add("ListView", "x20 y85 w955 h455 Checked Grid", [
        "Script Name",
        "Category",
        "Shortcut",
        "PID",
        "RAM",
        "Last Modified",
        "Description"
    ])

    RunningLV.ModifyCol(1, 210)
    RunningLV.ModifyCol(2, 150)
    RunningLV.ModifyCol(3, 150)
    RunningLV.ModifyCol(4, 70)
    RunningLV.ModifyCol(5, 85)
    RunningLV.ModifyCol(6, 140)
    RunningLV.ModifyCol(7, 240)

    RunningLV.OnEvent("DoubleClick", RunningLVDoubleClick)
    RunningLV.OnEvent("ContextMenu", RunningLVContextMenu)

    ; ======================================================
    ; TAB 3: FAVORITES
    ; ======================================================
    Tabs.UseTab(3)

    FavoritesLV := MyGui.Add("ListView", "x20 y85 w955 h455 Checked Grid", [
        "Script Name",
        "Category",
        "Status",
        "Shortcut",
        "PID",
        "RAM",
        "Last Modified",
        "Description",
        "Startup"
    ])

    FavoritesLV.ModifyCol(1, 210)
    FavoritesLV.ModifyCol(2, 140)
    FavoritesLV.ModifyCol(3, 80)
    FavoritesLV.ModifyCol(4, 140)
    FavoritesLV.ModifyCol(5, 60)
    FavoritesLV.ModifyCol(6, 75)
    FavoritesLV.ModifyCol(7, 130)
    FavoritesLV.ModifyCol(8, 230)
    FavoritesLV.ModifyCol(9, 70)

    FavoritesLV.OnEvent("DoubleClick", FavoritesLVDoubleClick)
    FavoritesLV.OnEvent("ContextMenu", FavoritesLVContextMenu)

    Tabs.UseTab()

    ; ======================================================
    ; BUTTONS
    ; ======================================================
    BtnRun := MyGui.Add("Button", "x10 y570 w115", "Run Selected")
    BtnRun.OnEvent("Click", (*) => RunSelectedScripts())

    BtnStop := MyGui.Add("Button", "x135 y570 w115", "Stop Selected")
    BtnStop.OnEvent("Click", (*) => StopSelectedScripts())

    BtnRestart := MyGui.Add("Button", "x260 y570 w115", "Restart Selected")
    BtnRestart.OnEvent("Click", (*) => RestartSelectedScripts())

    BtnEdit := MyGui.Add("Button", "x385 y570 w115", "Edit Selected")
    BtnEdit.OnEvent("Click", (*) => EditSelectedScripts())

    BtnFolder := MyGui.Add("Button", "x510 y570 w115", "Open Folder")
    BtnFolder.OnEvent("Click", (*) => OpenSelectedFolders())

    BtnRefresh := MyGui.Add("Button", "x635 y570 w115", "Refresh List")
    BtnRefresh.OnEvent("Click", (*) => RefreshUI(true))

    BtnRunAll := MyGui.Add("Button", "x10 y605 w115", "Run All")
    BtnRunAll.OnEvent("Click", (*) => RunAllScripts())

    BtnStopAll := MyGui.Add("Button", "x135 y605 w115", "Stop All")
    BtnStopAll.OnEvent("Click", (*) => StopAllScriptsWithConfirm())

    BtnStartupRun := MyGui.Add("Button", "x260 y605 w115", "Run Startup")
    BtnStartupRun.OnEvent("Click", (*) => RunStartupScriptsNow())

    BtnFavorite := MyGui.Add("Button", "x385 y605 w115", "Favorite")
    BtnFavorite.OnEvent("Click", (*) => ToggleFavoriteForSelected())

    BtnStartup := MyGui.Add("Button", "x510 y605 w115", "Startup")
    BtnStartup.OnEvent("Click", (*) => ToggleStartupForSelected())

    BtnBackup := MyGui.Add("Button", "x635 y605 w115", "Backup Selected")
    BtnBackup.OnEvent("Click", (*) => BackupSelectedScripts())

    BtnAddScript := MyGui.Add("Button", "x760 y570 w110", "Add Script")
    BtnAddScript.OnEvent("Click", (*) => AddScriptPopup())

    BtnDeleteScript := MyGui.Add("Button","x760 y605 w110", "Delete Script")
    BtnDeleteScript.OnEvent("Click", (*) => DeleteSelectedScripts())

    BtnEditNotepad := MyGui.Add("Button", "x885 y570 w100", "Edit")
    BtnEditNotepad.OnEvent("Click", (*) => EditSelectedScriptsInNotepad())

    MyGui.Add("Text", "x10 y645 w100", "Log:")
    LogBox := MyGui.Add("Edit", "x10 y670 w965 h120 ReadOnly VScroll -Wrap")

    RefreshUI(false)

    MyGui.Show("w995 h810")
}


HandleGuiClose(GuiObj, *) {
    global ManagerGui

    try {
        GuiObj.Destroy()
    }

    ManagerGui := ""
}


RefreshUI(rebuildIndex := true) {
    global ManagerGui, SearchBox, AllLV, RunningLV, FavoritesLV

    if !IsObject(ManagerGui)
        return

    if rebuildIndex {
        RefreshRunningScriptsFromWindows()
        BuildScriptIndex()
    }

    filterText := IsObject(SearchBox) ? SearchBox.Value : ""

    RebuildAllScriptsList(AllLV, filterText)
    RebuildRunningList(RunningLV, filterText)
    RebuildFavoritesList(FavoritesLV, filterText)
    UpdateTabNames()
    RenderLogs()
}


UpdateTabNames() {
    global Tabs, RunningScripts

    try {
        Tabs.Text := [
            "All Scripts",
            "Running " RunningScripts.Count,
            "Favorites " GetExistingFavoriteCount()
        ]
    }
}


; ==========================================================
; SCRIPT INDEX
; ==========================================================

BuildScriptIndex() {
    global TargetFolder, RunningScripts, Scripts, FavoriteScripts, StartupScripts

    Scripts := Map()

    loop files, TargetFolder "\*.ahk", "R" {
        fullPath := A_LoopFileFullPath

        if ShouldSkipScript(fullPath)
            continue

        subDir := A_LoopFileDir
        category := (subDir = TargetFolder) ? "Main" : StrReplace(subDir, TargetFolder "\", "")

        isRunning := RunningScripts.Has(fullPath)
        pid := isRunning ? RunningScripts[fullPath] : "-"
        ram := isRunning ? GetProcessMemory(pid) : "-"
        status := isRunning ? "RUNNING" : "Stopped"

        Scripts[fullPath] := {
            name: A_LoopFileName,
            path: fullPath,
            folder: category,
            status: status,
            shortcut: GetScriptShortcuts(fullPath),
            pid: pid,
            ram: ram,
            description: GetScriptDescription(fullPath),
            modified: A_LoopFileTimeModified,
            favorite: FavoriteScripts.Has(fullPath),
            startup: StartupScripts.Has(fullPath)
        }
    }
}


; ==========================================================
; ALL SCRIPTS TAB - GROUPED LISTVIEW
; ==========================================================

RebuildAllScriptsList(LV, filterText) {
    global Scripts, AllRowPaths

    if !IsObject(LV)
        return

    LV.Delete()
    AllRowPaths := Map()

    groups := Map()
    lowerFilter := StrLower(Trim(filterText))

    for fullPath, item in Scripts {
        if !ScriptMatchesFilter(item, lowerFilter)
            continue

        folder := item.folder

        if !groups.Has(folder)
            groups[folder] := []

        groups[folder].Push(item)
    }

    folders := GetSortedFolderNames(groups)

    for folder in folders {
        count := groups[folder].Length

        ; Folder row: only name + number of scripts
       folderRow := LV.Add("", folder "_" count, "", "", "", "", "", "", "", "", "")
        LV.Modify(folderRow, "-Check")

        for item in groups[folder] {
            favoriteText := item.favorite ? "Yes" : "No"
            startupText := item.startup ? "Yes" : "No"

            rowNum := LV.Add(
                "",
                "- " item.name,
                item.folder,
                item.status,
                item.shortcut,
                item.pid,
                item.ram,
                FormatTime(item.modified, "yyyy-MM-dd HH:mm"),
                item.description,
                favoriteText,
                startupText,
                "Edit"
            )

            AllRowPaths[rowNum] := item.path

            if (item.status = "RUNNING")
                LV.Modify(rowNum, "+Check")
        }
    }
}


GetSortedFolderNames(groups) {
    folders := []

    if groups.Has("Main")
        folders.Push("Main")

    text := ""

    for folder, _ in groups {
        if (folder != "Main")
            text .= folder "`n"
    }

    text := RTrim(text, "`n")

    if (text != "") {
        sorted := Sort(text)

        loop parse, sorted, "`n" {
            if (A_LoopField != "")
                folders.Push(A_LoopField)
        }
    }

    return folders
}


; ==========================================================
; RUNNING TAB
; ==========================================================

RebuildRunningList(LV, filterText) {
    global Scripts, RunningRowPaths

    if !IsObject(LV)
        return

    LV.Delete()
    RunningRowPaths := Map()

    lowerFilter := StrLower(Trim(filterText))

    for fullPath, item in Scripts {
        if (item.status != "RUNNING")
            continue

        if !ScriptMatchesFilter(item, lowerFilter)
            continue

        rowNum := LV.Add(
            "",
            item.name,
            item.folder,
            item.shortcut,
            item.pid,
            item.ram,
            FormatTime(item.modified, "yyyy-MM-dd HH:mm"),
            item.description
        )

        RunningRowPaths[rowNum] := fullPath
        LV.Modify(rowNum, "+Check")
    }
}


; ==========================================================
; FAVORITES TAB
; ==========================================================

RebuildFavoritesList(LV, filterText) {
    global Scripts, FavoriteRowPaths

    if !IsObject(LV)
        return

    LV.Delete()
    FavoriteRowPaths := Map()

    lowerFilter := StrLower(Trim(filterText))

    for fullPath, item in Scripts {
        if !item.favorite
            continue

        if !ScriptMatchesFilter(item, lowerFilter)
            continue

        startupText := item.startup ? "Yes" : "No"

        rowNum := LV.Add(
            "",
            item.name,
            item.folder,
            item.status,
            item.shortcut,
            item.pid,
            item.ram,
            FormatTime(item.modified, "yyyy-MM-dd HH:mm"),
            item.description,
            startupText
        )

        FavoriteRowPaths[rowNum] := fullPath

        if (item.status = "RUNNING")
            LV.Modify(rowNum, "+Check")
    }
}


ScriptMatchesFilter(item, lowerFilter) {
    if (lowerFilter = "")
        return true

    haystack := StrLower(
        item.name " "
        item.folder " "
        item.status " "
        item.shortcut " "
        item.description " "
        item.path
    )

    return InStr(haystack, lowerFilter)
}


; ==========================================================
; SELECTION HELPERS
; ==========================================================

GetSelectedPaths(preferChecked := true) {
    global Tabs, AllLV, RunningLV, FavoritesLV
    global AllRowPaths, RunningRowPaths, FavoriteRowPaths

    paths := []

    if !IsObject(Tabs)
        return paths

    activeTab := Tabs.Value

    if (activeTab = 1) {
        AddListViewSelectedPaths(AllLV, AllRowPaths, paths, preferChecked)
    } else if (activeTab = 2) {
        AddListViewSelectedPaths(RunningLV, RunningRowPaths, paths, preferChecked)
    } else if (activeTab = 3) {
        AddListViewSelectedPaths(FavoritesLV, FavoriteRowPaths, paths, preferChecked)
    }

    return RemoveDuplicatePaths(paths)
}


AddListViewSelectedPaths(LV, rowMap, paths, preferChecked := true) {
    if preferChecked {
        rowNum := 0

        loop {
            rowNum := LV.GetNext(rowNum, "Checked")

            if !rowNum
                break

            if rowMap.Has(rowNum)
                paths.Push(rowMap[rowNum])
        }
    }

    ; In AHK v2, selected rows are fetched by omitting the second parameter.
    if (paths.Length = 0) {
        rowNum := 0

        loop {
            rowNum := LV.GetNext(rowNum)

            if !rowNum
                break

            if rowMap.Has(rowNum)
                paths.Push(rowMap[rowNum])
        }
    }
}


RemoveDuplicatePaths(paths) {
    seen := Map()
    unique := []

    for path in paths {
        if seen.Has(path)
            continue

        seen[path] := true
        unique.Push(path)
    }

    return unique
}


; ==========================================================
; BUTTON ACTIONS
; ==========================================================

RunSelectedScripts() {
    paths := GetSelectedPaths()

    if (paths.Length = 0) {
        AddLog("Nothing selected to run.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        RunSingleScript(fullPath)
    }

    RefreshUI(true)
}


StopSelectedScripts() {
    paths := GetSelectedPaths()

    if (paths.Length = 0) {
        AddLog("Nothing selected to stop.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        StopSingleScript(fullPath)
    }

    RefreshUI(true)
}


RestartSelectedScripts() {
    paths := GetSelectedPaths()

    if (paths.Length = 0) {
        AddLog("Nothing selected to restart.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        RestartSingleScript(fullPath)
    }

    RefreshUI(true)
}


EditSelectedScripts() {
    paths := GetSelectedPaths(false)

    if (paths.Length = 0) {
        AddLog("Nothing selected to edit.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        EditScript(fullPath)
    }

    RefreshUI(true)
}


OpenSelectedFolders() {
    paths := GetSelectedPaths(false)

    if (paths.Length = 0) {
        AddLog("Nothing selected to open folder.")
        RefreshUI(false)
        return
    }

    opened := Map()

    for fullPath in paths {
        SplitPath fullPath, , &dir

        if opened.Has(dir)
            continue

        opened[dir] := true
        OpenScriptFolder(fullPath)
    }

    RefreshUI(false)
}


RunAllScripts() {
    global Scripts

    for fullPath, item in Scripts {
        RunSingleScript(fullPath)
    }

    RefreshUI(true)
}


StopAllScriptsWithConfirm() {
    global RunningScripts

    count := RunningScripts.Count

    if (count = 0) {
        AddLog("No running scripts to stop.")
        RefreshUI(false)
        return
    }

    result := MsgBox(
        "Are you sure you want to stop all " count " running script(s)?",
        "Confirm Stop All",
        "YesNo Default2 Icon!"
    )

    if (result != "Yes") {
        AddLog("Stop All cancelled.")
        RefreshUI(false)
        return
    }

    for fullPath, _ in RunningScripts.Clone() {
        StopSingleScript(fullPath)
    }

    RefreshUI(true)
}


RunStartupScriptsNow() {
    global StartupScripts

    if (StartupScripts.Count = 0) {
        AddLog("No startup scripts configured.")
        RefreshUI(false)
        return
    }

    for fullPath, _ in StartupScripts {
        if FileExist(fullPath)
            RunSingleScript(fullPath)
    }

    RefreshUI(true)
}


ToggleFavoriteForSelected() {
    paths := GetSelectedPaths(false)

    if (paths.Length = 0) {
        AddLog("Nothing selected to toggle favorite.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        ToggleFavorite(fullPath)
    }

    RefreshUI(true)
}


ToggleStartupForSelected() {
    paths := GetSelectedPaths(false)

    if (paths.Length = 0) {
        AddLog("Nothing selected to toggle startup.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        ToggleStartup(fullPath)
    }

    RefreshUI(true)
}


BackupSelectedScripts() {
    paths := GetSelectedPaths(false)

    if (paths.Length = 0) {
        AddLog("Nothing selected to backup.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        BackupScript(fullPath)
    }

    RefreshUI(false)
}


; ==========================================================
; ADD SCRIPT
; ==========================================================

AddScriptPopup() {
    selectedFolders := SelectTargetFoldersPopup()

    if (selectedFolders.Length = 0) {
        AddLog("Add Script cancelled. No folder selected.")
        RefreshUI(false)
        return
    }

    lastName := ""

    for folderPath in selectedFolders {
        folderName := GetFolderDisplayName(folderPath)

        promptText := "Enter script name for this folder:`n`n" folderName "`n`nExample: My Shortcut.ahk"

        inputResult := InputBox(promptText, "Create New Script", "w450 h180", lastName)

        if (inputResult.Result != "OK") {
            AddLog("Skipped script creation for folder: " folderName)
            continue
        }

        scriptName := NormalizeScriptName(inputResult.Value)

        if (scriptName = "") {
            AddLog("Skipped empty script name for folder: " folderName)
            continue
        }

        lastName := scriptName
        CreateNewScript(folderPath, scriptName)
    }

    RefreshUI(true)
}


SelectTargetFoldersPopup() {
    global TargetFolder
    global FolderPickerResult, FolderPickerConfirmed, FolderPickerRowPaths

    FolderPickerResult := []
    FolderPickerConfirmed := false
    FolderPickerRowPaths := Map()

    PickerGui := Gui("+Resize +AlwaysOnTop", "Select Folder(s)")
    PickerGui.SetFont("s10", "Segoe UI")

    PickerGui.Add("Text", "x10 y10 w650", "Select one or more folders where the new script should be created:")

    FolderLV := PickerGui.Add("ListView", "x10 y40 w680 h330 Checked Grid", [
        "Folder",
        "Full Path"
    ])

    FolderLV.ModifyCol(1, 230)
    FolderLV.ModifyCol(2, 430)

    PopulateFolderPickerList(FolderLV)

    BtnOK := PickerGui.Add("Button", "x10 y385 w100 Default", "OK")
    BtnOK.OnEvent("Click", (*) => FolderPickerOK(PickerGui, FolderLV))

    BtnCancel := PickerGui.Add("Button", "x120 y385 w100", "Cancel")
    BtnCancel.OnEvent("Click", (*) => PickerGui.Destroy())

    BtnAddFolder := PickerGui.Add("Button", "x230 y385 w120", "Add Folder")
    BtnAddFolder.OnEvent("Click", (*) => AddFolderFromPicker(PickerGui, FolderLV))

    PickerGui.Show("w705 h435")

    WinWaitClose("ahk_id " PickerGui.Hwnd)

    if FolderPickerConfirmed
        return FolderPickerResult

    return []
}

PopulateFolderPickerList(FolderLV) {
    global TargetFolder, FolderPickerRowPaths

    FolderLV.Delete()
    FolderPickerRowPaths := Map()

    ; Main/root target folder
    rowNum := FolderLV.Add("", "Main", TargetFolder)
    FolderPickerRowPaths[rowNum] := TargetFolder

    ; Direct and nested subfolders
    loop files, TargetFolder "\*", "D R" {
        folderPath := A_LoopFileFullPath
        folderDisplay := GetFolderDisplayName(folderPath)

        rowNum := FolderLV.Add("", folderDisplay, folderPath)
        FolderPickerRowPaths[rowNum] := folderPath
    }
}


AddFolderFromPicker(PickerGui, FolderLV) {
    global TargetFolder, FolderPickerRowPaths

    inputResult := ShowFolderNamePopup(PickerGui)

    if !inputResult.confirmed {
        AddLog("Add folder cancelled.")
        return
    }

    folderName := NormalizeFolderName(inputResult.value)

    if (folderName = "") {
        MsgBox("Folder name cannot be empty.", "Invalid Folder Name", "Icon!")
        AddLog("Add folder failed. Empty folder name.")
        return
    }

    newFolderPath := TargetFolder "\" folderName

    if DirExist(newFolderPath) {
        MsgBox("This folder already exists:`n`n" newFolderPath, "Folder Already Exists", "Icon!")
        AddLog("Folder already exists: " folderName)
        return
    }

    try {
        DirCreate(newFolderPath)
        AddLog("Created folder: " folderName)

        rowNum := FolderLV.Add("", folderName, newFolderPath)
        FolderPickerRowPaths[rowNum] := newFolderPath

        FolderLV.Modify(rowNum, "+Check Vis Focus Select")

    } catch Error as e {
        MsgBox("Failed to create folder:`n`n" e.Message, "Folder Creation Failed", "Icon!")
        AddLog("Failed to create folder: " folderName " | " e.Message)
    }
}

ShowFolderNamePopup(OwnerGui) {
    global TargetFolder

    result := {
        confirmed: false,
        value: ""
    }

    OwnerGui.Opt("+Disabled")

    InputGui := Gui("+AlwaysOnTop +Owner" OwnerGui.Hwnd, "Add New Folder")
    InputGui.SetFont("s10", "Segoe UI")

    InputGui.Add("Text", "x10 y15 w500", "Enter new folder name:")
    InputGui.Add("Text", "x10 y50 w500", "This folder will be created inside:`n" TargetFolder)

    FolderNameEdit := InputGui.Add("Edit", "x10 y115 w500")

    BtnOK := InputGui.Add("Button", "x145 y155 w100 Default", "OK")
    BtnCancel := InputGui.Add("Button", "x275 y155 w100", "Cancel")

    BtnOK.OnEvent("Click", (*) => (
        result.confirmed := true,
        result.value := FolderNameEdit.Value,
        InputGui.Destroy()
    ))

    BtnCancel.OnEvent("Click", (*) => InputGui.Destroy())

    InputGui.OnEvent("Close", (*) => InputGui.Destroy())
    InputGui.OnEvent("Escape", (*) => InputGui.Destroy())

    InputGui.Show("w525 h205")
    FolderNameEdit.Focus()

    WinWaitClose("ahk_id " InputGui.Hwnd)

    OwnerGui.Opt("-Disabled")
    OwnerGui.Show()

    return result
}


NormalizeFolderName(folderName) {
    folderName := Trim(folderName)

    if (folderName = "")
        return ""

    for invalidChar in [":", "\", "/", "*", "?", Chr(34), "<", ">", "|"] {
        folderName := StrReplace(folderName, invalidChar, "_")
    }

    folderName := Trim(folderName)

    ; Prevent accidental trailing dots/spaces, which Windows dislikes
    while (SubStr(folderName, -1) = "." || SubStr(folderName, -1) = " ") {
        folderName := SubStr(folderName, 1, StrLen(folderName) - 1)
    }

    return folderName
}


FolderPickerOK(PickerGui, FolderLV) {
    global FolderPickerResult, FolderPickerConfirmed, FolderPickerRowPaths

    FolderPickerResult := []

    rowNum := 0

    loop {
        rowNum := FolderLV.GetNext(rowNum, "Checked")

        if !rowNum
            break

        if FolderPickerRowPaths.Has(rowNum)
            FolderPickerResult.Push(FolderPickerRowPaths[rowNum])
    }

    ; If no folder is checked, simply close without doing anything.
    if (FolderPickerResult.Length = 0) {
        FolderPickerConfirmed := false
        PickerGui.Destroy()
        return
    }

    FolderPickerConfirmed := true
    PickerGui.Destroy()
}


CreateNewScript(folderPath, scriptName) {
    if !DirExist(folderPath) {
        AddLog("Cannot create script. Folder missing: " folderPath)
        return
    }

    newPath := folderPath "\" scriptName

    if FileExist(newPath) {
        result := MsgBox(
            "This script already exists:`n`n" newPath "`n`nDo you want to overwrite it?",
            "Script Already Exists",
            "YesNo Default2 Icon!"
        )

        if (result != "Yes") {
            AddLog("Skipped existing script: " scriptName)
            return
        }

        try {
            FileDelete(newPath)
        } catch Error as e {
            AddLog("Failed to overwrite existing script: " scriptName " | " e.Message)
            return
        }
    }

    template := ""
    template .= "#Requires AutoHotkey v2.0`r`n"
    template .= "#SingleInstance Force`r`n"
    template .= "`r`n"
    template .= "; Description: TODO - explain what this script does`r`n"
    template .= "`r`n"
    template .= "; Add your hotkeys/functions below.`r`n"
    template .= "`r`n"

    try {
        FileAppend(template, newPath, "UTF-8")
        AddLog("Created script: " newPath)

        ; Open newly created script in Notepad immediately
        ; Run('notepad.exe "' newPath '"')
        AddLog("Opened new script in Notepad: " scriptName)
    } catch Error as e {
        AddLog("Failed to create script: " scriptName " | " e.Message)
    }
}


NormalizeScriptName(scriptName) {
    scriptName := Trim(scriptName)

    if (scriptName = "")
        return ""

    for invalidChar in [":", "\", "/", "*", "?", Chr(34), "<", ">", "|"] {
        scriptName := StrReplace(scriptName, invalidChar, "_")
    }

    scriptName := Trim(scriptName)

    if (scriptName = "")
        return ""

    if !RegExMatch(scriptName, "i)\.ahk$")
        scriptName .= ".ahk"

    return scriptName
}


GetFolderDisplayName(folderPath) {
    global TargetFolder

    if (folderPath = TargetFolder)
        return "Main"

    return StrReplace(folderPath, TargetFolder "\", "")
}


; ==========================================================
; DELETE SCRIPT
; ==========================================================

DeleteSelectedScripts() {
    paths := GetSelectedPaths(true)

    if (paths.Length = 0) {
        AddLog("Nothing selected to delete.")
        RefreshUI(false)
        return
    }

    confirmResult := ConfirmDeleteScriptsWithBackup(paths)

    if !confirmResult.confirmed {
        AddLog("Delete cancelled.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        DeleteSingleScript(fullPath, confirmResult.backup)
    }

    RefreshUI(true)
}


ConfirmDeleteScriptsWithBackup(paths) {
    global DeleteConfirmResponse

    DeleteConfirmResponse := { confirmed: false, backup: true }

    ConfirmGui := Gui("+Resize +AlwaysOnTop", "Confirm Delete")
    ConfirmGui.SetFont("s10", "Segoe UI")

    ConfirmGui.Add("Text", "x10 y10 w560", "You are about to permanently delete " paths.Length " selected script(s).")

    scriptList := ""

    for fullPath in paths {
        scriptList .= GetFileName(fullPath) "`r`n"
    }

    ConfirmGui.Add("Edit", "x10 y45 w560 h180 ReadOnly VScroll", scriptList)

    BackupToggle := ConfirmGui.Add("Checkbox", "x10 y240 w350 Checked", "Create backup before deleting")

    BtnDelete := ConfirmGui.Add("Button", "x10 y280 w120 Default", "Delete")
    BtnDelete.OnEvent("Click", (*) => DeleteConfirmOK(ConfirmGui, BackupToggle))

    BtnCancel := ConfirmGui.Add("Button", "x140 y280 w120", "Cancel")
    BtnCancel.OnEvent("Click", (*) => ConfirmGui.Destroy())

    ConfirmGui.Show("w585 h330")

    WinWaitClose("ahk_id " ConfirmGui.Hwnd)

    return DeleteConfirmResponse
}


DeleteConfirmOK(ConfirmGui, BackupToggle) {
    global DeleteConfirmResponse

    DeleteConfirmResponse := {
        confirmed: true,
        backup: BackupToggle.Value = 1
    }

    ConfirmGui.Destroy()
}


DeleteSingleScript(fullPath, createBackup := true) {
    if !FileExist(fullPath) {
        AddLog("Cannot delete missing script: " fullPath)
        return
    }

    if createBackup {
        BackupScript(fullPath)
    }

    if IsScriptRunning(fullPath) {
        StopSingleScript(fullPath)
        Sleep(200)
    }

    try {
        FileDelete(fullPath)
        AddLog("Deleted script: " GetFileName(fullPath))
    } catch Error as e {
        AddLog("Failed to delete script: " GetFileName(fullPath) " | " e.Message)
    }
}


; ==========================================================
; RUN / STOP / RESTART
; ==========================================================

RunSingleScript(fullPath, asAdmin := false, silent := false) {
    global RunningScripts

    RefreshRunningScriptsFromWindows()

    if RunningScripts.Has(fullPath) {
        if !silent
            AddLog("Already running: " GetFileName(fullPath))
        return
    }

    if !FileExist(fullPath) {
        AddLog("Missing file: " fullPath)
        return
    }

    pid := 0

    try {
        if asAdmin {
            Run('*RunAs "' A_AhkPath '" "' fullPath '"', , , &pid)
        } else {
            Run('"' A_AhkPath '" "' fullPath '"', , , &pid)
        }

        if pid {
            RunningScripts[fullPath] := pid
            AddLog((asAdmin ? "Started as admin: " : "Started: ") GetFileName(fullPath) " | PID " pid)
        } else {
            AddLog("Started but PID was not captured: " GetFileName(fullPath))
        }
    } catch Error as e {
        AddLog("Failed to start: " GetFileName(fullPath) " | " e.Message)
    }
}


StopSingleScript(fullPath) {
    global RunningScripts

    RefreshRunningScriptsFromWindows()

    if !RunningScripts.Has(fullPath) {
        AddLog("Not running: " GetFileName(fullPath))
        return
    }

    pid := RunningScripts[fullPath]

    try {
        if ProcessExist(pid) {
            ProcessClose(pid)
            AddLog("Stopped: " GetFileName(fullPath) " | PID " pid)
        } else {
            AddLog("Process already closed: " GetFileName(fullPath))
        }
    } catch Error as e {
        AddLog("Failed to stop: " GetFileName(fullPath) " | " e.Message)
    }

    RunningScripts.Delete(fullPath)
}


RestartSingleScript(fullPath) {
    AddLog("Restarting: " GetFileName(fullPath))

    if IsScriptRunning(fullPath)
        StopSingleScript(fullPath)

    Sleep(250)
    RunSingleScript(fullPath)
}


IsScriptRunning(fullPath) {
    global RunningScripts

    RefreshRunningScriptsFromWindows()
    return RunningScripts.Has(fullPath)
}


; ==========================================================
; CONTEXT MENU
; ==========================================================

AllLVContextMenu(LV, rowNum, isRightClick, x, y) {
    global AllRowPaths, ContextPath

    if !rowNum
        rowNum := LV.GetNext(0, "Selected")

    if !rowNum || !AllRowPaths.Has(rowNum)
        return

    ContextPath := AllRowPaths[rowNum]
    ShowScriptContextMenu(x, y)
}


RunningLVContextMenu(LV, rowNum, isRightClick, x, y) {
    global RunningRowPaths, ContextPath

    if !rowNum
        rowNum := LV.GetNext(0, "Selected")

    if !rowNum || !RunningRowPaths.Has(rowNum)
        return

    ContextPath := RunningRowPaths[rowNum]
    ShowScriptContextMenu(x, y)
}


FavoritesLVContextMenu(LV, rowNum, isRightClick, x, y) {
    global FavoriteRowPaths, ContextPath

    if !rowNum
        rowNum := LV.GetNext(0, "Selected")

    if !rowNum || !FavoriteRowPaths.Has(rowNum)
        return

    ContextPath := FavoriteRowPaths[rowNum]
    ShowScriptContextMenu(x, y)
}


ShowScriptContextMenu(x := "", y := "") {
    global ContextPath, FavoriteScripts, StartupScripts

    if (ContextPath = "")
        return

    popupMenu := Menu()

    popupMenu.Add("Run", (*) => ContextRun())
    popupMenu.Add("Stop", (*) => ContextStop())
    popupMenu.Add("Restart", (*) => ContextRestart())
    popupMenu.Add("Run as Admin", (*) => ContextRunAsAdmin())

    popupMenu.Add()

    popupMenu.Add("Edit Script", (*) => ContextEdit())
    popupMenu.Add("Open Folder", (*) => ContextOpenFolder())
    popupMenu.Add("Copy Path", (*) => ContextCopyPath())
    popupMenu.Add("Backup Now", (*) => ContextBackup())

    popupMenu.Add()

    favText := FavoriteScripts.Has(ContextPath) ? "Remove from Favorites" : "Add to Favorites"
    startupText := StartupScripts.Has(ContextPath) ? "Remove from Startup" : "Add to Startup"

    popupMenu.Add(favText, (*) => ContextToggleFavorite())
    popupMenu.Add(startupText, (*) => ContextToggleStartup())

    try {
        popupMenu.Show(x, y)
    } catch {
        popupMenu.Show()
    }
}


ContextRun() {
    global ContextPath
    RunSingleScript(ContextPath)
    RefreshUI(true)
}


ContextStop() {
    global ContextPath
    StopSingleScript(ContextPath)
    RefreshUI(true)
}


ContextRestart() {
    global ContextPath
    RestartSingleScript(ContextPath)
    RefreshUI(true)
}


ContextRunAsAdmin() {
    global ContextPath
    RunSingleScript(ContextPath, true)
    RefreshUI(true)
}


ContextEdit() {
    global ContextPath
    EditScript(ContextPath)
    RefreshUI(true)
}


ContextOpenFolder() {
    global ContextPath
    OpenScriptFolder(ContextPath)
    RefreshUI(false)
}


ContextCopyPath() {
    global ContextPath
    A_Clipboard := ContextPath
    AddLog("Copied path: " GetFileName(ContextPath))
    RefreshUI(false)
}


ContextBackup() {
    global ContextPath
    BackupScript(ContextPath)
    RefreshUI(false)
}


ContextToggleFavorite() {
    global ContextPath
    ToggleFavorite(ContextPath)
    RefreshUI(true)
}


ContextToggleStartup() {
    global ContextPath
    ToggleStartup(ContextPath)
    RefreshUI(true)
}


; ==========================================================
; DOUBLE CLICK
; ==========================================================

AllLVDoubleClick(LV, rowNum) {
    global AllRowPaths

    if !rowNum || !AllRowPaths.Has(rowNum)
        return

    ToggleSingleScript(AllRowPaths[rowNum])
    RefreshUI(true)
}


RunningLVDoubleClick(LV, rowNum) {
    global RunningRowPaths

    if !rowNum || !RunningRowPaths.Has(rowNum)
        return

    StopSingleScript(RunningRowPaths[rowNum])
    RefreshUI(true)
}


FavoritesLVDoubleClick(LV, rowNum) {
    global FavoriteRowPaths

    if !rowNum || !FavoriteRowPaths.Has(rowNum)
        return

    ToggleSingleScript(FavoriteRowPaths[rowNum])
    RefreshUI(true)
}


ToggleSingleScript(fullPath) {
    if IsScriptRunning(fullPath)
        StopSingleScript(fullPath)
    else
        RunSingleScript(fullPath)
}

AllLVClick(LV, rowNum) {
    global AllRowPaths

    if !rowNum
        return

    if !AllRowPaths.Has(rowNum)
        return

    clickedCol := GetClickedListViewColumn(LV)

    ; Column 11 is the Edit column.
    if (clickedCol != 11)
        return

    fullPath := AllRowPaths[rowNum]
    OpenScriptFromEditColumn(fullPath)
}


GetClickedListViewColumn(LV) {
    ; Returns the 1-based column number under the mouse cursor.
    ; Returns 0 if detection fails.

    try {
        pt := Buffer(8, 0)

        DllCall("GetCursorPos", "Ptr", pt.Ptr)
        DllCall("ScreenToClient", "Ptr", LV.Hwnd, "Ptr", pt.Ptr)

        hit := Buffer(24, 0)

        NumPut("Int", NumGet(pt, 0, "Int"), hit, 0)
        NumPut("Int", NumGet(pt, 4, "Int"), hit, 4)

        ; LVM_SUBITEMHITTEST = 0x1039
        DllCall("SendMessage", "Ptr", LV.Hwnd, "UInt", 0x1039, "Ptr", 0, "Ptr", hit.Ptr)

        subItem := NumGet(hit, 16, "Int")

        return subItem + 1
    } catch {
        return 0
    }
}


OpenScriptFromEditColumn(fullPath) {
    if !FileExist(fullPath) {
        AddLog("Cannot edit missing file: " fullPath)
        return
    }

    ; Safety backup before opening.
    BackupScript(fullPath)

    try {
        Run('notepad.exe "' fullPath '"')
        AddLog("Opened in Notepad from Edit column: " GetFileName(fullPath))
    } catch Error as e {
        AddLog("Failed to open from Edit column: " GetFileName(fullPath) " | " e.Message)
    }
}


; ==========================================================
; FAVORITES / STARTUP
; ==========================================================

ToggleFavorite(fullPath) {
    global FavoriteScripts

    if FavoriteScripts.Has(fullPath) {
        FavoriteScripts.Delete(fullPath)
        AddLog("Removed favorite: " GetFileName(fullPath))
    } else {
        FavoriteScripts[fullPath] := true
        AddLog("Added favorite: " GetFileName(fullPath))
    }

    SaveSettings()
}


ToggleStartup(fullPath) {
    global StartupScripts

    if StartupScripts.Has(fullPath) {
        StartupScripts.Delete(fullPath)
        AddLog("Removed startup script: " GetFileName(fullPath))
    } else {
        StartupScripts[fullPath] := true
        AddLog("Added startup script: " GetFileName(fullPath))
    }

    SaveSettings()
}


AutoRunStartupScripts() {
    global StartupScripts

    for fullPath, _ in StartupScripts {
        if FileExist(fullPath) && !ShouldSkipScript(fullPath)
            RunSingleScript(fullPath, false, true)
    }
}


GetExistingFavoriteCount() {
    global Scripts

    count := 0

    for fullPath, item in Scripts {
        if item.favorite
            count++
    }

    return count
}


; ==========================================================
; EDIT / FOLDER / BACKUP
; ==========================================================

EditScript(fullPath) {
    global EditorPath

    if !FileExist(fullPath) {
        AddLog("Cannot edit missing file: " fullPath)
        return
    }

    BackupScript(fullPath)

    try {
        if (EditorPath != "" && FileExist(EditorPath)) {
            Run('"' EditorPath '" "' fullPath '"')
            AddLog("Opened in editor: " GetFileName(fullPath))
        } else {
            Run('notepad.exe "' fullPath '"')
            AddLog("Opened in Notepad: " GetFileName(fullPath))
        }
    } catch Error as e {
        AddLog("Failed to open editor: " GetFileName(fullPath) " | " e.Message)
    }
}


OpenScriptFolder(fullPath) {
    if !FileExist(fullPath) {
        AddLog("Cannot open folder for missing file: " fullPath)
        return
    }

    try {
        Run('explorer.exe /select,"' fullPath '"')
        AddLog("Opened folder: " GetFileName(fullPath))
    } catch Error as e {
        AddLog("Failed to open folder: " GetFileName(fullPath) " | " e.Message)
    }
}


BackupScript(fullPath) {
    global BackupFolder

    if !FileExist(fullPath) {
        AddLog("Cannot backup missing file: " fullPath)
        return
    }

    try {
        if !DirExist(BackupFolder)
            DirCreate(BackupFolder)

        SplitPath fullPath, &fileName

        safePath := fullPath

        for invalidChar in [":", "\", "/", "*", "?", Chr(34), "<", ">", "|"] {
            safePath := StrReplace(safePath, invalidChar, "_")
        }

        timestamp := FormatTime(A_Now, "yyyyMMdd_HHmmss")
        backupPath := BackupFolder "\" timestamp "_" safePath

        FileCopy(fullPath, backupPath, true)

        AddLog("Backup created: " fileName)
    } catch Error as e {
        AddLog("Backup failed: " GetFileName(fullPath) " | " e.Message)
    }
}


; ==========================================================
; SETTINGS
; ==========================================================

LoadSettings() {
    global SettingsFile, FavoriteScripts, StartupScripts, EditorPath

    FavoriteScripts := Map()
    StartupScripts := Map()

    if !FileExist(SettingsFile) {
        SaveSettings()
        return
    }

    try {
        content := FileRead(SettingsFile)
    } catch {
        return
    }

    section := ""

    loop parse, content, "`n", "`r" {
        line := Trim(A_LoopField)

        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        if RegExMatch(line, "^\[(.*)\]$", &match) {
            section := match[1]
            continue
        }

        pos := InStr(line, "=")

        if !pos
            continue

        key := Trim(SubStr(line, 1, pos - 1))
        value := Trim(SubStr(line, pos + 1))

        if (section = "Config") {
            if (key = "EditorPath" && EditorPath = "")
                EditorPath := value
        } else if (section = "Favorites") {
            if (value = "1")
                FavoriteScripts[key] := true
        } else if (section = "Startup") {
            if (value = "1")
                StartupScripts[key] := true
        }
    }
}


SaveSettings() {
    global SettingsFile, FavoriteScripts, StartupScripts, EditorPath

    text := ""
    text .= "[Config]`n"
    text .= "EditorPath=" EditorPath "`n`n"

    text .= "[Favorites]`n"
    for fullPath, _ in FavoriteScripts {
        text .= fullPath "=1`n"
    }

    text .= "`n[Startup]`n"
    for fullPath, _ in StartupScripts {
        text .= fullPath "=1`n"
    }

    try {
        if FileExist(SettingsFile)
            FileDelete(SettingsFile)

        FileAppend(text, SettingsFile, "UTF-8")
    }
}


; ==========================================================
; PROCESS DETECTION
; ==========================================================

RefreshRunningScriptsFromWindows() {
    global TargetFolder, RunningScripts

    existingScripts := Map()

    loop files, TargetFolder "\*.ahk", "R" {
        fullPath := A_LoopFileFullPath

        if ShouldSkipScript(fullPath)
            continue

        existingScripts[fullPath] := true
    }

    for fullPath, pid in RunningScripts.Clone() {
        if (!existingScripts.Has(fullPath) || !ProcessExist(pid)) {
            RunningScripts.Delete(fullPath)
        }
    }

    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, CommandLine from Win32_Process") {
            cmd := proc.CommandLine

            if (!cmd || !InStr(StrLower(cmd), ".ahk"))
                continue

            lowerCmd := StrLower(cmd)

            for fullPath, _ in existingScripts {
                if InStr(lowerCmd, StrLower(fullPath)) {
                    RunningScripts[fullPath] := proc.ProcessId
                    break
                }
            }
        }
    }
}


; ==========================================================
; METADATA
; ==========================================================

GetScriptShortcuts(filePath) {
    shortcuts := []

    try {
        fileText := FileRead(filePath)

        loop parse, fileText, "`n", "`r" {
            line := Trim(A_LoopField)

            if (line = "" || SubStr(line, 1, 1) = ";")
                continue

            if RegExMatch(line, "^\s*(?!:)([^:]+?)::", &match) {
                rawShortcut := Trim(match[1])

                if (rawShortcut != "") {
                    shortcuts.Push(MakeShortcutReadable(rawShortcut))

                    if (shortcuts.Length >= 6)
                        break
                }
            }
        }
    }

    if (shortcuts.Length = 0)
        return "None"

    return JoinArray(shortcuts, ", ")
}


MakeShortcutReadable(rawShortcut) {
    mods := []

    if InStr(rawShortcut, "^")
        mods.Push("Ctrl")

    if InStr(rawShortcut, "+")
        mods.Push("Shift")

    if InStr(rawShortcut, "!")
        mods.Push("Alt")

    if InStr(rawShortcut, "#")
        mods.Push("Win")

    key := rawShortcut
    for symbol in ["^", "+", "!", "#", "*", "~", "$", "<", ">"] {
        key := StrReplace(key, symbol, "")
    }

    key := Trim(key)

    if (StrLen(key) = 1)
        key := StrUpper(key)

    if (mods.Length = 0)
        return key

    return JoinArray(mods, "+") "+" key
}


GetScriptDescription(filePath) {
    try {
        fileText := FileRead(filePath)

        loop parse, fileText, "`n", "`r" {
            line := Trim(A_LoopField)

            if RegExMatch(line, "i)^\s*;\s*(Description|Desc)\s*:\s*(.+)$", &match) {
                return Trim(match[2])
            }
        }

        loop parse, fileText, "`n", "`r" {
            line := Trim(A_LoopField)

            if (line = "")
                continue

            if (SubStr(line, 1, 1) = ";") {
                clean := Trim(SubStr(line, 2))

                if (clean != "" && !InStr(clean, "==="))
                    return clean
            }

            if (SubStr(line, 1, 1) != ";")
                break
        }
    }

    return "-"
}


GetProcessMemory(pid) {
    if (pid = 0 || pid = "-" || !ProcessExist(pid))
        return "0 KB"

    try {
        for proc in ComObjGet("winmgmts:").ExecQuery("Select WorkingSetSize from Win32_Process Where ProcessId=" pid) {
            bytes := proc.WorkingSetSize

            if bytes
                return Format("{:.1f} MB", bytes / 1024 / 1024)
        }
    }

    return "N/A"
}


; ==========================================================
; LOGS
; ==========================================================

AddLog(message) {
    global LogLines, LogFile

    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    logLine := "[" timestamp "] " message

    ; Add to GUI log
    LogLines.Push(logLine)

    while (LogLines.Length > 80) {
        LogLines.RemoveAt(1)
    }

    RenderLogs()

    ; Add to TXT log file
    try {
        FileAppend(logLine "`r`n", LogFile, "UTF-8")
    } catch {
        ; Avoid breaking the command center if log writing fails
    }
}

RenderLogs() {
    global LogBox, LogLines

    if !IsObject(LogBox)
        return

    text := ""

    for line in LogLines {
        text .= line "`r`n"
    }

    LogBox.Value := text
}


; ==========================================================
; UTILITIES
; ==========================================================

ShouldSkipScript(fullPath) {
    global BackupFolder

    if (StrLower(fullPath) = StrLower(A_ScriptFullPath))
        return true

    if (BackupFolder != "" && InStr(StrLower(fullPath), StrLower(BackupFolder)))
        return true

    return false
}


GetFileName(fullPath) {
    SplitPath fullPath, &fileName
    return fileName
}


JoinArray(arr, separator) {
    output := ""

    for index, value in arr {
        if (index > 1)
            output .= separator

        output .= value
    }

    return output
}


EditSelectedScriptsInNotepad() {
    paths := GetSelectedPaths(false)

    if (paths.Length = 0) {
        AddLog("Nothing selected to edit.")
        RefreshUI(false)
        return
    }

    for fullPath in paths {
        OpenScriptInNotepad(fullPath)
    }

    RefreshUI(false)
}


OpenScriptInNotepad(fullPath) {
    if !FileExist(fullPath) {
        AddLog("Cannot edit missing file: " fullPath)
        return
    }

    ; Optional safety backup before editing
    BackupScript(fullPath)

    try {
        Run('notepad.exe "' fullPath '"')
        AddLog("Opened in Notepad: " GetFileName(fullPath))
    } catch Error as e {
        AddLog("Failed to open in Notepad: " GetFileName(fullPath) " | " e.Message)
    }
}