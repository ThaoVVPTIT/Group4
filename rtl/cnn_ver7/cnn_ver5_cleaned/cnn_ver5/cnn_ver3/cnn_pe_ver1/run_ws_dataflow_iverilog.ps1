$ErrorActionPreference = 'Stop'

$projectDir = $PSScriptRoot
$rtlDir = Join-Path $projectDir 'cnn_pe_ver1.srcs\sources_1\new'
$tbFile = Join-Path $projectDir 'cnn_pe_ver1.srcs\sim_1\new\tb_ws_dataflow.v'
$simOut = Join-Path ([System.IO.Path]::GetTempPath()) 'tb_ws_dataflow.vvp'

$iverilogCmd = Get-Command iverilog -ErrorAction SilentlyContinue
$vvpCmd = Get-Command vvp -ErrorAction SilentlyContinue

if (-not $iverilogCmd) {
    $fallbackIverilog = 'E:\iverilog\iverilog\bin\iverilog.exe'
    if (Test-Path -LiteralPath $fallbackIverilog) {
        $iverilogExe = $fallbackIverilog
    } else {
        throw 'iverilog was not found in PATH or the local fallback location.'
    }
} else {
    $iverilogExe = $iverilogCmd.Source
}

if (-not $vvpCmd) {
    $fallbackVvp = 'E:\iverilog\iverilog\bin\vvp.exe'
    if (Test-Path -LiteralPath $fallbackVvp) {
        $vvpExe = $fallbackVvp
    } else {
        throw 'vvp was not found in PATH or the local fallback location.'
    }
} else {
    $vvpExe = $vvpCmd.Source
}

$rtlFiles = Get-ChildItem -LiteralPath $rtlDir -Filter '*.v' |
    ForEach-Object { $_.FullName }

& $iverilogExe -g2001 -Wall -s tb_ws_dataflow -o $simOut $rtlFiles $tbFile
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $vvpExe $simOut
exit $LASTEXITCODE

