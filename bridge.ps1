# =====================================================================
# Prop Trader Edge OBS Overlay - Companion / HTTP bridge (PowerShell edition)
# ---------------------------------------------------------------------
# Same job as bridge.js but needs NOTHING installed - PowerShell ships
# with every Windows PC. Run it if you don't have Node.js:
#   Right-click -> Run with PowerShell,  or use "Start Bridge.bat"
#
# Companion (Generic HTTP module), method GET/POST/PUT, e.g.:
#   http://localhost:8787/toggle/subscribe
#   http://localhost:8787/show/topbar     http://localhost:8787/hide/topbar
#   http://localhost:8787/toggle/ci:<itemId>   (added canvas text/image)
#   http://localhost:8787/toggle/subscribe/true (force show - explicit value)
#   http://localhost:8787/toggle/subscribe/false (force hide)
#   http://localhost:8787/preset/Poker%20Night (load a preset AND push it live)
#   http://localhost:8787/update               (the control page's Update button)
# Open http://localhost:8787/ in a browser for the clickable list.
# =====================================================================
param([int]$Port = 8787)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
try { $listener.Start() } catch {
  Write-Host "Could not listen on port $Port ($($_.Exception.Message)). Is another bridge already running?" -ForegroundColor Red
  Read-Host "Press Enter to close"; exit 1
}
$sse    = New-Object System.Collections.ArrayList   # @{c=TcpClient; s=NetworkStream}
$states = @{ topbar=$true; contentFrame=$true; cameraFrame=$true; ticker=$true; marketbar=$true; affiliate=$true; chat=$true;
             startingSoon=$false; socialSidebar=$false; speaker=$false; joinCommunity=$false;
             liveQA=$false; nextLive=$false; subscribe=$false; applyProgram=$false }
$names  = @{ topbar="Top Bar (Sponsor Promo)"; contentFrame="Content Frame"; cameraFrame="Camera Frame"; ticker="Stock Ticker"; marketbar="Market Update Bar";
             affiliate="Affiliate Card"; chat="Chat Box"; startingSoon="Starting Soon Screen";
             socialSidebar="Social Media Sidebar"; speaker="Speaker Lower Third";
             joinCommunity="Join The Community"; liveQA="Live Q&A"; nextLive="Next Live Session";
             subscribe="Subscribe"; applyProgram="Apply For The Program" }
$mime   = @{ ".html"="text/html; charset=utf-8"; ".js"="text/javascript; charset=utf-8";
             ".json"="application/json; charset=utf-8"; ".css"="text/css; charset=utf-8";
             ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg"; ".gif"="image/gif";
             ".svg"="image/svg+xml"; ".ico"="image/x-icon" }

function T([string]$s){ [System.Text.Encoding]::UTF8.GetBytes($s) }
function SendB($stream,[byte[]]$b){ try { $stream.Write($b,0,$b.Length) } catch {} }
function Respond($client,$stream,[int]$code,[string]$ctype,[byte[]]$body){
  $hdr = "HTTP/1.1 $code OK`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET,POST,PUT,PATCH,DELETE,OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
  SendB $stream (T $hdr); SendB $stream $body
  try { $stream.Close(); $client.Close() } catch {}
}
function BroadcastRaw([string]$json){
  $line = T ("event: cmd`ndata: " + $json + "`n`n")
  $dead = @()
  foreach($cl in $sse){ try { $cl.s.Write($line,0,$line.Length) } catch { $dead += $cl } }
  foreach($d in $dead){ [void]$sse.Remove($d); try { $d.c.Close() } catch {} }
}
function Broadcast($key,$vis){
  BroadcastRaw ('{"key":"' + $key + '","visible":' + $vis.ToString().ToLower() + '}')
  $flag = ""
  if($sse.Count -eq 0){ $flag = "  ! no pages connected - is the overlay open?" }
  Write-Host ("[{0}] {1} -> {2}  ({3} page(s) notified){4}" -f (Get-Date -Format HH:mm:ss), $key, $(if($vis){"SHOWN"}else{"HIDDEN"}), $sse.Count, $flag)
}
function HelpHtml(){
  $base = "http://localhost:$Port"
  $rows = ($names.Keys | Sort-Object | ForEach-Object {
    "<tr><td><b>$($names[$_])</b></td><td><code>$_</code></td><td><a href='$base/toggle/$_'>toggle</a> &middot; <a href='$base/toggle/$_/true'>true</a> &middot; <a href='$base/toggle/$_/false'>false</a></td></tr>" }) -join ""
  return "<!doctype html><meta charset='utf-8'><title>Prop Trader Edge - HTTP bridge</title><style>body{background:#050f1d;color:#dfe9f7;font:15px/1.5 'Segoe UI',Arial,sans-serif;padding:32px;max-width:820px;margin:auto}h1{color:#f5892b}code{background:#0e2039;padding:2px 6px;border-radius:5px;color:#ffc38a}a{color:#f5892b}table{width:100%;border-collapse:collapse;margin-top:14px}td{padding:8px 6px;border-bottom:1px solid #1e3555}.big{background:#0e2039;border:1px solid #1e3555;border-radius:10px;padding:14px 18px;margin:14px 0}</style><h1>Prop Trader Edge - Companion / HTTP bridge (PowerShell)</h1><div class='big'>Bridge is <b style='color:#f5892b'>running</b> on <code>$base</code>. Point OBS &amp; your browser at <a href='$base/overlay.html'>$base/overlay.html</a> and <a href='$base/control.html'>$base/control.html</a>.</div><div class='big'><b style='color:#f5892b'>Whole-look switches</b><br><code>$base/preset/&lt;preset name&gt;</code> - load a saved preset and push it live in one press (spaces become <code>%20</code>).<br><code>$base/update</code> - the control page's Update button.</div><p>In Companion (Generic HTTP) use GET/POST/PUT with any URL below. For an added canvas item use <code>/toggle/ci:&lt;itemId&gt;</code>. Note: the PowerShell bridge relays commands only - for whole-state sync into OBS run the Node bridge (bridge.js).</p><table><tr><th align='left'>Banner</th><th align='left'>key</th><th align='left'>endpoints</th></tr>$rows</table>"
}

Write-Host ""
Write-Host "  Prop Trader Edge HTTP bridge (PowerShell) running:" -ForegroundColor Green
Write-Host "    Local:   http://localhost:$Port/"
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | ForEach-Object {
  Write-Host "    Network: http://$($_.IPAddress):$Port/   (use this IP in Companion on another machine)" }
Write-Host ""
Write-Host "  OBS Browser Source URL:  http://localhost:$Port/overlay.html"
Write-Host "  Control page / dock:     http://localhost:$Port/control.html"
Write-Host ""
Write-Host "  Companion example (Generic HTTP, GET/POST/PUT):"
Write-Host "    http://localhost:$Port/toggle/subscribe          (flip)"
Write-Host "    http://localhost:$Port/toggle/subscribe/true     (force show)"
Write-Host "    http://localhost:$Port/toggle/subscribe/false    (force hide)"
Write-Host "    http://localhost:$Port/preset/Default"
Write-Host "    http://localhost:$Port/update"
Write-Host ""

$lastPing = Get-Date
while($true){
  if(((Get-Date) - $lastPing).TotalSeconds -gt 20){
    $lastPing = Get-Date
    $ping = T ": ping`n`n"; $dead = @()
    foreach($cl in $sse){ try { $cl.s.Write($ping,0,$ping.Length) } catch { $dead += $cl } }
    foreach($d in $dead){ [void]$sse.Remove($d); try { $d.c.Close() } catch {} }
  }
  if(-not $listener.Pending()){ Start-Sleep -Milliseconds 40; continue }

  $client = $listener.AcceptTcpClient()
  $stream = $client.GetStream()
  $stream.ReadTimeout = 3000
  $buf = New-Object byte[] 16384
  $data = ""
  try {
    do {
      $n = $stream.Read($buf,0,$buf.Length)
      if($n -le 0){ break }
      $data += [System.Text.Encoding]::UTF8.GetString($buf,0,$n)
    } while(($data -notmatch "`r`n`r`n") -and ($data.Length -lt 65536))
  } catch {}
  if($data -eq ""){ try { $client.Close() } catch {}; continue }

  $reqLine = ($data -split "`r`n")[0]
  $parts = $reqLine -split " "
  if($parts.Count -lt 2){ try { $client.Close() } catch {}; continue }
  $method = $parts[0]
  $rawPath = $parts[1]
  $path = [uri]::UnescapeDataString(($rawPath -split "\?")[0])
  $qparts = $rawPath -split "\?"
  $query = ""
  if($qparts.Count -gt 1){ $query = [uri]::UnescapeDataString($qparts[1]) }

  if($method -eq "OPTIONS"){ Respond $client $stream 204 "text/plain" (T ""); continue }

  if($path -eq "/events"){
    $hdr = "HTTP/1.1 200 OK`r`nAccess-Control-Allow-Origin: *`r`nContent-Type: text/event-stream`r`nCache-Control: no-cache`r`nConnection: keep-alive`r`n`r`n"
    SendB $stream (T $hdr)
    SendB $stream (T "retry: 2000`n`n")
    [void]$sse.Add(@{ c = $client; s = $stream })
    Write-Host ("[{0}] page connected ({1} total)" -f (Get-Date -Format HH:mm:ss), $sse.Count)
    continue
  }
  if($path -eq "/ping" -or $path -eq "/status"){
    Respond $client $stream 200 "application/json" (T ('{"ok":true,"port":' + $Port + ',"clients":' + $sse.Count + '}'))
    continue
  }
  if($path -eq "/report"){
    try {
      $idx = $data.IndexOf("`r`n`r`n")
      if($idx -ge 0){
        $body = $data.Substring($idx + 4)
        if($body.Trim().Length -gt 1){
          $m = $body | ConvertFrom-Json
          $m.PSObject.Properties | ForEach-Object { $states[$_.Name] = [bool]$_.Value }
        }
      }
    } catch {}
    Respond $client $stream 200 "application/json" (T '{"ok":true}')
    continue
  }
  if($path -match "^/(toggle|show|hide|set)/(.+)$"){
    $mode = $Matches[1]; $key = $Matches[2]; $forced = $null
    # explicit value:  /toggle/<key>/true  |  /toggle/<key>?value=false
    if($key -match "^(.*)/(true|false|1|0|on|off|show|hide|yes|no)$"){ $key = $Matches[1]; $forced = $Matches[2] }
    elseif($query -match "(?:^|&)(?:value|state|visible)=([^&]+)"){ $forced = $Matches[1] }
    if($forced -ne $null){ $vis = @("true","1","on","show","yes") -contains $forced.ToLower() }
    elseif($mode -eq "show"){ $vis = $true }
    elseif($mode -eq "hide"){ $vis = $false }
    else { $cur = $true; if($states.ContainsKey($key)){ $cur = [bool]$states[$key] }; $vis = -not $cur }
    $states[$key] = $vis
    Broadcast $key $vis
    Respond $client $stream 200 "application/json" (T ('{"ok":true,"action":"' + $mode + '","key":"' + $key + '","visible":' + $vis.ToString().ToLower() + '}'))
    continue
  }
  if($path -match "^/preset/(.+)$"){
    $pname = $Matches[1] -replace '"','\"'
    BroadcastRaw ('{"cmd":"preset","name":"' + $pname + '"}')
    Write-Host ("[{0}] PRESET '{1}' -> loaded + published  ({2} page(s) notified)" -f (Get-Date -Format HH:mm:ss), $pname, $sse.Count)
    Respond $client $stream 200 "application/json" (T ('{"ok":true,"action":"preset","name":"' + $pname + '"}'))
    continue
  }
  if($path -eq "/update" -or $path -eq "/publish"){
    BroadcastRaw '{"cmd":"publish"}'
    Write-Host ("[{0}] UPDATE -> draft published  ({1} page(s) notified)" -f (Get-Date -Format HH:mm:ss), $sse.Count)
    Respond $client $stream 200 "application/json" (T '{"ok":true,"action":"publish"}')
    continue
  }
  if($path -eq "/"){ Respond $client $stream 200 "text/html; charset=utf-8" (T (HelpHtml)); continue }

  # static files
  $safe = $path -replace "/","\"
  $file = Join-Path $root $safe.TrimStart("\")
  if((Test-Path $file -PathType Leaf) -and ((Resolve-Path $file).Path.StartsWith($root))){
    $ext = [System.IO.Path]::GetExtension($file).ToLower()
    $ct = "application/octet-stream"; if($mime.ContainsKey($ext)){ $ct = $mime[$ext] }
    Respond $client $stream 200 $ct ([System.IO.File]::ReadAllBytes($file))
  } else {
    Respond $client $stream 404 "text/plain" (T "not found")
  }
}
