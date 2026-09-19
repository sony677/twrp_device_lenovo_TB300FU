Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'scripts/Collect-TB300FU.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
. $script

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $caught = $false
    try { & $Action | Out-Null } catch { $caught = $true }
    Assert-True $caught $Message
}
$nl = [Environment]::NewLine
$deviceList = "List of devices attached" + $nl + "HGR4G667 recovery product:twrp_TB300FU" + $nl
Assert-True ((Select-AdbTarget $deviceList '').Serial -eq 'HGR4G667') 'Single recovery selection failed.'
Assert-Throws { Select-AdbTarget ("List of devices attached" + $nl) '' } 'No device must fail promptly.'
Assert-Throws { Select-AdbTarget ("A device" + $nl + "B recovery") '' } 'Multiple devices must require selection.'
Assert-Throws { Select-AdbTarget "A unauthorized" 'A' } 'Unauthorized device must fail.'
Assert-Throws { Select-AdbTarget "A sideload" 'A' } 'Sideload does not allow shell collection.'
Assert-True ((Select-AdbTarget ("A device" + $nl + "B recovery") 'B').Serial -eq 'B') 'Explicit serial selection failed.'

foreach ($item in (Get-TB300FUReadPlan)) {
    Assert-True ($item.Command -notmatch '(?i)(^|[;|&]\s*)(dd|rm|mkfs\S*|mount|umount|setprop|reboot|start|stop)\s') ('Mutating command in plan: ' + $item.Name)
    Assert-True ($item.Command -notmatch '(?i)(cat|find|ls|readelf)\s+(?:-[^\s]+\s+)*(/data(?:/|\s|$)|/metadata(?:/|\s|$))') 'Private data/key read in plan.'
}

# Test actual Windows argument transport, not just the quoting implementation.
$python = (Get-Command python -CommandType Application | Select-Object -First 1).Source
$expected = @('a b', 'literal $HOME $(oops)', 'quote"here', 'C:\folder with spaces\', '', 'ascii')
$pythonArgs = @('-c', 'import json,sys; print(json.dumps(sys.argv[1:]))') + $expected
$r = Invoke-TimedProcess -Program $python -Arguments $pythonArgs -Seconds 10
Assert-True ($r.ExitCode -eq 0) ('Native argv test failed: ' + $r.Stderr)
$decoded = ConvertFrom-Json -InputObject $r.Stdout
$actual = @($decoded)
Assert-True ($actual.Count -eq $expected.Count) 'Argument count changed.'
for ($i = 0; $i -lt $expected.Count; $i++) {
    Assert-True ($actual[$i] -ceq $expected[$i]) ('Argument changed at index ' + $i)
}
$r = Invoke-TimedProcess -Program $python -Arguments @('-c', 'import time; time.sleep(10)') -Seconds 1
Assert-True ($r.ExitCode -eq 124) 'Timeout did not stop the child.'

# Exercise the same native runner used by the command-line entry point.
$nativeRunner = {
    param([string[]]$AdbArguments)
    Invoke-TimedProcess -Program $python -Arguments $AdbArguments -Seconds 10
}
$r = & $nativeRunner @('-c', 'print("runner-ok")')
Assert-True ($r.ExitCode -eq 0 -and $r.Stdout.Trim() -eq 'runner-ok') 'Native runner failed.'

# Fake ADB: exercise the entire collector without hardware or key material.
$state = @{ Calls = New-Object 'System.Collections.Generic.List[object]' }
$runner = {
    param([string[]]$AdbArguments)
    $state.Calls.Add($AdbArguments)
    if ($AdbArguments[0] -eq 'devices') {
        return [pscustomobject]@{ ExitCode=0; Stdout=("List of devices attached" + [Environment]::NewLine + "HGR4G667 recovery"); Stderr='' }
    }
    if ($AdbArguments[-1] -eq 'getprop ro.product.device') {
        return [pscustomobject]@{ ExitCode=0; Stdout="TB300FU"; Stderr='' }
    }
    return [pscustomobject]@{ ExitCode=1; Stdout=''; Stderr='Unavailable in mock recovery' }
}.GetNewClosure()
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('tb300fu-test-' + [guid]::NewGuid().ToString('N'))
$report = Collect-TB300FUEvidence -RequestedSerial '' -Destination $tempDir -RunAdb $runner
Assert-True (Test-Path (Join-Path $report 'commands.json')) 'Missing report index.'
Assert-True (Test-Path (Join-Path $report 'vendor-services.txt')) 'Partial failures lost the evidence files.'
Assert-True ((Get-Content (Join-Path $report 'vendor-services.txt') -Raw) -match 'EXIT_CODE=1') 'Partial error was not recorded.'
Assert-Throws { Collect-TB300FUEvidence -Destination $tempDir -RunAdb $runner } 'Existing reports must not be overwritten.'
foreach ($call in $state.Calls) {
    Assert-True ($call[0] -eq 'devices' -or ($call[0] -eq '-s' -and $call[1] -eq 'HGR4G667' -and $call[2] -eq 'shell')) 'Unexpected ADB operation.'
}
$wrongRunner = {
    param([string[]]$AdbArguments)
    if ($AdbArguments[0] -eq 'devices') {
        return [pscustomobject]@{ ExitCode=0; Stdout="A device"; Stderr='' }
    }
    return [pscustomobject]@{ ExitCode=0; Stdout="SOME_OTHER_DEVICE"; Stderr='' }
}
$wrongDir = Join-Path ([IO.Path]::GetTempPath()) ('tb300fu-wrong-' + [guid]::NewGuid().ToString('N'))
Assert-Throws { Collect-TB300FUEvidence -Destination $wrongDir -RunAdb $wrongRunner } 'Wrong model must stop collection.'
Assert-True (-not (Test-Path $wrongDir)) 'Wrong model created an evidence directory.'
Write-Host 'Collector tests passed: selection, quoting, timeout, partial errors, no overwrite, wrong-model rejection.'
