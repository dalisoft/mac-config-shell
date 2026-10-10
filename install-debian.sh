#!/usr/bin/env bash
# Debian/Ubuntu counterpart to install.sh. Run as a normal user with sudo access.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PLAN=0
GUI=1
DOTFILES=1
LANGUAGE_TOOLS=1
HOST_SETTINGS=1
SECURITY=1
SSH_WAS_ACTIVE=0
FAILURES=()
SKIPPED=()
FNM_VERSIONS=(18.20.8 20.20.2 22.23.2 24.18.1)
BUN_NPM_PACKAGES=(flamebearer git-stats node-gyp nodemon npm npm-check-updates typesync pnpm yarn repomix dprint)
PYTHON_TOOLS=(jupyterlab labelImg labelme notebook 'psrecord[plot]' virtualenv)

usage() {
  cat <<'EOF'
Usage: bash install-debian.sh [--plan] [--no-gui] [--no-dotfiles] [--no-language-tools] [--no-host-settings] [--no-security]
  --plan               Print the package plan without changing the machine.
  --no-gui             Skip APT and Flatpak desktop applications.
  --no-dotfiles        Do not clone or link the Unix dotfiles.
  --no-language-tools  Skip fnm, Node versions, Bun, Deno, uv, and global tools.
  --no-host-settings   Keep the current login shell and skip host configuration.
  --no-security        Do not enable UFW or configure OpenSSH key-only login.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --plan) PLAN=1 ;;
    --no-gui) GUI=0 ;;
    --no-dotfiles) DOTFILES=0 ;;
    --no-language-tools) LANGUAGE_TOOLS=0 ;;
    --no-host-settings) HOST_SETTINGS=0 ;;
    --no-security) SECURITY=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

while IFS='|' read -r source package || [[ -n "${source:-}" ]]; do
  [[ -z "${source:-}" || "$source" == \#* ]] && continue
  if [[ $PLAN -eq 1 ]]; then
    printf 'APT       %-35s %s\n' "$source" "$package"
  fi
done < "$SCRIPT_DIR/linux/apt-packages.tsv"

if [[ $PLAN -eq 1 ]]; then
  if [[ $GUI -eq 1 ]]; then
    while IFS='|' read -r source package || [[ -n "${source:-}" ]]; do
      [[ -z "${source:-}" || "$source" == \#* ]] && continue
      printf 'APT GUI   %-35s %s\n' "$source" "$package"
    done < "$SCRIPT_DIR/linux/apt-desktop.tsv"
    while IFS='|' read -r source app_id || [[ -n "${source:-}" ]]; do
      [[ -z "${source:-}" || "$source" == \#* ]] && continue
      printf 'FLATPAK   %-35s %s\n' "$source" "$app_id"
    done < "$SCRIPT_DIR/linux/flatpak-apps.tsv"
  fi
  [[ $LANGUAGE_TOOLS -eq 0 ]] || printf '%s\n' 'TOOLS     fnm/Node 18,20,22,24; Bun; Deno; uv; npm and Python tools'
  [[ $DOTFILES -eq 0 ]] || printf '%s\n' 'DOTFILES  clone ~/Desktop/dotfiles and back up/link existing Unix configuration'
  [[ $GUI -eq 0 ]] || printf '%s\n' 'SETTINGS  on GNOME: light appearance and list view in Files'
  [[ $HOST_SETTINGS -eq 0 ]] || printf '%s\n' 'HOST      fish login shell; GPG; Java; Neovim; portable helper commands'
  [[ $SECURITY -eq 0 || $HOST_SETTINGS -eq 0 ]] || printf '%s\n' 'SECURITY  UFW enabled; OpenSSH password authentication disabled when sshd is available'
  while IFS='|' read -r source route target parity note || [[ -n "${source:-}" ]]; do
    [[ -z "${source:-}" || "$source" == \#* ]] && continue
    printf '%-10s %-35s %-9s %s — %s\n' "$route" "$source" "$parity" "$target" "$note"
  done < "$SCRIPT_DIR/linux/other-packages.tsv"
  exit 0
fi

if [[ ! -r /etc/os-release ]] || ! command -v apt-get >/dev/null 2>&1; then
  echo 'This installer requires Debian or an APT-based Debian derivative.' >&2
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != debian && " ${ID_LIKE:-} " != *' debian '* ]]; then
  echo "Unsupported distribution: ${ID:-unknown}" >&2
  exit 1
fi
if [[ $EUID -eq 0 ]]; then
  echo 'Run as your normal user; the script calls sudo only for APT.' >&2
  exit 1
fi
for executable in sudo curl git; do
  if ! command -v "$executable" >/dev/null 2>&1; then
    echo "Missing prerequisite: $executable (install sudo, curl, and git first)." >&2
    exit 1
  fi
done
sudo -v || exit 1
export PATH="$HOME/.local/bin:$HOME/.fnm:$HOME/.bun/bin:$HOME/.deno/bin:$HOME/.cargo/bin:$PATH"

record_failure() { FAILURES+=("$1"); printf 'FAILED: %s\n' "$1" >&2; }
record_skip() { SKIPPED+=("$1"); printf 'UNAVAILABLE: %s\n' "$1" >&2; }

validate_manifests() {
  if ! command -v python3 >/dev/null 2>&1; then
    record_failure 'Python 3 is required to validate portability manifests'
    return 1
  fi
  python3 "$SCRIPT_DIR/scripts/verify-portability-manifests.py"
}

install_apt() {
  echo 'Updating APT metadata...'
  sudo apt-get update || { record_failure 'apt-get update'; return; }
  install_apt_file "$SCRIPT_DIR/linux/apt-packages.tsv"
  if [[ $GUI -eq 1 ]]; then install_apt_file "$SCRIPT_DIR/linux/apt-desktop.tsv"; fi
}

install_apt_file() {
  local source package
  while IFS='|' read -r source package || [[ -n "${source:-}" ]]; do
    [[ -z "${source:-}" || "$source" == \#* ]] && continue
    if ! apt-cache show "$package" >/dev/null 2>&1; then
      record_skip "APT $source -> $package"
      continue
    fi
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      continue
    fi
    echo "APT: $source -> $package"
    sudo apt-get install -y "$package" || record_failure "APT $source -> $package"
  done < "$1"
}

install_flatpaks() {
  local source app_id
  [[ $GUI -eq 1 ]] || return 0
  if ! command -v flatpak >/dev/null 2>&1; then
    sudo apt-get install -y flatpak || { record_failure 'APT flatpak'; return; }
  fi
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || {
    record_failure 'Flathub remote'; return;
  }
  while IFS='|' read -r source app_id || [[ -n "${source:-}" ]]; do
    [[ -z "${source:-}" || "$source" == \#* ]] && continue
    if flatpak info --user "$app_id" >/dev/null 2>&1; then continue; fi
    if ! flatpak remote-info --user flathub "$app_id" >/dev/null 2>&1; then
      record_skip "Flathub $source -> $app_id"
      continue
    fi
    echo "Flatpak: $source -> $app_id"
    flatpak install --user --noninteractive -y flathub "$app_id" || record_failure "Flatpak $source -> $app_id"
  done < "$SCRIPT_DIR/linux/flatpak-apps.tsv"
}

install_vendor_script() {
  local label=$1 url=$2 interpreter=$3
  shift 3
  local script_file
  script_file=$(mktemp) || { record_failure "$label temporary file"; return; }
  if curl -fsSL "$url" -o "$script_file" && "$interpreter" "$script_file" "$@"; then
    echo "Installed $label"
  else
    record_failure "$label installer"
  fi
  rm -f -- "$script_file"
}

install_language_tools() {
  local version package
  [[ $LANGUAGE_TOOLS -eq 1 ]] || return 0
  if ! command -v fnm >/dev/null 2>&1; then
    install_vendor_script fnm https://fnm.vercel.app/install bash --install-dir "$HOME/.local/bin" --skip-shell
  fi
  if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)" || record_failure 'fnm environment'
    for version in "${FNM_VERSIONS[@]}"; do
      fnm install "$version" || record_failure "Node $version"
    done
    fnm use system || record_failure 'fnm use system'
    fnm default system || record_failure 'fnm default system'
  else
    record_skip 'fnm / pinned Node versions'
  fi
  if ! command -v rustup >/dev/null 2>&1; then
    install_vendor_script Rustup https://sh.rustup.rs sh -y --no-modify-path
  fi
  if command -v rustup >/dev/null 2>&1; then
    rustup toolchain install stable || record_failure 'Rust stable toolchain'
    rustup default stable || record_failure 'Rust stable default'
  else
    record_skip 'Rust stable toolchain'
  fi
  if ! command -v bun >/dev/null 2>&1; then
    install_vendor_script Bun https://bun.com/install bash
  fi
  if ! command -v deno >/dev/null 2>&1; then
    install_vendor_script Deno https://deno.land/install.sh sh
  fi
  if ! command -v uv >/dev/null 2>&1; then
    install_vendor_script uv https://astral.sh/uv/install.sh sh
  fi
  if command -v bun >/dev/null 2>&1; then
    for package in "${BUN_NPM_PACKAGES[@]}"; do
      bun install --global "$package" || record_failure "Bun global $package"
    done
  else
    record_skip 'Bun global packages'
  fi
  if command -v uv >/dev/null 2>&1; then
    for package in "${PYTHON_TOOLS[@]}"; do
      if [[ $GUI -eq 0 && ( "$package" == labelImg || "$package" == labelme ) ]]; then continue; fi
      uv tool install "$package" || record_failure "uv tool $package"
    done
    # osxphotos can query Apple Photos libraries on Linux, with limited functionality.
    uv tool install osxphotos || record_failure 'uv tool osxphotos'
  else
    record_skip 'Python CLI tools'
  fi
}

install_go_tool() {
  local package=$1
  GOBIN="$HOME/.local/bin" go install "$package" || record_failure "Go tool $package"
}

install_rust_tool() {
  local package=$1
  cargo install --root "$HOME/.local" "$package" || record_failure "Rust tool $package"
}

install_extra_tools() {
  local package gem_home
  [[ $LANGUAGE_TOOLS -eq 1 ]] || return 0

  if command -v uv >/dev/null 2>&1; then
    uv tool install aider-chat || record_failure 'uv tool aider-chat'
    uv tool install 'huggingface_hub[cli]' || record_failure 'uv tool huggingface_hub[cli]'
  else
    record_skip 'aider and hf CLI tools'
  fi

  if command -v bun >/dev/null 2>&1; then
    for package in dprint pnpm repomix yarn @anthropic-ai/claude-code; do
      bun install --global "$package" || record_failure "Bun global $package"
    done
  else
    record_skip 'dprint pnpm repomix yarn and Claude Code'
  fi

  if command -v ruby >/dev/null 2>&1 && command -v gem >/dev/null 2>&1; then
    gem_home=$(ruby -e 'print Gem.user_dir')
    for package in cocoapods shellspec tmuxinator; do
      GEM_HOME="$gem_home" gem install --no-document "$package" || record_failure "Ruby gem $package"
    done
  else
    record_skip 'cocoapods shellspec and tmuxinator'
  fi

  if command -v go >/dev/null 2>&1; then
    install_go_tool github.com/github/git-sizer@latest
    install_go_tool sigs.k8s.io/kind@latest
    install_go_tool github.com/go-acme/lego/v4/cmd/lego@latest
    install_go_tool filippo.io/mkcert@latest
  else
    record_skip 'git-sizer kind lego and mkcert'
  fi

  if command -v cargo >/dev/null 2>&1; then
    for package in git-cliff mergiraf wasm-pack diffsitter; do
      install_rust_tool "$package"
    done
  else
    record_skip 'git-cliff mergiraf wasm-pack and diffsitter'
  fi

  if ! command -v helm >/dev/null 2>&1; then
    install_vendor_script Helm https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 bash
  fi
  if ! command -v volta >/dev/null 2>&1; then
    install_vendor_script Volta https://get.volta.sh bash --skip-setup
  fi
  if ! command -v opencode >/dev/null 2>&1; then
    install_vendor_script OpenCode https://opencode.ai/v2/install bash
  fi
  if ! command -v turso >/dev/null 2>&1; then
    install_vendor_script Turso https://get.tur.so/install.sh bash
  fi
}

write_portable_environment() {
  local env_dir env_file java_binary java_home gem_home
  [[ $LANGUAGE_TOOLS -eq 1 ]] || return 0
  env_dir="$HOME/.local/share/mac-config-shell"
  env_file="$env_dir/environment.sh"
  mkdir -p "$env_dir" || { record_failure 'portable environment directory'; return; }
  java_home=''
  if command -v java >/dev/null 2>&1; then
    java_binary=$(readlink -f "$(command -v java)")
    java_home=$(dirname "$(dirname "$java_binary")")
  fi
  gem_home=''
  if command -v ruby >/dev/null 2>&1; then
    gem_home=$(ruby -e 'print Gem.user_dir')
  fi
  {
    printf '%s\n' '# Managed by mac-config-shell. Edit the installer rather than this file.'
    printf '%s\n' "export NPM_CONFIG_PREFIX=\"\$HOME/.npm-global\""
    printf '%s\n' "export PATH=\"\$NPM_CONFIG_PREFIX/bin:\$HOME/.local/bin:\$HOME/.bun/bin:\$HOME/.deno/bin:\$HOME/.cargo/bin:\$HOME/go/bin:\$HOME/.volta/bin:\$HOME/.turso/bin:\$PATH\""
    if [[ -n "$java_home" ]]; then printf 'export JAVA_HOME=%q\n' "$java_home"; fi
    if [[ -n "$gem_home" ]]; then
      printf 'export GEM_HOME=%q\n' "$gem_home"
      printf '%s\n' "export PATH=\"\$GEM_HOME/bin:\$PATH\""
    fi
  } > "$env_file" || { record_failure 'portable environment'; return; }
  chmod 600 "$env_file"
}

configure_shell_path() {
  local rc shell_name init_line fish_dir fish_file
  [[ $LANGUAGE_TOOLS -eq 1 ]] || return 0
  for shell_name in bash zsh; do
    rc="$HOME/.$( [[ "$shell_name" == bash ]] && printf bashrc || printf zshrc )"
    init_line="[ -f \"\$HOME/.local/share/mac-config-shell/environment.sh\" ] && . \"\$HOME/.local/share/mac-config-shell/environment.sh\""
    if ! grep -Fq "$init_line" "$rc" 2>/dev/null; then
      printf '\n# mac-config-shell portable tools\n%s\n' "$init_line" >> "$rc" || record_failure "shell environment $rc"
    fi
    init_line="eval \"\$(fnm env --use-on-cd --shell $shell_name)\""
    if command -v fnm >/dev/null 2>&1 && ! grep -Fq "$init_line" "$rc" 2>/dev/null; then
      printf '%s\n' "$init_line" >> "$rc" || record_failure "fnm shell setup $rc"
    fi
  done
  fish_dir="$HOME/.config/fish/conf.d"
  fish_file="$fish_dir/mac-config-shell.fish"
  if command -v fish >/dev/null 2>&1; then
    mkdir -p "$fish_dir" || { record_failure 'fish configuration directory'; return; }
    cat > "$fish_file" <<'EOF'
# Managed by mac-config-shell.
set -gx NPM_CONFIG_PREFIX "$HOME/.npm-global"
fish_add_path "$NPM_CONFIG_PREFIX/bin" "$HOME/.local/bin" "$HOME/.bun/bin" "$HOME/.deno/bin" "$HOME/.cargo/bin" "$HOME/go/bin" "$HOME/.volta/bin" "$HOME/.turso/bin"
if type -q fnm
    fnm env --use-on-cd --shell fish | source
end
EOF
  fi
}

install_dotfiles() {
  local source target name backup_dir desktop_dir dotfiles_dir
  [[ $DOTFILES -eq 1 ]] || return 0
  desktop_dir="$HOME/Desktop"
  dotfiles_dir="$desktop_dir/dotfiles"
  mkdir -p "$desktop_dir" || { record_failure 'create Desktop directory'; return; }
  if [[ ! -d "$dotfiles_dir/.git" ]]; then
    git clone --recursive https://github.com/dalisoft/dotfiles.git "$dotfiles_dir" || {
      record_failure 'clone dotfiles'; return;
    }
  fi
  backup_dir="$HOME/.config-backup/$(date +%Y%m%d-%H%M%S)"
  for name in .nano .vim .config .pi .omp .nanorc .vimrc .tmux.conf .gitconfig .gitignore .gitattributes .gitmodules .hushlogin; do
    source="$dotfiles_dir/$name"
    target="$HOME/$name"
    [[ -e "$source" || -L "$source" ]] || { record_skip "dotfiles $name (missing upstream)"; continue; }
    [[ -L "$target" && "$(readlink "$target")" == "$source" ]] && continue
    if [[ -e "$target" || -L "$target" ]]; then
      mkdir -p "$backup_dir" || { record_failure "backup $name"; continue; }
      mv -- "$target" "$backup_dir/$name" || { record_failure "backup $name"; continue; }
    fi
    ln -s -- "$source" "$target" || record_failure "link $name"
  done
  mkdir -p "$HOME/.npm-global/lib" "$HOME/.vim/autoload" "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
}

configure_gpg() {
  local gpg_file pinentry temp
  [[ $HOST_SETTINGS -eq 1 ]] || return 0
  mkdir -p "$HOME/.gnupg" || { record_failure 'GnuPG directory'; return; }
  chmod 700 "$HOME/.gnupg"
  pinentry=$(command -v pinentry-curses || command -v pinentry-gnome3 || command -v pinentry-qt || true)
  if [[ -z "$pinentry" ]]; then
    record_skip 'GnuPG pinentry program'
    return 0
  fi
  gpg_file="$HOME/.gnupg/gpg-agent.conf"
  temp=$(mktemp) || { record_failure 'GnuPG temporary file'; return; }
  if [[ -f "$gpg_file" ]]; then
    awk '
      /^# >>> mac-config-shell gpg-agent >>>$/ { managed = 1; next }
      /^# <<< mac-config-shell gpg-agent <<<$/{ managed = 0; next }
      managed { next }
      /^[[:space:]]*(pinentry-program|default-cache-ttl|max-cache-ttl|enable-ssh-support|extra-socket)[[:space:]]/ { next }
      { print }
    ' "$gpg_file" > "$temp"
  else
    : > "$temp"
  fi
  {
    printf '\n%s\n' '# >>> mac-config-shell gpg-agent >>>'
    printf 'pinentry-program %s\n' "$pinentry"
    printf '%s\n' 'default-cache-ttl 3600' 'max-cache-ttl 14400' 'enable-ssh-support'
    printf 'extra-socket %s\n' "$HOME/.gnupg/S.gpg-agent.extra"
    printf '%s\n' '# <<< mac-config-shell gpg-agent <<<'
  } >> "$temp"
  mv "$temp" "$gpg_file" || { record_failure 'GnuPG agent configuration'; return; }
  find "$HOME/.gnupg" -type d -exec chmod 700 {} + || record_failure 'GnuPG directory permissions'
  find "$HOME/.gnupg" -type f -exec chmod 600 {} + || record_failure 'GnuPG file permissions'
  command -v gpgconf >/dev/null 2>&1 && gpgconf --kill gpg-agent || true
}

configure_fish_login_shell() {
  local fish_path current_user
  [[ $HOST_SETTINGS -eq 1 ]] || return 0
  fish_path=$(command -v fish || true)
  [[ -n "$fish_path" ]] || { record_skip 'fish login shell'; return; }
  current_user=$(id -un)
  if ! grep -Fxq "$fish_path" /etc/shells; then
    printf '%s\n' "$fish_path" | sudo tee -a /etc/shells >/dev/null || { record_failure 'register fish shell'; return; }
  fi
  sudo chsh -s "$fish_path" root || record_failure 'set root fish shell'
  sudo chsh -s "$fish_path" "$current_user" || record_failure 'set user fish shell'
}

install_security_prerequisites() {
  local package service
  [[ $SECURITY -eq 1 && $HOST_SETTINGS -eq 1 ]] || return 0
  if command -v systemctl >/dev/null 2>&1; then
    for service in ssh sshd; do
      if systemctl is-active --quiet "$service" 2>/dev/null; then
        SSH_WAS_ACTIVE=1
        break
      fi
    done
  fi
  for package in ufw openssh-server; do
    if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
      continue
    fi
    if apt-cache show "$package" >/dev/null 2>&1; then
      sudo apt-get install -y "$package" || record_failure "APT security prerequisite $package"
    else
      record_skip "APT security prerequisite $package"
    fi
  done
}

configure_security() {
  local sshd_bin sshd_dropin temp service_name
  [[ $SECURITY -eq 1 && $HOST_SETTINGS -eq 1 ]] || return 0
  if command -v ufw >/dev/null 2>&1; then
    sudo ufw --force enable || record_failure 'enable UFW'
  else
    record_skip 'UFW firewall'
  fi
  sshd_bin=$(command -v sshd || true)
  if [[ -z "$sshd_bin" || ! -f /etc/ssh/sshd_config ]] || ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf' /etc/ssh/sshd_config; then
    record_skip 'OpenSSH drop-in configuration'
    return 0
  fi
  sshd_dropin=/etc/ssh/sshd_config.d/99-mac-config-shell.conf
  temp=$(mktemp) || { record_failure 'OpenSSH temporary file'; return; }
  printf '%s\n' 'PasswordAuthentication no' 'PubkeyAuthentication yes' > "$temp"
  sudo install -d -m 755 /etc/ssh/sshd_config.d || { rm -f "$temp"; record_failure 'OpenSSH drop-in directory'; return; }
  sudo install -m 644 "$temp" "$sshd_dropin" || { rm -f "$temp"; record_failure 'OpenSSH configuration'; return; }
  rm -f "$temp"
  if ! sudo "$sshd_bin" -t; then
    sudo rm -f "$sshd_dropin"
    record_failure 'validate OpenSSH configuration'
    return 0
  fi
  service_name=ssh
  if ! systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx ssh.service; then service_name=sshd; fi
  if [[ $SSH_WAS_ACTIVE -eq 1 ]]; then
    sudo systemctl reload "$service_name" || record_failure "reload $service_name"
  else
    # macOS configures sshd but leaves Remote Login disabled. Preserve that state
    # if APT started the service while installing its configuration files.
    sudo systemctl disable --now "$service_name" || record_failure "disable inactive $service_name"
  fi
}

install_helpers() {
  local helper name
  [[ $HOST_SETTINGS -eq 1 ]] || return 0
  mkdir -p "$HOME/.local/bin" || { record_failure 'create ~/.local/bin'; return; }
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sfn -- "$(command -v fdfind)" "$HOME/.local/bin/fd" || record_failure 'fd alias'
  fi
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    ln -sfn -- "$(command -v batcat)" "$HOME/.local/bin/bat" || record_failure 'bat alias'
  fi
  for name in remme git-show-lfs mkv2mp4; do
    if [[ "$name" == remme ]]; then helper="$SCRIPT_DIR/utils/remme-linux.sh"; else helper="$SCRIPT_DIR/utils/$name.sh"; fi
    [[ -f "$helper" ]] || continue
    if [[ -e "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" ]]; then
      record_skip "helper $name (existing binary preserved)"
      continue
    fi
    ln -sfn -- "$helper" "$HOME/.local/bin/$name" || record_failure "helper $name"
  done
  if [[ $DOTFILES -eq 1 ]] && command -v nvim >/dev/null 2>&1; then
    mkdir -p "$HOME/.vim/autoload"
    if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
      curl -fsSL https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
        -o "$HOME/.vim/autoload/plug.vim" || record_failure 'vim-plug download'
    fi
    if [[ -f "$HOME/.vim/autoload/plug.vim" ]]; then
      nvim --headless '+PlugInstall' '+qa' || record_failure 'Neovim plugins'
    fi
  fi
}

configure_desktop() {
  [[ $GUI -eq 1 && "$HOST_SETTINGS" -eq 1 && "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] || return 0
  command -v gsettings >/dev/null 2>&1 || return 0
  gsettings_set_if_available org.gnome.desktop.interface color-scheme "'default'" 'GNOME light appearance'
  gsettings_set_if_available org.gnome.nautilus.preferences default-folder-viewer "'list-view'" 'GNOME Files list view'
  gsettings_set_if_available org.gnome.desktop.privacy remember-recent-files false 'GNOME recent files'
  gsettings_set_if_available org.gnome.desktop.screensaver lock-enabled true 'GNOME lock screen'
  gsettings_set_if_available org.gnome.desktop.screensaver lock-delay 'uint32 0' 'GNOME immediate lock'
  gsettings_set_if_available org.gnome.desktop.peripherals.touchpad tap-to-click true 'GNOME tap to click'
  gsettings_set_if_available org.gnome.desktop.peripherals.touchpad natural-scroll false 'GNOME natural scrolling'
  gsettings_set_if_available org.gnome.desktop.peripherals.touchpad two-finger-scrolling true 'GNOME two-finger scrolling'
  gsettings_set_if_available org.gnome.desktop.peripherals.touchpad speed -0.125 'GNOME touchpad speed'
  gsettings_set_if_available org.gnome.mutter dynamic-workspaces false 'GNOME fixed workspaces'
  gsettings_set_if_available org.gnome.gnome-screenshot auto-save-directory "'file://$HOME/Desktop'" 'GNOME screenshot directory'
}

gsettings_set_if_available() {
  local schema=$1 key=$2 value=$3 label=$4
  gsettings list-schemas | grep -Fxq "$schema" || return 0
  gsettings list-keys "$schema" | grep -Fxq "$key" || return 0
  gsettings set "$schema" "$key" "$value" || record_failure "$label"
}

install_apt
validate_manifests || exit 1
install_security_prerequisites
install_flatpaks
install_dotfiles
install_language_tools
install_extra_tools
write_portable_environment
configure_shell_path
configure_gpg
install_helpers
configure_fish_login_shell
configure_security
configure_desktop

printf '\nFinished. Failures: %d; unavailable/skipped: %d\n' "${#FAILURES[@]}" "${#SKIPPED[@]}"
printf '  %s\n' "${FAILURES[@]}" "${SKIPPED[@]}" | sed '/^  $/d'
if [[ ${#FAILURES[@]} -gt 0 ]]; then exit 1; fi
