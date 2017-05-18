#!/usr/bin/env bash

# Add our Adjust and Leanplum keys to the build depending on the scheme
if [ "$BUDDYBUILD_SCHEME" == FirefoxBeta ]; then
  echo "Setting Adjust environment to SANDBOX for $BUDDYBUILD_SCHEME"
  /usr/libexec/PlistBuddy -c "Set AdjustAppToken $ADJUST_KEY_SANDBOX" "Client/Info.plist"
  /usr/libexec/PlistBuddy -c "Set AdjustEnvironment sandbox" "Client/Info.plist"

  echo "Setting Leanplum environment to DEVELOPMENT for $BUDDYBUILD_SCHEME"
  /usr/libexec/PlistBuddy -c "Set LeanplumAppId $LEANPLUM_APP_ID" "Client/Info.plist"
  /usr/libexec/PlistBuddy -c "Set LeanplumEnvironment development" "Client/Info.plist"
  /usr/libexec/PlistBuddy -c "Set LeanplumKey $LEANPLUM_KEY_DEVELOPMENT" "Client/Info.plist"
elif [ "$BUDDYBUILD_SCHEME" == Firefox ]; then
  echo "Setting Adjust environment to PRODUCTION for $BUDDYBUILD_SCHEME"
  /usr/libexec/PlistBuddy -c "Set AdjustAppToken $ADJUST_KEY_PRODUCTION" "Client/Info.plist"
  /usr/libexec/PlistBuddy -c "Set AdjustEnvironment production" "Client/Info.plist"

  echo "Setting Leanplum environment to PRODUCTION for $BUDDYBUILD_SCHEME"
  /usr/libexec/PlistBuddy -c "Set LeanplumAppId $LEANPLUM_APP_ID" "Client/Info.plist"
  /usr/libexec/PlistBuddy -c "Set LeanplumEnvironment production" "Client/Info.plist"
  /usr/libexec/PlistBuddy -c "Set LeanplumKey $LEANPLUM_KEY_PRODUCTION" "Client/Info.plist"
fi

# Set the build number to match the Buddybuild number
agvtool new-version -all $BUDDYBUILD_BUILD_NUMBER
