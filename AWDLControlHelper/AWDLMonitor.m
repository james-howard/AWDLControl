//
//  AWDLMonitor.m
//  AWDLControlHelper
//
//  Created by James Howard on 12/31/25.
//

#import "AWDLMonitor.h"

#import <os/log.h>
#import <sys/types.h>
#import <sys/ioctl.h>
#import <sys/socket.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <net/route.h>
#import <unistd.h>
#import <poll.h>
#import <errno.h>
#import <err.h>
#import <fcntl.h>

#define LOG OS_LOG_DEFAULT

static const char *TARGETIFNAM = "awdl0";

@interface AWDLMonitor () {
    // Pipe file descriptors to monitor internal state changes (monitor invalidation, enablement change)
    int _msgfds[2];

    BOOL _exit;

    dispatch_semaphore_t _ioctlThreadExitSemaphore;
}

// Background thread watching AWDL state
@property NSThread *ioctlThread;

// Socket to perform ioctl to set interface flags
@property int iocfd;

// Socket to monitor network interface changes
@property int rtfd;

@end

@implementation AWDLMonitor

- (instancetype)init {
    if (self = [super init]) {
        // start off allowing AWDL to be active
        _awdlEnabled = YES;

        // socket to monitor network interface changes
        _rtfd = socket(AF_ROUTE, SOCK_RAW, 0);
        if (_rtfd < 0) {
            os_log_error(LOG, "Error creating AF_ROUTE socket: %d", errno);
            return nil;
        }
        if (fcntl(_rtfd, F_SETFL, O_NONBLOCK) < 0) {
            os_log_error(LOG, "Error setting nonblock on AF_ROUTE socket: %d", errno);
            return nil;
        }

        // socket to perform ioctl to set interface flags
        _iocfd = socket(AF_INET, SOCK_DGRAM, 0);
        if (_iocfd < 0) {
            os_log_error(LOG, "Error creating AF_INET socket: %d", errno);
            return nil;
        }

        if (0 != pipe(_msgfds)) {
            os_log_error(LOG, "Error creating pipe: %d", errno);
            return nil;
        }

        // Start background thread
        _ioctlThreadExitSemaphore = dispatch_semaphore_create(0);
        _ioctlThread = [[NSThread alloc] initWithTarget:self selector:@selector(pollIoctl) object:nil];
        [_ioctlThread start];
    }
    return self;
}

//! Bring the interface up or down. Must be run only on ioctlThread
- (void)ifconfig:(BOOL)up {
    NSAssert([NSThread currentThread] == _ioctlThread, @"ifconfig: must run on ioctlThread");

    struct ifreq ifr = {0};
    strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);

    if (ioctl(_iocfd, SIOCGIFFLAGS, &ifr) < 0) {
        os_log_error(LOG, "Error getting current interface flags: %d", errno);
        return;
    }
    if ((ifr.ifr_flags & IFF_UP) && !up) {
        ifr.ifr_flags &= ~IFF_UP;
        if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "Error bringing interface down: %d", errno);
        }
    } else if (!(ifr.ifr_flags & IFF_UP) && up) {
        ifr.ifr_flags |= IFF_UP;
        if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "Error bringing interace up: %d", errno);
        }
    } // else the interface is already in the desired state. do nothing.
}

/*! Main method for the background ioctlThread.
 *  Watches AWDL interface state and brings it up/down as needed.
 */
- (void)pollIoctl {
    os_log_debug(LOG, "+++ %{public}s", __func__);
    BOOL quit = NO;
    BOOL enable = _awdlEnabled;
    while (!quit) {
        struct pollfd fds[] = {
            {
                .fd = _rtfd,
                .events = POLLIN,
                .revents = 0
            },
            {
                .fd = _msgfds[0],
                .events = POLLIN,
                .revents = 0
            }
        };

        if (poll(fds, 2, -1)) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        if (fds[0].revents) {
            // AWDL state has changed. Check and see if it matches our expected state.
            int ifflag = 0;
            uint8_t rtmsgbuff[sizeof(struct rt_msghdr) + sizeof(struct if_msghdr)] = {0};
            for(ssize_t len = 0;;) {
                len = read(_rtfd, rtmsgbuff, sizeof(rtmsgbuff));
                if (len < 0) {
                    if (errno == EINTR) {
                        continue;
                    } else if (errno == EAGAIN) {
                        break;
                    }
                    os_log_error(LOG, "Error reading AF_ROUTE socket: %d", errno);
                }

                struct rt_msghdr * rtmsg = (void *)rtmsgbuff;
                if (rtmsg->rtm_type != RTM_IFINFO) {
                    continue;
                }

                // get interface ID
                int ifidx = if_nametoindex(TARGETIFNAM);
                if (!ifidx) {
                    err(1, "Error getting interface name");
                }

                struct if_msghdr * ifmsg = (void *)rtmsg;
                if (ifmsg->ifm_index != ifidx) {
                    // not the interface that we want
                    continue;
                }

                ifflag = ifmsg->ifm_flags;
            }

            struct ifreq ifr = {0};
            strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);
            if ((ifflag & IFF_UP) && !enable) {
                // AWDL has been brought up by some other process. Bring it back down.
                ifr.ifr_flags = ifflag & ~IFF_UP;
                if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
                    os_log_error(LOG, "Error turning down AWDL interface", errno);
                }
            }
        }

        if (fds[1].revents) {
            // Process messages from main thread
            char msg = 0;
            for(ssize_t len = 0;;) {
                len = read(_msgfds[0], &msg, 1);
                if (len < 0) {
                    if (errno == EINTR) {
                        continue;
                    } else if (errno == EAGAIN) {
                        break;
                    }
                    os_log_error(LOG, "Error reading AF_ROUTE socket: %d", errno);
                }

                switch (msg)
                {
                    case 'Q':
                        quit = YES;
                        break;
                    case 'U':
                        os_log_info(LOG, "Bringing AWDL interface UP");
                        [self ifconfig:YES];
                        break;
                    case 'D':
                        os_log_info(LOG, "Bringing AWDL interface DOWN");
                        [self ifconfig:NO];
                        break;
                    default:
                        break;
                }
            }
        }
    }
    dispatch_semaphore_signal(_ioctlThreadExitSemaphore);
    os_log_debug(LOG, "--- %{public}s", __func__);
}

- (void)setAwdlEnabled:(BOOL)awdlEnabled {
    if (awdlEnabled != _awdlEnabled) {
        _awdlEnabled = awdlEnabled;
        const char *msg = awdlEnabled ? "U" : "D";
        write(_msgfds[1], msg, 1);
    }
}

- (void)invalidate {
    os_log_debug(LOG, "+++ %{public}s", __func__);
    // Send the quit message to the background thread
    const char *msg = "Q";
    write(_msgfds[1], msg, 1);
    // Wait until the background thread exits
    dispatch_semaphore_wait(_ioctlThreadExitSemaphore, DISPATCH_TIME_FOREVER);
    os_log_debug(LOG, "--- %{public}s", __func__);
}

- (void)dealloc {
    close(_iocfd);
    close(_rtfd);
    close(_msgfds[0]);
    close(_msgfds[1]);
}

@end
