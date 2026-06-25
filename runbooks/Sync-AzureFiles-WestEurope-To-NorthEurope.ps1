$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-AzCopyCommand {
    param(
        [Parameter(Mandatory = $true)][string]$AzCopyPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $output = & $AzCopyPath @Arguments 2>&1
    $output | ForEach-Object { Write-Output $_ }

    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage with exit code $LASTEXITCODE. Output: $($output -join [Environment]::NewLine)"
    }
}

$sourceUrl = 'https://<source-storage-account>.file.core.windows.net/<source-share>'
$destinationUrl = 'https://<destination-storage-account>.file.core.windows.net/<destination-share>'
$azCopyZip = Join-Path $env:TEMP 'azcopy.zip'
$azCopyDir = Join-Path $env:TEMP 'azcopy'

if (Test-Path $azCopyDir) {
    Remove-Item $azCopyDir -Recurse -Force
}

New-Item -ItemType Directory -Path $azCopyDir -Force | Out-Null
Invoke-WebRequest -Uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile $azCopyZip
Expand-Archive -Path $azCopyZip -DestinationPath $azCopyDir -Force

$azCopy = Get-ChildItem -Path $azCopyDir -Filter 'azcopy.exe' -Recurse | Select-Object -First 1

if (-not $azCopy) {
    throw 'AzCopy executable was not found after download.'
}

Invoke-AzCopyCommand `
    -AzCopyPath $azCopy.FullName `
    -Arguments @('login', '--identity') `
    -FailureMessage 'AzCopy managed identity login failed'

Invoke-AzCopyCommand `
    -AzCopyPath $azCopy.FullName `
    -Arguments @('copy', $sourceUrl, $destinationUrl, '--recursive=true', '--from-to=FileFile', '--overwrite=ifSourceNewer') `
    -FailureMessage 'AzCopy copy failed'

