#Hotstring EndChars =
::=:: {
    InputBoxVar := InputBox("Enter Math Equation:", "Inline Calculator")
    if (InputBoxVar.Result = "OK" && InputBoxVar.Value != "") {
        try {
            ; Uses PowerShell in the background to safely evaluate the math string
            exec := ComObject("WScript.Shell").Exec("powershell.exe -Command [Math]::Round(" InputBoxVar.Value ", 2)")
            result := exec.StdOut.ReadAll()
            SendInput(Trim(result))
        } catch {
            ToolTip("Invalid Equation")
            SetTimer () => ToolTip(), -1000
        }
    }
}