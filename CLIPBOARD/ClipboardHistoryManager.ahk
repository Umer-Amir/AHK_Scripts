#Requires AutoHotkey v2.0
#SingleInstance Force
#ClipboardTimeout 2000
Persistent
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"

; God-Tier Clipboard Manager v2.7.2 SETTIMER FIXED (AutoHotkey v2)
; Alt+V: open/close | Alt+Shift+V: pause/resume capture

global MAX_ITEMS := 99999
global APP := "God-Tier Clipboard"
global ROOT := A_ScriptDir "\ClipboardGodData"
global BIN := ROOT "\Binary"
global BAK := ROOT "\Backups"
global PREV := ROOT "\ImagePreviews"
global PSIMG := ROOT "\ClipboardImageHelper.ps1"
global DB := ROOT "\ClipboardDatabase.dat"
global MIRROR := A_ScriptDir "\ClipboardHistory.txt"
global CFG := ROOT "\Settings.ini"
global MARK := "@@GODCLIP@@|"

global H := [], View := [], NextId := 1
global G := 0, Q := 0, F := 0, S := 0, LV := 0, E := 0, PicPane := 0, Pic := 0, Meta := 0, Status := 0
global PauseBtn := 0, TopBox := 0, ActionButtons := [], ActionButtonWidths := []
global PreviousHwnd := 0, SelectedIndex := 0, Paused := false
global SuppressUntil := 0, SuppressKey := "", SearchPending := false, Saving := false
global Settings := Map()

Init()
LoadSettings()
LoadDb()
Cleanup()
BuildGui()
RegisterHotkeys()
OnClipboardChange ClipChanged
OnExit ExitSave
SetTimer(Maintenance, 60000)
return

Init() {
    global ROOT, BIN, BAK, PREV
    for _, p in [ROOT, BIN, BAK, PREV]
        if !DirExist(p)
            DirCreate p
    EnsureImageHelper()
}

EnsureImageHelper() {
    global PSIMG
    script := 'param([Parameter(Mandatory=$true)][ValidateSet("Save","Load")][string]$Action,[Parameter(Mandatory=$true)][string]$ImagePath)' "`r`n"
    script .= 'Add-Type -AssemblyName System.Windows.Forms' "`r`n"
    script .= 'Add-Type -AssemblyName System.Drawing' "`r`n"
    script .= 'if ($Action -eq "Save") {' "`r`n"
    script .= '    if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) { exit 2 }' "`r`n"
    script .= '    $image = [System.Windows.Forms.Clipboard]::GetImage()' "`r`n"
    script .= '    if ($null -eq $image) { exit 3 }' "`r`n"
    script .= '    try { $image.Save($ImagePath,[System.Drawing.Imaging.ImageFormat]::Png); exit 0 } finally { $image.Dispose() }' "`r`n"
    script .= '}' "`r`n"
    script .= 'if (-not (Test-Path -LiteralPath $ImagePath)) { exit 4 }' "`r`n"
    script .= '$image = [System.Drawing.Image]::FromFile($ImagePath)' "`r`n"
    script .= 'try { [System.Windows.Forms.Clipboard]::SetImage($image); exit 0 } finally { $image.Dispose() }' "`r`n"
    WriteText(PSIMG,script)
}

LoadSettings() {
    global Settings, CFG
    d := Map("DuplicateMode","MoveToTop", "IgnoreWhitespace","0", "RetentionDays","90",
        "RecycleDays","7", "BackupMinutes","30", "AutoClosePaste","1",
        "PasteDelay","80", "AlwaysOnTop","0", "CaptureBinary","1",
        "OpacityPercent","100",
        "ExcludeProcesses","KeePass.exe|KeePassXC.exe|1Password.exe|Bitwarden.exe|CredentialUIBroker.exe")
    for k,v in d {
        try Settings[k] := IniRead(CFG,"Settings",k,v)
        catch
            Settings[k] := v
    }
    SaveSettings()
}

SaveSettings(*) {
    global Settings, CFG
    for k,v in Settings
        try IniWrite v, CFG, "Settings", k
}

BuildGui() {
    global G,Q,F,S,LV,E,PicPane,Pic,Meta,Status,Settings,APP
    global PauseBtn,TopBox,ActionButtons,ActionButtonWidths

    opt := "+Resize +MinSize900x620" (Settings["AlwaysOnTop"]="1" ? " +AlwaysOnTop" : "")
    G := Gui(opt, APP), G.SetFont("s9","Segoe UI")

    Q := G.AddEdit("x10 y10 w500 h28"), Q.OnEvent("Change", QueueSearch)

    F := G.AddDropDownList(
        "x520 y10 w135 Choose1",
        ["All","Images","Pinned","Favorites","Text","Rich/Binary","URLs","Code","Files","Today","Recycle Bin"]
    )
    F.OnEvent("Change", Populate)

    S := G.AddDropDownList(
        "x665 y10 w135 Choose1",
        ["Newest","Oldest","Most Used","Recently Used","Alphabetical","Largest","Pinned First"]
    )
    S.OnEvent("Change", Populate)

    PauseBtn := G.AddButton("x810 y10 w90 h28","Pause")
    PauseBtn.OnEvent("Click", TogglePause)

    TopBox := G.AddCheckBox("x910 y15 w110","Always on top")
    TopBox.Value := Settings["AlwaysOnTop"]
    TopBox.OnEvent("Click", (*) => ToggleTop(TopBox.Value))

    LV := G.AddListView(
        "x10 y48 w1120 h330 Grid Multi",
        ["#","Pin","Fav","Copied","Source","Type","Clipboard item","Uses","Copy","Paste"]
    )
    LV.OnEvent("ItemSelect", Selected)
    LV.OnEvent("DoubleClick", DoubleClick)
    LV.OnEvent("Click", Clicked)
    LV.OnEvent("ContextMenu", Context)

    Meta := G.AddText("x10 y384 w1120 h42 +0x200","No item selected.")
    E := G.AddEdit("x10 y432 w1120 h190 Multi VScroll WantTab")

    ; PicPane defines the available preview area. Pic is independently sized
    ; and centered inside it to preserve the image's original aspect ratio.
    PicPane := G.AddText("x10 y432 w1120 h190 Hidden Border", "")
    Pic := G.AddPicture("x10 y432 w1 h1 Hidden", "")

    ActionButtons := []
    ActionButtonWidths := []

    AddBtn("Paste",PasteSelected,85)
    AddBtn("Copy",CopySelected,85)
    AddBtn("Save Edit",SaveEdit,105)
    AddBtn("Pin",TogglePin,85)
    AddBtn("Favorite",ToggleFav,100)
    AddBtn("Combine",Combine,100)
    AddBtn("Delete Selected",DeleteSelected,125)
    AddBtn("Restore",RestoreDeleted,90)
    AddBtn("Export",ExportSelected,85)
    AddBtn("Backup",Backup,85)
    AddBtn("Settings",ShowSettings,90)

    Status := G.AddText(
        "x10 y690 w1120 h30 +0x200",
        "Alt+V open/close | Enter paste | Ctrl+Enter copy | Delete multi-delete | Ctrl+Z restore | Alt+Shift+O reset opacity"
    )

    G.OnEvent("Size", Resize)
    G.OnEvent("Close", Hide)
    G.OnEvent("Escape", Hide)

    ; Create the real window handle immediately while keeping the UI hidden.
    G.Show("Hide w1140 h730")
    ApplyTransparency()

    AddBtn(text,callback,preferredWidth) {
        global G,ActionButtons,ActionButtonWidths

        button := G.AddButton("x10 y650 w" preferredWidth " h30",text)
        button.OnEvent("Click",callback)
        ActionButtons.Push(button)
        ActionButtonWidths.Push(preferredWidth)
    }
}

Resize(gui,minmax,w,h) {
    global Q,F,S,PauseBtn,TopBox,LV,E,PicPane,Meta,Status

    if minmax=-1
        return

    ; Responsive top command row.
    searchWidth := Max(220,w-530)
    Q.Move(10,10,searchWidth,28)
    F.Move(searchWidth+20,10,135,28)
    S.Move(searchWidth+165,10,135,28)
    PauseBtn.Move(searchWidth+310,10,90,28)
    TopBox.Move(searchWidth+410,15,110,22)

    ; The toolbar uses one row when there is enough width and wraps to two
    ; centered rows on narrower windows.
    toolbarRows := ActionButtonRowCount(w)
    toolbarHeight := toolbarRows=1 ? 30 : 66

    statusY := h-40
    toolbarY := statusY-10-toolbarHeight
    contentTop := 48
    contentBottom := toolbarY-10
    bodyHeight := Max(320,contentBottom-contentTop)

    metaHeight := 42
    verticalGap := 6
    usableHeight := Max(280,bodyHeight-metaHeight-(verticalGap*2))

    ; Give the editor/image preview a substantial portion of the window.
    previewHeight := Max(180,Round(usableHeight*0.42))
    listHeight := usableHeight-previewHeight

    if listHeight<180 {
        listHeight := 180
        previewHeight := Max(100,usableHeight-listHeight)
    }

    LV.Move(10,contentTop,w-20,listHeight)

    metaY := contentTop+listHeight+verticalGap
    Meta.Move(10,metaY,w-20,metaHeight)

    previewY := metaY+metaHeight+verticalGap
    E.Move(10,previewY,w-20,previewHeight)
    PicPane.Move(10,previewY,w-20,previewHeight)

    LayoutActionButtons(w,toolbarY,toolbarRows)
    Status.Move(10,statusY,w-20,30)
    Columns(w-20)

    ; Recalculate the contained image whenever the preview pane changes size.
    RefitCurrentImagePreview()
}

ActionButtonRowCount(windowWidth) {
    global ActionButtonWidths

    gap := 8
    totalWidth := 0

    for _,preferredWidth in ActionButtonWidths
        totalWidth += preferredWidth

    totalWidth += gap*Max(0,ActionButtonWidths.Length-1)

    ; Permit slight proportional compression before wrapping.
    return windowWidth-20>=Round(totalWidth*0.90) ? 1 : 2
}

LayoutActionButtons(windowWidth,toolbarY,rowCount) {
    global ActionButtons

    availableWidth := windowWidth-20

    if rowCount=1 {
        LayoutButtonRange(1,ActionButtons.Length,10,toolbarY,availableWidth)
        return
    }

    firstRowEnd := Ceil(ActionButtons.Length/2)
    LayoutButtonRange(1,firstRowEnd,10,toolbarY,availableWidth)
    LayoutButtonRange(firstRowEnd+1,ActionButtons.Length,10,toolbarY+36,availableWidth)
}

LayoutButtonRange(startIndex,endIndex,startX,y,availableWidth) {
    global ActionButtons,ActionButtonWidths

    count := endIndex-startIndex+1

    if count<=0
        return

    gap := 8
    preferredTotal := 0

    loop count
        preferredTotal += ActionButtonWidths[startIndex+A_Index-1]

    usableWidth := availableWidth-(gap*(count-1))
    scale := Min(1,usableWidth/preferredTotal)

    renderedWidths := []
    renderedTotal := 0

    loop count {
        index := startIndex+A_Index-1
        buttonWidth := Max(60,Floor(ActionButtonWidths[index]*scale))
        renderedWidths.Push(buttonWidth)
        renderedTotal += buttonWidth
    }

    usedWidth := renderedTotal+(gap*(count-1))
    x := startX+Floor((availableWidth-usedWidth)/2)

    loop count {
        index := startIndex+A_Index-1
        buttonWidth := renderedWidths[A_Index]
        ActionButtons[index].Move(x,y,buttonWidth,30)
        x += buttonWidth+gap
    }
}

Columns(w) {
    global LV
    fixed := 55+40+40+145+115+85+55+55+55+30
    widths := [55,40,40,145,115,85,Max(220,w-fixed),55,55,55]
    for i,x in widths
        LV.ModifyCol(i,x)
}

RegisterHotkeys() {
    global Q,E
    HotIf GuiActive
    Hotkey "Enter", PasteSelected
    Hotkey "^Enter", CopySelected
    Hotkey "Delete", DeleteSelected
    Hotkey "^p", TogglePin
    Hotkey "^+p", ToggleFav
    Hotkey "^f", (*) => Q.Focus()
    Hotkey "^e", (*) => E.Focus()
    Hotkey "^s", SaveEdit
    Hotkey "^a", SelectAll
    Hotkey "^z", RestoreDeleted
    Hotkey "Escape", Hide
    loop 9
        Hotkey A_Index, PasteNumber.Bind(A_Index)
    HotIf
    Hotkey "!v", Toggle
    Hotkey "!+v", TogglePause
    Hotkey "!+o", ResetOpacity
}

MainGuiHwnd() {
    global G

    if !IsObject(G)
        return 0

    try return G.Hwnd
    catch
        return 0
}

MainGuiVisible() {
    hwnd := MainGuiHwnd()
    return hwnd && DllCall("IsWindowVisible","Ptr",hwnd,"Int")
}

GuiActive(*) {
    hwnd := MainGuiHwnd()
    return hwnd && WinActive("ahk_id " hwnd)
}

Toggle(*) {
    global G,PreviousHwnd,Q

    hwnd := MainGuiHwnd()

    if MainGuiVisible() {
        Hide()
        return
    }

    a := WinExist("A")
    if a && (!hwnd || a!=hwnd)
        PreviousHwnd := a

    SaveAll()
    Populate()

    try {
        G.Show("w1140 h730")
        ApplyTransparency()
        Q.Focus()
    } catch as error {
        SetStatus("Could not open clipboard window: " error.Message)
    }
}

Hide(*) {
    global G

    SaveAll()

    if !MainGuiHwnd()
        return

    try G.Hide()
}


ApplyTransparency(*) {
    global Settings

    hwnd := MainGuiHwnd()

    if !hwnd
        return

    percent := Max(0,Min(100,Settings["OpacityPercent"]+0))

    try {
        if percent>=100
            WinSetTransparent "Off","ahk_id " hwnd
        else
            WinSetTransparent Round(255*percent/100),"ahk_id " hwnd
    }
}

ResetOpacity(*) {
    global Settings

    Settings["OpacityPercent"] := 100
    SaveSettings()
    ApplyTransparency()
    SetStatus("Window opacity reset to 100%.")
}

ToggleTop(v) {
    global G,Settings
    Settings["AlwaysOnTop"] := v, G.Opt(v ? "+AlwaysOnTop" : "-AlwaysOnTop"), SaveSettings()
}

TogglePause(*) {
    global Paused
    Paused := !Paused, SetStatus(Paused ? "Clipboard tracking paused." : "Clipboard tracking resumed.")
}

ClipChanged(type) {
    global Paused,SuppressUntil,SuppressKey,Settings,G
    if Paused || type=0
        return
    src := Source()
    if Excluded(src["process"])
        return
    text := ""
    if type=1
        try text := A_Clipboard
    clip := 0, size := 0
    if Settings["CaptureBinary"]="1"
        try clip := ClipboardAll(), size := clip.Size
    if text="" && !IsObject(clip)
        return
    key := Finger(text,size)
    if A_TickCount<=SuppressUntil && key=SuppressKey {
        SuppressUntil := 0, SuppressKey := ""
        return
    }
    AddItem(text,clip,size,src,type)
    if MainGuiVisible()
        Populate()
}

Source() {
    hwnd := WinExist("A"), title := "", proc := "", path := ""
    guiHwnd := MainGuiHwnd()

    if guiHwnd && hwnd=guiHwnd
        hwnd := 0

    if hwnd {
        try title := WinGetTitle("ahk_id " hwnd)
        try proc := WinGetProcessName("ahk_id " hwnd)
        try path := WinGetProcessPath("ahk_id " hwnd)
    }

    return Map("title",title,"process",proc,"path",path)
}

Excluded(proc) {
    global Settings
    for _,x in StrSplit(Settings["ExcludeProcesses"],"|")
        if StrLower(Trim(x))=StrLower(proc)
            return true
    return false
}

AddItem(text,clip,size,src,clipType) {
    global H,NextId,BIN,Settings
    d := FindDuplicate(Normal(text),size)
    if d {
        mode := Settings["DuplicateMode"]
        if mode="Ignore"
            return
        if mode="MoveToTop" {
            item := H.RemoveAt(d), item["time"] := Stamp(), item["sourceProcess"] := src["process"], item["sourceTitle"] := src["title"], H.Push(item), SaveAll()
            return
        }
    }
    id := NextId, NextId += 1, file := "", isImage := false
    if IsObject(clip) && size>0 {
        file := BIN "\" id ".clip"
        if !WriteBinary(clip,file)
            file := ""
        if clipType=2
            isImage := SaveCurrentClipboardImage(id)
    }
    itemType := isImage ? "Image" : DetectType(text,size)
    H.Push(Map("id",id,"time",Stamp(),"text",text,"type",itemType,"binaryFile",file,"binarySize",size,
        "sourceProcess",src["process"],"sourceTitle",src["title"],"sourcePath",src["path"],"pinned",0,"favorite",0,
        "deleted",0,"deletedAt","","uses",0,"lastUsed",""))
    EnforceMax(), SaveAll()
}

Normal(t) {
    global Settings
    return Settings["IgnoreWhitespace"]="1" ? Trim(RegExReplace(t,"\s+"," ")) : t
}

FindDuplicate(t,size) {
    global H
    if t=""
        return 0
    start := Max(1,H.Length-5000)
    loop H.Length-start+1 {
        i := H.Length-A_Index+1
        if !H[i]["deleted"] && Normal(H[i]["text"])=t && H[i]["binarySize"]=size
            return i
    }
    return 0
}

WriteBinary(c,p) {
    f := 0
    try {
        if FileExist(p)
            FileDelete p
        f := FileOpen(p,"w"), f.RawWrite(c), f.Close()
        return true
    } catch {
        if IsObject(f)
            try f.Close()
        return false
    }
}

ImagePath(item) {
    global PREV
    return PREV "\" item["id"] ".png"
}

SaveCurrentClipboardImage(id) {
    global PREV,PSIMG
    path := PREV "\" id ".png"

    if FileExist(path)
        try FileDelete path

    command := 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' PSIMG '" -Action Save -ImagePath "' path '"'

    loop 3 {
        try exitCode := RunWait(command,,"Hide")
        catch
            exitCode := -1

        if exitCode=0 && FileExist(path)
            return true

        Sleep 80
    }

    if FileExist(path)
        try FileDelete path
    return false
}

SetClipboardFromImageFile(path) {
    global PSIMG

    if !FileExist(path)
        return false

    command := 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "' PSIMG '" -Action Load -ImagePath "' path '"'
    callbackRemoved := false
    exitCode := -1

    try {
        OnClipboardChange ClipChanged, 0
        callbackRemoved := true
        exitCode := RunWait(command,,"Hide")
    } catch {
        exitCode := -1
    } finally {
        if callbackRemoved
            OnClipboardChange ClipChanged
    }

    return exitCode=0
}

EnsureImagePreview(item) {
    path := ImagePath(item)

    if FileExist(path)
        return true

    if item["binaryFile"]="" || !FileExist(item["binaryFile"])
        return false

    savedClipboard := 0
    savedOkay := false
    callbackRemoved := false
    madePreview := false

    try {
        try {
            savedClipboard := ClipboardAll()
            savedOkay := true
        }

        OnClipboardChange ClipChanged, 0
        callbackRemoved := true

        raw := FileRead(item["binaryFile"],"RAW")
        A_Clipboard := ClipboardAll(raw)
        Sleep 100
        madePreview := SaveCurrentClipboardImage(item["id"])

        if savedOkay {
            A_Clipboard := savedClipboard
            Sleep 50
        }
    } catch {
        madePreview := false
    } finally {
        if callbackRemoved
            OnClipboardChange ClipChanged
    }

    return madePreview
}

ShowPreview(item) {
    global E,PicPane,Pic

    isImage := item["type"]="Image"

    if !isImage && item["type"]="Image/Rich" && EnsureImagePreview(item) {
        item["type"] := "Image"
        isImage := true
        SaveAll()
    }

    path := ImagePath(item)

    if isImage && FileExist(path) {
        E.Visible := false
        PicPane.Visible := true

        if FitImageInsidePreviewPane(path)
            Pic.Visible := true
        else {
            Pic.Visible := false
            SetStatus("The image preview dimensions could not be read.")
        }
    } else {
        Pic.Visible := false
        PicPane.Visible := false
        E.Visible := true
    }
}

RefitCurrentImagePreview() {
    global H,SelectedIndex,Pic

    if SelectedIndex<1 || SelectedIndex>H.Length
        return

    item := H[SelectedIndex]

    if item["type"]!="Image"
        return

    path := ImagePath(item)

    if FileExist(path) && FitImageInsidePreviewPane(path)
        Pic.Visible := true
}

FitImageInsidePreviewPane(path) {
    global PicPane,Pic

    if !FileExist(path)
        return false

    if !GetImagePixelDimensions(path,&imageWidth,&imageHeight)
        return false

    PicPane.GetPos(&paneX,&paneY,&paneWidth,&paneHeight)

    ; Keep a small inset so the image never overlaps the preview border.
    margin := 6
    availableWidth := Max(1,paneWidth-(margin*2))
    availableHeight := Max(1,paneHeight-(margin*2))

    ; One uniform scale factor preserves the aspect ratio. Min() implements
    ; a "contain" layout: no cropping and no independent width/height stretch.
    scale := Min(availableWidth/imageWidth,availableHeight/imageHeight)
    fittedWidth := Max(1,Round(imageWidth*scale))
    fittedHeight := Max(1,Round(imageHeight*scale))

    imageX := paneX+Floor((paneWidth-fittedWidth)/2)
    imageY := paneY+Floor((paneHeight-fittedHeight)/2)

    Pic.Visible := false
    Pic.Move(imageX,imageY,fittedWidth,fittedHeight)
    Pic.Value := "*w" fittedWidth " *h" fittedHeight " " path
    return true
}

GetImagePixelDimensions(path,&width,&height) {
    width := 0
    height := 0
    handle := 0
    imageType := 0

    try handle := LoadPicture(path,"",&imageType)
    catch
        return false

    if !handle
        return false

    try {
        ; PNG/JPEG/BMP previews are returned as HBITMAP handles.
        if imageType!=0
            return false

        bitmapInfo := Buffer(A_PtrSize=8 ? 32 : 24,0)

        if !DllCall(
            "gdi32\GetObjectW",
            "Ptr",handle,
            "Int",bitmapInfo.Size,
            "Ptr",bitmapInfo,
            "Int"
        )
            return false

        width := Abs(NumGet(bitmapInfo,4,"Int"))
        height := Abs(NumGet(bitmapInfo,8,"Int"))
        return width>0 && height>0
    } finally {
        if handle
            DllCall("gdi32\DeleteObject","Ptr",handle)
    }
}

ClearPreview() {
    global E,PicPane,Pic
    Pic.Visible := false
    PicPane.Visible := false
    E.Visible := true
}

RestoreClipboard(item) {
    global SuppressUntil,SuppressKey
    try {
        SuppressKey := Finger(item["text"],item["binarySize"]), SuppressUntil := A_TickCount+1500
        if item["binaryFile"]!="" && FileExist(item["binaryFile"]) {
            raw := FileRead(item["binaryFile"],"RAW"), A_Clipboard := ClipboardAll(raw)
        } else if item["type"]="Image" && FileExist(ImagePath(item)) {
            if !SetClipboardFromImageFile(ImagePath(item))
                return false
        } else
            A_Clipboard := item["text"]
        return true
    } catch {
        return false
    }
}

Finger(t,s) => StrLen(t) "|" s "|" SubStr(t,1,180)
Stamp() => FormatTime(,"yyyy-MM-dd HH:mm:ss")

QueueSearch(*) {
    global SearchPending
    if SearchPending
        SetTimer(Populate, 0)
    SearchPending := true
    SetTimer(Populate, -180)
}

Populate(*) {
    global H,View,LV,Q,F,S,E,SelectedIndex,SearchPending
    SearchPending := false, idx := []
    loop H.Length {
        i := A_Index, item := H[i]
        if Pass(item,F.Text) && Match(item,Trim(Q.Value))
            idx.Push(i)
    }
    SortIdx(idx,S.Text), View := idx, Redraw(false), LV.Delete()
    try for _,i in View {
        x := H[i]
        LV.Add("",x["id"],x["pinned"]?"P":"",x["favorite"]?"*":"",x["time"],x["sourceProcess"],x["type"],Preview(x),x["uses"],"Copy","Paste")
    } finally Redraw(true)
    SelectedIndex := 0, E.Value := "", ClearPreview(), UpdateMeta(), UpdateCount()
}

Pass(x,f) {
    if f="Recycle Bin"
        return x["deleted"]
    if x["deleted"]
        return false
    switch f {
        case "All": return true
        case "Images": return x["type"]="Image" || x["type"]="Image/Rich"
        case "Pinned": return x["pinned"]
        case "Favorites": return x["favorite"]
        case "Text": return x["type"]="Text"
        case "Rich/Binary": return x["binarySize"]>0
        case "URLs": return x["type"]="URL"
        case "Code": return x["type"]="Code"
        case "Files": return x["type"]="Files"
        case "Today": return SubStr(x["time"],1,10)=FormatTime(,"yyyy-MM-dd")
    }
    return true
}

Match(x,q) {
    if q=""
        return true
    for _,t in StrSplit(q," ") {
        l := StrLower(t)
        if InStr(l,"app:")=1 {
            if !InStr(StrLower(x["sourceProcess"]),SubStr(l,5))
                return false
        } else if InStr(l,"type:")=1 {
            if !InStr(StrLower(x["type"]),SubStr(l,6))
                return false
        } else if InStr(l,"pinned:")=1 {
            want := SubStr(l,8)~="^(1|true|yes)$"
            if x["pinned"]!=want
                return false
        } else if !InStr(x["text"] "`n" x["sourceProcess"] "`n" x["sourceTitle"] "`n" x["type"] "`n" x["time"],t,false)
            return false
    }
    return true
}

SortIdx(a,m) {
    global H

    switch m {
        case "Newest":
            compare := (x,y,*) => CompareNumberDesc(H[x]["id"],H[y]["id"])
        case "Oldest":
            compare := (x,y,*) => CompareNumberAsc(H[x]["id"],H[y]["id"])
        case "Most Used":
            compare := (x,y,*) => CompareUses(x,y)
        case "Recently Used":
            compare := (x,y,*) => CompareLastUsed(x,y)
        case "Alphabetical":
            compare := (x,y,*) => CompareAlphabetical(x,y)
        case "Largest":
            compare := (x,y,*) => CompareLargest(x,y)
        case "Pinned First":
            compare := (x,y,*) => ComparePinned(x,y)
        default:
            compare := (x,y,*) => CompareNumberDesc(H[x]["id"],H[y]["id"])
    }

    StableMergeSort(a,compare)
}

CompareNumberAsc(x,y) {
    return x<y ? -1 : x>y ? 1 : 0
}

CompareNumberDesc(x,y) {
    return x>y ? -1 : x<y ? 1 : 0
}

CompareUses(x,y) {
    global H
    result := CompareNumberDesc(H[x]["uses"],H[y]["uses"])
    return result!=0 ? result : CompareNumberDesc(H[x]["id"],H[y]["id"])
}

CompareLastUsed(x,y) {
    global H
    result := StrCompare(H[y]["lastUsed"],H[x]["lastUsed"])
    return result!=0 ? result : CompareNumberDesc(H[x]["id"],H[y]["id"])
}

CompareAlphabetical(x,y) {
    global H
    result := StrCompare(H[x]["text"],H[y]["text"])
    return result!=0 ? result : CompareNumberDesc(H[x]["id"],H[y]["id"])
}

CompareLargest(x,y) {
    global H
    result := CompareNumberDesc(Size(H[x]),Size(H[y]))
    return result!=0 ? result : CompareNumberDesc(H[x]["id"],H[y]["id"])
}

ComparePinned(x,y) {
    global H
    result := CompareNumberDesc(H[x]["pinned"],H[y]["pinned"])
    return result!=0 ? result : CompareNumberDesc(H[x]["id"],H[y]["id"])
}

StableMergeSort(items,compare) {
    count := items.Length

    if count<2
        return

    source := []
    destination := []

    for _,value in items {
        source.Push(value)
        destination.Push(0)
    }

    width := 1

    while width<count {
        left := 1

        while left<=count {
            middle := Min(left+width,count+1)
            right := Min(left+(2*width),count+1)
            sourceLeft := left
            sourceRight := middle
            destinationIndex := left

            while sourceLeft<middle && sourceRight<right {
                if compare.Call(source[sourceLeft],source[sourceRight])<=0 {
                    destination[destinationIndex] := source[sourceLeft]
                    sourceLeft += 1
                } else {
                    destination[destinationIndex] := source[sourceRight]
                    sourceRight += 1
                }
                destinationIndex += 1
            }

            while sourceLeft<middle {
                destination[destinationIndex] := source[sourceLeft]
                sourceLeft += 1
                destinationIndex += 1
            }

            while sourceRight<right {
                destination[destinationIndex] := source[sourceRight]
                sourceRight += 1
                destinationIndex += 1
            }

            left += 2*width
        }

        temporary := source
        source := destination
        destination := temporary
        width *= 2
    }

    loop count
        items[A_Index] := source[A_Index]
}

Preview(x) {
    t := x["text"]
    if x["type"]="Image"
        return "[Image - " Bytes(x["binarySize"]) "]"
    if t=""
        return "[Rich clipboard data - " Bytes(x["binarySize"]) "]"
    t := StrReplace(StrReplace(StrReplace(StrReplace(t,"`r`n"," ↵ "),"`n"," ↵ "),"`r"," ↵ "),"`t"," ⇥ ")
    return StrLen(t)>500 ? SubStr(t,1,497) "..." : t
}

Redraw(on) {
    global LV
    DllCall("SendMessage","Ptr",LV.Hwnd,"UInt",0x000B,"Ptr",on?1:0,"Ptr",0,"Ptr",0)
    if on
        DllCall("RedrawWindow","Ptr",LV.Hwnd,"Ptr",0,"Ptr",0,"UInt",0x0085)
}

Selected(ctrl,row,on) {
    global View,H,SelectedIndex,E
    if !on || row<1 || row>View.Length
        return
    SelectedIndex := View[row]
    E.Value := H[SelectedIndex]["text"]
    ShowPreview(H[SelectedIndex])
    UpdateMeta()
}

Selections() {
    global LV,View
    a := [], r := 0
    while r := LV.GetNext(r)
        if r<=View.Length
            a.Push(View[r])
    return a
}

DoubleClick(ctrl,row) {
    global View
    if row>0 && row<=View.Length
        Use(View[row],true)
}

Clicked(ctrl,row) {
    global View
    if row<1 || row>View.Length
        return
    c := HitCol(ctrl.Hwnd)
    if c=8
        Use(View[row],false)
    else if c=9
        Use(View[row],true)
}

HitCol(hwnd) {
    MouseGetPos &x,&y
    p:=Buffer(8), NumPut("Int",x,p,0), NumPut("Int",y,p,4), DllCall("ScreenToClient","Ptr",hwnd,"Ptr",p)
    h:=Buffer(A_PtrSize=8?32:24), NumPut("Int",NumGet(p,0,"Int"),h,0), NumPut("Int",NumGet(p,4,"Int"),h,4)
    DllCall("SendMessage","Ptr",hwnd,"UInt",0x1039,"Ptr",0,"Ptr",h,"Ptr")
    return NumGet(h,16,"Int")
}

Use(i,paste) {
    global H
    if i<1 || i>H.Length || H[i]["deleted"]
        return
    if !RestoreClipboard(H[i]) {
        SetStatus("Could not restore this clipboard item.")
        return
    }
    H[i]["uses"] += 1, H[i]["lastUsed"] := Stamp(), SaveAll()
    if paste
        PastePrevious()
    else
        SetStatus("Copied item #" H[i]["id"] ".")
}

PastePrevious() {
    global PreviousHwnd,Settings,G
    if !PreviousHwnd || !WinExist("ahk_id " PreviousHwnd) {
        SetStatus("Previous application unavailable; item remains copied.")
        return
    }
    if Settings["AutoClosePaste"]="1" && MainGuiHwnd()
        try G.Hide()
    try {
        WinActivate "ahk_id " PreviousHwnd
        WinWaitActive "ahk_id " PreviousHwnd,,1
        Sleep Settings["PasteDelay"]+0
        Send "^v"
    } catch
        SetStatus("Copied, but automatic paste failed.")
}

CopySelected(*) {
    a:=Selections()
    if a.Length=0
        return SetStatus("Select at least one item.")
    if a.Length=1
        return Use(a[1],false)
    CombineIndexes(a,"`r`n")
}

PasteSelected(*) {
    a:=Selections()
    if a.Length=0
        return SetStatus("Select at least one item.")
    if a.Length=1
        return Use(a[1],true)
    if CombineIndexes(a,"`r`n")
        PastePrevious()
}

PasteNumber(n,*) {
    global View
    if n<=View.Length
        Use(View[n],true)
}

SaveEdit(*) {
    global SelectedIndex,H,E
    a:=Selections()
    if SelectedIndex<1 || a.Length!=1
        return SetStatus("Select exactly one item to edit.")

    item := H[SelectedIndex]

    ; Editing converts the entry to plain text. Remove its old rich snapshot
    ; so Copy/Paste cannot restore stale pre-edit clipboard content.
    if item["binaryFile"]!="" && FileExist(item["binaryFile"])
        try FileDelete item["binaryFile"]

    previewFile := ImagePath(item)
    if FileExist(previewFile)
        try FileDelete previewFile

    item["binaryFile"] := ""
    item["binarySize"] := 0
    item["text"] := E.Value
    item["type"] := DetectType(item["text"],0)

    SaveAll(), Populate(), SetStatus("Edit saved.")
}

TogglePin(*) => ToggleFlag("pinned")
ToggleFav(*) => ToggleFlag("favorite")
ToggleFlag(k) {
    global H
    a:=Selections()
    if !a.Length
        return SetStatus("Select one or more items.")
    on:=false
    for _,i in a
        if !H[i][k] {
            on:=true
            break
        }
    for _,i in a
        H[i][k]:=on?1:0
    SaveAll(), Populate(), SetStatus((on?"Enabled ":"Disabled ") k " for " a.Length " item(s).")
}

DeleteSelected(*) {
    global H,APP
    a:=Selections()
    if !a.Length
        return SetStatus("Select entries to delete.")
    if MsgBox("Move " a.Length " selected item(s) to the recycle bin?",APP,"YesNo Icon?")!="Yes"
        return
    t:=Stamp()
    for _,i in a
        H[i]["deleted"]:=1,H[i]["deletedAt"]:=t
    SaveAll(),Populate(),SetStatus("Moved " a.Length " item(s) to recycle bin.")
}

RestoreDeleted(*) {
    global H
    a:=Selections(), n:=0
    if a.Length {
        for _,i in a
            if H[i]["deleted"]
                H[i]["deleted"]:=0,H[i]["deletedAt"]:="",n++
    } else {
        latest:=""
        for _,x in H
            if x["deleted"] && x["deletedAt"]>latest
                latest:=x["deletedAt"]
        for _,x in H
            if latest!="" && x["deletedAt"]=latest
                x["deleted"]:=0,x["deletedAt"]:="",n++
    }
    SaveAll(),Populate(),SetStatus(n ? "Restored " n " item(s)." : "Nothing to restore.")
}

Combine(*) {
    a:=Selections()
    if a.Length<2
        return SetStatus("Select at least two items.")
    r:=MsgBox("Yes = line breaks`nNo = commas","Combine", "YesNoCancel")
    if r!="Cancel"
        CombineIndexes(a,r="Yes"?"`r`n":", ")
}

CombineIndexes(a,sep) {
    global H,SuppressKey,SuppressUntil
    p:=[]
    for _,i in a
        if H[i]["text"]!=""
            p.Push(H[i]["text"])
    if !p.Length
        return false
    t:=Join(p,sep), SuppressKey:=Finger(t,0), SuppressUntil:=A_TickCount+1500, A_Clipboard:=t
    SetStatus("Combined and copied " p.Length " item(s).")
    return true
}

Join(a,sep) {
    s:=""
    for i,v in a
        s.=(i=1?"":sep) v
    return s
}

SelectAll(*) {
    global LV
    loop LV.GetCount()
        LV.Modify(A_Index,"Select")
}

Context(ctrl,row,right,x,y) {
    m:=Menu(),m.Add("Paste",PasteSelected),m.Add("Copy",CopySelected),m.Add(),m.Add("Pin / Unpin",TogglePin),m.Add("Favorite / Unfavorite",ToggleFav)
    m.Add(),m.Add("Open image preview",OpenImagePreview),m.Add("Save image as...",SaveImageAs),m.Add("Transform text",TransformMenu),m.Add("Open URL or file",OpenContent)
    m.Add(),m.Add("Export selected",ExportSelected),m.Add("Delete selected",DeleteSelected),m.Show(x,y)
}

OpenImagePreview(*) {
    global H
    a := Selections()
    if a.Length!=1
        return SetStatus("Select exactly one image.")
    item := H[a[1]]
    if item["type"]!="Image" && !EnsureImagePreview(item)
        return SetStatus("The selected item does not contain a previewable image.")
    item["type"] := "Image"
    SaveAll()
    path := ImagePath(item)
    if FileExist(path)
        Run path
}

SaveImageAs(*) {
    global H
    a := Selections()
    if a.Length!=1
        return SetStatus("Select exactly one image.")
    item := H[a[1]]
    if item["type"]!="Image" && !EnsureImagePreview(item)
        return SetStatus("The selected item does not contain a previewable image.")
    item["type"] := "Image"
    SaveAll()
    source := ImagePath(item)
    destination := FileSelect("S16",A_Desktop "\ClipboardImage_" item["id"] ".png","Save copied image","PNG Image (*.png)")
    if destination=""
        return
    try {
        FileCopy source,destination,1
        SetStatus("Image saved to " destination)
    } catch as error {
        SetStatus("Image save failed: " error.Message)
    }
}

TransformMenu(*) {
    m:=Menu()
    for name,mode in Map("UPPERCASE","upper","lowercase","lower","Title Case","title","Trim","trim","Remove extra spaces","spaces","Remove line breaks","line","Sort lines","sort","Unique lines","unique","Join lines with commas","comma","SQL escape quotes","sql","Wrap lines in quotes","quote")
        m.Add(name,Transform.Bind(mode))
    m.Show()
}

Transform(mode,*) {
    global E
    t:=E.Value
    switch mode {
        case "upper": t:=StrUpper(t)
        case "lower": t:=StrLower(t)
        case "title": t:=StrTitle(t)
        case "trim": t:=Trim(t)
        case "spaces": t:=RegExReplace(t,"[ \t]+"," ")
        case "line": t:=RegExReplace(t,"\R+"," ")
        case "sort": t:=Sort(t)
        case "comma": t:=RegExReplace(Trim(t),"\R+",", ")
        case "sql": t:=StrReplace(t,"'","''")
        case "quote":
            a:=[]
            for _,line in StrSplit(StrReplace(t,"`r"),"`n")
                a.Push('"' StrReplace(line,'"','""') '"')
            t:=Join(a,"`r`n")
        case "unique":
            seen:=Map(),a:=[]
            for _,line in StrSplit(StrReplace(t,"`r"),"`n")
                if !seen.Has(line)
                    seen[line]:=1,a.Push(line)
            t:=Join(a,"`r`n")
    }
    E.Value:=t,SetStatus("Transformation applied. Press Ctrl+S to save.")
}

OpenContent(*) {
    global H
    a:=Selections()
    if a.Length!=1
        return
    t:=Trim(H[a[1]]["text"]), first:=StrSplit(StrReplace(t,"`r"),"`n")[1]
    if RegExMatch(t,"i)^https?://")
        Run t
    else if FileExist(first)||DirExist(first)
        Run first
    else
        SetStatus("Not a recognized URL or existing path.")
}

ExportSelected(*) {
    global H,ROOT
    a:=Selections()
    if !a.Length
        return SetStatus("Select items to export.")
    p:=FileSelect("S16",ROOT "\ClipboardExport_" FormatTime(,"yyyyMMdd_HHmmss") ".txt","Export","Text (*.txt)")
    if p=""
        return
    out:=""
    for n,i in a {
        x:=H[i],out.="========== ITEM " n " ==========`r`nID: " x["id"] "`r`nCopied: " x["time"] "`r`nSource: " x["sourceProcess"] " - " x["sourceTitle"] "`r`nType: " x["type"] "`r`n`r`n" x["text"] "`r`n`r`n"
    }
    WriteText(p,out),SetStatus("Exported " a.Length " item(s).")
}

ShowSettings(*) {
    global Settings,G

    ownerHwnd := MainGuiHwnd()
    ownerOption := ownerHwnd ? "+Owner" ownerHwnd : ""
    g:=Gui(ownerOption,"Clipboard Settings"),g.SetFont("s9","Segoe UI")

    g.AddText("x10 y12 w170","Duplicate handling:")
    d:=g.AddDropDownList("x190 y10 w150",["MoveToTop","Ignore","Allow"])
    d.Text:=Settings["DuplicateMode"]

    whitespace:=g.AddCheckBox("x10 y48 w320","Ignore whitespace differences")
    whitespace.Value:=Settings["IgnoreWhitespace"]

    g.AddText("x10 y83 w170","Retention days:")
    retention:=g.AddEdit("x190 y80 w100 Number",Settings["RetentionDays"])

    g.AddText("x10 y118 w170","Recycle-bin days:")
    recycle:=g.AddEdit("x190 y115 w100 Number",Settings["RecycleDays"])

    g.AddText("x10 y153 w240","Window opacity (0 invisible, 100 opaque):")
    opacity:=g.AddSlider(
        "x10 y178 w380 Range0-100 ToolTip",
        Settings["OpacityPercent"]
    )
    opacityValue:=g.AddText("x400 y180 w45 Right",Settings["OpacityPercent"] "%")
    opacity.OnEvent("Change",(*)=>opacityValue.Text:=opacity.Value "%")

    g.AddText("x10 y218 w240","Excluded processes (separate with |):")
    excluded:=g.AddEdit("x10 y243 w435 h55 Multi",Settings["ExcludeProcesses"])

    captureBinary:=g.AddCheckBox("x10 y310 w320","Capture rich/binary clipboard formats")
    captureBinary.Value:=Settings["CaptureBinary"]

    autoClose:=g.AddCheckBox("x10 y340 w320","Close after direct paste")
    autoClose.Value:=Settings["AutoClosePaste"]

    g.AddText(
        "x10 y372 w435 h35",
        "Safety: Alt+Shift+O resets opacity to 100% if the window is made invisible."
    )

    saveButton:=g.AddButton("x255 y415 w90 Default","Save")
    cancelButton:=g.AddButton("x355 y415 w90","Cancel")
    saveButton.OnEvent("Click",SaveDlg)
    cancelButton.OnEvent("Click",(*)=>g.Destroy())

    SaveDlg(*) {
        Settings["DuplicateMode"]:=d.Text
        Settings["IgnoreWhitespace"]:=whitespace.Value
        Settings["RetentionDays"]:=Max(0,retention.Value+0)
        Settings["RecycleDays"]:=Max(0,recycle.Value+0)
        Settings["OpacityPercent"]:=Max(0,Min(100,opacity.Value+0))
        Settings["ExcludeProcesses"]:=excluded.Value
        Settings["CaptureBinary"]:=captureBinary.Value
        Settings["AutoClosePaste"]:=autoClose.Value

        SaveSettings()
        ApplyTransparency()
        g.Destroy()
        Cleanup()
        SaveAll()
        SetStatus("Settings saved. Window opacity: " Settings["OpacityPercent"] "%.")
    }

    g.Show("w455 h460")
}
Maintenance(*) {
    static last:=0
    global Settings
    Cleanup()
    if A_TickCount-last>=(Settings["BackupMinutes"]+0)*60000
        Backup(false),last:=A_TickCount
}

Cleanup() {
    global H,Settings
    now:=A_Now,rd:=Settings["RetentionDays"]+0,dd:=Settings["RecycleDays"]+0,changed:=false
    loop H.Length {
        i:=H.Length-A_Index+1,x:=H[i]
        if !x["deleted"] && !x["pinned"] && rd>0 && DateDiff(now,NormDate(x["time"]),"Days")>=rd
            x["deleted"]:=1,x["deletedAt"]:=Stamp(),changed:=true
        else if x["deleted"] && dd>0 && x["deletedAt"]!="" && DateDiff(now,NormDate(x["deletedAt"]),"Days")>=dd
            RemoveAt(i),changed:=true
    }
    if changed
        SaveAll()
}

NormDate(t)=>RegExReplace(t,"[-: ]")
EnforceMax() {
    global H,MAX_ITEMS
    while H.Length>MAX_ITEMS {
        i:=0
        for n,x in H
            if !x["pinned"]&&!x["favorite"] {
                i:=n
                break
            }
        if !i
            break
        RemoveAt(i)
    }
}
RemoveAt(i) {
    global H
    p:=H[i]["binaryFile"]
    if p!=""&&FileExist(p)
        try FileDelete p
    previewFile := ImagePath(H[i])
    if FileExist(previewFile)
        try FileDelete previewFile
    H.RemoveAt(i)
}

Backup(show:=true,*) {
    global DB,MIRROR,BAK
    SaveAll(),stamp:=FormatTime(,"yyyyMMdd_HHmmss")
    try {
        if FileExist(DB)
            FileCopy DB,BAK "\ClipboardDatabase_" stamp ".dat",1
        if FileExist(MIRROR)
            FileCopy MIRROR,BAK "\ClipboardHistory_" stamp ".txt",1
        if show
            SetStatus("Backup created.")
    } catch as e {
        if show
            SetStatus("Backup failed: " e.Message)
    }
}

SaveAll(*) {
    global Saving
    if Saving
        return
    Saving:=true
    try SaveDb(),SaveMirror()
    finally Saving:=false
}

SaveDb() {
    global DB,H,NextId,MARK
    tmp:=DB ".tmp",f:=0
    try {
        if FileExist(tmp)
            FileDelete tmp
        f:=FileOpen(tmp,"w","UTF-8"),f.Write("# God Clipboard v1`r`n# NextId=" NextId "`r`n")
        for _,x in H {
            vals:=[x["id"],x["time"],x["type"],x["binaryFile"],x["binarySize"],x["sourceProcess"],x["sourceTitle"],x["sourcePath"],x["pinned"],x["favorite"],x["deleted"],x["deletedAt"],x["uses"],x["lastUsed"],x["text"]]
            head:="",body:=""
            for n,v in vals
                v.="",head.=(n=1?"":"|") StrLen(v),body.=v
            f.Write(MARK head "`r`n" body "`r`n")
        }
        f.Close(),FileMove(tmp,DB,1)
    } catch {
        if IsObject(f)
            try f.Close()
        if FileExist(tmp)
            try FileDelete tmp
    }
}

LoadDb() {
    global DB,H,NextId,MARK
    if !FileExist(DB)
        return
    try data:=FileRead(DB,"UTF-8")
    catch
        return
    if RegExMatch(data,"m)^# NextId=(\d+)",&m)
        NextId:=m[1]+0
    pos:=1,ml:=StrLen(MARK),dl:=StrLen(data)
    while rs:=InStr(data,MARK,false,pos) {
        he:=InStr(data,"`n",false,rs)
        if !he
            break
        lens:=StrSplit(Trim(SubStr(data,rs+ml,he-rs-ml),"`r`n "),"|")
        if lens.Length!=15 {
            pos:=he+1
            continue
        }
        cur:=he+1,v:=[],ok:=true
        for _,ls in lens {
            n:=ls+0
            if n<0||cur+n-1>dl {
                ok:=false
                break
            }
            v.Push(SubStr(data,cur,n)),cur+=n
        }
        if !ok
            break
        H.Push(Map("id",v[1]+0,"time",v[2],"type",v[3],"binaryFile",v[4],"binarySize",v[5]+0,"sourceProcess",v[6],"sourceTitle",v[7],"sourcePath",v[8],"pinned",v[9]+0,"favorite",v[10]+0,"deleted",v[11]+0,"deletedAt",v[12],"uses",v[13]+0,"lastUsed",v[14],"text",v[15]))
        NextId:=Max(NextId,v[1]+1),pos:=cur
    }
}

SaveMirror() {
    global MIRROR,H
    tmp:=MIRROR ".tmp",f:=0
    try {
        if FileExist(tmp)
            FileDelete tmp
        f:=FileOpen(tmp,"w","UTF-8"),f.Write("# GOD-TIER CLIPBOARD HISTORY`r`n# Binary data is in ClipboardGodData\Binary. Image previews are in ClipboardGodData\ImagePreviews.`r`n`r`n")
        for _,x in H
            f.Write("======================================================================`r`nID: " x["id"] "`r`nCopied: " x["time"] "`r`nSource: " x["sourceProcess"] " - " x["sourceTitle"] "`r`nType: " x["type"] "`r`nPinned: " x["pinned"] " | Favorite: " x["favorite"] " | Deleted: " x["deleted"] "`r`nUses: " x["uses"] "`r`nBinary: " Bytes(x["binarySize"]) "`r`n----------------------------------------------------------------------`r`n" x["text"] "`r`n`r`n")
        f.Close(),FileMove(tmp,MIRROR,1)
    } catch {
        if IsObject(f)
            try f.Close()
        if FileExist(tmp)
            try FileDelete tmp
    }
}

DetectType(t,s) {
    z:=Trim(t)
    if z=""
        return s>0?"Image/Rich":"Unknown"
    if RegExMatch(z,"i)^https?://\S+$")
        return "URL"
    lines:=StrSplit(StrReplace(z,"`r"),"`n"),files:=0
    for _,line in lines
        if FileExist(Trim(line))||DirExist(Trim(line))
            files++
    if files&&files=lines.Length
        return "Files"
    score:=0
    for _,p in ["i)\b(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|JOIN)\b","i)\b(class|public|private|function|return|const|var|let)\b","=>|:=|==|!=|&&|\|\|","^\s*[\{\[]","</?[a-z][^>]*>"]
        if RegExMatch(t,p)
            score++
    if score>=2
        return "Code"
    return s>0?"Rich Text":"Text"
}

Size(x)=>x["binarySize"]+StrPut(x["text"],"UTF-8")
Bytes(n)=>n<1024?n " B":n<1048576?Round(n/1024,1) " KB":Round(n/1048576,1) " MB"

UpdateMeta() {
    global SelectedIndex,H,Meta
    if SelectedIndex<1||SelectedIndex>H.Length
        Meta.Text:="No item selected."
    else {
        x:=H[SelectedIndex],Meta.Text:="ID " x["id"] " | " x["type"] " | " Bytes(Size(x)) " | Uses " x["uses"] " | Source: " x["sourceProcess"] " - " x["sourceTitle"] (x["type"]="Image" ? " | Image preview shown below" : "")
    }
}

UpdateCount() {
    global Status,View,H
    active:=0
    for _,x in H
        if !x["deleted"]
            active++
    Status.Text:=View.Length " shown / " active " active | Choose Images in the filter to view copied pictures | Enter paste | Delete multi-delete"
}

SetStatus(t) {
    global Status
    if IsObject(Status)
        Status.Text:=t
}

WriteText(p,t) {
    if FileExist(p)
        FileDelete p
    FileAppend t,p,"UTF-8"
}

ExitSave(*) {
    SaveSettings(),SaveAll()
}
