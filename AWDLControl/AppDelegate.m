//
//  AppDelegate.m
//  AWDLControl
//
//  Created by James Howard on 12/31/25.
//

#import "AppDelegate.h"

#import "../Common/HelperProtocol.h"
#import "Reachability.h"

#import <os/log.h>
#import <ServiceManagement/ServiceManagement.h>

#define LOG OS_LOG_DEFAULT

typedef NS_ENUM(NSInteger, AWDLMode) {
    AWDLModeGame,
    AWDLModeUp,
    AWDLModeDown,
};

@interface NSImage (MenuExtras)

- (NSImage *)menuItemImage;

@end

@interface AppDelegate () {
    AWDLMode _awdlMode;
    BOOL _needsRegisterAtLogin;
    NSInteger _awdlEnabled;
}

@property (strong) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSMenu *statusMenu;
@property (strong) IBOutlet NSMenuItem *activeMenuItem;
@property (strong) IBOutlet NSMenuItem *activeMenuSeparator;
@property (strong) IBOutlet NSMenuItem *gameModeMenuItem;
@property (strong) IBOutlet NSMenuItem *downMenuItem;
@property (strong) IBOutlet NSMenuItem *upMenuItem;
@property (strong) NSStatusItem *statusItem;

@property (strong) IBOutlet NSButton *registerButton;
@property (strong) IBOutlet NSButton *openAtLoginCheckbox;

@property SMAppService *helperService;
@property NSXPCConnection *helperConnection;
@property NSTimer *helperStatusTimer;

@property Reachability *reachability;
@property NSRunningApplication *lastGameApp;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _awdlEnabled = -1;
    self.helperService = [SMAppService daemonServiceWithPlistName:@"com.jh.AWDLControl.Helper.plist"];
    [self updateHelperStatus];

    [self setAWDLMode:[[NSUserDefaults standardUserDefaults] integerForKey:@"AWDLMode"]];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(updateAutoAWDLMode) name:NSWorkspaceDidActivateApplicationNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAutoAWDLMode) name:ReachabilityDidChangeNotification object:nil];
    self.reachability = [Reachability new];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return self.helperService.status != SMAppServiceStatusEnabled;
}

// MARK: IBActions

- (IBAction)registerHelper:(id)sender {
    if (self.helperService.status == SMAppServiceStatusNotRegistered
        || self.helperService.status == SMAppServiceStatusNotFound) {
        NSError *err = nil;
        [self.helperService registerAndReturnError:&err];
        if (err) {
            os_log_error(LOG, "SMAppService register error: %{public}@", err);
            // generally not helpful to present this error to the user because there is an async notification prompt
            // that the user is seeing at this point.
        }
        [self updateHelperStatus];
    } else if (self.helperService.status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
    }

    _needsRegisterAtLogin = _openAtLoginCheckbox.state == NSControlStateValueOn;
}

- (IBAction)goAuto:(id)sender {
    [self setAWDLMode:AWDLModeGame];
}

- (IBAction)goDown:(id)sender {
    [self setAWDLMode:AWDLModeDown];
}

- (IBAction)goUp:(id)sender {
    [self setAWDLMode:AWDLModeUp];
}

- (IBAction)showAbout:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:nil];
}

// MARK: Mode Set

/// Returns the active game, or nil if the active app isn't a game.
- (NSRunningApplication *)activeGame {
    NSRunningApplication *app = [[NSWorkspace sharedWorkspace] frontmostApplication];

    NSURL *bundleURL = [app bundleURL];
    if (!bundleURL) {
        return nil; // Games are in bundles
    }

    NSURL *infoURL = [[bundleURL URLByAppendingPathComponent:@"Contents"] URLByAppendingPathComponent:@"Info.plist"];
    NSData *infoData = [NSData dataWithContentsOfURL:infoURL];
    if (!infoData) {
        return nil;
    }

    @try {
        NSDictionary *plistData = [NSPropertyListSerialization propertyListWithData:infoData options:0 format:NULL error:NULL];
        if (![plistData isKindOfClass:[NSDictionary class]]) {
            return nil;
        }

        if ([plistData[@"LSApplicationCategoryType"] isEqualToString:@"public.app-category.games"]
            || [plistData[@"LSSupportsGameMode"] boolValue]) {
            return app;
        }
    } @catch (id exc) { }

    return nil;
}

- (void)updateAutoAWDLMode {
    if (_awdlMode != AWDLModeGame || !self.helperConnection)
        return;

    BOOL onWiFi = _reachability.interfaceType == nw_interface_type_wifi;
    NSRunningApplication *gameApp = [self activeGame];
    BOOL inGame = gameApp != nil;
    if (gameApp) {
        self.lastGameApp = gameApp;
    }

    [self setAWDLEnabled:!(onWiFi && inGame)];
}

- (void)setAWDLMode:(AWDLMode)mode {
    _awdlMode = mode;
    [[NSUserDefaults standardUserDefaults] setInteger:_awdlMode forKey:@"AWDLMode"];
    switch (mode) {
        case AWDLModeDown:
            [self setAWDLEnabled:NO];
            _gameModeMenuItem.state = NSControlStateValueOff;
            _downMenuItem.state = NSControlStateValueOn;
            _upMenuItem.state = NSControlStateValueOff;
            break;
        case AWDLModeUp:
            [self setAWDLEnabled:YES];
            _gameModeMenuItem.state = NSControlStateValueOff;
            _downMenuItem.state = NSControlStateValueOff;
            _upMenuItem.state = NSControlStateValueOn;
            break;
        case AWDLModeGame:
        default:
            _gameModeMenuItem.state = NSControlStateValueOn;
            _downMenuItem.state = NSControlStateValueOff;
            _upMenuItem.state = NSControlStateValueOff;
            [self updateAutoAWDLMode];
            break;
    }
}

- (void)updateAWDLMode {
    [self setAWDLMode:_awdlMode];
}

- (void)setAWDLEnabled:(BOOL)enabled {
    if (self.helperConnection) {
        if (_awdlEnabled < 0 || enabled != _awdlEnabled)
        {
            _awdlEnabled = enabled;
            [self.helperConnection.remoteObjectProxy setAWDLEnabled:enabled];
        }
    }
    [self updateActiveMenuItem];
}

- (void)updateActiveMenuItem {
    if (!self.helperConnection) {
        _activeMenuItem.image = nil;
        _activeMenuItem.title = @"Helper Inactive";
        _activeMenuItem.hidden = NO;
        _activeMenuSeparator.hidden = NO;
    } else if (_awdlMode == AWDLModeGame) {
        if (self.lastGameApp.active) {
            _activeMenuItem.image = [self.lastGameApp.icon menuItemImage];
            _activeMenuItem.title = [NSString stringWithFormat:@"Active for %@", self.lastGameApp.localizedName];
        } else if (self.lastGameApp && !self.lastGameApp.terminated) {
            _activeMenuItem.image = [self.lastGameApp.icon menuItemImage];
            _activeMenuItem.title = [NSString stringWithFormat:@"Previously Active for %@", self.lastGameApp.localizedName];
        } else {
            _activeMenuItem.image = nil;
            _activeMenuItem.title = @"No Active Games";
        }
        _activeMenuItem.hidden = NO;
        _activeMenuSeparator.hidden = NO;
    } else {
        self.lastGameApp = nil;
        _activeMenuItem.hidden = YES;
        _activeMenuSeparator.hidden = YES;
    }
}

// MARK: Helper Registration

- (void)updateHelperStatusUI {
    BOOL showWindow = NO;
    switch (self.helperService.status) {
        case SMAppServiceStatusNotFound:
        case SMAppServiceStatusNotRegistered:
            self.registerButton.title = @"Register Helper";
            showWindow = YES;
            break;
        case SMAppServiceStatusRequiresApproval:
            self.registerButton.title = @"Enable Helper";
            showWindow = YES;
            break;
        default:
            break;
    }

    if (showWindow && ![self.window isVisible]) {
        [NSApp activateIgnoringOtherApps:YES];
        [self.window makeKeyAndOrderFront:nil];
        self.statusItem = nil;
    }

    if (!showWindow && !self.statusItem) {
        NSImage *statusIcon = [NSImage imageNamed:@"MenuIcon"];
        statusIcon.template = YES;
        _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:28.0];
        _statusItem.button.image = statusIcon;
        _statusItem.menu = _statusMenu;
        _statusItem.behavior = NSStatusItemBehaviorTerminationOnRemoval;
        [self.window close];
    }
}

- (void)updateHelperStatus {
    if (self.helperService.status == SMAppServiceStatusEnabled
        && !self.helperConnection) {
        [self connectXPC];
        [self.helperStatusTimer invalidate];
        self.helperStatusTimer = nil;
        [self updateAWDLMode];

        if (_needsRegisterAtLogin) {
            _needsRegisterAtLogin = NO;
            SMAppService *loginService = [SMAppService mainAppService];
            [loginService registerAndReturnError:NULL];
        }
    } else if (!self.helperStatusTimer) {
        // Set up a timer to poll the status on a regular interval until the helper is enabled.
        // There's no notification or kvo for the status property on SMAppService, so this is the
        // best we can do to know if the user changes it in System Settings.
        self.helperStatusTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateHelperStatus) userInfo:nil repeats:YES];
        self.helperStatusTimer.tolerance = 1.0;
    }

    [self updateHelperStatusUI];
}

- (void)connectXPC {
    os_log_debug(LOG, "Connect XPC");
    self.helperConnection = [[NSXPCConnection alloc] initWithMachServiceName:@"com.jh.xpc.AWDLControl.Helper" options:0];
    self.helperConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HelperProtocol)];
    self.helperConnection.interruptionHandler = ^{
        os_log_error(LOG, "Helper Connection Interrupted");
    };
    self.helperConnection.invalidationHandler = ^{
        os_log_error(LOG, "Helper Connection Invalidated");
    };
    [self.helperConnection activate];
    [self updateAWDLMode];
}

@end

@implementation NSImage (MenuExtras)

- (NSImage *)menuItemImage {
    NSImage *img = [self copy];
    img.size = NSMakeSize(16, 16);
    return img;
}

@end
