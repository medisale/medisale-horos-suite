#import "ViewerInspectorPanelHost.h"

#import "CompactGuideLayoutPolicy.h"
#import "CompactGuideLocalization.h"
#import "CompactGuidePresentation.h"
#import "CompactGuideViewState.h"
#import "GuideEngine.h"
#import "LineOverlayModel.h"
#import "MeasurementPersistenceStore.h"
#import "MeasurementRecord.h"
#import <ViewerController.h>

@interface ViewerInspectorPanelHost ()
@property(nonatomic, weak) ViewerController *viewer;
@property(nonatomic, strong, nullable) LineOverlayModel *model;
@property(nonatomic, strong) CompactGuideViewState *guideState;
@property(nonatomic, strong) GuideEngine *guideEngine;
@property(nonatomic, strong) CompactGuideLocalization *localization;
@property(nonatomic, strong, nullable) id<MeasurementPersistenceStore> persistenceStore;
@property(nonatomic, copy) NSString *measurementID;
@property(nonatomic, copy) NSDate *createdAt;
@property(nonatomic, copy, nullable) MedisalePanelHostCancellation cancellation;
@property(nonatomic, copy) MedisalePanelHostInvalidation invalidation;
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSTextField *modeField;
@property(nonatomic, strong) NSTextField *instructionField;
@property(nonatomic, strong) NSTextField *progressField;
@property(nonatomic, strong) NSImageView *calibrationIcon;
@property(nonatomic, strong) NSTextField *calibrationField;
@property(nonatomic, strong) NSImageView *confirmationIcon;
@property(nonatomic, strong) NSTextField *confirmationField;
@property(nonatomic, strong) NSButton *detailsButton;
@property(nonatomic, strong) NSButton *cancelButton;
@property(nonatomic, strong) NSButton *confirmButton;
@property(nonatomic, strong) NSScrollView *detailsScrollView;
@property(nonatomic, strong) NSTextField *detailsField;
@property(nonatomic, strong) NSButton *saveButton;
@property(nonatomic, strong) NSTextField *saveStatusField;
@property(nonatomic, strong) NSMutableArray *observers;
@property(nonatomic, strong, nullable) id modelObserver;
@property(nonatomic, readwrite, getter=isBound) BOOL bound;
@property(nonatomic) BOOL userClosed;
@property(nonatomic) BOOL hasSaved;
@property(nonatomic) BOOL restoredMeasurement;
@property(nonatomic) NSPoint savedPointA;
@property(nonatomic) NSPoint savedPointB;
@property(nonatomic) NSPoint editOriginA;
@property(nonatomic) NSPoint editOriginB;
@property(nonatomic) LineOverlayInputState previousInputState;
@property(nonatomic) CompactGuideMeasurementState lastAnnouncedState;
@end

@implementation ViewerInspectorPanelHost

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(LineOverlayModel *)model
                      guideState:(CompactGuideViewState *)guideState
                     guideEngine:(GuideEngine *)guideEngine
                persistenceStore:(id<MeasurementPersistenceStore>)persistenceStore
             existingMeasurement:(MeasurementRecord *)existingMeasurement
                    cancellation:(MedisalePanelHostCancellation)cancellation
                    invalidation:(MedisalePanelHostInvalidation)invalidation
{
    self = [super init];
    if (self) {
        _viewer = viewer;
        _model = model;
        _guideState = guideState;
        _guideEngine = guideEngine;
        _localization = [CompactGuideLocalization pluginLocalization];
        _persistenceStore = persistenceStore;
        _measurementID = existingMeasurement == nil
            ? NSUUID.UUID.UUIDString : existingMeasurement.measurementID;
        _createdAt = existingMeasurement == nil
            ? [NSDate date] : existingMeasurement.createdAt;
        _cancellation = [cancellation copy];
        _invalidation = [invalidation copy];
        _observers = [NSMutableArray array];
        _lastAnnouncedState = guideState.measurementState;
        [self applyExistingMeasurement:existingMeasurement];
        if (model != nil) {
            _previousInputState = model.inputState;
            [self syncReviewSnapshotFromModel];
        }
    }
    return self;
}

- (void)applyExistingMeasurement:(MeasurementRecord *)existingMeasurement
{
    self.hasSaved = existingMeasurement != nil;
    self.restoredMeasurement = existingMeasurement != nil;
    if (existingMeasurement != nil) {
        self.measurementID = existingMeasurement.measurementID;
        self.createdAt = existingMeasurement.createdAt;
        self.savedPointA = NSMakePoint(existingMeasurement.endpointAX,
                                      existingMeasurement.endpointAY);
        self.savedPointB = NSMakePoint(existingMeasurement.endpointBX,
                                      existingMeasurement.endpointBY);
    }
}

- (void)bindModel:(LineOverlayModel *)model
 persistenceStore:(id<MeasurementPersistenceStore>)persistenceStore
existingMeasurement:(MeasurementRecord *)existingMeasurement
{
    [self removeModelObserver];
    self.model = model;
    self.persistenceStore = persistenceStore;
    self.previousInputState = model.inputState;
    self.editOriginA = model.pointA;
    self.editOriginB = model.pointB;
    [self applyExistingMeasurement:existingMeasurement];
    [self syncReviewSnapshotFromModel];
    if (self.bound) {
        [self installModelObserver];
    }
    [self updateFieldsAndLayout:YES];
}

- (BOOL)isVisible
{
    return self.panel.isVisible;
}

- (BOOL)present
{
    ViewerController *viewer = self.viewer;
    NSWindow *viewerWindow = viewer.window;
    if (viewer == nil || viewerWindow == nil || self.guideState == nil ||
        self.guideEngine == nil) {
        return NO;
    }
    if (self.panel == nil) {
        [self buildPanel];
        [self installObserversForViewerWindow:viewerWindow];
    }
    self.bound = YES;
    self.userClosed = NO;
    [self installModelObserver];
    [self updateFieldsAndLayout:NO];
    [self followViewerWindow];
    [self.panel orderFront:nil];
    return YES;
}

- (NSTextField *)wrappingLabel
{
    NSTextField *field = [NSTextField labelWithString:@""];
    field.lineBreakMode = NSLineBreakByWordWrapping;
    field.maximumNumberOfLines = 0;
    field.cell.wraps = YES;
    return field;
}

- (void)buildPanel
{
    NSRect frame = NSMakeRect(0.0, 0.0, 248.0, 124.0);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
        NSWindowStyleMaskClosable |
        NSWindowStyleMaskUtilityWindow |
        NSWindowStyleMaskNonactivatingPanel;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = [self.localization stringForKey:@"guide.panel.title"];
    panel.releasedWhenClosed = NO;
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.hidesOnDeactivate = YES;
    panel.level = NSNormalWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorTransient;
    panel.delegate = self;

    NSView *content = [[NSView alloc] initWithFrame:frame];
    content.autoresizesSubviews = YES;
    panel.contentView = content;

    self.modeField = [self wrappingLabel];
    self.modeField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    self.instructionField = [self wrappingLabel];
    self.instructionField.font = [NSFont systemFontOfSize:11.5];
    self.progressField = [self wrappingLabel];
    self.progressField.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    self.calibrationIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.calibrationField = [self wrappingLabel];
    self.calibrationField.font = [NSFont systemFontOfSize:10.5];
    self.confirmationIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.confirmationField = [self wrappingLabel];
    self.confirmationField.font = [NSFont systemFontOfSize:10.5];

    self.detailsButton = [NSButton buttonWithTitle:@"" target:self
                                           action:@selector(toggleDetails:)];
    self.cancelButton = [NSButton buttonWithTitle:@"" target:self
                                          action:@selector(cancelPressed:)];
    self.confirmButton = [NSButton buttonWithTitle:@"" target:self
                                           action:@selector(confirmPressed:)];
    for (NSButton *button in @[self.detailsButton, self.cancelButton,
                              self.confirmButton]) {
        button.bezelStyle = NSBezelStyleRounded;
        button.controlSize = NSControlSizeSmall;
    }

    self.detailsField = [self wrappingLabel];
    self.detailsField.font = [NSFont systemFontOfSize:11.0];
    self.detailsField.textColor = NSColor.secondaryLabelColor;
    NSView *documentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 200)];
    [documentView addSubview:self.detailsField];
    self.detailsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.detailsScrollView.hasVerticalScroller = YES;
    self.detailsScrollView.borderType = NSNoBorder;
    self.detailsScrollView.drawsBackground = NO;
    self.detailsScrollView.documentView = documentView;

    self.saveButton = [NSButton buttonWithTitle:
        [self.localization stringForKey:@"guide.button.saveSpike"]
                                         target:self action:@selector(saveMeasurement:)];
    self.saveButton.controlSize = NSControlSizeSmall;
    self.saveStatusField = [self wrappingLabel];
    self.saveStatusField.font = [NSFont systemFontOfSize:9.5];
    self.saveStatusField.textColor = NSColor.secondaryLabelColor;

    for (NSView *view in @[self.modeField, self.instructionField,
                          self.progressField, self.calibrationIcon,
                          self.calibrationField, self.confirmationIcon,
                          self.confirmationField, self.detailsButton,
                          self.cancelButton, self.confirmButton,
                          self.detailsScrollView, self.saveButton,
                          self.saveStatusField]) {
        [content addSubview:view];
    }

    [self configureAccessibility];
    self.detailsButton.nextKeyView = self.cancelButton;
    self.cancelButton.nextKeyView = self.confirmButton;
    self.confirmButton.nextKeyView = self.detailsButton;
    self.panel = panel;
}

- (void)configureAccessibility
{
    CompactGuideLocalization *l = self.localization;
    self.modeField.accessibilityLabel = [l stringForKey:@"guide.access.mode.label"];
    self.instructionField.accessibilityLabel =
        [l stringForKey:@"guide.access.instruction.label"];
    self.progressField.accessibilityLabel =
        [l stringForKey:@"guide.access.progress.label"];
    self.calibrationField.accessibilityLabel =
        [l stringForKey:@"guide.access.calibration.label"];
    self.calibrationField.accessibilityHelp =
        [l stringForKey:@"guide.access.calibration.help"];
    self.confirmationField.accessibilityLabel =
        [l stringForKey:@"guide.access.confirmation.label"];
    self.confirmationField.accessibilityHelp =
        [l stringForKey:@"guide.access.confirmation.help"];
    self.detailsButton.accessibilityHelp =
        [l stringForKey:@"guide.access.details.help"];
    self.cancelButton.accessibilityHelp =
        [l stringForKey:@"guide.access.cancel.help"];
    self.confirmButton.accessibilityHelp =
        [l stringForKey:@"guide.access.confirm.help"];
    self.saveButton.accessibilityHelp =
        [l stringForKey:@"guide.access.save.help"];
}

- (void)installObserversForViewerWindow:(NSWindow *)viewerWindow
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    __weak typeof(self) weakSelf = self;
    [self.observers addObject:[center
        addObserverForName:CompactGuideViewStateDidChangeNotification
        object:self.guideState queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf updateFieldsAndLayout:YES];
        }]];
    [self.observers addObject:[center
        addObserverForName:GuideEngineDidChangeNotification
        object:self.guideEngine queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf updateFieldsAndLayout:NO];
        }]];
    for (NSNotificationName name in @[NSWindowDidMoveNotification,
                                      NSWindowDidResizeNotification,
                                      NSWindowDidChangeScreenNotification]) {
        [self.observers addObject:[center addObserverForName:name object:viewerWindow
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf updateFieldsAndLayout:NO];
                [weakSelf followViewerWindow];
            }]];
    }
    [self.observers addObject:[center
        addObserverForName:NSWindowDidBecomeKeyNotification object:viewerWindow
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            (void)notification;
            typeof(self) self = weakSelf;
            if (self != nil && self.bound && !self.userClosed) {
                [self followViewerWindow];
                [self.panel orderFront:nil];
            }
        }]];
    [self.observers addObject:[center
        addObserverForName:NSWindowDidResignKeyNotification object:viewerWindow
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf.panel orderOut:nil];
        }]];
    [self.observers addObject:[center
        addObserverForName:NSWindowWillCloseNotification object:viewerWindow
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf invalidate];
        }]];
}

- (void)installModelObserver
{
    if (self.modelObserver != nil || self.model == nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.modelObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:LineOverlayModelDidChangeNotification object:self.model
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            (void)notification;
            [weakSelf modelDidChange];
        }];
}

- (void)removeModelObserver
{
    if (self.modelObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.modelObserver];
        self.modelObserver = nil;
    }
}

- (void)modelDidChange
{
    LineOverlayModel *model = self.model;
    if (model == nil) {
        return;
    }
    BOOL editing = model.inputState == LineOverlayInputStateEditingEndpointA ||
        model.inputState == LineOverlayInputStateEditingEndpointB;
    BOOL wasEditing = self.previousInputState == LineOverlayInputStateEditingEndpointA ||
        self.previousInputState == LineOverlayInputStateEditingEndpointB;
    if (editing && !wasEditing) {
        self.editOriginA = model.pointA;
        self.editOriginB = model.pointB;
        [self.guideState beginEditing];
    } else if (!editing && wasEditing) {
        BOOL changed = !NSEqualPoints(self.editOriginA, model.pointA) ||
            !NSEqualPoints(self.editOriginB, model.pointB);
        [self.guideState finishEditingChanged:changed];
    }
    self.previousInputState = model.inputState;
    [self syncReviewSnapshotFromModel];
    [self updateFieldsAndLayout:NO];
}

- (void)syncReviewSnapshotFromModel
{
    LineOverlayModel *model = self.model;
    if (model == nil) {
        return;
    }
    [self.guideState updateMeasurementSnapshotWithPointA:model.pointA
        pointB:model.pointB rawResult:model.pixelDistance
        calculationMethodVersion:MedisaleDistanceCalculationMethodVersion];
}

- (NSString *)progressTextForState:(CompactGuideMeasurementState)state
{
    CompactGuideLocalization *l = self.localization;
    NSString *key = [CompactGuidePresentation
        progressKeyForMeasurementState:state];
    if (state == CompactGuideMeasurementStateCollecting) {
        return [NSString stringWithFormat:
            [l stringForKey:key],
            (unsigned long)self.guideState.collectedPointCount];
    }
    return [l stringForKey:key];
}

- (void)updateFieldsAndLayout:(BOOL)announceStateChange
{
    if (self.panel == nil) {
        return;
    }
    CompactGuideLocalization *l = self.localization;
    CompactGuideViewState *state = self.guideState;
    self.modeField.stringValue = [l stringForKey:@"guide.mode"];
    NSString *instructionKey = [CompactGuidePresentation
        instructionKeyForMeasurementState:state.measurementState
        pointCount:state.collectedPointCount];
    self.instructionField.stringValue = [l stringForKey:instructionKey];
    self.progressField.stringValue = [self progressTextForState:state.measurementState];

    NSString *calibrationKey = [CompactGuidePresentation
        compactCalibrationValueKeyForState:state.calibrationState];
    NSString *calibrationIconName = NSImageNameStatusUnavailable;
    if (state.calibrationState == CompactGuideCalibrationStateCalibrated) {
        calibrationIconName = NSImageNameStatusAvailable;
    } else if (state.calibrationState == CompactGuideCalibrationStateDICOMSpacingOnly) {
        calibrationIconName = NSImageNameStatusPartiallyAvailable;
    }
    self.calibrationIcon.image = [NSImage imageNamed:calibrationIconName];
    self.calibrationField.stringValue = [NSString stringWithFormat:@"%@: %@",
        [l stringForKey:@"guide.calibration.compact.label"],
        [l stringForKey:calibrationKey]];

    NSString *confirmationKey = [CompactGuidePresentation
        compactConfirmationValueKeyForState:state.confirmationState];
    NSString *confirmationIconName = NSImageNameStatusPartiallyAvailable;
    if (state.confirmationState == CompactGuideConfirmationStateUserConfirmed) {
        confirmationIconName = NSImageNameStatusAvailable;
    } else if (state.confirmationState ==
               CompactGuideConfirmationStateModifiedAfterConfirmation) {
        confirmationIconName = NSImageNameStatusPartiallyAvailable;
    } else if (state.confirmationState == CompactGuideConfirmationStateInvalidated) {
        confirmationIconName = NSImageNameStatusUnavailable;
    }
    self.confirmationIcon.image = [NSImage imageNamed:confirmationIconName];
    self.confirmationField.stringValue = [NSString stringWithFormat:@"%@: %@",
        [l stringForKey:@"guide.confirmation.compact.label"],
        [l stringForKey:confirmationKey]];

    switch ([CompactGuidePresentation
        semanticRoleForMeasurementState:state.measurementState]) {
        case CompactGuideSemanticRoleActive:
            self.progressField.textColor = NSColor.systemBlueColor;
            break;
        case CompactGuideSemanticRoleAttention:
            self.progressField.textColor = NSColor.systemOrangeColor;
            break;
        case CompactGuideSemanticRoleConfirmed:
            self.progressField.textColor = NSColor.systemGreenColor;
            break;
        case CompactGuideSemanticRoleUnavailable:
            self.progressField.textColor = NSColor.systemRedColor;
            break;
        case CompactGuideSemanticRoleNeutral:
        default:
            self.progressField.textColor = NSColor.secondaryLabelColor;
            break;
    }

    self.detailsButton.title = [l stringForKey:state.isExpanded
        ? @"guide.button.hideDetails" : @"guide.button.details"];
    self.cancelButton.title = [l stringForKey:@"guide.button.cancel"];
    self.confirmButton.title = [l stringForKey:@"guide.button.confirm"];
    self.cancelButton.hidden = !state.canCancel;
    self.confirmButton.hidden = !state.canConfirm;
    self.detailsScrollView.hidden = !state.isExpanded;
    self.saveButton.hidden = !state.isExpanded || self.model == nil ||
        self.persistenceStore == nil;
    self.saveStatusField.hidden = self.saveButton.hidden;

    if (self.model == nil) {
        self.detailsField.stringValue = [NSString stringWithFormat:@"%@\n\n%@",
            [l stringForKey:@"guide.details.body"],
            [l stringForKey:@"guide.details.collecting"]];
    } else {
        NSString *coordinates = [NSString stringWithFormat:
            [l stringForKey:@"guide.details.coordinates.format"],
            self.model.pointA.x, self.model.pointA.y,
            self.model.pointB.x, self.model.pointB.y,
            self.model.pixelDistance];
        CalibrationProvenanceModel *calibration = state.calibrationModel;
        NSString *spacingDetails = nil;
        if (calibration.hasUsableSpacing) {
            NSString *row = [MeasurementValueFormatter
                displayStringForRawValue:calibration.rowSpacing precision:4
                locale:NSLocale.currentLocale];
            NSString *column = [MeasurementValueFormatter
                displayStringForRawValue:calibration.columnSpacing precision:4
                locale:NSLocale.currentLocale];
            spacingDetails = [NSString stringWithFormat:
                [l stringForKey:@"guide.details.spacing.format"], row, column];
        } else {
            spacingDetails = [l stringForKey:@"guide.details.spacing.unavailable"];
        }
        self.detailsField.stringValue = [NSString stringWithFormat:@"%@\n\n%@\n%@",
            [l stringForKey:@"guide.details.body"], coordinates, spacingDetails];
        self.saveButton.enabled =
            self.model.inputState == LineOverlayInputStateComplete &&
            state.canPersistMeasurement;
        if (self.hasSaved) {
            BOOL unchanged = NSEqualPoints(self.model.pointA, self.savedPointA) &&
                NSEqualPoints(self.model.pointB, self.savedPointB);
            self.saveStatusField.stringValue = [l stringForKey:unchanged
                ? (self.restoredMeasurement ? @"guide.save.restored" : @"guide.save.ok")
                : @"guide.save.changed"];
        } else if (self.saveStatusField.stringValue.length == 0) {
            self.saveStatusField.stringValue = [l stringForKey:@"guide.save.notSaved"];
        }
    }
    [self updatePanelLayout];
    if (announceStateChange && self.lastAnnouncedState != state.measurementState) {
        self.lastAnnouncedState = state.measurementState;
        NSAccessibilityPostNotification(self.progressField,
                                        NSAccessibilityValueChangedNotification);
    }
}

- (void)updatePanelLayout
{
    NSWindow *viewerWindow = self.viewer.window;
    NSSize viewerSize = viewerWindow == nil ? NSMakeSize(640, 480)
                                             : viewerWindow.contentLayoutRect.size;
    NSSize contentSize = self.guideState.isExpanded
        ? [CompactGuideLayoutPolicy expandedContentSizeForViewerContentSize:viewerSize]
        : [CompactGuideLayoutPolicy compactContentSizeForViewerContentSize:viewerSize];
    [self.panel setContentSize:contentSize];
    NSView *content = self.panel.contentView;
    CGFloat width = content.bounds.size.width;
    CGFloat height = content.bounds.size.height;
    CGFloat inset = 8.0;
    CGFloat coreBottom = MAX(0.0, height - 124.0);
    CGFloat usable = width - inset * 2.0;
    self.modeField.frame = NSMakeRect(inset, coreBottom + 101.0, usable, 16.0);
    self.instructionField.frame = NSMakeRect(inset, coreBottom + 70.0, usable, 29.0);
    self.progressField.frame = NSMakeRect(inset, coreBottom + 52.0, usable, 16.0);
    CGFloat statusWidth = floor((usable - 6.0) * 0.5);
    self.calibrationIcon.frame = NSMakeRect(inset, coreBottom + 33.0, 14.0, 14.0);
    self.calibrationField.frame = NSMakeRect(inset + 16.0, coreBottom + 31.0,
                                             statusWidth - 16.0, 18.0);
    CGFloat confirmationX = inset + statusWidth + 6.0;
    self.confirmationIcon.frame = NSMakeRect(confirmationX, coreBottom + 33.0,
                                             14.0, 14.0);
    self.confirmationField.frame = NSMakeRect(confirmationX + 16.0,
                                              coreBottom + 31.0,
                                              statusWidth - 16.0, 18.0);
    self.detailsButton.frame = NSMakeRect(inset, coreBottom + 3.0, 78.0, 24.0);
    self.cancelButton.frame = NSMakeRect(MAX(inset + 80.0, width - 162.0),
                                         coreBottom + 3.0, 76.0, 24.0);
    self.confirmButton.frame = NSMakeRect(width - inset - 78.0,
                                          coreBottom + 3.0, 78.0, 24.0);

    CGFloat detailsHeight = MAX(0.0, coreBottom - 42.0);
    self.detailsScrollView.frame = NSMakeRect(inset, 36.0, usable, detailsHeight);
    NSView *documentView = self.detailsScrollView.documentView;
    CGFloat documentWidth = MAX(120.0, usable - 14.0);
    CGFloat textHeight = MAX(detailsHeight,
        [self.detailsField sizeThatFits:NSMakeSize(documentWidth, CGFLOAT_MAX)].height + 8.0);
    documentView.frame = NSMakeRect(0, 0, documentWidth, textHeight);
    self.detailsField.frame = NSMakeRect(0, 4.0, documentWidth, textHeight - 4.0);
    self.saveButton.frame = NSMakeRect(inset, 7.0, 126.0, 24.0);
    self.saveStatusField.frame = NSMakeRect(inset + 132.0, 8.0,
                                            MAX(0.0, usable - 132.0), 20.0);
}

- (void)toggleDetails:(id)sender
{
    (void)sender;
    [self.guideState setExpanded:!self.guideState.isExpanded];
    [self followViewerWindow];
}

- (void)cancelPressed:(id)sender
{
    (void)sender;
    CompactGuideViewState *state = self.guideState;
    MedisalePanelHostCancellation cancellation = self.cancellation;
    if (cancellation != nil) {
        cancellation();
    }
    [state cancelCurrentOperation];
    if (state.measurementState == CompactGuideMeasurementStateCancelled) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [state settleCancellationToIdle];
        });
    }
}

- (void)confirmPressed:(id)sender
{
    (void)sender;
    [self syncReviewSnapshotFromModel];
    if (![self.guideState confirm]) {
        NSBeep();
    }
}

- (void)saveMeasurement:(id)sender
{
    (void)sender;
    LineOverlayModel *model = self.model;
    id<MeasurementPersistenceStore> store = self.persistenceStore;
    CompactGuideLocalization *l = self.localization;
    if (model == nil || store == nil ||
        model.inputState != LineOverlayInputStateComplete ||
        !self.guideState.canPersistMeasurement) {
        self.saveStatusField.stringValue = [l stringForKey:@"guide.save.unavailable"];
        NSBeep();
        return;
    }
    MeasurementRecord *record = [[MeasurementRecord alloc]
        initWithMeasurementID:self.measurementID imageContext:model.imageIdentity
                    endpointAX:model.pointA.x endpointAY:model.pointA.y
                    endpointBX:model.pointB.x endpointBY:model.pointB.y
                  pixelDistance:model.pixelDistance
                  schemaVersion:MedisaleMeasurementSchemaVersion
                      createdAt:self.createdAt updatedAt:[NSDate date]];
    NSError *error = nil;
    if (![store saveMeasurement:record error:&error]) {
        (void)error;
        self.saveStatusField.stringValue = [l stringForKey:@"guide.save.failed"];
        NSBeep();
        return;
    }
    self.hasSaved = YES;
    self.restoredMeasurement = NO;
    self.savedPointA = model.pointA;
    self.savedPointB = model.pointB;
    self.saveStatusField.stringValue = [l stringForKey:@"guide.save.ok"];
}

- (void)followViewerWindow
{
    NSWindow *viewerWindow = self.viewer.window;
    NSPanel *panel = self.panel;
    if (viewerWindow == nil || panel == nil) {
        return;
    }
    NSScreen *screen = viewerWindow.screen ?: NSScreen.mainScreen;
    NSRect contentFrame = [viewerWindow convertRectToScreen:viewerWindow.contentLayoutRect];
    CompactGuidePlacement placement = CompactGuidePlacementRight;
    NSPoint origin = [CompactGuideLayoutPolicy originForViewerFrame:viewerWindow.frame
        viewerContentFrame:contentFrame screenVisibleFrame:screen.visibleFrame
        panelSize:panel.frame.size placement:&placement];
    (void)placement;
    [panel setFrameOrigin:origin];
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (notification.object == self.panel && self.bound) {
        self.userClosed = YES;
    }
}

- (void)invalidate
{
    if (!self.bound && self.panel == nil && self.observers.count == 0 &&
        self.model == nil && self.viewer == nil) {
        return;
    }
    self.bound = NO;
    [self removeModelObserver];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (id observer in self.observers) {
        [center removeObserver:observer];
    }
    [self.observers removeAllObjects];
    self.panel.delegate = nil;
    [self.panel close];
    self.panel = nil;
    self.model = nil;
    self.guideState = nil;
    self.guideEngine = nil;
    self.localization = nil;
    self.persistenceStore = nil;
    self.measurementID = nil;
    self.createdAt = nil;
    self.cancellation = nil;
    self.viewer = nil;

    MedisalePanelHostInvalidation invalidation = self.invalidation;
    self.invalidation = nil;
    if (invalidation != nil) {
        invalidation();
    }
}

- (void)dealloc
{
    [self invalidate];
}

@end
