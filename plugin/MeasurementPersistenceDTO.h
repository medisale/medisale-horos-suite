#import <Foundation/Foundation.h>

@class MeasurementDomainSnapshot;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const MedisaleMeasurementDTOErrorDomain;
FOUNDATION_EXPORT const NSInteger MedisaleMeasurementPersistenceDTOVersion;

@interface MeasurementPersistenceDTO : NSObject <NSCopying>
@property(nonatomic, readonly) NSInteger dtoVersion;
@property(nonatomic, copy, readonly) NSString *measurementID;
@property(nonatomic, copy, readonly) MeasurementDomainSnapshot *domainSnapshot;
@property(nonatomic, copy, readonly) NSDate *createdAt;
@property(nonatomic, copy, readonly) NSDate *updatedAt;
+ (nullable instancetype)DTOWithMeasurementID:(NSString *)measurementID
                                domainSnapshot:(MeasurementDomainSnapshot *)domainSnapshot
                                     createdAt:(NSDate *)createdAt
                                     updatedAt:(NSDate *)updatedAt
                                         error:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)DTOFromDictionary:(NSDictionary<NSString *, id> *)dictionary
                                      error:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)DTOFromSerializedData:(NSData *)data
                                          error:(NSError * _Nullable * _Nullable)error;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
- (nullable NSData *)serializedDataWithError:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
