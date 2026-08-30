$ErrorActionPreference = "Stop"

$toolsRepository = "Sam-DarkBall-Mods/build-assets"
$toolsTag = "arma3-tools-2026-08"
$toolsAsset = "arma3-tools.zip"
$toolsSha256 = "9146a385ee16cf0cc983c88e12e52540417725c597f426929d14f62fea35a091"
$referenceAsset = "arma3-reference-2026-08.zip"
$referenceSha256 = "a7a5f7560b0d967f56a741e62d4b71747b1c383619867e562892906171718527"
$registryUrl = "https://raw.githubusercontent.com/arma-actions/arma3-tools/7a1666b84a58503702f56319d8ffa975ec8a463e/arma3tools.reg"
$registrySha256 = "d0f1f01a8d2c3208fe925934db97d3d945e1996f1d38f28d021e74a87d19c334"
$toolsRoot = "C:\arma3tools"
$projectRoot = Split-Path $PSScriptRoot -Parent
$downloadRoot = Join-Path $env:RUNNER_TEMP "arma3tools-setup"
$archivePath = Join-Path $downloadRoot $toolsAsset
$referencePath = Join-Path $downloadRoot $referenceAsset
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

    & gh release download $toolsTag `
        --repo $toolsRepository `
        --pattern $referenceAsset `
        --dir $downloadRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download Arma 3 reference data"
    }
    $env:GH_TOKEN = $null

    $archiveHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $toolsSha256) {
        throw "Arma 3 Tools SHA-256 mismatch"
    }

    $referenceHash = (Get-FileHash $referencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($referenceHash -ne $referenceSha256) {
        throw "Arma 3 reference data SHA-256 mismatch"
    }

    Expand-Archive -Path $archivePath -DestinationPath $toolsRoot
    Expand-Archive -Path $referencePath -DestinationPath $projectRoot

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

    $requiredReferenceFiles = @(
        "a3\air_f_heli\heli_transport_04\data\heli_transport_04_glass.rvmat",
        "a3\air_f_heli\heli_transport_04\data\heli_transport_04_glass_ca.paa",
        "a3\data_f\default_alpha.rvmat",
        "a3\data_f\destruct\default_destruct_exterior.rvmat",
        "a3\data_f\inter_opt.rvmat",
        "a3\data_f\penetration\metal.rvmat",
        "a3\data_f\penetration\metal_plate.rvmat",
        "a3\data_f\penetration\metal_plate_thin.rvmat",
        "a3\data_f\penetration\plastic.rvmat",
        "a3\data_f\penetration\tyre.rvmat",
        "a3\soft_f_orange\van_02\data\van_tire_cover.rvmat",
        "a3\soft_f_orange\van_02\data\van_tire_cover_co.paa",
        "a3\weapons_f\reticle\data\optics_lcd_ca.paa"
    )
    foreach ($relativePath in $requiredReferenceFiles) {
        if (-not (Test-Path (Join-Path $projectRoot $relativePath))) {
            throw "Missing Arma 3 reference file: $relativePath"
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
