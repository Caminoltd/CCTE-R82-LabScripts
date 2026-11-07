<#
.SYNOPSIS
  Installs the improved CCTE R82 lab scripts and the "labmenu" menu on the lab appliances.

.DESCRIPTION
  Run on A-GUI (Windows PowerShell 5.1 or PowerShell 7):

    irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/Install-CCTEScripts.ps1 | iex

  To put the original Check Point scripts back:

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/Install-CCTEScripts.ps1))) -Restore

  For each of A-SMS, A-SMS-02, A-GW-01 and A-GW-02 it logs in as admin with PuTTY plink (enters
  Expert mode if the login shell is clish), keeps the original scripts once in
  /home/admin/CCTE_Scripts/.orig, backs up the current ones, copies in the new set, checks
  every file's MD5 and adds the command "labmenu". The lab guide commands do not change.

  The admin password is asked for once and kept in memory only. If
  $HOME\.ssh\lab-password.txt exists it is used instead.
#>
param(
    [switch]$Restore,
    [string[]]$Only,                 # e.g. -Only A-SMS,A-SMS-02
    [string]$Branch = "main",
    [string]$Repo = "Caminoltd/CCTE-R82-LabScripts",
    [string]$User = "admin",
    [string]$LocalDist               # test option: folder holding SMS.tgz, GW.tgz, manifest.md5
)

$ErrorActionPreference = "Stop"
$Hosts = [ordered]@{
    "A-SMS"    = @{ IP = "10.1.1.101"; Pack = "SMS" }
    "A-SMS-02" = @{ IP = "10.1.1.111"; Pack = "SMS" }
    "A-GW-01"  = @{ IP = "10.1.1.2";   Pack = "GW"  }
    "A-GW-02"  = @{ IP = "10.1.1.3";   Pack = "GW"  }
}
if ($Only) { foreach ($k in @($Hosts.Keys)) { if ($Only -notcontains $k) { $Hosts.Remove($k) } } }

function Say($t, $c = "Gray") { Write-Host $t -ForegroundColor $c }

Say ""
Say "CCTE R82 lab scripts - $(if ($Restore) { 'RESTORE ORIGINALS' } else { 'INSTALL' }) ($Repo@$Branch)" Cyan

# --- plink -------------------------------------------------------------------
$plink = (Get-Command plink.exe -ErrorAction SilentlyContinue).Source
if (-not $plink) {
    foreach ($p in "$env:ProgramFiles\PuTTY\plink.exe", "${env:ProgramFiles(x86)}\PuTTY\plink.exe") { if (Test-Path $p) { $plink = $p } }
}
if (-not $plink) { Say "plink.exe (PuTTY) was not found on this machine." Red; return }

# --- password ----------------------------------------------------------------
$pwFile = Join-Path $HOME ".ssh\lab-password.txt"
if (Test-Path $pwFile) {
    $pw = (Get-Content $pwFile -Raw).Trim()
} else {
    $sec = Read-Host "Lab admin password (used for this run only)" -AsSecureString
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

# --- packages ----------------------------------------------------------------
$base = "https://raw.githubusercontent.com/$Repo/$Branch"
$pkg = @{}
if (-not $Restore) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($p in "SMS", "GW") {
        if ($LocalDist) { $pkg[$p] = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $LocalDist "$p.tgz"))); continue }
        $tmp = Join-Path $env:TEMP "ccte-$p.tgz"
        Invoke-WebRequest -UseBasicParsing -Uri "$base/dist/$p.tgz" -OutFile $tmp
        $pkg[$p] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tmp))
        Remove-Item $tmp
    }
    if ($LocalDist) { $manifest = Get-Content (Join-Path $LocalDist "manifest.md5") -Raw }
    else { $manifest = (Invoke-WebRequest -UseBasicParsing -Uri "$base/dist/manifest.md5").Content }
    Say "Downloaded packages: SMS $([int]($pkg.SMS.Length * 3 / 4 / 1024)) KB, GW $([int]($pkg.GW.Length * 3 / 4 / 1024)) KB" DarkGray
}

# --- remote script (bash) ------------------------------------------------------
$remoteInstall = @'
D=/home/admin/CCTE_Scripts
[ -d "$D" ] || { echo "RESULT FAIL no $D on this host"; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)
if [ "$MODE" = "restore" ]; then
    if [ ! -d "$D/.orig" ]; then echo "RESULT SKIP nothing to restore (no .orig folder)"; exit 0; fi
    mkdir -p "$D/.backup-$TS" && cp -p "$D"/lab* "$D/VERSION" "$D/.backup-$TS/" 2>/dev/null
    rm -f "$D"/lab* "$D/VERSION" /usr/bin/labmenu
    cp -p "$D/.orig/"* "$D/" && chmod 777 "$D"/lab*
    echo "RESULT OK original scripts restored (copy of the new ones in .backup-$TS)"
    exit 0
fi
if [ ! -d "$D/.orig" ]; then mkdir "$D/.orig" && cp -p "$D"/lab* "$D/.orig/"; fi
mkdir -p "$D/.backup-$TS" && cp -p "$D"/lab* "$D/.backup-$TS/" 2>/dev/null
base64 -d /tmp/ccte.b64 > /tmp/ccte.tgz || { echo "RESULT FAIL package did not arrive intact"; exit 1; }
tar -xzf /tmp/ccte.tgz -C "$D" || { echo "RESULT FAIL could not unpack"; exit 1; }
chmod 755 "$D"/lab* "$D/labmenu"
ln -sf "$D/labmenu" /usr/bin/labmenu
BAD=0
while read -r sum file; do
    [ -f "$D/$file" ] || { echo "missing $file"; BAD=1; continue; }
    [ "$(md5sum < "$D/$file" | cut -d' ' -f1)" = "$sum" ] || { echo "md5 mismatch $file"; BAD=1; }
done < /tmp/ccte.md5
rm -f /tmp/ccte.b64 /tmp/ccte.tgz /tmp/ccte.md5
if [ $BAD -eq 0 ]; then echo "RESULT OK version $(cat "$D/VERSION") installed, originals kept in $D/.orig, type: labmenu"
else echo "RESULT FAIL file check failed"; fi
'@

function Invoke-Gaia([string]$IP, [string[]]$Lines, [bool]$Clish, [int]$TimeoutSec = 180) {
    $psi = New-Object Diagnostics.ProcessStartInfo $plink
    $psi.Arguments = "-ssh -batch -t -l $User -pw `"$pw`" $IP"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $send = { param($t, $ms) $p.StandardInput.Write($t + "`n"); $p.StandardInput.Flush(); Start-Sleep -Milliseconds $ms }
    Start-Sleep 3
    if ($Clish) { & $send "expert" 1500; & $send $pw 2500 }
    & $send "stty -echo 2>/dev/null; unset PROMPT_COMMAND; export PS1=''" 800
    foreach ($l in $Lines) { & $send $l 250 }
    & $send "exit" 200
    if ($Clish) { & $send "exit" 200 }
    $p.StandardInput.Close()
    $task = $p.StandardOutput.ReadToEndAsync()
    if (-not $task.Wait($TimeoutSec * 1000)) { $p.Kill(); return "TIMEOUT" }
    return $task.Result.Replace("`r", "")
}

function Chunk-Lines([string]$b64, [string]$file) {
    $out = @("rm -f $file")
    for ($i = 0; $i -lt $b64.Length; $i += 500) { $out += "echo " + $b64.Substring($i, [Math]::Min(500, $b64.Length - $i)) + " >> $file" }
    return $out
}

$results = @()
foreach ($name in $Hosts.Keys) {
    $ip = $Hosts[$name].IP; $pack = $Hosts[$name].Pack
    Write-Host ("{0,-9} {1,-11} " -f $name, $ip) -NoNewline
    if (-not (Test-NetConnection $ip -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        Say "not reachable on port 22 - skipped" Yellow; $results += "$name SKIP"; continue
    }
    # Accept the host key on first contact, and find out the login shell
    $probe = cmd /c "echo y| `"$plink`" -ssh -l $User -pw `"$pw`" $ip `"echo SHELL_IS_`$((40+2))`" 2>&1" | Out-String
    if ($probe -match "Access denied|password") { Say "login failed (check the password)" Red; $results += "$name FAIL"; continue }
    $clish = $probe -notmatch "SHELL_IS_42"   # bash prints 42; clish only echoes the command back

    $script = $remoteInstall
    $lines = @()
    if ($Restore) { $lines += "export MODE=restore" } else {
        $lines += "export MODE=install"
        $lines += Chunk-Lines $pkg[$pack] "/tmp/ccte.b64"
        $sums = ($manifest -split "`n" | Where-Object { $_ -match "^\w{32}\s+$pack/" } | ForEach-Object { $_ -replace "$pack/", "" }) -join "`n"
        $lines += Chunk-Lines ([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($sums + "`n"))) "/tmp/ccte.md5.b64"
        $lines += "base64 -d /tmp/ccte.md5.b64 > /tmp/ccte.md5; rm -f /tmp/ccte.md5.b64"
    }
    $lines += Chunk-Lines ([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($script.Replace("`r", "")))) "/tmp/ccte-run.b64"
    $lines += 'base64 -d /tmp/ccte-run.b64 > /tmp/ccte-run.sh; bash /tmp/ccte-run.sh < /dev/null 2>&1; rm -f /tmp/ccte-run.sh /tmp/ccte-run.b64'

    $out = Invoke-Gaia $ip $lines $clish
    $res = ($out -split "`n" | ForEach-Object { if ($_ -match "RESULT ((OK|FAIL|SKIP).*)$") { "RESULT " + $Matches[1] } } | Select-Object -Last 1)
    if (-not $res) {
        $res = "RESULT FAIL no answer from host"
        if ($env:CCTE_DEBUG) { $out -split "`n" | Where-Object { $_ -notmatch '^echo [A-Za-z0-9+/=]+ >>' } | Select-Object -First 25 | ForEach-Object { Say "    | $_" DarkGray } }
    }
    $res = $res -replace "^RESULT ", ""
    $color = if ($res -like "OK*") { "Green" } elseif ($res -like "SKIP*") { "Yellow" } else { "Red" }
    Say $res $color
    $out -split "`n" | Where-Object { $_ -match "(missing|md5 mismatch) \S+$" } | ForEach-Object { Say "    $_" Red }
    $results += "$name $res"
}
$pw = $null

Say ""
if ($Restore) {
    Say "Done. The original Check Point scripts are back in /home/admin/CCTE_Scripts." Cyan
} else {
    Say "Done. On A-SMS, A-SMS-02 or the gateways: log in, type 'expert', then 'labmenu'." Cyan
    Say "The lab guide commands (cd /home/admin/CCTE_Scripts; ./labstart <lab>) still work as before." Cyan
}
