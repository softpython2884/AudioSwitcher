<#
================================================================================
  audio-switch.core.ps1  -  Shared library for audio-switch.
  Dot-sourced by audio-switch.ps1 (one-shot) and audio-switch-daemon.ps1.
  Contains: config, svcl helpers, device resolution, the WPF overlay builder,
  dynamic-colour sampling, positioning, and the actual switch logic.
================================================================================
#>

# ---- paths (resolved relative to whoever dot-sources this) -------------------
$script:Root    = Split-Path -Parent $PSCommandPath
$script:SVCL    = Join-Path $script:Root 'svcl.exe'
$script:CfgPath = Join-Path $script:Root 'audio-switch.config.json'
$script:LogFile = Join-Path $script:Root 'audio-switch.log'

function Write-ASLog([string]$m, $sw) {
    try {
        $t = if ($sw) { "[t+{0,5}ms] " -f $sw.ElapsedMilliseconds } else { '' }
        Add-Content -Path $script:LogFile -Value ("{0}  {1}{2}" -f (Get-Date -Format 'HH:mm:ss'), $t, $m)
    } catch {}
}

function Get-ASConfig {
    if (Test-Path $script:CfgPath) {
        try { return (Get-Content -Raw -Path $script:CfgPath | ConvertFrom-Json) }
        catch { Write-ASLog "config.json invalid: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{
        slots = [pscustomobject]@{
            '1' = [pscustomobject]@{ label = 'Sortie Écran';  icon = 'monitor'; id = ''; fragment = 'VG34VQL3A'; name = '' }
            '2' = [pscustomobject]@{ label = 'Sortie Casque'; icon = 'headset'; id = ''; fragment = 'BlackShark'; name = '' }
        }
        ui = [pscustomobject]@{ corner = 'TopRight'; gapX = 28; gapY = 40; closeMs = 2550; dynamicColors = $false }
    }
}

function Test-SVCL {
    if (-not (Test-Path $script:SVCL)) {
        Write-ASLog "svcl.exe missing: $script:SVCL"
        Write-Host "ERROR: svcl.exe is missing. Run setup.cmd to download it." -ForegroundColor Red
        return $false
    }
    return $true
}

function Get-AudioItems {
    $csv = Join-Path $env:TEMP ("svcl_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
    & $script:SVCL /scomma "$csv" /Columns "Name,Type,Direction,Device Name,Default,Command-Line Friendly ID,Process ID,Process Path" 2>$null | Out-Null
    if (-not (Test-Path $csv)) { return @() }
    try { $data = Import-Csv -Path $csv } catch { $data = @() }
    Remove-Item $csv -ErrorAction SilentlyContinue
    return $data
}

function Resolve-Device($slot, $items) {
    $render = $items | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' }
    $hit = $null
    if ($slot.id) { $hit = $render | Where-Object { $_.'Command-Line Friendly ID' -eq $slot.id } | Select-Object -First 1 }
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

# ---- THE SWITCH: default first, then move running apps in PARALLEL -----------
function Invoke-Switch($slot, $sw) {
    # 1) Flip default immediately with the cached id (single call, fastest).
    if ($slot.id) { & $script:SVCL /SetDefault "$($slot.id)" all 2>$null | Out-Null; Write-ASLog "fast SetDefault (cached)" $sw }

    # 2) Enumerate (needed for app PIDs + verification).
    $items = Get-AudioItems
    Write-ASLog "enumerated $($items.Count) items" $sw
    $dev = Resolve-Device $slot $items
    if (-not $dev) { Write-ASLog "no device matched slot label=$($slot.label)" $sw; return $null }
    $devId = $dev.'Command-Line Friendly ID'

    # 3) Re-set if the cached id was empty/stale.
    if (-not $slot.id -or $slot.id -ne $devId) { & $script:SVCL /SetDefault "$devId" all 2>$null | Out-Null; Write-ASLog "SetDefault (resolved)" $sw }

    # 4) Move every app NOT already on target -> fire in parallel, don't wait.
    $pids = $items |
        Where-Object { $_.Type -eq 'Application' -and $_.Direction -eq 'Render' -and $_.'Process ID' -and ($_.'Device Name' -ne $dev.'Device Name') } |
        Select-Object -ExpandProperty 'Process ID' -Unique
    foreach ($p in $pids) {
        Start-Process -FilePath $script:SVCL -ArgumentList @('/SetAppDefault', "`"$devId`"", 'all', "$p") -WindowStyle Hidden | Out-Null
    }
    Write-ASLog ("apps moved (parallel): {0} | switch issued in {1}ms" -f (($pids | Measure-Object).Count), $sw.ElapsedMilliseconds) $sw
    return $dev
}

# ---- colour helpers ----------------------------------------------------------
function script:HsvToColor([double]$h, [double]$s, [double]$v) {
    $h = (($h % 360) + 360) % 360
    $c = $v * $s; $x = $c * (1 - [math]::Abs((($h / 60) % 2) - 1)); $m = $v - $c
    switch ([int][math]::Floor($h / 60)) {
        0 { $r=$c; $g=$x; $b=0 } 1 { $r=$x; $g=$c; $b=0 } 2 { $r=0; $g=$c; $b=$x }
        3 { $r=0; $g=$x; $b=$c } 4 { $r=$x; $g=0; $b=$c } default { $r=$c; $g=0; $b=$x }
    }
    return [Windows.Media.Color]::FromRgb([byte](($r+$m)*255), [byte](($g+$m)*255), [byte](($b+$m)*255))
}

$script:AmdPalette = @{
    light = [Windows.Media.Color]::FromRgb(0xFF,0x56,0x4D)
    mid   = [Windows.Media.Color]::FromRgb(0xED,0x1C,0x24)
    dark  = [Windows.Media.Color]::FromRgb(0xA1,0x0E,0x13)
}

# Sample the screen near the chosen corner and build a vibrant palette.
function Get-AccentPalette([bool]$dynamic, [string]$corner) {
    if (-not $dynamic) { return $script:AmdPalette }
    try {
        Add-Type -AssemblyName System.Drawing, System.Windows.Forms | Out-Null
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea   # physical px
        $w = 360; $h = 90; $pad = 30
        switch ($corner) {
            'TopLeft'     { $sx = $wa.Left + $pad;            $sy = $wa.Top + $pad }
            'BottomLeft'  { $sx = $wa.Left + $pad;            $sy = $wa.Bottom - $pad - $h }
            'BottomRight' { $sx = $wa.Right - $pad - $w;      $sy = $wa.Bottom - $pad - $h }
            default       { $sx = $wa.Right - $pad - $w;      $sy = $wa.Top + $pad }
        }
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($sx, $sy, 0, 0, (New-Object System.Drawing.Size($w, $h)))
        $g.Dispose()
        $bestScore = -1.0; $bh = 0.0; $sumScore = 0.0
        for ($iy = 0; $iy -lt $h; $iy += 6) {
            for ($ix = 0; $ix -lt $w; $ix += 6) {
                $px = $bmp.GetPixel($ix, $iy)
                $r = $px.R / 255.0; $gg = $px.G / 255.0; $b = $px.B / 255.0
                $mx = [math]::Max($r, [math]::Max($gg, $b)); $mn = [math]::Min($r, [math]::Min($gg, $b))
                $v = $mx; $d = $mx - $mn; $s = if ($mx -eq 0) { 0 } else { $d / $mx }
                if ($d -gt 0) {
                    if ($mx -eq $r) { $hh = 60 * ((($gg - $b) / $d) % 6) }
                    elseif ($mx -eq $gg) { $hh = 60 * ((($b - $r) / $d) + 2) }
                    else { $hh = 60 * ((($r - $gg) / $d) + 4) }
                } else { $hh = 0 }
                $score = $s * $v
                $sumScore += $score
                if ($score -gt $bestScore) { $bestScore = $score; $bh = $hh }
            }
        }
        $bmp.Dispose()
        $avg = $sumScore / [math]::Max(1, (([math]::Floor($w/6)) * ([math]::Floor($h/6))))
        if ($avg -lt 0.12 -and $bestScore -lt 0.25) { return $script:AmdPalette }  # too grey -> keep AMD red
        return @{
            light = (script:HsvToColor $bh 0.70 1.00)
            mid   = (script:HsvToColor $bh 0.88 0.92)
            dark  = (script:HsvToColor $bh 0.95 0.55)
        }
    } catch { Write-ASLog "dynamic colour failed: $($_.Exception.Message)"; return $script:AmdPalette }
}

# ---- WPF overlay -------------------------------------------------------------
$script:IconMonitor = 'M4 4 H20 A2 2 0 0 1 22 6 V15 A2 2 0 0 1 20 17 H13.2 V19 H16 A1 1 0 0 1 16 21 H8 A1 1 0 0 1 8 19 H10.8 V17 H4 A2 2 0 0 1 2 15 V6 A2 2 0 0 1 4 4 Z'
$script:IconHeadset = 'M3 13 V12 A9 9 0 0 1 21 12 V13 H17 V12 A5 5 0 0 0 7 12 V13 Z M3 13 H7 V19 A2 2 0 0 1 5 21 A2 2 0 0 1 3 19 Z M17 13 H21 V19 A2 2 0 0 1 19 21 A2 2 0 0 1 17 19 Z'
$script:IconSpeaker = 'M4 9 H7.5 L12.4 5 A0.6 0.6 0 0 1 13.4 5.5 V18.5 A0.6 0.6 0 0 1 12.4 19 L7.5 15 H4 A1 1 0 0 1 3 14 V10 A1 1 0 0 1 4 9 Z M15 9.4 Q17.1 12 15 14.6 L15.7 14.6 Q17.8 12 15.7 9.4 Z M17 7.8 Q20.2 12 17 16.2 L17.7 16.2 Q20.9 12 17.7 7.8 Z'

function New-Overlay {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase | Out-Null
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="Manual" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ShowActivated="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType">
  <Window.Resources>
    <Storyboard x:Key="Sb">
      <DoubleAnimation Storyboard.TargetName="CardT" Storyboard.TargetProperty="X" From="-360" To="0" Duration="0:0:0.22">
        <DoubleAnimation.EasingFunction><ExponentialEase EasingMode="EaseOut" Exponent="6"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <DoubleAnimation Storyboard.TargetName="Shadow" Storyboard.TargetProperty="Opacity" From="0" To="0.45" BeginTime="0:0:0.14" Duration="0:0:0.22"/>
      <DoubleAnimation Storyboard.TargetName="Writer" Storyboard.TargetProperty="Opacity" From="0" To="1" BeginTime="0:0:0.18" Duration="0:0:0.06"/>
      <DoubleAnimation Storyboard.TargetName="WriterT" Storyboard.TargetProperty="X" From="16" To="322" BeginTime="0:0:0.20" Duration="0:0:0.32">
        <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseInOut"/></DoubleAnimation.EasingFunction>
      </DoubleAnimation>
      <RectAnimation Storyboard.TargetName="ContentClip" Storyboard.TargetProperty="Rect" From="0,0,0,76" To="0,0,320,76" BeginTime="0:0:0.20" Duration="0:0:0.32">
        <RectAnimation.EasingFunction><CubicEase EasingMode="EaseInOut"/></RectAnimation.EasingFunction>
      </RectAnimation>
      <DoubleAnimation Storyboard.TargetName="Writer" Storyboard.TargetProperty="Opacity" To="0" BeginTime="0:0:0.50" Duration="0:0:0.12"/>
      <DoubleAnimation Storyboard.TargetName="CovLT" Storyboard.TargetProperty="X" From="360" To="0" BeginTime="0:0:1.77" Duration="0:0:0.42"/>
      <DoubleAnimation Storyboard.TargetName="CovMT" Storyboard.TargetProperty="X" From="360" To="0" BeginTime="0:0:1.855" Duration="0:0:0.42"/>
      <DoubleAnimation Storyboard.TargetName="CovDT" Storyboard.TargetProperty="X" From="360" To="0" BeginTime="0:0:1.94" Duration="0:0:0.42"/>
      <RectAnimation Storyboard.TargetName="EraseClip" Storyboard.TargetProperty="Rect" From="0,0,340,76" To="340,0,0,76" BeginTime="0:0:2.06" Duration="0:0:0.30">
        <RectAnimation.EasingFunction><ExponentialEase EasingMode="EaseIn" Exponent="5"/></RectAnimation.EasingFunction>
      </RectAnimation>
    </Storyboard>
  </Window.Resources>

  <Grid x:Name="Root" Margin="32" Width="340" Height="76" HorizontalAlignment="Left" VerticalAlignment="Top">
    <Grid.Clip><RectangleGeometry x:Name="EraseClip" Rect="0,0,340,76"/></Grid.Clip>

    <Border x:Name="Card" Width="340" Height="76" CornerRadius="12" BorderThickness="1" HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CardT" X="-360"/></Border.RenderTransform>
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FF202024" Offset="0"/><GradientStop Color="#FF141418" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#FF3A3A40" Offset="0"/><GradientStop Color="#FF202024" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.Effect><DropShadowEffect x:Name="Shadow" Color="#000000" BlurRadius="16" ShadowDepth="6" Direction="270" Opacity="0"/></Border.Effect>

      <Grid x:Name="Content" Margin="18,0,14,0">
        <Grid.Clip><RectangleGeometry x:Name="ContentClip" Rect="0,0,0,76"/></Grid.Clip>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Viewbox Grid.Column="0" Width="26" Height="26" Margin="0,0,13,0" VerticalAlignment="Center" HorizontalAlignment="Center">
          <Canvas Width="24" Height="24"><Path x:Name="IconPath" Fill="#F4F4F6" Data="M0,0"/></Canvas>
        </Viewbox>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="Title" Text="SORTIE" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20" Foreground="#FFF5F5F7"/>
          <TextBlock x:Name="Sub" Text="" FontFamily="Segoe UI" FontSize="11.5" Foreground="#FFA8A8AF" Margin="0,1,0,0" TextTrimming="CharacterEllipsis" MaxWidth="250"/>
        </StackPanel>
      </Grid>
    </Border>

    <Border x:Name="Writer" Width="3" Height="56" CornerRadius="1.5" HorizontalAlignment="Left" VerticalAlignment="Center" Opacity="0">
      <Border.RenderTransform><TranslateTransform x:Name="WriterT" X="16"/></Border.RenderTransform>
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#FFFF4D45" Offset="0"/><GradientStop Color="#FFED1C24" Offset="1"/></LinearGradientBrush>
      </Border.Background>
      <Border.Effect><DropShadowEffect Color="#FFED1C24" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/></Border.Effect>
    </Border>

    <Border x:Name="CovLight" Width="340" Height="76" CornerRadius="12" Background="#FFFF564D" HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CovLT" X="360"/></Border.RenderTransform>
    </Border>
    <Border x:Name="CovMid" Width="340" Height="76" CornerRadius="12" Background="#FFED1C24" HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CovMT" X="360"/></Border.RenderTransform>
    </Border>
    <Border x:Name="CovDark" Width="340" Height="76" CornerRadius="12" Background="#FFA10E13" HorizontalAlignment="Left" VerticalAlignment="Top">
      <Border.RenderTransform><TranslateTransform x:Name="CovDT" X="360"/></Border.RenderTransform>
    </Border>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

function Set-OverlayContent($win, [string]$label, [string]$icon, [string]$device, $palette) {
    $map = @{ monitor = $script:IconMonitor; headset = $script:IconHeadset; speaker = $script:IconSpeaker }
    $d = $map[$icon]; if (-not $d) { $d = $script:IconMonitor }
    $win.FindName('Title').Text    = if ($label) { $label.ToUpper() } else { 'SORTIE' }
    $win.FindName('Sub').Text      = $device
    $win.FindName('IconPath').Data = [Windows.Media.Geometry]::Parse($d)

    $light = New-Object Windows.Media.SolidColorBrush $palette.light
    $mid   = New-Object Windows.Media.SolidColorBrush $palette.mid
    $dark  = New-Object Windows.Media.SolidColorBrush $palette.dark
    $win.FindName('CovLight').Background = $light
    $win.FindName('CovMid').Background   = $mid
    $win.FindName('CovDark').Background  = $dark
    $wb = New-Object Windows.Media.LinearGradientBrush
    $wb.StartPoint = New-Object Windows.Point(0,0); $wb.EndPoint = New-Object Windows.Point(0,1)
    $wb.GradientStops.Add((New-Object Windows.Media.GradientStop($palette.light,0)))
    $wb.GradientStops.Add((New-Object Windows.Media.GradientStop($palette.mid,1)))
    $writer = $win.FindName('Writer'); $writer.Background = $wb
    if ($writer.Effect) { $writer.Effect.Color = $palette.mid }
}

function Set-OverlayPosition($win, [string]$corner, [int]$gapX, [int]$gapY) {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $m = 32; $cw = 340; $ch = 76
    switch ($corner) {
        'TopLeft'     { $L = $wa.Left  + $gapX - $m;        $T = $wa.Top    + $gapY - $m }
        'BottomLeft'  { $L = $wa.Left  + $gapX - $m;        $T = $wa.Bottom - $gapY - $m - $ch }
        'BottomRight' { $L = $wa.Right - $gapX - $m - $cw;  $T = $wa.Bottom - $gapY - $m - $ch }
        default       { $L = $wa.Right - $gapX - $m - $cw;  $T = $wa.Top    + $gapY - $m }
    }
    # clamp so it always stays fully on the work area (safety on any resolution)
    $winW = $cw + 2*$m; $winH = $ch + 2*$m
    if ($L -lt $wa.Left) { $L = $wa.Left }
    if ($T -lt $wa.Top)  { $T = $wa.Top }
    if (($L + $winW) -gt $wa.Right)  { $L = $wa.Right  - $winW }
    if (($T + $winH) -gt $wa.Bottom) { $T = $wa.Bottom - $winH }
    $win.Left = $L; $win.Top = $T
}

function Set-ClickThrough($win) {
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
        if ($h -ne [IntPtr]::Zero) {
            $ex = [WinEx]::GetWindowLong($h, -20)
            [WinEx]::SetWindowLong($h, -20, $ex -bor 0x80 -bor 0x08000000 -bor 0x20) | Out-Null
        }
    } catch { Write-ASLog "exstyle: $($_.Exception.Message)" }
}

function Get-Sb($win) { return $win.FindResource('Sb') }
