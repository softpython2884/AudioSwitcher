<#
================================================================================
  audio-switch.ps1  -  Switch the default audio output + move running apps to it,
                       then show a fast AMD-style overlay.

  Reads optional "audio-switch.config.json" next to this script (created by
  setup.ps1). Falls back to built-in defaults if missing.

  Usage:
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 1      # slot 1
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 2      # slot 2
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 list   # list devices

  Requires svcl.exe (NirSoft SoundVolumeCommandLine) next to this script.
  Run setup.cmd once to download it and pick your devices.
================================================================================
#>

param(
    [Parameter(Position = 0)]
    [string]$Cible
)

# ============================== CONFIG (paths) =================================
$SVCL    = Join-Path $PSScriptRoot 'svcl.exe'
$CfgPath = Join-Path $PSScriptRoot 'audio-switch.config.json'
$LogFile = Join-Path $PSScriptRoot 'audio-switch.log'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
function Write-Log([string]$m) {
    try { Add-Content -Path $LogFile -Value ("{0}  [t+{1,5}ms]  {2}" -f (Get-Date -Format 'HH:mm:ss'), $sw.ElapsedMilliseconds, $m) } catch {}
}

# --- Default configuration (used when audio-switch.config.json is absent) -----
function Get-Config {
    if (Test-Path $CfgPath) {
        try { return (Get-Content -Raw -Path $CfgPath | ConvertFrom-Json) }
        catch { Write-Log "config.json invalid: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{
        slots = [pscustomobject]@{
            '1' = [pscustomobject]@{ label = 'Sortie Écran';  icon = 'monitor'; id = ''; fragment = 'VG34VQL3A'; name = '' }
            '2' = [pscustomobject]@{ label = 'Sortie Casque'; icon = 'headset'; id = ''; fragment = 'BlackShark'; name = '' }
        }
        ui = [pscustomobject]@{ corner = 'TopRight'; gapX = 28; gapY = 40; closeMs = 2550 }
    }
}

if (-not (Test-Path $SVCL)) {
    Write-Log "svcl.exe not found: $SVCL"
    Write-Host "ERROR: svcl.exe is missing next to the script." -ForegroundColor Red
    Write-Host "Run setup.cmd to download it automatically, or grab it here:" -ForegroundColor Yellow
    Write-Host "  https://www.nirsoft.net/utils/sound_volume_command_line.html"
    exit 1
}

# --- Enumerate every audio item via svcl -------------------------------------
function Get-AudioItems {
    $csv = Join-Path $env:TEMP ("svcl_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
    & $SVCL /scomma "$csv" /Columns "Name,Type,Direction,Device Name,Default,Command-Line Friendly ID,Process ID,Process Path" 2>$null | Out-Null
    if (-not (Test-Path $csv)) { return @() }
    try { $data = Import-Csv -Path $csv } catch { $data = @() }
    Remove-Item $csv -ErrorAction SilentlyContinue
    return $data
}

# --- Resolve a slot to an actual render device (id -> fragment -> name) -------
function Resolve-Device($slot, $items) {
    $render = $items | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' }
    $hit = $null
    if ($slot.id)       { $hit = $render | Where-Object { $_.'Command-Line Friendly ID' -eq $slot.id } | Select-Object -First 1 }
    if (-not $hit -and $slot.fragment) {
        $hit = $render | Where-Object {
            ($_.'Command-Line Friendly ID' -like "*$($slot.fragment)*") -or
            ($_.'Device Name' -like "*$($slot.fragment)*") -or
            ($_.Name -like "*$($slot.fragment)*")
        }
    }
    if (-not $hit -and $slot.name) { $hit = $render | Where-Object { $_.Name -eq $slot.name -or $_.'Device Name' -eq $slot.name } | Select-Object -First 1 }
    if ($hit -is [array]) {
        $pref = $hit | Where-Object { $_.'Command-Line Friendly ID' -like '*\Render' } | Select-Object -First 1
        $hit  = if ($pref) { $pref } else { $hit[0] }
    }
    return $hit
}

# --- Icon geometries (24x24 SVG path data) -----------------------------------
$IconMonitor = 'M4 4 H20 A2 2 0 0 1 22 6 V15 A2 2 0 0 1 20 17 H13.2 V19 H16 A1 1 0 0 1 16 21 H8 A1 1 0 0 1 8 19 H10.8 V17 H4 A2 2 0 0 1 2 15 V6 A2 2 0 0 1 4 4 Z'
$IconHeadset = 'M3 13 V12 A9 9 0 0 1 21 12 V13 H17 V12 A5 5 0 0 0 7 12 V13 Z M3 13 H7 V19 A2 2 0 0 1 5 21 A2 2 0 0 1 3 19 Z M17 13 H21 V19 A2 2 0 0 1 19 21 A2 2 0 0 1 17 19 Z'
$IconSpeaker = 'M4 9 H7.5 L12.4 5 A0.6 0.6 0 0 1 13.4 5.5 V18.5 A0.6 0.6 0 0 1 12.4 19 L7.5 15 H4 A1 1 0 0 1 3 14 V10 A1 1 0 0 1 4 9 Z M15 9.4 Q17.1 12 15 14.6 L15.7 14.6 Q17.8 12 15.7 9.4 Z M17 7.8 Q20.2 12 17 16.2 L17.7 16.2 Q20.9 12 17.7 7.8 Z'

# --- Overlay (AMD style, red) ------------------------------------------------
function Show-Toast {
    param(
        [string]$Label,
        [string]$IconName,
        [string]$DeviceName,
        [string]$Corner = 'TopRight',
        [int]$GapX = 28,
        [int]$GapY = 40,
        [int]$CloseMs = 2550
    )

    try { Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null }
    catch { Write-Log "Add-Type WPF: $($_.Exception.Message)"; return }

    $iconMap = @{ monitor = $IconMonitor; headset = $IconHeadset; speaker = $IconSpeaker }
    $icon = $iconMap[$IconName]; if (-not $icon) { $icon = $IconMonitor }
    $title = if ($Label) { $Label.ToUpper() } else { 'SORTIE' }

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="Manual" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ShowActivated="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType">

  <Grid x:Name="Root" Margin="32" Width="340" Height="76"
        HorizontalAlignment="Left" VerticalAlignment="Top">
    <Grid.Clip>
      <RectangleGeometry x:Name="EraseClip" Rect="0,0,340,76"/>
    </Grid.Clip>

    <Border x:Name="Card" Width="340" Height="76" CornerRadius="12" BorderThickness="1"
            HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CardT" X="-360"/></Border.RenderTransform>
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FF202024" Offset="0"/>
          <GradientStop Color="#FF141418" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#FF3A3A40" Offset="0"/>
          <GradientStop Color="#FF202024" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.Effect>
        <DropShadowEffect x:Name="Shadow" Color="#000000" BlurRadius="16"
                          ShadowDepth="6" Direction="270" Opacity="0"/>
      </Border.Effect>

      <Grid x:Name="Content" Margin="18,0,14,0">
        <Grid.Clip><RectangleGeometry x:Name="ContentClip" Rect="0,0,0,76"/></Grid.Clip>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Viewbox Grid.Column="0" Width="26" Height="26" Margin="0,0,13,0"
                 VerticalAlignment="Center" HorizontalAlignment="Center">
          <Canvas Width="24" Height="24">
            <Path x:Name="IconPath" Fill="#F4F4F6" Data="M0,0"/>
          </Canvas>
        </Viewbox>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="Title" Text="SORTIE" FontFamily="Segoe UI" FontWeight="Bold"
                     FontSize="20" Foreground="#FFF5F5F7"/>
          <TextBlock x:Name="Sub" Text="" FontFamily="Segoe UI" FontSize="11.5"
                     Foreground="#FFA8A8AF" Margin="0,1,0,0"
                     TextTrimming="CharacterEllipsis" MaxWidth="250"/>
        </StackPanel>
      </Grid>
    </Border>

    <Border x:Name="Writer" Width="3" Height="56" CornerRadius="1.5"
            HorizontalAlignment="Left" VerticalAlignment="Center" Opacity="0">
      <Border.RenderTransform><TranslateTransform x:Name="WriterT" X="16"/></Border.RenderTransform>
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FFFF4D45" Offset="0"/>
          <GradientStop Color="#FFED1C24" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.Effect>
        <DropShadowEffect Color="#FFED1C24" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/>
      </Border.Effect>
    </Border>

    <Border x:Name="CovLight" Width="340" Height="76" CornerRadius="12" Background="#FFFF564D"
            HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CovLT" X="360"/></Border.RenderTransform>
    </Border>
    <Border x:Name="CovMid" Width="340" Height="76" CornerRadius="12" Background="#FFED1C24"
            HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CovMT" X="360"/></Border.RenderTransform>
    </Border>
    <Border x:Name="CovDark" Width="340" Height="76" CornerRadius="12" Background="#FFA10E13"
            HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CovDT" X="360"/></Border.RenderTransform>
    </Border>
  </Grid>

  <Window.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
      <BeginStoryboard>
        <Storyboard>
          <DoubleAnimation Storyboard.TargetName="CardT" Storyboard.TargetProperty="X"
                           From="-360" To="0" Duration="0:0:0.22">
            <DoubleAnimation.EasingFunction><ExponentialEase EasingMode="EaseOut" Exponent="6"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="Shadow" Storyboard.TargetProperty="Opacity"
                           From="0" To="0.45" BeginTime="0:0:0.14" Duration="0:0:0.22"/>

          <DoubleAnimation Storyboard.TargetName="Writer" Storyboard.TargetProperty="Opacity"
                           From="0" To="1" BeginTime="0:0:0.18" Duration="0:0:0.06"/>
          <DoubleAnimation Storyboard.TargetName="WriterT" Storyboard.TargetProperty="X"
                           From="16" To="322" BeginTime="0:0:0.20" Duration="0:0:0.32">
            <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseInOut"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <RectAnimation Storyboard.TargetName="ContentClip" Storyboard.TargetProperty="Rect"
                         From="0,0,0,76" To="0,0,320,76" BeginTime="0:0:0.20" Duration="0:0:0.32">
            <RectAnimation.EasingFunction><CubicEase EasingMode="EaseInOut"/></RectAnimation.EasingFunction>
          </RectAnimation>
          <DoubleAnimation Storyboard.TargetName="Writer" Storyboard.TargetProperty="Opacity"
                           To="0" BeginTime="0:0:0.50" Duration="0:0:0.12"/>

          <DoubleAnimation Storyboard.TargetName="CovLT" Storyboard.TargetProperty="X"
                           From="360" To="0" BeginTime="0:0:1.77" Duration="0:0:0.42"/>
          <DoubleAnimation Storyboard.TargetName="CovMT" Storyboard.TargetProperty="X"
                           From="360" To="0" BeginTime="0:0:1.855" Duration="0:0:0.42"/>
          <DoubleAnimation Storyboard.TargetName="CovDT" Storyboard.TargetProperty="X"
                           From="360" To="0" BeginTime="0:0:1.94" Duration="0:0:0.42"/>

          <RectAnimation Storyboard.TargetName="EraseClip" Storyboard.TargetProperty="Rect"
                         From="0,0,340,76" To="340,0,0,76" BeginTime="0:0:2.06" Duration="0:0:0.30">
            <RectAnimation.EasingFunction><ExponentialEase EasingMode="EaseIn" Exponent="5"/></RectAnimation.EasingFunction>
          </RectAnimation>
        </Storyboard>
      </BeginStoryboard>
    </EventTrigger>
  </Window.Triggers>
</Window>
'@

    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $win    = [Windows.Markup.XamlReader]::Load($reader)
    } catch { Write-Log "XAML load fail: $($_.Exception.Message)"; return }

    $win.FindName('Title').Text    = $title
    $win.FindName('Sub').Text      = $DeviceName
    $win.FindName('IconPath').Data = [Windows.Media.Geometry]::Parse($icon)
    $win.Left = -10000; $win.Top = -10000

    $win.Add_Loaded({
        try {
            $sig = @'
using System;
using System.Runtime.InteropServices;
public static class WinEx {
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
}
'@
            if (-not ('WinEx' -as [type])) { Add-Type -TypeDefinition $sig }
            $h  = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
            $ex = [WinEx]::GetWindowLong($h, -20)
            [WinEx]::SetWindowLong($h, -20, $ex -bor 0x80 -bor 0x08000000 -bor 0x20) | Out-Null
        } catch { Write-Log "exstyle: $($_.Exception.Message)" }

        $wa = [System.Windows.SystemParameters]::WorkArea
        $m = 32; $cw = 340; $ch = 76
        switch ($Corner) {
            'TopLeft'     { $win.Left = $wa.Left  + $GapX - $m;        $win.Top = $wa.Top    + $GapY - $m }
            'BottomLeft'  { $win.Left = $wa.Left  + $GapX - $m;        $win.Top = $wa.Bottom - $GapY - $m - $ch }
            'BottomRight' { $win.Left = $wa.Right - $GapX - $m - $cw;  $win.Top = $wa.Bottom - $GapY - $m - $ch }
            default       { $win.Left = $wa.Right - $GapX - $m - $cw;  $win.Top = $wa.Top    + $GapY - $m }   # TopRight
        }
    })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($CloseMs)
    $timer.Add_Tick({ $timer.Stop(); $win.Close() })
    $timer.Start()

    try { [void]$win.ShowDialog() } catch { Write-Log "ShowDialog: $($_.Exception.Message)" }
}

# ============================== MAIN ==========================================
$cfg  = Get-Config
$norm = ($Cible -replace '^[-/]+', '').Trim().ToLower()

switch -Regex ($norm) {
    '^(1|ecran|écran|screen|moniteur|monitor)$'      { $key = '1';    break }
    '^(2|casque|headset|headphones?|hp|speakers?)$'  { $key = '2';    break }
    '^(list|liste|l)$'                               { $key = 'list'; break }
    default                                          { $key = 'help'; break }
}

if ($key -eq 'help') {
    Write-Host "Usage: audio-switch.ps1 [1|2|list]" -ForegroundColor Cyan
    Write-Host "  1     -> switch to slot 1 ($($cfg.slots.'1'.label))"
    Write-Host "  2     -> switch to slot 2 ($($cfg.slots.'2'.label))"
    Write-Host "  list  -> show detected devices"
    Write-Host "Run setup.cmd to (re)configure your devices."
    exit 0
}

if ($key -eq 'list') {
    $items = Get-AudioItems
    Write-Host "`n--- RENDER devices (outputs) ---`n" -ForegroundColor Cyan
    $items | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' } |
        Select-Object Name, @{n='Default';e={$_.Default}}, @{n='ID';e={$_.'Command-Line Friendly ID'}} |
        Format-Table -AutoSize -Wrap
    Write-Host "`n--- Active applications (outputs) ---`n" -ForegroundColor Cyan
    $items | Where-Object { $_.Type -eq 'Application' -and $_.Direction -eq 'Render' } |
        Select-Object Name, @{n='Device';e={$_.'Device Name'}}, @{n='PID';e={$_.'Process ID'}} |
        Format-Table -AutoSize -Wrap
    exit 0
}

$slot = $cfg.slots.$key
if (-not $slot) { Write-Log "Slot '$key' missing in config."; exit 1 }

# ===================== ACTION FIRST (priority) ===============================
# 1) Fastest possible: flip the default with the cached id (single svcl call).
if ($slot.id) {
    & $SVCL /SetDefault "$($slot.id)" all 2>$null | Out-Null
    Write-Log "fast SetDefault (cached id)"
}

# 2) Enumerate (needed to move running apps + verify the device).
$items = Get-AudioItems
Write-Log "enumerated $($items.Count) items"
if (-not $items -or $items.Count -eq 0) { Write-Log "svcl returned nothing."; exit 1 }

$dev = Resolve-Device $slot $items
if (-not $dev) {
    Write-Log "No device matched slot '$key' (label=$($slot.label))."
    Write-Host "ERROR: no output device matched slot $key. Run setup.cmd again." -ForegroundColor Red
    exit 1
}
$devId   = $dev.'Command-Line Friendly ID'
$devName = if ($dev.Name) { $dev.Name } else { $dev.'Device Name' }

# 3) If the cached id was empty or stale, set the resolved one now.
if (-not $slot.id -or $slot.id -ne $devId) {
    & $SVCL /SetDefault "$devId" all 2>$null | Out-Null
    Write-Log "SetDefault (resolved) -> $devName"
}

# 4) Move every running app that is NOT already on the target device.
$pids = $items |
    Where-Object {
        $_.Type -eq 'Application' -and $_.Direction -eq 'Render' -and $_.'Process ID' -and
        ($_.'Device Name' -ne $dev.'Device Name')
    } |
    Select-Object -ExpandProperty 'Process ID' -Unique
foreach ($p in $pids) { & $SVCL /SetAppDefault "$devId" all $p 2>$null | Out-Null }
Write-Log ("apps moved: {0}  | SWITCH DONE in {1}ms" -f (($pids | Measure-Object).Count), $sw.ElapsedMilliseconds)

# ============================= OVERLAY =======================================
$corner  = if ($cfg.ui.corner)  { [string]$cfg.ui.corner } else { 'TopRight' }
$gapX    = if ($cfg.ui.gapX -ne $null)    { [int]$cfg.ui.gapX }    else { 28 }
$gapY    = if ($cfg.ui.gapY -ne $null)    { [int]$cfg.ui.gapY }    else { 40 }
$closeMs = if ($cfg.ui.closeMs -ne $null) { [int]$cfg.ui.closeMs } else { 2550 }

Show-Toast -Label $slot.label -IconName $slot.icon -DeviceName $devName `
           -Corner $corner -GapX $gapX -GapY $gapY -CloseMs $closeMs
