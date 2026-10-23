# Changelog

Every release is on the [releases page](https://github.com/Atliso-Dev/win11-eos-audit/releases) with its zip, and on [atliso.com](https://atliso.com/tools) under Version history.

## 1.1.0 - unreleased

- LTSC devices now get their real last day of updates instead of being skipped. Windows 10 Enterprise LTSC 2021 ends on 12 January 2027, so those devices are flagged as ending soon from mid-November 2026. IoT Enterprise LTSC (SKU 191) gets its longer date (2032 for LTSC 2021, 2034 for LTSC 2024). LTSC 2019 runs to 9 January 2029; LTSB 2016 ended on 13 October 2026.
- Adds Windows 11 26H1 (build 28000), the release for new devices: Home and Pro until 14 March 2028, Enterprise and Education until 13 March 2029. These devices showed as Unknown before.
- Dates from Microsoft's Windows release information pages, checked 23 October 2026.

## 1.0.2 - 2026-10-19

Adds PowerShell Gallery metadata (PSScriptInfo) so the script can be installed with `Install-Script Atliso-Win11EndOfSupportAudit`. No change to what the script does.

## 1.0.1 - 2026-10-13

Enterprise Evaluation (SKU 72, 84) is now on the Enterprise track and LTSC Evaluation (129, 130) is never flagged. Found on a real Windows 11 Enterprise Evaluation lab device. When Intune reports a SKU number the script doesn't list, it falls back to the edition name, and only says the edition was not reported when it really wasn't.

## 1.0.0 - 2026-10-12

Initial public release. MIT licensed. Download the zip below or clone the repo. See README for usage and the linked Atliso guide.

