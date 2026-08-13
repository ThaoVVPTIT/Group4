param(
    [switch]$SkipStructural,
    [switch]$SkipRealWeights
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$rtlDir = Join-Path $projectRoot "cnn_pe_ver1.srcs\sources_1\new"
$tbDir = Join-Path $projectRoot "cnn_pe_ver1.srcs\sim_1\new"
$rtlFiles = @(Get-ChildItem -LiteralPath $rtlDir -Filter *.v | ForEach-Object { $_.FullName })

if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) {
    throw "iverilog is not available on PATH"
}
if (-not (Get-Command vvp -ErrorAction SilentlyContinue)) {
    throw "vvp is not available on PATH"
}

function Invoke-IverilogRegression {
    param(
        [string]$Top,
        [string]$Testbench,
        [string[]]$RuntimeArgs = @()
    )

    $output = Join-Path $env:TEMP (
        "cnn_ver5_{0}_{1}.vvp" -f $Top, [guid]::NewGuid().ToString("N"))
    try {
        & iverilog -g2012 -Wall -s $Top -o $output $rtlFiles $Testbench
        if ($LASTEXITCODE -ne 0) {
            throw "iverilog compile failed for $Top"
        }

        Push-Location $projectRoot
        try {
            & vvp $output @RuntimeArgs
            if ($LASTEXITCODE -ne 0) {
                throw "vvp regression failed for $Top $($RuntimeArgs -join ' ')"
            }
        } finally {
            Pop-Location
        }
    } finally {
        if (Test-Path -LiteralPath $output) {
            Remove-Item -LiteralPath $output -Force
        }
    }
}

Write-Host "[1/3] Focused convolution numerical/backpressure regression"
Invoke-IverilogRegression -Top "tb_ws_dataflow" `
    -Testbench (Join-Path $tbDir "tb_ws_dataflow.v")

if (-not $SkipStructural) {
    Write-Host "[2/3] End-to-end scheduler/AXI structural regression"
    Invoke-IverilogRegression -Top "tb_axis_cnn" `
        -Testbench (Join-Path $tbDir "tb_axis_cnn.v")
}

if (-not $SkipRealWeights) {
    Write-Host "[3/3] End-to-end real-weight numerical regression"
    Invoke-IverilogRegression -Top "tb_axis_cnn" `
        -Testbench (Join-Path $tbDir "tb_axis_cnn.v") `
        -RuntimeArgs @("+REAL_WEIGHTS")
}

Write-Host "cnn_ver5 regression suite: PASS"
