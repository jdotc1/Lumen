#import "LumenHeadlessGuard.h"
#import <AppKit/AppKit.h>
#import "LumenHeadlessCore.h"
#import <unistd.h>
#import <stdlib.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Test-only dependency. It is deliberately absent from the production conformance dependency.
static BOOL installed;
static __weak id currentTest;
static NSMutableArray<NSString *> *pendingFailures;
static NSString *expectedSelector;
static __weak NSWindow *expectedWindow;
static NSUInteger expectedCount;
static NSUInteger violations;
static NSUInteger blockedCalls;
static NSUInteger frontmostChanges;
static pid_t frontmostBefore;
static BOOL observingTests;
static BOOL checking;
static NSUInteger initializingWindow;
static BOOL initializingApp;
static BOOL observingHostingPolicy;
static NSApplicationActivationPolicy observedPolicy;
static NSUInteger observedPolicyCalls;
static IMP originalPolicyGetter;

static NSApplicationActivationPolicy guardedPolicyGetter(id self, SEL command) {
    if (observingHostingPolicy) return observedPolicy;
    return ((NSApplicationActivationPolicy (*)(id, SEL))originalPolicyGetter)(self, command);
}

static NSString *describeWindow(NSWindow *window) {
    if (!window) return @"(application)";
    return [NSString stringWithFormat:@"%@ #%ld title=%@ frame=%@ alpha=%g key=%d main=%d",
            NSStringFromClass(window.class), (long)window.windowNumber, window.title,
            NSStringFromRect(window.frame), window.alphaValue, window.keyWindow, window.mainWindow];
}

static void recordFailure(NSString *message) {
    violations++;
    fprintf(stderr, "HEADLESS VIOLATION: %s\n", message.UTF8String);
    if (currentTest) {
        SEL selector = NSSelectorFromString(@"recordFailureWithDescription:inFile:atLine:expected:");
        ((void (*)(id, SEL, id, id, NSUInteger, BOOL))objc_msgSend)(currentTest, selector, message,
             @"LumenHeadlessGuard", 1, YES);
    } else {
        [pendingFailures addObject:message];
    }
}

static void blocked(id object, SEL selector) {
    blockedCalls++;
    NSString *name = NSStringFromSelector(selector);
    NSWindow *window = [object isKindOfClass:NSWindow.class] ? object : nil;
    NSString *message = [NSString stringWithFormat:@"blocked %@ before dispatch: %@", name, describeWindow(window)];
    if ([expectedSelector isEqualToString:name] && object == expectedWindow && expectedCount == 0) {
        expectedCount++;
        fprintf(stderr, "HEADLESS EXPECTED: %s\n", message.UTF8String);
    } else {
        recordFailure(message);
    }
}

static NSRect offscreen(NSRect rect) {
    return LumenHeadlessOffscreenRect(rect);
}

static BOOL intersectsScreen(NSRect rect) {
    for (NSScreen *screen in NSScreen.screens) if (NSIntersectsRect(rect, screen.frame)) return YES;
    return NO;
}

void LumenHeadlessGuardCheck(void) {
    if (checking || initializingWindow || !NSThread.isMainThread) return;
    checking = YES;
    if (NSApp.active) recordFailure(@"application became active");
    for (NSWindow *window in NSApp.windows) {
        if (window.keyWindow || window.mainWindow || intersectsScreen(window.frame)) {
            recordFailure([@"unsafe window state: " stringByAppendingString:describeWindow(window)]);
            window.alphaValue = 0;
            [window orderOut:nil];
        }
    }
    checking = NO;
}

static void replace(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    if (original) *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
}

// Enforce before AppKit constructs any window, independently of shared hosting or the
// test observation facade. Initializing NSApplication installs the prohibited policy.
static void requireProhibitedActivation(void) {
    NSApplication *app = NSApplication.sharedApplication;
    NSApplicationActivationPolicy actual =
        ((NSApplicationActivationPolicy (*)(id, SEL))originalPolicyGetter)(app, @selector(activationPolicy));
    if (actual != NSApplicationActivationPolicyProhibited) {
        fprintf(stderr, "HEADLESS VIOLATION: activation must be prohibited before window construction\n");
        abort();
    }
}

static IMP originalWindowInit;
static id guardedWindowInit(id self, SEL command, NSRect rect, NSWindowStyleMask style,
                            NSBackingStoreType backing, BOOL defer) {
    requireProhibitedActivation();
    initializingWindow++;
    id result = ((id (*)(id, SEL, NSRect, NSWindowStyleMask, NSBackingStoreType, BOOL))originalWindowInit)
        (self, command, offscreen(rect), style, backing, defer);
    LumenHeadlessPrepareWindow(result);
    initializingWindow--;
    return result;
}

static IMP originalWindowScreenInit;
static id guardedWindowScreenInit(id self, SEL command, NSRect rect, NSWindowStyleMask style,
                                  NSBackingStoreType backing, BOOL defer, NSScreen *screen) {
    requireProhibitedActivation();
    initializingWindow++;
    id result = ((id (*)(id, SEL, NSRect, NSWindowStyleMask, NSBackingStoreType, BOOL, NSScreen *))originalWindowScreenInit)
        (self, command, offscreen(rect), style, backing, defer, screen);
    LumenHeadlessPrepareWindow(result);
    initializingWindow--;
    return result;
}
static id blockedWindowCoder(id self, SEL command, NSCoder *coder) {
    (void)self; (void)coder; blocked(nil, command); return nil;
}
static NSModalResponse blockedModal(id self, SEL command) {
    blocked(self, command); return NSModalResponseCancel;
}
static void blockedBegin(id self, SEL command, void (^completion)(NSModalResponse)) {
    blocked(self, command); if (completion) completion(NSModalResponseCancel);
}
static void blockedBeginSheet(id self, SEL command, NSWindow *window, void (^completion)(NSModalResponse)) {
    (void)window; blocked(self, command); if (completion) completion(NSModalResponseCancel);
}
static NSModalResponse blockedRunModalWindow(id self, SEL command, NSWindow *window) {
    (void)window; blocked(self, command); return NSModalResponseAbort;
}

static IMP originalAppInit;
static id guardedAppInit(id self, SEL command) {
    initializingApp = YES;
    NSApplication *app = ((id (*)(id, SEL))originalAppInit)(self, command);
    initializingApp = NO;
    [app setActivationPolicy:NSApplicationActivationPolicyProhibited];
    return app;
}
static IMP originalPolicy;
static BOOL guardedPolicy(id self, SEL command, NSApplicationActivationPolicy policy) {
    if (observingHostingPolicy) {
        observedPolicyCalls++;
        observedPolicy = policy;
        return YES; // Facade only: the real process remains prohibited under the guard.
    }
    if (initializingApp) policy = NSApplicationActivationPolicyProhibited;
    if (policy != NSApplicationActivationPolicyProhibited) {
        blocked(self, command);
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSApplicationActivationPolicy))originalPolicy)(self, command, policy);
}
static void blockNoArgument(id self, SEL command) { blocked(self, command); }
static void blockObjectArgument(id self, SEL command, id sender) { (void)sender; blocked(self, command); }
static void blockBoolArgument(id self, SEL command, BOOL flag) { (void)flag; blocked(self, command); }
static BOOL cannotBecome(id self, SEL command) { (void)self; (void)command; return NO; }
static BOOL guardedRunningActivate(id self, SEL command, NSApplicationActivationOptions options) {
    (void)options; blocked(self, command); return NO;
}
static BOOL blockedRunningActivateFrom(id self, SEL command, NSRunningApplication *app, NSApplicationActivationOptions options) {
    (void)app; (void)options; blocked(self, command); return NO;
}
static BOOL blockedUnhide(id self, SEL command) { blocked(self, command); return NO; }
static IMP originalOrder;
static void guardedOrder(id self, SEL command, NSWindowOrderingMode place, NSInteger other) {
    NSWindow *window = self;
    if (place == NSWindowAbove) { blocked(self, command); return; }
    if (place != NSWindowOut && (window.alphaValue != 0 || intersectsScreen(window.frame))) {
        blocked(self, command); return;
    }
    ((void (*)(id, SEL, NSWindowOrderingMode, NSInteger))originalOrder)(self, command, place, other);
    LumenHeadlessGuardCheck();
}
static IMP originalAlpha;
static void guardedAlpha(id self, SEL command, CGFloat alpha) {
    if (alpha > 0 && !initializingWindow) { blocked(self, command); return; }
    alpha = 0;
    ((void (*)(id, SEL, CGFloat))originalAlpha)(self, command, alpha);
}
// Raw constructors in protected snapshot code receive the same unconstrained parking.
static NSRect unconstrainedFrame(id self, SEL command, NSRect frame, NSScreen *screen) {
    (void)self; (void)command; (void)screen; return frame;
}
static IMP originalLayout;
static void guardedLayout(id self, SEL command) {
    ((void (*)(id, SEL))originalLayout)(self, command);
    NSWindow *window = [(NSView *)self window];
    if (window) LumenHeadlessPrepareWindow(window);
    LumenHeadlessGuardCheck();
}
static IMP originalFrame;
static void guardedFrame(id self, SEL command, NSRect frame, BOOL display) {
    ((void (*)(id, SEL, NSRect, BOOL))originalFrame)(self, command, offscreen(frame), display);
    LumenHeadlessGuardCheck();
}
static IMP originalFrameAnimated;
static void guardedFrameAnimated(id self, SEL command, NSRect frame, BOOL display, BOOL animate) {
    (void)animate;
    ((void (*)(id, SEL, NSRect, BOOL, BOOL))originalFrameAnimated)(self, command, offscreen(frame), display, NO);
    LumenHeadlessGuardCheck();
}

static IMP originalOrigin;
static void guardedOrigin(id self, SEL command, NSPoint point) {
    (void)point;
    ((void (*)(id, SEL, NSPoint))originalOrigin)(self, command, offscreen([self frame]).origin);
    LumenHeadlessGuardCheck();
}
static IMP originalTopLeft;
static void guardedTopLeft(id self, SEL command, NSPoint point) {
    (void)point; NSRect rect = offscreen([self frame]);
    ((void (*)(id, SEL, NSPoint))originalTopLeft)(self, command, NSMakePoint(NSMinX(rect), NSMaxY(rect)));
    LumenHeadlessGuardCheck();
}
static IMP originalLevel;
static void guardedLevel(id self, SEL command, NSWindowLevel level) {
    ((void (*)(id, SEL, NSWindowLevel))originalLevel)(self, command, level);
    LumenHeadlessGuardCheck();
}

@interface LumenHeadlessTestObserver : NSObject
@end
@implementation LumenHeadlessTestObserver
- (void)testBundleWillStart:(id)bundle { (void)bundle; LumenHeadlessGuardCheck(); }
- (void)testCaseWillStart:(id)test {
    currentTest = test;
    NSArray *failures = [pendingFailures copy]; [pendingFailures removeAllObjects];
    for (NSString *message in failures) recordFailure(message);
    LumenHeadlessGuardCheck();
}
- (void)testCaseDidFinish:(id)test { (void)test; LumenHeadlessGuardCheck(); currentTest = nil; }
- (void)testBundleDidFinish:(id)bundle {
    (void)bundle; LumenHeadlessGuardCheck();
    fprintf(stderr, "HEADLESS SUMMARY: violations=%lu blockedCalls=%lu frontmostChanges=%lu\n",
            (unsigned long)violations, (unsigned long)blockedCalls, (unsigned long)frontmostChanges);
    // A violation outside a running case must also fail an empty filtered bundle.
    if (violations > 0) { fflush(stderr); exit(EXIT_FAILURE); }
}
@end
static LumenHeadlessTestObserver *testObserver;
static void registerObserver(void) {
    if (observingTests) return;
    Class centerClass = NSClassFromString(@"XCTestObservationCenter");
    Protocol *observation = NSProtocolFromString(@"XCTestObservation");
    if (!centerClass || !observation) return;
    // XCTest checks actual protocol conformance, not just the observer selectors.
    class_addProtocol(LumenHeadlessTestObserver.class, observation);
    id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, NSSelectorFromString(@"sharedTestObservationCenter"));
    testObserver = [LumenHeadlessTestObserver new];
    ((void (*)(id, SEL, id))objc_msgSend)(center, NSSelectorFromString(@"addTestObserver:"), testObserver);
    observingTests = YES;
}

// +load and -ObjC on every test target ensure even pure-model tests install the same process guard.
@interface LumenHeadlessBootstrap : NSObject
@end
@implementation LumenHeadlessBootstrap
+ (void)load {
    pendingFailures = [NSMutableArray new];
    replace(NSWindow.class, @selector(initWithContentRect:styleMask:backing:defer:), (IMP)guardedWindowInit, &originalWindowInit);
    replace(NSWindow.class, @selector(initWithContentRect:styleMask:backing:defer:screen:), (IMP)guardedWindowScreenInit, &originalWindowScreenInit);
    replace(NSWindow.class, NSSelectorFromString(@"initWithCoder:"), (IMP)blockedWindowCoder, NULL);
    replace(NSWindow.class, @selector(becomeKeyWindow), (IMP)blockNoArgument, NULL);
    replace(NSWindow.class, @selector(becomeMainWindow), (IMP)blockNoArgument, NULL);
    replace(NSWindow.class, @selector(makeKeyAndOrderFront:), (IMP)blockObjectArgument, NULL);
    replace(NSWindow.class, @selector(orderFront:), (IMP)blockObjectArgument, NULL);
    replace(NSWindow.class, @selector(orderFrontRegardless), (IMP)blockNoArgument, NULL);
    replace(NSWindow.class, @selector(makeKeyWindow), (IMP)blockNoArgument, NULL);
    replace(NSWindow.class, @selector(makeMainWindow), (IMP)blockNoArgument, NULL);
    replace(NSWindow.class, @selector(canBecomeKeyWindow), (IMP)cannotBecome, NULL);
    replace(NSWindow.class, @selector(canBecomeMainWindow), (IMP)cannotBecome, NULL);
    replace(NSPanel.class, @selector(canBecomeKeyWindow), (IMP)cannotBecome, NULL);
    replace(NSPanel.class, @selector(canBecomeMainWindow), (IMP)cannotBecome, NULL);
    replace(NSWindow.class, @selector(orderWindow:relativeTo:), (IMP)guardedOrder, &originalOrder);
    replace(NSWindow.class, @selector(setAlphaValue:), (IMP)guardedAlpha, &originalAlpha);
    replace(NSWindow.class, @selector(constrainFrameRect:toScreen:), (IMP)unconstrainedFrame, NULL);
    replace(NSView.class, @selector(layoutSubtreeIfNeeded), (IMP)guardedLayout, &originalLayout);
    replace(NSWindow.class, @selector(setFrame:display:), (IMP)guardedFrame, &originalFrame);
    replace(NSWindow.class, @selector(setFrame:display:animate:), (IMP)guardedFrameAnimated, &originalFrameAnimated);
    replace(NSWindow.class, @selector(setFrameOrigin:), (IMP)guardedOrigin, &originalOrigin);
    replace(NSWindow.class, @selector(setFrameTopLeftPoint:), (IMP)guardedTopLeft, &originalTopLeft);
    replace(NSWindow.class, @selector(setLevel:), (IMP)guardedLevel, &originalLevel);
    for (Class cls in @[NSSavePanel.class, NSOpenPanel.class, NSAlert.class]) {
        replace(cls, @selector(runModal), (IMP)blockedModal, NULL);
        replace(cls, @selector(beginWithCompletionHandler:), (IMP)blockedBegin, NULL);
        replace(cls, @selector(beginSheetModalForWindow:completionHandler:), (IMP)blockedBeginSheet, NULL);
    }
    replace(NSApplication.class, @selector(runModalForWindow:), (IMP)blockedRunModalWindow, NULL);
    replace(NSApplication.class, @selector(init), (IMP)guardedAppInit, &originalAppInit);
    replace(NSApplication.class, @selector(activationPolicy), (IMP)guardedPolicyGetter, &originalPolicyGetter);
    replace(NSApplication.class, @selector(setActivationPolicy:), (IMP)guardedPolicy, &originalPolicy);
    replace(NSApplication.class, @selector(activate), (IMP)blockNoArgument, NULL);
    replace(NSApplication.class, @selector(activateIgnoringOtherApps:), (IMP)blockBoolArgument, NULL);
    replace(NSRunningApplication.class, @selector(activateWithOptions:), (IMP)guardedRunningActivate, NULL);
    replace(NSRunningApplication.class, @selector(activateFromApplication:options:), (IMP)blockedRunningActivateFrom, NULL);
    replace(NSRunningApplication.class, @selector(unhide), (IMP)blockedUnhide, NULL);
    replace(NSApplication.class, @selector(unhide:), (IMP)blockObjectArgument, NULL);
    replace(NSApplication.class, @selector(unhideWithoutActivation), (IMP)blockNoArgument, NULL);
    replace(NSApplication.class, @selector(unhideAllApplications:), (IMP)blockObjectArgument, NULL);
    if (NSApp) [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    installed = YES;
    registerObserver();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:NSBundleDidLoadNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        (void)note; registerObserver();
    }];
    for (NSNotificationName name in @[NSApplicationDidBecomeActiveNotification, NSWindowDidBecomeKeyNotification,
                                     NSWindowDidBecomeMainNotification, NSWindowDidMoveNotification,
                                     NSWindowDidResizeNotification, NSApplicationDidChangeScreenParametersNotification]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            (void)note; LumenHeadlessGuardCheck();
        }];
    }
    frontmostBefore = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
            if (app.processIdentifier != frontmostBefore) frontmostChanges++;
            if (app.processIdentifier == getpid()) recordFailure(@"test process became frontmost");
        }];
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting,
        true, 0, ^(CFRunLoopObserverRef item, CFRunLoopActivity activity) {
            (void)item; (void)activity; LumenHeadlessGuardCheck();
        });
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    CFRelease(observer);
}
@end

BOOL LumenHeadlessGuardInstalled(void) { return installed && observingTests; }
void LumenHeadlessGuardBeginExpectedAttempt(NSWindow *window, NSString *selector) {
    NSCAssert(expectedSelector == nil, @"Expected headless attempts cannot nest");
    expectedWindow = window; expectedSelector = [selector copy]; expectedCount = 0;
}
NSUInteger LumenHeadlessGuardEndExpectedAttempt(void) {
    NSUInteger count = expectedCount; expectedSelector = nil; expectedWindow = nil; expectedCount = 0; return count;
}
NSDictionary<NSString *, id> *LumenHeadlessGuardSnapshot(void) {
    LumenHeadlessGuardCheck();
    NSUInteger visible = 0, ordered = 0, key = 0, main = 0, intersecting = 0;
    for (NSWindow *window in NSApp.windows) {
        if (window.alphaValue > 0 && intersectsScreen(window.frame)) visible++;
        if (intersectsScreen(window.frame)) intersecting++;
        if (window.visible) ordered++;
        if (window.keyWindow) key++;
        if (window.mainWindow) main++;
    }
    return @{@"installed": @(LumenHeadlessGuardInstalled()), @"violations": @(violations),
             @"blockedCalls": @(blockedCalls), @"ordered": @(ordered), @"visible": @(visible), @"key": @(key), @"main": @(main),
             @"intersecting": @(intersecting), @"active": @(NSApp.active), @"frontmostBefore": @(frontmostBefore),
             @"frontmostAfter": @(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier),
             @"frontmostChanges": @(frontmostChanges)};
}

NSDictionary<NSString *, id> *LumenHeadlessGuardObserveHostingPolicy(void (NS_NOESCAPE ^body)(void)) {
    NSCAssert(NSThread.isMainThread && !observingHostingPolicy, @"Policy observation must be main-thread and non-nested");
    NSApplication *app = NSApplication.sharedApplication;
    NSCAssert(app.activationPolicy == NSApplicationActivationPolicyProhibited, @"Real process must remain guarded");
    observedPolicy = NSApplicationActivationPolicyAccessory;
    observedPolicyCalls = 0;
    observingHostingPolicy = YES;
    @try { body(); }
    @finally { observingHostingPolicy = NO; }
    NSCAssert(app.activationPolicy == NSApplicationActivationPolicyProhibited, @"Observation changed the real policy");
    return @{@"setterCalls": @(observedPolicyCalls), @"reportedPolicyAfter": @(observedPolicy),
             @"actualPolicyAfter": @(app.activationPolicy)};
}
