<#
.SYNOPSIS
  CCTE R82 lab menu for A-GUI. Runs the lab scripts on the appliances for you.

.DESCRIPTION
  Runs the same commands as the lab guide (./labstart, ./labstop, ./labrevert <lab>) on the
  right appliance, over SSH (PuTTY plink) in Expert mode. Works with the original Check Point
  scripts and with the improved set (labmenu). Nothing is installed on the appliances.

  Lab 2B is driven end to end from this one window: A-SMS, then A-SMS-02, answering the
  script prompts and typing "exit" on A-SMS at the right moment, with the book step shown
  for each part.

  Non-interactive use:  .\CCTE-LabMenu.ps1 -Lab lab2b -Action start [-VerboseLab]
#>
param(
    [string]$Lab,
    [ValidateSet("start", "stop", "revert", "status")][string]$Action,
    [switch]$VerboseLab,
    [string]$User = "admin"
)

$Version = "1.0.0"
$Hosts = [ordered]@{ "A-SMS" = "10.1.1.101"; "A-SMS-02" = "10.1.1.111"; "A-GW-01" = "10.1.1.2"; "A-GW-02" = "10.1.1.3" }
$ApiLabs = @("lab5a", "lab6a", "lab8a", "lab9a")
$Labs = [ordered]@{
    "lab2a" = @{ Title = "Troubleshoot Security Management Server Processes"; Host = "A-SMS" }
    "lab2b" = @{ Title = "Troubleshoot Management High Availability";        Host = "A-SMS + A-SMS-02" }
    "lab3a" = @{ Title = "Troubleshoot SmartLog";                             Host = "A-SMS" }
    "lab4a" = @{ Title = "Debug User Mode Processes";                         Host = "Active gateway" }
    "lab5a" = @{ Title = "Debug the Security Gateway Kernel";                 Host = "A-SMS" }
    "lab6a" = @{ Title = "Debug Unified Policy Inspection";                   Host = "A-SMS" }
    "lab8a" = @{ Title = "Debug Identity Awareness";                          Host = "A-SMS" }
    "lab9a" = @{ Title = "Troubleshoot Site-to-Site VPN";                     Host = "A-SMS" }
}

function Say([string]$t, [string]$c = "Gray") { Write-Host $t -ForegroundColor $c }
function Step([string]$book, [string]$t) { Write-Host ""; Write-Host ("[{0}] " -f $book) -ForegroundColor Cyan -NoNewline; Write-Host $t -ForegroundColor White }

# ---------------------------------------------------------------- plink / password
$script:plink = (Get-Command plink.exe -ErrorAction SilentlyContinue).Source
if (-not $script:plink) {
    foreach ($p in "$env:ProgramFiles\PuTTY\plink.exe", "${env:ProgramFiles(x86)}\PuTTY\plink.exe") { if (Test-Path $p) { $script:plink = $p } }
}
if (-not $script:plink) { Say "plink.exe (PuTTY) was not found on this machine." Red; return }

$script:pw = $null
function Get-LabPassword {
    if ($script:pw) { return $script:pw }
    $f = Join-Path $HOME ".ssh\lab-password.txt"
    if (Test-Path $f) { $script:pw = (Get-Content $f -Raw).Trim() }
    else {
        $sec = Read-Host "Lab admin password (kept in memory for this window only)" -AsSecureString
        $script:pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    }
    return $script:pw
}

# ---------------------------------------------------------------- Gaia session
# A live plink session in Expert mode. Output is read raw (prompts have no newline).
function Open-Gaia([string]$Name) {
    $ip = $Hosts[$Name]; $pw = Get-LabPassword
    $probe = cmd /c "echo y| `"$script:plink`" -ssh -l $User -pw `"$pw`" $ip `"echo SHELL_IS_`$((40+2))`" 2>&1" | Out-String
    if ($probe -match "Access denied") { throw "Login to $Name ($ip) failed - check the password" }
    $clish = $probe -notmatch "SHELL_IS_42"
    $psi = New-Object Diagnostics.ProcessStartInfo $script:plink
    $psi.Arguments = "-ssh -batch -t -l $User -pw `"$pw`" $ip"
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $s = [pscustomobject]@{ Name = $Name; P = $p; Buf = New-Object Text.StringBuilder; Mark = 0; Task = $null; Chars = New-Object char[] 4096; Shown = 0 }
    Start-Sleep 2
    if ($clish) {
        Send-Gaia $s "expert"; [void](Wait-Gaia $s "Password:" 20 -Quiet)
        Send-Gaia $s $pw;      [void](Wait-Gaia $s "#\s*$|expert mode" 20 -Quiet)
    }
    Send-Gaia $s "stty -echo 2>/dev/null; unset PROMPT_COMMAND; export PS1='CCTE_READY> '; cd /home/admin/CCTE_Scripts"
    [void](Wait-Gaia $s "CCTE_READY> " 20 -Quiet)
    $s.Mark = $s.Buf.Length; $s.Shown = $s.Buf.Length
    return $s
}

function Send-Gaia($s, [string]$t) { $s.P.StandardInput.Write($t + "`n"); $s.P.StandardInput.Flush() }

function Pump-Gaia($s) {
    if ($null -eq $s.Task) { $s.Task = $s.P.StandardOutput.ReadAsync($s.Chars, 0, $s.Chars.Length) }
    while ($s.Task.IsCompleted) {
        $n = $s.Task.Result
        if ($n -le 0) { return $false }
        [void]$s.Buf.Append($s.Chars, 0, $n)
        $s.Task = $s.P.StandardOutput.ReadAsync($s.Chars, 0, $s.Chars.Length)
    }
    return $true
}

function Show-New($s) {
    # Print what arrived since last time, cleaned of terminal codes and our own prompt markers
    $t = $s.Buf.ToString($s.Shown, $s.Buf.Length - $s.Shown); $s.Shown = $s.Buf.Length
    $t = $t -replace "\x1b\][^\x07]*\x07", "" -replace "\x1b\[[0-9;?]*[A-Za-z]", "" -replace "\r(?!\n)", "`n" -replace "\r", ""
    $t = $t -replace "CCTE_READY> ", "" -replace "__RC=\d+", ""
    $t = $t -replace "(?:\nWorking \.+)+(?=\nWorking)", ""
    if ($t) { Write-Host -NoNewline ("" + $t) }
}

# Wait until $Pattern appears in the output since the last mark. Returns the match text, or $null on timeout/exit.
function Wait-Gaia($s, [string]$Pattern, [int]$TimeoutSec = 600, [switch]$Quiet) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $alive = Pump-Gaia $s
        if (-not $Quiet) { Show-New $s }
        $since = $s.Buf.ToString($s.Mark, $s.Buf.Length - $s.Mark)
        $m = [regex]::Match($since, $Pattern)
        if ($m.Success) { $s.Mark = $s.Mark + $m.Index + $m.Length; if (-not $Quiet) { Show-New $s }; return $m.Value }
        if (-not $alive -or $s.P.HasExited) { return $null }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Close-Gaia($s) {
    if ($null -eq $s) { return }
    try { Send-Gaia $s "exit"; Send-Gaia $s "exit"; $s.P.StandardInput.Close() } catch { }
    if (-not $s.P.WaitForExit(3000)) { try { $s.P.Kill() } catch { } }
}

# Run one lab command and wait for it to finish. Returns the exit code (or -1).
function Invoke-LabCmd($s, [string]$Cmd, [int]$TimeoutSec = 900) {
    $v = if ($script:VerboseOn) { " -v" } else { "" }
    Say ""; Say ("{0}> ./{1}{2}     (the same command as in the lab guide)" -f $s.Name, $Cmd, $v) Yellow
    Send-Gaia $s ("./{0}{1} < /dev/null; echo __RC=`$?" -f $Cmd, $v)
    $r = Wait-Gaia $s "__RC=\d+" $TimeoutSec
    Write-Host ""
    if ($r) { return [int]($r -replace "__RC=", "") } else { return -1 }
}

# Read-only shell command; returns its output as text
function Invoke-Read($s, [string]$Cmd, [int]$TimeoutSec = 120) {
    Send-Gaia $s ("{0}; echo __RC=`$?" -f $Cmd)
    $start = $s.Mark
    $r = Wait-Gaia $s "__RC=\d+" $TimeoutSec -Quiet
    $s.Shown = $s.Buf.Length
    $t = $s.Buf.ToString($start, [Math]::Max(0, $s.Mark - $start))
    return ($t -replace "\x1b\][^\x07]*\x07", "" -replace "\x1b\[[0-9;?]*[A-Za-z]", "" -replace "\r", "" -replace "CCTE_READY> ", "" -replace "__RC=\d+", "").Trim("`n").TrimEnd()
}

# ---------------------------------------------------------------- policy installs (SMS)
$WaitInstalls = @'
source /etc/profile.d/CP.sh 2>/dev/null
n() { mgmt_cli -r true show tasks status in-progress details-level full -f json 2>/dev/null | jq -r --arg s "$(( ($(date +%s) - 600) * 1000 ))" '[.tasks[]? | select((."task-name" | contains("Policy installation")) and (."start-time".posix // 0) > ($s|tonumber))] | length' 2>/dev/null; }
i=0; c=$(n); while [ "${c:-0}" -gt 0 ] && [ $i -lt 60 ]; do [ $i -eq 0 ] && echo -n "Waiting for $c policy installation(s) to finish "; echo -n "."; sleep 5; i=$((i+1)); c=$(n); done; [ $i -gt 0 ] && echo " done"
'@
function Results-Cmd([int]$since) {
    return "mgmt_cli -r true show tasks from-date `"`$(date -u -d @$since +%Y-%m-%dT%H:%M:%S)`" details-level full -f json 2>/dev/null | jq -r --arg s `"$($since * 1000)`" '.tasks[]? | select((.`"task-name`" | contains(`"Policy installation`")) and (.`"start-time`".posix // 0) >= (`$s|tonumber)) | `"  \(.status)  -  \(.`"task-name`")`" + ([.`"task-details`"[]? | select(.statusDescription != `"Succeeded`") | `"\n      \(.gatewayName): \([.stagesInfo[]?.messages[]?.message] | unique | join(`" `") | .[0:200])`"] | unique | join(`"`"))'"
}
function Wait-Installs($s) { [void](Invoke-Read $s ($WaitInstalls -replace "`r", "") 330) }
function Show-InstallResults($s, [int]$since, [string]$lab, [string]$action) {
    Say "Waiting for the policy installations this action started..." DarkGray
    $k = 0
    do { Start-Sleep 5; $k++; $c = Invoke-Read $s ("mgmt_cli -r true show tasks from-date `"`$(date -u -d @$since +%Y-%m-%dT%H:%M:%S)`" details-level full -f json 2>/dev/null | jq -r --arg s `"$($since * 1000)`" '[.tasks[]? | select((.`"task-name`" | contains(`"Policy installation`")) and (.`"start-time`".posix // 0) >= (`$s|tonumber))] | length'") } while ([int]("0" + ($c -replace "\D", "")) -lt 2 -and $k -lt 24)
    $w = Invoke-Read $s ($WaitInstalls -replace "`r", "") 330; if ($w) { Say $w DarkGray }
    Say "Policy installation results (as in SmartConsole > Recent Tasks):" White
    $r = Invoke-Read $s (Results-Cmd $since)
    foreach ($line in ($r -split "`n")) {
        if ($line -match "^\s*succeeded") { Say ("  " + $line.Trim()) Green } elseif ($line -match "^\s*failed") { Say $line Red } elseif ($line.Trim()) { Say $line Yellow }
    }
    if ($lab -eq "lab8a" -and $action -eq "start") { Say "  (Lab 8A: the Bravo-Standard failure on B-GW is the problem you troubleshoot in this lab.)" Cyan }
}

# ---------------------------------------------------------------- single-host labs
function Get-ActiveGateway {
    foreach ($g in "A-GW-02", "A-GW-01") {
        $s = $null
        try {
            $s = Open-Gaia $g
            $o = Invoke-Read $s "cphaprob state 2>/dev/null | grep -i '(local)'"
            if ($o -match "(?i)active") { return $g }
        } catch { } finally { Close-Gaia $s }
    }
    return "A-GW-02"
}

function Run-Simple([string]$lab, [string]$action) {
    $hostName = "A-SMS"
    if ($lab -eq "lab4a") {
        Say "Lab 4A runs on the Active cluster member (book 4A-1.1 / 4A-1.2). Checking which member is Active..." DarkGray
        $hostName = Get-ActiveGateway; Say "Active member: $hostName" Green
    }
    $s = $null
    try {
        $s = Open-Gaia $hostName
        $api = $ApiLabs -contains $lab
        if ($api) { Wait-Installs $s }
        $since = [int](Invoke-Read $s "date +%s")
        $rc = Invoke-LabCmd $s ("lab{0} {1}" -f $action, $lab)
        if ($rc -eq 0) { Say "Finished (exit code 0)." Green } elseif ($rc -eq -1) { Say "No answer from $hostName within the time limit." Red } else { Say "Finished with exit code $rc - read the messages above." Yellow }
        if ($api -and ($rc -eq 0 -or $rc -eq 2)) { Show-InstallResults $s $since $lab $action }
    } catch { Say $_.Exception.Message Red } finally { Close-Gaia $s }
}

# ---------------------------------------------------------------- lab 2B, both servers
function Run-2B([string]$action) {
    $a = $null; $b = $null
    try {
        switch ($action) {
            "start" {
                Say "Lab 2B start drives both servers from this window, in the order of book Task 2B-1." White
                Step "2B-1.2a" "A-SMS: start the script. It cuts A-SMS off from A-SMS-02 and then waits for 'exit'."
                $a = Open-Gaia "A-SMS"
                $v = if ($script:VerboseOn) { " -v" } else { "" }
                Say "A-SMS> ./labstart lab2b$v" Yellow
                Send-Gaia $a "./labstart lab2b$v; echo __RC=`$?"
                $r = Wait-Gaia $a 'Type "exit" to restore connectivity|__RC=\d+' 900
                if ($r -notmatch "Type") { Say "`nA-SMS did not reach the 'exit' prompt - read the messages above (A-SMS must be Active and A-SMS-02 Standby and synchronised)." Red; return }

                Step "2B-1.2b" "A-SMS-02: start the script while A-SMS waits."
                $b = Open-Gaia "A-SMS-02"
                Say "A-SMS-02> ./labstart lab2b$v" Yellow
                Send-Gaia $b "./labstart lab2b$v; echo __RC=`$?"
                $r = Wait-Gaia $b 'Has the same script been started on A-SMS\? \(y/n\):|__RC=\d+' 300
                if ($r -notmatch "Has the same") { Say "`nA-SMS-02 stopped early - read the messages above. A-SMS is still waiting; typing exit there to restore connectivity." Red; Send-Gaia $a "exit"; [void](Wait-Gaia $a "__RC=\d+" 120); return }
                Step "2B-1.2c" "A-SMS-02 asks whether the script is running on A-SMS: it is, so answering y."
                Send-Gaia $b "y"
                $r = Wait-Gaia $b 'Please return to A-SMS|__RC=\d+' 300
                if ($r -notmatch "return") { Say "`nA-SMS-02 did not complete - read the messages above. Typing exit on A-SMS to restore connectivity." Red; Send-Gaia $a "exit"; [void](Wait-Gaia $a "__RC=\d+" 120); return }

                Step "2B-1.3" "Back on A-SMS: typing exit in the waiting script. This restores the connection between the two servers."
                Send-Gaia $a "exit"
                $ra = Wait-Gaia $a "__RC=\d+" 300
                Step "2B-1.3" "A-SMS-02: its script ends by itself once A-SMS is reachable again."
                $rb = Wait-Gaia $b "__RC=\d+" 300
                Write-Host ""
                if ($ra -eq "__RC=0" -and $rb -eq "__RC=0") {
                    Say "Lab 2B is set up: both servers are Active and can see each other." Green
                    Say "Continue with Task 2B-2 (page 159). The conflict in SmartConsole can take 3 to 5 minutes to show." Green
                } else { Say "Finished with A-SMS $ra, A-SMS-02 $rb - read the messages above." Yellow }
            }
            "stop" {
                Say "Lab 2B stop follows book Task 2B-3: A-SMS first, then A-SMS-02." White
                Step "2B-3.2b" "A-SMS: restore script (makes A-SMS Active again)."
                $a = Open-Gaia "A-SMS"; $st = $a.Buf.Length; $ra = Invoke-LabCmd $a "labstop lab2b"
                $rb = $null
                if ($ra -ne 0 -and $a.Buf.ToString($st, $a.Buf.Length - $st) -match "stop script on A-SMS-02 first") {
                    Say "Both servers are still Active, so A-SMS-02 has to be set to Standby first." Yellow
                    $b = Open-Gaia "A-SMS-02"
                    for ($try = 1; $try -le 4; $try++) {
                        Step "2B-3.5b" "A-SMS-02: restore script first (attempt $try)."
                        $rb = Invoke-LabCmd $b "labstop lab2b"
                        if ($rb -eq 0) { break }
                        if ($try -lt 4) { Say "A-SMS-02 is not ready yet (the servers are still settling after the conflict). Trying again in 30 seconds..." Yellow; Start-Sleep 30 }
                    }
                    for ($try = 1; $try -le 11; $try++) {
                        Step "2B-3.2b" "A-SMS: restore script again, now that A-SMS-02 is Standby (attempt $try)."
                        $st = $a.Buf.Length; $ra = Invoke-LabCmd $a "labstop lab2b"
                        if ($ra -eq 0 -or $a.Buf.ToString($st, $a.Buf.Length - $st) -notmatch "stop script on A-SMS-02 first") { break }
                        if ($try -lt 11) { Say "A-SMS still sees A-SMS-02 as Active; its view updates within a few minutes (book: 3 to 5 minutes). Trying again in 30 seconds..." Yellow; Start-Sleep 30 }
                    }
                }
                $o = Invoke-Read $a "cpprod_util FwIsActiveManagement"
                Step "2B-3.2c" ("A-SMS FwIsActiveManagement = {0} (1 = Active)" -f $o)
                if ($rb -ne 0) {
                    Step "2B-3.5b" "A-SMS-02: restore script (sets A-SMS-02 to Standby)."
                    if ($null -eq $b) { $b = Open-Gaia "A-SMS-02" }
                    $rb = Invoke-LabCmd $b "labstop lab2b"
                }
                $o = Invoke-Read $b "cpprod_util FwIsActiveManagement"
                Step "2B-3.5c" ("A-SMS-02 FwIsActiveManagement = {0} (0 = Standby)" -f $o)
                if ($ra -eq 0 -and $rb -eq 0) { Say "`nLab 2B restored. Continue with 2B-3.7: SmartConsole to A-SMS (10.1.1.101)." Green }
                else { Say "`nFinished with A-SMS $ra, A-SMS-02 $rb - read the messages above." Yellow }
            }
            "revert" {
                Say "Lab 2B revert: back to the start of the lab (A-SMS Active, A-SMS-02 Standby, LDAP Services group restored)." White
                Step "revert" "A-SMS: revert script."
                $a = Open-Gaia "A-SMS"
                $v = if ($script:VerboseOn) { " -v" } else { "" }
                Say "A-SMS> ./labrevert lab2b$v" Yellow
                Send-Gaia $a "./labrevert lab2b$v; echo __RC=`$?"
                $r = Wait-Gaia $a 'Type "exit" to restore connectivity|__RC=\d+' 900
                Step "revert" "A-SMS-02: revert script."
                $b = Open-Gaia "A-SMS-02"
                Say "A-SMS-02> ./labrevert lab2b$v" Yellow
                Send-Gaia $b "./labrevert lab2b$v; echo __RC=`$?"
                if ($r -match "Type") {
                    $rb = Wait-Gaia $b 'Please return to A-SMS|__RC=\d+' 300
                    Step "revert" "Back on A-SMS: typing exit to restore connectivity."
                    Send-Gaia $a "exit"; $ra = Wait-Gaia $a "__RC=\d+" 600
                    if ($rb -notmatch "__RC") { $rb = Wait-Gaia $b "__RC=\d+" 300 }
                } else { $ra = $r; $rb = Wait-Gaia $b "__RC=\d+" 300 }
                if ($ra -eq "__RC=0" -and $rb -eq "__RC=0") { Say "`nLab 2B reverted. Start it again when ready." Green }
                else { Say "`nFinished with A-SMS $ra, A-SMS-02 $rb - read the messages above." Yellow }
            }
        }
    } catch { Say $_.Exception.Message Red } finally { Close-Gaia $a; Close-Gaia $b }
}

# ---------------------------------------------------------------- status (read-only)
function Show-Status([string]$lab) {
    $s = $null
    try {
        $s = Open-Gaia "A-SMS"
        $cmd = switch ($lab) {
            "lab2a" { "pgrep -x lab2a_start >/dev/null && echo 'Lab 2A is running (CPM is being stopped every 15 s).' || echo 'Lab 2A is not running.'" }
            "lab3a" { "pgrep -x lab3a_start >/dev/null && echo 'Lab 3A is running.' || echo 'Lab 3A is not running.'" }
            "lab2b" { "source /etc/profile.d/CP.sh; mgmt_cli -r true show ha-state -f json 2>/dev/null | jq -r '.domains[].servers[] | `"\(.name): \(.`"ha-state`")`"'; clish -c 'show route static' 2>/dev/null | grep -q '10.1.1.111/32.*reject' && echo 'A-SMS has a reject route to A-SMS-02 (the lab 2B start script on A-SMS is waiting for exit).'" }
            "lab6a" { "mgmt_cli -r true show access-rule name 'Unified Policy Test Rule' layer 'Web Content Layer' -f json >/dev/null 2>&1 && echo 'Lab 6A is set up.' || echo 'Lab 6A is not set up.'" }
            "lab8a" { "mgmt_cli -r true show access-rule name 'Media Access rule' layer 'Web Content Layer' -f json >/dev/null 2>&1 && echo 'Lab 8A is set up (Media Access rule exists).' || echo 'Lab 8A is not set up.'" }
            "lab9a" { "mgmt_cli -r true show vpn-community-star name Bravo2AlphaVPN -f json >/dev/null 2>&1 && echo 'Lab 9A is set up.' || echo 'Lab 9A is not set up.'" }
            default { "echo 'No status check for $lab.'" }
        }
        Say (Invoke-Read $s $cmd) White
        if ($lab -eq "lab4a") { Say "Lab 4A runs on the gateways; use Status in labmenu on the gateway, or ps aux | grep lab." DarkGray }
    } catch { Say $_.Exception.Message Red } finally { Close-Gaia $s }
}

function Invoke-Action([string]$lab, [string]$action) {
    if ($action -eq "status") { Show-Status $lab; return }
    if ($lab -eq "lab2b") { Run-2B $action } else { Run-Simple $lab $action }
}

# ---------------------------------------------------------------- menu
$script:VerboseOn = [bool]$VerboseLab
if ($Lab -and $Action) { Invoke-Action $Lab.ToLower() $Action; return }

function Pause-Menu { Write-Host ""; [void](Read-Host "Press Enter to return to the menu") }
function Header {
    Clear-Host
    Say "CCTE R82 Lab Menu for A-GUI  (v$Version)" Cyan
    Say ("Runs the lab guide commands on the appliances for you.   Verbose: {0}" -f $(if ($script:VerboseOn) { "ON" } else { "off" })) DarkGray
    Say "-----------------------------------------------------------------------------" DarkGray
}
while ($true) {
    Header
    $keys = @($Labs.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) { Write-Host ("  {0}) {1}  {2,-52} [{3}]" -f ($i + 1), $keys[$i].ToUpper(), $Labs[$keys[$i]].Title, $Labs[$keys[$i]].Host) }
    Write-Host ""; Write-Host "  v) Verbose on/off   q) Quit"; Write-Host ""
    $c = Read-Host "Choose a lab"
    if ($c -match "^[qQ]") { break }
    if ($c -match "^[vV]") { $script:VerboseOn = -not $script:VerboseOn; continue }
    if (-not ($c -match "^\d+$") -or [int]$c -lt 1 -or [int]$c -gt $keys.Count) { continue }
    $lab = $keys[[int]$c - 1]
    while ($true) {
        Header
        Say ("{0}  {1}" -f $lab.ToUpper(), $Labs[$lab].Title) White
        if ($lab -eq "lab2b") { Say "Runs on A-SMS and A-SMS-02 together; this window answers the prompts in the book's order." Yellow }
        if ($lab -eq "lab4a") { Say "Runs on the Active cluster member (detected automatically)." Yellow }
        Write-Host ""
        Write-Host "  1) Start    ./labstart $lab"
        Write-Host "  2) Stop     ./labstop $lab"
        Write-Host "  3) Revert   ./labrevert $lab"
        Write-Host "  4) Status   read-only check"
        Write-Host "  b) Back"
        Write-Host ""
        $a = Read-Host "Choice"
        if ($a -match "^[bB]" -or $a -eq "") { break }
        $act = switch ($a) { "1" { "start" } "2" { "stop" } "3" { "revert" } "4" { "status" } default { $null } }
        if (-not $act) { continue }
        if ($act -eq "revert") { if ((Read-Host "Revert $lab? Work done in this lab will be undone (y/n)") -notmatch "^[yY]") { continue } }
        Invoke-Action $lab $act
        Pause-Menu
    }
}
