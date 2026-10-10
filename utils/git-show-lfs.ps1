[CmdletBinding()]
param(
    [ValidateRange(1, 1000)]
    [int]$Count = 30
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required and is not on PATH.'
}
if (-not (Test-Path -LiteralPath '.git')) {
    throw 'Run this command from the root of a non-bare Git repository.'
}

$indexes = Get-ChildItem -LiteralPath '.git/objects/pack' -Filter '*.idx' -File -ErrorAction SilentlyContinue
if (-not $indexes) {
    throw 'No Git pack index files found.'
}

$locations = @{}
foreach ($line in (& git rev-list --all --objects)) {
    $parts = $line -split ' ', 2
    if ($parts[0]) { $locations[$parts[0]] = if ($parts.Count -gt 1) { $parts[1] } else { '' } }
}

$objects = foreach ($index in $indexes) {
    & git verify-pack -v $index.FullName | ForEach-Object {
        $fields = $_ -split '\s+'
        if ($fields.Count -ge 3 -and $fields[0] -match '^[0-9a-f]{40,64}$' -and $fields[2] -match '^\d+$') {
            [pscustomobject]@{ Sha = $fields[0]; SizeKiB = [math]::Floor([int64]$fields[2] / 1KB) }
        }
    }
}

$objects | Sort-Object SizeKiB -Descending | Select-Object -First $Count | ForEach-Object {
    [pscustomobject]@{
        SizeKiB = $_.SizeKiB
        SHA = $_.Sha
        Location = $locations[$_.Sha]
    }
} | Format-Table -AutoSize
