param(
    [switch]$StopOnFailure,
    [string]$Pattern = 'test-*.ps1',
    [string]$Dir = '.',
    [string]$LogDir = '.\test-logs'
)

# Ensure log directory exists
if (-not (Test-Path -Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# Find test files
$tests = Get-ChildItem -Path $Dir -Filter $Pattern -File -Recurse | Sort-Object FullName
if (-not $tests) {
    Write-Host "No test files found matching pattern '$Pattern' in '$Dir'"
    exit 0
}

$results = @()

foreach ($t in $tests) {
    $name = $t.Name
    $log = Join-Path $LogDir ($name + '.log')
    Write-Host "=== Running $name ==="

    # Run each test in a clean PowerShell process so $LASTEXITCODE is reliable
    $cmd = @(
        'powershell',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $t.FullName
    )

    # Start-Process with redirect doesn't capture combined output easily; use & and redirect
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $t.FullName *> $log
        $exit = $LASTEXITCODE
    } catch {
        # On unexpected error, write it to log and mark failure
        $_ | Out-String | Out-File -FilePath $log -Append
        $exit = 1
    }

    if ($exit -ne 0) {
        Write-Host "FAIL: $name (exit code $exit) - log: $log" -ForegroundColor Red
    } else {
        Write-Host "OK:   $name" -ForegroundColor Green
    }

    $results += [pscustomobject]@{ Name = $name; ExitCode = $exit; Log = (Resolve-Path $log).Path }

    if ($StopOnFailure -and $exit -ne 0) { break }
}

# Summary
Write-Host "`n=== Test summary ==="
# Ensure ExitCode is treated as integer when checking failures
$failed = $results | Where-Object { ([int]$_.ExitCode) -ne 0 }
if ($failed.Count -gt 0) {
    Write-Host "Failed tests: $($failed.Count)" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "{0} -> Exit {1} | Log: {2}" -f $_.Name, $_.ExitCode, $_.Log }
    # return non-zero so CI can detect failure
    exit 1
} else {
    Write-Host "All tests passed: $($results.Count)" -ForegroundColor Green
    exit 0
}
