#import "CompactGuideViewState.h"

#import "ImageContext.h"

NSNotificationName const CompactGuideViewStateDidChangeNotification =
    @"MedisaleCompactGuideViewStateDidChangeNotification";

@interface CompactGuideViewState ()
@property(nonatomic, readwrite) CompactGuideMeasurementState measurementState;
@property(nonatomic, readwrite) CompactGuideCalibrationState calibrationState;
@property(nonatomic, readwrite) CompactGuideConfirmationState confirmationState;
@property(nonatomic, readwrite) NSUInteger collectedPointCount;
@property(nonatomic, readwrite, getter=isExpanded) BOOL expanded;
@property(nonatomic) CompactGuideMeasurementState stateBeforeEditing;
@property(nonatomic) CompactGuideConfirmationState confirmationBeforeEditing;
@property(nonatomic) CompactGuideMeasurementState stateBeforeCollecting;
@end

@implementation CompactGuideViewState

- (instancetype)initWithImageIdentity:(ImageContext *)imageIdentity
                     calibrationState:(CompactGuideCalibrationState)calibrationState
{
    self = [super init];
    if (self) {
        _imageIdentity = [imageIdentity copy];
        _measurementState = CompactGuideMeasurementStateIdle;
        _calibrationState = calibrationState;
        _confirmationState = CompactGuideConfirmationStateNotReviewed;
        _stateBeforeEditing = CompactGuideMeasurementStateIdle;
        _confirmationBeforeEditing = CompactGuideConfirmationStateNotReviewed;
        _stateBeforeCollecting = CompactGuideMeasurementStateIdle;
    }
    return self;
}

- (BOOL)canCancel
{
    return self.measurementState == CompactGuideMeasurementStateCollecting ||
        self.measurementState == CompactGuideMeasurementStateEditing ||
        self.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed;
}

- (BOOL)canConfirm
{
    return self.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed ||
        self.measurementState == CompactGuideMeasurementStateModifiedAfterConfirmation;
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
    self.confirmationState = CompactGuideConfirmationStateNotReviewed;
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
    self.confirmationState = CompactGuideConfirmationStateNotReviewed;
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
    self.confirmationBeforeEditing = self.confirmationState;
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
        self.confirmationState = self.confirmationBeforeEditing;
    } else if (self.stateBeforeEditing == CompactGuideMeasurementStateConfirmed ||
               self.stateBeforeEditing == CompactGuideMeasurementStateModifiedAfterConfirmation ||
               self.confirmationBeforeEditing == CompactGuideConfirmationStateUserConfirmed ||
               self.confirmationBeforeEditing == CompactGuideConfirmationStateModifiedAfterConfirmation) {
        self.measurementState = CompactGuideMeasurementStateModifiedAfterConfirmation;
        self.confirmationState = CompactGuideConfirmationStateModifiedAfterConfirmation;
    } else {
        self.measurementState = CompactGuideMeasurementStateCalculatedUnconfirmed;
        self.confirmationState = CompactGuideConfirmationStateNotReviewed;
    }
    [self notifyChange];
    return YES;
}

- (BOOL)confirm
{
    if (!self.canConfirm) {
        return NO;
    }
    self.measurementState = CompactGuideMeasurementStateConfirmed;
    self.confirmationState = CompactGuideConfirmationStateUserConfirmed;
    [self notifyChange];
    return YES;
}

- (BOOL)cancelCurrentOperation
{
    if (self.measurementState == CompactGuideMeasurementStateEditing) {
        self.measurementState = self.stateBeforeEditing;
        self.confirmationState = self.confirmationBeforeEditing;
        [self notifyChange];
        return YES;
    }
    if (self.measurementState == CompactGuideMeasurementStateCalculatedUnconfirmed) {
        self.measurementState = self.stateBeforeCollecting;
        self.confirmationState = CompactGuideConfirmationStateNotReviewed;
        self.collectedPointCount = 0;
        [self notifyChange];
        return YES;
    }
    if (self.measurementState != CompactGuideMeasurementStateCollecting) {
        return NO;
    }
    self.measurementState = CompactGuideMeasurementStateCancelled;
    self.confirmationState = CompactGuideConfirmationStateNotReviewed;
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
    self.confirmationState = CompactGuideConfirmationStateNotReviewed;
    self.collectedPointCount = 0;
    [self notifyChange];
    return YES;
}

- (BOOL)resetToIdle
{
    self.measurementState = CompactGuideMeasurementStateIdle;
    self.confirmationState = CompactGuideConfirmationStateNotReviewed;
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

- (void)updateCalibrationState:(CompactGuideCalibrationState)calibrationState
{
    if (self.calibrationState == calibrationState) {
        return;
    }
    self.calibrationState = calibrationState;
    [self markMeasurementValueChanged];
}

- (void)markMeasurementValueChanged
{
    if (self.measurementState == CompactGuideMeasurementStateConfirmed ||
        self.confirmationState == CompactGuideConfirmationStateUserConfirmed) {
        self.measurementState = CompactGuideMeasurementStateModifiedAfterConfirmation;
        self.confirmationState = CompactGuideConfirmationStateModifiedAfterConfirmation;
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
