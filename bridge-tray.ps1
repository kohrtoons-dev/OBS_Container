# =====================================================================
# Prop Trader Edge Bridge - system tray host
# Runs the HTTP bridge in the BACKGROUND (no console window) with a
# green-dot icon in the system tray.
#   Launch via "Start Bridge Tray.vbs" (fully hidden), or:
#   powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File bridge-tray.ps1
# Tray menu: open control page / help, start with Windows, restart, exit.
# =====================================================================
param([int]$Port = 8787)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$dir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$base = "http://localhost:$Port"

# Already running? Don't start a second copy.
try {
  $null = (New-Object Net.WebClient).DownloadString("$base/ping")
  [System.Windows.Forms.MessageBox]::Show("The bridge is already running on port $Port.", "Prop Trader Edge Bridge") | Out-Null
  exit
} catch {}

$script:proc = $null
function Start-Bridge {
  if (Get-Command node -ErrorAction SilentlyContinue) {
    $script:proc = Start-Process node -ArgumentList "`"$dir\bridge.js`" $Port" -WindowStyle Hidden -PassThru -WorkingDirectory $dir
  } else {
    $script:proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\bridge.ps1`" $Port" -WindowStyle Hidden -PassThru -WorkingDirectory $dir
  }
}
Start-Bridge

function New-DotIcon([System.Drawing.Color]$col) {
  $bmp = New-Object System.Drawing.Bitmap 16, 16
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = "AntiAlias"
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $col), 2, 2, 12, 12)
  $g.Dispose()
  return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$iconGreen = New-DotIcon ([System.Drawing.Color]::FromArgb(30, 201, 107))
$iconRed   = New-DotIcon ([System.Drawing.Color]::FromArgb(255, 90, 110))

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = $iconGreen
$ni.Text = "Prop Trader Edge Bridge - starting..."
$ni.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add("Open control page", $null, { Start-Process "$base/control.html" })
[void]$menu.Items.Add("Open bridge help / endpoints", $null, { Start-Process "$base/" })
[void]$menu.Items.Add("-")
[void]$menu.Items.Add("Start with Windows", $null, {
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut([IO.Path]::Combine($ws.SpecialFolders("Startup"), "Prop Trader Edge Bridge.lnk"))
  $lnk.TargetPath = "wscript.exe"
  $lnk.Arguments = "`"$dir\Start Bridge Tray.vbs`""
  $lnk.WorkingDirectory = $dir
  $lnk.Save()
  $ni.ShowBalloonTip(3000, "Prop Trader Edge Bridge", "Will now start automatically with Windows.", [System.Windows.Forms.ToolTipIcon]::Info)
})
[void]$menu.Items.Add("Restart bridge", $null, {
  try { if ($script:proc -and !$script:proc.HasExited) { $script:proc.Kill() } } catch {}
  Start-Sleep -Milliseconds 400
  Start-Bridge
})
[void]$menu.Items.Add("-")
[void]$menu.Items.Add("Exit (stops the bridge)", $null, {
  try { if ($script:proc -and !$script:proc.HasExited) { $script:proc.Kill() } } catch {}
  $ni.Visible = $false
  [System.Windows.Forms.Application]::Exit()
})
$ni.ContextMenuStrip = $menu
$ni.add_DoubleClick({ Start-Process "$base/" })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 8000
$timer.add_Tick({
  try {
    $j = (New-Object Net.WebClient).DownloadString("$base/ping") | ConvertFrom-Json
    $ni.Icon = $iconGreen
    $ni.Text = "Prop Trader Edge Bridge - port $Port, $($j.clients) page(s)"
  } catch {
    $ni.Icon = $iconRed
    $ni.Text = "Prop Trader Edge Bridge - NOT responding"
  }
})
$timer.Start()
[System.Windows.Forms.Application]::Run()
