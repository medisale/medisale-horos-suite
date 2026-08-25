#import <Foundation/Foundation.h>

#import "CalibrationConfirmationState.h"

@class ImageContext;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompactGuideMeasurementState) {
    CompactGuideMeasurementStateIdle = 0,
    CompactGuideMeasurementStateCollecting,
    CompactGuideMeasurementStateEditing,
    CompactGuideMeasurementStateCalculatedUnconfirmed,
    CompactGuideMeasurementStateConfirmed,
    CompactGuideMeasurementStateModifiedAfterConfirmation,
    CompactGuideMeasurementStateCancelled,
    CompactGuideMeasurementStateUnavailable,
};

typedef MedisaleCalibrationState CompactGuideCalibrationState;
enum {
    CompactGuideCalibrationStateCalibrated = MedisaleCalibrationStateCalibrated,
    CompactGuideCalibrationStateDICOMSpacingOnly = MedisaleCalibrationStateDICOMSpacingOnly,
    CompactGuideCalibrationStateUnknown = MedisaleCalibrationStateUnknown,
};

typedef MedisaleConfirmationState CompactGuideConfirmationState;
enum {
    CompactGuideConfirmationStateNotReviewed = MedisaleConfirmationStateUnreviewed,
    CompactGuideConfirmationStateUserConfirmed = MedisaleConfirmationStateUserConfirmed,
    CompactGuideConfirmationStateModifiedAfterConfirmation =
        MedisaleConfirmationStateModifiedAfterConfirmation,
    CompactGuideConfirmationStateInvalidated = MedisaleConfirmationStateInvalidated,
};

FOUNDATION_EXPORT NSNotificationName const CompactGuideViewStateDidChangeNotification;

@interface CompactGuideViewState : NSObject

@property(nonatomic, copy, readonly) ImageContext *imageIdentity;
@property(nonatomic, readonly) CompactGuideMeasurementState measurementState;
@property(nonatomic, readonly) CompactGuideCalibrationState calibrationState;
@property(nonatomic, readonly) CompactGuideConfirmationState confirmationState;
@property(nonatomic, copy, readonly) CalibrationProvenanceModel *calibrationModel;
@property(nonatomic, strong, readonly) ConfirmationStateModel *confirmationModel;
@property(nonatomic, readonly) NSUInteger collectedPointCount;
@property(nonatomic, readonly, getter=isExpanded) BOOL expanded;
@property(nonatomic, readonly) BOOL canCancel;
@property(nonatomic, readonly) BOOL canConfirm;

- (instancetype)initWithImageIdentity:(ImageContext *)imageIdentity
                      calibrationModel:(CalibrationProvenanceModel *)calibrationModel
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)startCollecting;
- (BOOL)updateCollectedPointCount:(NSUInteger)pointCount;
- (BOOL)markCalculated;
- (BOOL)beginEditing;
- (BOOL)finishEditingChanged:(BOOL)changed;
- (BOOL)confirm;
- (BOOL)cancelCurrentOperation;
- (BOOL)settleCancellationToIdle;
- (BOOL)markUnavailable;
- (BOOL)resetToIdle;
- (void)setExpanded:(BOOL)expanded;
- (void)updateCalibrationModel:(CalibrationProvenanceModel *)calibrationModel;
- (void)updateMeasurementSnapshotWithPointA:(NSPoint)pointA
                                      pointB:(NSPoint)pointB
                                   rawResult:(double)rawResult
                    calculationMethodVersion:(NSString *)calculationMethodVersion;
- (BOOL)matchesImageContext:(nullable ImageContext *)imageContext;

@end

NS_ASSUME_NONNULL_END
