// Exercise the production detection and AWDL decision without a privileged helper.
#import "../AWDLControl/AppDelegate.m"

@interface TestApplication : NSObject
@property NSString *bundleIdentifier;
@property NSURL *bundleURL;
@property NSString *localizedName;
@property (getter=isTerminated) BOOL terminated;
@property (getter=isActive) BOOL active;
@property NSImage *icon;
@end
@implementation TestApplication
@end

@interface TestConnection : NSObject
@property BOOL enabled;
@property NSUInteger commandCount;
@end
@implementation TestConnection
- (id)remoteObjectProxy { return self; }
- (void)setAWDLEnabled:(BOOL)enabled {
    self.enabled = enabled;
    self.commandCount++;
}
@end

@interface TestReachability : NSObject
@property nw_interface_type_t interfaceType;
@end
@implementation TestReachability
@end

@interface TestDelegate : AppDelegate
@property NSRunningApplication *testFrontmost;
@property NSArray<NSRunningApplication *> *testApplications;
@end
@implementation TestDelegate
- (NSRunningApplication *)activeGame {
    return [self gameApplicationWithFrontmostApplication:self.testFrontmost
                                    runningApplications:self.testApplications];
}
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static TestApplication *Application(NSString *identifier, NSURL *bundleURL) {
    TestApplication *app = [TestApplication new];
    app.bundleIdentifier = identifier;
    app.bundleURL = bundleURL;
    app.localizedName = identifier;
    return app;
}

int main(void) {
    @autoreleasepool {
        NSURL *fixture = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        NSURL *contents = [fixture URLByAppendingPathComponent:@"Contents"];
        NSError *error = nil;
        Check([[NSFileManager defaultManager] createDirectoryAtURL:contents withIntermediateDirectories:YES attributes:nil error:&error], @"create fixture");
        NSURL *info = [contents URLByAppendingPathComponent:@"Info.plist"];
        Check([@{@"LSApplicationCategoryType": @"public.app-category.games"} writeToURL:info atomically:YES], @"write fixture");

        TestApplication *streamer = Application(@"com.nvidia.gfnpc.streamer", fixture);
        TestApplication *launcher = Application(@"com.nvidia.gfnpc.mall", fixture);
        TestApplication *desktop = Application(@"test.desktop", nil);
        TestApplication *game = Application(@"test.game", fixture);
        TestDelegate *delegate = [TestDelegate new];
        TestConnection *connection = [TestConnection new];
        TestReachability *network = [TestReachability new];
        network.interfaceType = nw_interface_type_wifi;
        delegate.helperConnection = (id)connection;
        delegate.reachability = (id)network;
        delegate.activeMenuItem = [NSMenuItem new];
        delegate.testFrontmost = (id)desktop;
        delegate.testApplications = (id)@[launcher, streamer, desktop];
        [delegate setValue:@(-1) forKey:@"awdlEnabled"];

        [delegate updateAutoAWDLMode];
        Check(!connection.enabled, @"stream remains protected with desktop/overlay foreground");
        Check(delegate.currentGameApp == (id)streamer, @"select streamer rather than launcher");
        Check([delegate.activeMenuItem.title isEqualToString:@"Active for com.nvidia.gfnpc.streamer"], @"status matches session even when streamer is inactive");
        NSUInteger count = connection.commandCount;
        [delegate updateAutoAWDLMode];
        Check(connection.commandCount == count, @"periodic checks do not resend unchanged commands");

        streamer.terminated = YES;
        [delegate updateAutoAWDLMode];
        Check(connection.enabled, @"restore AWDL after streamer exits with launcher still running");
        Check(delegate.currentGameApp == nil, @"terminated streamer does not count as active");
        streamer.terminated = NO;
        [delegate updateAutoAWDLMode];
        Check(!connection.enabled, @"poll recovers a missed streamer launch");
        delegate.testApplications = (id)@[launcher, desktop];
        [delegate updateAutoAWDLMode];
        Check(connection.enabled, @"poll recovers a missed streamer termination");

        delegate.testFrontmost = (id)launcher;
        [delegate updateAutoAWDLMode];
        Check(!connection.enabled, @"foreground launcher retains normal game behavior");
        delegate.testFrontmost = (id)game;
        [delegate updateAutoAWDLMode];
        Check(!connection.enabled, @"ordinary foreground game is protected");
        delegate.testFrontmost = (id)desktop;
        [delegate updateAutoAWDLMode];
        Check(connection.enabled, @"ordinary background game does not hold AWDL down");

        delegate.testApplications = (id)@[streamer];
        network.interfaceType = nw_interface_type_wired;
        [delegate updateAutoAWDLMode];
        Check(connection.enabled, @"Ethernet leaves AWDL enabled during stream");
        network.interfaceType = nw_interface_type_wifi;
        [delegate updateAutoAWDLMode];
        Check(!connection.enabled, @"switching back to Wi-Fi protects ongoing stream");
        network.interfaceType = nw_interface_type_other;
        [delegate updateAutoAWDLMode];
        Check(connection.enabled, @"no Wi-Fi leaves AWDL enabled");
        network.interfaceType = nw_interface_type_wifi;

        for (NSNumber *mode in @[@(AWDLModeUp), @(AWDLModeDown)]) {
            [delegate setValue:mode forKey:@"awdlMode"];
            count = connection.commandCount;
            [delegate updateAutoAWDLMode];
            Check(connection.commandCount == count, @"automatic updates respect manual mode");
        }
        [delegate setValue:@(AWDLModeGame) forKey:@"awdlMode"];
        delegate.testApplications = @[];
        delegate.testFrontmost = nil;
        Check([delegate activeGame] == nil, @"missing foreground application is safe");
        Check([@{@"LSSupportsGameMode": @YES} writeToURL:info atomically:YES], @"write opt-in fixture");
        Check([delegate isGameApplication:(id)game], @"explicit Game Mode opt-in still works");
        Check([@{@"LSApplicationCategoryType": @"public.app-category.utilities"} writeToURL:info atomically:YES], @"write non-game fixture");
        Check(![delegate isGameApplication:(id)game], @"non-game metadata is rejected");
        Check([[NSFileManager defaultManager] removeItemAtURL:fixture error:&error], @"remove fixture");
        printf("Passed %lu checks. No helper or network settings changed.\n", (unsigned long)checks);
    }
    return 0;
}
