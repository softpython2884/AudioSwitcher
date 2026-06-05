<#
  audio-switch-daemon.ps1  -  INSTANT mode.
  Stays resident with WPF + svcl warmed up. Polls a tiny ".trigger" file
  (written by trigger-1.cmd / trigger-2.cmd) and switches immediately, so a
  key press doesn't pay PowerShell/WPF startup. Run via install-daemon.cmd.
#>
. (Join-Path $PSScriptRoot 'audio-switch.core.ps1')
if (-not (Test-SVCL)) { exit 1 }

$TriggerFile = Join-Path $PSScriptRoot '.trigger'
Write-ASLog "daemon: starting"

$win = New-Overlay
$sb  = Get-Sb $win
$win.Add_Loaded({ Set-ClickThrough $win })

# Prime the window handle once (invisible: everything starts off-screen/hidden).
$startCfg = Get-ASConfig
$cInit = if ($startCfg.ui.corner) { [string]$startCfg.ui.corner } else { 'TopRight' }
Set-OverlayContent  $win 'Audio' 'monitor' '' $script:AmdPalette
Set-OverlayPosition $win $cInit 28 40
$win.Show(); $win.Hide()

$script:lastWrite = [datetime]::MinValue
$hideTimer = New-Object System.Windows.Threading.DispatcherTimer
$hideTimer.Add_Tick({ $hideTimer.Stop(); $win.Hide() })

$poll = New-Object System.Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromMilliseconds(40)
$poll.Add_Tick({
    if (-not (Test-Path $TriggerFile)) { return }
    try { $wt = (Get-Item $TriggerFile).LastWriteTimeUtc } catch { return }
    if ($wt -le $script:lastWrite) { return }
    $script:lastWrite = $wt

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $key = $null
    for ($i = 0; $i -lt 6 -and -not $key; $i++) {
        try { $key = (Get-Content -Raw -Path $TriggerFile).Trim() } catch { Start-Sleep -Milliseconds 4 }
    }
    if ($key -notin @('1','2')) { return }

    $cfg = Get-ASConfig
    $slot = $cfg.slots.$key
    if (-not $slot) { return }

    $dev = Invoke-Switch $slot $sw
    if (-not $dev) { return }
    $devName = if ($dev.Name) { $dev.Name } else { $dev.'Device Name' }

    $corner  = if ($cfg.ui.corner)            { [string]$cfg.ui.corner } else { 'TopRight' }
    $gapX    = if ($cfg.ui.gapX -ne $null)    { [int]$cfg.ui.gapX }      else { 28 }
    $gapY    = if ($cfg.ui.gapY -ne $null)    { [int]$cfg.ui.gapY }      else { 40 }
    $closeMs = if ($cfg.ui.closeMs -ne $null) { [int]$cfg.ui.closeMs }   else { 2550 }
    $palette = Get-AccentPalette ([bool]$cfg.ui.dynamicColors) $corner

    Set-OverlayContent  $win $slot.label $slot.icon $devName $palette
    Set-OverlayPosition $win $corner $gapX $gapY
    $win.Show(); $win.Topmost = $false; $win.Topmost = $true
    $sb.Begin($win, $true)
    $hideTimer.Stop(); $hideTimer.Interval = [TimeSpan]::FromMilliseconds($closeMs); $hideTimer.Start()
    Write-ASLog ("overlay shown (slot $key)") $sw
})
$poll.Start()
Write-ASLog "daemon: ready (polling .trigger)"
[System.Windows.Threading.Dispatcher]::Run()
