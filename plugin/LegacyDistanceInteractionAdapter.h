#import <Foundation/Foundation.h>

@class MeasurementInteractionDefinition;

NS_ASSUME_NONNULL_BEGIN

@interface LegacyDistanceInteractionAdapter : NSObject
+ (MeasurementInteractionDefinition *)interactionDefinition;
@end

NS_ASSUME_NONNULL_END
