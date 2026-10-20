# Assemble index.html from app_template.html and the data files (no network access).
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 [-DataDate 2026-10-20]
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$DataDate = (Get-Date -Format "yyyy-MM-dd")
)
$ErrorActionPreference = "Stop"
$enc = [System.Text.UTF8Encoding]::new($false)
function Read-Text($rel, $default) {
  $p = Join-Path $Root $rel
  if (Test-Path $p) { return [System.IO.File]::ReadAllText($p, $enc) } else { return $default }
}

$combined = @()
foreach ($f in @("data\jgrants_national.json", "data\local_gov.json", "data\curated.json")) {
  $combined += (Read-Text $f "[]") | ConvertFrom-Json
}
$dataJson = $combined | ConvertTo-Json -Depth 6 -Compress
[System.IO.File]::WriteAllText((Join-Path $Root "dataset.json"), $dataJson, $enc)

$overrides = (Read-Text "data\overrides.json" "{}") | ConvertFrom-Json | ConvertTo-Json -Depth 6 -Compress
$html = (Read-Text "app_template.html" "").
  Replace('/*__DATA__*/', $dataJson).
  Replace('/*__OVERRIDES__*/', $overrides).
  Replace('/*__BUILD_INFO__*/', "{`"date`":`"$DataDate`"}").
  Replace('/*__JDETAIL__*/', (Read-Text "data\jgrants_detail.json" "{}")).
  Replace('/*__LDETAIL__*/', (Read-Text "data\local_detail.json" "{}"))

$left = [regex]::Matches($html, '/\*__[A-Z_]+__\*/').Count
if ($left -gt 0) { throw "unreplaced placeholders: $left" }
[System.IO.File]::WriteAllText((Join-Path $Root "index.html"), $html, $enc)
Write-Output ("records: {0}, index.html: {1:N1} MB" -f $combined.Count, ((Get-Item (Join-Path $Root "index.html")).Length / 1MB))
