//
//  Reachability.m
//  AWDLControl
//
//  Created by James Howard on 1/3/26.
//

#import "Reachability.h"

#import <os/log.h>

#define LOG OS_LOG_DEFAULT

NSString* const ReachabilityDidChangeNotification = @"ReachabilityDidChangeNotification";

@interface Reachability ()

@property nw_path_monitor_t monitor;

@end

@implementation Reachability

- (instancetype)init {
    if (self = [super init]) {
        self.monitor = nw_path_monitor_create();
        nw_path_monitor_set_queue(self.monitor, dispatch_get_main_queue());
        __weak __typeof(self) weakSelf = self;
        nw_path_monitor_set_update_handler(self.monitor, ^(nw_path_t  _Nonnull path) {
            [weakSelf updateNWPath:path];
        });
        nw_path_monitor_start(self.monitor);
    }
    return self;
}

- (void)dealloc {
    nw_path_monitor_cancel(self.monitor);
}

- (void)updateNWPath:(nw_path_t)path {
    os_log_info(LOG, "nw_path %@", path);

    nw_interface_type_t types[] = {
        nw_interface_type_wired,
        nw_interface_type_wifi,
        nw_interface_type_cellular
    };

    self.interfaceType = nw_interface_type_other;
    for (size_t i = 0; i < sizeof(types) / sizeof(types[0]); i++) {
        if (nw_path_uses_interface_type(path, types[i])) {
            self.interfaceType = types[i];
            break;
        }
    }

    // Check if we're on VPN over WiFi ...
    if (self.interfaceType == nw_interface_type_other) {
        __block BOOL hasWiFi = NO;
        nw_path_enumerate_interfaces(path, ^bool(nw_interface_t  _Nonnull interface) {
            nw_interface_type_t type = nw_interface_get_type(interface);
            if (type == nw_interface_type_wired) {
                return false; // break early if Ethernet is before WiFi
            } else if (type == nw_interface_type_wifi) {
                hasWiFi = YES;
                return false;
            } else {
                return true;
            }
        });
        if (hasWiFi) {
            self.interfaceType = nw_interface_type_wifi;
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:ReachabilityDidChangeNotification object:self userInfo:@{@"interfaceType":@(self.interfaceType)}];
}

@end
