#!/bin/bash
set -e

#############################
### Environment variables ###
#############################
read -p "Enter your password: " PASSWORD
read -p "Enter installation mode: minimal, compact or all [minimal]: " MODE
MODE=${MODE:-minimal}
ARCH=$(uname -m)
PWD=$(pwd)
OS_VER=$(sw_vers -productVersion | cut -d':' -f2 | tr -d ' ')

##############################
### Installation variables ###
##############################
MAX_TRIES=5

ENSURE_FOLDERS=(".npm-global" "Desktop/config/dotfiles/.vim/autoload")
LINK_FOLDERS=(".nano" ".vim" ".config")
LINK_FILES=(".nanorc" ".vimrc" ".tmux.conf" ".gitconfig")

NPM_PACKAGES=("npm" "0x" "bs-platform" "cordova" "esy" "flamebearer" "http-server" "node-gyp" "nodemon" "npm-check-updates" "typesync")
PIP_PACKAGES=("virtualenv" "jupyterlab" "notebook" "labelme" "psrecord")

FNM_VERSIONS=("12.22.5" "14.17.5")

#############################
### Preparations of steps ###
#############################

### Check and prompts ENV
### variables
function check_env {
  if [[ "$PASSWORD" == "" ]]; then
    echo "Hey, welcome! please trust me"
    echo "and enter valid password here"
    echo "I hope you understand me..."
    exit 1
  fi
  if [[ "$MODE" != "minimal" && $MODE != "compact" && $MODE != "full" ]]; then
    echo "Hey, welcome!"
    echo "Please select any of these values"
    echo "minimal, compact, full"
    exit 1
  fi
}
### Configre SUDO
### Askpass file
function configure_askpass {
  rm -rf askpass.sh
  echo "#!/bin/sh" >>./askpass.sh
  echo "echo \"$PASSWORD\"" >>./askpass.sh
  chmod 700 askpass.sh
}
### Configre ENV
### for future actions
function configure_env {
  export NPM_CONFIG_PREFIX="~/.npm-global"
  export SUDO_ASKPASS=$(pwd)/askpass.sh
  export PATH="$NPM_CONFIG_PREFIX/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
}
### Check for SUDO
### access check to
### validate
function sudo_access_check {
  if [[ "$EUID" = 0 ]]; then
    echo "Hey, welcome! I got (sudo) access"
    echo "Thank you for your trust, so"
    echo "i will continue my processes"
  else
    if sudo -A true; then
      echo "Hey, welcome! I got valid password"
      echo "Thank you for your trust, so"
      echo "i will continue my processes"
    else
      echo "Hey, how are you?"
      echo "Seems password is not valid"
      echo "Please check enter again..."
      echo "Thank you"
      rm -rf askpass.sh
      exit 1
    fi
  fi
}

#############################
### Optimizations  Set-up ###
#############################
# See link for more info
# https://blog.macstadium.com/blog/simple-optimizations-for-macos-and-ios-build-agents
function optimziations_setup {
  echo "------"

  echo "Optimizations steps..."

  echo ""
  ## Disable Spotlight
  MIN_OS=10.14
  if [ $(echo -e $MIN_OS"\n"$OS_VER | sort -V | tail -1) == "$MIN_OS" ]; then
    sudo -A launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist
  else
    echo "You running latest *macOS*"
    echo "You should disable SIP"
    echo "to disable *Spotlight*"
  fi

  sudo -A mdutil -a -i off
  sudo -A defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes"
  killall mds >/dev/null 2>&1
  sudo -A mdutil -a -i off

  ## Disable Siri
  MIN_OS=10.14
  if [ $(echo -e $MIN_OS"\n"$OS_VER | sort -V | tail -1) == "$MIN_OS" ]; then
    sudo -A plutil -replace Disabled -bool true /System/Library/LaunchAgents/com.apple.Siri.agent.plist || echo "Siri cannot be disabled, SIP enabled"
  else
    echo "You running latest *macOS*"
    echo "You should disable SIP"
    echo "to disable *Siri*"
  fi
  defaults write com.apple.Siri StatusMenuVisible -bool false
  defaults write com.apple.Siri UserHasDeclinedEnable -bool true
  defaults write com.apple.assistant.support "Assistant Enabled" 0

  ## Disable Software Update
  sudo -A softwareupdate --schedule off
}

#############################
### Run preparation steps ###
#############################
function check_and_prepare {
  check_env
  configure_askpass
  configure_env
  sudo_access_check
}

###################################
### Prepares linking and config ###
###################################
function pre_installation {
  echo "------"

  echo "Pre-installation steps..."

  echo ""
  echo "This step removes all of your previous config"
  read -p "Did you already backup up your config? [Y]es/[N]o. Default is [Y]:  " backup_ask
  backup_ask=${backup_ask:-Y}

  if [[ $backup_ask != "Y" && $backup_ask != "N" ]]; then
    echo "Please type *Y* or *N* !"
    echo "Wrong answer, exiting."
    exit 1
  fi

  ## Ensure these folders exists
  for ensure_folder in "${ENSURE_FOLDERS[@]}"; do
    mkdir -p "$HOME/$ensure_folder"
  done

  ## Link folders
  for link_folder in "${LINK_FOLDERS[@]}"; do
    if [[ $backup_ask == "Y" ]]; then
      rm -rf "$HOME/$link_folder"
    fi
    ln -vhs "$HOME/Desktop/config/dotfiles/$link_folder/" "$HOME/$link_folder"
  done

  ## Link files
  for link_file in "${LINK_FILES[@]}"; do
    if [[ $backup_ask == "Y" ]]; then
      rm -rf "$HOME/$link_file"
    fi
    ln -vh "$HOME/Desktop/config/dotfiles/$link_file" "$HOME/$link_file"
  done
}

#############################
### Packages installation ###
#############################

### Installing package manager
function install_package_manager {
  echo "------"

  # XCode requirements
  if sudo -A xcode-select --version >>/dev/null; then
    echo "XCode is already installed! Continue process..."
  else
    sudo -A xcode-select --install
  fi

  # Rosetta installation for Apple Silicon
  # This is required to run x64/x86 apps
  if [[ "$ARCH" == "arm64" ]]; then
    if [[ ! -f "/Library/Apple/System/Library/LaunchDaemons/com.apple.oahd.plist" ]]; then
      sudo -A softwareupdate --install-rosetta --agree-to-license
    else
      echo "Rosetta is already installed. Continue process..."
    fi
  fi

  # Install Homebrew
  if brew --version >>/dev/null; then
    echo "Homebrew is already installed! Continue process..."
  else
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash -
  fi
}
### Installing system packages
function install_system_packages {
  echo "------"

  BREWFILE_PATH="${ARCH}_$MODE"

  rm -rf Brewfile
  touch Brewfile
  cat "$PWD/base/Brewfile" >>Brewfile
  echo "" >>Brewfile # empty space for fix newline bug
  if [[ "$MODE" == "compact" ]]; then
    cat "$PWD/${ARCH}_minimal/Brewfile" >>Brewfile
    echo "" >>Brewfile # empty space for fix newline bug
  fi
  if [[ "$MODE" == "all" ]]; then
    cat "$PWD/${ARCH}_minimal/Brewfile" >>Brewfile
    echo "" >>Brewfile # empty space for fix newline bug
    cat "$PWD/${ARCH}_compact/Brewfile" >>Brewfile
    echo "" >>Brewfile # empty space for fix newline bug
  fi
  cat "$PWD/$BREWFILE_PATH/Brewfile" >>Brewfile

  # Installing bundle
  brew bundle --force --no-lock

  rm -rf $PWD/Brewfile
}

### Installation npm packages
function install_npm_packages {
  echo "------"

  echo "Installing npm packages..."

  INSTALLED_PACKAGES=$(npm list --global --depth=0 --json)
  for package in "${NPM_PACKAGES[@]}"; do
    if [[ $(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"") == "\"$package\"" ]]; then
      echo "Already installed npm package: $package"
    else
      npm install --global $package
    fi
  done
}

### Installation pip packages
function install_pip_packages {
  echo "------"

  echo "Installing pip packages..."

  INSTALLED_PACKAGES=$(pip list --format json)
  python3 -m pip install --upgrade pip
  for package in "${PIP_PACKAGES[@]}"; do
    if [[ $(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"") == "\"$package\"" ]]; then
      echo "Already installed pip package: $package"
    else
      python3 -m pip install $package
    fi
  done
}

## Installation Mac App Store apps
function install_mas_apps {
  echo "------"

  # iMovie
  mas install 408981434
  # Medis
  mas install 1063631769
  # Racompass
  mas install 1538380685
}

## Installation Node.js versions
function install_fnm_versions {
  echo "------"

  echo "Installing fnm versions..."

  INSTALLED_VERSION=$(fnm ls)
  for fnm_nvm in "${FNM_VERSIONS[@]}"; do
    if echo "$INSTALLED_VERSION" | grep "* v$fnm_nvm" >>/dev/null; then
      echo "Already installed fnm version: $fnm_nvm"
    else
      fnm install $fnm_nvm
    fi
  done
}

### POST-installation
### steps for configure
function post_installation {
  echo "------"

  echo "Pre-installation steps..."

  # neovim plugins installation
  nvim -c "PlugInstall" -c "qa"

  ### fish shell configuration
  FISH_SHELL_PATH=$(which fish)
  if grep -o "$FISH_SHELL_PATH" /etc/shells >>/dev/null; then
    echo "Already set fish as list of shells"
  else
    echo $FISH_SHELL_PATH | sudo -A tee -a /etc/shells
  fi
  sudo -A chsh -s $FISH_SHELL_PATH       # change for root
  sudo -A chsh -s $FISH_SHELL_PATH $USER # change for current user
}

#############################
### All installation step ###
#############################
function installation {
  pre_installation
  optimziations_setup

  install_package_manager
  install_system_packages

  ## Install npm and pip packages
  ## only on *compact* and *full*
  ## modes so all of these tools
  ## does not conflicts
  if [[ "$MODE" != "minimal" ]]; then
    install_npm_packages
    install_fnm_versions
    install_pip_packages
    install_mas_apps
  fi

  # Post-installation
  post_installation

  # Remove password by removing askpass
  rm -rf askpass.sh

  return 0
}

RETRIES=0

### Run preparation
### steps once
check_and_prepare

#############################
### Retry validation step ###
#############################
while true; do
  ### Installation done
  if installation; then
    echo "Your apps installed successfully..."
    echo "Enjoy..."
    break
    exit 0
  ### Installation failed
  else
    echo "Something got wrong..."
    echo "Retrying $RETRIES of $MAX_TRIES"
    RETRIES=$((RETRIES + 1))
    sleep 15
  fi
done
