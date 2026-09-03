#import "TransientLineOverlayController.h"

#import "HorosAdapter.h"
#import "HoldSpacePanState.h"
#import "ImageContext.h"
#import "LegacyDistanceInteractionAdapter.h"
#import "LineOverlayModel.h"
#import "MeasurementInteraction.h"
#import <DCMView.h>
#import <Notifications.h>
#import <ViewerController.h>

@interface MedisaleLineOverlayView : NSView
@property(nonatomic, weak) DCMView *imageView;
@property(nonatomic, strong) LineOverlayModel *legacyModel;
@property(nonatomic, strong) MeasurementInteractionSession *session;
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
    MeasurementInteractionSession *session = self.session;
    if (imageView == nil || session == nil) {
        return;
    }
    NSMutableDictionary<NSNumber *, NSValue *> *displayPoints =
        [NSMutableDictionary dictionary];
    for (NamedImageLandmark *landmark in session.landmarks) {
        displayPoints[@(landmark.identifier)] = [NSValue valueWithPoint:
            [imageView ConvertFromGL2NSView:landmark.imagePoint]];
    }
    for (MeasurementOverlaySegment *segment in session.definition.overlaySegments) {
        NSValue *start = displayPoints[@(segment.startIdentifier)];
        NSValue *end = displayPoints[@(segment.endIdentifier)];
        if (start == nil || end == nil) continue;
        for (NSNumber *width in @[@5.0, @2.5]) {
            NSBezierPath *path = [NSBezierPath bezierPath];
            [path moveToPoint:start.pointValue];
            [path lineToPoint:end.pointValue];
            path.lineWidth = width.doubleValue;
            path.lineCapStyle = NSLineCapStyleRound;
            if (width.doubleValue > 3.0) {
                [[NSColor colorWithCalibratedWhite:0.0 alpha:0.85] setStroke];
            } else {
                [[NSColor colorWithCalibratedRed:0.0 green:0.95 blue:1.0 alpha:1.0]
                    setStroke];
            }
            [path stroke];
        }
    }
    for (NSNumber *identifier in session.definition.collectionOrder) {
        NSPoint point = displayPoints[identifier].pointValue;
        NSRect markerRect = NSMakeRect(point.x - 4.0, point.y - 4.0, 8.0, 8.0);
        NSBezierPath *marker = [NSBezierPath bezierPathWithOvalInRect:markerRect];
        [[NSColor colorWithCalibratedRed:0.0 green:0.95 blue:1.0 alpha:1.0] setFill];
        [marker fill];
        [[NSColor blackColor] setStroke];
        marker.lineWidth = 1.0;
        [marker stroke];

        if (session.selectedLandmarkIdentifier == identifier.integerValue) {
            NSRect selectionRect = NSMakeRect(point.x - 8.0, point.y - 8.0, 16.0, 16.0);
            NSBezierPath *selection = [NSBezierPath bezierPathWithOvalInRect:selectionRect];
            selection.lineWidth = 3.0;
            [[NSColor colorWithCalibratedRed:1.0 green:0.82 blue:0.0 alpha:1.0] setStroke];
            [selection stroke];
        }
    }

    LineOverlayModel *model = self.legacyModel;
    if (model == nil || session.definition.overlaySegments.count == 0) return;
    MeasurementOverlaySegment *labelSegment = session.definition.overlaySegments.firstObject;
    NSPoint a = displayPoints[@(labelSegment.startIdentifier)].pointValue;
    NSPoint b = displayPoints[@(labelSegment.endIdentifier)].pointValue;
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
@property(nonatomic, weak) HoldSpacePanState *panState;
@property(nonatomic, strong) MeasurementInteractionSession *session;
@property(nonatomic, copy) NSString *viewerOwnershipIdentifier;
@end

@implementation TransientLineOverlayController

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(LineOverlayModel *)model
                        panState:(HoldSpacePanState *)panState
                    invalidation:(MedisaleOverlayInvalidation)invalidation
{
    self = [super init];
    if (self) {
        _viewer = viewer;
        _model = model;
        _panState = panState;
        _invalidation = [invalidation copy];
        _observers = [NSMutableArray array];
        _viewerOwnershipIdentifier = NSUUID.UUID.UUIDString;
        MeasurementImageContext *context = [MeasurementImageContext
            contextWithStudyInstanceUID:model.imageIdentity.studyInstanceUID
            seriesInstanceUID:model.imageIdentity.seriesInstanceUID
            sopInstanceUID:model.imageIdentity.sopInstanceUID
            frameNumber:model.imageIdentity.frameNumber
            pixelWidth:model.imageIdentity.pixelWidth
            pixelHeight:model.imageIdentity.pixelHeight error:nil];
        MeasurementInteractionDefinition *definition =
            [LegacyDistanceInteractionAdapter interactionDefinition];
        NSArray *landmarks = @[
            [NamedImageLandmark landmarkWithIdentifier:
                MedisaleLandmarkIdentifierEndpointA imagePoint:model.pointA error:nil],
            [NamedImageLandmark landmarkWithIdentifier:
                MedisaleLandmarkIdentifierEndpointB imagePoint:model.pointB error:nil],
        ];
        NamedLandmarkSnapshot *snapshot = [NamedLandmarkSnapshot
            snapshotWithMethod:definition.method imageContext:context
            landmarks:landmarks error:nil];
        _session = [MeasurementInteractionSession
            sessionWithViewerOwnershipIdentifier:_viewerOwnershipIdentifier
            definition:definition landmarkSnapshot:snapshot error:nil];
    }
    return self;
}

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(LineOverlayModel *)model
                    invalidation:(MedisaleOverlayInvalidation)invalidation
{
    return [self initWithViewer:viewer model:model panState:nil
                   invalidation:invalidation];
}

- (BOOL)start
{
    if (self.active) {
        return YES;
    }
    DCMView *imageView = self.viewer.imageView;
    if (imageView == nil || self.session == nil || ![self currentImageMatchesModel]) {
        return NO;
    }

    self.originalPostsFrameChangedNotifications = imageView.postsFrameChangedNotifications;
    imageView.postsFrameChangedNotifications = YES;

    MedisaleLineOverlayView *overlayView = [[MedisaleLineOverlayView alloc]
        initWithFrame:imageView.bounds];
    overlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlayView.imageView = imageView;
    overlayView.legacyModel = self.model;
    overlayView.session = self.session;
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
        [self.observers addObject:[center
            addObserverForName:NSWindowDidResignKeyNotification
            object:imageView.window queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf.session handleFocusLoss];
                [weakSelf syncLegacyModelFromSession];
                [weakSelf requestRedraw];
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
            if (self.panState.isActive) {
                return event;
            }
            if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
                if (self.session.state == MedisaleMeasurementInteractionStateEditing ||
                    self.session.selectedLandmarkIdentifier != 0) {
                    [self.session cancelCurrentOperation];
                    [self syncLegacyModelFromSession];
                    [self requestRedraw];
                    return nil;
                }
                return event;
            }
            if (event.type == NSEventTypeKeyDown &&
                (event.modifierFlags & NSEventModifierFlagCommand) != 0 &&
                [[event.charactersIgnoringModifiers lowercaseString]
                    isEqualToString:@"z"]) {
                BOOL redo = (event.modifierFlags & NSEventModifierFlagShift) != 0;
                if (redo ? [self.session redo] : [self.session undo]) {
                    [self syncLegacyModelFromSession];
                    [self requestRedraw];
                    return nil;
                }
                return event;
            }
            if (event.type == NSEventTypeLeftMouseDown) {
                return [self beginLandmarkDragForEvent:event] ? nil : event;
            }
            if (event.type == NSEventTypeLeftMouseDragged &&
                self.session.state == MedisaleMeasurementInteractionStateEditing) {
                [self updateLandmarkDragForEvent:event];
                return nil;
            }
            if (event.type == NSEventTypeLeftMouseUp &&
                self.session.state == MedisaleMeasurementInteractionStateEditing) {
                [self updateLandmarkDragForEvent:event];
                [self.session endSelectedLandmarkDrag];
                [self syncLegacyModelFromSession];
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
    [self.session cancelCurrentOperation];
    [self syncLegacyModelFromSession];
    [self requestRedraw];
}

- (NSDictionary<NSNumber *, NSValue *> *)displayPointsByIdentifier
{
    DCMView *imageView = self.viewer.imageView;
    NSMutableDictionary *points = [NSMutableDictionary dictionary];
    for (NamedImageLandmark *landmark in self.session.landmarks) {
        points[@(landmark.identifier)] = [NSValue valueWithPoint:
            [imageView ConvertFromGL2NSView:landmark.imagePoint]];
    }
    return points;
}

- (MedisaleLandmarkIdentifier)landmarkNearViewPoint:(NSPoint)viewPoint
{
    return [MeasurementLandmarkHitTester nearestLandmarkToViewPoint:viewPoint
        displayPointsByIdentifier:[self displayPointsByIdentifier]
        hitRadius:12.0];
}

- (BOOL)beginLandmarkDragForEvent:(NSEvent *)event
{
    if (!self.active || ![self currentImageMatchesModel]) {
        [self.session cancelCurrentOperation];
        if (self.active) {
            [self invalidate];
        }
        return NO;
    }
    DCMView *imageView = self.viewer.imageView;
    NSPoint viewPoint = [imageView convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(viewPoint, imageView.bounds)) {
        [self.session cancelCurrentOperation];
        [self syncLegacyModelFromSession];
        return NO;
    }
    MedisaleLandmarkIdentifier identifier = [self landmarkNearViewPoint:viewPoint];
    if (identifier == 0) {
        [self.session cancelCurrentOperation];
        [self syncLegacyModelFromSession];
        return NO;
    }
    BOOL began = [self.session selectLandmarkIdentifier:identifier] &&
        [self.session beginSelectedLandmarkDrag];
    [self syncLegacyModelFromSession];
    return began;
}

- (void)updateLandmarkDragForEvent:(NSEvent *)event
{
    if (self.session.state != MedisaleMeasurementInteractionStateEditing) {
        return;
    }
    if (![self currentImageMatchesModel]) {
        [self.session cancelCurrentOperation];
        [self invalidate];
        return;
    }
    DCMView *imageView = self.viewer.imageView;
    NSPoint viewPoint = [imageView convertPoint:event.locationInWindow fromView:nil];
    NSPoint imagePoint = [imageView ConvertFromNSView2GL:viewPoint];
    ImageContext *identity = self.model.imageIdentity;
    if (imagePoint.x < 0.0 || imagePoint.y < 0.0 ||
        imagePoint.x >= identity.pixelWidth || imagePoint.y >= identity.pixelHeight) {
        return;
    }
    [self.session updateSelectedLandmarkToImagePoint:imagePoint error:nil];
    [self syncLegacyModelFromSession];
    [self requestRedraw];
}

- (void)syncLegacyModelFromSession
{
    NamedImageLandmark *first = [self.session landmarkForIdentifier:
        MedisaleLandmarkIdentifierEndpointA];
    NamedImageLandmark *second = [self.session landmarkForIdentifier:
        MedisaleLandmarkIdentifierEndpointB];
    if (first != nil) [self.model updatePointA:first.imagePoint];
    if (second != nil) [self.model updatePointB:second.imagePoint];
    LineOverlayInputState inputState = LineOverlayInputStateComplete;
    if (self.session.selectedLandmarkIdentifier ==
            MedisaleLandmarkIdentifierEndpointA) {
        inputState = self.session.state == MedisaleMeasurementInteractionStateEditing
            ? LineOverlayInputStateEditingEndpointA
            : LineOverlayInputStateComplete;
    } else if (self.session.selectedLandmarkIdentifier ==
            MedisaleLandmarkIdentifierEndpointB) {
        inputState = self.session.state == MedisaleMeasurementInteractionStateEditing
            ? LineOverlayInputStateEditingEndpointB
            : LineOverlayInputStateComplete;
    }
    [self.model updateInputState:inputState];
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
    [self.session cancelCurrentOperation];
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
    self.overlayView.legacyModel = nil;
    self.overlayView.session = nil;
    self.overlayView = nil;

    MedisaleOverlayInvalidation invalidation = self.invalidation;
    self.invalidation = nil;
    self.panState = nil;
    [self.session invalidate];
    self.session = nil;
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
