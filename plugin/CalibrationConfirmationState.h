#import <Foundation/Foundation.h>

@class ImageContext;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MedisaleCalibrationState) {
    MedisaleCalibrationStateCalibrated = 0,
    MedisaleCalibrationStateDICOMSpacingOnly,
    MedisaleCalibrationStateUnknown,
};

typedef NS_ENUM(NSInteger, MedisaleCalibrationSourceCategory) {
    MedisaleCalibrationSourceCategoryNone = 0,
    MedisaleCalibrationSourceCategoryDICOMDerived,
    MedisaleCalibrationSourceCategoryExplicitCalibration,
};

typedef NS_ENUM(NSInteger, MedisaleCalibrationDerivationStatus) {
    MedisaleCalibrationDerivationStatusMissing = 0,
    MedisaleCalibrationDerivationStatusDICOMDerived,
    MedisaleCalibrationDerivationStatusExplicit,
    MedisaleCalibrationDerivationStatusInvalid,
};

typedef NS_ENUM(NSInteger, MedisaleConfirmationState) {
    MedisaleConfirmationStateUnreviewed = 0,
    MedisaleConfirmationStateUserConfirmed,
    MedisaleConfirmationStateModifiedAfterConfirmation,
    MedisaleConfirmationStateInvalidated,
};

FOUNDATION_EXPORT NSInteger const MedisaleCalibrationModelSchemaVersion;
FOUNDATION_EXPORT NSInteger const MedisaleConfirmationModelSchemaVersion;
FOUNDATION_EXPORT NSString * const MedisaleDistanceCalculationMethodVersion;
FOUNDATION_EXPORT NSString * const MedisaleDisplayRoundingPolicyVersion;

@interface CalibrationProvenanceModel : NSObject <NSCopying>

@property(nonatomic, readonly) MedisaleCalibrationState state;
@property(nonatomic, readonly) MedisaleCalibrationSourceCategory sourceCategory;
@property(nonatomic, copy, readonly) NSString *sourceIdentifier;
@property(nonatomic, copy, readonly) NSString *methodVersion;
@property(nonatomic, readonly) double rowSpacing;
@property(nonatomic, readonly) double columnSpacing;
@property(nonatomic, copy, readonly) NSString *units;
@property(nonatomic, readonly) MedisaleCalibrationDerivationStatus derivationStatus;
@property(nonatomic, copy, readonly) NSArray<NSString *> *warnings;
@property(nonatomic, readonly) NSInteger modelSchemaVersion;
@property(nonatomic, readonly, getter=hasUsableSpacing) BOOL usableSpacing;

+ (instancetype)modelFromImageContext:(ImageContext *)imageContext;
+ (instancetype)unknownModelWithWarnings:(NSArray<NSString *> *)warnings;
+ (nullable instancetype)calibratedModelWithSourceIdentifier:(NSString *)sourceIdentifier
                                               methodVersion:(NSString *)methodVersion
                                                  rowSpacing:(double)rowSpacing
                                               columnSpacing:(double)columnSpacing
                                                       error:(NSError * _Nullable * _Nullable)error;

- (double)physicalDistanceForPointA:(NSPoint)pointA pointB:(NSPoint)pointB;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)modelFromDictionary:(NSDictionary<NSString *, id> *)dictionary
                                        error:(NSError * _Nullable * _Nullable)error;
- (BOOL)isEquivalentToModel:(nullable CalibrationProvenanceModel *)other;

@end

@interface MeasurementReviewSnapshot : NSObject <NSCopying>

@property(nonatomic, copy, readonly) ImageContext *imageIdentity;
@property(nonatomic, readonly) NSPoint pointA;
@property(nonatomic, readonly) NSPoint pointB;
@property(nonatomic, copy, readonly) CalibrationProvenanceModel *calibration;
@property(nonatomic, copy, readonly) NSString *calculationMethodVersion;
@property(nonatomic, readonly) double rawResult;
@property(nonatomic, copy, readonly) NSString *displayRoundingPolicyVersion;
@property(nonatomic, readonly) NSUInteger displayPrecision;
@property(nonatomic, readonly) NSInteger modelSchemaVersion;
@property(nonatomic, readonly, getter=isStructurallyValid) BOOL structurallyValid;

- (instancetype)initWithImageIdentity:(ImageContext *)imageIdentity
                                pointA:(NSPoint)pointA
                                pointB:(NSPoint)pointB
                           calibration:(CalibrationProvenanceModel *)calibration
              calculationMethodVersion:(NSString *)calculationMethodVersion
                             rawResult:(double)rawResult
          displayRoundingPolicyVersion:(NSString *)displayRoundingPolicyVersion
                      displayPrecision:(NSUInteger)displayPrecision
                    modelSchemaVersion:(NSInteger)modelSchemaVersion
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)matchesImageIdentity:(nullable ImageContext *)imageIdentity;
- (BOOL)isEquivalentToSnapshot:(nullable MeasurementReviewSnapshot *)other;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
+ (nullable instancetype)snapshotFromDictionary:(NSDictionary<NSString *, id> *)dictionary
                                           error:(NSError * _Nullable * _Nullable)error;

@end

@interface ConfirmationStateModel : NSObject

@property(nonatomic, readonly) MedisaleConfirmationState state;
@property(nonatomic, copy, readonly, nullable) MeasurementReviewSnapshot *currentSnapshot;
@property(nonatomic, copy, readonly, nullable) MeasurementReviewSnapshot *confirmedSnapshot;

- (void)reset;
- (void)updateCurrentSnapshot:(nullable MeasurementReviewSnapshot *)snapshot;
- (BOOL)confirmCurrentSnapshot;
- (void)invalidate;

@end

@interface MeasurementValueFormatter : NSObject

+ (NSString *)displayStringForRawValue:(double)rawValue
                             precision:(NSUInteger)precision
                                locale:(NSLocale *)locale;

@end

NS_ASSUME_NONNULL_END
