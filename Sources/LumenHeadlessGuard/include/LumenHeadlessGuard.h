#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@class NSWindow;
FOUNDATION_EXPORT BOOL LumenHeadlessGuardInstalled(void);
FOUNDATION_EXPORT void LumenHeadlessGuardCheck(void);
FOUNDATION_EXPORT void LumenHeadlessGuardBeginExpectedAttempt(NSWindow *window, NSString *selector);
FOUNDATION_EXPORT NSUInteger LumenHeadlessGuardEndExpectedAttempt(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *LumenHeadlessGuardSnapshot(void);
// Test-only policy facade: reports accessory and observes setters without changing the real policy.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *LumenHeadlessGuardObserveHostingPolicy(void (NS_NOESCAPE ^body)(void));
NS_ASSUME_NONNULL_END
