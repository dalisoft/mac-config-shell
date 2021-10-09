#!/bin/bash
set -e

#############################
### Environment variables ###
#############################
read -p "Enter your password: " PASSWORD
ARCH=$(uname -m)
PWD=$(pwd)
OS_VER=$(sw_vers -productVersion | cut -d':' -f2 | tr -d ' ')

##############################
### Installation variables ###
##############################
MAX_TRIES=5

ENSURE_FOLDERS=(".npm-global" "Desktop/dotfiles/.vim/autoload")
LINK_FOLDERS=(".nano" ".vim" ".config")
LINK_FILES=(".nanorc" ".vimrc" ".tmux.conf" ".gitconfig")

# M1 incompatible npm packages: "bs-platform"
NPM_PACKAGES=("npm" "0x" "cordova" "esy" "flamebearer" "http-server" "node-gyp" "nodemon" "npm-check-updates" "typesync")
PIP_PACKAGES=("virtualenv" "jupyterlab" "notebook" "labelme" "psrecord")

FNM_VERSIONS=("12.22.6" "14.18.0")

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
  export PATH="$NPM_CONFIG_PREFIX/bin:usr/local/bin:/opt/homebrew/bin:$PATH"
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
  sudo -A mdutil -a -i off /
  sudo -A mdutil -a -i off /*

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
    ln -vs "$HOME/Desktop/dotfiles/$link_folder/" "$HOME/$link_folder"
  done

  ## Link files
  for link_file in "${LINK_FILES[@]}"; do
    if [[ $backup_ask == "Y" ]]; then
      rm -rf "$HOME/$link_file"
    fi
    ln -vs "$HOME/Desktop/dotfiles/$link_file" "$HOME/$link_file"
  done

  exit 0
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

  # Installing bundle
  brew bundle --no-lock --verbose
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

  echo "Installed already via Homebrew"
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
    # Set default to 14 for compatibility
    fnm default 14
  done
}

### POST-installation
### steps for configure
function post_installation {
  echo "------"

  # Load post-environment variables
  BREW_PREFIX=$(brew --prefix)

  echo "Post-installation steps..."

  # neovim plugins installation
  wget -O "$HOME/Desktop/dotfiles/.vim/autoload/plug.vim" https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  nvim -c "PlugInstall" -c "qa"

  # use XCode SDK tools
  sudo -A xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo -A xcodebuild -license accept

  # link OpenJDK
  sudo -A ln -sfn $BREW_PREFIX/opt/openjdk@11/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk@11.jdk

  # locate `RemMe`
  sudo -A ln -vh $(pwd)/remme.sh $BREW_PREFIX/bin/remme

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

  install_npm_packages
  install_fnm_versions
  install_pip_packages
  install_mas_apps

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
    exit 0
  ### Installation failed
  else
    echo "Something got wrong..."
    echo "Retrying $RETRIES of $MAX_TRIES"
    RETRIES=$((RETRIES + 1))
    sleep 15
  fi
done
