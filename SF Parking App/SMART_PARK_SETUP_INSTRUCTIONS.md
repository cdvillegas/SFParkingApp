# Smart Park 2.0 - Xcode Project Configuration

## Required Manual Xcode Configuration Steps

Since I cannot directly modify the .xcodeproj file, please complete these configuration steps in Xcode:

### 1. Add AppIntents Framework
1. Open the project in Xcode
2. Select the app target "SF Parking App"
3. Go to "Build Phases" → "Link Binary With Libraries"
4. Click "+" and add `AppIntents.framework`

### 2. Add Required Capabilities  
⚠️ **Personal Team (Free Account) Users:** Skip Siri and App Groups - they're not supported

**For Paid Developer Account:**
1. In the project navigator, select the "SF Parking App" target
2. Go to "Signing & Capabilities"
3. Click "+" Capability and add:
   - **Siri** (for voice commands)
   - **App Groups** (for advanced data sharing)
4. Set the App Group identifier to: `group.com.zshor.SFParkingApp`

**For Personal Team (Free Account):**
1. Only add **Background Modes** capability
2. Enable: Location updates ✅, Background processing ✅

### 3. Configure Background Modes
1. In "Signing & Capabilities", add **Background Modes** capability
2. Enable:
   - ✅ Location updates
   - ✅ Background processing

### 4. Update Build Settings
Add these Info.plist keys (if using build settings approach):
```
INFOPLIST_KEY_UIBackgroundModes = "location background-processing";
INFOPLIST_KEY_NSSupportsLiveActivities = NO;
INFOPLIST_KEY_NSUserActivityTypes = "SaveParkingLocationIntent CheckCarConnectionIntent";
```

### 5. Verify Info.plist File
If the project now uses the Info.plist file I created, ensure it's selected in:
- Target → "Build Settings" → "Info.plist File" should point to "SF Parking App/Info.plist"

### 6. Test App Intents Integration
After configuration, test that:
1. App builds successfully
2. App Shortcuts appear in Settings → Siri & Search → SF Parking App
3. Shortcuts app can discover the intents

## Files Created for Smart Park 2.0

✅ **Core/Intents/ParkingLocationIntent.swift** - Main App Intents
✅ **Core/Intents/AppShortcutsProvider.swift** - App Shortcuts configuration  
✅ **Core/Managers/ParkingLocationManager.swift** - Location management
✅ **SF Parking App.entitlements** - App capabilities
✅ **Info.plist** - App configuration
✅ **Updated NotificationManager.swift** - Notification handling
✅ **Updated SF_Parking_AppApp.swift** - App initialization

## How Users Will Set Up Smart Park 2.0

1. **Install App** - Smart Park intents become available immediately
2. **Open Shortcuts App** - Find "Save Parking Location" in the gallery
3. **Create Automation**:
   - Trigger: "When I disconnect from CarPlay" or "When Bluetooth disconnects from [Device Name]"
   - Action: "Save Parking Location" (from SF Parking App)
   - Configure: Set trigger type and Bluetooth device name if needed
4. **Test** - Disconnect from car and verify location is saved with 2-minute confirmation

## Troubleshooting

If App Intents don't appear:
- Verify AppIntents framework is linked
- Check entitlements file is properly configured
- Ensure target deployment is iOS 16.0+
- Test on physical device (Simulator may not show all Shortcuts features)