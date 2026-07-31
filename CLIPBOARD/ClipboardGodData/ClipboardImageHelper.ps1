param([Parameter(Mandatory=$true)][ValidateSet("Save","Load")][string]$Action,[Parameter(Mandatory=$true)][string]$ImagePath)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if ($Action -eq "Save") {
    if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) { exit 2 }
    $image = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $image) { exit 3 }
    try { $image.Save($ImagePath,[System.Drawing.Imaging.ImageFormat]::Png); exit 0 } finally { $image.Dispose() }
}
if (-not (Test-Path -LiteralPath $ImagePath)) { exit 4 }
$image = [System.Drawing.Image]::FromFile($ImagePath)
try { [System.Windows.Forms.Clipboard]::SetImage($image); exit 0 } finally { $image.Dispose() }
