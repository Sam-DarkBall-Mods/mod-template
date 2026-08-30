$ErrorActionPreference = "Stop"

$releaseRoot = Join-Path $PWD ".hemttout\release"
$toolsRoot = "C:\arma3tools"
$dssign = Join-Path $toolsRoot "DSSignFile\DSSignFile.exe"
$privateKeyPath = Join-Path $env:RUNNER_TEMP "release.biprivatekey"
$publicKeys = @(Get-ChildItem (Join-Path $PWD "keys") -File -Filter "*.bikey" -ErrorAction SilentlyContinue)

if (-not (Test-Path $releaseRoot)) {
    throw "HEMTT release folder not found"
}
if (-not (Test-Path $dssign)) {
    throw "DSSignFile.exe not found in Arma 3 Tools"
}
if ([string]::IsNullOrWhiteSpace($env:BI_PRIVATE_KEY_B64)) {
    throw "BI_PRIVATE_KEY_B64 is required"
}
if ($publicKeys.Count -ne 1) {
    throw "Exactly one committed public key is required in keys"
}

try {
    [IO.File]::WriteAllBytes(
        $privateKeyPath,
        [Convert]::FromBase64String($env:BI_PRIVATE_KEY_B64.Trim())
    )
    $env:BI_PRIVATE_KEY_B64 = $null

    $publicKeyPath = $publicKeys[0].FullName
    $releaseKeyDirectories = @((Join-Path $releaseRoot "keys"))
    $optionalsRoot = Join-Path $releaseRoot "optionals"
    if (Test-Path $optionalsRoot) {
        $releaseKeyDirectories += @(Get-ChildItem $optionalsRoot -Directory | ForEach-Object {
            Join-Path $_.FullName "keys"
        })
    }

    foreach ($releaseKeysRoot in $releaseKeyDirectories) {
        $releaseKeyPath = Join-Path $releaseKeysRoot $publicKeys[0].Name
        New-Item -ItemType Directory -Force -Path $releaseKeysRoot | Out-Null
        if (Test-Path $releaseKeyPath) {
            if ((Get-FileHash $publicKeyPath).Hash -ne (Get-FileHash $releaseKeyPath).Hash) {
                throw "Release public key differs from the committed public key"
            }
        } else {
            Copy-Item $publicKeyPath $releaseKeyPath
        }
        $releasePublicKeys = @(Get-ChildItem $releaseKeysRoot -File -Filter "*.bikey")
        if ($releasePublicKeys.Count -ne 1) {
            throw "Exactly one public key is required in $releaseKeysRoot"
        }
    }

    $releasePublicKeyPath = Join-Path $releaseKeyDirectories[0] $publicKeys[0].Name
    $inspection = (& hemtt utils inspect $releasePublicKeyPath 2>&1 | Out-String)
    $authorityMatch = [regex]::Match(
        $inspection,
        "(?m)^\s*-\s*Authority:\s*(\S+)\s*$"
    )
    if (-not $authorityMatch.Success) {
        throw "Could not read authority from BI public key"
    }

    $authority = $authorityMatch.Groups[1].Value

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

        hemtt utils verify $pbo.FullName $releasePublicKeyPath
        if ($LASTEXITCODE -ne 0) {
            throw "Signature verification failed for $($pbo.Name)"
        }
    }

    Write-Host "Signed $($pbos.Count) PBO(s) with $authority"
}
finally {
    $env:BI_PRIVATE_KEY_B64 = $null
    Remove-Item $privateKeyPath -Force -ErrorAction SilentlyContinue
}
