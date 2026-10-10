[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$InputFile
)

$ErrorActionPreference = 'Stop'
$resolved = Resolve-Path -LiteralPath $InputFile
if ([IO.Path]::GetExtension($resolved.Path) -ine '.mkv') {
    throw 'Expected an .mkv file.'
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw 'ffmpeg is required and is not on PATH.'
}

$output = [IO.Path]::ChangeExtension($resolved.Path, '.mp4')
Write-Host "Converting $($resolved.Path)"
& ffmpeg -y -i $resolved.Path -movflags use_metadata_tags `
    -map 0:v -c:v copy -map 0:a -c:a copy -map 0:s -c:s mov_text `
    -strict unofficial $output
if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE" }
Write-Host "Created $output"
