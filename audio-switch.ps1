<#
  audio-switch.ps1  -  one-shot switch + overlay.
  Usage: powershell -ExecutionPolicy Bypass -File audio-switch.ps1 [1|2|list]
  Needs audio-switch.core.ps1 and svcl.exe next to it (run setup.cmd once).
#>
param([Parameter(Position = 0)][string]$Cible)

. (Join-Path $PSScriptRoot 'audio-switch.core.ps1')
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if (-not (Test-SVCL)) { exit 1 }
$cfg = Get-ASConfig

$norm = ($Cible -replace '^[-/]+', '').Trim().ToLower()
switch -Regex ($norm) {
    '^(1|ecran|écran|screen|moniteur|monitor)$'     { $key = '1';    break }
    '^(2|casque|headset|headphones?|hp|speakers?)$' { $key = '2';    break }
    '^(list|liste|l)$'                              { $key = 'list'; break }
    default                                         { $key = 'help'; break }
}

if ($key -eq 'help') {
    Write-Host "Usage: audio-switch.ps1 [1|2|list]" -ForegroundColor Cyan
    Write-Host "  1     -> $($cfg.slots.'1'.label)"
    Write-Host "  2     -> $($cfg.slots.'2'.label)"
    Write-Host "  list  -> show detected devices. Run setup.cmd to configure."
    exit 0
}
if ($key -eq 'list') {
    $items = Get-AudioItems
    Write-Host "`n--- RENDER devices (outputs) ---`n" -ForegroundColor Cyan
    $items | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' } |
        Select-Object Name, @{n='Default';e={$_.Default}}, @{n='ID';e={$_.'Command-Line Friendly ID'}} | Format-Table -AutoSize -Wrap
    Write-Host "`n--- Active applications (outputs) ---`n" -ForegroundColor Cyan
    $items | Where-Object { $_.Type -eq 'Application' -and $_.Direction -eq 'Render' } |
        Select-Object Name, @{n='Device';e={$_.'Device Name'}}, @{n='PID';e={$_.'Process ID'}} | Format-Table -AutoSize -Wrap
    exit 0
}

$slot = $cfg.slots.$key
if (-not $slot) { Write-Host "Slot '$key' missing in config." -ForegroundColor Red; exit 1 }

# ----- ACTION FIRST -----
$dev = Invoke-Switch $slot $sw
if (-not $dev) { Write-Host "ERROR: no output device matched slot $key. Run setup.cmd." -ForegroundColor Red; exit 1 }
$devName = if ($dev.Name) { $dev.Name } else { $dev.'Device Name' }

# ----- OVERLAY -----
$corner  = if ($cfg.ui.corner)            { [string]$cfg.ui.corner }   else { 'TopRight' }
$gapX    = if ($cfg.ui.gapX -ne $null)    { [int]$cfg.ui.gapX }        else { 28 }
$gapY    = if ($cfg.ui.gapY -ne $null)    { [int]$cfg.ui.gapY }        else { 40 }
$closeMs = if ($cfg.ui.closeMs -ne $null) { [int]$cfg.ui.closeMs }     else { 2550 }
$dyn     = [bool]$cfg.ui.dynamicColors

$palette = Get-AccentPalette $dyn $corner
$win = New-Overlay
Set-OverlayContent  $win $slot.label $slot.icon $devName $palette
Set-OverlayPosition $win $corner $gapX $gapY
$sb = Get-Sb $win
$win.Add_Loaded({ Set-ClickThrough $win; $sb.Begin($win, $true) })

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds($closeMs)
$timer.Add_Tick({ $timer.Stop(); $win.Close() })
$timer.Start()
try { [void]$win.ShowDialog() } catch { Write-ASLog "ShowDialog: $($_.Exception.Message)" }
