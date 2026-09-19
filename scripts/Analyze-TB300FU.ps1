[CmdletBinding()]
param([string]$ReportDirectory, [switch]$AsJson)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-TB300FUAnalysis {
    param([hashtable]$Reports)
    $read = @{}
    $findings = New-Object 'System.Collections.Generic.List[object]'
    foreach ($name in @('identity', 'mounts', 'vendor-access', 'block-links',
                       'crypto-processes', 'filesystems', 'recovery-fstab')) {
        $text = [string]$Reports[$name]
        $code = $null
        $body = ''
        if ($text -match '\A\uFEFF?EXIT_CODE=(-?\d+)\r?\n') {
            $code = [int]$Matches[1]
            $body = $text.Substring($Matches[0].Length).Trim()
        }
        $read[$name] = [pscustomobject]@{ Code = $code; Body = $body }
        if ($null -eq $code -or $code -eq 124 -or -not $body) {
            $findings.Add([pscustomobject]@{
                Code = 'EVIDENCE_INCOMPLETE'; Source = "$name.txt"
                Message = 'Informe ausente, vacio, sin cabecera o agotado; no permite concluir ausencia de componentes.'
            })
        }
    }
    $identityOk = $read.identity.Code -eq 0 -and
        ($read.identity.Body -split '\r?\n')[0] -in @('TB300FU', 'TB300FU_S', 'twrp_TB300FU')
    $result = [ordered]@{
        DeviceIdentityVerified = $identityOk
        VendorReadable = $null
        DataMounted = $null
        MetadataMounted = $null
        F2fsSupported = $null
        UserdataMapperPresent = $null
        DecryptionVerified = $false
        Findings = $null
    }
    if (-not $identityOk) {
        $findings.Add([pscustomobject]@{
            Code = 'IDENTITY_UNVERIFIED'; Source = 'identity.txt'
            Message = 'No se aplica el mapa de particiones TB300FU sin identidad valida.'
        })
        $result.Findings = @($findings.ToArray())
        return [pscustomobject]$result
    }
    $access = $read['vendor-access']
    if ($access.Code -eq 0 -and $access.Body -in @('VENDOR_READABLE', 'VENDOR_UNAVAILABLE')) {
        $result.VendorReadable = $access.Body -eq 'VENDOR_READABLE'
        if (-not $result.VendorReadable) {
            $findings.Add([pscustomobject]@{
                Code = 'VENDOR_UNAVAILABLE'; Source = 'vendor-access.txt'
                Message = 'vendor no era accesible durante la captura. Informes vacios no prueban que falten HAL en el firmware.'
            })
        }
    }
    $mounts = $read.mounts
    if ($mounts.Code -eq 0 -and $mounts.Body -match '(?m)^\S+\s+/\S*\s+\S+\s+\S+\s+\d+\s+\d+\s*$') {
        $result.DataMounted = [bool]($mounts.Body -match '(?m)^/dev/block/\S+\s+/data\s+(f2fs|ext4)\s+')
        $result.MetadataMounted = [bool]($mounts.Body -match '(?m)^/dev/block/\S+\s+/metadata\s+ext4\s+')
    }
    if ($read.filesystems.Code -eq 0 -and $read.filesystems.Body) {
        $result.F2fsSupported = [bool]($read.filesystems.Body -match '(?m)^\s*(?:nodev\s+)?f2fs\s*$')
    }
    $links = $read['block-links']
    # ls exits 1 if one requested link is absent; preserve the positive and
    # explicit ENOENT evidence without treating other errors as absence.
    if ($links.Code -in @(0, 1)) {
        if ($links.Body -match '(?m)^l\S*\s+.*\s/dev/block/mapper/userdata\s+->\s+/dev/block/\S+') {
            $result.UserdataMapperPresent = $true
        } elseif ($links.Body -match '(?m)^ls: /dev/block/mapper/userdata: No such file or directory\s*$') {
            $result.UserdataMapperPresent = $false
        }
    }
    $fstab = $read['recovery-fstab']
    if ($fstab.Code -eq 0) {
        if ($fstab.Body -match '(?m)^\s*(/dev/block/by-name/metadata|/dev/block/mmcblk0p8)\s+/metadata\s+') {
            $findings.Add([pscustomobject]@{
                Code = 'METADATA_SOURCE_WRONG'; Source = 'recovery-fstab.txt'
                Message = 'El stock usa md_udc (p7) para /metadata; metadata (p8) es otra particion. No formatear ninguna.'
            })
        }
        if ($result.UserdataMapperPresent -eq $false -and $result.DataMounted -eq $false -and
            $fstab.Body -match 'keydirectory=/metadata/vold/metadata_encryption') {
            $findings.Add([pscustomobject]@{
                Code = 'METADATA_MAPPING_MISSING'; Source = 'block-links.txt, mounts.txt, recovery-fstab.txt'
                Message = 'No hay mapper/userdata ni /data montada y fstab requiere claves de metadata. Investigar descifrado antes de interpretar errores F2FS como corrupcion.'
            })
        }
    }
    $processes = $read['crypto-processes']
    if ($processes.Code -eq 0 -and $processes.Body -match '(?m)^\S+\s+\d+\s+.*\s(?:/\S*/)?recovery\s*$') {
        $userspace = (($processes.Body -split '\r?\n') | Where-Object { $_ -notmatch '\[[^\]]+\]\s*$' }) -join "`n"
        foreach ($service in @(
            @{ Code = 'TEE_NOT_RUNNING'; Pattern = 'teei_daemon'; Name = 'Microtrust teei_daemon' },
            @{ Code = 'KEYMASTER_NOT_RUNNING'; Pattern = 'android\.hardware\.keymaster@4\.0-service\.beanpod'; Name = 'Beanpod Keymaster 4.0' },
            @{ Code = 'GATEKEEPER_NOT_RUNNING'; Pattern = 'android\.hardware\.gatekeeper@1\.0-service'; Name = 'Gatekeeper 1.0' }
        )) {
            if ($userspace -notmatch ('(?m)^\S+\s+\d+\s+.*\s(?:/\S*/)?' + $service.Pattern + '\s*$')) {
                $findings.Add([pscustomobject]@{
                    Code = $service.Code; Source = 'crypto-processes.txt'
                    Message = $service.Name + ' no aparece en la captura de recovery. Los hilos del kernel no sustituyen este servicio.'
                })
            }
        }
    }
    $result.Findings = @($findings.ToArray())
    return [pscustomobject]$result
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $ReportDirectory -or -not (Test-Path -LiteralPath $ReportDirectory -PathType Container)) {
        throw 'Indica -ReportDirectory con la carpeta producida por Collect-TB300FU.ps1.'
    }
    # Explicit allowlist: no recursion, no ADB, no scripts/commands from reports,
    # no reads of key files or personal data, and no device or filesystem writes.
    $reports = @{}
    foreach ($name in @('identity', 'mounts', 'vendor-access', 'block-links',
                       'crypto-processes', 'filesystems', 'recovery-fstab')) {
        $path = Join-Path $ReportDirectory ($name + '.txt')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $reports[$name] = [IO.File]::ReadAllText($path)
        }
    }
    $analysis = Get-TB300FUAnalysis $reports
    if ($AsJson) {
        $analysis | ConvertTo-Json -Depth 5
    } else {
        'TB300FU: evaluacion local; no se ejecuto ningun comando en la tablet.'
        $analysis.Findings | ForEach-Object { '[{0}] {1}' -f $_.Code, $_.Message }
        'Limite: estos informes no certifican descifrado de archivos ni que una imagen sea segura para flashear.'
        'No formatear /data ni /metadata y no ejecutar reparacion sobre userdata cifrada.'
    }
}
