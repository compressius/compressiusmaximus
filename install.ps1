# CompressiusMaximus (cmx) installer for Windows (PowerShell).
# Downloads the release archive from the distribution host, verifies the
# checksum and installs a single static binary.
#
#   $env:CMX_DIST_URL = "https://dl.example.com"; irm <installer-url> | iex
$ErrorActionPreference = "Stop"

$Dest = if ($env:CMX_INSTALL_DIR) { $env:CMX_INSTALL_DIR } else { "$env:USERPROFILE\.local\bin" }
$Base = if ($env:CMX_DIST_URL) { $env:CMX_DIST_URL.TrimEnd('/') } else { "https://github.com/compressius/compressiusmaximus/releases/latest/download" }

$GOOS = "windows"
$GOARCH = switch ($env:PROCESSOR_ARCHITECTURE) {
    "ARM64" { "arm64" }
    default { "amd64" }
}
$Asset = "cmx_${GOOS}_${GOARCH}.tar.gz"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cmx-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$Interactive = [Environment]::UserInteractive -and -not [Console]::IsOutputRedirected

function Write-Stage([string]$Message, [int]$Percent) {
    if ($Interactive) {
        Write-Progress -Activity "Installing CMX" -Status $Message -PercentComplete $Percent
    }
    Write-Host "`n==> $Message"
}

function Download-File([string]$Uri, [string]$OutFile, [hashtable]$Headers) {
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -Headers $Headers -UseBasicParsing
}

New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
try {
    $Url = "$Base/$Asset"
    Write-Stage "Downloading CMX" 10
    $Headers = @{}
    if ($env:CMX_GITHUB_TOKEN) { $Headers["Authorization"] = "Bearer $($env:CMX_GITHUB_TOKEN)" }
    Download-File $Url "$Tmp\$Asset" $Headers
    if ($Interactive) { Write-Progress -Activity "Installing CMX" -Status "Download complete" -PercentComplete 30 }

    Write-Stage "Verifying download" 40
    Download-File "$Base/latest.json" "$Tmp\latest.json" @{}
    $manifest = Get-Content "$Tmp\latest.json" -Raw | ConvertFrom-Json
    $want = ($manifest.files | Where-Object { $_.os -eq $GOOS -and $_.arch -eq $GOARCH }).sha256
    if (-not $want -or $want -notmatch '^[a-fA-F0-9]{64}$') {
        throw "manifest has no valid checksum for $Asset"
    }
    $got = (Get-FileHash "$Tmp\$Asset" -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $want.ToLower()) { throw "checksum mismatch ($got != $want)" }
    if ($Interactive) { Write-Progress -Activity "Installing CMX" -Status "Checksum verified" -PercentComplete 65 }
    Write-Host "    checksum verified"

    Write-Stage "Installing CMX" 75
    tar -xzf "$Tmp\$Asset" -C $Tmp
    $Bin = Get-ChildItem -Path $Tmp -Recurse -Filter "cmx.exe" | Select-Object -First 1
    if (-not $Bin) { throw "binary not found in archive" }

    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    Copy-Item $Bin.FullName "$Dest\cmx.exe" -Force
}
finally { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }

$Command = "cmx"
if (($env:Path -split ";") -notcontains $Dest) {
    $Command = "$Dest\cmx.exe"
}

$GatewayState = "not started"
Write-Stage "Starting gateway" 90
if ($env:CMX_SKIP_START -eq "1") {
    $GatewayState = "not started (skipped)"
    Write-Host "    skipped (CMX_SKIP_START=1)"
}
else {
    & "$Dest\cmx.exe" start
    if ($LASTEXITCODE -eq 0) {
        $GatewayState = "running"
        Write-Host "    gateway running"
    }
    else {
        $GatewayState = "not running (start failed)"
        Write-Warning "Gateway did not start; run '$Dest\cmx.exe start' after installation."
    }
}

if ($Interactive) {
    Write-Progress -Activity "Installing CMX" -Status "Installation complete" -PercentComplete 100
    Write-Progress -Activity "Installing CMX" -Completed
}
Write-Host ""
Write-Host "╭─ CMX installed ─────────────────────────────────"
Write-Host "│ Installed: $Dest\cmx.exe"
Write-Host "│ Gateway:   $GatewayState"
Write-Host "│ Open TUI:  $Command"
Write-Host "│ Helpful:   $Command status · $Command setup · $Command help"
Write-Host "╰────────────────────────────────────────────────"
if ($Command -ne "cmx") {
    Write-Host "Add CMX to PATH, then restart PowerShell: `$env:Path = `"$Dest;`$env:Path`""
}
