#import <Foundation/Foundation.h>

#import "CompactGuideViewState.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompactGuideSemanticRole) {
    CompactGuideSemanticRoleNeutral = 0,
    CompactGuideSemanticRoleActive,
    CompactGuideSemanticRoleAttention,
    CompactGuideSemanticRoleConfirmed,
    CompactGuideSemanticRoleUnavailable,
};

@interface CompactGuidePresentation : NSObject

+ (NSString *)instructionKeyForMeasurementState:(CompactGuideMeasurementState)state
                                     pointCount:(NSUInteger)pointCount;
+ (NSString *)progressKeyForMeasurementState:(CompactGuideMeasurementState)state;
+ (NSString *)calibrationValueKeyForState:(CompactGuideCalibrationState)state;
+ (NSString *)confirmationValueKeyForState:(CompactGuideConfirmationState)state;
+ (NSString *)compactCalibrationValueKeyForState:(CompactGuideCalibrationState)state;
+ (NSString *)compactConfirmationValueKeyForState:(CompactGuideConfirmationState)state;
+ (CompactGuideSemanticRole)semanticRoleForMeasurementState:
    (CompactGuideMeasurementState)state;

@end

NS_ASSUME_NONNULL_END
