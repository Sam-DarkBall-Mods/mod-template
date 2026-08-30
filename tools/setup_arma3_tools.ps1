$ErrorActionPreference = "Stop"

$toolsRepository = "Sam-DarkBall-Mods/build-assets"
$toolsTag = "arma3-tools-2026-08"
$toolsAsset = "arma3-tools.zip"
$toolsSha256 = "9146a385ee16cf0cc983c88e12e52540417725c597f426929d14f62fea35a091"
$registryUrl = "https://raw.githubusercontent.com/arma-actions/arma3-tools/7a1666b84a58503702f56319d8ffa975ec8a463e/arma3tools.reg"
$registrySha256 = "f8443c98233e6611ccc46265d06d02558e8c25796d38224b236b2805cd8cc708"
$toolsRoot = "C:\arma3tools"
$downloadRoot = Join-Path $env:RUNNER_TEMP "arma3tools-setup"
$archivePath = Join-Path $downloadRoot $toolsAsset
$registryPath = Join-Path $downloadRoot "arma3tools.reg"

if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    throw "GH_TOKEN is required to download private Arma 3 Tools"
}
if (Test-Path $toolsRoot) {
    throw "$toolsRoot already exists"
}

New-Item -ItemType Directory -Path $downloadRoot | Out-Null

try {
    & gh release download $toolsTag `
        --repo $toolsRepository `
        --pattern $toolsAsset `
        --dir $downloadRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download Arma 3 Tools"
    }
    $env:GH_TOKEN = $null

    $archiveHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $toolsSha256) {
        throw "Arma 3 Tools SHA-256 mismatch"
    }

    Expand-Archive -Path $archivePath -DestinationPath $toolsRoot

    $requiredFiles = @(
        "AddonBuilder\AddonBuilder.exe",
        "Binarize\binarize.exe",
        "BinMake\binMake.exe",
        "CfgConvert\CfgConvert.exe",
        "DSSignFile\DSSignFile.exe"
    )
    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path (Join-Path $toolsRoot $relativePath))) {
            throw "Missing Arma 3 Tools file: $relativePath"
        }
    }

    Invoke-WebRequest $registryUrl -OutFile $registryPath
    $registryHash = (Get-FileHash $registryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($registryHash -ne $registrySha256) {
        throw "Arma 3 Tools registry SHA-256 mismatch"
    }

    & reg.exe import $registryPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to import Arma 3 Tools registry settings"
    }

    $rulesPath = Join-Path $toolsRoot "BinMake\binMakeRules.txt"
    (Get-Content $rulesPath) `
        -replace 'O:\\Arma3CommunityTools', $toolsRoot |
        Set-Content $rulesPath

    & choco install directx --yes --no-progress
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install DirectX runtime"
    }
}
finally {
    $env:GH_TOKEN = $null
    Remove-Item $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue
}
