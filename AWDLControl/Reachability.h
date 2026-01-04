//
//  Reachability.h
//  AWDLControl
//
//  Created by James Howard on 1/3/26.
//

#import <Foundation/Foundation.h>
#import <Network/Network.h>

NS_ASSUME_NONNULL_BEGIN

@interface Reachability : NSObject

@property nw_interface_type_t interfaceType;

@end

extern NSString* const ReachabilityDidChangeNotification;

NS_ASSUME_NONNULL_END
