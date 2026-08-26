#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const MedisaleMeasurementDomainErrorDomain;
FOUNDATION_EXPORT const NSInteger MedisaleMeasurementDomainSchemaVersion;
FOUNDATION_EXPORT const NSInteger MedisaleLegacyDistanceMethodVersion;

typedef NS_ENUM(NSInteger, MedisaleMeasurementKind) {
    MedisaleMeasurementKindLegacyImageDistance = 1,
};

typedef NS_ENUM(NSInteger, MedisaleLandmarkIdentifier) {
    MedisaleLandmarkIdentifierEndpointA = 1,
    MedisaleLandmarkIdentifierEndpointB = 2,
};

typedef NS_ENUM(NSInteger, MedisaleMeasurementUnit) {
    MedisaleMeasurementUnitPixels = 1,
};

typedef NS_ENUM(NSInteger, MedisaleMeasurementValidity) {
    MedisaleMeasurementValidityValid = 1,
};

typedef NS_ENUM(NSInteger, MedisaleMeasurementWarningCode) {
    MedisaleMeasurementWarningCalibrationUnknown = 1,
    MedisaleMeasurementWarningRuntimeSpacingUncalibrated = 2,
    MedisaleMeasurementWarningTagProvenanceUnverified = 3,
};

typedef NS_ENUM(NSInteger, MedisaleMeasurementCalibrationState) {
    MedisaleMeasurementCalibrationStateUnknown = 1,
    MedisaleMeasurementCalibrationStateRuntimeSpacingUncalibrated = 2,
    MedisaleMeasurementCalibrationStateExplicit = 3,
};

typedef NS_ENUM(NSInteger, MedisaleMeasurementCalibrationProvenance) {
    MedisaleMeasurementCalibrationProvenanceNone = 1,
    MedisaleMeasurementCalibrationProvenanceHorosRuntimeSpacing = 2,
    MedisaleMeasurementCalibrationProvenanceExplicit = 3,
};

@interface MeasurementMethodDefinition : NSObject <NSCopying>
@property(nonatomic, readonly) MedisaleMeasurementKind kind;
@property(nonatomic, copy, readonly) NSString *stableIdentifier;
@property(nonatomic, readonly) NSInteger version;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *requiredLandmarkIdentifiers;
@property(nonatomic, readonly) MedisaleMeasurementUnit resultUnit;
+ (instancetype)legacyImageDistanceV1;
+ (nullable instancetype)definitionForKind:(MedisaleMeasurementKind)kind
                                   version:(NSInteger)version
                                     error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementImageContext : NSObject <NSCopying>
@property(nonatomic, copy, readonly) NSString *studyInstanceUID;
@property(nonatomic, copy, readonly) NSString *seriesInstanceUID;
@property(nonatomic, copy, readonly) NSString *sopInstanceUID;
@property(nonatomic, readonly) NSInteger frameNumber;
@property(nonatomic, readonly) NSInteger pixelWidth;
@property(nonatomic, readonly) NSInteger pixelHeight;
+ (nullable instancetype)contextWithStudyInstanceUID:(NSString *)studyInstanceUID
                                    seriesInstanceUID:(NSString *)seriesInstanceUID
                                       sopInstanceUID:(NSString *)sopInstanceUID
                                          frameNumber:(NSInteger)frameNumber
                                           pixelWidth:(NSInteger)pixelWidth
                                          pixelHeight:(NSInteger)pixelHeight
                                                error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface NamedImageLandmark : NSObject <NSCopying>
@property(nonatomic, readonly) MedisaleLandmarkIdentifier identifier;
@property(nonatomic, readonly) NSPoint imagePoint;
+ (nullable instancetype)landmarkWithIdentifier:(MedisaleLandmarkIdentifier)identifier
                                      imagePoint:(NSPoint)imagePoint
                                           error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface NamedLandmarkSnapshot : NSObject <NSCopying>
@property(nonatomic, copy, readonly) MeasurementMethodDefinition *method;
@property(nonatomic, copy, readonly) MeasurementImageContext *imageContext;
@property(nonatomic, copy, readonly) NSArray<NamedImageLandmark *> *landmarks;
+ (nullable instancetype)snapshotWithMethod:(MeasurementMethodDefinition *)method
                               imageContext:(MeasurementImageContext *)imageContext
                                  landmarks:(NSArray<NamedImageLandmark *> *)landmarks
                                      error:(NSError * _Nullable * _Nullable)error;
- (nullable NamedImageLandmark *)landmarkForIdentifier:
    (MedisaleLandmarkIdentifier)identifier;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface VersionedMeasurementResult : NSObject <NSCopying>
@property(nonatomic, copy, readonly) MeasurementMethodDefinition *method;
@property(nonatomic, readonly) double rawValue;
@property(nonatomic, readonly) MedisaleMeasurementUnit unit;
@property(nonatomic, readonly) MedisaleMeasurementValidity validity;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *warningCodes;
+ (nullable instancetype)resultWithMethod:(MeasurementMethodDefinition *)method
                                 rawValue:(double)rawValue
                                     unit:(MedisaleMeasurementUnit)unit
                                 validity:(MedisaleMeasurementValidity)validity
                             warningCodes:(NSArray<NSNumber *> *)warningCodes
                                    error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementDomainSnapshot : NSObject <NSCopying>
@property(nonatomic, copy, readonly) NamedLandmarkSnapshot *landmarkSnapshot;
@property(nonatomic, copy, readonly) VersionedMeasurementResult *result;
+ (nullable instancetype)snapshotWithLandmarks:(NamedLandmarkSnapshot *)landmarks
                                        result:(VersionedMeasurementResult *)result
                                         error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementCalibrationReference : NSObject <NSCopying>
@property(nonatomic, readonly) MedisaleMeasurementCalibrationState state;
@property(nonatomic, readonly) MedisaleMeasurementCalibrationProvenance provenance;
@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly) NSInteger methodVersion;
@property(nonatomic, readonly) double rowSpacing;
@property(nonatomic, readonly) double columnSpacing;
+ (nullable instancetype)referenceWithState:(MedisaleMeasurementCalibrationState)state
                                  provenance:(MedisaleMeasurementCalibrationProvenance)provenance
                               schemaVersion:(NSInteger)schemaVersion
                               methodVersion:(NSInteger)methodVersion
                                  rowSpacing:(double)rowSpacing
                               columnSpacing:(double)columnSpacing
                                       error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementReviewAssociation : NSObject <NSCopying>
@property(nonatomic, copy, readonly) MeasurementDomainSnapshot *snapshot;
@property(nonatomic, copy, readonly) MeasurementCalibrationReference *calibration;
@property(nonatomic, copy, readonly) NSString *inputFingerprint;
+ (nullable instancetype)associationWithSnapshot:(MeasurementDomainSnapshot *)snapshot
                                     calibration:(MeasurementCalibrationReference *)calibration
                                           error:(NSError * _Nullable * _Nullable)error;
- (BOOL)hasSameInputsAsAssociation:(MeasurementReviewAssociation *)other;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
