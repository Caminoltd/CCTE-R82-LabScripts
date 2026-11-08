<#
.SYNOPSIS
  Installs the CCTE R82 Lab Menu on A-GUI (Windows). Nothing is installed on the appliances.

.DESCRIPTION
  Run on A-GUI in PowerShell:

    irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/agui/Install-CCTELabMenu.ps1 | iex

  It copies CCTE-LabMenu.ps1 to C:\CCTE-LabMenu and adds a "CCTE Lab Menu" shortcut to the
  desktop. The menu runs the lab guide commands on A-SMS, A-SMS-02 and the gateways over SSH.
  It works with the original Check Point lab scripts and with the improved set (labmenu).

  To remove it:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/agui/Install-CCTELabMenu.ps1))) -Uninstall
#>
param(
    [switch]$Uninstall,
    [string]$Branch = "main",
    [string]$Repo = "Caminoltd/CCTE-R82-LabScripts",
    [string]$Target = "C:\CCTE-LabMenu",
    [string]$LocalFile               # test option: install from a local copy of CCTE-LabMenu.ps1
)
$ErrorActionPreference = "Stop"
$lnk = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "CCTE Lab Menu.lnk"
$userLnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "CCTE Lab Menu.lnk"

if ($Uninstall) {
    foreach ($f in $lnk, $userLnk) { if (Test-Path $f) { Remove-Item $f -Force } }
    if (Test-Path $Target) { Remove-Item $Target -Recurse -Force }
    Write-Host "CCTE Lab Menu removed from A-GUI." -ForegroundColor Cyan
    return
}

if (-not (Get-Command plink.exe -ErrorAction SilentlyContinue) -and -not (Test-Path "$env:ProgramFiles\PuTTY\plink.exe")) {
    Write-Host "Warning: plink.exe (PuTTY) was not found. The menu needs it to reach the appliances." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force $Target | Out-Null
$dest = Join-Path $Target "CCTE-LabMenu.ps1"
if ($LocalFile) { Copy-Item $LocalFile $dest -Force }
else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/$Repo/$Branch/agui/CCTE-LabMenu.ps1" -OutFile $dest
}
Unblock-File $dest -ErrorAction SilentlyContinue

$ws = New-Object -ComObject WScript.Shell
$where = $lnk
try { $sc = $ws.CreateShortcut($lnk); $sc.Save() } catch { $where = $userLnk }
$sc = $ws.CreateShortcut($where)
$sc.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$dest`""
$sc.WorkingDirectory = $Target
$sc.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
$sc.Description = "CCTE R82 Lab Menu"
$sc.Save()

$ver = (Select-String -Path $dest -Pattern '^\$Version = "([^"]+)"' | Select-Object -First 1).Matches.Groups[1].Value
Write-Host ""
Write-Host "CCTE Lab Menu $ver installed in $Target" -ForegroundColor Green
Write-Host "Start it from the desktop shortcut 'CCTE Lab Menu', or run:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$dest`"" -ForegroundColor Cyan
