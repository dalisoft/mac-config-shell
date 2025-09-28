#!/bin/sh
set -eu

#############################
### Environment variables ###
#############################
printf "%b" "Enter your password: "
stty -echo
read -r PASSWORD
stty echo
printf "\n%s\n" "Did you already backup up your config? [Y]es/[N]o. Default is [Y]:  "
read -r backup_ask
PWD=$(pwd)
OS_VER=$(sw_vers -productVersion | cut -d':' -f2 | tr -d ' ')
MIN_OS=14.6

##############################
### Installation variables ###
##############################
MAX_TRIES=5

ENSURE_FOLDERS=".npm-global/lib .vim/autoload .gnupg"
LINK_FOLDERS=".nano .vim .config"
LINK_FILES=".nanorc .vimrc .tmux.conf .gitconfig .hushlogin"

NPM_PACKAGES="@anthropic-ai/claude-code @github/copilot @google/gemini-cli @openai/codex 0x cordova @qwen-code/qwen-code@latest esy flamebearer git-stats http-server neon-cli node-gyp nodemon npm npm-check-updates opencode-ai typesync"
PIP_PACKAGES="jupyterlab labelImg labelme notebook psrecord[plot] virtualenv"
UV_TOOLS="claude-monitor osxphotos"

FNM_VERSIONS="18.20.8 20.19.5 22.19.0"

#############################
### Preparations of steps ###
#############################

### Check and prompts ENV
### variables
check_env() {
  if [ -z "$PASSWORD" ]; then
    echo "Hey, welcome! please trust me"
    echo "and enter valid password here"
    echo "I hope you understand me..."
    exit 1
  fi

  if [ "$(printf "%b" $MIN_OS"\n$OS_VER" | sort -V | tail -1)" = "$MIN_OS" ]; then
    echo "Your OS does not meet requirements"
    echo "Minimum required OS is: v14.6.x"
    exit 1
  fi

  if ! ls ~/* 1>/dev/null; then
    echo "You do not base permission, please give script permission"
    exit 1
  fi
  if ! cat /Library/Preferences/com.apple.TimeMachine.plist 1>/dev/null; then
    echo "You do not have full-disk permission, please give full-disk access"
    exit 1
  fi
}
### Configure SUDO
### Askpass file
configure_askpass() {
  rm -rf askpass.sh
  echo "#!/bin/sh" >>./askpass.sh
  echo "echo \"$PASSWORD\"" >>./askpass.sh
  chmod 700 askpass.sh
}

### Configre ENV
### for future actions
configure_env() {
  export NPM_CONFIG_PREFIX="$HOME/.npm-global"
  export SUDO_ASKPASS="$PWD/askpass.sh"
  export PATH="$NPM_CONFIG_PREFIX/bin:usr/local/bin:/opt/homebrew/bin:~/.local/bin:$PATH"

  # Homebrew environemnt variables
  export HOMEBREW_NO_ANALYTICS=1 # Homebrew disable telemetry
  export HOMEBREW_NO_ENV_HINTS=1 # Hide hints for cleaner logs
}

### Check for SUDO
### access check to
### validate
sudo_access_check() {
  if [ "$(id -u)" = 0 ]; then
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
optimziations_setup() {
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

finder_setup() {
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

settings_setup() {
  echo "------"

  echo "Configuring Settings..."

  osascript -e 'tell application "System Preferences" to quit'

  #########################
  ######## General ########
  #########################
  # General
  defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
  defaults write NSGlobalDomain AppleInterfaceStyle -string "Light"
  defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false

  # UI
  defaults -currentHost write -g AppleFontSmoothing -int 0

  # Finder?
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write NSGlobalDomain AppleShowScrollBars -string "Always"

  #########################
  ####### Keyboard ########
  #########################
  # Keyboard
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  # Keyboard (UI tooltip)
  sudo -A defaults write /Library/Preferences/FeatureFlags/Domain/UIKit.plist redesigned_text_cursor -dict-add Enabled -bool NO

  # Sound
  defaults write NSGlobalDomain com.apple.sound.beep.feedback -bool true

  #########################
  # Magic Trackpad config #
  #########################
  # Point & Click → Force Click and haptic feedback
  defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -bool false
  defaults write com.apple.AppleMultitouchTrackpad ActuationStrength -bool false
  defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true

  # Point & Click → Tap-to-Click
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

  defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerDoubleTapGesture -bool false

  # Point & Click → Look up & data detectors
  defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -bool false

  # Scroll & Zoom → Scroll direction
  defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
  defaults write NSGlobalDomain com.apple.trackpad.scaling -float 0.875

  # Scroll & Zoom → Zoom-in-or-Out
  defaults write com.apple.AppleMultitouchTrackpad TrackpadPinch -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadPinch -bool true

  # Scroll & Zoom → Rotate
  defaults write com.apple.AppleMultitouchTrackpad TrackpadRotate -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRotate -bool false

  defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -bool false
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -bool false

  # More Gestures → App Expose
  defaults write com.apple.dock showAppExposeGestureEnabled -bool true
  # More Gestures → Launchpad
  defaults write com.apple.dock showLaunchpadGestureEnabled -bool true

  #########################
  ### Missiong control ####
  #########################
  defaults write com.apple.dock mru-spaces -bool false
  defaults write com.apple.dock expose-group-apps -bool true
  defaults write com.apple.dock expose-group-by-app -bool true

  #########################
  ######### Dock ##########
  #########################
  defaults write com.apple.dock show-recents -int 0

  #########################
  ### Activity Monitor ####
  #########################
  defaults write com.apple.ActivityMonitor OpenMainWindow -bool false
  defaults write com.apple.ActivityMonitor SelectedTab -int 1
  defaults write com.apple.ActivityMonitor ShowCategory -bool false
  defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
  defaults write com.apple.ActivityMonitor UpdatePeriod -int 1

  #########################
  ### Software Update ####
  #########################
  defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
  defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
  defaults write com.apple.SoftwareUpdate ConfigDataInstall -int 1
  defaults write com.apple.commerce AutoUpdate -bool false
  defaults write com.apple.commerce AutoUpdateRestartRequired -bool true

  #########################
  ######## Privacy ########
  #########################
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  #########################
  ##### Time Machine ######
  #########################
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  #########################
  ###### Screenshots ######
  #########################
  defaults write com.apple.screencapture location -string "${HOME}/Desktop"
  defaults write com.apple.screencapture type -string "png"
  defaults write com.apple.screencapture disable-shadow -bool true

  #########################
  ######## Safari #########
  #########################
  defaults write com.apple.appstore WebKitDeveloperExtras -bool true
  defaults write com.apple.appstore ShowDebugMenu -bool true

  # Prevent Photos from opening automatically when devices are plugged in
  defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

  #########################
  ##### Disk Utility ######
  #########################
  defaults write com.apple.DiskUtility SidebarShowAllDevices -bool true
}

#############################
### Run preparation steps ###
#############################
check_and_prepare() {
  check_env
  configure_askpass
  configure_env
  sudo_access_check
}

###################################
######## Prepares dotfiles ########
###################################
dotfiles_installation() {
  echo "------"

  echo "dotfiles-installation steps..."

  echo ""
  echo "This step may remove all of your previous config"
  backup_ask=${backup_ask:-Y}

  if [ "$backup_ask" != "Y" ] && [ "$backup_ask" != "N" ]; then
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
  for ensure_folder in ${ENSURE_FOLDERS}; do
    mkdir -p "$HOME/$ensure_folder"
  done

  ## Link folders
  for link_folder in ${LINK_FOLDERS}; do
    if [ "$backup_ask" = "Y" ]; then
      rm -rf "${HOME}/${link_folder:?}"
    fi
    ln -vs "$HOME/Desktop/dotfiles/$link_folder/" "$HOME/$link_folder"
  done

  ## Link files
  for link_file in ${LINK_FILES}; do
    if [ "$backup_ask" = "Y" ]; then
      rm -rf "${HOME}/${link_file:?}"
    fi
    ln -vs "$HOME/Desktop/dotfiles/$link_file" "$HOME/$link_file"
  done
}

#############################
### Packages installation ###
#############################

### Installing package manager
install_package_manager() {
  echo "------"

  # Install Homebrew
  if command -v brew; then
    echo "Homebrew is already installed! Continue process..."
  else
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash -
  fi
}

### Installing system packages
install_system_packages() {
  echo "------"

  # Install `mas` for asking Apple ID for App Store
  brew install mas
  # Infuse installation check
  if ! mas install 1136220934 1>/dev/null; then
    echo "Mac App Store failed to run."
    echo "Please ensure you're logged in to App Store"
    exit 1
  fi

  # Installing bundle
  brew bundle --no-lock --verbose
}

### Installation npm packages
install_npm_packages() {
  echo "------"

  echo "Installing npm packages..."

  INSTALLED_PACKAGES=$(npm list --global --depth=0 --json)
  for package in ${NPM_PACKAGES}; do
    if [ "$(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"")" = "\"$package\"" ]; then
      echo "Already installed npm package: $package"
    else
      npm install --global "$package"
    fi
  done
}

### Installation pip packages
install_pip_packages() {
  echo "------"

  echo "Installing pip packages..."

  INSTALLED_PACKAGES=$(pip list --format json)
  pip install --upgrade pip
  for package in ${PIP_PACKAGES}; do
    if [ "$(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"")" = "\"$package\"" ]; then
      echo "Already installed pip package: $package"
    else
      pip install "$package"
    fi
  done
}

### Installation uv tools
install_uv_tools() {
  echo "------"

  echo "Installing uv tools..."

  INSTALLED_PACKAGES=$(uv tool list)
  for package in ${UV_TOOLS}; do
    if [ "$(echo "$INSTALLED_PACKAGES" | grep -o "\"$package\"")" = "\"$package\"" ]; then
      echo "Already installed uv tool: $package"
    else
      uv tool install --python 3.12 "$package"
    fi
  done
}

## Installation Mac App Store apps
install_mas_apps() {
  echo "------"

  echo "Installed already via Homebrew"
}

## Installation Node.js versions
install_fnm_versions() {
  echo "------"

  echo "Installing fnm versions..."

  INSTALLED_VERSION=$(fnm ls)
  for fnm_nvm in ${FNM_VERSIONS}; do
    if echo "$INSTALLED_VERSION" | grep "\* v${fnm_nvm}" >>/dev/null; then
      echo "Already installed fnm version: $fnm_nvm"
    else
      fnm install "$fnm_nvm"
    fi
  done

  # Use and set as default `system` node
  fnm use system
  fnm default system
}

### POST-installation
### steps for configure
post_installation() {
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
  chown -R "$USER" ~/.gnupg
  chmod 700 ~/.gnupg
  chmod 600 ~/.gnupg/*
  chmod 644 ~/.gnupg/*.d

  # neovim plugins installation
  wget -O "$HOME/.vim/autoload/plug.vim" https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  nvim -c "PlugInstall" -c "qa"

  # use XCode SDK tools
  sudo -A xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo -A xcodebuild -license accept

  if [ ! -f "${BREW_PREFIX}/bin/python" ] && [ -f "${BREW_PREFIX}/bin/python3" ]; then
    sudo -A ln -s "$BREW_PREFIX/bin/python3" "$BREW_PREFIX/bin/python"
    echo "Python3 → Python2 patch was applied"
  fi

  # Rustup toolchain
  rustup-init --profile complete --default-toolchain stable -y --no-modify-path

  # link OpenJDK
  sudo -A ln -sfn "$BREW_PREFIX/opt/openjdk@11/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-11.jdk"
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

  # Unstable: Enable Remote Apple Events
  # sudo -A systemsetup -setremoteappleevents on

  # Unstable: Enable Remote login
  # sudo -A systemsetup -setremotelogin on
  # sudo -A dseditgroup -o edit -a "${USER}" -t user com.apple.access_ssh

  # Reload SSHD
  if ! grep 'PasswordAuthentication no' /etc/ssh/sshd_config; then
    sudo -A launchctl stop com.openssh.sshd
    echo "PasswordAuthentication no" | sudo -A tee /etc/ssh/sshd_config
    echo "PubkeyAuthentication yes" | sudo -A tee /etc/ssh/sshd_config
    sudo -A launchctl stop com.openssh.sshd
  fi

  # Enable Firewall
  sudo -A /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

  # Terminal set theme
  defaults write com.apple.Terminal Shell "login -pfql $USER $BREW_PREFIX/bin/fish"
  defaults write com.apple.Terminal NSNavLastRootDirectory "$HOME/Desktop/dotfiles"
  defaults write com.apple.Terminal "Default Window Settings" "Transcluent"
  defaults write com.apple.Terminal "Startup Window Settings" "Transcluent"
}

#############################
### All installation step ###
#############################
installation() {
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

# We should kill sleep prevention before installation
killall caffeinate

# Avoid sleep for make sure all apps installed
caffeinate -sdt 43200 &
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

# We can kill sleep prevention after successfully installation
killall caffeinate
