param([ValidateSet('run','check','test','package')][string]$Action = 'run')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw 'Install Rust stable with rustup, then reopen Developer PowerShell.'
}
git submodule update --init -- ../toolchain/nsh
if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the pinned NSH source' }
Push-Location ../toolchain/nsh
try {
    cargo build --locked -p nsh-cli
    if ($LASTEXITCODE -ne 0) { throw 'Could not build NSH' }
} finally { Pop-Location }
$nsh = Join-Path (Get-Location) '../toolchain/nsh/target/debug/nsh.exe'
if ($Action -eq 'check') { & $nsh check App.tsx }
elseif ($Action -eq 'test') {
    $oldLibrary = $env:STILL_LIBRARY_DIR
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("still-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    try {
        $env:STILL_LIBRARY_DIR = Join-Path $testRoot 'headless'
        & $nsh test App.test.tsx
        if ($LASTEXITCODE -ne 0) { throw 'Headless import and playback tests failed' }
        $env:STILL_LIBRARY_DIR = Join-Path $testRoot 'win32'
        & $nsh test Windows.test.tsx --target windows
        if ($LASTEXITCODE -ne 0) { throw 'Win32 toolbar test failed' }
    } finally {
        $env:STILL_LIBRARY_DIR = $oldLibrary
        Remove-Item -Recurse -Force -LiteralPath $testRoot
    }
}
else { & $nsh $Action App.tsx --target windows }
if ($LASTEXITCODE -ne 0) { throw "NSH failed with exit code $LASTEXITCODE" }
