#import "TemporaryPanController.h"

#import "HoldSpacePanState.h"
#import "HorosAdapter.h"
#import "ImageContext.h"
#import <CoreGraphics/CoreGraphics.h>
#import <DCMView.h>
#import <Notifications.h>
#import <ViewerController.h>

@interface TemporaryPanController ()
@property(nonatomic, weak, readwrite, nullable) ViewerController *viewer;
@property(nonatomic, strong, readwrite) HoldSpacePanState *state;
@property(nonatomic, readwrite, getter=isValid) BOOL valid;
@property(nonatomic, strong, nullable) id eventMonitor;
@property(nonatomic, strong) NSMutableArray *observers;
@property(nonatomic, strong, nullable) NSTimer *keyStateTimer;
@property(nonatomic, strong, nullable) NSEvent *lastRoutedMouseEvent;
@property(nonatomic) BOOL routingNativeMouse;
@property(nonatomic) BOOL consumeNextSpaceUp;
@end

@implementation TemporaryPanController

- (instancetype)initWithViewer:(ViewerController *)viewer
{
    self = [super init];
    if (self) {
        _viewer = viewer;
        _state = [[HoldSpacePanState alloc] init];
        _observers = [NSMutableArray array];
    }
    return self;
}

- (BOOL)start
{
    if (self.valid) {
        return YES;
    }
    ViewerController *viewer = self.viewer;
    NSWindow *window = viewer.imageView.window;
    if (viewer == nil || window == nil) {
        return NO;
    }

    self.valid = YES;
    __weak typeof(self) weakSelf = self;
    NSEventMask mask = NSEventMaskKeyDown | NSEventMaskKeyUp |
        NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged |
        NSEventMaskLeftMouseUp;
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
        handler:^NSEvent * _Nullable(NSEvent *event) {
            typeof(self) self = weakSelf;
            return self == nil ? event : [self handleEvent:event];
        }];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [self.observers addObject:[center addObserverForName:NSWindowDidResignKeyNotification
        object:window queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf forceEndTemporaryPan];
        }]];
    [self.observers addObject:[center addObserverForName:NSWindowWillCloseNotification
        object:window queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf invalidate];
        }]];
    [self.observers addObject:[center addObserverForName:NSApplicationDidResignActiveNotification
        object:NSApplication.sharedApplication queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf forceEndTemporaryPan];
        }]];
    for (NSNotificationName name in @[OsirixDCMViewIndexChangedNotification,
                                      OsirixDCMUpdateCurrentImageNotification]) {
        [self.observers addObject:[center addObserverForName:name
            object:viewer.imageView queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf endIfImageIdentityChanged];
            }]];
    }
    return YES;
}

- (NSEvent *)handleEvent:(NSEvent *)event
{
    ViewerController *viewer = self.viewer;
    DCMView *imageView = viewer.imageView;
    if (!self.valid || viewer == nil || imageView == nil ||
        event.window != imageView.window) {
        return event;
    }

    if (event.type == NSEventTypeKeyDown) {
        if (event.keyCode == 53 && self.state.isActive) {
            [self forceEndTemporaryPan];
            NSEvent *escapeEvent = event;
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSApp postEvent:escapeEvent atStart:YES];
            });
            return nil;
        }
        if (event.keyCode != 49) {
            return event;
        }
        NSEventModifierFlags relevantModifiers = event.modifierFlags &
            NSEventModifierFlagDeviceIndependentFlagsMask;
        if (self.state.isActive) {
            return relevantModifiers == 0 ? nil : event;
        }
        HoldSpacePanFocusKind focusKind =
            [self focusKindForWindow:event.window imageView:imageView];
        if (![HoldSpacePanState shouldBeginForKeyCode:event.keyCode
                                        modifierFlags:event.modifierFlags
                                             isRepeat:event.isARepeat
                                            focusKind:focusKind]) {
            return event;
        }
        NSError *error = nil;
        ImageContext *identity = [HorosAdapter imageContextForViewer:viewer error:&error];
        (void)error;
        if (![self.state beginWithImageContext:identity]) {
            return event;
        }
        self.consumeNextSpaceUp = YES;
        [self startKeyStateTimer];
        return nil;
    }

    if (event.type == NSEventTypeKeyUp && event.keyCode == 49) {
        if (self.state.isActive || self.consumeNextSpaceUp) {
            [self endTemporaryPanFromKeyUp];
            return nil;
        }
        return event;
    }

    if (!self.state.isActive) {
        return event;
    }
    if (![self currentImageStillMatches]) {
        [self forceEndTemporaryPan];
        return event;
    }
    return [self nativePanEventForLeftMouseEvent:event imageView:imageView];
}

- (HoldSpacePanFocusKind)focusKindForWindow:(NSWindow *)window
                                 imageView:(DCMView *)imageView
{
    return [HoldSpacePanState focusKindForResponder:window.firstResponder
                                          imageView:imageView];
}

- (NSEvent *)nativePanEventForLeftMouseEvent:(NSEvent *)event
                                   imageView:(DCMView *)imageView
{
    NSEventType nativeType;
    if (event.type == NSEventTypeLeftMouseDown) {
        NSPoint point = [imageView convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, imageView.bounds)) {
            return event;
        }
        self.routingNativeMouse = YES;
        nativeType = NSEventTypeOtherMouseDown;
    } else if (event.type == NSEventTypeLeftMouseDragged && self.routingNativeMouse) {
        nativeType = NSEventTypeOtherMouseDragged;
    } else if (event.type == NSEventTypeLeftMouseUp && self.routingNativeMouse) {
        nativeType = NSEventTypeOtherMouseUp;
    } else {
        return event;
    }

    CGEventRef source = event.CGEvent;
    if (source == NULL) {
        [self releaseRoutedNativeMouseForImageView:imageView];
        return event;
    }
    CGEventRef nativeEvent = CGEventCreateCopy(source);
    if (nativeEvent == NULL) {
        [self releaseRoutedNativeMouseForImageView:imageView];
        return event;
    }
    CGEventType nativeCGType = kCGEventOtherMouseDown;
    if (nativeType == NSEventTypeOtherMouseDragged) {
        nativeCGType = kCGEventOtherMouseDragged;
    } else if (nativeType == NSEventTypeOtherMouseUp) {
        nativeCGType = kCGEventOtherMouseUp;
    }
    CGEventSetType(nativeEvent, nativeCGType);
    CGEventSetIntegerValueField(nativeEvent, kCGMouseEventButtonNumber,
                                kCGMouseButtonCenter);
    NSEvent *result = [NSEvent eventWithCGEvent:nativeEvent];
    CFRelease(nativeEvent);
    if (result == nil) {
        [self releaseRoutedNativeMouseForImageView:imageView];
        return event;
    }
    if (nativeType == NSEventTypeOtherMouseUp) {
        self.routingNativeMouse = NO;
        self.lastRoutedMouseEvent = nil;
    } else {
        self.lastRoutedMouseEvent = result;
    }
    return result;
}

- (void)releaseRoutedNativeMouseForImageView:(DCMView *)imageView
{
    if (!self.routingNativeMouse) {
        self.lastRoutedMouseEvent = nil;
        return;
    }
    NSEvent *sourceEvent = self.lastRoutedMouseEvent;
    self.routingNativeMouse = NO;
    self.lastRoutedMouseEvent = nil;
    if (sourceEvent == nil || imageView == nil) {
        return;
    }
    CGEventRef source = sourceEvent.CGEvent;
    if (source == NULL) {
        return;
    }
    CGEventRef releaseEvent = CGEventCreateCopy(source);
    if (releaseEvent == NULL) {
        return;
    }
    CGEventSetType(releaseEvent, kCGEventOtherMouseUp);
    CGEventSetIntegerValueField(releaseEvent, kCGMouseEventButtonNumber,
                                kCGMouseButtonCenter);
    NSEvent *release = [NSEvent eventWithCGEvent:releaseEvent];
    CFRelease(releaseEvent);
    if (release != nil) {
        [imageView otherMouseUp:release];
    }
}

- (void)startKeyStateTimer
{
    [self.keyStateTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.keyStateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES
        block:^(NSTimer *timer) {
            (void)timer;
            typeof(self) self = weakSelf;
            if (self == nil || !self.state.isActive) {
                return;
            }
            BOOL spaceIsDown = CGEventSourceKeyState(
                kCGEventSourceStateCombinedSessionState, 49);
            if (!spaceIsDown || ![self currentImageStillMatches]) {
                [self forceEndTemporaryPan];
            }
        }];
    self.keyStateTimer.tolerance = 0.02;
}

- (BOOL)currentImageStillMatches
{
    ViewerController *viewer = self.viewer;
    if (viewer == nil) {
        return NO;
    }
    NSError *error = nil;
    ImageContext *identity = [HorosAdapter imageContextForViewer:viewer error:&error];
    (void)error;
    return [self.state matchesImageContext:identity];
}

- (void)endIfImageIdentityChanged
{
    if (self.state.isActive && ![self currentImageStillMatches]) {
        [self forceEndTemporaryPan];
    }
}

- (void)endTemporaryPanFromKeyUp
{
    self.consumeNextSpaceUp = NO;
    [self endTemporaryPan];
}

- (void)forceEndTemporaryPan
{
    [self endTemporaryPan];
}

- (void)endTemporaryPan
{
    [self releaseRoutedNativeMouseForImageView:self.viewer.imageView];
    [self.keyStateTimer invalidate];
    self.keyStateTimer = nil;
    [self.state end];
}

- (void)invalidate
{
    if (!self.valid && self.viewer == nil && self.eventMonitor == nil &&
        self.observers.count == 0 && self.keyStateTimer == nil) {
        return;
    }
    self.valid = NO;
    self.consumeNextSpaceUp = NO;
    [self endTemporaryPan];
    if (self.eventMonitor != nil) {
        [NSEvent removeMonitor:self.eventMonitor];
        self.eventMonitor = nil;
    }
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (id observer in self.observers) {
        [center removeObserver:observer];
    }
    [self.observers removeAllObjects];
    self.viewer = nil;
}

- (void)dealloc
{
    [self invalidate];
}

@end
