# Appliance scripts 2.2.4 and A-GUI lab menu 1.0.4 (8 Nov 2026)

| File | Change |
| --- | --- |
| `GW/lab4a_stop` | After "Setup completed", reminds you of lab guide step 4A-4.2: the stop script ends the kill loop but does not start CPD; the student starts it with `cpwd_admin start -name CPD -path "$CPDIR/bin/cpd" -command "cpd"`. Without it, management cannot reach the gateway and policy installs to A-GW-Cluster fail |
| `agui/CCTE-LabMenu.ps1` | Shows the same 4A-4.2 reminder (also with the original scripts). Lab 4A Stop and Revert now run on the gateway where lab 4A is actually running |

# Appliance scripts 2.2.3 and A-GUI lab menu 1.0.3 (8 Nov 2026)

| File | Change |
| --- | --- |
| `labmenu` (appliances) | After Start, Stop or Revert of labs 5A, 6A, 8A and 9A, waits for policy installations only when the script printed "Setup completed". A second run ("already set up") starts no installation, and the menu used to wait about 2 minutes for one before showing an empty result. Now it says "No policy installation was started (nothing was changed)." |
| `agui/CCTE-LabMenu.ps1` | Same fix in the A-GUI menu |

# A-GUI lab menu 1.0.2 (8 Nov 2026)

Shows "Connecting to <host> ... ok" for every SSH login (each takes about 12 seconds), says when an
action is working, ignores keys pressed while waiting (they used to skip the "Press Enter" pause),
and remembers each host's login shell so later connections in the same window are quicker.

# A-GUI lab menu 1.0.1 (8 Nov 2026)

Status added for Lab 4A (both gateways: cluster state and whether the lab script runs) and Lab 5A.

# A-GUI lab menu 1.0.0 (8 Nov 2026)

New, optional, in `agui/`; nothing else changes. `CCTE-LabMenu.ps1` runs on A-GUI and drives the
lab scripts on the appliances over plink in Expert mode (original or improved scripts).
`Install-CCTEScripts.ps1` and the appliance scripts are untouched.

Tested on 8 Nov 2026 (CCTE R82 lab): lab 2B Start (both servers, about 1 minute) and Stop (including
straight after Start, when A-SMS needs about 2.5 minutes to see A-SMS-02 as Standby); lab 8A Start
and Revert with installation results; status checks.

# Changes in 2.2.2 (8 Nov 2026)

| File | Change |
| --- | --- |
| `lab2b_start`, `lab2b_revert` | One extra line after each existing prompt; the existing lines are unchanged. On A-SMS: "Leave THIS window open. When A-SMS-02 shows 'Setup completed', come back here and type exit." On A-SMS-02: "Type exit in the A-SMS window that is waiting for it (do not open a new session)." Lab guide step 2B-1.3 is easy to read as "close the SSH sessions"; if the waiting A-SMS script never gets `exit`, A-SMS stays cut off from A-SMS-02 and the conflict on page 160 never appears |
| `docs/` handout | New section "Lab notes" with known differences between the lab guide and the R82 lab |

# Changes in 2.2.1 (7 Nov 2026)

| File | Change |
| --- | --- |
| `labmenu` | Before running an action, waits for any policy installation started in the last 10 minutes to finish. Running Revert and then Start straight away made the two sets of installs collide, and the new ones failed. After Start, Stop or Revert, waits for the installations the script started and shows each result, including the reason for a failure (for example the intended B-GW failure in Lab 8A). Uses only jq 1.4 features (the version on Gaia R82) |
| `lab8a_stop` | Counts settings it could not apply. If any, it prints a WARNING after "Setup completed" (for example when the Media Access rule is missing because the lab was reverted) and exits with code 2 |

# Changes in 2.2.0 (7 Nov 2026)

Base: the Check Point scripts in the CCTE R82 lab image (dated 6 Mar 2026, version 2.1.1/2.1.2).
Every lab guide command and every normal message is unchanged. `diff -r original/ SMS/` shows each change.

## All hosts

| File | Change |
| --- | --- |
| `lab_script_functions` | `export VERBOSE`, so `-v` works before or after the lab name. New helpers: `valid_lab_name`, `require_sid`, `lab_interrupted` (Ctrl-C = discard + logout), `lab_already_set_up` (second-run message), `show_api_error` |
| `labstart` | Refuses names that are not `lab<number><letter>` |
| `labstop`, `labrevert` | Same name check. `labrevert` on a lab with no revert script says it runs the stop script. When a background lab was started twice, both copies are stopped |
| `labmenu` | New: menu that runs the lab guide commands |
| `VERSION` | New: `2.2.0` |

## A-SMS / A-SMS-02

| Lab | Change |
| --- | --- |
| 2a | `lab2a_stop`: the "taking too long" warning no longer appears when CPM came up on the 12th check, and the stray text after it is gone |
| 2b | Waiting dots on A-SMS-02 print every 90 s (the test was always true). Ctrl-C or a dropped session on A-SMS removes the reject route to A-SMS-02. Uses `$TMP_OTPT` throughout. Header comments corrected |
| 3a | `pgrep -x` matches the exact process name |
| 5a | Ctrl-C discards and logs out. Login without a session id stops with an error |
| 6a | Second `labstart` explains that the lab is already set up. Errors show the API message. `lab6a_stop` failures exit with code 1 and log out |
| 8a | Second `labstart` explains that the lab is already set up. "Could not create access role" now starts with `ERROR:` and shows the reason. `lab8a_revert` failures exit with code 1 |
| 9a | `labstart` twice: the second run says the lab is already set up. `labstop` twice: no error, A-GW-Cluster is put back in Alpha2BravoVPN |

## A-GW-01 / A-GW-02

| Lab | Change |
| --- | --- |
| 4a | `pgrep -x` matches the exact process name (`cpd`) |

## Not changed on purpose

`install-policy --sync false` and "Kindly check policy installation status in SmartConsole"; the
faults each lab creates; `/tmp/labX.json` file names; message typos; the `TikTok` application name
(already correct in the lab image; the ATC portal zip has `TikTokd` on line 74 of `lab8a_start`).

## Tested on 7 Nov 2026 (CCTE R82 lab)

Install and `-Restore` on all four hosts. labstart/labstop for 2a, 3a, 4a, 5a, 6a, 8a and 9a, each run
twice. labrevert for 3a (stop-script path) and 8a. Interrupting 5a: session discarded, no locks. Menu
navigation and status on A-SMS. **Lab 2b was not run end to end** (it needs both servers driven by hand).
