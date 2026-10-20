# Fetch per-subsidy detail (本文・対象業種・利用目的・掲載日・元ページURL) into cache files.
# Resumable: already-cached ids are skipped. Run from Windows PowerShell 5.1:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fetch_details.ps1
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$Today = (Get-Date -Format "yyyy-MM-dd"),
  [string]$NationalSince = ((Get-Date).AddMonths(-12).ToString("yyyy-MM-dd")),
  [int]$Concurrency = 4,
  [int]$LocalRecheckDays = 14
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http
$enc = [System.Text.UTF8Encoding]::new($false)

function Read-Json($path) {
  if (-not (Test-Path $path)) { return $null }
  return [System.IO.File]::ReadAllText($path, $enc) | ConvertFrom-Json
}
function To-Hashtable($obj) {
  $h = @{}
  if ($obj) { $obj.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }
  return $h
}
function Save-Json($path, $obj) {
  [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 6 -Compress), $enc)
}
function Html-ToText($html) {
  if (-not $html) { return "" }
  $t = [regex]::Replace($html, '<br\s*/?>|</p>|</li>|</div>', ' ')
  $t = [regex]::Replace($t, '<[^>]+>', '')
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  return ($t -replace '\s+', ' ').Trim()
}
function Cap($s, $n) { if ($s.Length -gt $n) { return $s.Substring(0, $n) } return $s }
function Split-List($s) {
  if (-not $s) { return ,@() }
  # Leading comma keeps a one-element result an array (PowerShell unrolls it otherwise).
  return ,@($s -split '\s*/\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Bounded-concurrency GET. Returns @{ url = @{ status; location; body } }.
function Get-Many($client, [string[]]$urls) {
  $out = @{}
  for ($i = 0; $i -lt $urls.Count; $i += $Concurrency) {
    $batch = $urls[$i..([Math]::Min($i + $Concurrency, $urls.Count) - 1)]
    $tasks = @($batch | ForEach-Object { $client.GetAsync($_) })
    try { [System.Threading.Tasks.Task]::WaitAll($tasks) } catch {}
    for ($k = 0; $k -lt $batch.Count; $k++) {
      $t = $tasks[$k]
      if ($t.IsFaulted -or $t.IsCanceled) { $out[$batch[$k]] = @{ status = 0 }; continue }
      $r = $t.Result
      $body = [System.Text.Encoding]::UTF8.GetString($r.Content.ReadAsByteArrayAsync().Result)
      $loc = if ($r.Headers.Location) { $r.Headers.Location.ToString() } else { "" }
      $out[$batch[$k]] = @{ status = [int]$r.StatusCode; location = $loc; body = $body }
    }
    Start-Sleep -Milliseconds 300
  }
  return $out
}

$nat = Read-Json "$Root\data\jgrants_national.json"
$loc = Read-Json "$Root\data\local_gov.json"
$jdPath = "$Root\data\jgrants_detail.json"
$ldPath = "$Root\data\local_detail.json"
$jd = To-Hashtable (Read-Json $jdPath)
$ld = To-Hashtable (Read-Json $ldPath)

# ---- jGrants detail API ----
$jClient = [System.Net.Http.HttpClient]::new()
$jClient.Timeout = [TimeSpan]::FromSeconds(30)
$natTargets = @($nat | Where-Object { (-not $_.d -or $_.d -ge $NationalSince) -and -not $jd.ContainsKey($_.id) })
Write-Output "jGrants detail to fetch: $($natTargets.Count)"
$openIds = @{}
$nat | Where-Object { -not $_.d -or $_.d -ge $Today } | ForEach-Object { $openIds[$_.id] = $true }
for ($i = 0; $i -lt $natTargets.Count; $i += 100) {
  $chunk = $natTargets[$i..([Math]::Min($i + 100, $natTargets.Count) - 1)]
  $urlById = @{}
  $chunk | ForEach-Object { $urlById[$_.id] = "https://api.jgrants-portal.go.jp/exp/v1/public/subsidies/id/$($_.id)" }
  $res = Get-Many $jClient @($urlById.Values)
  foreach ($id in $urlById.Keys) {
    $r = $res[$urlById[$id]]
    if ($r.status -ne 200) { continue }
    $d = ($r.body | ConvertFrom-Json).result[0]
    if (-not $d) { continue }
    $text = (Html-ToText $d.detail) -replace '^■?目的・概要\s*', ''
    $jd[$id] = @{
      ind  = Split-List $d.industry
      pur  = Split-List $d.use_purpose
      rate = $d.subsidy_rate
      txt  = $(if ($openIds.ContainsKey($id)) { Cap $text 1200 } else { "" })
    }
  }
  Save-Json $jdPath $jd
  Write-Output ("  jGrants {0}/{1}" -f [Math]::Min($i + 100, $natTargets.Count), $natTargets.Count)
}

# ---- J-Net21 article pages ----
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$lClient = [System.Net.Http.HttpClient]::new($handler)
$lClient.Timeout = [TimeSpan]::FromSeconds(30)
$lClient.DefaultRequestHeaders.UserAgent.ParseAdd("hojokin-compass/1.0")
$recheckBefore = ([DateTime]$Today).AddDays(-$LocalRecheckDays).ToString("yyyy-MM-dd")
$locTargets = @($loc | Where-Object {
  ($_.d -eq "unknown" -or -not $_.d -or $_.d -ge $Today) -and
  (-not $ld.ContainsKey($_.id) -or (-not $ld[$_.id].removed -and $ld[$_.id].checked -lt $recheckBefore))
})
Write-Output "J-Net21 articles to fetch: $($locTargets.Count)"
for ($i = 0; $i -lt $locTargets.Count; $i += 100) {
  $chunk = $locTargets[$i..([Math]::Min($i + 100, $locTargets.Count) - 1)]
  $urlById = @{}
  $chunk | ForEach-Object { $urlById[$_.id] = ($_.id -replace '/snavi/articles/', '/snavi2/articles/') }
  $res = Get-Many $lClient @($urlById.Values)
  foreach ($id in $urlById.Keys) {
    $r = $res[$urlById[$id]]
    if ($r.status -ge 300 -and $r.status -lt 400) {
      # J-Net21 redirects withdrawn articles back to the headline top page.
      $ld[$id] = @{ removed = $true; checked = $Today }
      continue
    }
    if ($r.status -ne 200) { continue }
    $h = $r.body
    $ind = if ($h -match '<dt class="def-list__ttl">業種</dt>\s*<dd class="def-list__desc">\s*<p class="txt">([^<]*)</p>') { [System.Net.WebUtility]::HtmlDecode($matches[1]).Trim() } else { "" }
    $body = if ($h -match '実施機関からのお知らせ</span></h2>\s*<p class="txt">([\s\S]*?)</p>') { Html-ToText $matches[1] } else { "" }
    $src = if ($h -match '詳細情報を見る</span></h3>\s*<ul class="list">[\s\S]*?<a href="([^"]+)"') { [System.Net.WebUtility]::HtmlDecode($matches[1]) } else { "" }
    $pub = if ($h -match '掲載日：(\d{4})年(\d{1,2})月(\d{1,2})日') { '{0:D4}-{1:D2}-{2:D2}' -f [int]$matches[1], [int]$matches[2], [int]$matches[3] } else { "" }
    $ld[$id] = @{
      removed = $false
      checked = $Today
      ind     = (Split-List $(if ($ind -and $ind -ne "指定無し") { $ind -replace '[、,]', ' / ' } else { "" }))
      txt     = Cap ($body -replace '申込方法ほか詳細情報は、「詳細情報を見る」からご確認ください。', '').Trim() 600
      srcUrl  = $src
      p       = $pub
    }
  }
  Save-Json $ldPath $ld
  Write-Output ("  J-Net21 {0}/{1}" -f [Math]::Min($i + 100, $locTargets.Count), $locTargets.Count)
}
Write-Output "done. jGrants cached: $($jd.Count), J-Net21 cached: $($ld.Count)"
