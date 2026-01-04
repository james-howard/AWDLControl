#  AWDL Control

Apple Wireless Direct Link (AWDL) is a technology built in to macOS and iOS that supports AirDrop and Continuity features.

AWDL can cause network lag spikes when playing online multiplayer games or when game streaming over WiFi. These spikes can be caused by background activity on your Mac, or they can even be caused by other nearby Apple devices!

AWDL Control is a Mac app that automatically disables AWDL when the active application is a game, and then automatically bring it back up when you quit the game or switch back to your desktop. This preserves the useful Apple ecosystem functionality that AWDL provides, while preventing network lag spikes in game when you don't need AirDrop or related features.

## System Requirements

macOS 13.0 or higher.

## Downloads

[GitHub Releases](releases/)

## Installation

1. Drag AWDLControl.app to your Mac's Applications folder.
2. Launch AWDLControl.app and click on the "Register Helper" button to install.
    * macOS will prompt you for Admin authorization to install the helper.
3. (Optional) Configure AWDL Control to start at login time so it will always be running.

## How to Use

Once AWDL Control is installed and its helper is registered, it lives in your Mac menu bar.

AWDL Control has 3 modes:

* Game Mode
    - AWDL will be disabled when on WiFi and you are actively playing a game.
* AWDL On
    - Allow AWDL connections. This is the stock / out of the box Mac setting.
* AWDL Off
    - Suppress AWDL connections at all times. Useful if the app you're using is network latency sensitive, but isn't identifiable as a game.

## Uninstallation

1. If AWDL Control is running, click the AWDL Control menu bar icon and select "Quit".
2. Drag AWDLControl.app from Applications to the Trash.
3. There is no step 3. Yes, everything is totally gone including the helper!

## Feedback

Please report bugs here on GitHub.

Please send fan mail to jameshoward@mac.com

## Technical Notes

In older versions of macOS, running the following command in the Terminal could reliably disable AWDL:

```
sudo ifconfig awdl0 down
```

In recent macOS, the system will automatically bring the `awdl0` interface back up, which limits the effectiveness of that command.

AWDL Control efficiently automates keeping the `awdl0` interface down by monitoring network route changes and immediately bringing the interface back down if some other system component tries to bring it back up. Hat tip to [awdlkiller](https://github.com/jamestut/awdlkiller) by James Nugraha, which is a command line tool that originally implemented this idea!

### Helper Service

The AWDL Control Helper is a new style bundled LaunchDaemon, registered with [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)?language=objc). The big advantage of this compared to old style LaunchDaemons is the daemon and its launchd plist are part of the app bundle. This means the app can be relocated without issue, and uninstallation is as simple as dragging the app to the Trash without worrying about any orphaned plists or programs cluttering up the filesystem or, worse, still running in the background.

The helper daemon is necessary because elevated privileges are required to bring network interfaces up or down.

The helper only runs when the main AWDL Control application with the user interface is also running. When you quit AWDL Control, the daemon brings `awdl0` back up, and exits itself. This means there is never any hidden background software running on your computer that you can't see. We just need the daemon for the elevated privileges.

The helper is intentionally as simple as possible to limit the risk of running code with elevated privileges. All it can do is bring `awdl0` up or hold it down. The rest of the app logic runs in the UI process.

### Game Mode

AWDL Control uses approximately the same mechanism as macOS does to determine when to activate Game Mode. This means when the active application's Info.plist contains either:

* `LSApplicationCategoryType = "public.app-category.games"`
* `LSSupportsGameMode = true`

## Dear Apple

I have an open feedback with you about the issue this app addresses.

* FB13512447 - WiFi background scans cause latency spikes

Expanding macOS's Game Mode to limit any activity on the WiFi interface that can cause latency spikes would be a significant enhancement and would improve the viability of multiplayer gaming and game streaming on the Mac. AWDL is one culprit, but CoreLocation is also another major offender when doing WiFi scans for location in the background (e.g. for Calendar appointments with locations). Game Mode already has a feature to reduce Gamepad latency over the Bluetooth radio, so it fits in well to consider what you can do to limit WiFi interruptions in games.

Nothing would make me happier than to see Apple address this issue in macOS itself.

## Alternatives to AWDL Control

Look, I get it, nobody wants to install yet another utility, especially with a privileged helper, just to manage a shortcoming of macOS. Here are a couple of other ideas.

* Run an Ethernet cable to your Mac. You're going to read this and not do it because complaining about lag is easier than physically moving your computer or drilling holes in your walls, but if you're serious about competitive games, you need Ethernet.
* Set your 5GHz WiFi channel at your router to 149 (in the US) or 44 (in the EU). I'm not sure about other regions. This can reduce lag due to wireless channel hopping performed by AWDL. 
