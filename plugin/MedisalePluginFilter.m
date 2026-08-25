#import <Cocoa/Cocoa.h>
#import <BrowserController.h>
#import <DicomSeries.h>
#import <DicomStudy.h>
#import <Notifications.h>
#import <PluginFilter.h>
#import "CompactGuideViewState.h"
#import "GuideEngine.h"
#import "GuidePreferenceStore.h"
#import "HoldSpacePanState.h"
#import "HorosAdapter.h"
#import "ImageContext.h"
#import "LineOverlayModel.h"
#import "MeasurementPanelHost.h"
#import "MeasurementContextConsumer.h"
#import "MeasurementPersistenceStore.h"
#import "MeasurementRecord.h"
#import "SQLiteMeasurementStore.h"
#import "TransientLineOverlayController.h"
#import "TemporaryPanController.h"
#import "TwoPointInputController.h"
#import "ViewerInspectorPanelHost.h"

static NSString *const MedisaleViewerToolbarIdentifier = @"jp.medisale.horos.viewer-toolbar-test";
static NSString *const MedisaleBrowserToolbarIdentifier = @"jp.medisale.horos.browser-toolbar-test";
static NSString *const MedisaleContextToolbarIdentifier = @"jp.medisale.horos.image-context-test";
static NSString *const MedisaleTwoPointToolbarIdentifier = @"jp.medisale.horos.two-point-test";

@interface MedisalePluginFilter : PluginFilter {
    NSMapTable<NSToolbarItem *, id> *_viewerByToolbarItem;
    NSMapTable<id, NSNumber *> *_viewerNumberByViewer;
    NSMapTable<NSToolbarItem *, BrowserController *> *_browserByToolbarItem;
    NSMapTable<ViewerController *, TwoPointInputController *> *_inputByViewer;
    NSMapTable<ViewerController *, TransientLineOverlayController *> *_overlayByViewer;
    NSMapTable<ViewerController *, id<MeasurementPanelHost>> *_panelByViewer;
    NSMapTable<ViewerController *, CompactGuideViewState *> *_guideStateByViewer;
    NSMapTable<ViewerController *, TemporaryPanController *> *_panByViewer;
    GuideEngine *_guideEngine;
    id<MeasurementPersistenceStore> _measurementStore;
    NSMutableArray *_restoreObservers;
    BOOL _restoreScheduled;
    NSUInteger _nextViewerNumber;
}
@end

@implementation MedisalePluginFilter

- (void)initPlugin
{
    [self ensureViewerTracking];
    [self installRestoreObservers];
    [self scheduleRestoreForOpenViewers];
}

- (void)willUnload
{
    NSArray *inputs = _inputByViewer.objectEnumerator.allObjects;
    NSArray *overlays = _overlayByViewer.objectEnumerator.allObjects;
    NSArray *panels = _panelByViewer.objectEnumerator.allObjects;
    NSArray *pans = _panByViewer.objectEnumerator.allObjects;
    for (TemporaryPanController *pan in pans) {
        [pan invalidate];
    }
    for (TwoPointInputController *input in inputs) {
        [input invalidate];
    }
    for (TransientLineOverlayController *overlay in overlays) {
        [overlay invalidate];
    }
    for (id<MeasurementPanelHost> panel in panels) {
        [panel invalidate];
    }
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (id observer in _restoreObservers) {
        [center removeObserver:observer];
    }
    [_restoreObservers removeAllObjects];
    _restoreObservers = nil;
    _restoreScheduled = NO;
    _inputByViewer = nil;
    _overlayByViewer = nil;
    _panelByViewer = nil;
    _guideStateByViewer = nil;
    _panByViewer = nil;
    _viewerByToolbarItem = nil;
    _viewerNumberByViewer = nil;
    _browserByToolbarItem = nil;
    _measurementStore = nil;
    _guideEngine = nil;
}

- (void)installRestoreObservers
{
    if (_restoreObservers != nil) {
        return;
    }
    _restoreObservers = [NSMutableArray array];
    NSArray<NSNotificationName> *names = @[
        OsirixViewerControllerDidLoadImagesNotification,
        OsirixDCMViewIndexChangedNotification,
        OsirixDCMUpdateCurrentImageNotification,
        OsirixViewerDidChangeNotification,
    ];
    __weak typeof(self) weakSelf = self;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in names) {
        [_restoreObservers addObject:[center
            addObserverForName:name object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf scheduleRestoreForOpenViewers];
            }]];
    }
}

- (void)scheduleRestoreForOpenViewers
{
    if (_restoreScheduled) {
        return;
    }
    _restoreScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (self == nil) {
            return;
        }
        self->_restoreScheduled = NO;
        [self restoreMeasurementsForOpenViewers];
    });
}

- (void)restoreMeasurementsForOpenViewers
{
    NSArray *viewers = [self viewerControllersList];
    for (id candidate in viewers) {
        if ([candidate isKindOfClass:[ViewerController class]]) {
            [self restoreMeasurementForViewer:(ViewerController *)candidate];
        }
    }
}

- (void)restoreMeasurementForViewer:(ViewerController *)viewer
{
    if (viewer == nil || viewer.window == nil) {
        return;
    }
    TemporaryPanController *panController =
        [self temporaryPanControllerForViewer:viewer];
    NSError *contextError = nil;
    ImageContext *context = [HorosAdapter imageContextForViewer:viewer error:&contextError];
    (void)contextError;

    CompactGuideViewState *activeGuide = [_guideStateByViewer objectForKey:viewer];
    if (activeGuide != nil && ![activeGuide matchesImageContext:context]) {
        [activeGuide markUnavailable];
        TwoPointInputController *input = [_inputByViewer objectForKey:viewer];
        [_inputByViewer removeObjectForKey:viewer];
        [input cancel];
        TransientLineOverlayController *overlay = [_overlayByViewer objectForKey:viewer];
        [_overlayByViewer removeObjectForKey:viewer];
        [overlay invalidate];
        id<MeasurementPanelHost> panel = [_panelByViewer objectForKey:viewer];
        [_panelByViewer removeObjectForKey:viewer];
        [panel invalidate];
        [_guideStateByViewer removeObjectForKey:viewer];
        return;
    }
    if ([_inputByViewer objectForKey:viewer] != nil) {
        return;
    }

    TransientLineOverlayController *existing = [_overlayByViewer objectForKey:viewer];
    ImageContext *existingIdentity = existing.model.imageIdentity;
    BOOL existingMatches = existing.isActive && context != nil &&
        [existingIdentity.studyInstanceUID isEqualToString:context.studyInstanceUID] &&
        [existingIdentity.seriesInstanceUID isEqualToString:context.seriesInstanceUID] &&
        [existingIdentity.sopInstanceUID isEqualToString:context.sopInstanceUID] &&
        existingIdentity.frameNumber == context.frameNumber;
    if (existingMatches) {
        return;
    }
    if (existing != nil) {
        [existing invalidate];
    }
    if (context == nil) {
        return;
    }

    NSError *storeError = nil;
    id<MeasurementPersistenceStore> store = [self measurementStoreWithError:&storeError];
    if (store == nil) {
        return;
    }
    MeasurementRecord *record = [store latestMeasurementForImageContext:context
                                                                    error:&storeError];
    if (record == nil) {
        return;
    }

    if (_overlayByViewer == nil) {
        _overlayByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    LineOverlayModel *model = [[LineOverlayModel alloc]
        initWithPointA:NSMakePoint(record.endpointAX, record.endpointAY)
                pointB:NSMakePoint(record.endpointBX, record.endpointBY)
         imageIdentity:context];
    CompactGuideCalibrationState calibration =
        context.pixelSpacingX > 0.0 && context.pixelSpacingY > 0.0
            ? CompactGuideCalibrationStateDICOMSpacingOnly
            : CompactGuideCalibrationStateUnknown;
    CompactGuideViewState *guideState = [[CompactGuideViewState alloc]
        initWithImageIdentity:context calibrationState:calibration];
    [guideState markCalculated];
    if (_guideStateByViewer == nil) {
        _guideStateByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    [_guideStateByViewer setObject:guideState forKey:viewer];
    __weak typeof(self) weakSelf = self;
    __weak ViewerController *weakViewer = viewer;
    __block __weak TransientLineOverlayController *weakOverlay = nil;
    TransientLineOverlayController *overlay = [[TransientLineOverlayController alloc]
        initWithViewer:viewer model:model panState:panController.state invalidation:^{
            typeof(self) self = weakSelf;
            ViewerController *viewer = weakViewer;
            TransientLineOverlayController *overlay = weakOverlay;
            if (self != nil && viewer != nil &&
                [self->_overlayByViewer objectForKey:viewer] == overlay) {
                [self->_overlayByViewer removeObjectForKey:viewer];
            }
            id<MeasurementPanelHost> panel =
                [self->_panelByViewer objectForKey:viewer];
            [self->_panelByViewer removeObjectForKey:viewer];
            [panel invalidate];
        }];
    weakOverlay = overlay;
    [_overlayByViewer setObject:overlay forKey:viewer];
    if (![overlay start]) {
        [_overlayByViewer removeObjectForKey:viewer];
        [overlay invalidate];
        if ([_guideStateByViewer objectForKey:viewer] == guideState) {
            [_guideStateByViewer removeObjectForKey:viewer];
        }
        return;
    }

    if (_panelByViewer == nil) {
        _panelByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    __block __weak id<MeasurementPanelHost> weakPanel = nil;
    id<MeasurementPanelHost> panel = [[ViewerInspectorPanelHost alloc]
        initWithViewer:viewer
                 model:model
            guideState:guideState
           guideEngine:[self guideEngine]
      persistenceStore:store
   existingMeasurement:record
          cancellation:^{
            TransientLineOverlayController *overlay = weakOverlay;
            if (guideState.measurementState == CompactGuideMeasurementStateEditing) {
                [overlay cancelCurrentInteraction];
            } else {
                [overlay invalidate];
            }
          }
          invalidation:^{
            typeof(self) self = weakSelf;
            ViewerController *viewer = weakViewer;
            id<MeasurementPanelHost> panel = weakPanel;
            if (self != nil && viewer != nil &&
                [self->_panelByViewer objectForKey:viewer] == panel) {
                [self->_panelByViewer removeObjectForKey:viewer];
            }
            if (self != nil && viewer != nil &&
                [self->_guideStateByViewer objectForKey:viewer] == guideState) {
                [self->_guideStateByViewer removeObjectForKey:viewer];
            }
        }];
    weakPanel = panel;
    [_panelByViewer setObject:panel forKey:viewer];
    if (![panel present]) {
        [_panelByViewer removeObjectForKey:viewer];
        [panel invalidate];
        [_overlayByViewer removeObjectForKey:viewer];
        [overlay invalidate];
    }
}

- (id<MeasurementPersistenceStore>)measurementStoreWithError:(NSError **)error
{
    if (_measurementStore == nil) {
        _measurementStore = [SQLiteMeasurementStore pluginOwnedStoreWithError:error];
    }
    return _measurementStore;
}

- (GuideEngine *)guideEngine
{
    if (_guideEngine == nil) {
        id<GuidePreferenceStore> store = [[CFPreferencesGuidePreferenceStore alloc]
            initWithApplicationIdentifier:MedisaleGuidePreferenceApplicationIdentifier
                                     key:MedisaleDetailedGuidePreferenceKey
                            defaultValue:NO];
        _guideEngine = [[GuideEngine alloc] initWithPreferenceStore:store];
    }
    return _guideEngine;
}

- (long)filterImage:(NSString *)menuName
{
    (void)menuName;

    if (viewerController != nil) {
        [self startTwoPointInputForViewer:viewerController];
        return 0;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Medisale Plugin OK";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];

    return 0;
}

- (void)startTwoPointInputForViewer:(ViewerController *)controller
{
    TemporaryPanController *panController =
        [self temporaryPanControllerForViewer:controller];
    TransientLineOverlayController *existingOverlay =
        [_overlayByViewer objectForKey:controller];
    id<MeasurementPanelHost> existingPanel = [_panelByViewer objectForKey:controller];
    if (existingOverlay.isActive && existingPanel.isBound) {
        if (!existingPanel.isVisible) {
            [existingPanel present];
        }
        return;
    }

    NSError *contextError = nil;
    ImageContext *inputIdentity = [HorosAdapter imageContextForViewer:controller
                                                                error:&contextError];
    if (inputIdentity == nil) {
        NSAlert *stop = [[NSAlert alloc] init];
        stop.messageText = @"Transient Overlay STOP";
        stop.informativeText = contextError.localizedDescription;
        [stop addButtonWithTitle:@"OK"];
        [stop runModal];
        return;
    }
    NSError *storeError = nil;
    id<MeasurementPersistenceStore> persistenceStore =
        [self measurementStoreWithError:&storeError];
    if (persistenceStore == nil) {
        NSAlert *stop = [[NSAlert alloc] init];
        stop.messageText = @"Measurement Store STOP";
        stop.informativeText = storeError.localizedDescription ?:
            @"The standalone measurement store could not be opened safely.";
        [stop addButtonWithTitle:@"OK"];
        [stop runModal];
        return;
    }
    if (_inputByViewer == nil) {
        _inputByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    TwoPointInputController *existing = [_inputByViewer objectForKey:controller];
    [existing cancel];

    CompactGuideCalibrationState calibration =
        inputIdentity.pixelSpacingX > 0.0 && inputIdentity.pixelSpacingY > 0.0
            ? CompactGuideCalibrationStateDICOMSpacingOnly
            : CompactGuideCalibrationStateUnknown;
    CompactGuideViewState *guideState = [[CompactGuideViewState alloc]
        initWithImageIdentity:inputIdentity calibrationState:calibration];
    [guideState startCollecting];
    if (_guideStateByViewer == nil) {
        _guideStateByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    [_guideStateByViewer setObject:guideState forKey:controller];

    __weak typeof(self) weakSelf = self;
    __weak ViewerController *weakViewer = controller;
    __block __weak TwoPointInputController *weakInput = nil;
    __block __weak TransientLineOverlayController *weakOverlay = nil;
    __block __weak id<MeasurementPanelHost> weakPanel = nil;

    if (_panelByViewer == nil) {
        _panelByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    id<MeasurementPanelHost> panel = [[ViewerInspectorPanelHost alloc]
        initWithViewer:controller model:nil guideState:guideState
           guideEngine:[self guideEngine] persistenceStore:nil
    existingMeasurement:nil cancellation:^{
        TwoPointInputController *input = weakInput;
        TransientLineOverlayController *overlay = weakOverlay;
        if (input != nil) {
            [input cancel];
        } else if (guideState.measurementState == CompactGuideMeasurementStateEditing) {
            [overlay cancelCurrentInteraction];
        } else {
            [overlay invalidate];
        }
    } invalidation:^{
        typeof(self) self = weakSelf;
        ViewerController *viewer = weakViewer;
        id<MeasurementPanelHost> panel = weakPanel;
        if (self != nil && viewer != nil &&
            [self->_panelByViewer objectForKey:viewer] == panel) {
            [self->_panelByViewer removeObjectForKey:viewer];
        }
        if (self != nil && viewer != nil &&
            [self->_guideStateByViewer objectForKey:viewer] == guideState) {
            [self->_guideStateByViewer removeObjectForKey:viewer];
        }
    }];
    weakPanel = panel;
    [_panelByViewer setObject:panel forKey:controller];
    if (![panel present]) {
        [_panelByViewer removeObjectForKey:controller];
        [panel invalidate];
        return;
    }

    TwoPointInputController *input = [[TwoPointInputController alloc]
        initWithViewer:controller
        panState:panController.state
        progress:^(NSUInteger pointCount) {
            [guideState updateCollectedPointCount:pointCount];
        }
        completion:^(BOOL cancelled, NSArray<NSValue *> *points) {
            typeof(self) self = weakSelf;
            ViewerController *viewer = weakViewer;
            if (self == nil) {
                return;
            }
            [self->_inputByViewer removeObjectForKey:viewer];
            if (cancelled) {
                [guideState cancelCurrentOperation];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(0.8 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [guideState settleCancellationToIdle];
                });
                return;
            }
            if (points.count != 2 || viewer == nil) {
                [guideState markUnavailable];
                return;
            }
            NSError *currentError = nil;
            ImageContext *currentIdentity =
                [HorosAdapter imageContextForViewer:viewer error:&currentError];
            (void)currentError;
            if (![guideState matchesImageContext:currentIdentity]) {
                [guideState markUnavailable];
                return;
            }

            NSPoint a = points[0].pointValue;
            NSPoint b = points[1].pointValue;
            if (self->_overlayByViewer == nil) {
                self->_overlayByViewer = [NSMapTable weakToStrongObjectsMapTable];
            }
            LineOverlayModel *model = [[LineOverlayModel alloc]
                initWithPointA:a pointB:b imageIdentity:currentIdentity];
            TransientLineOverlayController *overlay =
                [[TransientLineOverlayController alloc] initWithViewer:viewer
                    model:model panState:panController.state invalidation:^{
                typeof(self) self = weakSelf;
                ViewerController *viewer = weakViewer;
                TransientLineOverlayController *overlay = weakOverlay;
                if (self != nil && viewer != nil &&
                    [self->_overlayByViewer objectForKey:viewer] == overlay) {
                    [self->_overlayByViewer removeObjectForKey:viewer];
                }
                id<MeasurementPanelHost> panel =
                    [self->_panelByViewer objectForKey:viewer];
                [self->_panelByViewer removeObjectForKey:viewer];
                [panel invalidate];
            }];
            weakOverlay = overlay;
            [self->_overlayByViewer setObject:overlay forKey:viewer];
            if (![overlay start]) {
                [self->_overlayByViewer removeObjectForKey:viewer];
                [overlay invalidate];
                [guideState markUnavailable];
                return;
            }
            [panel bindModel:model persistenceStore:persistenceStore
         existingMeasurement:nil];
            [guideState markCalculated];
        }];
    weakInput = input;
    [_inputByViewer setObject:input forKey:controller];
    [input start];
}

- (BOOL)isCertifiedForMedicalImaging
{
    return NO;
}

- (NSArray *)toolbarAllowedIdentifiersForViewer:(id)controller
{
    (void)controller;
    return @[MedisaleViewerToolbarIdentifier, MedisaleContextToolbarIdentifier,
             MedisaleTwoPointToolbarIdentifier];
}

- (NSToolbarItem *)toolbarItemForItemIdentifier:(NSString *)identifier forViewer:(id)controller
{
    if ((! [identifier isEqualToString:MedisaleViewerToolbarIdentifier] &&
         ![identifier isEqualToString:MedisaleContextToolbarIdentifier] &&
         ![identifier isEqualToString:MedisaleTwoPointToolbarIdentifier]) || controller == nil) {
        return nil;
    }

    [self ensureViewerTracking];
    [self temporaryPanControllerForViewer:controller];

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    BOOL contextItem = [identifier isEqualToString:MedisaleContextToolbarIdentifier];
    BOOL twoPointItem = [identifier isEqualToString:MedisaleTwoPointToolbarIdentifier];
    item.label = contextItem ? @"Medisale Context" :
        (twoPointItem ? @"Medisale Overlay" : @"Medisale Test");
    item.paletteLabel = item.label;
    item.toolTip = contextItem ? @"Create an independent ImageContext" :
        (twoPointItem ? @"Draw a transient line from two image-coordinate points" : @"Verify the owning Viewer");
    item.image = [NSImage imageNamed:NSImageNameActionTemplate];
    item.target = self;
    item.action = contextItem ? @selector(showImageContext:) :
        (twoPointItem ? @selector(startTwoPointInput:) : @selector(showViewerToolbarOK:));

    [_viewerByToolbarItem setObject:controller forKey:item];
    [self viewerNumberForViewer:controller];
    [self scheduleRestoreForOpenViewers];

    return item;
}

- (void)startTwoPointInput:(id)sender
{
    ViewerController *controller = [sender isKindOfClass:[NSToolbarItem class]]
        ? [_viewerByToolbarItem objectForKey:sender]
        : nil;
    if (controller != nil) {
        [self startTwoPointInputForViewer:controller];
    }
}

- (void)showImageContext:(id)sender
{
    ViewerController *controller = [sender isKindOfClass:[NSToolbarItem class]]
        ? [_viewerByToolbarItem objectForKey:sender]
        : nil;
    [self showImageContextForViewer:controller];
}

- (void)showImageContextForViewer:(ViewerController *)controller
{
    NSError *error = nil;
    ImageContext *context = controller == nil ? nil :
        [HorosAdapter imageContextForViewer:controller error:&error];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = context == nil ? @"Image Context STOP" : @"Image Context OK";
    alert.informativeText = context == nil ? error.localizedDescription
        : MedisaleMeasurementSummary(context);
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showViewerToolbarOK:(id)sender
{
    id controller = [sender isKindOfClass:[NSToolbarItem class]]
        ? [_viewerByToolbarItem objectForKey:sender]
        : nil;
    NSNumber *viewerNumber = controller == nil ? nil : [self viewerNumberForViewer:controller];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Viewer Toolbar OK";
    alert.informativeText = viewerNumber == nil
        ? @"Owning Viewer: Closed"
        : [NSString stringWithFormat:@"Owning Viewer: Viewer %@", viewerNumber];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Duplicate Viewer"];

    if ([alert runModal] == NSAlertSecondButtonReturn && controller != nil) {
        ViewerController *previousViewerController = viewerController;
        viewerController = controller;
        [self duplicateCurrent2DViewerWindow];
        viewerController = previousViewerController;
    }
}

- (void)ensureViewerTracking
{
    if (_viewerByToolbarItem == nil) {
        _viewerByToolbarItem = [NSMapTable weakToWeakObjectsMapTable];
        _viewerNumberByViewer = [NSMapTable weakToStrongObjectsMapTable];
        _nextViewerNumber = 1;
    }
}

- (NSNumber *)viewerNumberForViewer:(id)controller
{
    [self ensureViewerTracking];

    NSNumber *viewerNumber = [_viewerNumberByViewer objectForKey:controller];
    if (viewerNumber == nil) {
        viewerNumber = @(_nextViewerNumber++);
        [_viewerNumberByViewer setObject:viewerNumber forKey:controller];
    }
    return viewerNumber;
}

- (TemporaryPanController *)temporaryPanControllerForViewer:(ViewerController *)viewer
{
    if (viewer == nil || viewer.window == nil) {
        return nil;
    }
    if (_panByViewer == nil) {
        _panByViewer = [NSMapTable weakToStrongObjectsMapTable];
    }
    TemporaryPanController *existing = [_panByViewer objectForKey:viewer];
    if (existing.isValid) {
        return existing;
    }
    [existing invalidate];
    TemporaryPanController *controller =
        [[TemporaryPanController alloc] initWithViewer:viewer];
    if (![controller start]) {
        [controller invalidate];
        return nil;
    }
    [_panByViewer setObject:controller forKey:viewer];
    return controller;
}

- (NSArray *)toolbarAllowedIdentifiersForBrowserController:(id)controller
{
    (void)controller;
    return @[MedisaleBrowserToolbarIdentifier];
}

- (NSToolbarItem *)toolbarItemForItemIdentifier:(NSString *)identifier
                           forBrowserController:(id)controller
{
    if (![identifier isEqualToString:MedisaleBrowserToolbarIdentifier] ||
        ![controller isKindOfClass:[BrowserController class]]) {
        return nil;
    }

    if (_browserByToolbarItem == nil) {
        _browserByToolbarItem = [NSMapTable weakToWeakObjectsMapTable];
    }

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"Medisale Tools Test";
    item.paletteLabel = @"Medisale Tools Test";
    item.toolTip = @"Inspect the Browser selection without changing it";
    item.image = [NSImage imageNamed:NSImageNameInfo];
    item.target = self;
    item.action = @selector(showBrowserToolbarOK:);

    [_browserByToolbarItem setObject:controller forKey:item];
    return item;
}

- (void)showBrowserToolbarOK:(id)sender
{
    BrowserController *controller = [sender isKindOfClass:[NSToolbarItem class]]
        ? [_browserByToolbarItem objectForKey:sender]
        : nil;
    NSArray *selection = controller == nil ? @[] : [controller databaseSelection];
    NSUInteger studyCount = 0;
    NSUInteger seriesCount = 0;
    NSUInteger otherCount = 0;

    for (id object in selection) {
        if ([object isKindOfClass:[DicomStudy class]]) {
            studyCount++;
        } else if ([object isKindOfClass:[DicomSeries class]]) {
            seriesCount++;
        } else {
            otherCount++;
        }
    }

    NSString *summary;
    if (selection.count == 0) {
        summary = @"Selection: None";
    } else if (selection.count == 1 && studyCount == 1) {
        summary = @"Selection: Study 1";
    } else if (selection.count == 1 && seriesCount == 1) {
        summary = @"Selection: Series 1";
    } else {
        summary = [NSString stringWithFormat:
            @"Selection: Multiple %lu (Studies %lu, Series %lu, Other %lu)",
            (unsigned long)selection.count,
            (unsigned long)studyCount,
            (unsigned long)seriesCount,
            (unsigned long)otherCount];
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Browser Toolbar OK";
    alert.informativeText = summary;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
