# Changelog

Every release is on the [releases page](https://github.com/Atliso-Dev/win11-eos-audit/releases) with its zip, and on [atliso.com](https://atliso.com/tools) under Version history.

## 1.0.2 - 2026-10-19

Adds PowerShell Gallery metadata (PSScriptInfo) so the script can be installed with `Install-Script Atliso-Win11EndOfSupportAudit`. No change to what the script does.

## 1.0.1 - 2026-10-13

Enterprise Evaluation (SKU 72, 84) is now on the Enterprise track and LTSC Evaluation (129, 130) is never flagged. Found on a real Windows 11 Enterprise Evaluation lab device. When Intune reports a SKU number the script doesn't list, it falls back to the edition name, and only says the edition was not reported when it really wasn't.

## 1.0.0 - 2026-10-12

Initial public release. MIT licensed. Download the zip below or clone the repo. See README for usage and the linked Atliso guide.

