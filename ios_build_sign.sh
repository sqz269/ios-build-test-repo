# Assert to check if the script is running on MacOS
if [ "$(uname)" != "Darwin" ]; then
    echo "This script is only supported on MacOS"
    exit 1
fi

# Assert to check if the required environment variables are set
if [ -z "$APPLE_DEVELOPER_TEAM_ID" ]; then
    echo "Please set the APPLE_DEVELOPER_TEAM_ID environment variable"
    exit 1
fi

if [ -z "$APPLE_DEVELOPER_EMAIL" ]; then
    echo "Please set the APPLE_DEVELOPER_EMAIL environment variable"
    exit 1
fi

if [ -z "$APP_SPECIFIC_PASSWORD" ]; then
    echo "Please set the APP_SPECIFIC_PASSWORD environment variable"
    exit 1
fi

# Identify the P12 Cert name from the keychain
P12_CERTIFICATE_NAME=$(security find-identity -v -p codesigning | grep -o '"[^"]*"' | head -1 | sed 's/"//g')
echo "P12_CERTIFICATE_NAME: $P12_CERTIFICATE_NAME"

# Identify the Provisioning Profile UUID
PROVISIOING_PROFILE_UUID=$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< $(/usr/bin/security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision))
echo "PROVISIOING_PROFILE_UUID: $PROVISIOING_PROFILE_UUID"

APP_BUNDLE_ID=$(cat ios/Runner.xcodeproj/project.pbxproj | grep -o "PRODUCT_BUNDLE_IDENTIFIER = [^;]*" | head -1 | cut -d ' ' -f 3)
echo "APP_BUNDLE_ID: $APP_BUNDLE_ID"

echo "Building and signing the iOS app..."
# archive
xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -sdk iphoneos \
    -configuration Release \
    -archivePath $PWD/build/Runner.xcarchive \
    clean archive \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="$PROVISIOING_PROFILE_UUID" \
    DEVELOPMENT_TEAM="$APPLE_DEVELOPER_TEAM_ID" \
    CODE_SIGN_IDENTITY="$P12_CERTIFICATE_NAME"

# Create ExportOptions.plist
echo "Creating ExportOptions.plist..."
cat <<EOF > ExportOptions.plist
<?xml version="1.0" encoding="UTF-8"?>
<dict>
    <key>provisioningProfiles</key>
    <dict>
        <key>$APP_BUNDLE_ID</key>
        <string>$PROVISIOING_PROFILE_UUID</string>
    </dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>signingCertificate</key>
    <string>$P12_CERTIFICATE_NAME</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>$APPLE_DEVELOPER_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

echo "Exporting IPA..."
# Export IPA
xcodebuild \
    -exportArchive \
    -archivePath $PWD/build/Runner.xcarchive \
    -exportPath $PWD/build/IPA \
    -exportOptionsPlist ExportOptions.plist

echo "iOS app signed successfully!"

# find the ipa file name created
IPA_FILE_NAME=$(ls $PWD/build/IPA/*.ipa)
echo "IPA_FILE_NAME: $IPA_FILE_NAME"

# echo "Upoloading the IPA to App Store Connect..."
# upload IPA to App Store Connect
xcrun altool --upload-app -f $PWD/build/IPA/$IPA_FILE_NAME -t ios -u $APPLE_DEVELOPER_EMAIL -p @env:APP_SPECIFIC_PASSWORD

