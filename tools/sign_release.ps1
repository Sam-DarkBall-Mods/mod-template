$ErrorActionPreference = "Stop"

$releaseRoot = Join-Path $PWD ".hemttout\release"
$toolsRoot = "C:\arma3tools"
$dssign = Join-Path $toolsRoot "DSSignFile\DSSignFile.exe"
$privateKeyPath = Join-Path $env:RUNNER_TEMP "release.biprivatekey"
$publicKeyPath = Join-Path $env:RUNNER_TEMP "release.bikey"

if (-not (Test-Path $releaseRoot)) {
    throw "HEMTT release folder not found"
}
if (-not (Test-Path $dssign)) {
    throw "DSSignFile.exe not found in Arma 3 Tools"
}
if ([string]::IsNullOrWhiteSpace($env:BI_PRIVATE_KEY_B64)) {
    throw "BI_PRIVATE_KEY_B64 is required"
}
if ([string]::IsNullOrWhiteSpace($env:BI_PUBLIC_KEY_B64)) {
    throw "BI_PUBLIC_KEY_B64 is required"
}

try {
    [IO.File]::WriteAllBytes(
        $privateKeyPath,
        [Convert]::FromBase64String($env:BI_PRIVATE_KEY_B64.Trim())
    )
    [IO.File]::WriteAllBytes(
        $publicKeyPath,
        [Convert]::FromBase64String($env:BI_PUBLIC_KEY_B64.Trim())
    )

    $inspection = (& hemtt utils inspect $publicKeyPath 2>&1 | Out-String)
    $authorityMatch = [regex]::Match(
        $inspection,
        "(?m)^\s*-\s*Authority:\s*(\S+)\s*$"
    )
    if (-not $authorityMatch.Success) {
        throw "Could not read authority from BI public key"
    }

    $authority = $authorityMatch.Groups[1].Value
    $publicKeyName = "$authority.bikey"

    $rootKeys = Join-Path $releaseRoot "keys"
    New-Item -ItemType Directory -Force -Path $rootKeys | Out-Null
    Copy-Item $publicKeyPath (Join-Path $rootKeys $publicKeyName) -Force

    $optionalsRoot = Join-Path $releaseRoot "optionals"
    if (Test-Path $optionalsRoot) {
        Get-ChildItem $optionalsRoot -Directory | ForEach-Object {
            $keys = Join-Path $_.FullName "keys"
            New-Item -ItemType Directory -Force -Path $keys | Out-Null
            Copy-Item $publicKeyPath (Join-Path $keys $publicKeyName) -Force
        }
    }

    $pbos = @(Get-ChildItem $releaseRoot -Recurse -Filter "*.pbo")
    if ($pbos.Count -eq 0) {
        throw "No release PBOs found"
    }

    foreach ($pbo in $pbos) {
        Get-ChildItem "$($pbo.FullName).*bisign" -ErrorAction SilentlyContinue |
            Remove-Item -Force

        & $dssign $privateKeyPath $pbo.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "DSSignFile failed for $($pbo.Name)"
        }

        $signature = Get-ChildItem "$($pbo.FullName).*bisign" |
            Select-Object -First 1
        if ($null -eq $signature) {
            throw "DSSignFile did not create a signature for $($pbo.Name)"
        }

        hemtt utils verify $pbo.FullName $publicKeyPath
        if ($LASTEXITCODE -ne 0) {
            throw "Signature verification failed for $($pbo.Name)"
        }
    }

    Write-Host "Signed $($pbos.Count) PBO(s) with $authority"
}
finally {
    Remove-Item $privateKeyPath -Force -ErrorAction SilentlyContinue
    Remove-Item $publicKeyPath -Force -ErrorAction SilentlyContinue
}
