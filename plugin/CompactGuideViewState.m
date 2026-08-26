#import "CompactGuideViewState.h"

#import "ImageContext.h"

NSNotificationName const CompactGuideViewStateDidChangeNotification =
    @"MedisaleCompactGuideViewStateDidChangeNotification";

@interface CompactGuideViewState ()
@property(nonatomic, readwrite) CompactGuideMeasurementState measurementState;
@property(nonatomic, copy, readwrite) CalibrationProvenanceModel *calibrationModel;
@property(nonatomic, strong, readwrite) ConfirmationStateModel *confirmationModel;
@property(nonatomic, readwrite) NSUInteger collectedPointCount;
@property(nonatomic, readwrite, getter=isExpanded) BOOL expanded;
@property(nonatomic) CompactGuideMeasurementState stateBeforeEditing;
@property(nonatomic) CompactGuideMeasurementState stateBeforeCollecting;
@end

@implementation CompactGuideViewState

- (instancetype)initWithImageIdentity:(ImageContext *)imageIdentity
                      calibrationModel:(CalibrationProvenanceModel *)calibrationModel
{
    self = [super init];
    if (self) {
        _imageIdentity = [imageIdentity copy];
        _measurementState = CompactGuideMeasurementStateIdle;
        _calibrationModel = [calibrationModel copy];
        _confirmationModel = [[ConfirmationStateModel alloc] init];
        _stateBeforeEditing = CompactGuideMeasurementStateIdle;
        _stateBeforeCollecting = CompactGuideMeasurementStateIdle;
    }
    return self;
}

- (CompactGuideCalibrationState)calibrationState
{
    return self.calibrationModel.state;
}

- (CompactGuideConfirmationState)confirmationState
{
    return self.confirmationModel.state;
}

- (BOOL)canCancel
{
    return self.measurementState == CompactGuideMeasurementStateCollecting ||
        self.measurementState == CompactGuideMeasurementStateEditing ||
        self.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed;
}

- (BOOL)canConfirm
{
    BOOL stateAllows =
        self.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed ||
        self.measurementState == CompactGuideMeasurementStateModifiedAfterConfirmation;
    return stateAllows && self.confirmationModel.currentSnapshot.isStructurallyValid &&
        self.confirmationState != CompactGuideConfirmationStateInvalidated;
}

- (BOOL)startCollecting
{
    if (self.measurementState != CompactGuideMeasurementStateIdle &&
        self.measurementState != CompactGuideMeasurementStateCancelled) {
        return NO;
    }
    self.stateBeforeCollecting = self.measurementState ==
        CompactGuideMeasurementStateCancelled
            ? CompactGuideMeasurementStateIdle : self.measurementState;
    self.measurementState = CompactGuideMeasurementStateCollecting;
    [self.confirmationModel reset];
    self.collectedPointCount = 0;
    [self notifyChange];
    return YES;
}

- (BOOL)updateCollectedPointCount:(NSUInteger)pointCount
{
    if (self.measurementState != CompactGuideMeasurementStateCollecting || pointCount > 2) {
        return NO;
    }
    self.collectedPointCount = pointCount;
    if (pointCount == 2) {
        self.measurementState = CompactGuideMeasurementStateCalculatedUnconfirmed;
    }
    [self notifyChange];
    return YES;
}

- (BOOL)markCalculated
{
    if (self.measurementState != CompactGuideMeasurementStateCollecting &&
        self.measurementState != CompactGuideMeasurementStateIdle &&
        self.measurementState != CompactGuideMeasurementStateCancelled) {
        return NO;
    }
    if (self.measurementState != CompactGuideMeasurementStateCollecting) {
        self.stateBeforeCollecting = CompactGuideMeasurementStateIdle;
    }
    self.collectedPointCount = 2;
    self.measurementState = CompactGuideMeasurementStateCalculatedUnconfirmed;
    [self notifyChange];
    return YES;
}

- (BOOL)beginEditing
{
    if (self.measurementState != CompactGuideMeasurementStateCalculatedUnconfirmed &&
        self.measurementState != CompactGuideMeasurementStateConfirmed &&
        self.measurementState != CompactGuideMeasurementStateModifiedAfterConfirmation) {
        return NO;
    }
    self.stateBeforeEditing = self.measurementState;
    self.measurementState = CompactGuideMeasurementStateEditing;
    [self notifyChange];
    return YES;
}

- (BOOL)finishEditingChanged:(BOOL)changed
{
    if (self.measurementState != CompactGuideMeasurementStateEditing) {
        return NO;
    }
    if (!changed) {
        self.measurementState = self.stateBeforeEditing;
    } else if (self.confirmationState ==
               CompactGuideConfirmationStateModifiedAfterConfirmation) {
        self.measurementState = CompactGuideMeasurementStateModifiedAfterConfirmation;
    } else if (self.confirmationState == CompactGuideConfirmationStateInvalidated) {
        self.measurementState = CompactGuideMeasurementStateCalculatedUnconfirmed;
    } else {
        self.measurementState = self.stateBeforeEditing;
    }
    [self notifyChange];
    return YES;
}

- (BOOL)confirm
{
    if (!self.canConfirm || ![self.confirmationModel confirmCurrentSnapshot]) {
        return NO;
    }
    self.measurementState = CompactGuideMeasurementStateConfirmed;
    [self notifyChange];
    return YES;
}

- (BOOL)cancelCurrentOperation
{
    if (self.measurementState == CompactGuideMeasurementStateEditing) {
        self.measurementState = self.stateBeforeEditing;
        [self notifyChange];
        return YES;
    }
    if (self.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed) {
        self.measurementState = self.stateBeforeCollecting;
        [self.confirmationModel reset];
        self.collectedPointCount = 0;
        [self notifyChange];
        return YES;
    }
    if (self.measurementState != CompactGuideMeasurementStateCollecting) {
        return NO;
    }
    self.measurementState = CompactGuideMeasurementStateCancelled;
    [self.confirmationModel reset];
    self.collectedPointCount = 0;
    [self notifyChange];
    return YES;
}

- (BOOL)settleCancellationToIdle
{
    if (self.measurementState != CompactGuideMeasurementStateCancelled) {
        return NO;
    }
    self.measurementState = CompactGuideMeasurementStateIdle;
    [self notifyChange];
    return YES;
}

- (BOOL)markUnavailable
{
    self.measurementState = CompactGuideMeasurementStateUnavailable;
    [self.confirmationModel invalidate];
    self.collectedPointCount = 0;
    [self notifyChange];
    return YES;
}

- (BOOL)resetToIdle
{
    self.measurementState = CompactGuideMeasurementStateIdle;
    [self.confirmationModel reset];
    self.collectedPointCount = 0;
    [self notifyChange];
    return YES;
}

- (void)setExpanded:(BOOL)expanded
{
    if (_expanded == expanded) {
        return;
    }
    _expanded = expanded;
    [self notifyChange];
}

- (void)updateCalibrationModel:(CalibrationProvenanceModel *)calibrationModel
{
    if ([self.calibrationModel isEquivalentToModel:calibrationModel]) {
        return;
    }
    self.calibrationModel = [calibrationModel copy];
    MeasurementReviewSnapshot *current = self.confirmationModel.currentSnapshot;
    if (current != nil) {
        [self updateMeasurementSnapshotWithPointA:current.pointA
            pointB:current.pointB rawResult:current.rawResult
            calculationMethodVersion:current.calculationMethodVersion];
    } else {
        [self notifyChange];
    }
}

- (void)updateMeasurementSnapshotWithPointA:(NSPoint)pointA
                                      pointB:(NSPoint)pointB
                                   rawResult:(double)rawResult
                    calculationMethodVersion:(NSString *)calculationMethodVersion
{
    MeasurementReviewSnapshot *snapshot = [[MeasurementReviewSnapshot alloc]
        initWithImageIdentity:self.imageIdentity pointA:pointA pointB:pointB
        calibration:self.calibrationModel
        calculationMethodVersion:calculationMethodVersion rawResult:rawResult
        displayRoundingPolicyVersion:MedisaleDisplayRoundingPolicyVersion
        displayPrecision:MedisaleDisplayPrecision
        modelSchemaVersion:MedisaleConfirmationModelSchemaVersion];
    [self.confirmationModel updateCurrentSnapshot:snapshot];
    if (self.measurementState == CompactGuideMeasurementStateConfirmed &&
        self.confirmationState == CompactGuideConfirmationStateModifiedAfterConfirmation) {
        self.measurementState = CompactGuideMeasurementStateModifiedAfterConfirmation;
    } else if ((self.measurementState == CompactGuideMeasurementStateConfirmed ||
                self.measurementState ==
                    CompactGuideMeasurementStateModifiedAfterConfirmation) &&
               self.confirmationState == CompactGuideConfirmationStateInvalidated) {
        self.measurementState = CompactGuideMeasurementStateCalculatedUnconfirmed;
    }
    [self notifyChange];
}

- (BOOL)matchesImageContext:(ImageContext *)imageContext
{
    ImageContext *expected = self.imageIdentity;
    return imageContext != nil &&
        [imageContext.studyInstanceUID isEqualToString:expected.studyInstanceUID] &&
        [imageContext.seriesInstanceUID isEqualToString:expected.seriesInstanceUID] &&
        [imageContext.sopInstanceUID isEqualToString:expected.sopInstanceUID] &&
        imageContext.frameNumber == expected.frameNumber;
}

- (void)notifyChange
{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:CompactGuideViewStateDidChangeNotification object:self];
}

@end
