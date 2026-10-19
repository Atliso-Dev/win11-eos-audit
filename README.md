# Windows 11 End of Support Audit

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Atliso-Win11EndOfSupportAudit?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/Atliso-Win11EndOfSupportAudit)

Read-only PowerShell script that lists every Intune-managed Windows device with its version, edition and the real last day of security updates for that edition.

Windows 11 support is split by edition, not by build. 24H2 is build 10.0.26100 on every edition, but Home and Pro lose support on 13 October 2026 while Enterprise and Education keep it until 12 October 2027. Windows 11 Enterprise LTSC 2024 is also 26100 and is supported for years. Filtering Intune by OS version gives you the wrong list. This script reads each device's edition from Microsoft Graph and works out the date that actually applies to it.

## What it does

- Reads Intune's managed Windows devices through Microsoft Graph, with your own account
- Works out each device's release (21H2 to 26H2) and edition (Home/Pro, Enterprise/Education, SE, LTSC)
- Applies the matching Microsoft lifecycle date and counts the days left
- Never flags LTSC, which has its own long-term lifecycle
- Flags Pro devices in a tenant licensed for Enterprise (when the token can read licences): a sign that subscription activation isn't working
- Exports a CSV and prints a summary with the devices that lose support soonest
- Changes nothing in your tenant. There is no WhatIf switch because nothing is written
- Logs to `%LOCALAPPDATA%\Atliso\Win11EndOfSupportAudit.log`

## Install

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/Atliso-Win11EndOfSupportAudit):

```powershell
Install-Script Atliso-Win11EndOfSupportAudit -Scope CurrentUser
```

Or download `Atliso-Win11EndOfSupportAudit.ps1` from this repo or the [latest release](../../releases/latest).

## Quick start

1. Install the Graph authentication module once:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

2. Download [`Atliso-Win11EndOfSupportAudit.ps1`](Atliso-Win11EndOfSupportAudit.ps1) and check the config at the top:

```powershell
# ===== CONFIG =====
$OutputPath = Join-Path $env:USERPROFILE 'Desktop\Atliso-Win11-EndOfSupport.csv'
$WarnDays   = 60     # flag devices whose support ends within this many days
$LogPath    = Join-Path $env:LOCALAPPDATA 'Atliso\Win11EndOfSupportAudit.log'
# ==================
```

3. Run it and sign in when prompted:

```powershell
.\Atliso-Win11EndOfSupportAudit.ps1
```

MSPs can point it at a customer tenant:

```powershell
.\Atliso-Win11EndOfSupportAudit.ps1 -TenantId contoso.onmicrosoft.com
```

## Output

One CSV row per Windows device:

`DeviceName, UserPrincipalName, OSVersion, Release, Edition, SkuNumber, SupportTrack, LastSupportedDay, DaysLeft, Status, Note, LastSync`

Status is one of:

| Status | Meaning |
|---|---|
| `OutOfSupport` | The last supported day for this device's edition has passed |
| `EndingSoon` | Support ends within `$WarnDays` days |
| `Supported` | Supported for longer than that |
| `LTSC` | Long-term servicing edition, separate lifecycle, never flagged |
| `Unknown` | Edition not reported, or a build that isn't in the lifecycle table. Check the device |

Exit code 0 when nothing is out of support or ending soon, 1 when something is, so it can run on a schedule.

## Lifecycle table

Last supported day, from Microsoft's lifecycle pages for [Windows 11 Home and Pro](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro) and [Windows 11 Enterprise and Education](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-and-education):

| Release | Build | Home / Pro | Enterprise / Education |
|---|---|---|---|
| 26H2 | 26300 | 9 Oct 2028 | 9 Oct 2029 |
| 25H2 | 26200 | 12 Oct 2027 | 10 Oct 2028 |
| 24H2 | 26100 | 13 Oct 2026 | 12 Oct 2027 |
| 23H2 | 22631 | 11 Nov 2025 | 10 Nov 2026 |
| 22H2 | 22621 | 8 Oct 2024 | 14 Oct 2025 |
| 21H2 | 22000 | 10 Oct 2023 | 8 Oct 2024 |

Windows 11 SE follows the Home/Pro dates, and 24H2 is its last version.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7
- The `Microsoft.Graph.Authentication` module
- An account that can read Intune devices: the script asks for `DeviceManagementManagedDevices.Read.All` (delegated). Intune Read Only Operator is enough

## Guide

The full walkthrough, including how to move devices to 25H2 or 26H2 with an Intune feature update policy: [Windows 11 24H2 end of support: find every Intune device on it](https://atliso.com/blog/windows-11-24h2-end-of-support-intune)

Want this checked every day across your whole tenant? [Atliso Pro](https://atliso.com/pro) runs it by edition, alongside BitLocker, LAPS and remediation checks. The first scan is free.

## License

MIT. See [LICENSE](LICENSE).
