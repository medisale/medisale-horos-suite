#import "TransientLineOverlayController.h"

#import "HorosAdapter.h"
#import "ImageContext.h"
#import "LineOverlayModel.h"
#import <DCMView.h>
#import <Notifications.h>
#import <ViewerController.h>

typedef NS_ENUM(NSInteger, MedisaleEndpoint) {
    MedisaleEndpointNone = 0,
    MedisaleEndpointA,
    MedisaleEndpointB,
};

@interface MedisaleLineOverlayView : NSView
@property(nonatomic, weak) DCMView *imageView;
@property(nonatomic, strong) LineOverlayModel *model;
@property(nonatomic) MedisaleEndpoint selectedEndpoint;
@end

@implementation MedisaleLineOverlayView

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)isFlipped
{
    return NO;
}

- (NSView *)hitTest:(NSPoint)point
{
    (void)point;
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    DCMView *imageView = self.imageView;
    LineOverlayModel *model = self.model;
    if (imageView == nil || model == nil) {
        return;
    }

    NSPoint a = [imageView ConvertFromGL2NSView:model.pointA];
    NSPoint b = [imageView ConvertFromGL2NSView:model.pointB];

    NSBezierPath *outline = [NSBezierPath bezierPath];
    [outline moveToPoint:a];
    [outline lineToPoint:b];
    outline.lineWidth = 5.0;
    outline.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.85] setStroke];
    [outline stroke];

    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:a];
    [line lineToPoint:b];
    line.lineWidth = 2.5;
    line.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithCalibratedRed:0.0 green:0.95 blue:1.0 alpha:1.0] setStroke];
    [line stroke];

    NSArray<NSValue *> *points = @[[NSValue valueWithPoint:a], [NSValue valueWithPoint:b]];
    for (NSUInteger index = 0; index < points.count; index++) {
        NSValue *value = points[index];
        NSPoint point = value.pointValue;
        NSRect markerRect = NSMakeRect(point.x - 4.0, point.y - 4.0, 8.0, 8.0);
        NSBezierPath *marker = [NSBezierPath bezierPathWithOvalInRect:markerRect];
        [[NSColor colorWithCalibratedRed:0.0 green:0.95 blue:1.0 alpha:1.0] setFill];
        [marker fill];
        [[NSColor blackColor] setStroke];
        marker.lineWidth = 1.0;
        [marker stroke];

        MedisaleEndpoint endpoint = index == 0 ? MedisaleEndpointA : MedisaleEndpointB;
        if (self.selectedEndpoint == endpoint) {
            NSRect selectionRect = NSMakeRect(point.x - 8.0, point.y - 8.0, 16.0, 16.0);
            NSBezierPath *selection = [NSBezierPath bezierPathWithOvalInRect:selectionRect];
            selection.lineWidth = 3.0;
            [[NSColor colorWithCalibratedRed:1.0 green:0.82 blue:0.0 alpha:1.0] setStroke];
            [selection stroke];
        }
    }

    NSPoint midpoint = NSMakePoint((a.x + b.x) * 0.5, (a.y + b.y) * 0.5);
    NSString *distance = [NSString stringWithFormat:
        @"A %.2f, %.2f   B %.2f, %.2f   |   %.2f px",
        model.pointA.x, model.pointA.y, model.pointB.x, model.pointB.y,
        model.pixelDistance];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSBackgroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.0 alpha:0.72],
    };
    NSSize labelSize = [distance sizeWithAttributes:attributes];
    NSPoint labelPoint = NSMakePoint(midpoint.x - labelSize.width * 0.5, midpoint.y + 10.0);
    [distance drawAtPoint:labelPoint withAttributes:attributes];
}

@end

@interface TransientLineOverlayController ()
@property(nonatomic, weak, readwrite) ViewerController *viewer;
@property(nonatomic, strong, readwrite) LineOverlayModel *model;
@property(nonatomic, readwrite, getter=isActive) BOOL active;
@property(nonatomic, strong) MedisaleLineOverlayView *overlayView;
@property(nonatomic, strong) NSTimer *redrawTimer;
@property(nonatomic, strong) NSMutableArray *observers;
@property(nonatomic, strong) id eventMonitor;
@property(nonatomic, copy) MedisaleOverlayInvalidation invalidation;
@property(nonatomic) BOOL originalPostsFrameChangedNotifications;
@property(nonatomic) MedisaleEndpoint selectedEndpoint;
@property(nonatomic) BOOL draggingEndpoint;
@property(nonatomic) NSPoint dragOrigin;
@end

@implementation TransientLineOverlayController

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(LineOverlayModel *)model
                    invalidation:(MedisaleOverlayInvalidation)invalidation
{
    self = [super init];
    if (self) {
        _viewer = viewer;
        _model = model;
        _invalidation = [invalidation copy];
        _observers = [NSMutableArray array];
    }
    return self;
}

- (BOOL)start
{
    if (self.active) {
        return YES;
    }
    DCMView *imageView = self.viewer.imageView;
    if (imageView == nil || ![self currentImageMatchesModel]) {
        return NO;
    }

    self.originalPostsFrameChangedNotifications = imageView.postsFrameChangedNotifications;
    imageView.postsFrameChangedNotifications = YES;

    MedisaleLineOverlayView *overlayView = [[MedisaleLineOverlayView alloc]
        initWithFrame:imageView.bounds];
    overlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlayView.imageView = imageView;
    overlayView.model = self.model;
    overlayView.wantsLayer = YES;
    [imageView addSubview:overlayView positioned:NSWindowAbove relativeTo:nil];
    self.overlayView = overlayView;
    self.active = YES;

    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (imageView.window != nil) {
        [self.observers addObject:[center
            addObserverForName:NSWindowWillCloseNotification
            object:imageView.window
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf invalidate];
            }]];
    }
    [self.observers addObject:[center
        addObserverForName:OsirixDCMViewIndexChangedNotification
        object:imageView
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            typeof(self) self = weakSelf;
            if (self != nil && ![self currentImageMatchesModel]) {
                [self invalidate];
            }
        }]];
    [self.observers addObject:[center
        addObserverForName:OsirixUpdateViewNotification
        object:imageView
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf requestRedraw];
        }]];
    [self.observers addObject:[center
        addObserverForName:NSViewFrameDidChangeNotification
        object:imageView
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf requestRedraw];
        }]];

    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
        (NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged |
         NSEventMaskLeftMouseUp | NSEventMaskKeyDown |
         NSEventMaskRightMouseDragged |
         NSEventMaskOtherMouseDragged | NSEventMaskScrollWheel |
         NSEventMaskMagnify | NSEventMaskRotate)
        handler:^NSEvent * _Nullable(NSEvent *event) {
            typeof(self) self = weakSelf;
            if (self == nil) {
                return event;
            }
            if (event.window != self.viewer.imageView.window) {
                return event;
            }
            if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
                if (self.draggingEndpoint) {
                    [self cancelEndpointDragRestoring:YES];
                    return nil;
                }
                if (self.selectedEndpoint != MedisaleEndpointNone) {
                    [self selectEndpoint:MedisaleEndpointNone];
                    return nil;
                }
                return event;
            }
            if (event.type == NSEventTypeLeftMouseDown) {
                return [self beginEndpointDragForEvent:event] ? nil : event;
            }
            if (event.type == NSEventTypeLeftMouseDragged && self.draggingEndpoint) {
                [self updateEndpointDragForEvent:event];
                return nil;
            }
            if (event.type == NSEventTypeLeftMouseUp && self.draggingEndpoint) {
                [self updateEndpointDragForEvent:event];
                self.draggingEndpoint = NO;
                [self.model updateInputState:LineOverlayInputStateComplete];
                [self requestRedraw];
                return nil;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self requestRedraw];
            });
            return event;
        }];

    self.redrawTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                        repeats:YES
                                                          block:^(NSTimer *timer) {
        (void)timer;
        typeof(self) self = weakSelf;
        if (self == nil) {
            return;
        }
        if (![self currentImageMatchesModel]) {
            [self invalidate];
            return;
        }
        [self requestRedraw];
    }];
    [self requestRedraw];
    return YES;
}

- (BOOL)currentImageMatchesModel
{
    ViewerController *viewer = self.viewer;
    NSError *error = nil;
    ImageContext *current = viewer == nil ? nil :
        [HorosAdapter imageContextForViewer:viewer error:&error];
    (void)error;
    ImageContext *expected = self.model.imageIdentity;
    return current != nil &&
        [current.studyInstanceUID isEqualToString:expected.studyInstanceUID] &&
        [current.seriesInstanceUID isEqualToString:expected.seriesInstanceUID] &&
        [current.sopInstanceUID isEqualToString:expected.sopInstanceUID] &&
        current.frameNumber == expected.frameNumber;
}

- (void)cancelCurrentInteraction
{
    if (self.draggingEndpoint || self.selectedEndpoint != MedisaleEndpointNone) {
        [self cancelEndpointDragRestoring:YES];
    }
}

- (void)selectEndpoint:(MedisaleEndpoint)endpoint
{
    self.selectedEndpoint = endpoint;
    self.overlayView.selectedEndpoint = endpoint;
    if (!self.draggingEndpoint) {
        LineOverlayInputState state = LineOverlayInputStateComplete;
        if (endpoint == MedisaleEndpointA) {
            state = LineOverlayInputStateEndpointASelected;
        } else if (endpoint == MedisaleEndpointB) {
            state = LineOverlayInputStateEndpointBSelected;
        }
        [self.model updateInputState:state];
    }
    [self requestRedraw];
}

- (MedisaleEndpoint)endpointNearViewPoint:(NSPoint)viewPoint
{
    DCMView *imageView = self.viewer.imageView;
    if (imageView == nil) {
        return MedisaleEndpointNone;
    }
    NSPoint a = [imageView ConvertFromGL2NSView:self.model.pointA];
    NSPoint b = [imageView ConvertFromGL2NSView:self.model.pointB];
    double distanceA = hypot(viewPoint.x - a.x, viewPoint.y - a.y);
    double distanceB = hypot(viewPoint.x - b.x, viewPoint.y - b.y);
    static const double hitRadius = 12.0;
    if (distanceA > hitRadius && distanceB > hitRadius) {
        return MedisaleEndpointNone;
    }
    return distanceA <= distanceB ? MedisaleEndpointA : MedisaleEndpointB;
}

- (BOOL)beginEndpointDragForEvent:(NSEvent *)event
{
    if (!self.active || ![self currentImageMatchesModel]) {
        [self cancelEndpointDragRestoring:NO];
        if (self.active) {
            [self invalidate];
        }
        return NO;
    }
    DCMView *imageView = self.viewer.imageView;
    NSPoint viewPoint = [imageView convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(viewPoint, imageView.bounds)) {
        [self selectEndpoint:MedisaleEndpointNone];
        return NO;
    }
    MedisaleEndpoint endpoint = [self endpointNearViewPoint:viewPoint];
    if (endpoint == MedisaleEndpointNone) {
        [self selectEndpoint:MedisaleEndpointNone];
        return NO;
    }
    [self selectEndpoint:endpoint];
    self.dragOrigin = endpoint == MedisaleEndpointA ? self.model.pointA : self.model.pointB;
    self.draggingEndpoint = YES;
    [self.model updateInputState:endpoint == MedisaleEndpointA
        ? LineOverlayInputStateEditingEndpointA
        : LineOverlayInputStateEditingEndpointB];
    return YES;
}

- (void)updateEndpointDragForEvent:(NSEvent *)event
{
    if (!self.draggingEndpoint) {
        return;
    }
    if (![self currentImageMatchesModel]) {
        [self cancelEndpointDragRestoring:YES];
        [self invalidate];
        return;
    }
    DCMView *imageView = self.viewer.imageView;
    NSPoint viewPoint = [imageView convertPoint:event.locationInWindow fromView:nil];
    NSPoint imagePoint = [imageView ConvertFromNSView2GL:viewPoint];
    ImageContext *identity = self.model.imageIdentity;
    imagePoint.x = MIN(MAX(imagePoint.x, 0.0), (double)identity.pixelWidth - 1.0);
    imagePoint.y = MIN(MAX(imagePoint.y, 0.0), (double)identity.pixelHeight - 1.0);
    if (self.selectedEndpoint == MedisaleEndpointA) {
        [self.model updatePointA:imagePoint];
    } else if (self.selectedEndpoint == MedisaleEndpointB) {
        [self.model updatePointB:imagePoint];
    }
    [self requestRedraw];
}

- (void)cancelEndpointDragRestoring:(BOOL)restore
{
    if (restore && self.draggingEndpoint) {
        if (self.selectedEndpoint == MedisaleEndpointA) {
            [self.model updatePointA:self.dragOrigin];
        } else if (self.selectedEndpoint == MedisaleEndpointB) {
            [self.model updatePointB:self.dragOrigin];
        }
    }
    self.draggingEndpoint = NO;
    self.selectedEndpoint = MedisaleEndpointNone;
    self.overlayView.selectedEndpoint = MedisaleEndpointNone;
    [self.model updateInputState:LineOverlayInputStateComplete];
    [self requestRedraw];
}

- (void)requestRedraw
{
    if (!self.active) {
        return;
    }
    DCMView *imageView = self.viewer.imageView;
    if (imageView == nil) {
        [self invalidate];
        return;
    }
    if (!NSEqualRects(self.overlayView.frame, imageView.bounds)) {
        self.overlayView.frame = imageView.bounds;
    }
    [self.overlayView setNeedsDisplay:YES];
}

- (void)invalidate
{
    if (!self.active && self.overlayView == nil && self.eventMonitor == nil &&
        self.observers.count == 0 && self.redrawTimer == nil) {
        return;
    }

    self.active = NO;
    [self cancelEndpointDragRestoring:YES];
    [self.redrawTimer invalidate];
    self.redrawTimer = nil;
    if (self.eventMonitor != nil) {
        [NSEvent removeMonitor:self.eventMonitor];
        self.eventMonitor = nil;
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (id observer in self.observers) {
        [center removeObserver:observer];
    }
    [self.observers removeAllObjects];

    DCMView *imageView = self.viewer.imageView;
    if (imageView != nil) {
        imageView.postsFrameChangedNotifications = self.originalPostsFrameChangedNotifications;
    }
    [self.overlayView removeFromSuperview];
    self.overlayView.imageView = nil;
    self.overlayView.model = nil;
    self.overlayView = nil;

    MedisaleOverlayInvalidation invalidation = self.invalidation;
    self.invalidation = nil;
    self.viewer = nil;
    if (invalidation != nil) {
        invalidation();
    }
}

- (void)dealloc
{
    [self invalidate];
}

@end
