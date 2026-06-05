<#
================================================================================
  audio-switch.ps1
  Bascule la sortie audio (Ecran <-> Casque), deplace TOUTES les applis en cours
  vers le nouveau peripherique, et affiche une animation bleue en bas a droite.

  Usage :
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 1     # -> Ecran
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 2     # -> Casque
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 --1   # -> Ecran
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 --2   # -> Casque
    powershell -ExecutionPolicy Bypass -File audio-switch.ps1 list  # liste les peripheriques

  Prerequis : svcl.exe (SoundVolumeCommandLine de NirSoft) place A COTE de ce script.
              https://www.nirsoft.net/utils/sound_volume_command_line.html
================================================================================
#>

param(
    [Parameter(Position = 0)]
    [string]$Cible
)

# ============================== CONFIG =========================================
# Chemin vers svcl.exe (par defaut : a cote de ce script)
$SVCL = Join-Path $PSScriptRoot 'svcl.exe'

# Fragments de nom pour reconnaitre chaque peripherique (insensible a la casse).
# Mets juste un bout du nom qui est UNIQUE a chaque appareil.
# Lance ".\audio-switch.ps1 list" pour voir les noms exacts si besoin.
$FragmentEcran  = 'VG34VQL3A'      # ton ecran (AMD High Definition Audio)
$FragmentCasque = 'BlackShark'     # ton casque Razer USB

# Duree d'affichage de l'animation, en millisecondes (entree + maintien + sortie)
$ToastDurationMs = 2700
# ===============================================================================

$LogFile = Join-Path $PSScriptRoot 'audio-switch.log'
function Write-Log([string]$m) {
    try { Add-Content -Path $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) } catch {}
}

# --- Verif svcl --------------------------------------------------------------
if (-not (Test-Path $SVCL)) {
    Write-Log "svcl.exe introuvable : $SVCL"
    Write-Host "ERREUR : svcl.exe est introuvable a cote du script." -ForegroundColor Red
    Write-Host "Telecharge-le ici puis place svcl.exe dans le meme dossier :" -ForegroundColor Yellow
    Write-Host "  https://www.nirsoft.net/utils/sound_volume_command_line.html"
    exit 1
}

# --- Lecture de tous les elements audio via svcl -----------------------------
function Get-AudioItems {
    $csv = Join-Path $env:TEMP ("svcl_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
    & $SVCL /scomma "$csv" /Columns "Name,Type,Direction,Device Name,Default,Command-Line Friendly ID,Process ID,Process Path" 2>$null | Out-Null
    if (-not (Test-Path $csv)) { return @() }
    try { $data = Import-Csv -Path $csv } catch { $data = @() }
    Remove-Item $csv -ErrorAction SilentlyContinue
    return $data
}

# --- Trouve le peripherique de rendu correspondant au fragment ---------------
function Resolve-RenderDevice([string]$fragment, $items) {
    $cands = $items | Where-Object {
        $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and
        (
            ($_.'Command-Line Friendly ID' -and $_.'Command-Line Friendly ID' -like "*$fragment*") -or
            ($_.'Device Name' -and $_.'Device Name' -like "*$fragment*") -or
            ($_.Name -and $_.Name -like "*$fragment*")
        )
    }
    # On prefere l'entree "endpoint" complete (.\Render)
    $best = $cands | Where-Object { $_.'Command-Line Friendly ID' -like '*\Render' } | Select-Object -First 1
    if (-not $best) { $best = $cands | Select-Object -First 1 }
    return $best
}

# --- Geometries d'icones (24x24) ---------------------------------------------
$IconMonitor  = 'M4 4 H20 A2 2 0 0 1 22 6 V15 A2 2 0 0 1 20 17 H13.2 V19 H16 A1 1 0 0 1 16 21 H8 A1 1 0 0 1 8 19 H10.8 V17 H4 A2 2 0 0 1 2 15 V6 A2 2 0 0 1 4 4 Z'
$IconHeadset  = 'M3 13 V12 A9 9 0 0 1 21 12 V13 H17 V12 A5 5 0 0 0 7 12 V13 Z M3 13 H7 V19 A2 2 0 0 1 5 21 A2 2 0 0 1 3 19 Z M17 13 H21 V19 A2 2 0 0 1 19 21 A2 2 0 0 1 17 19 Z'

# --- Animation (overlay WPF) -------------------------------------------------
function Show-Toast {
    param(
        [ValidateSet('ecran','casque')] [string]$Mode,
        [string]$DeviceName
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml | Out-Null

    if ($Mode -eq 'ecran') { $title = 'SORTIE ECRAN' ; $icon = $IconMonitor }
    else                   { $title = 'SORTIE CASQUE'; $icon = $IconHeadset }

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="Manual" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ShowActivated="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <Grid x:Name="Root" Margin="44" Opacity="0" RenderTransformOrigin="1,1">
    <Grid.RenderTransform>
      <TranslateTransform x:Name="SlideT" X="520" Y="0"/>
    </Grid.RenderTransform>
    <Border CornerRadius="16" Padding="22,18" BorderThickness="1.2">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#F20D1426" Offset="0"/>
          <GradientStop Color="#F2101D3A" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#9048D6FF" Offset="0"/>
          <GradientStop Color="#152A6CF7" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.Effect>
        <DropShadowEffect x:Name="Glow" Color="#33C8FF" BlurRadius="40" ShadowDepth="0" Opacity="0"/>
      </Border.Effect>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid Grid.Column="0" Width="58" Height="58" Margin="0,0,18,0"
              RenderTransformOrigin="0.5,0.5">
          <Grid.RenderTransform><ScaleTransform x:Name="BadgeScale" ScaleX="0.5" ScaleY="0.5"/></Grid.RenderTransform>
          <Ellipse>
            <Ellipse.Fill>
              <RadialGradientBrush>
                <GradientStop Color="#3848D6FF" Offset="0"/>
                <GradientStop Color="#0048D6FF" Offset="1"/>
              </RadialGradientBrush>
            </Ellipse.Fill>
          </Ellipse>
          <Ellipse Stroke="#7048D6FF" StrokeThickness="1.4" Margin="3"/>
          <Viewbox Width="30" Height="30" HorizontalAlignment="Center" VerticalAlignment="Center">
            <Canvas Width="24" Height="24">
              <Path x:Name="IconPath" Fill="#EAF6FF" Data="M0,0"/>
            </Canvas>
          </Viewbox>
        </Grid>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="Kicker" Text="PERIPHERIQUE AUDIO" FontFamily="Segoe UI Semibold"
                     FontSize="10" Foreground="#80B8D8FF"/>
          <TextBlock x:Name="Title" Text="SORTIE" FontFamily="Segoe UI" FontWeight="Bold"
                     FontSize="21" Foreground="#FFFFFFFF" Margin="0,1,0,2"/>
          <TextBlock x:Name="Sub" Text="" FontFamily="Segoe UI" FontSize="11.5"
                     Foreground="#9FB6CF" TextTrimming="CharacterEllipsis" MaxWidth="260"/>
          <Border Height="3" CornerRadius="2" Margin="0,9,0,0" Width="240" Background="#1FFFFFFF"
                  HorizontalAlignment="Left">
            <Border x:Name="Sweep" HorizontalAlignment="Left" Height="3" CornerRadius="2" Width="0">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                  <GradientStop Color="#48D6FF" Offset="0"/>
                  <GradientStop Color="#2A6CF7" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
            </Border>
          </Border>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
  <Window.Triggers>
    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
      <BeginStoryboard>
        <Storyboard>
          <DoubleAnimation Storyboard.TargetName="Root" Storyboard.TargetProperty="Opacity"
                           From="0" To="1" Duration="0:0:0.35"/>
          <DoubleAnimation Storyboard.TargetName="SlideT" Storyboard.TargetProperty="X"
                           From="520" To="0" Duration="0:0:0.55">
            <DoubleAnimation.EasingFunction><QuinticEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="BadgeScale" Storyboard.TargetProperty="ScaleX"
                           From="0.5" To="1" BeginTime="0:0:0.12" Duration="0:0:0.5">
            <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="BadgeScale" Storyboard.TargetProperty="ScaleY"
                           From="0.5" To="1" BeginTime="0:0:0.12" Duration="0:0:0.5">
            <DoubleAnimation.EasingFunction><BackEase EasingMode="EaseOut" Amplitude="0.6"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="Glow" Storyboard.TargetProperty="Opacity"
                           From="0" To="0.85" Duration="0:0:0.6"/>
          <DoubleAnimation Storyboard.TargetName="Sweep" Storyboard.TargetProperty="Width"
                           From="0" To="240" BeginTime="0:0:0.15" Duration="0:0:0.75">
            <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="Root" Storyboard.TargetProperty="Opacity"
                           To="0" BeginTime="0:0:2.05" Duration="0:0:0.45"/>
          <DoubleAnimation Storyboard.TargetName="SlideT" Storyboard.TargetProperty="X"
                           To="90" BeginTime="0:0:2.05" Duration="0:0:0.45">
            <DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseIn"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
        </Storyboard>
      </BeginStoryboard>
    </EventTrigger>
  </Window.Triggers>
</Window>
'@

    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $win    = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        Write-Log "XAML load fail: $($_.Exception.Message)"
        return
    }

    $win.FindName('Title').Text    = $title
    $win.FindName('Sub').Text      = $DeviceName
    $win.FindName('IconPath').Data = [Windows.Media.Geometry]::Parse($icon)
    $win.Left = -10000; $win.Top = -10000   # hors-ecran le temps de mesurer

    # Fenetre click-through + sans focus + cachee de alt-tab
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
            $ex = [WinEx]::GetWindowLong($h, -20)            # GWL_EXSTYLE
            # WS_EX_TOOLWINDOW(0x80) | WS_EX_NOACTIVATE(0x08000000) | WS_EX_TRANSPARENT(0x20)
            [WinEx]::SetWindowLong($h, -20, $ex -bor 0x80 -bor 0x08000000 -bor 0x20) | Out-Null
        } catch { Write-Log "exstyle: $($_.Exception.Message)" }

        $wa = [System.Windows.SystemParameters]::WorkArea
        $win.Left = $wa.Right  - $win.ActualWidth  + 26   # marge interne 44 - gap visible 18
        $win.Top  = $wa.Bottom - $win.ActualHeight + 30   # marge interne 44 - gap visible 14
    })

    # Fermeture auto a la fin de l'anim
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($ToastDurationMs)
    $timer.Add_Tick({ $timer.Stop(); $win.Close() })
    $timer.Start()

    [void]$win.ShowDialog()
}

# ============================== MAIN ==========================================
$norm = ($Cible -replace '^[-/]+', '').Trim().ToLower()

switch -Regex ($norm) {
    '^(1|ecran|écran|screen|moniteur|monitor)$' { $mode = 'ecran';  $frag = $FragmentEcran  ; break }
    '^(2|casque|headset|headphones?|hp)$'       { $mode = 'casque'; $frag = $FragmentCasque ; break }
    '^(list|liste|l)$'                          { $mode = 'list' ;  break }
    default                                     { $mode = 'help' ;  break }
}

if ($mode -eq 'help') {
    Write-Host "Usage : audio-switch.ps1 [1|2|ecran|casque|list]" -ForegroundColor Cyan
    Write-Host "  1 / ecran   -> bascule vers l'ecran"
    Write-Host "  2 / casque  -> bascule vers le casque"
    Write-Host "  list        -> affiche les peripheriques detectes"
    exit 0
}

$items = Get-AudioItems
if (-not $items -or $items.Count -eq 0) {
    Write-Log "Aucun element retourne par svcl."
    Write-Host "ERREUR : svcl n'a rien renvoye." -ForegroundColor Red
    exit 1
}

if ($mode -eq 'list') {
    Write-Host "`n--- Peripheriques de RENDU (sortie) ---`n" -ForegroundColor Cyan
    $items | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' } |
        Select-Object Name, @{n='Defaut';e={$_.Default}}, @{n='ID';e={$_.'Command-Line Friendly ID'}} |
        Format-Table -AutoSize -Wrap
    Write-Host "`n--- Applications actives (sortie) ---`n" -ForegroundColor Cyan
    $items | Where-Object { $_.Type -eq 'Application' -and $_.Direction -eq 'Render' } |
        Select-Object Name, @{n='Peripherique';e={$_.'Device Name'}}, @{n='PID';e={$_.'Process ID'}} |
        Format-Table -AutoSize -Wrap
    exit 0
}

# --- Resolution du peripherique cible ---------------------------------------
$dev = Resolve-RenderDevice $frag $items
if (-not $dev) {
    Write-Log "Peripherique introuvable pour le fragment '$frag'."
    Write-Host "ERREUR : aucun peripherique ne correspond a '$frag'." -ForegroundColor Red
    Write-Host "Lance '.\audio-switch.ps1 list' et ajuste les fragments en haut du script." -ForegroundColor Yellow
    exit 1
}
$devId   = $dev.'Command-Line Friendly ID'
$devName = if ($dev.Name) { $dev.Name } else { $dev.'Device Name' }
Write-Log "Cible: $mode | $devName | $devId"

# --- 1) Definit le peripherique par defaut (tous les roles) -----------------
& $SVCL /SetDefault "$devId" all 2>$null | Out-Null

# --- 2) Deplace TOUTES les applis en cours vers ce peripherique -------------
$pids = $items |
    Where-Object { $_.Type -eq 'Application' -and $_.Direction -eq 'Render' -and $_.'Process ID' } |
    Select-Object -ExpandProperty 'Process ID' -Unique
foreach ($p in $pids) {
    & $SVCL /SetAppDefault "$devId" all $p 2>$null | Out-Null
}
Write-Log ("Applis deplacees : {0}" -f ($pids -join ', '))

# --- 3) Animation -----------------------------------------------------------
Show-Toast -Mode $mode -DeviceName $devName
