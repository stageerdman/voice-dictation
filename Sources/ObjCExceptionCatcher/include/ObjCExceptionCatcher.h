#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift can't catch Objective-C exceptions, and AVAudioEngine raises them
/// (e.g. installTap on a stale/invalid format). Uncaught, AppKit swallows them
/// inside the hotkey callback and every later press silently dies. This runs
/// `block` and turns any NSException into an NSError instead.
@interface ObjCExceptionCatcher : NSObject
+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
