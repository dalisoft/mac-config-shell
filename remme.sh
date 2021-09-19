#!/bin/bash
set -e

#############################
### Remove-Me Auto-script ###
#############################

# Environment variables
CLEAN_FOLDERS=(
  # System library clean folders
  "/Library/LaunchDaemons"
  "/Library/LaunchAgents"
  "/Library/PrivilegedHelperTools"
  # User library clean folders
  "$HOME/Library/LaunchAgents"
  "$HOME/Library/Preferences"
  "$HOME/Library/Caches"
  "$HOME/Library/Logs"
  "$HOME/Library/Containers"
  "$HOME/Library/Application Scripts"
  "$HOME/Library/Application Support"
  # Temporarily folders
  "/var/folders"
)

if [[ "$1" == "" ]]; then
  echo "Application path is required!"
  echo "example, /Applications/XCode.app"
  exit 0
fi

# Identify Apps
APP_NAME=$(/usr/libexec/PlistBuddy -c "print CFBundleName" "$1/Contents/Info.plist" 2>/dev/null)
APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "print CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null)

# Remove app itself
sudo rm -rf "$1"

# Cleanup apps from these folders
for folder in "${CLEAN_FOLDERS[@]}"; do
  sudo find "$folder" -d -iname "$APP_IDENTIFIER*" -delete 2>/dev/null || echo "" >/dev/null
  sudo find "$folder" -d -iname "$APP_NAME*" -delete 2>/dev/null || echo "" >/dev/null
done
