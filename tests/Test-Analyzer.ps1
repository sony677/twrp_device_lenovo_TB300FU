$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$analyzer = Join-Path $PSScriptRoot '../scripts/Analyze-TB300FU.ps1'
if (-not (Test-Path -LiteralPath $analyzer)) {
    throw 'FAIL: falta el evaluador de informes TB300FU'
}
. $analyzer

function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Get-Fixture {
    return @{
        identity = "EXIT_CODE=0`nTB300FU`ntwrp/TB300FU`n3.7.1_12-0`n_b"
        'vendor-access' = "EXIT_CODE=0`nVENDOR_UNAVAILABLE"
        mounts = "EXIT_CODE=0`nrootfs / rootfs rw 0 0`ntmpfs /tmp tmpfs rw 0 0"
        'block-links' = "EXIT_CODE=1`nls: /dev/block/mapper/userdata: No such file or directory`nlrwxrwxrwx 1 root root 20 /dev/block/by-name/md_udc -> /dev/block/mmcblk0p7`nlrwxrwxrwx 1 root root 20 /dev/block/by-name/metadata -> /dev/block/mmcblk0p8"
        'crypto-processes' = "EXIT_CODE=0`nroot 186 2 0 0 0 0 S [teei_switch_thr]`nroot 260 1 103944 30144 0 0 S recovery"
        filesystems = "EXIT_CODE=0`nnodev sysfs`n      f2fs"
        'vendor-fstab' = "EXIT_CODE=0`n"
        'recovery-fstab' = "EXIT_CODE=0`n/dev/block/by-name/md_udc /metadata ext4 noatime wait`n/dev/block/by-name/userdata /data f2fs inlinecrypt wait,fileencryption=aes-256-xts:aes-256-cts:v2,keydirectory=/metadata/vold/metadata_encryption"
    }
}

$r = Get-TB300FUAnalysis (Get-Fixture)
Assert-True ($r.Findings.Code -contains 'VENDOR_UNAVAILABLE') 'vendor inaccesible no se confunde con firmware sin HAL'
Assert-True ($r.Findings.Code -contains 'TEE_NOT_RUNNING') 'hilos teei del kernel no cuentan como daemon'
Assert-True ($r.Findings.Code -contains 'KEYMASTER_NOT_RUNNING') 'detecta Keymaster ausente'
Assert-True ($r.Findings.Code -contains 'METADATA_MAPPING_MISSING') 'reconoce mapper ausente aunque ls termina con 1'
Assert-True ($r.Findings.Code -notcontains 'METADATA_SOURCE_WRONG') 'md_udc p7 se conserva'
Assert-True ($r.Findings.Code -notcontains 'VOLD_NOT_RUNNING') 'no exige vold independiente a TWRP'
Assert-True ($r.F2fsSupported -eq $true) 'detecta soporte f2fs'
Write-Host 'PASS: recovery sin servicios ni mapper'

$fixture = Get-Fixture
$fixture['vendor-access'] = "EXIT_CODE=0`nVENDOR_READABLE"
$fixture['mounts'] += "`n/dev/block/mapper/vendor_b /vendor ext4 ro 0 0"
$fixture['crypto-processes'] += "`nsystem 395 1 13084 3636 0 0 S teei_daemon`nsystem 412 1 12988 5464 0 0 S android.hardware.keymaster@4.0-service.beanpod`nsystem 547 1 11460 3816 0 0 S android.hardware.gatekeeper@1.0-service"
$r = Get-TB300FUAnalysis $fixture
Assert-True ($r.VendorReadable -eq $true) 'vendor legible'
Assert-True ($r.Findings.Code -notcontains 'TEE_NOT_RUNNING') 'detecta el daemon real'
Assert-True ($r.Findings.Code -notcontains 'KEYMASTER_NOT_RUNNING') 'detecta Keymaster real'
Assert-True (-not $r.DecryptionVerified) 'servicios iniciados no prueban descifrado'
Write-Host 'PASS: servicios presentes no implican descifrado'

$fixture = Get-Fixture
$fixture['mounts'] += "`n/dev/block/dm-39 /data f2fs rw 0 0`n/dev/block/mmcblk0p7 /metadata ext4 rw 0 0"
$fixture['block-links'] = "EXIT_CODE=0`nlrwxrwxrwx 1 root root 16 /dev/block/mapper/userdata -> /dev/block/dm-39"
$r = Get-TB300FUAnalysis $fixture
Assert-True ($r.DataMounted -eq $true) '/data montada reconocida'
Assert-True ($r.Findings.Code -notcontains 'METADATA_MAPPING_MISSING') 'no reporta mapper ausente si existe'
Assert-True (-not $r.DecryptionVerified) 'montaje f2fs no prueba descifrado de credenciales'
Write-Host 'PASS: mapper y montaje no implican archivos descifrados'

$fixture = Get-Fixture
$fixture['recovery-fstab'] = $fixture['recovery-fstab'].Replace('/by-name/md_udc', '/by-name/metadata')
$r = Get-TB300FUAnalysis $fixture
Assert-True ($r.Findings.Code -contains 'METADATA_SOURCE_WRONG') 'detecta cambio peligroso a metadata p8'
Write-Host 'PASS: metadata p8 rechazada'

$fixture = Get-Fixture
$fixture['mounts'] = "EXIT_CODE=124`nTimed out"
$fixture['crypto-processes'] = "EXIT_CODE=124`nTimed out"
$fixture['filesystems'] = "EXIT_CODE=1`nPermission denied"
$fixture['vendor-access'] = "EXIT_CODE=0`n"
$r = Get-TB300FUAnalysis $fixture
Assert-True ($null -eq $r.DataMounted) 'timeout no significa /data desmontada'
Assert-True ($null -eq $r.VendorReadable) 'salida vacia no demuestra vendor inaccesible'
Assert-True ($r.Findings.Code -notcontains 'TEE_NOT_RUNNING') 'timeout no demuestra daemon ausente'
Assert-True ($null -eq $r.F2fsSupported) 'fallo no significa falta de f2fs'
Write-Host 'PASS: errores de recopilacion quedan como desconocidos'

$fixture = Get-Fixture
$fixture['mounts'] = "EXIT_CODE=0`ntmpfs /data tmpfs rw 0 0`n/dev/block/dm-39 /storage/emulated/0/Android/obb f2fs rw 0 0"
$r = Get-TB300FUAnalysis $fixture
Assert-True ($r.DataMounted -eq $false) 'tmpfs y subruta no cuentan como userdata montada'
$r = Get-TB300FUAnalysis @{}
Assert-True ($r.Findings.Code -contains 'IDENTITY_UNVERIFIED') 'carpeta vacia no produce diagnostico seguro'
Assert-True ($null -eq $r.DataMounted) 'archivo ausente es desconocido'
Write-Host 'PASS: entradas vacias y montajes ajenos'

$fixture = Get-Fixture
$fixture['identity'] = "EXIT_CODE=0`nOTHER_DEVICE"
$r = Get-TB300FUAnalysis $fixture
Assert-True ($r.Findings.Code -contains 'IDENTITY_UNVERIFIED') 'rechaza identidad diferente'
Assert-True ($r.Findings.Code -notcontains 'METADATA_SOURCE_WRONG') 'no aplica layout TB300FU a otro dispositivo'
Write-Host 'PASS: identidad protegida'

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('TB300FU-analyzer-test-' + [guid]::NewGuid().ToString('N'))
$createdPaths = @()
try {
    [void](New-Item -ItemType Directory -Path $testDirectory)
    $fixture = Get-Fixture
    foreach ($name in $fixture.Keys) {
        $fixturePath = Join-Path $testDirectory ($name + '.txt')
        [IO.File]::WriteAllText($fixturePath, $fixture[$name], (New-Object Text.UTF8Encoding($false)))
        $createdPaths += $fixturePath
    }
    $before = @(Get-ChildItem -LiteralPath $testDirectory -File | Get-FileHash | Select-Object -ExpandProperty Hash)
    $json = & $analyzer -ReportDirectory $testDirectory -AsJson
    $cliResult = $json | ConvertFrom-Json
    Assert-True ($cliResult.Findings.Code -contains 'METADATA_MAPPING_MISSING') 'CLI lee los archivos reales'
    $textResult = (& $analyzer -ReportDirectory $testDirectory) -join "`n"
    Assert-True ($textResult -match 'METADATA_MAPPING_MISSING') 'salida legible conserva hallazgos'
    $after = @(Get-ChildItem -LiteralPath $testDirectory -File | Get-FileHash | Select-Object -ExpandProperty Hash)
    Assert-True (($before -join ',') -eq ($after -join ',')) 'evaluador no modifica los informes'
} finally {
    # Remove only the exact generated files, then the empty generated directory.
    foreach ($fixturePath in $createdPaths) { Remove-Item -LiteralPath $fixturePath }
    if (Test-Path -LiteralPath $testDirectory) { Remove-Item -LiteralPath $testDirectory }
}
Write-Host 'PASS: CLI local JSON y texto sin escrituras'

Write-Host 'Todas las pruebas del evaluador pasaron.'
