#import "CompactGuidePresentation.h"

@implementation CompactGuidePresentation

+ (NSString *)instructionKeyForMeasurementState:(CompactGuideMeasurementState)state
                                     pointCount:(NSUInteger)pointCount
{
    switch (state) {
        case CompactGuideMeasurementStateCollecting:
            return pointCount == 0 ? @"guide.instruction.collecting.first"
                                   : @"guide.instruction.collecting.second";
        case CompactGuideMeasurementStateEditing:
            return @"guide.instruction.editing";
        case CompactGuideMeasurementStateCalculatedUnconfirmed:
            return @"guide.instruction.calculated";
        case CompactGuideMeasurementStateConfirmed:
            return @"guide.instruction.confirmed";
        case CompactGuideMeasurementStateModifiedAfterConfirmation:
            return @"guide.instruction.modified";
        case CompactGuideMeasurementStateCancelled:
            return @"guide.instruction.cancelled";
        case CompactGuideMeasurementStateUnavailable:
            return @"guide.instruction.unavailable";
        case CompactGuideMeasurementStateIdle:
        default:
            return @"guide.instruction.idle";
    }
}

+ (NSString *)progressKeyForMeasurementState:(CompactGuideMeasurementState)state
{
    switch (state) {
        case CompactGuideMeasurementStateCollecting:
            return @"guide.progress.collecting.format";
        case CompactGuideMeasurementStateEditing:
            return @"guide.progress.editing";
        case CompactGuideMeasurementStateCalculatedUnconfirmed:
            return @"guide.progress.calculated";
        case CompactGuideMeasurementStateConfirmed:
            return @"guide.progress.confirmed";
        case CompactGuideMeasurementStateModifiedAfterConfirmation:
            return @"guide.progress.modified";
        case CompactGuideMeasurementStateCancelled:
            return @"guide.progress.cancelled";
        case CompactGuideMeasurementStateUnavailable:
            return @"guide.progress.unavailable";
        case CompactGuideMeasurementStateIdle:
        default:
            return @"guide.progress.idle";
    }
}

+ (NSString *)calibrationValueKeyForState:(CompactGuideCalibrationState)state
{
    switch (state) {
        case CompactGuideCalibrationStateCalibrated:
            return @"guide.calibration.calibrated";
        case CompactGuideCalibrationStateDICOMSpacingOnly:
            return @"guide.calibration.dicom";
        case CompactGuideCalibrationStateUnknown:
        default:
            return @"guide.calibration.unknown";
    }
}

+ (NSString *)confirmationValueKeyForState:(CompactGuideConfirmationState)state
{
    switch (state) {
        case CompactGuideConfirmationStateUserConfirmed:
            return @"guide.confirmation.confirmed";
        case CompactGuideConfirmationStateModifiedAfterConfirmation:
            return @"guide.confirmation.modified";
        case CompactGuideConfirmationStateNotReviewed:
        default:
            return @"guide.confirmation.notReviewed";
    }
}

+ (NSString *)compactCalibrationValueKeyForState:(CompactGuideCalibrationState)state
{
    return [[self calibrationValueKeyForState:state]
        stringByReplacingOccurrencesOfString:@"guide.calibration."
                                  withString:@"guide.calibration.compact."];
}

+ (NSString *)compactConfirmationValueKeyForState:(CompactGuideConfirmationState)state
{
    return [[self confirmationValueKeyForState:state]
        stringByReplacingOccurrencesOfString:@"guide.confirmation."
                                  withString:@"guide.confirmation.compact."];
}

+ (CompactGuideSemanticRole)semanticRoleForMeasurementState:
    (CompactGuideMeasurementState)state
{
    switch (state) {
        case CompactGuideMeasurementStateCollecting:
        case CompactGuideMeasurementStateEditing:
            return CompactGuideSemanticRoleActive;
        case CompactGuideMeasurementStateCalculatedUnconfirmed:
        case CompactGuideMeasurementStateModifiedAfterConfirmation:
            return CompactGuideSemanticRoleAttention;
        case CompactGuideMeasurementStateConfirmed:
            return CompactGuideSemanticRoleConfirmed;
        case CompactGuideMeasurementStateUnavailable:
            return CompactGuideSemanticRoleUnavailable;
        case CompactGuideMeasurementStateIdle:
        case CompactGuideMeasurementStateCancelled:
        default:
            return CompactGuideSemanticRoleNeutral;
    }
}

@end
