//
//  AWDLMonitor.h
//  AWDLControlHelper
//
//  Created by James Howard on 12/31/25.
//

#import <Foundation/Foundation.h>

/*! Tracks the state of the AWDL interface and brings it up or down as needed. */
@interface AWDLMonitor : NSObject

@property (nonatomic) BOOL awdlEnabled;

//! Stop monitoring AWDL state
- (void)invalidate;

@end

