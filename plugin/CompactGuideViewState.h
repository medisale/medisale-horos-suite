#import <Foundation/Foundation.h>

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

typedef NS_ENUM(NSInteger, CompactGuideCalibrationState) {
    CompactGuideCalibrationStateCalibrated = 0,
    CompactGuideCalibrationStateDICOMSpacingOnly,
    CompactGuideCalibrationStateUnknown,
};

typedef NS_ENUM(NSInteger, CompactGuideConfirmationState) {
    CompactGuideConfirmationStateNotReviewed = 0,
    CompactGuideConfirmationStateUserConfirmed,
    CompactGuideConfirmationStateModifiedAfterConfirmation,
};

FOUNDATION_EXPORT NSNotificationName const CompactGuideViewStateDidChangeNotification;

@interface CompactGuideViewState : NSObject

@property(nonatomic, copy, readonly) ImageContext *imageIdentity;
@property(nonatomic, readonly) CompactGuideMeasurementState measurementState;
@property(nonatomic, readonly) CompactGuideCalibrationState calibrationState;
@property(nonatomic, readonly) CompactGuideConfirmationState confirmationState;
@property(nonatomic, readonly) NSUInteger collectedPointCount;
@property(nonatomic, readonly, getter=isExpanded) BOOL expanded;
@property(nonatomic, readonly) BOOL canCancel;
@property(nonatomic, readonly) BOOL canConfirm;

- (instancetype)initWithImageIdentity:(ImageContext *)imageIdentity
                     calibrationState:(CompactGuideCalibrationState)calibrationState
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
- (void)updateCalibrationState:(CompactGuideCalibrationState)calibrationState;
- (void)markMeasurementValueChanged;
- (BOOL)matchesImageContext:(nullable ImageContext *)imageContext;

@end

NS_ASSUME_NONNULL_END
