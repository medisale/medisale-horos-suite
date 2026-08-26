#import <Foundation/Foundation.h>

@class ImageContext;
@class MeasurementPersistenceDTO;
@class MeasurementRecord;

NS_ASSUME_NONNULL_BEGIN

@interface LegacyDistanceMeasurementAdapter : NSObject
+ (nullable MeasurementPersistenceDTO *)DTOFromRecord:(MeasurementRecord *)record
                                                  error:(NSError * _Nullable * _Nullable)error;
+ (nullable MeasurementRecord *)recordFromDTO:(MeasurementPersistenceDTO *)DTO
                            restorationContext:(ImageContext *)restorationContext
                                         error:(NSError * _Nullable * _Nullable)error;
+ (nullable MeasurementRecord *)canonicalRecordFromRecord:(MeasurementRecord *)record
                                                     error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
