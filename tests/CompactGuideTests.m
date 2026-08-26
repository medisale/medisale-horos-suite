#import <Cocoa/Cocoa.h>

#import "CompactGuideLayoutPolicy.h"
#import "CompactGuideLocalization.h"
#import "CompactGuidePresentation.h"
#import "CompactGuideViewState.h"
#import "ImageContext.h"

static NSUInteger assertionCount = 0;

static void Assert(BOOL condition, NSString *message)
{
    assertionCount++;
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static ImageContext *Context(NSString *study, NSString *series,
                             NSString *instance, NSInteger frame)
{
    return [[ImageContext alloc] initWithStudyInstanceUID:study
        seriesInstanceUID:series sopInstanceUID:instance frameNumber:frame
        pixelWidth:640 pixelHeight:480 pixelSpacingX:0.2 pixelSpacingY:0.3];
}

static void TestStateMachine(void)
{
    ImageContext *identity = Context(@"study-a", @"series-a", @"instance-a", 0);
    CalibrationProvenanceModel *dicom =
        [CalibrationProvenanceModel modelFromImageContext:identity];
    CompactGuideViewState *state = [[CompactGuideViewState alloc]
        initWithImageIdentity:identity
        calibrationModel:dicom];
    Assert(state.measurementState == CompactGuideMeasurementStateIdle, @"initial idle");
    Assert(state.confirmationState == CompactGuideConfirmationStateNotReviewed,
           @"initial not reviewed");
    Assert(state.calibrationState == CompactGuideCalibrationStateDICOMSpacingOnly,
           @"initial calibration");
    Assert(!state.isExpanded, @"compact by default");
    Assert(!state.canCancel, @"idle cannot cancel");
    Assert(!state.canConfirm, @"idle cannot confirm");
    Assert([state startCollecting], @"idle to collecting");
    Assert(state.canCancel, @"collecting can cancel");
    Assert(!state.canConfirm, @"collecting cannot confirm");
    Assert(![state startCollecting], @"cannot restart while collecting");
    Assert([state updateCollectedPointCount:1], @"collect first point");
    Assert(state.collectedPointCount == 1, @"one point recorded");
    Assert(![state updateCollectedPointCount:3], @"reject excess points");
    Assert([state updateCollectedPointCount:2], @"collect second point");
    [state updateMeasurementSnapshotWithPointA:NSMakePoint(1, 2)
        pointB:NSMakePoint(4, 6) rawResult:5.0
        calculationMethodVersion:MedisaleDistanceCalculationMethodVersion];
    Assert(state.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed,
           @"two points calculate result");
    Assert(state.canCancel, @"unconfirmed calculation can cancel");
    Assert(state.canConfirm, @"unconfirmed calculation can confirm");
    Assert([state confirm], @"confirm review");
    Assert(state.measurementState == CompactGuideMeasurementStateConfirmed,
           @"confirmed state");
    Assert(state.confirmationState == CompactGuideConfirmationStateUserConfirmed,
           @"confirmed marker");
    Assert(!state.canConfirm, @"cannot reconfirm unchanged result");
    Assert([state beginEditing], @"begin editing confirmed result");
    Assert(state.measurementState == CompactGuideMeasurementStateEditing,
           @"editing state");
    [state updateMeasurementSnapshotWithPointA:NSMakePoint(2, 2)
        pointB:NSMakePoint(4, 6) rawResult:sqrt(20.0)
        calculationMethodVersion:MedisaleDistanceCalculationMethodVersion];
    Assert([state finishEditingChanged:YES], @"finish changed edit");
    Assert(state.measurementState == CompactGuideMeasurementStateModifiedAfterConfirmation,
           @"modified state");
    Assert(state.confirmationState ==
           CompactGuideConfirmationStateModifiedAfterConfirmation,
           @"modified confirmation marker");
    Assert(state.canConfirm, @"modified result can be reviewed again");
    Assert([state confirm], @"confirm modified result");
    Assert([state beginEditing], @"begin no-change edit");
    [state updateMeasurementSnapshotWithPointA:NSMakePoint(2, 2)
        pointB:NSMakePoint(4, 6) rawResult:sqrt(20.0)
        calculationMethodVersion:MedisaleDistanceCalculationMethodVersion];
    Assert([state finishEditingChanged:NO], @"finish no-change edit");
    Assert(state.measurementState == CompactGuideMeasurementStateConfirmed,
           @"no-change edit preserves confirmation");
    [state updateMeasurementSnapshotWithPointA:NSMakePoint(3, 2)
        pointB:NSMakePoint(4, 6) rawResult:sqrt(17.0)
        calculationMethodVersion:MedisaleDistanceCalculationMethodVersion];
    Assert(state.measurementState == CompactGuideMeasurementStateModifiedAfterConfirmation,
           @"actual endpoint/result change requires renewed confirmation");
    [state setExpanded:YES];
    Assert(state.isExpanded, @"expanded per-view state");
    Assert(state.confirmationState ==
           CompactGuideConfirmationStateModifiedAfterConfirmation,
           @"expand does not change confirmation state");
    [state setExpanded:NO];
    Assert(!state.isExpanded, @"collapse per-view state");
    [state updateCalibrationModel:
        [CalibrationProvenanceModel
            unknownModelWithWarnings:@[@"spacing-provenance-unknown"]]];
    Assert(state.calibrationState == CompactGuideCalibrationStateUnknown,
           @"calibration status updates");

    CompactGuideViewState *cancel = [[CompactGuideViewState alloc]
        initWithImageIdentity:identity calibrationModel:
            [CalibrationProvenanceModel
                unknownModelWithWarnings:@[@"spacing-provenance-unknown"]]];
    Assert([cancel startCollecting], @"cancel fixture collecting");
    Assert([cancel updateCollectedPointCount:1], @"cancel fixture point");
    Assert([cancel cancelCurrentOperation], @"cancel collecting");
    Assert(cancel.measurementState == CompactGuideMeasurementStateCancelled,
           @"cancelled state visible");
    Assert(cancel.collectedPointCount == 0, @"cancel clears partial points");
    Assert([cancel settleCancellationToIdle], @"cancel settles to idle");
    Assert(cancel.measurementState == CompactGuideMeasurementStateIdle,
           @"settled idle");
    Assert([cancel markUnavailable], @"mark unavailable");
    Assert(cancel.measurementState == CompactGuideMeasurementStateUnavailable,
           @"unavailable state");
    Assert(cancel.confirmationState == CompactGuideConfirmationStateInvalidated &&
           !cancel.canCancel && !cancel.canConfirm,
           @"unavailable invalidates confirmation and has no actions");
    Assert([cancel resetToIdle], @"unavailable resets");

    CompactGuideViewState *discard = [[CompactGuideViewState alloc]
        initWithImageIdentity:identity calibrationModel:
            [CalibrationProvenanceModel
                unknownModelWithWarnings:@[@"spacing-provenance-unknown"]]];
    Assert([discard markCalculated], @"prepare unconfirmed calculation");
    Assert([discard cancelCurrentOperation], @"discard unconfirmed operation");
    Assert(discard.measurementState == CompactGuideMeasurementStateIdle,
           @"unconfirmed cancel returns to prior idle state");
    Assert(discard.confirmationState == CompactGuideConfirmationStateNotReviewed,
           @"unconfirmed cancel does not confirm");

    Assert([state matchesImageContext:identity], @"exact identity matches");
    Assert(![state matchesImageContext:Context(@"study-b", @"series-a",
                                               @"instance-a", 0)],
           @"study mismatch rejected");
    Assert(![state matchesImageContext:Context(@"study-a", @"series-b",
                                               @"instance-a", 0)],
           @"series mismatch rejected");
    Assert(![state matchesImageContext:Context(@"study-a", @"series-a",
                                               @"instance-b", 0)],
           @"SOP mismatch rejected");
    Assert(![state matchesImageContext:Context(@"study-a", @"series-a",
                                               @"instance-a", 1)],
           @"frame mismatch rejected");
    Assert(![state matchesImageContext:nil], @"nil identity rejected");
}

static void TestLocalization(void)
{
    CompactGuideLocalization *localization = [[CompactGuideLocalization alloc]
        initWithPrimaryStrings:@{@"primary": @"日本語", @"empty": @""}
        fallbackStrings:@{@"primary": @"English", @"fallback": @"Fallback",
                          @"empty": @"Nonempty"}];
    Assert([[localization stringForKey:@"primary"] isEqualToString:@"日本語"],
           @"primary localization wins");
    Assert([[localization stringForKey:@"fallback"] isEqualToString:@"Fallback"],
           @"English fallback used");
    Assert([[localization stringForKey:@"empty"] isEqualToString:@"Nonempty"],
           @"empty primary falls back");
    Assert([[localization stringForKey:@"missing"] isEqualToString:@"missing"],
           @"missing key is deterministic");

    NSDictionary<NSString *, NSString *> *english =
        [NSDictionary dictionaryWithContentsOfFile:
            @"plugin/Resources/en.lproj/Localizable.strings"];
    NSDictionary<NSString *, NSString *> *japanese =
        [NSDictionary dictionaryWithContentsOfFile:
            @"plugin/Resources/ja.lproj/Localizable.strings"];
    Assert(english.count >= 40, @"English fallback resource is complete");
    Assert(japanese.count == english.count,
           @"Japanese and English resources have the same key count");
    Assert([[NSSet setWithArray:english.allKeys]
        isEqualToSet:[NSSet setWithArray:japanese.allKeys]],
        @"Japanese and English resources have exactly the same key set");
    for (NSString *key in english) {
        Assert([english[key] length] > 0, @"English value is nonempty");
        Assert([japanese[key] length] > 0, @"Japanese value is nonempty");
    }
    Assert([english[@"guide.calibration.dicom"]
        containsString:@"DICOM/Viewer"],
        @"English full calibration copy names DICOM/Viewer spacing");
    Assert([english[@"guide.calibration.dicom"]
        containsString:@"uncalibrated"],
        @"English full calibration copy says uncalibrated");
    Assert([japanese[@"guide.calibration.dicom"]
        containsString:@"DICOM/Viewer"],
        @"Japanese full calibration copy names DICOM/Viewer spacing");
    Assert([japanese[@"guide.calibration.dicom"] containsString:@"未校正"],
        @"Japanese full calibration copy says uncalibrated");
    Assert([english[@"guide.calibration.compact.dicom"]
        containsString:@"Uncalibrated"],
        @"English compact calibration copy remains explicit");
    Assert([japanese[@"guide.calibration.compact.dicom"] containsString:@"未校正"],
        @"Japanese compact calibration copy remains explicit");
}

static void TestPresentation(void)
{
    NSArray<NSNumber *> *states = @[
        @(CompactGuideMeasurementStateIdle),
        @(CompactGuideMeasurementStateCollecting),
        @(CompactGuideMeasurementStateEditing),
        @(CompactGuideMeasurementStateCalculatedUnconfirmed),
        @(CompactGuideMeasurementStateConfirmed),
        @(CompactGuideMeasurementStateModifiedAfterConfirmation),
        @(CompactGuideMeasurementStateCancelled),
        @(CompactGuideMeasurementStateUnavailable),
    ];
    for (NSNumber *value in states) {
        CompactGuideMeasurementState state = value.integerValue;
        Assert([CompactGuidePresentation
            instructionKeyForMeasurementState:state pointCount:0].length > 0,
            @"every state has an instruction");
        Assert([CompactGuidePresentation
            progressKeyForMeasurementState:state].length > 0,
            @"every state has progress text");
    }
    Assert(![[CompactGuidePresentation
        instructionKeyForMeasurementState:CompactGuideMeasurementStateCollecting
        pointCount:0] isEqualToString:[CompactGuidePresentation
        instructionKeyForMeasurementState:CompactGuideMeasurementStateCollecting
        pointCount:1]], @"collecting instructions advance");
    Assert([CompactGuidePresentation semanticRoleForMeasurementState:
        CompactGuideMeasurementStateCollecting] == CompactGuideSemanticRoleActive,
        @"collecting semantic role");
    Assert([CompactGuidePresentation semanticRoleForMeasurementState:
        CompactGuideMeasurementStateCalculatedUnconfirmed] ==
        CompactGuideSemanticRoleAttention, @"calculated attention role");
    Assert([CompactGuidePresentation semanticRoleForMeasurementState:
        CompactGuideMeasurementStateModifiedAfterConfirmation] ==
        CompactGuideSemanticRoleAttention, @"modified attention role");
    Assert([CompactGuidePresentation semanticRoleForMeasurementState:
        CompactGuideMeasurementStateConfirmed] == CompactGuideSemanticRoleConfirmed,
        @"confirmed semantic role");
    Assert([CompactGuidePresentation semanticRoleForMeasurementState:
        CompactGuideMeasurementStateUnavailable] == CompactGuideSemanticRoleUnavailable,
        @"unavailable semantic role");
    for (NSInteger value = CompactGuideCalibrationStateCalibrated;
         value <= CompactGuideCalibrationStateUnknown; value++) {
        Assert([CompactGuidePresentation calibrationValueKeyForState:value].length > 0,
               @"every calibration state has text");
        Assert([CompactGuidePresentation compactCalibrationValueKeyForState:value].length > 0,
               @"every calibration state has compact text");
    }
    for (NSInteger value = CompactGuideConfirmationStateNotReviewed;
         value <= CompactGuideConfirmationStateInvalidated; value++) {
        Assert([CompactGuidePresentation confirmationValueKeyForState:value].length > 0,
               @"every confirmation state has text");
        Assert([CompactGuidePresentation compactConfirmationValueKeyForState:value].length > 0,
               @"every confirmation state has compact text");
    }
    Assert([[CompactGuidePresentation confirmationValueKeyForState:
        CompactGuideConfirmationStateInvalidated]
        isEqualToString:@"guide.confirmation.invalidated"],
        @"invalidated confirmation has a dedicated presentation key");
    Assert([[CompactGuidePresentation compactConfirmationValueKeyForState:
        CompactGuideConfirmationStateInvalidated]
        isEqualToString:@"guide.confirmation.compact.invalidated"],
        @"invalidated compact presentation does not fall back to pending");
}

static void TestLayoutPolicy(void)
{
    Assert([CompactGuideLayoutPolicy layoutModeForViewerContentSize:NSMakeSize(640, 480)] ==
           CompactGuideLayoutModeStandard, @"threshold is standard");
    Assert([CompactGuideLayoutPolicy layoutModeForViewerContentSize:NSMakeSize(639, 480)] ==
           CompactGuideLayoutModeNarrow, @"narrow width adapts");
    Assert([CompactGuideLayoutPolicy layoutModeForViewerContentSize:NSMakeSize(640, 479)] ==
           CompactGuideLayoutModeNarrow, @"narrow height adapts");
    NSSize standard = [CompactGuideLayoutPolicy
        compactContentSizeForViewerContentSize:NSMakeSize(1200, 900)];
    Assert(NSEqualSizes(standard, NSMakeSize(248, 124)), @"standard compact baseline");
    NSSize narrow = [CompactGuideLayoutPolicy
        compactContentSizeForViewerContentSize:NSMakeSize(400, 300)];
    Assert(narrow.width >= 180 && narrow.width <= 220, @"narrow width bounds");
    Assert(narrow.height >= 140 && narrow.height <= 180, @"narrow height bounds");
    NSSize expanded = [CompactGuideLayoutPolicy
        expandedContentSizeForViewerContentSize:NSMakeSize(1200, 900)];
    Assert(expanded.width >= standard.width && expanded.width <= 280,
           @"expanded width bound");
    Assert(expanded.height > standard.height && expanded.height <= 360,
           @"expanded height bound");

    CompactGuidePlacement placement = -1;
    NSPoint origin = [CompactGuideLayoutPolicy
        originForViewerFrame:NSMakeRect(100, 100, 500, 500)
        viewerContentFrame:NSMakeRect(110, 110, 480, 460)
        screenVisibleFrame:NSMakeRect(0, 0, 1200, 900)
        panelSize:NSMakeSize(248, 124) placement:&placement];
    Assert(placement == CompactGuidePlacementRight, @"right placement preferred");

    origin = [CompactGuideLayoutPolicy
        originForViewerFrame:NSMakeRect(650, 100, 500, 500)
        viewerContentFrame:NSMakeRect(660, 110, 480, 460)
        screenVisibleFrame:NSMakeRect(0, 0, 1200, 900)
        panelSize:NSMakeSize(248, 124) placement:&placement];
    Assert(placement == CompactGuidePlacementLeft, @"left placement fallback");

    origin = [CompactGuideLayoutPolicy
        originForViewerFrame:NSMakeRect(40, 40, 720, 600)
        viewerContentFrame:NSMakeRect(50, 50, 700, 560)
        screenVisibleFrame:NSMakeRect(0, 0, 800, 700)
        panelSize:NSMakeSize(248, 124) placement:&placement];
    Assert(placement == CompactGuidePlacementTopRightFloating,
           @"top-right content fallback");
    Assert(origin.x >= 0 && origin.x + 248 <= 800, @"fallback horizontally visible");
    Assert(origin.y >= 0 && origin.y + 124 <= 700, @"fallback vertically visible");
}

int main(void)
{
    @autoreleasepool {
        TestStateMachine();
        TestLocalization();
        TestPresentation();
        TestLayoutPolicy();
        NSLog(@"PASS: Compact Guide state/localization/layout (%lu assertions)",
              (unsigned long)assertionCount);
    }
    return 0;
}
