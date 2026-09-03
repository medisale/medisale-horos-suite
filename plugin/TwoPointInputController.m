#import "TwoPointInputController.h"

#import "HoldSpacePanState.h"
#import "HorosAdapter.h"
#import "ImageContext.h"
#import "LegacyDistanceInteractionAdapter.h"
#import "MeasurementInteraction.h"
#import <DCMPix.h>
#import <DCMView.h>
#import <Notifications.h>
#import <ViewerController.h>

@interface TwoPointInputController ()
@property(nonatomic, weak, readwrite) ViewerController *viewer;
@property(nonatomic, copy) MedisaleTwoPointProgress progress;
@property(nonatomic, copy) MedisaleTwoPointCompletion completion;
@property(nonatomic, strong) id eventMonitor;
@property(nonatomic, strong) NSMutableArray *observers;
@property(nonatomic, weak) HoldSpacePanState *panState;
@property(nonatomic, copy) NSString *viewerOwnershipIdentifier;
@property(nonatomic, strong) MeasurementInteractionSession *session;
@end

@implementation TwoPointInputController

- (instancetype)initWithViewer:(ViewerController *)viewer
                       panState:(HoldSpacePanState *)panState
                       progress:(MedisaleTwoPointProgress)progress
                     completion:(MedisaleTwoPointCompletion)completion
{
    self = [super init];
    if (self) {
        _viewer = viewer;
        _panState = panState;
        _progress = [progress copy];
        _completion = [completion copy];
        _observers = [NSMutableArray array];
        _viewerOwnershipIdentifier = NSUUID.UUID.UUIDString;
    }
    return self;
}

- (instancetype)initWithViewer:(ViewerController *)viewer
                       progress:(MedisaleTwoPointProgress)progress
                     completion:(MedisaleTwoPointCompletion)completion
{
    return [self initWithViewer:viewer panState:nil progress:progress
                     completion:completion];
}

- (instancetype)initWithViewer:(ViewerController *)viewer
                     completion:(MedisaleTwoPointCompletion)completion
{
    return [self initWithViewer:viewer progress:nil completion:completion];
}

- (NSArray<NSValue *> *)points
{
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    for (NamedImageLandmark *landmark in self.session.landmarks) {
        [points addObject:[NSValue valueWithPoint:landmark.imagePoint]];
    }
    return [points copy];
}

- (MeasurementImageContext *)currentMeasurementImageContext
{
    NSError *error = nil;
    ImageContext *context = self.viewer == nil ? nil :
        [HorosAdapter imageContextForViewer:self.viewer error:&error];
    (void)error;
    if (context == nil) return nil;
    return [MeasurementImageContext
        contextWithStudyInstanceUID:context.studyInstanceUID
        seriesInstanceUID:context.seriesInstanceUID
        sopInstanceUID:context.sopInstanceUID frameNumber:context.frameNumber
        pixelWidth:context.pixelWidth pixelHeight:context.pixelHeight error:nil];
}

- (void)start
{
    if (self.eventMonitor != nil) {
        return;
    }

    MeasurementImageContext *context = [self currentMeasurementImageContext];
    self.session = [MeasurementInteractionSession
        sessionWithViewerOwnershipIdentifier:self.viewerOwnershipIdentifier
        definition:[LegacyDistanceInteractionAdapter interactionDefinition]
        imageContext:context error:nil];
    if (self.session == nil) {
        [self finishCancelled:YES];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSWindow *window = self.viewer.imageView.window;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (window != nil) {
        [self.observers addObject:[center
            addObserverForName:NSWindowWillCloseNotification
            object:window
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf cancel];
            }]];
        [self.observers addObject:[center
            addObserverForName:NSWindowDidResignKeyNotification
            object:window queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf.session handleFocusLoss];
            }]];
    }
    for (NSNotificationName name in @[OsirixDCMViewIndexChangedNotification,
                                      OsirixDCMUpdateCurrentImageNotification]) {
        [self.observers addObject:[center addObserverForName:name
            object:self.viewer.imageView queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                typeof(self) self = weakSelf;
                MeasurementImageContext *current =
                    [self currentMeasurementImageContext];
                if (self != nil &&
                    [self.session invalidateIfImageContextChanged:current]) {
                    [self finishCancelled:YES];
                }
            }]];
    }
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
        (NSEventMaskLeftMouseDown | NSEventMaskKeyDown)
        handler:^NSEvent * _Nullable(NSEvent *event) {
            typeof(self) self = weakSelf;
            if (self == nil) {
                return event;
            }
            DCMView *view = self.viewer.imageView;
            if (self.panState.isActive) {
                return event;
            }
            if (event.type == NSEventTypeKeyDown) {
                if (event.keyCode == 53 && event.window == view.window) {
                    [self cancel];
                    return nil;
                }
                if (event.window == view.window &&
                    (event.modifierFlags & NSEventModifierFlagCommand) != 0 &&
                    [[event.charactersIgnoringModifiers lowercaseString]
                        isEqualToString:@"z"]) {
                    BOOL redo = (event.modifierFlags & NSEventModifierFlagShift) != 0;
                    if (redo ? [self.session redo] : [self.session undo]) {
                        MedisaleTwoPointProgress progress = self.progress;
                        if (progress != nil) progress(self.session.collectedLandmarkCount);
                        return nil;
                    }
                }
                return event;
            }
            if (event.type != NSEventTypeLeftMouseDown || event.window != view.window) {
                return event;
            }
            NSPoint viewPoint = [view convertPoint:event.locationInWindow fromView:nil];
            if (!NSPointInRect(viewPoint, view.bounds)) {
                return event;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self captureCurrentImagePoint];
            });
            return event;
        }];
}

- (void)captureCurrentImagePoint
{
    DCMView *view = self.viewer.imageView;
    DCMPix *pix = view.curDCM;
    NSPoint point = NSMakePoint(view.mouseXPos, view.mouseYPos);
    if (pix == nil || point.x < 0 || point.y < 0 ||
        point.x >= pix.pwidth || point.y >= pix.pheight) {
        return;
    }
    MeasurementImageContext *current = [self currentMeasurementImageContext];
    if (![self.session acceptsEventsForViewerOwnershipIdentifier:
            self.viewerOwnershipIdentifier imageContext:current] ||
        ![self.session collectImagePoint:point error:nil]) {
        return;
    }
    MedisaleTwoPointProgress progress = self.progress;
    if (progress != nil) {
        progress(self.session.collectedLandmarkCount);
    }
    if (self.session.state == MedisaleMeasurementInteractionStateComplete) {
        [self finishCancelled:NO];
    }
}

- (void)cancel
{
    [self.session cancelCurrentOperation];
    [self finishCancelled:YES];
}

- (void)removeRuntimeHooks
{
    if (self.eventMonitor != nil) {
        [NSEvent removeMonitor:self.eventMonitor];
        self.eventMonitor = nil;
    }
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (id observer in self.observers) [center removeObserver:observer];
    [self.observers removeAllObjects];
}

- (void)invalidate
{
    [self removeRuntimeHooks];
    self.completion = nil;
    self.progress = nil;
    self.panState = nil;
    [self.session invalidate];
    self.session = nil;
    self.viewer = nil;
}

- (void)finishCancelled:(BOOL)cancelled
{
    [self removeRuntimeHooks];
    MedisaleTwoPointCompletion completion = self.completion;
    self.completion = nil;
    self.progress = nil;
    if (completion != nil) {
        completion(cancelled, self.points);
    }
}

- (void)dealloc
{
    [self invalidate];
}

@end
