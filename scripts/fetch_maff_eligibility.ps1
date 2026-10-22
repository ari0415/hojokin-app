# 農林水産省の各公募の公募要領(PDF)から「応募者の要件」部分を抜き出し、data/maff_eligibility.json にキャッシュする。
# 取得済みはスキップ（途中再開可）。PDFはWindows標準のPDF描画とOCR(日本語)で読む（テキスト層が壊れたPDFも読める）。
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fetch_maff_eligibility.ps1 -PdfDir <作業用フォルダ>
param(
  [string]$Root = "",
  [Parameter(Mandatory = $true)][string]$PdfDir,
  [int]$MaxPages = 25,
  [int]$Limit = 0
)
$ErrorActionPreference = "Stop"
# $PSScriptRoot is empty in param defaults of advanced scripts under Windows PowerShell 5.1.
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]

$ext = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
$asTaskOp = ($ext | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskAction = ($ext | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function Await($op, [Type]$type) { $t = $asTaskOp.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
function AwaitAction($op) { $t = $asTaskAction.Invoke($null, @($op)); $t.Wait(-1) | Out-Null }

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]::new("ja"))
if (-not $engine) { throw "Japanese OCR is not available on this PC" }

# OCR the first $MaxPages pages; lines are re-sorted top-to-bottom because the engine's order wanders.
function Read-Pdf($path) {
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
  $doc = Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
  $out = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt [Math]::Min($MaxPages, $doc.PageCount); $i++) {
    $page = $doc.GetPage($i)
    $stream = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
    $opt = [Windows.Data.Pdf.PdfPageRenderOptions]::new()
    $opt.DestinationWidth = [uint32]([Math]::Min($page.Size.Width * 2.5, $engine.MaxImageDimension))
    AwaitAction ($page.RenderToStreamAsync($stream, $opt))
    $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bmp = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
    # Indexing a WinRT list from PowerShell yields an array, so take the first word via @()[0].
    $lines = @($res.Lines) | Sort-Object { [Math]::Round([double](@($_.Words)[0].BoundingRect.Y) / 8) }, { [double](@($_.Words)[0].BoundingRect.X) }
    foreach ($l in $lines) { [void]$out.Append(($l.Text -replace ' ', '')).Append(' ') }
    $page.Dispose(); $stream.Dispose()
  }
  $doc = $null
  return $out.ToString()
}

$enc = [System.Text.UTF8Encoding]::new($false)
$cachePath = "$Root\data\maff_eligibility.json"
New-Item -ItemType Directory -Force $PdfDir | Out-Null
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(60)
$client.DefaultRequestHeaders.UserAgent.ParseAdd("hojokin-compass/1.0")

$cache = @{}
if (Test-Path $cachePath) { ([System.IO.File]::ReadAllText($cachePath, $enc) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
$calls = [System.IO.File]::ReadAllText("$Root\data\maff.json", $enc) | ConvertFrom-Json
# Entries without `who` text failed earlier (or came from the old Word-based run); retry them.
$todo = @($calls | Where-Object { -not ($cache.ContainsKey($_.id) -and $cache[$_.id].who -and $cache[$_.id].ocr) })
if ($Limit) { $todo = @($todo | Select-Object -First $Limit) }
Write-Output "to check: $($todo.Count) of $($calls.Count)"

# Where 公募要領 state who may apply, most specific first. A bare "事業実施主体" also appears in the 総則
# ("事業実施主体の公募については…"), so it only counts as a heading ("第4 事業実施主体") or a definition.
$whoPatterns = @(
  # Skip passing mentions ("応募者の要件、事業期間等" in the 審査 section) and the "応募資格の停止" penalty clause.
  '(応募者の要件|応募の要件|応募者の資格|応募資格|応募できる者|応募できる団体|応募団体の要件|応募主体|申請者の要件|申請できる者|補助事業者の要件|事業実施主体の要件)(?![、,）)を]|の停止)',
  '第[0-9０-９一二三四五六七八九十]+\s*事業実施主体(?!の(公募|選定|審査|責務|変更|義務|遵守))|事業実施主体は[、,]?\s*(次|以下)',
  '補助対象者|対象となる者|補助事業者は[、,]?\s*(次|以下)'
)
function Get-Who($text) {
  # Long enough to reach the end of applicant enumerations; the app shows only the beginning.
  foreach ($p in $whoPatterns) { $m = [regex]::Match($text, "($p)[\s\S]{0,1200}"); if ($m.Success) { return $m.Value.Trim() } }
  return ""
}

$n = 0
foreach ($c in $todo) {
  $n++
  $entry = [ordered]@{ checked = (Get-Date -Format "yyyy-MM-dd"); ocr = $true; pdf = ""; who = "" }
  try {
    $page = [System.Text.Encoding]::UTF8.GetString($client.GetByteArrayAsync($c.u).Result)
    # The document name is either the link text or the text just before the link ("公募要領 (PDF : 738KB)").
    $links = @([regex]::Matches($page, '<a href="([^"]+\.pdf)"[^>]*>([\s\S]{0,300}?)</a>') | Where-Object {
      $before = [regex]::Replace($page.Substring([Math]::Max(0, $_.Index - 160), [Math]::Min(160, $_.Index)), '<[^>]+>', ' ')
      $label = [regex]::Replace($_.Groups[2].Value, '<[^>]+>', ' ')
      ($label -match '公募要領') -or ($label -notmatch '[\p{IsCJKUnifiedIdeographs}\p{IsHiragana}\p{IsKatakana}]{2,}' -and ($before -replace '\s+', '') -match '公募要領[^。]{0,6}$')
    } | Select-Object -First 2)
    $snips = foreach ($l in $links) {
      $url = ([Uri]::new([Uri]$c.u, [System.Net.WebUtility]::HtmlDecode($l.Groups[1].Value))).AbsoluteUri
      $file = Join-Path $PdfDir ([IO.Path]::GetFileName(([Uri]$url).AbsolutePath))
      if (-not (Test-Path $file)) { [IO.File]::WriteAllBytes($file, $client.GetByteArrayAsync($url).Result) }
      $entry.pdf = $url
      # OCR text is kept next to the PDF so the extraction can be re-tuned without re-scanning.
      $txtFile = "$file.txt"
      if (Test-Path $txtFile) { $text = [System.IO.File]::ReadAllText($txtFile, $enc) }
      else { $text = Read-Pdf $file; [System.IO.File]::WriteAllText($txtFile, $text, $enc) }
      Get-Who $text
    }
    $entry.who = (@($snips) | Where-Object { $_ }) -join ' ／ '
    if (-not $links.Count) { $entry.who = "(公募要領のPDFが公募ページに見当たりません)" }
    elseif (-not $entry.who) { $entry.who = "(公募要領に応募者の要件の記載が見つかりません)" }
  } catch { $entry.who = "(取得失敗: $($_.Exception.Message))" }
  $cache[$c.id] = $entry
  [System.IO.File]::WriteAllText($cachePath, ($cache | ConvertTo-Json -Depth 4 -Compress), $enc)
  if ($n % 10 -eq 0) { Write-Output "  $n/$($todo.Count)" }
}
Write-Output "done. cached: $($cache.Count)"
