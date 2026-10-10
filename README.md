# mac-config-shell

A shell configuration project for macOS, Debian, and Windows.

The macOS setup remains the original Homebrew-based installer. Debian and
Windows counterparts track every active `Brewfile` entry and preserve the
original runtime, dotfile, GPG, Neovim, helper-command, and security setup
where the target platform supports it.

**macOS:** compatible with Apple Silicon and Sonoma 14.6+. Debian uses APT
and Flathub; Windows uses WinGet.

## Note

> This configuration was made for remote employee who work always from home and has it's secure home for it. No one touches to my machine
> **I do not guarantee nor support for your any damage & data loss, do & run it at your own risk**

Debian and Windows counterparts are included below. The older separate
[Windows project](https://github.com/dalisoft/win-install) is also available.

## Debian / APT

Use a Debian desktop (or an APT-based Debian derivative), with `sudo`, `curl`,
and `git` installed. Run as your normal user:

```sh
bash install-debian.sh --plan
bash install-debian.sh
```

`--plan` prints the mappings without making changes. `--no-gui` skips desktop
apps, `--no-dotfiles` preserves your existing dotfiles, and
`--no-language-tools` skips fnm, Node, Bun, Deno, uv, Rust, Go, and their
global tools. `--no-host-settings` skips the login shell, GPG, Java, Neovim,
helpers, desktop preferences, firewall, and SSH configuration. `--no-security`
skips only the UFW and OpenSSH changes.

APT choices are in [linux/apt-packages.tsv](linux/apt-packages.tsv) and
[linux/apt-desktop.tsv](linux/apt-desktop.tsv); Flathub IDs are in
[linux/flatpak-apps.tsv](linux/flatpak-apps.tsv). The installer checks which APT
packages exist in your configured release, installs each available package,
and reports unavailable or failed entries. It installs Flatpak desktop apps
per user. Fast-moving runtimes use their official upstream installers.

The dotfile step clones `dalisoft/dotfiles` to `~/Desktop/dotfiles`, as the
macOS installer does. It moves an existing target to
`~/.config-backup/<timestamp>/` before linking `.nano`, `.vim`, `.config`,
`.pi`, `.omp`, and the original dotfiles. On GNOME, it applies the closest
equivalents of the Finder, light-theme, input, workspace, lock-screen, and
screenshot settings. By default it also makes Fish the login shell, enables
UFW, and configures OpenSSH for public-key authentication.

## Windows / WinGet

Run in an elevated PowerShell on Windows 10/11 with WinGet. The default setup
also enables Windows Defender Firewall, installs OpenSSH Server, and disables
SSH password authentication:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1 -Plan
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

`-NoDotfiles`, `-NoLanguageTools`, and `-NoSettings` omit those steps.
`-NoHostSettings` lets a standard user install the app and tool set without
changing OpenSSH or firewall settings; `-NoSecurity` retains other host setup
but skips those security changes. `-InstallWSL` additionally starts a Debian
WSL installation, which may require a reboot. After WSL setup, clone this
repository **inside Debian** and run `bash install-debian.sh --no-gui` for the
Unix-only command-line tools.

Windows apps and native developer tools are listed in
[windows/winget-packages.tsv](windows/winget-packages.tsv). Each exact WinGet
ID is checked at run time, then installed separately. Missing IDs and failed
installers appear in the summary. The dotfile step uses the same
`~/Desktop/dotfiles` location and the same folders/files as macOS; it creates
symbolic links when permitted and safely copies a target when Windows link
permissions are unavailable. It sets File Explorer extensions, a light theme,
text-input preferences, lock-screen protection, screenshot location, GPG
agent settings, `JAVA_HOME`, Neovim plugins, and Windows versions of the
original helper commands.

Every active `Brewfile` entry appears in a platform manifest. Items without a
native package route are recorded with an `automatic`, `manual`, `wsl`,
`replacement`, `web`, or `unavailable` outcome in
[linux/other-packages.tsv](linux/other-packages.tsv) and
[windows/other-packages.tsv](windows/other-packages.tsv). This makes the
remaining platform limits inspectable instead of silently omitting them.

Apple-only tools and workflows such as Xcode, `mas`, Apple Configurator,
TestFlight, Finder/Dock internals, and hardware utilities cannot have identical
Debian or Windows behavior. Commercial apps may need a sign-in or vendor
installer. Debian package availability and WinGet/Flathub IDs vary by release
and architecture. Run the coverage check at any time with:

```sh
python3 scripts/verify-portability-manifests.py
```

The GitHub workflow parses both installers and renders their plans on Ubuntu
and Windows runners.

## Used projects

- <https://github.com/mathiasbynens/dotfiles/blob/main/.macos>

## Guide

If you want guide (optional), there exists a file. See [guide at here](./guide.md)

## Pre-installation

- Give "Full-disk access" for "Terminal" ([guide](https://www.howtoisolve.com/full-disk-access-full-permissions-on-mac/))
- Import a "dotfiles" `.terminal` theme into "Terminal"
- Login into "macOS App Store" and download any app ([guide](https://support.apple.com/en-uz/guide/app-store/fir6253293d/3.0/mac/12.0))

## Installation

```shell
# go-to your desired downloads folder
git clone https://github.com/dalisoft/mac-config-shell.git
cd mac-config-shell
sh install.sh
> "YOUR_PASSWORD"
```

## SSH Permissions

This could happen if you're copying `~/.ssh` folder from elsewhere and there are fix

```sh
chown -R $USER ~/.ssh
find ~/.ssh -type d | xargs -L1 sudo chmod 700
find ~/.ssh -type f | xargs -L1 sudo chmod 600
```

### GNUPG Permissions

This could happen if you're copying `~/.gnupg` folder from elsewhere and there are fix

```sh
chown -R $USER ~/.gnupg
find ~/.gnupg -type d | xargs -L1 sudo chmod 700
find ~/.gnupg -type f | xargs -L1 sudo chmod 600
```

## To-Do

| Bug Name                                       | Status        |
| ---------------------------------------------- | ------------- |
| Fix disk check condition                       | ✅ Fixed      |
| Add temporarily disable sleep script           | ✅ Fixed      |
| Add `disable font anti-alias`                  | ✅ Fixed      |
| Hide `password enter`                          | ✅ Fixed      |
| Tap to Click Enable, Scroll, Zoom              | ✅ Fixed      |
| SSH Passwordless                               | ✅ Fixed      |
| Enable Firewall                                | ✅ Fixed      |
| Open & Sign In MAS when run script             | ✅ Fixed      |
| Auto-allow older versions via MAS              | ❌ Won't Fix  |
| Enable remote enable (SSH)                     | 📝 See guides |
| Add `Dock enlarge`?                            | 📝 See guides |
| Disable personalized ads                       | 📝 See guides |
| Calculate all sizes options?                   | 📝 See guides |
| Show Downloads, Movies, Music, Pictures, User? | 📝 See guides |
| Recent Items — 0                               | 📝 See guides |
| Uncheck “Close windows when quitting an app”   | 📝 See guides |
| Fix SSH folder permissions                     | 📝 See above  |
| Photos iCloud Enable                           | 🤔 Out-of-Box |

## Old histories

- [`78c55d`](https://github.com/dalisoft/config/commit/78c55d1182d93ccde8b5a82958ee3afbbbf9e2bd) until [`409750`](https://github.com/dalisoft/config/commit/4097507eb225644425e37dca15965f3a2b0aca40) commits, see [compare](https://github.com/dalisoft/ansible-config/compare/78c55d...409750)
- [`ae9e98`](https://github.com/dalisoft/ansible-config/commit/ae9e9892b770ab3817107a56271a96d6deb1558a) until [`fe1c09`](https://github.com/dalisoft/ansible-config/commit/fe1c09426aec767ba8471f496e91bb21a0be091b) commits, see [compare](https://github.com/dalisoft/ansible-config/compare/ae9e98...fe1c09)

## License

Apache-2.0 License
