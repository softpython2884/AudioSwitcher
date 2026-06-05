<#
================================================================================
  setup.ps1  -  One-shot configurator for audio-switch.

  - Downloads svcl.exe (NirSoft) automatically if it's missing.
  - Lists your output devices and lets you assign two of them to keys 1 and 2.
  - Writes audio-switch.config.json.
  - Generates Stream Deck launchers (.vbs, no console flash).

  Just double-click setup.cmd. (Or: powershell -ExecutionPolicy Bypass -File setup.ps1)
================================================================================
#>

$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$svcl    = Join-Path $root 'svcl.exe'
$cfgPath = Join-Path $root 'audio-switch.config.json'
$psMain  = Join-Path $root 'audio-switch.ps1'

function Line { Write-Host ('-' * 64) -ForegroundColor DarkGray }
function To-Ascii([string]$s) {
    if (-not $s) { return '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormD)
    -join ($d.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
}

Clear-Host
Line
Write-Host "  audio-switch  -  setup" -ForegroundColor Cyan
Line
Write-Host ""

# --- 1) Ensure svcl.exe ------------------------------------------------------
if (-not (Test-Path $svcl)) {
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $url  = if ($arch -eq 'x64') { 'https://www.nirsoft.net/utils/svcl-x64.zip' } else { 'https://www.nirsoft.net/utils/svcl.zip' }
    Write-Host "svcl.exe not found - downloading NirSoft SoundVolumeCommandLine ($arch)..." -ForegroundColor Yellow
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
        $zip = Join-Path $env:TEMP 'svcl_dl.zip'
        $tmp = Join-Path $env:TEMP ('svcl_x_' + [guid]::NewGuid().ToString('N'))
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -UserAgent 'Mozilla/5.0'
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $exe = Get-ChildItem -Path $tmp -Recurse -Filter 'svcl.exe' | Select-Object -First 1
        if (-not $exe) { throw "svcl.exe not found inside the downloaded archive." }
        Copy-Item $exe.FullName $svcl -Force
        try { Unblock-File $svcl } catch {}
        Remove-Item $zip -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -ErrorAction SilentlyContinue
        Write-Host "  -> svcl.exe ready." -ForegroundColor Green
    } catch {
        Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Please download svcl.exe manually and drop it next to this script:" -ForegroundColor Yellow
        Write-Host "    https://www.nirsoft.net/utils/sound_volume_command_line.html"
        Read-Host "`nPress Enter to close"
        exit 1
    }
} else {
    Write-Host "svcl.exe found." -ForegroundColor Green
}
Write-Host ""

# --- 2) Enumerate output (render) devices ------------------------------------
$csv = Join-Path $env:TEMP ("svcl_setup_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
& $svcl /scomma "$csv" /Columns "Name,Type,Direction,Device Name,Default,Command-Line Friendly ID" 2>$null | Out-Null
if (-not (Test-Path $csv)) { Write-Host "svcl did not return data." -ForegroundColor Red; Read-Host "`nPress Enter to close"; exit 1 }
$all = Import-Csv -Path $csv
Remove-Item $csv -ErrorAction SilentlyContinue

$devices = @($all | Where-Object { $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and $_.Name })
if ($devices.Count -lt 2) {
    Write-Host "Need at least 2 output devices, found $($devices.Count)." -ForegroundColor Red
    Read-Host "`nPress Enter to close"; exit 1
}

Write-Host "Output devices detected:" -ForegroundColor Cyan
for ($i = 0; $i -lt $devices.Count; $i++) {
    $d = $devices[$i]
    $def = if ($d.Default -and $d.Default -match 'Render') { '  (current default)' } else { '' }
    Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $d.Name, $def)
}
Write-Host ""

function Read-DeviceIndex([string]$prompt, [int]$count) {
    while ($true) {
        $r = Read-Host $prompt
        if ($r -match '^\d+$') { $n = [int]$r; if ($n -ge 1 -and $n -le $count) { return $n - 1 } }
        Write-Host "  Enter a number between 1 and $count." -ForegroundColor DarkYellow
    }
}

function Guess([string]$name) {
    $n = $name.ToLower()
    if ($n -match 'head|casque|razer|blackshark|arctis|hyperx|steelseries|logitech g|earbud|airpod|wh-|wf-') { return @{ label = 'Headset'; icon = 'headset' } }
    if ($n -match 'monitor|display|screen|tv|hdmi|odyssey|vg\d|lg ultra|high definition audio|nvidia|amd ') { return @{ label = 'Monitor'; icon = 'monitor' } }
    return @{ label = 'Speakers'; icon = 'speaker' }
}

function Read-Slot([int]$num, $devices) {
    Write-Host ""
    Line
    Write-Host ("  KEY $num" ) -ForegroundColor Cyan
    Line
    $idx = Read-DeviceIndex "Which device for key $num? (number)" $devices.Count
    $dev = $devices[$idx]
    $g   = Guess $dev.Name
    Write-Host ("Selected: {0}" -f $dev.Name) -ForegroundColor Green

    $label = Read-Host ("Label shown in the overlay [{0}]" -f $g.label)
    if (-not $label) { $label = $g.label }

    $icon = Read-Host ("Icon - monitor / headset / speaker [{0}]" -f $g.icon)
    if (-not $icon) { $icon = $g.icon }
    $icon = $icon.ToLower()
    if ($icon -notin @('monitor','headset','speaker')) { $icon = $g.icon }

    return [ordered]@{
        label    = $label
        icon     = $icon
        id       = $dev.'Command-Line Friendly ID'
        fragment = ''
        name     = $dev.Name
    }
}

$slot1 = Read-Slot 1 $devices
$slot2 = Read-Slot 2 $devices
if ($slot1.id -eq $slot2.id) {
    Write-Host "`nKey 1 and key 2 point to the same device - that's allowed but unusual." -ForegroundColor DarkYellow
}

# --- 3) Overlay corner -------------------------------------------------------
Write-Host ""
Line
Write-Host "  OVERLAY POSITION" -ForegroundColor Cyan
Line
$corner = Read-Host "Corner - TopRight / TopLeft / BottomRight / BottomLeft [TopRight]"
if (-not $corner) { $corner = 'TopRight' }
$map = @{ topright='TopRight'; topleft='TopLeft'; bottomright='BottomRight'; bottomleft='BottomLeft' }
$corner = $map[$corner.ToLower()]; if (-not $corner) { $corner = 'TopRight' }

# --- 4) Write config.json ----------------------------------------------------
$config = [ordered]@{
    slots = [ordered]@{ '1' = $slot1; '2' = $slot2 }
    ui    = [ordered]@{ corner = $corner; gapX = 28; gapY = 40; closeMs = 2550 }
}
$config | ConvertTo-Json -Depth 6 | Out-File -FilePath $cfgPath -Encoding UTF8
Write-Host "`nSaved $([IO.Path]::GetFileName($cfgPath))" -ForegroundColor Green

# --- 5) Generate Stream Deck launchers (.vbs) --------------------------------
$vbsTemplate = @'
' Auto-generated launcher for Stream Deck (no window flashes)
Dim fso, here, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File """ & here & "\audio-switch.ps1"" __SLOT__"
CreateObject("WScript.Shell").Run cmd, 0, False
'@

function New-Launcher([string]$label, [int]$slotNum) {
    $name = (To-Ascii $label) -replace '[^A-Za-z0-9]+', ''
    if (-not $name) { $name = "slot$slotNum" }
    $file = Join-Path $root ($name + '.vbs')
    ($vbsTemplate -replace '__SLOT__', "$slotNum") | Set-Content -Path $file -Encoding ASCII
    return $file
}
$f1 = New-Launcher $slot1.label 1
$f2 = New-Launcher $slot2.label 2
Write-Host ("Created launchers:`n  {0}`n  {1}" -f ([IO.Path]::GetFileName($f1)), ([IO.Path]::GetFileName($f2))) -ForegroundColor Green

# --- 6) Optional test --------------------------------------------------------
Write-Host ""
$test = Read-Host "Test switch to KEY 1 now? (y/N)"
if ($test -match '^(y|yes|o|oui)$') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $psMain 1
}

# --- 7) Done -----------------------------------------------------------------
Write-Host ""
Line
Write-Host "  ALL SET" -ForegroundColor Green
Line
Write-Host "In Stream Deck, add two buttons -> action 'System: Open':"
Write-Host ("   Key 1  ->  {0}" -f $f1)
Write-Host ("   Key 2  ->  {0}" -f $f2)
Write-Host ""
Write-Host "Re-run this setup any time to change devices, labels, or the corner."
Read-Host "`nPress Enter to close"
