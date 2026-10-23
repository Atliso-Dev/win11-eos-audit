# Pester 5+. Graph is mocked, so these run anywhere without a tenant or the Graph module:
#   Invoke-Pester ./tests

BeforeAll {
  $script:Script = Join-Path $PSScriptRoot '..\Atliso-Win11EndOfSupportAudit.ps1'

  # Stand-ins so the mocks have something to replace when Microsoft.Graph.Authentication isn't installed.
  if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) { function global:Connect-MgGraph { param($Scopes, $TenantId, [switch]$NoWelcome) } }
  if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) { function global:Invoke-MgGraphRequest { param($Method, $Uri, $OutputType) } }

  function script:Device([string]$Name, [string]$Os, $Sku, [string]$Family = '') {
    [pscustomobject]@{ id = $Name; deviceName = $Name; userPrincipalName = "$Name@contoso.com"; operatingSystem = 'Windows'; osVersion = $Os; skuNumber = $Sku; skuFamily = $Family; lastSyncDateTime = '2026-10-01T00:00:00Z' }
  }

  # Runs the audit against a fake tenant and returns the CSV rows by device name.
  function script:Invoke-Audit([object[]]$Devices, [object[]]$Skus = $null) {
    $env:USERPROFILE  = Join-Path $TestDrive 'home'
    $env:LOCALAPPDATA = Join-Path $TestDrive 'appdata'
    New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE 'Desktop') -Force | Out-Null
    $global:AtlisoDevices = $Devices
    $global:AtlisoSkus = $Skus
    Mock Connect-MgGraph { }
    Mock Invoke-MgGraphRequest {
      if ($Uri -like '*subscribedSkus*') {
        if ($null -eq $global:AtlisoSkus) { throw 'Response status code does not indicate success: 403 (Forbidden).' }
        return [pscustomobject]@{ value = $global:AtlisoSkus }
      }
      [pscustomobject]@{ value = $global:AtlisoDevices }
    }
    $out = & $script:Script *>&1 | Out-String
    $rows = @{}
    foreach ($row in Import-Csv (Join-Path $env:USERPROFILE 'Desktop\Atliso-Win11-EndOfSupport.csv')) { $rows[$row.DeviceName] = $row }
    [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $out; Rows = $rows }
  }
}

Describe 'Atliso-Win11EndOfSupportAudit' {

  It '24H2 is dated by edition: Pro 13 Oct 2026, Enterprise 12 Oct 2027' {
    $r = Invoke-Audit @((Device 'pro' '10.0.26100.4652' 48 'Professional'), (Device 'ent' '10.0.26100.4652' 4 'Enterprise'))
    $r.Rows['pro'].SupportTrack | Should -Be 'HomePro'
    $r.Rows['pro'].LastSupportedDay | Should -Be '2026-10-13'
    $r.Rows['ent'].SupportTrack | Should -Be 'Enterprise'
    $r.Rows['ent'].LastSupportedDay | Should -Be '2027-10-12'
  }

  It 'LTSC 2024 (build 26100) is dated as LTSC, not as 24H2: Enterprise 2029, IoT Enterprise 2034' {
    $r = Invoke-Audit @((Device 'ltsc' '10.0.26100.1' 125 'EnterpriseS'), (Device 'iot' '10.0.26100.1' 191 'IoTEnterpriseS'))
    $r.Rows['ltsc'].Release | Should -Be 'LTSC 2024'
    $r.Rows['ltsc'].LastSupportedDay | Should -Be '2029-10-09'
    $r.Rows['iot'].LastSupportedDay | Should -Be '2034-10-10'
    $r.Rows['ltsc'].SupportTrack | Should -Be 'LTSC'
  }

  It 'Windows 10 LTSC 2021 gets its own end date instead of being skipped' {
    $r = Invoke-Audit @((Device 'w10ltsc' '10.0.19044.7807' 125 'EnterpriseS'), (Device 'w10iot' '10.0.19044.7807' 191 'IoTEnterpriseS'))
    $r.Rows['w10ltsc'].Release | Should -Be 'LTSC 2021'
    $r.Rows['w10ltsc'].LastSupportedDay | Should -Be '2027-01-12'
    $r.Rows['w10ltsc'].Status | Should -BeIn @('Supported', 'EndingSoon', 'OutOfSupport')
    $r.Rows['w10iot'].LastSupportedDay | Should -Be '2032-01-13'
  }

  It 'LTSB 2016 is out of support (ended 13 Oct 2026)' {
    $r = Invoke-Audit @((Device 'ltsb' '10.0.14393.9612' 125 'EnterpriseS'))
    $r.Rows['ltsb'].LastSupportedDay | Should -Be '2026-10-13'
    if ((Get-Date).Date -gt [datetime]'2026-10-13') { $r.Rows['ltsb'].Status | Should -Be 'OutOfSupport'; $r.Exit | Should -Be 1 }
  }

  It 'an LTSC build missing from the table says so instead of guessing' {
    $r = Invoke-Audit @((Device 'odd' '10.0.20348.1' 125 'EnterpriseS'))
    $r.Rows['odd'].Status | Should -Be 'LTSC'
    $r.Rows['odd'].Note | Should -Match 'not in the table'
  }

  It '26H1 (build 28000, new devices only) is dated: Pro 14 Mar 2028, Enterprise 13 Mar 2029' {
    $r = Invoke-Audit @((Device 'pro' '10.0.28000.3231' 48 'Professional'), (Device 'ent' '10.0.28000.3231' 4 'Enterprise'))
    $r.Rows['pro'].Release | Should -Be '26H1'
    $r.Rows['pro'].LastSupportedDay | Should -Be '2028-03-14'
    $r.Rows['ent'].LastSupportedDay | Should -Be '2029-03-13'
  }

  It 'Windows 10 is out of support and sorts first; the run exits 1' {
    $r = Invoke-Audit @((Device 'ent' '10.0.26200.1' 4 'Enterprise'), (Device 'w10' '10.0.19045.5000' 48 'Professional'))
    $r.Rows['w10'].Release | Should -Be 'Windows 10'
    $r.Rows['w10'].Status | Should -Be 'OutOfSupport'
    (Import-Csv (Join-Path $env:USERPROFILE 'Desktop\Atliso-Win11-EndOfSupport.csv'))[0].DeviceName | Should -Be 'w10'
    $r.Exit | Should -Be 1
  }

  It 'Enterprise Evaluation (SKU 72) is on the Enterprise track' {
    (Invoke-Audit @((Device 'eval' '10.0.26100.1' 72))).Rows['eval'].SupportTrack | Should -Be 'Enterprise'
  }

  It 'an unknown SKU falls back to the edition name Intune reports' {
    (Invoke-Audit @((Device 'x' '10.0.26100.1' 9999 'Education'))).Rows['x'].SupportTrack | Should -Be 'Enterprise'
  }

  It 'a build missing from the lifecycle table is Unknown, never given another release''s date' {
    $r = Invoke-Audit @((Device 'future' '10.0.27000.1' 48 'Professional'))
    $r.Rows['future'].Status | Should -Be 'Unknown'
    $r.Rows['future'].Note | Should -Match 'not in the lifecycle table'
  }

  It 'Pro in an Enterprise-licensed tenant gets the subscription activation note' {
    $r = Invoke-Audit @((Device 'pro' '10.0.26200.1' 48 'Professional')) @([pscustomobject]@{ skuPartNumber = 'SPE_E3'; capabilityStatus = 'Enabled' })
    $r.Rows['pro'].Note | Should -Match 'subscription activation'
  }

  It 'without Organization.Read.All the licence check is skipped quietly' {
    $r = Invoke-Audit @((Device 'pro' '10.0.26200.1' 48 'Professional'))
    $r.Rows['pro'].Note | Should -Not -Match 'subscription activation'
  }

  Context 'Lifecycle table' {
    # The table is the part Microsoft changes under us. These fail loudly when it falls behind.
    It 'still has a Home/Pro release in support today' {
      $src = Get-Content $script:Script -Raw
      $dates = [regex]::Matches($src, "Consumer = '(\d{4}-\d{2}-\d{2})'") | ForEach-Object { [datetime]$_.Groups[1].Value }
      ($dates | Measure-Object -Maximum).Maximum | Should -BeGreaterThan (Get-Date)
    }

    It 'every build has a release name and both dates' {
      $src = Get-Content $script:Script -Raw
      $entries = [regex]::Matches($src, "(?m)^\s*(\d{5}) = @\{ Release = '(\d\dH\d)'; Consumer = '(\d{4}-\d{2}-\d{2})'; Enterprise = '(\d{4}-\d{2}-\d{2})' \}")
      $entries.Count | Should -BeGreaterOrEqual 7
      foreach ($e in $entries) { [datetime]$e.Groups[4].Value | Should -BeGreaterThan ([datetime]$e.Groups[3].Value) }
    }
  }
}
