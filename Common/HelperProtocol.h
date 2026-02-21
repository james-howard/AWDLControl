//
//  HelperProtocol.h
//  AWDLControl
//
//  Created by James Howard on 12/31/25.
//

#import <Foundation/Foundation.h>

@protocol HelperProtocol <NSObject>

- (BOOL)isAWDLEnabled;
- (void)setAWDLEnabled:(BOOL)enable;
- (void)checkinWithReply:(void (^)(BOOL ok))reply;

@end
