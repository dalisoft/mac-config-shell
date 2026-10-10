# Requires -Version 5.1
<#
.SYNOPSIS
Installs the Windows counterpart of the macOS Brewfile and install.sh setup.

.DESCRIPTION
The active Brewfile entries are represented in windows/winget-packages.tsv or
windows/other-packages.tsv.  WinGet entries are installed automatically.  The
other manifest records upstream, WSL, replacement, and unavailable routes so
that every active macOS entry has an explicit Windows outcome.
#>
[CmdletBinding()]
param(
    [switch]$Plan,
    [switch]$NoDotfiles,
    [switch]$NoLanguageTools,
    [switch]$NoSettings,
    [switch]$NoHostSettings,
    [switch]$NoSecurity,
    [switch]$InstallWSL
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WingetManifestPath = Join-Path $RepoRoot 'windows/winget-packages.tsv'
$OtherManifestPath = Join-Path $RepoRoot 'windows/other-packages.tsv'
$NodeVersions = @('18.20.8', '20.20.2', '22.23.2', '24.18.1')
$BunGlobalPackages = @('flamebearer', 'git-stats', 'node-gyp', 'nodemon', 'npm', 'npm-check-updates', 'typesync')
$PythonPackages = @('jupyterlab', 'labelImg', 'labelme', 'notebook', 'psrecord[plot]', 'virtualenv')
$Script:Failures = [System.Collections.Generic.List[string]]::new()
$Script:Unavailable = [System.Collections.Generic.List[string]]::new()

function Write-Section {
    param([string]$Title)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

function Add-Failure {
    param([string]$Message)
    $Script:Failures.Add($Message)
    Write-Warning $Message
}

function Add-Unavailable {
    param([string]$Message)
    $Script:Unavailable.Add($Message)
    Write-Warning $Message
}

function Read-WingetManifest {
    param([string]$Path)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (!$trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $fields = $line -split '\|'
        if ($fields.Count -ne 2) {
            throw "Malformed WinGet manifest row: $line"
        }

        $rows.Add([pscustomobject]@{
                Source = $fields[0].Trim()
                Id = $fields[1].Trim()
            })
    }

    return $rows.ToArray()
}

function Read-OtherManifest {
    param([string]$Path)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (!$trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $fields = $line -split '\|'
        if ($fields.Count -ne 5) {
            throw "Malformed Windows parity manifest row: $line"
        }

        $rows.Add([pscustomobject]@{
                Source = $fields[0].Trim()
                Route = $fields[1].Trim()
                Target = $fields[2].Trim()
                Parity = $fields[3].Trim()
                Note = (($fields[4..($fields.Count - 1)] -join '|').Trim())
            })
    }

    return $rows.ToArray()
}

function Test-ManifestCoverage {
    $expected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath (Join-Path $RepoRoot 'Brewfile')) {
        if ($line -match '^\s*(?:brew|cask|mas)\s+"([^"]+)"') {
            $null = $expected.Add($Matches[1])
        }
    }

    $covered = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($package in @(Read-WingetManifest -Path $WingetManifestPath) + @(Read-OtherManifest -Path $OtherManifestPath)) {
        if (!$package.Source.StartsWith('@')) {
            $null = $covered.Add($package.Source)
        }
    }

    $missing = @($expected | Where-Object { !$covered.Contains($_) } | Sort-Object)
    $unknown = @($covered | Where-Object { !$expected.Contains($_) } | Sort-Object)
    if ($missing.Count -gt 0 -or $unknown.Count -gt 0) {
        $message = [System.Collections.Generic.List[string]]::new()
        if ($missing.Count -gt 0) { $message.Add("missing: $($missing -join ', ')") }
        if ($unknown.Count -gt 0) { $message.Add("unknown: $($unknown -join ', ')") }
        throw "Windows portability manifest coverage failed ($($message -join '; '))."
    }

    Write-Host "Windows: $($expected.Count)/$($expected.Count) active Brewfile entries covered"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ';'
}

function Add-UserPathSegment {
    param([string]$Segment)

    if (!(Test-Path -LiteralPath $Segment)) {
        New-Item -ItemType Directory -Force -Path $Segment | Out-Null
    }

    $existing = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($existing -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts -notcontains $Segment) {
        $updated = (@($parts) + $Segment) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    }

    if ((@($env:Path -split ';') | ForEach-Object { $_.Trim() }) -notcontains $Segment) {
        $env:Path = "$Segment;$env:Path"
    }
}

function Invoke-Native {
    param(
        [string]$Description,
        [string]$Command,
        [string[]]$Arguments
    )

    try {
        & $Command @Arguments
        $exitCode = $LASTEXITCODE
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            throw "exit code $exitCode"
        }
    }
    catch {
        Add-Failure "$Description failed: $($_.Exception.Message)"
    }
}

function Invoke-WingetInstall {
    param([pscustomobject]$Package)

    if ($Package.Id.StartsWith('@')) {
        return
    }

    Write-Host "WinGet: $($Package.Source) -> $($Package.Id)"
    & winget show --id $Package.Id --exact --source winget --accept-source-agreements *> $null
    if ($LASTEXITCODE -ne 0) {
        Add-Unavailable "WinGet package unavailable: $($Package.Source) ($($Package.Id))"
        return
    }

    & winget install --id $Package.Id --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "WinGet installation failed: $($Package.Source) ($($Package.Id))"
    }
}

function Set-ManagedBlock {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Body
    )

    $directory = Split-Path -Parent $Path
    if (!(Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $begin = "# >>> mac-config:$Name >>>"
    $end = "# <<< mac-config:$Name <<<"
    $current = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { '' }
    $pattern = "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))\s*"
    $withoutManagedBlock = [regex]::Replace($current, $pattern, '')
    if ($withoutManagedBlock -and !$withoutManagedBlock.EndsWith("`n")) {
        $withoutManagedBlock += "`r`n"
    }

    $block = "$begin`r`n$($Body.Trim())`r`n$end`r`n"
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $withoutManagedBlock + $block, $utf8WithoutBom)
}

function Test-ManagedSymbolicLink {
    param(
        [string]$Path,
        [string]$Target
    )

    if (!(Test-Path -LiteralPath $Path)) {
        return $false
    }
    $item = Get-Item -LiteralPath $Path -Force
    return $item.LinkType -eq 'SymbolicLink' -and (@($item.Target) -contains $Target)
}

function Backup-ExistingPath {
    param(
        [string]$Path,
        [string]$Timestamp
    )

    $backup = "$Path.backup.$Timestamp"
    $sequence = 1
    while (Test-Path -LiteralPath $backup) {
        $backup = "$Path.backup.$Timestamp.$sequence"
        $sequence++
    }
    Move-Item -LiteralPath $Path -Destination $backup -Force
}

function Initialize-Fnm {
    if (!(Get-Command fnm -ErrorAction SilentlyContinue)) {
        Add-Failure 'fnm is unavailable after WinGet installation.'
        return
    }

    Write-Section 'Node.js versions'
    foreach ($version in $NodeVersions) {
        Invoke-Native -Description "fnm install $version" -Command 'fnm' -Arguments @('install', $version)
    }
    Invoke-Native -Description 'fnm use system' -Command 'fnm' -Arguments @('use', 'system')
    Invoke-Native -Description 'fnm default system' -Command 'fnm' -Arguments @('default', 'system')

    $fnmProfile = @'
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
'@
    Set-ManagedBlock -Path $PROFILE -Name 'fnm' -Body $fnmProfile
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

function Install-Dotfiles {
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    if (!$desktop) {
        $desktop = Join-Path $HOME 'Desktop'
    }
    $dotfiles = Join-Path $desktop 'dotfiles'
    $linkFolders = @('.nano', '.vim', '.config', '.pi', '.omp')
    $linkFiles = @('.nanorc', '.vimrc', '.tmux.conf', '.gitconfig', '.gitignore', '.gitattributes', '.gitmodules', '.hushlogin')

    Write-Section 'Dotfiles'
    if (!(Test-Path -LiteralPath (Join-Path $dotfiles '.git'))) {
        if (Test-Path -LiteralPath $dotfiles) {
            Add-Failure "Dotfiles path exists but is not a Git clone: $dotfiles"
            return
        }
        New-Item -ItemType Directory -Force -Path $desktop | Out-Null
        & git clone --recursive https://github.com/dalisoft/dotfiles.git $dotfiles
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "Could not clone dotfiles into $dotfiles"
            return
        }
    }

    foreach ($relativePath in @('.npm-global/lib', '.vim/autoload', '.gnupg')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $HOME $relativePath) | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($name in $linkFolders) {
        $source = Join-Path $dotfiles $name
        $destination = Join-Path $HOME $name
        if (!(Test-Path -LiteralPath $source)) {
            Add-Unavailable "Dotfiles source is missing: $source"
            continue
        }
        if (Test-ManagedSymbolicLink -Path $destination -Target $source) {
            continue
        }
        if (Test-Path -LiteralPath $destination) {
            Backup-ExistingPath -Path $destination -Timestamp $timestamp
        }
        try {
            New-Item -ItemType SymbolicLink -Path $destination -Target $source | Out-Null
        }
        catch {
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
            Add-Unavailable "Created a copy instead of a directory link for $name; enable Developer Mode to use symbolic links."
        }
    }

    foreach ($name in $linkFiles) {
        $source = Join-Path $dotfiles $name
        $destination = Join-Path $HOME $name
        if (!(Test-Path -LiteralPath $source)) {
            Add-Unavailable "Dotfiles source is missing: $source"
            continue
        }
        if (Test-ManagedSymbolicLink -Path $destination -Target $source) {
            continue
        }
        if (Test-Path -LiteralPath $destination) {
            Backup-ExistingPath -Path $destination -Timestamp $timestamp
        }
        try {
            New-Item -ItemType SymbolicLink -Path $destination -Target $source | Out-Null
        }
        catch {
            Copy-Item -LiteralPath $source -Destination $destination -Force
            Add-Unavailable "Created a copy instead of a file link for $name; enable Developer Mode to use symbolic links."
        }
    }
}

function Install-LanguageTools {
    Write-Section 'Language tools and global packages'

    $userBin = Join-Path $HOME 'bin'
    $npmPrefix = Join-Path $HOME '.npm-global'
    $pythonEnvironment = Join-Path $HOME '.local\share\mac-config\python'
    New-Item -ItemType Directory -Force -Path $userBin, $npmPrefix | Out-Null
    Add-UserPathSegment -Segment $userBin
    Add-UserPathSegment -Segment (Join-Path $npmPrefix 'bin')
    [Environment]::SetEnvironmentVariable('NPM_CONFIG_PREFIX', $npmPrefix, 'User')
    $env:NPM_CONFIG_PREFIX = $npmPrefix

    Initialize-Fnm

    if (Get-Command bun -ErrorAction SilentlyContinue) {
        foreach ($package in $BunGlobalPackages) {
            Invoke-Native -Description "Bun global package $package" -Command 'bun' -Arguments @('install', '--global', $package)
        }
        Invoke-Native -Description 'Repomix CLI' -Command 'bun' -Arguments @('install', '--global', 'repomix')
    }
    else {
        Add-Failure 'Bun is unavailable after WinGet installation.'
    }

    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Invoke-Native -Description 'uv shell integration' -Command 'uv' -Arguments @('tool', 'update-shell')
        Invoke-Native -Description 'Python virtual environment' -Command 'uv' -Arguments @('venv', '--python', '3.12', $pythonEnvironment)
        $pythonExecutable = Join-Path $pythonEnvironment 'Scripts\python.exe'
        Invoke-Native -Description 'Python packages from install.sh' -Command 'uv' -Arguments (@('pip', 'install', '--python', $pythonExecutable) + $PythonPackages)
        Invoke-Native -Description 'aider CLI' -Command 'uv' -Arguments @('tool', 'install', 'aider-chat')
        Invoke-Native -Description 'Hugging Face CLI' -Command 'uv' -Arguments @('tool', 'install', 'huggingface_hub[cli]')
        Add-Unavailable 'osxphotos is not installed on Windows because it requires an Apple Photos library.'
    }
    else {
        Add-Failure 'uv is unavailable after WinGet installation.'
    }

    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        Invoke-Native -Description 'Rust stable toolchain' -Command 'rustup' -Arguments @('toolchain', 'install', 'stable')
        Invoke-Native -Description 'Rust default toolchain' -Command 'rustup' -Arguments @('default', 'stable')
        Invoke-Native -Description 'rust-analyzer component' -Command 'rustup' -Arguments @('component', 'add', 'rust-analyzer')
        $env:CARGO_INSTALL_ROOT = $userBin
        Invoke-Native -Description 'mergiraf' -Command 'cargo' -Arguments @('install', 'mergiraf')
        Invoke-Native -Description 'diffsitter' -Command 'cargo' -Arguments @('install', 'diffsitter')
        Remove-Item Env:CARGO_INSTALL_ROOT -ErrorAction SilentlyContinue
    }
    else {
        Add-Failure 'Rustup is unavailable after WinGet installation.'
    }

    if (Get-Command go -ErrorAction SilentlyContinue) {
        $previousGoBin = $env:GOBIN
        $env:GOBIN = $userBin
        Invoke-Native -Description 'lego' -Command 'go' -Arguments @('install', 'github.com/go-acme/lego/v4/cmd/lego@latest')
        if ($null -eq $previousGoBin) {
            Remove-Item Env:GOBIN -ErrorAction SilentlyContinue
        }
        else {
            $env:GOBIN = $previousGoBin
        }
    }
    else {
        Add-Failure 'Go is unavailable after WinGet installation.'
    }
}

function Set-GpgAgentConfiguration {
    $gpg = Get-Command gpg.exe -ErrorAction SilentlyContinue
    if (!$gpg) {
        Add-Unavailable 'Gpg4win is unavailable; skipped gpg-agent configuration.'
        return
    }

    Write-Section 'GnuPG agent'
    $gpgconf = Get-Command gpgconf.exe -ErrorAction SilentlyContinue
    $gpgDirectory = Join-Path $HOME '.gnupg'
    if ($gpgconf) {
        $reportedHome = @(& $gpgconf.Source --list-dirs homedir | Select-Object -First 1)[0]
        if ($LASTEXITCODE -eq 0 -and $reportedHome) {
            $reportedHome = $reportedHome.Trim()
            if ($reportedHome.StartsWith('homedir:')) {
                $reportedHome = $reportedHome.Substring('homedir:'.Length)
            }
            $gpgDirectory = [Uri]::UnescapeDataString($reportedHome)
        }
    }
    $gpgBinDirectory = Split-Path -Parent $gpg.Source
    $programFilesRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $pinentryCandidates = @(
        (Join-Path $gpgBinDirectory 'pinentry.exe'),
        (Join-Path $gpgBinDirectory 'pinentry-basic.exe')
    )
    foreach ($root in $programFilesRoots) {
        $pinentryCandidates += @(
            (Join-Path $root 'GnuPG\bin\pinentry.exe'),
            (Join-Path $root 'Gpg4win\bin\pinentry.exe')
        )
    }
    $pinentry = $pinentryCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($pinentry) {
        $lines.Add("pinentry-program $pinentry")
    }
    $lines.Add('default-cache-ttl 3600')
    $lines.Add('max-cache-ttl 14400')
    $lines.Add('enable-ssh-support')
    $lines.Add("extra-socket $gpgDirectory\S.gpg-agent.extra")
    $gpgAgentConfig = Join-Path $gpgDirectory 'gpg-agent.conf'
    if (Test-Path -LiteralPath $gpgAgentConfig) {
        $unmanagedLines = Get-Content -LiteralPath $gpgAgentConfig | Where-Object {
            $_ -notmatch '^\s*(?:pinentry-program|default-cache-ttl|max-cache-ttl|enable-ssh-support|extra-socket)\b'
        }
        Set-Content -LiteralPath $gpgAgentConfig -Value $unmanagedLines -Encoding utf8
    }
    Set-ManagedBlock -Path $gpgAgentConfig -Name 'gpg-agent' -Body ($lines -join [Environment]::NewLine)
    if ($gpgconf) {
        & $gpgconf.Source --kill gpg-agent
    }
}

function Set-JavaHome {
    $java = Get-Command java.exe -ErrorAction SilentlyContinue
    if (!$java) {
        Add-Unavailable 'Java 11 is unavailable; JAVA_HOME was not configured.'
        return
    }

    $javaHome = Split-Path -Parent (Split-Path -Parent $java.Source)
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'User')
    $env:JAVA_HOME = $javaHome
}

function Install-NeovimPlugins {
    $plugDirectory = Join-Path $HOME '.vim\autoload'
    $plugPath = Join-Path $plugDirectory 'plug.vim'
    New-Item -ItemType Directory -Force -Path $plugDirectory | Out-Null
    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' -OutFile $plugPath -UseBasicParsing
    }
    catch {
        Add-Failure "Could not download vim-plug: $($_.Exception.Message)"
        return
    }

    if (Get-Command nvim.exe -ErrorAction SilentlyContinue) {
        Invoke-Native -Description 'Neovim PlugInstall' -Command 'nvim.exe' -Arguments @('-c', 'PlugInstall', '-c', 'qa')
    }
    else {
        Add-Unavailable 'Neovim is unavailable; skipped PlugInstall.'
    }
}

function Install-HelperCommands {
    Write-Section 'Helper commands'
    $userBin = Join-Path $HOME 'bin'
    New-Item -ItemType Directory -Force -Path $userBin | Out-Null
    Add-UserPathSegment -Segment $userBin

    foreach ($name in @('remme', 'git-show-lfs', 'mkv2mp4')) {
        $source = Join-Path $RepoRoot "utils\$name.ps1"
        $scriptDestination = Join-Path $userBin "$name.ps1"
        $launcherDestination = Join-Path $userBin "$name.cmd"
        if (!(Test-Path -LiteralPath $source)) {
            Add-Failure "Missing Windows helper: $source"
            continue
        }
        Copy-Item -LiteralPath $source -Destination $scriptDestination -Force
        $launcher = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$name.ps1`" %*`r`n"
        Set-Content -LiteralPath $launcherDestination -Value $launcher -Encoding ascii
    }
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = 'DWord'
    )

    New-Item -Path $Path -Force | Out-Null
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-WindowsPreferences {
    Write-Section 'Windows preferences'

    # Finder equivalents: show file extensions, avoid recent-item recommendations,
    # and keep the desktop as the screenshot destination.
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_IrisRecommendations' -Value 0
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value 1
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value 1

    # Keyboard equivalents for the macOS text-substitution settings.
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\TabletTip\1.7' -Name 'EnableAutoShiftEngage' -Value 0
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\TabletTip\1.7' -Name 'EnableDoubleTapSpace' -Value 0
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\TabletTip\1.7' -Name 'EnableAutocorrection' -Value 0
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\TabletTip\1.7' -Name 'EnableHwkbTextPrediction' -Value 0
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverIsSecure' -Value '1' -Type 'String'

    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name '{B7BEDE81-DF94-4682-A7D8-57A52620B86F}' -Value $desktop -Type 'ExpandString'
}

function Set-SshdGlobalOption {
    param(
        [string[]]$Lines,
        [string]$Name,
        [string]$Value
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $found = $false
    $inMatchBlock = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*Match\b') {
            $inMatchBlock = $true
        }
        if (!$inMatchBlock -and $line -match "^\s*#?\s*$([regex]::Escape($Name))\s+") {
            if (!$found) {
                $result.Add("$Name $Value")
                $found = $true
            }
            continue
        }
        $result.Add($line)
    }

    if (!$found) {
        $matchIndex = -1
        for ($index = 0; $index -lt $result.Count; $index++) {
            if ($result[$index] -match '^\s*Match\b') {
                $matchIndex = $index
                break
            }
        }
        if ($matchIndex -ge 0) {
            $result.Insert($matchIndex, "$Name $Value")
        }
        else {
            $result.Add("$Name $Value")
        }
    }

    return $result.ToArray()
}

function Configure-OpenSshAndFirewall {
    Write-Section 'OpenSSH and firewall'
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True

    $existingService = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $wasRunning = $existingService -and $existingService.Status -eq 'Running'
    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if (!$capability -or $capability.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    }

    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if (!$service) {
        Add-Failure 'OpenSSH Server was not installed; skipped SSH configuration.'
        return
    }
    if (!$wasRunning -and $service.Status -eq 'Running') {
        # Installing the capability can start sshd on some Windows builds. Keep
        # Remote Login off unless it was already active before this installer.
        Stop-Service -Name sshd
    }

    $sshConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    $sshd = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
    if (!(Test-Path -LiteralPath $sshConfig) -or !(Test-Path -LiteralPath $sshd)) {
        Add-Failure 'OpenSSH configuration files are unavailable; skipped SSH hardening.'
        return
    }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backup = "$sshConfig.mac-config.$timestamp.bak"
    Copy-Item -LiteralPath $sshConfig -Destination $backup -Force
    $lines = @(Get-Content -LiteralPath $sshConfig)
    $lines = @(Set-SshdGlobalOption -Lines $lines -Name 'PasswordAuthentication' -Value 'no')
    $lines = @(Set-SshdGlobalOption -Lines $lines -Name 'PubkeyAuthentication' -Value 'yes')
    $temporaryConfig = "$sshConfig.mac-config.tmp"
    Set-Content -LiteralPath $temporaryConfig -Value $lines -Encoding ascii
    Copy-Item -LiteralPath $temporaryConfig -Destination $sshConfig -Force

    & $sshd -t
    if ($LASTEXITCODE -ne 0) {
        Copy-Item -LiteralPath $backup -Destination $sshConfig -Force
        Remove-Item -LiteralPath $temporaryConfig -Force -ErrorAction SilentlyContinue
        Add-Failure "OpenSSH configuration validation failed; restored $backup"
        return
    }
    Remove-Item -LiteralPath $temporaryConfig -Force -ErrorAction SilentlyContinue
    if ($wasRunning) {
        Restart-Service -Name sshd
    }

    $shellRegistry = 'HKLM:\SOFTWARE\OpenSSH'
    New-Item -Path $shellRegistry -Force | Out-Null
    New-ItemProperty -Path $shellRegistry -Name 'DefaultShell' -Value (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -PropertyType String -Force | Out-Null
}

function Install-WSLDistribution {
    if (!(Test-IsAdministrator)) {
        Add-Failure 'WSL installation requires an elevated PowerShell session.'
        return
    }
    Write-Section 'WSL Debian'
    Invoke-Native -Description 'WSL Debian installation' -Command 'wsl.exe' -Arguments @('--install', '-d', 'Debian')
    Write-Host 'After the required restart, open Debian and run ./install-debian.sh from this repository.' -ForegroundColor Yellow
}

$WingetPackages = Read-WingetManifest -Path $WingetManifestPath
$OtherPackages = Read-OtherManifest -Path $OtherManifestPath

Test-ManifestCoverage

if ($Plan) {
    Write-Section 'Windows installation plan'
    foreach ($package in $WingetPackages) {
        Write-Host "WinGet      $($package.Source) -> $($package.Id)"
    }
    foreach ($package in $OtherPackages) {
        Write-Host ("{0,-11} {1} -> {2} ({3}): {4}" -f $package.Route, $package.Source, $package.Target, $package.Parity, $package.Note)
    }
    Write-Host ("Dotfiles: {0}" -f $(if ($NoDotfiles) { 'skipped' } else { 'linked or copied from ~/Desktop/dotfiles' }))
    Write-Host ("Language tools: {0}" -f $(if ($NoLanguageTools) { 'skipped' } else { 'Bun, fnm, uv, Rust, Go, and original global packages' }))
    Write-Host ("User settings: {0}" -f $(if ($NoSettings -or $NoHostSettings) { 'skipped' } else { 'File Explorer, light theme, text input, lock screen, screenshots' }))
    Write-Host ("Host settings: {0}" -f $(if ($NoHostSettings) { 'skipped' } else { 'GPG, Java, Neovim, helpers, OpenSSH server, and Windows Defender Firewall' }))
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'install-windows.ps1 must run on Windows.'
}
if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet is required. Install or update App Installer, then run this script again.'
}
if (!$NoHostSettings -and !(Test-IsAdministrator)) {
    throw 'Run PowerShell as Administrator to configure OpenSSH and the firewall, or pass -NoHostSettings.'
}

Write-Section 'WinGet packages'
$languageSources = @('fnm', 'node', 'oven-sh/bun/bun', 'deno', 'uv', 'rustup', 'go', 'openjdk@11', 'pipx', 'pnpm', 'volta', 'wasm-pack', 'yarn', '@bootstrap-python')
$installedWingetIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($package in $WingetPackages) {
    if ($NoLanguageTools -and $languageSources -contains $package.Source) {
        continue
    }
    if (!$installedWingetIds.Add($package.Id)) {
        continue
    }
    Invoke-WingetInstall -Package $package
}
Refresh-ProcessPath

if (!$NoDotfiles) {
    Install-Dotfiles
}
if (!$NoLanguageTools) {
    Install-LanguageTools
}
if (!$NoHostSettings) {
    Set-GpgAgentConfiguration
    Set-JavaHome
    if (!$NoDotfiles) {
        Install-NeovimPlugins
    }
    Install-HelperCommands
}
if (!$NoSettings -and !$NoHostSettings) {
    Set-WindowsPreferences
}
if (!$NoHostSettings -and !$NoSecurity) {
    Configure-OpenSshAndFirewall
}
if ($InstallWSL) {
    Install-WSLDistribution
}

Write-Section 'Installation summary'
if ($Script:Unavailable.Count -gt 0) {
    Write-Host 'Unavailable or intentionally non-native items:' -ForegroundColor Yellow
    $Script:Unavailable | ForEach-Object { Write-Host "  - $_" }
}
if ($Script:Failures.Count -gt 0) {
    Write-Host 'Failed steps:' -ForegroundColor Red
    $Script:Failures | ForEach-Object { Write-Host "  - $_" }
    Write-Host "See $OtherManifestPath for manual, WSL, replacement, and unsupported routes."
    exit 1
}

Write-Host "Completed. See $OtherManifestPath for manual, WSL, replacement, and unsupported routes." -ForegroundColor Green
