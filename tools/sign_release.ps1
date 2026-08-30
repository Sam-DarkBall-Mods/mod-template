$ErrorActionPreference = "Stop"

$releaseRoot = Join-Path $PWD ".hemttout\release"
$toolsRoot = "C:\arma3tools"
$dssign = Join-Path $toolsRoot "DSSignFile\DSSignFile.exe"
$signingConfigPath = Join-Path $PWD "tools\signing.json"
$privateKeysRoot = Join-Path $env:RUNNER_TEMP "release-private-keys"

if (-not (Test-Path $releaseRoot)) {
    throw "HEMTT release folder not found"
}
if (-not (Test-Path $dssign)) {
    throw "DSSignFile.exe not found in Arma 3 Tools"
}
if (-not (Test-Path $signingConfigPath)) {
    throw "tools/signing.json not found"
}
if ([string]::IsNullOrWhiteSpace($env:BI_PRIVATE_KEYS_JSON)) {
    throw "BI_PRIVATE_KEYS_JSON is required"
}

try {
    $signingConfig = Get-Content $signingConfigPath -Raw |
        ConvertFrom-Json -AsHashtable
    $privateKeys = $env:BI_PRIVATE_KEYS_JSON |
        ConvertFrom-Json -AsHashtable
    $env:BI_PRIVATE_KEYS_JSON = $null

    if ($signingConfig -isnot [Collections.IDictionary]) {
        throw "Signing config must be a JSON object"
    }
    if ($privateKeys -isnot [Collections.IDictionary]) {
        throw "BI_PRIVATE_KEYS_JSON must be a JSON object"
    }

    $defaultAuthority = [string]$signingConfig["default"]
    if ([string]::IsNullOrWhiteSpace($defaultAuthority)) {
        throw "Signing config requires a default authority"
    }

    $pboOverrides = $signingConfig["pbos"]
    if ($null -eq $pboOverrides) {
        $pboOverrides = @{}
    }
    if ($pboOverrides -isnot [Collections.IDictionary]) {
        throw "Signing config pbos must be a JSON object"
    }

    $pbos = @(Get-ChildItem $releaseRoot -Recurse -File -Filter "*.pbo")
    if ($pbos.Count -eq 0) {
        throw "No release PBOs found"
    }

    foreach ($pboName in $pboOverrides.Keys) {
        if ($pboName -notin $pbos.Name) {
            throw "Signing config references missing PBO: $pboName"
        }
    }

    $authoritiesByPbo = @{}
    foreach ($pbo in $pbos) {
        $authority = $defaultAuthority
        if ($pboOverrides.ContainsKey($pbo.Name)) {
            $authority = [string]$pboOverrides[$pbo.Name]
        }
        if ($authority -notmatch '^[A-Za-z0-9._-]+$') {
            throw "Invalid signing authority for $($pbo.Name)"
        }
        $authoritiesByPbo[$pbo.FullName] = $authority
    }

    $usedAuthorities = @($authoritiesByPbo.Values | Sort-Object -Unique)
    $publicKeys = @{}
    $privateKeyPaths = @{}
    New-Item -ItemType Directory -Path $privateKeysRoot | Out-Null

    foreach ($authority in $usedAuthorities) {
        $publicKeyPath = Join-Path $PWD "keys\$authority.bikey"
        if (-not (Test-Path $publicKeyPath)) {
            throw "Missing committed public key: $authority.bikey"
        }

        $inspection = (& hemtt utils inspect $publicKeyPath 2>&1 | Out-String)
        $authorityMatch = [regex]::Match(
            $inspection,
            "(?m)^\s*-\s*Authority:\s*(\S+)\s*$"
        )
        if (-not $authorityMatch.Success) {
            throw "Could not inspect public key: $authority.bikey"
        }
        if ($authorityMatch.Groups[1].Value -cne $authority) {
            throw "Public key authority does not match $authority.bikey"
        }
        if (-not $privateKeys.ContainsKey($authority)) {
            throw "Missing private key secret for $authority"
        }

        $privateKeyPath = Join-Path $privateKeysRoot "$authority.biprivatekey"
        [IO.File]::WriteAllBytes(
            $privateKeyPath,
            [Convert]::FromBase64String(([string]$privateKeys[$authority]).Trim())
        )

        $publicKeys[$authority] = $publicKeyPath
        $privateKeyPaths[$authority] = $privateKeyPath
    }

    foreach ($pbo in $pbos) {
        $authority = $authoritiesByPbo[$pbo.FullName]
        $publicKeyPath = $publicKeys[$authority]
        $privateKeyPath = $privateKeyPaths[$authority]
        $modRoot = Split-Path $pbo.Directory.FullName -Parent
        $releaseKeysRoot = Join-Path $modRoot "keys"
        $releasePublicKeyPath = Join-Path $releaseKeysRoot "$authority.bikey"

        New-Item -ItemType Directory -Force -Path $releaseKeysRoot | Out-Null
        if (Test-Path $releasePublicKeyPath) {
            if ((Get-FileHash $publicKeyPath).Hash -ne (Get-FileHash $releasePublicKeyPath).Hash) {
                throw "Release public key differs from $authority.bikey"
            }
        } else {
            Copy-Item $publicKeyPath $releasePublicKeyPath
        }

        Get-ChildItem "$($pbo.FullName).*bisign" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force

        & $dssign $privateKeyPath $pbo.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "DSSignFile failed for $($pbo.Name)"
        }

        $signatures = @(Get-ChildItem "$($pbo.FullName).*bisign" -File -ErrorAction SilentlyContinue)
        if ($signatures.Count -ne 1) {
            throw "Expected one signature for $($pbo.Name)"
        }

        hemtt utils verify $pbo.FullName $releasePublicKeyPath
        if ($LASTEXITCODE -ne 0) {
            throw "Signature verification failed for $($pbo.Name)"
        }
    }

    Write-Host "Signed $($pbos.Count) PBO(s) with $($usedAuthorities -join ', ')"
}
finally {
    $env:BI_PRIVATE_KEYS_JSON = $null
    Remove-Item $privateKeysRoot -Recurse -Force -ErrorAction SilentlyContinue
}
