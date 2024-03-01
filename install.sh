#!/usr/bin/env bash
set -e

#############################
### Environment variables ###
#############################
read -rp "Enter your password: " PASSWORD
read -rp "Did you already backup up your config? [Y]es/[N]o. Default is [Y]:  " backup_ask
PWD=$(pwd)
OS_VER=$(sw_vers -productVersion | cut -d':' -f2 | tr -d ' ')
MIN_OS=11.6

##############################
### Installation variables ###
##############################
MAX_TRIES=5

ENSURE_FOLDERS=(".npm-global/lib" "Desktop/dotfiles/.vim/autoload" ".gnupg")
LINK_FOLDERS=(".nano" ".vim" ".config")
LINK_FILES=(".nanorc" ".vimrc" ".tmux.conf" ".gitconfig" ".hushlogin")

# M1 incompatible npm packages: "bs-platform"
NPM_PACKAGES=("npm" "0x" "cordova" "esy" "flamebearer" "http-server" "node-gyp" "nodemon" "npm-check-updates" "typesync")
PIP_PACKAGES=("virtualenv" "jupyterlab" "notebook" "labelme" "labelImg" "psrecord")
PIPX_PACKAGES=("osxphotos")

FNM_VERSIONS=("18.19.1" "20.11.1")

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

  if [[ $(echo -e $MIN_OS"\n$OS_VER" | sort -V | tail -1) == "$MIN_OS" ]]; then
    echo "Your OS does not meet requirements"
    echo "Minimum required OS is: v11.6.x"
    exit 1
  fi

  if [[ $(ls ~/* 1>/dev/null) != "" ]]; then
    echo "You do not have permission, please give full-disk access"
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
  export NPM_CONFIG_PREFIX="$HOME/.npm-global"
  export SUDO_ASKPASS="$PWD/askpass.sh"
  export PATH="$NPM_CONFIG_PREFIX/bin:usr/local/bin:/opt/homebrew/bin:~/.local/bin:$PATH"

  # Homebrew environemnt variables
  export HOMEBREW_NO_ANALYTICS=1        # Homebrew disable telemetry
  export HOMEBREW_NO_GOOGLE_ANALYTICS=1 # Homebrew Google telemetry
  export HOMEBREW_NO_INSTALL_FROM_API=1 # Use Git for immediate changes
  export HOMEBREW_NO_ENV_HINTS=1        # Hide hints for cleaner logs
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

  sudo -A mdutil -a -i off
  sudo -A defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes"
  killall mds >/dev/null 2>&1
  sudo -A mdutil -a -i off
  sudo -A mdutil -a -i off /
  sudo -A mdutil -a -i off /*

  defaults write com.apple.Siri StatusMenuVisible -bool false
  defaults write com.apple.Siri UserHasDeclinedEnable -bool true
  defaults write com.apple.assistant.support "Assistant Enabled" 0
}

function finder_setup {
  echo "------"

  echo "Configuring Finder..."

  chflags nohidden ~/Library && xattr -d com.apple.FinderInfo ~/Library 2>/dev/null

  defaults write com.apple.finder NewWindowTarget -string "PfDe"
  defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"

  defaults write com.apple.finder DownloadsFolderListViewSettingsVersion -bool true
  defaults write com.apple.finder DownloadsFolderListViewSettingsVersion -int 1
  defaults write com.apple.finder FXArrangeGroupViewBy -string "Date Modified"
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  defaults write com.apple.finder FXPreferredGroupBy -string "None"
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  defaults write com.apple.finder FXRemoveOldTrashItems -bool true

  defaults write com.apple.finder FXSidebarUpgradedToTenFourteen -int 1
  defaults write com.apple.finder FXSidebarUpgradedToTenTen -int 1

  defaults write com.apple.finder FinderSpawnTab -bool false
  defaults write com.apple.finder NSNavLastUserSetHideExtensionButtonState -bool true
  defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
  defaults write com.apple.finder ShowRecentTags -bool false
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder ShowSidebar -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder SidebarShowingSignedIntoiCloud -bool true
  defaults write com.apple.finder SidebariCloudDriveSectionDisclosedState -bool true

  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:ExtendedListViewSettingsV2:calculateAllSizes true" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:ListViewSettings:calculateAllSizes true" ~/Library/Preferences/com.apple.finder.plist

  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:ExtendedListViewSettingsV2:textSize 12" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:ListViewSettings:textSize 12" ~/Library/Preferences/com.apple.finder.plist

  /usr/libexec/PlistBuddy -c "Set :ComputerViewSettings:CustomViewStyleVersion 1" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :ComputerViewSettings:WindowState:ContainerShowSidebar 1" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :ComputerViewSettings:WindowState:ShowTabView 1" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :ComputerViewSettings:WindowState:ShowToolbar 1" ~/Library/Preferences/com.apple.finder.plist

  # Avoid creating .DS_Store files on network or USB volumes
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

  defaults write com.apple.bird optimize-storage -bool false
  defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

  # Disable the “Are you sure you want to open this application?” dialog
  defaults write com.apple.LaunchServices LSQuarantine -bool false

  # Disable disk image verification
  defaults write com.apple.frameworks.diskimages skip-verify -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

  # Show item info near icons on the desktop and in other icon views
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist

  # Show item info to the right of the icons on the desktop
  /usr/libexec/PlistBuddy -c "Set DesktopViewSettings:IconViewSettings:labelOnBottom false" ~/Library/Preferences/com.apple.finder.plist

  # Enable snap-to-grid for icons on the desktop and in other icon views
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
}

function settings_setup {
  echo "------"

  echo "Configuring Settings..."

  osascript -e 'tell application "System Preferences" to quit'

  # General
  defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
  defaults write NSGlobalDomain AppleInterfaceStyle -string "Light"
  defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false

  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write NSGlobalDomain AppleShowScrollBars -string "Always"

  # Keyboard
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  # Sound
  defaults write NSGlobalDomain com.apple.sound.beep.feedback -bool true

  # Magic Trackpad config
  defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
  defaults write NSGlobalDomain com.apple.trackpad.scaling -float 0.875

  defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -bool false
  defaults write com.apple.AppleMultitouchTrackpad ActuationStrength -bool false
  defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true

  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

  defaults write com.apple.AppleMultitouchTrackpad TrackpadPinch -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadPinch -bool false

  defaults write com.apple.AppleMultitouchTrackpad TrackpadRotate -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRotate -bool false

  defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -bool false

  defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerDoubleTapGesture -bool false

  defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -bool false

  # Missiong control
  defaults write com.apple.dock mru-spaces -bool false
  defaults write com.apple.dock showAppExposeGestureEnabled -bool true
  defaults write com.apple.dock showLaunchpadGestureEnabled -bool true
  defaults write com.apple.dock expose-group-apps -bool true
  defaults write com.apple.dock expose-group-by-app -bool true

  # Dock
  defaults write com.apple.dock show-recents -bool false

  # Activity Monitor
  defaults write com.apple.ActivityMonitor OpenMainWindow -bool false
  defaults write com.apple.ActivityMonitor SelectedTab -int 1
  defaults write com.apple.ActivityMonitor ShowCategory -bool false
  defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
  defaults write com.apple.ActivityMonitor UpdatePeriod -int 1

  # Software Update
  defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
  defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
  defaults write com.apple.SoftwareUpdate ConfigDataInstall -int 1
  defaults write com.apple.commerce AutoUpdate -bool true
  defaults write com.apple.commerce AutoUpdateRestartRequired -bool true

  # Privacy
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Time Machine
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  # Screenshots
  defaults write com.apple.screencapture location -string "${HOME}/Desktop"
  defaults write com.apple.screencapture type -string "png"
  defaults write com.apple.screencapture disable-shadow -bool true

  # Debug & Dev-mode
  defaults write com.apple.appstore WebKitDeveloperExtras -bool true
  defaults write com.apple.appstore ShowDebugMenu -bool true

  # Prevent Photos from opening automatically when devices are plugged in
  defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

  # Disk Utility
  defaults write com.apple.DiskUtility SidebarShowAllDevices -bool true

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
######## Prepares dotfiles ########
###################################
function dotfiles_installation {
  echo "------"

  echo "dotfiles-installation steps..."

  echo ""
  echo "This step may remove all of your previous config"
  backup_ask=${backup_ask:-Y}

  if [[ $backup_ask != "Y" && $backup_ask != "N" ]]; then
    echo "Please type *Y* or *N* !"
    echo "Wrong answer, exiting."
    exit 1
  fi

  # For working integration
  git clone \
    https://github.com/dalisoft/dotfiles.git \
    ~/Desktop/dotfiles \
    --recursive 2>/dev/null

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
}

#############################
### Packages installation ###
#############################

### Installing package manager
function install_package_manager {
  echo "------"

  # Install Homebrew
  if brew --version >/dev/null; then
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
  #brew install --cask casks/*.rb
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
      npm install --global "$package"
    fi
  done
}

### Installation pip packages
function install_pip_packages {
  echo "------"

  echo "Installing pip packages..."

  INSTALLED_PACKAGES=$(python3 -m pip list --format json)
  python3 -m pip install --upgrade pip
  for package in "${PIP_PACKAGES[@]}"; do
    if [[ $(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"") == "\"$package\"" ]]; then
      echo "Already installed pip package: $package"
    else
      python3 -m pip install "$package"
    fi
  done
}

### Installation pipx packages
function install_pipx_packages {
  echo "------"

  echo "Installing pipx packages..."

  INSTALLED_PACKAGES=$(pipx list --json)
  for package in "${PIPX_PACKAGES[@]}"; do
    if [[ $(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"") == "\"$package\"" ]]; then
      echo "Already installed pipx package: $package"
    else
      pipx install "$package"
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
      fnm install "$fnm_nvm"
    fi
  done
}

### POST-installation
### steps for configure
function post_installation {
  echo "------"

  # Load post-environment variables
  BREW_PREFIX=$(brew --prefix)

  echo "Post-installation steps..."

  # Mutagen prepare
  # mutagen daemon register
  # mutagen daemon start

  # GnuPG configuration
  sudo -A rm -rf "$HOME/.gnupg/gpg-agent.conf"
  echo "pinentry-program $(which pinentry-mac)" >>"$HOME/.gnupg/gpg-agent.conf"
  echo "default-cache-ttl 3600" >>"$HOME/.gnupg/gpg-agent.conf"
  echo "max-cache-ttl 14400" >>"$HOME/.gnupg/gpg-agent.conf"
  echo "enable-ssh-support" >>"$HOME/.gnupg/gpg-agent.conf"
  echo "extra-socket $HOME/.gnupg/S.gpg-agent.extra" >>"$HOME/.gnupg/gpg-agent.conf"
  chown -R "$USER" "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
  chmod 600 "$HOME/.gnupg/gpg-agent.conf"

  # neovim plugins installation
  wget -O "$HOME/Desktop/dotfiles/.vim/autoload/plug.vim" https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  nvim -c "PlugInstall" -c "qa"

  # use XCode SDK tools
  sudo -A xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo -A xcodebuild -license accept

  if [[ ! -f $BREW_PREFIX/bin/python && -f $BREW_PREFIX/bin/python3 ]]; then
    sudo -A ln -s "$BREW_PREFIX/bin/python3" "$BREW_PREFIX/bin/python"
    echo "Python3 → Python2 patch was applied"
  fi

  # link OpenJDK
  sudo -A ln -sfn "$BREW_PREFIX/opt/openjdk@11/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk@11.jdk"
  echo "OpenJDK patch was applied"

  # locate binaries
  sudo -A ln -vh "$PWD/utils/remme.sh" "$BREW_PREFIX/bin/remme"
  sudo -A ln -vh "$PWD/utils/git-show-lfs.sh" "$BREW_PREFIX/bin/git-show-lfs"
  sudo -A ln -vh "$PWD/utils/mkv2mp4.sh" "$BREW_PREFIX/bin/mkv2mp4"

  ### fish shell configuration
  FISH_SHELL_PATH=$(which fish)
  if grep -o "$FISH_SHELL_PATH" /etc/shells >>/dev/null; then
    echo "Already set fish as list of shells"
  else
    echo "$FISH_SHELL_PATH" | sudo -A tee -a /etc/shells
  fi
  sudo -A chsh -s "$FISH_SHELL_PATH"         # change for root
  sudo -A chsh -s "$FISH_SHELL_PATH" "$USER" # change for current user
  echo "shell → fish was set"

  # Terminal set theme
  defaults write com.apple.Terminal Shell "login -pfql $USER $BREW_PREFIX/bin/fish"
  defaults write com.apple.Terminal NSNavLastRootDirectory "$HOME/Desktop/dotfiles"
  defaults write com.apple.Terminal "Default Window Settings" "Transcluent"
  defaults write com.apple.Terminal "Startup Window Settings" "Transcluent"
}

#############################
### All installation step ###
#############################
function installation {
  # optimziations_setup
  finder_setup
  settings_setup

  install_package_manager
  install_system_packages

  # dotfiles installation
  dotfiles_installation

  install_npm_packages
  install_fnm_versions
  install_pip_packages
  install_pipx_packages
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
    echo "Please reboot your device!!!"
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
