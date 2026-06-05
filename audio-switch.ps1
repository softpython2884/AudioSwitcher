<#
================================================================================
  audio-switch.ps1
  Bascule la sortie audio (Ecran <-> Casque), deplace TOUTES les applis en cours
  vers le nouveau peripherique, puis affiche une animation rouge AMD en bas a
  gauche (remontee de ~20%).

  L'ACTION (changement de sortie) est faite EN PREMIER, l'animation ensuite.

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

# Delai avant fermeture de la fenetre d'animation, en ms (laisse finir l'anim).
# La duree interne de l'anim (~2.4s dont 1.25s de pause) est fixee plus bas.
$CloseMs = 2550

# Position : marge depuis le bord droit (px) et hauteur depuis le haut (% de l'ecran)
$GapRightPx = 28
$TopPercent = 0.20
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
    $best = $cands | Where-Object { $_.'Command-Line Friendly ID' -like '*\Render' } | Select-Object -First 1
    if (-not $best) { $best = $cands | Select-Object -First 1 }
    return $best
}

# --- Geometries d'icones (24x24) ---------------------------------------------
$IconMonitor = 'M4 4 H20 A2 2 0 0 1 22 6 V15 A2 2 0 0 1 20 17 H13.2 V19 H16 A1 1 0 0 1 16 21 H8 A1 1 0 0 1 8 19 H10.8 V17 H4 A2 2 0 0 1 2 15 V6 A2 2 0 0 1 4 4 Z'
$IconHeadset = 'M3 13 V12 A9 9 0 0 1 21 12 V13 H17 V12 A5 5 0 0 0 7 12 V13 Z M3 13 H7 V19 A2 2 0 0 1 5 21 A2 2 0 0 1 3 19 Z M17 13 H21 V19 A2 2 0 0 1 19 21 A2 2 0 0 1 17 19 Z'

# --- Animation overlay (style AMD, rouge) ------------------------------------
function Show-Toast {
    param(
        [ValidateSet('ecran','casque')] [string]$Mode,
        [string]$DeviceName
    )

    try { Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase | Out-Null }
    catch { Write-Log "Add-Type WPF: $($_.Exception.Message)"; return }

    if ($Mode -eq 'ecran') { $title = 'SORTIE ÉCRAN' ; $icon = $IconMonitor }
    else                   { $title = 'SORTIE CASQUE'; $icon = $IconHeadset }

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

    <!-- Panneau gris AMD (glisse depuis la gauche) -->
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

      <!-- Contenu (icone + texte) revele par la barre rouge -->
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

    <!-- Barre rouge fine qui "ecrit" le texte -->
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

    <!-- 3 barres rouges (sortie) qui balaient de droite vers gauche -->
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
          <!-- 1) Panneau gris glisse de gauche a droite -->
          <DoubleAnimation Storyboard.TargetName="CardT" Storyboard.TargetProperty="X"
                           From="-360" To="0" Duration="0:0:0.22">
            <DoubleAnimation.EasingFunction><ExponentialEase EasingMode="EaseOut" Exponent="6"/></DoubleAnimation.EasingFunction>
          </DoubleAnimation>
          <DoubleAnimation Storyboard.TargetName="Shadow" Storyboard.TargetProperty="Opacity"
                           From="0" To="0.45" BeginTime="0:0:0.14" Duration="0:0:0.22"/>

          <!-- 2) Barre rouge passe et ecrit le texte -->
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

          <!-- 3) PAUSE ~1.25s (de ~0.52 a ~1.77) -->

          <!-- 4a) 3 barres rouges : balayage droite -> gauche, decalees ~20% -->
          <DoubleAnimation Storyboard.TargetName="CovLT" Storyboard.TargetProperty="X"
                           From="360" To="0" BeginTime="0:0:1.77" Duration="0:0:0.42"/>
          <DoubleAnimation Storyboard.TargetName="CovMT" Storyboard.TargetProperty="X"
                           From="360" To="0" BeginTime="0:0:1.855" Duration="0:0:0.42"/>
          <DoubleAnimation Storyboard.TargetName="CovDT" Storyboard.TargetProperty="X"
                           From="360" To="0" BeginTime="0:0:1.94" Duration="0:0:0.42"/>

          <!-- 4b) Disparition gauche -> droite (avant que la derniere barre arrive a moitie) -->
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
    } catch {
        Write-Log "XAML load fail: $($_.Exception.Message)"
        return
    }

    $win.FindName('Title').Text    = $title
    $win.FindName('Sub').Text      = $DeviceName
    $win.FindName('IconPath').Data = [Windows.Media.Geometry]::Parse($icon)
    $win.Left = -10000; $win.Top = -10000   # hors-ecran le temps de mesurer

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
        $margin = 32; $cardW = 340; $cardH = 76
        $win.Left = $wa.Right - $GapRightPx - $margin - $cardW
        $win.Top  = $wa.Top + ($wa.Height * $TopPercent) - $margin
    })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($CloseMs)
    $timer.Add_Tick({ $timer.Stop(); $win.Close() })
    $timer.Start()

    try { [void]$win.ShowDialog() } catch { Write-Log "ShowDialog: $($_.Exception.Message)" }
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

# ========================= ACTION EN PRIORITE ================================
# 1) Definit le peripherique par defaut (tous les roles) -- le son bascule ici
& $SVCL /SetDefault "$devId" all 2>$null | Out-Null

# 2) Deplace TOUTES les applis en cours vers ce peripherique
#    (on saute celles deja sur la bonne sortie)
$pids = $items |
    Where-Object {
        $_.Type -eq 'Application' -and $_.Direction -eq 'Render' -and $_.'Process ID' -and
        ($_.'Device Name' -ne $dev.'Device Name')
    } |
    Select-Object -ExpandProperty 'Process ID' -Unique
foreach ($p in $pids) {
    & $SVCL /SetAppDefault "$devId" all $p 2>$null | Out-Null
}
Write-Log ("Applis deplacees : {0}" -f ($pids -join ', '))

# ============================= ANIMATION =====================================
Show-Toast -Mode $mode -DeviceName $devName
