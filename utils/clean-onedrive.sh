#!/bin/bash
set -euo pipefail

UNLOAD_EXTENSIONS=(
  com.microsoft.OneDriveStandaloneUpdater.plist
  com.microsoft.OneDriveStandaloneUpdaterDaemon.plist
  com.microsoft.OneDriveUpdaterDaemon.plist
  com.microsoft.SyncReporter
)

CLEAN_FILES=(
  # System library clean folders
  /Library/LaunchAgents/com.microsoft.OneDriveStandaloneUpdater.plist
  /Library/LaunchDaemons/com.microsoft.OneDriveStandaloneUpdaterDaemon.plist
  /Library/LaunchDaemons/com.microsoft.OneDriveUpdaterDaemon.plist
  /Library/Logs/Microsoft/OneDrive
  # User library clean folders
  ~/Library/Application\ Scripts/*.OfficeOneDriveSyncIntegration
  ~/Library/Application\ Scripts/*.OneDriveStandaloneSuite
  ~/Library/Application\ Scripts/com.microsoft.OneDrive-mac
  ~/Library/Application\ Scripts/com.microsoft.OneDrive.FileProvider
  ~/Library/Application\ Scripts/com.microsoft.OneDrive.FinderSync
  ~/Library/Application\ Scripts/com.microsoft.OneDriveLauncher
  ~/Library/Application\ Support/com.microsoft.OneDrive
  ~/Library/Application\ Support/com.microsoft.OneDriveUpdater
  ~/Library/Application\ Support/FileProvider/com.microsoft.OneDrive.FileProvider
  ~/Library/Application\ Support/OneDrive
  ~/Library/Application\ Support/OneDriveUpdater
  ~/Library/Caches/com.microsoft.OneDrive
  ~/Library/Caches/com.microsoft.OneDriveStandaloneUpdater
  ~/Library/Caches/com.microsoft.OneDriveUpdater
  ~/Library/Caches/com.plausiblelabs.crashreporter.data/com.microsoft.OneDrive
  ~/Library/Caches/com.plausiblelabs.crashreporter.data/com.microsoft.OneDriveUpdater
  ~/Library/Caches/OneDrive
  ~/Library/Containers/com.microsoft.OneDrive.FileProvider
  ~/Library/Containers/com.microsoft.OneDrive.FinderSync
  ~/Library/Containers/com.microsoft.OneDriveLauncher
  ~/Library/Cookies/com.microsoft.OneDrive.binarycookies
  ~/Library/Cookies/com.microsoft.OneDriveUpdater.binarycookies
  ~/Library/Group\ Containers/*.OfficeOneDriveSyncIntegration
  ~/Library/Group\ Containers/*.OneDriveStandaloneSuite
  ~/Library/Group\ Containers/*.OneDriveSyncClientSuite
  ~/Library/Group\ Containers/*.com.microsoft.oneauth
  ~/Library/Group\ Containers/*.com.microsoft.rdc
  ~/Library/Group\ Containers/*.Kfm
  ~/Library/HTTPStorages/com.microsoft.OneDrive
  ~/Library/HTTPStorages/com.microsoft.OneDrive.binarycookies
  ~/Library/HTTPStorages/com.microsoft.OneDriveStandaloneUpdater
  ~/Library/HTTPStorages/com.microsoft.OneDriveStandaloneUpdater.binarycookies
  ~/Library/Logs/OneDrive
  ~/Library/Preferences/*.OneDriveStandaloneSuite.plist
  ~/Library/Preferences/com.microsoft.OneDrive.plist
  ~/Library/Preferences/com.microsoft.OneDriveStandaloneUpdater.plist
  ~/Library/Preferences/com.microsoft.OneDriveUpdater.plist
  ~/Library/WebKit/com.microsoft.OneDrive
  # Application itself
  # /Applications/OneDrive.app
  # Location itself
  ~/OneDrive
  ~/OneDrive*
  ~/Library/CloudStorage/OneDrive
  ~/Library/CloudStorage/OneDrive*
)

# Kill all OneDrive prefixed processes
killall OneDrive* 2>/dev/null || echo -n

if [ -f /Applications/OneDrive.app/Contents/Resources/RemoveOneDriveCreds.command ]; then
  # shellcheck source=/dev/null
  bash /Applications/OneDrive.app/Contents/Resources/RemoveOneDriveCreds.command
fi
if [ -f /Applications/OneDrive.app/Contents/Resources/ResetOneDriveApp.command ]; then
  # shellcheck source=/dev/null
  bash /Applications/OneDrive.app/Contents/Resources/ResetOneDriveApp.command
fi

for extension in "${UNLOAD_EXTENSIONS[@]}"; do
  sudo launchctl remove ${extension} 2>/dev/null || echo -n

  sudo launchctl unload -w /Library/LaunchAgents/${extension} 2>/dev/null || echo -n
  sudo launchctl unload -w /Library/LaunchDaemons/${extension} 2>/dev/null || echo -n

  sudo launchctl unload -w ~/Library/LaunchAgents/${extension} 2>/dev/null || echo -n
  sudo launchctl unload -w ~/Library/LaunchDaemons/${extension} 2>/dev/null || echo -n
done

sudo rm -rf "${CLEAN_FILES[@]}"
