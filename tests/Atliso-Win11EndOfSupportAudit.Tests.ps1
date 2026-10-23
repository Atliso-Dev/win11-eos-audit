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

  It 'LTSC on build 26100 is never flagged' {
    $r = Invoke-Audit @((Device 'ltsc' '10.0.26100.1' 125 'EnterpriseS'))
    $r.Rows['ltsc'].Status | Should -Be 'LTSC'
    $r.Rows['ltsc'].LastSupportedDay | Should -BeNullOrEmpty
    $r.Exit | Should -Be 0
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
      $entries.Count | Should -BeGreaterOrEqual 6
      foreach ($e in $entries) { [datetime]$e.Groups[4].Value | Should -BeGreaterThan ([datetime]$e.Groups[3].Value) }
    }
  }
}
