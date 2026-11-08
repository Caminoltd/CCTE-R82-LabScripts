# CCTE R82 Lab Scripts – improved set and lab menu

Improved versions of the Check Point CCTE R82 lab ("break") scripts, plus `labmenu`, a simple menu on
each lab appliance. **The lab guide does not change**: every command in the book
(`cd /home/admin/CCTE_Scripts`, `./labstart <lab>`, `./labstop <lab>`, `./labrevert <lab>`) works exactly
as written, with the same results.

## Install (on A-GUI)

Open PowerShell on A-GUI and run:

```powershell
irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/Install-CCTEScripts.ps1 | iex
```

Enter the lab admin password when asked. It is used for this run only and not saved. The installer
updates A-SMS, A-SMS-02, A-GW-01 and A-GW-02, and prints one line per host:

```
A-SMS     10.1.1.101  OK version 2.2.3 installed, originals kept in /home/admin/CCTE_Scripts/.orig, type: labmenu
```

It takes about 20 seconds per host. Requirements: PuTTY `plink.exe` on A-GUI (it is in the lab image) and
SSH from A-GUI to the appliances.

To put the original Check Point scripts back:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/Install-CCTEScripts.ps1))) -Restore
```

Add `-Only A-SMS,A-SMS-02` to change only some hosts.

## Use

On A-SMS, A-SMS-02, A-GW-01 or A-GW-02: log in as admin, type `expert`, then `labmenu`.

```
CCTE R82 Lab Scripts   host: A-SMS   scripts: 2.2.3
Labs on this host:
   1) LAB2A  Troubleshoot Security Management Server Processes  [not running]
   2) LAB2B  Troubleshoot Management High Availability
   ...
   6) LAB8A  Debug Identity Awareness
```

Pick a lab, then **Start**, **Stop**, **Revert** or **Status**. The menu shows and runs the same
command as the lab guide (for example `./labstart lab8a`). `v` turns verbose mode on and off.
After an action it waits for the policy installations and shows each result, and it will not start
a new action while an installation is still running.

## Optional: the lab menu on A-GUI (PowerShell)

A separate menu that runs on A-GUI and drives the appliances for you over SSH. It installs
nothing on the appliances, works with the original Check Point scripts and with this set,
and does not change anything above.

```powershell
irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/agui/Install-CCTELabMenu.ps1 | iex
```

This adds a **CCTE Lab Menu** shortcut to the desktop (files in `C:\CCTE-LabMenu`). Pick a lab, then
Start, Stop, Revert or Status. It runs each lab guide command on the right appliance:

- **Lab 2B** is run from this one window, in the book's order. Start runs A-SMS (2B-1.2a), then
  A-SMS-02 (2B-1.2b), answers *y* (2B-1.2c) and types *exit* on A-SMS (2B-1.3). Stop follows
  Task 2B-3 (A-SMS, then A-SMS-02) and waits for the two servers to agree on their HA state.
- **Lab 4A** runs on whichever gateway is the Active cluster member.
- **Labs 5A, 6A, 8A, 9A** wait for any running policy installation first, then show the result of
  each installation, as in SmartConsole Recent Tasks.

It asks for the lab admin password once per window and keeps it in memory only. To remove it:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Caminoltd/CCTE-R82-LabScripts/main/agui/Install-CCTELabMenu.ps1))) -Uninstall
```

## What changed

See [CHANGES.md](CHANGES.md) and the handout in `docs/`. In short:

- A second `labstart` says "Lab lab8a is already set up ... Nothing was changed" instead of exiting silently.
- `labrevert` on a lab without a revert script says that it runs the stop script instead.
- Ctrl-C during a lab script discards its session and logs out, so no objects stay locked. On A-SMS during
  lab 2b, it restores the connection to A-SMS-02.
- Errors start with `ERROR:` and show the reason from the management API.
- `-v` works before or after the lab name.
- Labs 9a start and stop can be run twice without errors.

## Repository layout

| Path | Contents |
| --- | --- |
| `SMS/`, `GW/` | The improved scripts, as installed in `/home/admin/CCTE_Scripts` |
| `original/` | The Check Point originals from the lab image (6 Mar 2026), for comparison |
| `dist/` | The packages the installer downloads (`SMS.tgz`, `GW.tgz`, `manifest.md5`) |
| `Install-CCTEScripts.ps1` | Installer for A-GUI |
| `build.sh` | Rebuilds `dist/` after a script change |
| `docs/` | Handout for instructors and students |
| `agui/` | Optional lab menu for A-GUI (`CCTE-LabMenu.ps1`) and its installer |

Tested and seen to be working on a CCTE R82 lab on 7 November 2026.
