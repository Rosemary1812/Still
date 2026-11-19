param([ValidateSet('run','check','test','package')][string]$Action = 'run')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Get-Command nsh -ErrorAction SilentlyContinue)) {
    throw 'Install NSH v0.5.0 first. See README.md.'
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw 'Install Rust stable with rustup, then reopen Developer PowerShell.'
}
$version = (& nsh --version) -join ' '
if ($version -notmatch '0\.5\.0') { throw "Expected NSH 0.5.0, got $version" }
if ($Action -eq 'check') { & nsh check App.tsx }
elseif ($Action -eq 'test') {
    $oldLibrary = $env:STILL_LIBRARY_DIR
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("still-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    try {
        $env:STILL_LIBRARY_DIR = Join-Path $testRoot 'headless'
        & nsh test App.test.tsx
        if ($LASTEXITCODE -ne 0) { throw 'Headless import and playback tests failed' }
        $env:STILL_LIBRARY_DIR = Join-Path $testRoot 'win32'
        & nsh test Windows.test.tsx --target windows
        if ($LASTEXITCODE -ne 0) { throw 'Win32 toolbar test failed' }
    } finally {
        $env:STILL_LIBRARY_DIR = $oldLibrary
        Remove-Item -Recurse -Force -LiteralPath $testRoot
    }
}
else { & nsh $Action App.tsx --target windows }
if ($LASTEXITCODE -ne 0) { throw "NSH failed with exit code $LASTEXITCODE" }
