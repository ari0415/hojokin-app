# 農林水産省「補助事業参加者の公募」(https://www.maff.go.jp/j/supply/hozyo/index.html) を data/maff.json に取り込む。
# 公共データ利用規約(PDL1.0)で再利用可（出典表示が必要。アプリのフッター・詳細画面に表示している）。
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fetch_maff.ps1
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http
$enc = [System.Text.UTF8Encoding]::new($false)
$listUrl = "https://www.maff.go.jp/j/supply/hozyo/index.html"
$outPath = "$Root\data\maff.json"

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(30)
$client.DefaultRequestHeaders.UserAgent.ParseAdd("hojokin-compass/1.0")
function Get-Html($url) { [System.Text.Encoding]::UTF8.GetString($client.GetByteArrayAsync($url).Result) }
function Html-ToText($html) {
  $t = [regex]::Replace($html, '<br\s*/?>|</p>|</li>|</div>|</h3>|</tr>', ' ')
  $t = [regex]::Replace($t, '<[^>]+>', '')
  return (([System.Net.WebUtility]::HtmlDecode($t)) -replace '\s+', ' ').Trim()
}
# "令和8年10月13日" → "2026-10-13"
function JDate($s) {
  if ($s -match '令和\s*(\d+|元)\s*年\s*(\d+)\s*月\s*(\d+)\s*日') {
    $y = if ($matches[1] -eq '元') { 1 } else { [int]$matches[1] }
    return '{0:D4}-{1:D2}-{2:D2}' -f (2018 + $y), [int]$matches[2], [int]$matches[3]
  }
  return $null
}

$list = Get-Html $listUrl
# Only the first table (公告日・参加締切日・件名) lists calls; the later 公募結果 table holds finished ones.
$rows = [regex]::Matches($list, '<tr[^>]*>\s*<td[^>]*>([\s\S]*?)</td>\s*<td[^>]*>([\s\S]*?)</td>\s*<td[^>]*>([\s\S]*?)</td>\s*</tr>')
$calls = foreach ($r in $rows) {
  $pub = JDate (Html-ToText $r.Groups[1].Value)
  $end = JDate (Html-ToText $r.Groups[2].Value)
  $a = [regex]::Match($r.Groups[3].Value, '<a href="([^"#][^"]*)"[^>]*>([\s\S]*?)</a>')
  if (-not $pub -or -not $end -or -not $a.Success) { continue }
  [pscustomobject]@{
    url   = ([Uri]::new([Uri]$listUrl, [System.Net.WebUtility]::HtmlDecode($a.Groups[1].Value))).AbsoluteUri
    title = Html-ToText $a.Groups[2].Value
    pub   = $pub
    end   = $end
  }
}
Write-Output "calls on the list: $(@($calls).Count)"

$existing = @{}
if (Test-Path $outPath) { ([System.IO.File]::ReadAllText($outPath, $enc) | ConvertFrom-Json) | ForEach-Object { $existing[$_.id] = $_ } }

foreach ($c in $calls) {
  $txt = ""; $start = $c.pub; $org = "農林水産省"
  try {
    $h = Get-Html $c.url
    $m = [regex]::Match($h, 'id="main_content">([\s\S]*?)(<div class="adobe_reader"|<!-- /\.content -->)')
    if ($m.Success) {
      $body = [regex]::Replace($m.Groups[1].Value, '<h1[\s\S]*?</h1>', '')
      $split = $body -split '以上、公示します', 2
      $body = $split[0]
      # The notice is signed by the responsible 局長 (e.g. "農林水産省農産局長"); used when no 担当課 is given.
      $signer = if ($split.Count -gt 1) { [regex]::Match((Html-ToText $split[1]), '(農林水産省\S{0,20}?(局|部|官房)|林野庁|水産庁)(長官|長)') } else { $null }
      $parts = [regex]::Split($body, '<h2[^>]*>')
      $lead = (Html-ToText $parts[0]) -replace '\s*記\s*$', ''
      $secs = for ($i = 1; $i -lt $parts.Count; $i++) {
        $hb = $parts[$i] -split '</h2>', 2
        $head = (Html-ToText $hb[0]) -replace '^[0-9０-９]+[\s　.．、]*', ''
        $text = if ($hb.Count -gt 1) { Html-ToText $hb[1] } else { "" }
        if ($text) { "■$head $text" }
      }
      $txt = (@($lead) + @($secs) | Where-Object { $_ }) -join ' '
      $period = [regex]::Match($txt, '■公募期間 ([^■]*)')
      if ($period.Success -and (JDate $period.Groups[1].Value)) { $start = JDate $period.Groups[1].Value }
      $contact = [regex]::Match($txt, '■[^■ ]*問(い)?合(わ)?せ[^■ ]* ([^■]*)')
      $dept = '(農林水産省|林野庁|水産庁|大臣官房|[^\s　]{1,4}農政局|農産局|畜産局|経営局|農村振興局|輸出・国際局|消費・安全局|新事業・食品産業部)[^\s　、。（(〒:：]*(課|室|班|係|ユニット|センター|事務所)'
      $orgM = [regex]::Match($(if ($contact.Success) { $contact.Groups[3].Value } else { "" }), $dept)
      $org = if ($orgM.Success) { $orgM.Value }
             elseif ($signer -and $signer.Success) { $signer.Groups[1].Value }
             else { "農林水産省" }
    }
  } catch { Write-Output "  detail failed: $($c.url)" }
  $existing[$c.url] = [ordered]@{
    id = $c.url; t = $c.title; o = $org; a = @("全国"); e = 0; m = $null
    s = $start; d = $c.end; p = $c.pub; src = "maffkobo"; u = $c.url; txt = $txt
  }
  Start-Sleep -Milliseconds 300
}

$all = @($existing.Values)
[System.IO.File]::WriteAllText($outPath, ($all | ConvertTo-Json -Depth 5 -Compress), $enc)
Write-Output "saved $($all.Count) calls to data\maff.json"
