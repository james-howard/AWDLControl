//
//  AppDelegate.m
//  AWDLControl
//
//  Created by James Howard on 12/31/25.
//

#import "AppDelegate.h"

#import "../Common/HelperProtocol.h"

#import <os/log.h>
#import <ServiceManagement/ServiceManagement.h>

#define LOG OS_LOG_DEFAULT

@interface AppDelegate ()

@property (strong) IBOutlet NSWindow *window;

@property (strong) IBOutlet NSButton *registerButton;
@property (strong) IBOutlet NSButton *downButton;
@property (strong) IBOutlet NSButton *upButton;

@property (strong) IBOutlet NSTextField *statusLabel;

@property SMAppService *helperService;
@property NSXPCConnection *helperConnection;
@property NSTimer *helperStatusTimer;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.helperService = [SMAppService daemonServiceWithPlistName:@"com.jh.AWDLControl.Helper.plist"];
    [self updateHelperStatus];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
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
}

- (IBAction)goDown:(id)sender {
    [self.helperConnection.remoteObjectProxy setAWDLEnabled:NO];
}

- (IBAction)goUp:(id)sender {
    [self.helperConnection.remoteObjectProxy setAWDLEnabled:YES];
}

// MARK: Helper Registration

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (object == self.helperService) {
        [self updateHelperStatus];
    }
}

- (void)updateHelperStatusLabel {
    NSString *status = @"Unknown";
    switch (self.helperService.status)
    {
        case SMAppServiceStatusNotFound:
            status = @"Not Found";
            break;
        case SMAppServiceStatusNotRegistered:
            status = @"Not Registered";
            break;
        case SMAppServiceStatusRequiresApproval:
            status = @"Requires Approval";
            break;
        case SMAppServiceStatusEnabled:
            status = @"Enabled";
            break;
        default:
            break;
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Helper Status: %@", status];
}

- (void)updateHelperStatus {
    [self updateHelperStatusLabel];

    if (self.helperService.status == SMAppServiceStatusEnabled
        && !self.helperConnection) {
        [self connectXPC];
        [self.helperStatusTimer invalidate];
        self.helperStatusTimer = nil;
    } else if (!self.helperStatusTimer) {
        // Set up a timer to poll the status on a regular interval until the helper is enabled.
        // There's no notification or kvo for the status property on SMAppService, so this is the
        // best we can do to know if the user changes it in System Settings.
        self.helperStatusTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateHelperStatus) userInfo:nil repeats:YES];
        self.helperStatusTimer.tolerance = 1.0;
    }
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
}

@end
