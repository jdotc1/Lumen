#import "LumenHeadlessCore.h"

NSRect LumenHeadlessOffscreenRect(NSRect rect) {
    CGFloat minX = 0, minY = 0;
    for (NSScreen *screen in NSScreen.screens) {
        minX = MIN(minX, NSMinX(screen.frame));
        minY = MIN(minY, NSMinY(screen.frame));
    }
    rect.origin = NSMakePoint(minX - MAX(rect.size.width, 0) - 100000,
                              minY - MAX(rect.size.height, 0) - 100000);
    return rect;
}

void LumenHeadlessPrepareWindow(NSWindow *window) {
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    window.excludedFromWindowsMenu = YES;
    window.collectionBehavior = NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle |
                                NSWindowCollectionBehaviorFullScreenNone;
    window.releasedWhenClosed = NO;
    NSPoint origin = LumenHeadlessOffscreenRect(window.frame).origin;
    if (!NSEqualPoints(window.frame.origin, origin)) [window setFrameOrigin:origin];
}
