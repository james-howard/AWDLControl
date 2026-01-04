//
//  main.m
//  AWDLControlHelper
//
//  Created by James Howard on 12/31/25.
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "../Common/HelperProtocol.h"
#import "AWDLMonitor.h"

#define LOG OS_LOG_DEFAULT

@interface AWDLService : NSObject <HelperProtocol, NSXPCListenerDelegate>

@property AWDLMonitor *monitor;

@end

@implementation AWDLService

- (instancetype)init {
    if (self = [super init]) {
        self.monitor = [AWDLMonitor new];
    }
    return self;
}

- (BOOL)isAWDLEnabled { 
    return self.monitor.awdlEnabled;
}

- (void)setAWDLEnabled:(BOOL)enable { 
    self.monitor.awdlEnabled = enable;
}

- (void)scheduleExit {
    [self.monitor setAwdlEnabled:YES];
    [self.monitor invalidate];
    exit(0);
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    NSLog(@"Received new connection: %@", newConnection);
    os_log(LOG, "Received new connection: %{public}@", newConnection);

    newConnection.interruptionHandler = ^{
        os_log(LOG, "Connection interrupted");
        [self scheduleExit];
    };

    newConnection.invalidationHandler = ^{
        os_log(LOG, "Connection invalidated");
        [self scheduleExit];
    };

    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HelperProtocol)];
    newConnection.exportedObject = self;
    [newConnection resume];

    return YES;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        os_log(LOG, "AWDLControlHelper starting up");

        AWDLService *service = [AWDLService new];
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.jh.xpc.AWDLControl.Helper"];
        [listener setConnectionCodeSigningRequirement:@"anchor apple generic and identifier \"com.jh.AWDLControl\" and certificate leaf[subject.OU] = H2Q5P3YR67"];
        listener.delegate = service;

        [listener activate];

        dispatch_main();

        os_log(LOG, "AWDLControlHelper exiting");
    }
    return EXIT_SUCCESS;
}
