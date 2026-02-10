#Requires -Version 5.1
param(
    [int]$Threads   = 50,
    [int]$RampUp    = 10,
    [int]$Duration  = 60
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir

# Prevent MSYS/Git Bash from mangling Linux paths (e.g. /tests/ -> C:/Program Files/Git/tests/)
$env:MSYS_NO_PATHCONV = "1"

$ResultsDir  = Join-Path $ScriptDir "results"
$ReportIndex = Join-Path $ResultsDir "html_report\index.html"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  TCC Microservices Benchmark Runner" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Threads:  $Threads"
Write-Host "  Ramp-Up:  ${RampUp}s"
Write-Host "  Duration: ${Duration}s per group (x3 groups = $($Duration * 3)s total)"
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------
# 1. Clean up previous results
# -----------------------------------------------
Write-Host "[1/5] Cleaning previous results..." -ForegroundColor Yellow

if (Test-Path $ResultsDir) {
    Remove-Item $ResultsDir -Recurse -Force
    Write-Host "      Deleted existing results/ folder."
}

New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
Write-Host "      Created empty results/ folder." -ForegroundColor Green

# -----------------------------------------------
# 2. Build and start infrastructure
# -----------------------------------------------
Write-Host ""
Write-Host "[2/5] Building and starting infrastructure..." -ForegroundColor Yellow

docker-compose up --build -d rabbitmq processing-service api-gateway
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: docker-compose up failed." -ForegroundColor Red
    exit 1
}

Write-Host "      Containers started. Waiting for services to stabilize..." -ForegroundColor Green

# -----------------------------------------------
# 3. Wait for services to be healthy
# -----------------------------------------------
Write-Host ""
Write-Host "[3/5] Waiting for services to be ready..." -ForegroundColor Yellow

$MaxRetries = 30
$RetryCount = 0
$Ready = $false

while (-not $Ready -and $RetryCount -lt $MaxRetries) {
    $RetryCount++
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:5000/swagger/index.html" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $Ready = $true
        }
    }
    catch {
        Write-Host "      Attempt $RetryCount/$MaxRetries - API Gateway not ready yet, retrying in 3s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
    }
}

if (-not $Ready) {
    Write-Host "ERROR: API Gateway did not become ready in time." -ForegroundColor Red
    Write-Host "       Check logs with: docker-compose logs api-gateway" -ForegroundColor Red
    exit 1
}

Write-Host "      All services are UP and responding." -ForegroundColor Green

# -----------------------------------------------
# 4. Run JMeter benchmark
# -----------------------------------------------
Write-Host ""
Write-Host "[4/5] Running JMeter benchmark..." -ForegroundColor Yellow
Write-Host "      This will take ~$($Duration * 3) seconds (3 groups x ${Duration}s each)." -ForegroundColor DarkGray
Write-Host ""

docker-compose --profile benchmark run --rm `
    jmeter `
    -n `
    -t /tests/tcc_benchmark.jmx `
    -JBASE_HOST=api-gateway `
    -JBASE_PORT=5000 `
    "-JTHREADS=$Threads" `
    "-JRAMP_UP=$RampUp" `
    "-JDURATION=$Duration" `
    -l /results/raw_results.jtl `
    -e -o /results/html_report

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "WARNING: JMeter exited with code $LASTEXITCODE." -ForegroundColor Red
    Write-Host "         Check results/raw_results.jtl for details." -ForegroundColor Red
}

# -----------------------------------------------
# 5. Open report
# -----------------------------------------------
Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "  Benchmark Finished!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

if (Test-Path $ReportIndex) {
    Write-Host "[5/5] Opening HTML report in browser..." -ForegroundColor Yellow
    Start-Process $ReportIndex
    Write-Host ""
    Write-Host "Results saved at:" -ForegroundColor Cyan
    Write-Host "  Raw data:    results\raw_results.jtl"
    Write-Host "  HTML report: results\html_report\index.html"
}
else {
    Write-Host "[5/5] HTML report not found at: $ReportIndex" -ForegroundColor Red
    Write-Host "      Check JMeter output above for errors." -ForegroundColor Red
}

Write-Host ""