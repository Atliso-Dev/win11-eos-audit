<#
.SYNOPSIS
  Atliso Windows 11 End of Support Audit. Read-only.

.DESCRIPTION
  Lists every Intune-managed Windows device with its version, edition and the last day of
  security updates for that edition, and exports the result to CSV.

  Windows 11 support is split by edition, not by build. 24H2 is build 26100 on every edition,
  but Home and Pro lose support on 13 October 2026 while Enterprise and Education keep it until
  12 October 2027, and LTSC 2024 (also 26100) is on a separate long-term lifecycle. Filtering
  Intune by OS version alone gives the wrong list. This script works out the date per device.

  Read-only: it signs in with your own account and only reads Intune's managed devices.
  Nothing in your tenant is changed, so there is no WhatIf switch.

  Guide: https://atliso.com/blog/windows-11-24h2-end-of-support-intune

.PARAMETER TenantId
  Optional. Sign in to a specific tenant (MSPs: run once per customer tenant).

.NOTES
  Requires the Microsoft.Graph.Authentication module:
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
  Delegated permission: DeviceManagementManagedDevices.Read.All (Intune Read Only Operator is enough).
  Runs on PowerShell 5.1 and 7.
  Exit 0 = nothing out of support or ending within $WarnDays. Exit 1 = devices need action.
  MIT licensed. https://github.com/Atliso-Dev/win11-eos-audit
#>
[CmdletBinding()]
param(
  [string]$TenantId
)

# ===== CONFIG =====
$OutputPath = Join-Path $env:USERPROFILE 'Desktop\Atliso-Win11-EndOfSupport.csv'
$WarnDays   = 60     # flag devices whose support ends within this many days
$LogPath    = Join-Path $env:LOCALAPPDATA 'Atliso\Win11EndOfSupportAudit.log'
# ==================

# Edition (GetProductInfo product type, reported by Intune as skuNumber) decides the support track.
$ConsumerSkus   = 98,99,100,101,48,49,161,162,164,165   # Home, Pro, Pro for Workstations, Pro Education
$SeSkus         = 178,179                               # Windows 11 SE: 24H2 is its last version
$EnterpriseSkus = 4,27,121,122,175,188                  # Enterprise, Education, multi-session, IoT Enterprise
$LtscSkus       = 125,126,191                           # LTSC: separate long-term lifecycle, never flagged

# Last supported day per Microsoft's lifecycle pages. Matched on the exact build:
# a build that isn't listed is reported as Unknown rather than given another release's dates.
$Lifecycle = @{
  26300 = @{ Release = '26H2'; Consumer = '2028-10-09'; Enterprise = '2029-10-09' }
  26200 = @{ Release = '25H2'; Consumer = '2027-10-12'; Enterprise = '2028-10-10' }
  26100 = @{ Release = '24H2'; Consumer = '2026-10-13'; Enterprise = '2027-10-12' }
  22631 = @{ Release = '23H2'; Consumer = '2025-11-11'; Enterprise = '2026-11-10' }
  22621 = @{ Release = '22H2'; Consumer = '2024-10-08'; Enterprise = '2025-10-14' }
  22000 = @{ Release = '21H2'; Consumer = '2023-10-10'; Enterprise = '2024-10-08' }
}

# Licences that step Pro up to Enterprise through subscription activation.
$EnterpriseLicencePatterns = '^SPE_E[35]', '^MICROSOFT_365_E[35]', '^WIN10_PRO_ENT_SUB', '^WIN10_VDA_E[35]', '^WINE5', '^WIN_ENT_E[35]', '^M365EDU_A[35]', '^WIN10_EDU_A[35]'

function Write-Log([string]$Message) {
  $dir = Split-Path $LogPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  "$(Get-Date -Format s) $Message" | Add-Content -Path $LogPath
  Write-Verbose $Message
}

# Status code and Retry-After from a failed Graph call, on both PowerShell 5.1 and 7.
function Get-ThrottleWait($ErrorRecord) {
  $resp = $ErrorRecord.Exception.Response
  $code = $null
  if ($resp -and $resp.StatusCode) { $code = [int]$resp.StatusCode }
  elseif ("$ErrorRecord" -match 'TooManyRequests|\b429\b') { $code = 429 }
  if ($code -ne 429) { return $null }
  $wait = 10
  try {
    if ($resp.Headers.RetryAfter.Delta) { $wait = [int][Math]::Ceiling($resp.Headers.RetryAfter.Delta.TotalSeconds) }
    elseif ($resp.Headers['Retry-After']) { $wait = [int]$resp.Headers['Retry-After'] }
  } catch { }
  [Math]::Max(1, $wait)
}

function Get-AllPages([string]$Uri) {
  $items = New-Object System.Collections.Generic.List[object]
  $retries = 0
  while ($Uri) {
    try {
      $page = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
      $retries = 0
    } catch {
      $wait = Get-ThrottleWait $_
      if ($null -ne $wait -and $retries -lt 5) {
        $retries++
        Write-Log "Throttled by Graph, waiting $wait s (retry $retries)"
        Start-Sleep -Seconds $wait
        continue
      }
      throw
    }
    foreach ($v in @($page.value)) { $items.Add($v) }
    $Uri = $page.'@odata.nextLink'
  }
  $items
}

# Optional: does the tenant hold a licence that should make these devices Enterprise? Needs Organization.Read.All,
# which this script doesn't ask for. If the token happens to carry it, use it; otherwise skip quietly.
function Test-EnterpriseLicensed {
  try {
    $skus = Get-AllPages 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuPartNumber,capabilityStatus'
    foreach ($s in $skus) {
      if ($s.capabilityStatus -ne 'Enabled') { continue }
      foreach ($p in $EnterpriseLicencePatterns) { if ($s.skuPartNumber -match $p) { return $true } }
    }
    return $false
  } catch {
    Write-Log 'Licence check skipped (no Organization.Read.All on this token)'
    return $false
  }
}

$connect = @{ Scopes = 'DeviceManagementManagedDevices.Read.All'; NoWelcome = $true }
if ($TenantId) { $connect.TenantId = $TenantId }
Connect-MgGraph @connect
Write-Log 'Connected to Microsoft Graph'

# Edition fields (skuNumber, skuFamily) are on the beta managedDevice resource.
$select  = 'id,deviceName,userPrincipalName,operatingSystem,osVersion,skuFamily,skuNumber,lastSyncDateTime'
$devices = @(Get-AllPages "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=$select" |
  Where-Object { $_.operatingSystem -eq 'Windows' })
Write-Log "Read $($devices.Count) Windows devices"

$entLicensed = Test-EnterpriseLicensed
$today = (Get-Date).Date

$rows = foreach ($d in $devices) {
  $build = $null
  if ($d.osVersion -match '^10\.0\.(\d+)') { $build = [int]$Matches[1] }
  $sku = 0
  if ($null -ne $d.skuNumber) { $sku = [int]$d.skuNumber }

  $track = 'Unknown'
  if ($LtscSkus -contains $sku) { $track = 'LTSC' }
  elseif ($EnterpriseSkus -contains $sku) { $track = 'Enterprise' }
  elseif ($SeSkus -contains $sku) { $track = 'SE' }
  elseif ($ConsumerSkus -contains $sku) { $track = 'HomePro' }

  $life = $null
  if ($build -and $Lifecycle.ContainsKey($build)) { $life = $Lifecycle[$build] }
  $release = 'Unknown'
  if ($life) { $release = $life.Release } elseif ($build -and $build -lt 22000) { $release = 'Windows 10' }

  $lastDay = $null; $daysLeft = $null; $status = 'Unknown'; $note = ''
  if ($track -eq 'LTSC') {
    $status = 'LTSC'; $note = 'Long-term servicing, separate lifecycle'
  } elseif ($release -eq 'Windows 10') {
    $status = 'OutOfSupport'; $note = 'Windows 10 ended 14 Oct 2025 unless enrolled in ESU'
  } elseif (-not $life) {
    $note = 'Build not in the lifecycle table, check manually'
  } elseif ($track -eq 'Unknown') {
    $note = 'Edition not reported, check the device'
  } else {
    $lastDay = [datetime]::ParseExact($(if ($track -eq 'Enterprise') { $life.Enterprise } else { $life.Consumer }), 'yyyy-MM-dd', $null)
    $daysLeft = ($lastDay - $today).Days
    if ($daysLeft -lt 0) { $status = 'OutOfSupport' } elseif ($daysLeft -le $WarnDays) { $status = 'EndingSoon' } else { $status = 'Supported' }
    if ($track -eq 'SE' -and $release -eq '24H2') { $note = 'SE: 24H2 is the last version, replace or reimage' }
    elseif ($track -eq 'HomePro' -and $entLicensed) { $note = 'Pro edition in an Enterprise-licensed tenant: check subscription activation' }
  }

  [pscustomobject]@{
    DeviceName        = $d.deviceName
    UserPrincipalName = $d.userPrincipalName
    OSVersion         = $d.osVersion
    Release           = $release
    Edition           = $d.skuFamily
    SkuNumber         = $d.skuNumber
    SupportTrack      = $track
    LastSupportedDay  = $(if ($lastDay) { $lastDay.ToString('yyyy-MM-dd') } else { '' })
    DaysLeft          = $daysLeft
    Status            = $status
    Note              = $note
    LastSync          = $d.lastSyncDateTime
  }
}
$rows = @($rows)

# Out of support first (Windows 10 has no countdown), then soonest to end, then the rest.
$sorted = $rows | Sort-Object @{ Expression = {
    if ($_.Status -eq 'OutOfSupport' -and $null -eq $_.DaysLeft) { [int]::MinValue }
    elseif ($null -ne $_.DaysLeft) { $_.DaysLeft }
    else { [int]::MaxValue } } }, DeviceName
$sorted | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host "Windows devices: $($rows.Count)"
$rows | Group-Object Status | Sort-Object Name | Format-Table @{ L = 'Status'; E = { $_.Name } }, Count -AutoSize | Out-Host
$soonest = @($sorted | Where-Object { $_.Status -in 'OutOfSupport', 'EndingSoon' } | Select-Object -First 10)
if ($soonest.Count) {
  Write-Host 'Soonest to lose support:'
  $soonest | Format-Table DeviceName, Release, Edition, LastSupportedDay, DaysLeft, Status -AutoSize | Out-Host
}
Write-Host "CSV: $OutputPath"

$needAction = @($rows | Where-Object { $_.Status -in 'OutOfSupport', 'EndingSoon' }).Count
Write-Log "Done. $($rows.Count) Windows devices, $needAction need action"
if ($needAction) { exit 1 } else { exit 0 }
