[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$PackageId
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'WinGet is required and is not on PATH.'
}

& winget uninstall --id $PackageId --exact --accept-source-agreements
if ($LASTEXITCODE -ne 0) { throw "WinGet failed with exit code $LASTEXITCODE" }
