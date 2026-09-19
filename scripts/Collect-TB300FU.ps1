[CmdletBinding()]
param(
    [string]$Serial,
    [string]$AdbPath = 'adb',
    [string]$OutputDirectory,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 20
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW/CRT quoting. Never evaluate remote commands in PS.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-TimedProcess {
    param([string]$Program, [string[]]$Arguments, [int]$Seconds = 20)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Program
    $info.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw "Cannot start $Program" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Seconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            return [pscustomobject]@{
                ExitCode = 124; Stdout = $stdout.GetAwaiter().GetResult()
                Stderr = ('Timed out after {0}s. ' -f $Seconds) + $stderr.GetAwaiter().GetResult()
            }
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout.GetAwaiter().GetResult()
            Stderr = $stderr.GetAwaiter().GetResult()
        }
    } finally { $process.Dispose() }
}

function Select-AdbTarget {
    param([string]$DeviceList, [string]$RequestedSerial)
    $targets = @()
    foreach ($line in ($DeviceList -split '\r?\n')) {
        if ($line -match '^(\S+)\s+(device|recovery|offline|unauthorized|sideload)(?:\s|$)') {
            $targets += [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
    if ($RequestedSerial) {
        $targets = @($targets | Where-Object Serial -eq $RequestedSerial)
    }
    if ($targets.Count -ne 1) {
        throw 'Conecta una sola tablet por ADB, o indica -Serial. No se reinicia ni modifica ningun dispositivo.'
    }
    if ($targets[0].State -notin @('device', 'recovery')) {
        throw ('ADB no esta listo: {0}. Autoriza la conexion o sal de sideload.' -f $targets[0].State)
    }
    return $targets[0]
}

function Get-TB300FUReadPlan {
    # Only text from firmware/system interfaces. No key files, PINs, /data,
    # /metadata contents, partitions, mount operations, or service start/stop.
    return @(
        [pscustomobject]@{ Name = 'identity'; Command = 'getprop ro.product.device; getprop ro.build.fingerprint; getprop ro.vendor.build.fingerprint; getprop ro.twrp.version; getprop ro.boot.slot_suffix; getprop sys.boot_completed' }
        [pscustomobject]@{ Name = 'mounts'; Command = 'cat /proc/mounts' }
        [pscustomobject]@{ Name = 'crypto-properties'; Command = 'getprop | grep -Ei "ro.crypto|ro.product.first_api_level|ro.vendor.api_level|ro.boot.hardware|sys.usb|init.svc.*(tee|keymaster|gatekeeper|keystore|vold|thh)"' }
        [pscustomobject]@{ Name = 'crypto-processes'; Command = 'ps -A | grep -Ei "tee|keymaster|gatekeeper|keystore|vold|thh|recovery"' }
        [pscustomobject]@{ Name = 'recovery-fstab'; Command = 'cat /etc/recovery.fstab /etc/additional.fstab 2>&1' }
        [pscustomobject]@{ Name = 'vendor-fstab'; Command = 'for f in /vendor/etc/fstab.* /odm/etc/fstab.*; do if [ -f "$f" ]; then echo "FILE: $f"; cat "$f"; fi; done' }
        [pscustomobject]@{ Name = 'vendor-services'; Command = 'for f in /vendor/etc/init/*.rc /vendor/etc/init/hw/*.rc; do if [ -f "$f" ] && grep -qiE "keymaster|gatekeeper|microtrust|beanpod|teei|thh" "$f"; then echo "FILE: $f"; cat "$f"; fi; done' }
        [pscustomobject]@{ Name = 'vendor-manifest'; Command = 'for f in /vendor/etc/vintf/manifest.xml /vendor/etc/vintf/manifest/*.xml; do if [ -f "$f" ] && grep -qiE "keymaster|gatekeeper|microtrust|beanpod|teei|thh" "$f"; then echo "FILE: $f"; cat "$f"; fi; done' }
        [pscustomobject]@{ Name = 'vendor-inventory'; Command = 'find /vendor/bin /vendor/lib /vendor/etc /vendor/firmware -maxdepth 5 -type f 2>/dev/null | grep -Ei "keymaster|gatekeeper|microtrust|beanpod|teei|thh|trustkernel"' }
        [pscustomobject]@{ Name = 'vendor-dependencies'; Command = 'for f in /vendor/bin/teei_daemon /vendor/bin/hw/*keymaster* /vendor/bin/hw/*gatekeeper* /vendor/bin/hw/*thh*; do if [ -f "$f" ]; then echo "FILE: $f"; if command -v readelf >/dev/null 2>&1; then readelf -d "$f" 2>&1 | grep -E "NEEDED|RPATH|RUNPATH|Error"; elif command -v toybox >/dev/null 2>&1; then toybox readelf -d "$f" 2>&1 | grep -E "NEEDED|RPATH|RUNPATH|Error|Unknown"; else echo "readelf unavailable"; fi; fi; done' }
        [pscustomobject]@{ Name = 'tee-nodes'; Command = 'ls -l /dev/tee* /dev/tz* /dev/utr* /dev/trust* /dev/teei* 2>&1' }
        [pscustomobject]@{ Name = 'block-links'; Command = 'ls -l /dev/block/by-name/md_udc /dev/block/by-name/metadata /dev/block/by-name/userdata /dev/block/mapper/userdata 2>&1' }
        [pscustomobject]@{ Name = 'filesystems'; Command = 'cat /proc/filesystems' }
        [pscustomobject]@{ Name = 'vendor-access'; Command = 'if [ -d /vendor/etc/init ] && [ -d /vendor/bin/hw ]; then echo VENDOR_READABLE; else echo VENDOR_UNAVAILABLE; fi' }
    )
}

function Collect-TB300FUEvidence {
    param(
        [string]$RequestedSerial, [string]$Destination,
        [scriptblock]$RunAdb
    )
    $devices = & $RunAdb @('devices', '-l')
    if ($devices.ExitCode -ne 0) { throw "adb devices fallo: $($devices.Stderr)" }
    $target = Select-AdbTarget $devices.Stdout $RequestedSerial
    $identity = & $RunAdb @('-s', $target.Serial, 'shell', 'getprop ro.product.device')
    if ($identity.ExitCode -ne 0 -or $identity.Stdout.Trim() -notin @('TB300FU', 'TB300FU_S', 'twrp_TB300FU')) {
        throw 'El dispositivo no se identifica como TB300FU. No se recopilo informacion.'
    }
    if (-not $Destination) {
        $folder = 'TB300FU-diagnostico-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
        $Destination = Join-Path (Join-Path $env:USERPROFILE 'Downloads') $folder
    }
    if (Test-Path -LiteralPath $Destination) { throw 'La carpeta de salida ya existe. Usa una carpeta nueva para conservar los informes anteriores.' }
    $dir = New-Item -ItemType Directory -Path $Destination
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $results = @()
    foreach ($item in (Get-TB300FUReadPlan)) {
        Write-Host ('Leyendo {0}...' -f $item.Name)
        $r = & $RunAdb @('-s', $target.Serial, 'shell', $item.Command)
        $body = "EXIT_CODE=$($r.ExitCode)" + [Environment]::NewLine + $r.Stdout + [Environment]::NewLine + $r.Stderr
        [IO.File]::WriteAllText((Join-Path $dir.FullName ($item.Name + '.txt')), $body, $utf8)
        $results += [pscustomobject]@{ Name = $item.Name; ExitCode = $r.ExitCode; Command = $item.Command }
    }
    [IO.File]::WriteAllText((Join-Path $dir.FullName 'commands.json'), ($results | ConvertTo-Json -Depth 4), $utf8)
    $summary = @(
        'TB300FU: recopilacion de solo lectura. Ninguna particion se monto, borro o flasheo.',
        ('Estado ADB: ' + $target.State),
        'Lee vendor-services.txt para las definiciones originales; vendor-dependencies.txt muestra las bibliotecas requeridas.',
        'Si vendor-access.txt contiene VENDOR_UNAVAILABLE, ejecuta este mismo script desde Android normal con ADB.',
        'No se recopilan claves de /metadata ni datos de /data. No subas esas particiones.',
        ('Resultados: ' + $dir.FullName)
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $dir.FullName 'resumen.txt'), $summary, $utf8)
    Write-Host $summary
    return $dir.FullName
}

if ($MyInvocation.InvocationName -ne '.') {
    $adbCommand = (Get-Command $AdbPath -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $runner = {
        param([string[]]$AdbArguments)
        Invoke-TimedProcess -Program $adbCommand -Arguments $AdbArguments -Seconds $TimeoutSeconds
    }
    Collect-TB300FUEvidence -RequestedSerial $Serial -Destination $OutputDirectory -RunAdb $runner
}
