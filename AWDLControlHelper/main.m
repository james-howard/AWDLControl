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
    os_log_info(LOG, "Received new connection: %{public}@", newConnection);

    newConnection.interruptionHandler = ^{
        os_log_info(LOG, "Connection interrupted");
        [self scheduleExit];
    };

    newConnection.invalidationHandler = ^{
        os_log_info(LOG, "Connection invalidated");
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
        AWDLService *service = [AWDLService new];
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@"jh.AWDLControl.Helper"];
        listener.delegate = service;

        [listener activate];
    }
    return EXIT_SUCCESS;
}
