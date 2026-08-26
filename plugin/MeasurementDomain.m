#import "MeasurementDomain.h"

#import <float.h>
#import <math.h>

NSErrorDomain const MedisaleMeasurementDomainErrorDomain =
    @"jp.medisale.horos.measurement-domain";
const NSInteger MedisaleMeasurementDomainSchemaVersion = 1;
const NSInteger MedisaleLegacyDistanceMethodVersion = 1;

typedef NS_ENUM(NSInteger, MedisaleMeasurementDomainErrorCode) {
    MedisaleMeasurementDomainErrorInvalidIdentifier = 1,
    MedisaleMeasurementDomainErrorUnsupportedVersion,
    MedisaleMeasurementDomainErrorInvalidContext,
    MedisaleMeasurementDomainErrorInvalidLandmarks,
    MedisaleMeasurementDomainErrorInvalidResult,
    MedisaleMeasurementDomainErrorInvalidCalibration,
};

static void MedisaleDomainSetError(NSError **error,
                                   MedisaleMeasurementDomainErrorCode code,
                                   NSString *description)
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:MedisaleMeasurementDomainErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
}

static BOOL MedisaleStableIdentifierIsValid(NSString *value)
{
    if (![value isKindOfClass:NSString.class] || value.length == 0 ||
        value.length > 128) {
        return NO;
    }
    static NSCharacterSet *disallowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        disallowed = [[NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"]
            invertedSet];
    });
    return [value rangeOfCharacterFromSet:disallowed].location == NSNotFound;
}

static BOOL MedisalePointIsFinite(NSPoint point)
{
    return isfinite(point.x) && isfinite(point.y);
}

static BOOL MedisalePointIsInsideContext(NSPoint point,
                                         MeasurementImageContext *context)
{
    return MedisalePointIsFinite(point) && point.x >= 0.0 && point.y >= 0.0 &&
        point.x < context.pixelWidth && point.y < context.pixelHeight;
}

@interface MeasurementMethodDefinition ()
- (instancetype)initWithKind:(MedisaleMeasurementKind)kind
             stableIdentifier:(NSString *)stableIdentifier
                       version:(NSInteger)version
   requiredLandmarkIdentifiers:(NSArray<NSNumber *> *)requiredLandmarkIdentifiers
                    resultUnit:(MedisaleMeasurementUnit)resultUnit;
@end

@implementation MeasurementMethodDefinition

- (instancetype)initWithKind:(MedisaleMeasurementKind)kind
             stableIdentifier:(NSString *)stableIdentifier
                       version:(NSInteger)version
   requiredLandmarkIdentifiers:(NSArray<NSNumber *> *)requiredLandmarkIdentifiers
                    resultUnit:(MedisaleMeasurementUnit)resultUnit
{
    self = [super init];
    if (self) {
        _kind = kind;
        _stableIdentifier = [stableIdentifier copy];
        _version = version;
        _requiredLandmarkIdentifiers = [requiredLandmarkIdentifiers copy];
        _resultUnit = resultUnit;
    }
    return self;
}

+ (instancetype)legacyImageDistanceV1
{
    static MeasurementMethodDefinition *definition;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        definition = [[self alloc]
            initWithKind:MedisaleMeasurementKindLegacyImageDistance
            stableIdentifier:@"image-distance"
            version:MedisaleLegacyDistanceMethodVersion
            requiredLandmarkIdentifiers:@[
                @(MedisaleLandmarkIdentifierEndpointA),
                @(MedisaleLandmarkIdentifierEndpointB)]
            resultUnit:MedisaleMeasurementUnitPixels];
    });
    return definition;
}

+ (instancetype)definitionForKind:(MedisaleMeasurementKind)kind
                           version:(NSInteger)version
                             error:(NSError **)error
{
    if (kind == MedisaleMeasurementKindLegacyImageDistance &&
        version == MedisaleLegacyDistanceMethodVersion) {
        return [self legacyImageDistanceV1];
    }
    MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorUnsupportedVersion,
        @"The measurement method or version is unsupported.");
    return nil;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface MeasurementImageContext ()
- (instancetype)initWithStudy:(NSString *)study series:(NSString *)series
                           sop:(NSString *)sop frame:(NSInteger)frame
                         width:(NSInteger)width height:(NSInteger)height;
@end

@implementation MeasurementImageContext
- (instancetype)initWithStudy:(NSString *)study series:(NSString *)series
                           sop:(NSString *)sop frame:(NSInteger)frame
                         width:(NSInteger)width height:(NSInteger)height
{
    self = [super init];
    if (self) {
        _studyInstanceUID = [study copy];
        _seriesInstanceUID = [series copy];
        _sopInstanceUID = [sop copy];
        _frameNumber = frame;
        _pixelWidth = width;
        _pixelHeight = height;
    }
    return self;
}

+ (instancetype)contextWithStudyInstanceUID:(NSString *)studyInstanceUID
                            seriesInstanceUID:(NSString *)seriesInstanceUID
                               sopInstanceUID:(NSString *)sopInstanceUID
                                  frameNumber:(NSInteger)frameNumber
                                   pixelWidth:(NSInteger)pixelWidth
                                  pixelHeight:(NSInteger)pixelHeight
                                        error:(NSError **)error
{
    if (!MedisaleStableIdentifierIsValid(studyInstanceUID) ||
        !MedisaleStableIdentifierIsValid(seriesInstanceUID) ||
        !MedisaleStableIdentifierIsValid(sopInstanceUID) ||
        frameNumber < 0 || pixelWidth <= 0 || pixelHeight <= 0) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidContext,
            @"The image identity or dimensions are invalid.");
        return nil;
    }
    return [[self alloc] initWithStudy:studyInstanceUID series:seriesInstanceUID
        sop:sopInstanceUID frame:frameNumber width:pixelWidth height:pixelHeight];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface NamedImageLandmark ()
- (instancetype)initWithIdentifier:(MedisaleLandmarkIdentifier)identifier
                              point:(NSPoint)point;
@end

@implementation NamedImageLandmark
- (instancetype)initWithIdentifier:(MedisaleLandmarkIdentifier)identifier
                              point:(NSPoint)point
{
    self = [super init];
    if (self) {
        _identifier = identifier;
        _imagePoint = point;
    }
    return self;
}

+ (instancetype)landmarkWithIdentifier:(MedisaleLandmarkIdentifier)identifier
                              imagePoint:(NSPoint)imagePoint
                                   error:(NSError **)error
{
    if ((identifier != MedisaleLandmarkIdentifierEndpointA &&
         identifier != MedisaleLandmarkIdentifierEndpointB) ||
        !MedisalePointIsFinite(imagePoint)) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidLandmarks,
            @"The landmark identifier or coordinate is invalid.");
        return nil;
    }
    return [[self alloc] initWithIdentifier:identifier point:imagePoint];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface NamedLandmarkSnapshot ()
- (instancetype)initWithMethod:(MeasurementMethodDefinition *)method
                   imageContext:(MeasurementImageContext *)context
                      landmarks:(NSArray<NamedImageLandmark *> *)landmarks;
@end

@implementation NamedLandmarkSnapshot
- (instancetype)initWithMethod:(MeasurementMethodDefinition *)method
                   imageContext:(MeasurementImageContext *)context
                      landmarks:(NSArray<NamedImageLandmark *> *)landmarks
{
    self = [super init];
    if (self) {
        _method = [method copy];
        _imageContext = [context copy];
        _landmarks = [[NSArray alloc] initWithArray:landmarks copyItems:YES];
    }
    return self;
}

+ (instancetype)snapshotWithMethod:(MeasurementMethodDefinition *)method
                       imageContext:(MeasurementImageContext *)imageContext
                          landmarks:(NSArray<NamedImageLandmark *> *)landmarks
                              error:(NSError **)error
{
    if (method == nil || imageContext == nil ||
        ![landmarks isKindOfClass:NSArray.class]) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidLandmarks,
            @"The named landmark set is incomplete.");
        return nil;
    }
    NSMutableDictionary<NSNumber *, NamedImageLandmark *> *byIdentifier =
        [NSMutableDictionary dictionary];
    NSSet<NSNumber *> *required = [NSSet setWithArray:method.requiredLandmarkIdentifiers];
    for (id candidate in landmarks) {
        if (![candidate isKindOfClass:NamedImageLandmark.class]) {
            MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidLandmarks,
                @"The named landmark set contains an invalid value.");
            return nil;
        }
        NamedImageLandmark *landmark = candidate;
        NSNumber *identifier = @(landmark.identifier);
        if (![required containsObject:identifier] || byIdentifier[identifier] != nil ||
            !MedisalePointIsInsideContext(landmark.imagePoint, imageContext)) {
            MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidLandmarks,
                @"The named landmark set is unknown, duplicated, or outside the image.");
            return nil;
        }
        byIdentifier[identifier] = landmark;
    }
    if (![[NSSet setWithArray:byIdentifier.allKeys] isEqualToSet:required]) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidLandmarks,
            @"A required named landmark is missing.");
        return nil;
    }
    NSArray<NSNumber *> *orderedIdentifiers =
        [method.requiredLandmarkIdentifiers sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NamedImageLandmark *> *ordered = [NSMutableArray array];
    for (NSNumber *identifier in orderedIdentifiers) {
        [ordered addObject:byIdentifier[identifier]];
    }
    return [[self alloc] initWithMethod:method imageContext:imageContext
        landmarks:ordered];
}

- (NamedImageLandmark *)landmarkForIdentifier:(MedisaleLandmarkIdentifier)identifier
{
    for (NamedImageLandmark *landmark in self.landmarks) {
        if (landmark.identifier == identifier) {
            return landmark;
        }
    }
    return nil;
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface VersionedMeasurementResult ()
- (instancetype)initWithMethod:(MeasurementMethodDefinition *)method
                       rawValue:(double)rawValue unit:(MedisaleMeasurementUnit)unit
                       validity:(MedisaleMeasurementValidity)validity
                   warningCodes:(NSArray<NSNumber *> *)warningCodes;
@end


@implementation VersionedMeasurementResult
- (instancetype)initWithMethod:(MeasurementMethodDefinition *)method
                       rawValue:(double)rawValue unit:(MedisaleMeasurementUnit)unit
                       validity:(MedisaleMeasurementValidity)validity
                   warningCodes:(NSArray<NSNumber *> *)warningCodes
{
    self = [super init];
    if (self) {
        _method = [method copy];
        _rawValue = rawValue;
        _unit = unit;
        _validity = validity;
        _warningCodes = [warningCodes copy];
    }
    return self;
}

+ (instancetype)resultWithMethod:(MeasurementMethodDefinition *)method
                         rawValue:(double)rawValue
                             unit:(MedisaleMeasurementUnit)unit
                         validity:(MedisaleMeasurementValidity)validity
                     warningCodes:(NSArray<NSNumber *> *)warningCodes
                            error:(NSError **)error
{
    if (![warningCodes isKindOfClass:NSArray.class]) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidResult,
            @"The warning-code collection is invalid.");
        return nil;
    }
    NSSet<NSNumber *> *allowed = [NSSet setWithArray:@[
        @(MedisaleMeasurementWarningCalibrationUnknown),
        @(MedisaleMeasurementWarningRuntimeSpacingUncalibrated),
        @(MedisaleMeasurementWarningTagProvenanceUnverified)]];
    NSSet<NSNumber *> *provided = [NSSet setWithArray:warningCodes ?: @[]];
    BOOL warningsValid = warningCodes != nil &&
        provided.count == warningCodes.count && [provided isSubsetOfSet:allowed];
    if (method == nil || !isfinite(rawValue) || rawValue < 0.0 ||
        unit != method.resultUnit || validity != MedisaleMeasurementValidityValid ||
        !warningsValid) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidResult,
            @"The raw measurement result is invalid or unsupported.");
        return nil;
    }
    NSArray<NSNumber *> *ordered = [warningCodes
        sortedArrayUsingSelector:@selector(compare:)];
    return [[self alloc] initWithMethod:method rawValue:rawValue unit:unit
        validity:validity warningCodes:ordered];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface MeasurementDomainSnapshot ()
- (instancetype)initWithLandmarks:(NamedLandmarkSnapshot *)landmarks
                            result:(VersionedMeasurementResult *)result;
@end

@implementation MeasurementDomainSnapshot
- (instancetype)initWithLandmarks:(NamedLandmarkSnapshot *)landmarks
                            result:(VersionedMeasurementResult *)result
{
    self = [super init];
    if (self) {
        _landmarkSnapshot = [landmarks copy];
        _result = [result copy];
    }
    return self;
}

+ (instancetype)snapshotWithLandmarks:(NamedLandmarkSnapshot *)landmarks
                                result:(VersionedMeasurementResult *)result
                                 error:(NSError **)error
{
    if (landmarks == nil || result == nil ||
        landmarks.method.kind != result.method.kind ||
        landmarks.method.version != result.method.version) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidResult,
            @"The landmark and result method identities do not match.");
        return nil;
    }
    NamedImageLandmark *a = [landmarks
        landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointA];
    NamedImageLandmark *b = [landmarks
        landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointB];
    if (a == nil || b == nil) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidResult,
            @"The required result landmarks are missing.");
        return nil;
    }
    double expected = hypot(b.imagePoint.x - a.imagePoint.x,
                            b.imagePoint.y - a.imagePoint.y);
    double tolerance = DBL_EPSILON * fmax(1.0, expected) * 8.0;
    if (fabs(result.rawValue - expected) > tolerance) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidResult,
            @"The raw result does not match its named landmark inputs.");
        return nil;
    }
    return [[self alloc] initWithLandmarks:landmarks result:result];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface MeasurementCalibrationReference ()
- (instancetype)initWithState:(MedisaleMeasurementCalibrationState)state
                    provenance:(MedisaleMeasurementCalibrationProvenance)provenance
                 schemaVersion:(NSInteger)schemaVersion
                 methodVersion:(NSInteger)methodVersion
                    rowSpacing:(double)rowSpacing
                 columnSpacing:(double)columnSpacing;
@end

@implementation MeasurementCalibrationReference
- (instancetype)initWithState:(MedisaleMeasurementCalibrationState)state
                    provenance:(MedisaleMeasurementCalibrationProvenance)provenance
                 schemaVersion:(NSInteger)schemaVersion
                 methodVersion:(NSInteger)methodVersion
                    rowSpacing:(double)rowSpacing
                 columnSpacing:(double)columnSpacing
{
    self = [super init];
    if (self) {
        _state = state;
        _provenance = provenance;
        _schemaVersion = schemaVersion;
        _methodVersion = methodVersion;
        _rowSpacing = rowSpacing;
        _columnSpacing = columnSpacing;
    }
    return self;
}

+ (instancetype)referenceWithState:(MedisaleMeasurementCalibrationState)state
                          provenance:(MedisaleMeasurementCalibrationProvenance)provenance
                       schemaVersion:(NSInteger)schemaVersion
                       methodVersion:(NSInteger)methodVersion
                          rowSpacing:(double)rowSpacing
                       columnSpacing:(double)columnSpacing
                               error:(NSError **)error
{
    BOOL valid = schemaVersion == 1 && methodVersion == 1;
    if (state == MedisaleMeasurementCalibrationStateUnknown) {
        valid = valid && provenance == MedisaleMeasurementCalibrationProvenanceNone &&
            isnan(rowSpacing) && isnan(columnSpacing);
    } else if (state == MedisaleMeasurementCalibrationStateRuntimeSpacingUncalibrated) {
        valid = valid && provenance ==
            MedisaleMeasurementCalibrationProvenanceHorosRuntimeSpacing &&
            isfinite(rowSpacing) && rowSpacing > 0.0 &&
            isfinite(columnSpacing) && columnSpacing > 0.0;
    } else if (state == MedisaleMeasurementCalibrationStateExplicit) {
        valid = valid && provenance == MedisaleMeasurementCalibrationProvenanceExplicit &&
            isfinite(rowSpacing) && rowSpacing > 0.0 &&
            isfinite(columnSpacing) && columnSpacing > 0.0;
    } else {
        valid = NO;
    }
    if (!valid) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidCalibration,
            @"The calibration state, provenance, or version is inconsistent.");
        return nil;
    }
    return [[self alloc] initWithState:state provenance:provenance
        schemaVersion:schemaVersion methodVersion:methodVersion
        rowSpacing:rowSpacing columnSpacing:columnSpacing];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface MeasurementReviewAssociation ()
@property(nonatomic, copy) NSData *canonicalInputData;
- (instancetype)initWithSnapshot:(MeasurementDomainSnapshot *)snapshot
                       calibration:(MeasurementCalibrationReference *)calibration
                  canonicalInputData:(NSData *)canonicalInputData
                         fingerprint:(NSString *)fingerprint;
@end


@implementation MeasurementReviewAssociation
+ (instancetype)associationWithSnapshot:(MeasurementDomainSnapshot *)snapshot
                             calibration:(MeasurementCalibrationReference *)calibration
                                   error:(NSError **)error
{
    if (snapshot == nil || calibration == nil) {
        MedisaleDomainSetError(error, MedisaleMeasurementDomainErrorInvalidCalibration,
            @"The review inputs are incomplete.");
        return nil;
    }
    MeasurementImageContext *context = snapshot.landmarkSnapshot.imageContext;
    NSMutableString *fingerprint = [NSMutableString stringWithFormat:
        @"%ld|%ld|%@|%@|%@|%ld|%ld|%ld",
        (long)snapshot.landmarkSnapshot.method.kind,
        (long)snapshot.landmarkSnapshot.method.version,
        context.studyInstanceUID, context.seriesInstanceUID, context.sopInstanceUID,
        (long)context.frameNumber, (long)context.pixelWidth, (long)context.pixelHeight];
    for (NamedImageLandmark *landmark in snapshot.landmarkSnapshot.landmarks) {
        [fingerprint appendFormat:@"|%ld|%a|%a", (long)landmark.identifier,
            landmark.imagePoint.x, landmark.imagePoint.y];
    }
    [fingerprint appendFormat:@"|%a|%ld|%ld|%ld|%ld|%a|%a",
        snapshot.result.rawValue, (long)calibration.state,
        (long)calibration.provenance, (long)calibration.schemaVersion,
        (long)calibration.methodVersion, calibration.rowSpacing,
        calibration.columnSpacing];
    NSData *canonicalInputData = [fingerprint dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = canonicalInputData.bytes;
    uint64_t hash = UINT64_C(1469598103934665603);
    for (NSUInteger index = 0; index < canonicalInputData.length; index++) {
        hash ^= bytes[index];
        hash *= UINT64_C(1099511628211);
    }
    NSString *opaqueFingerprint = [NSString stringWithFormat:@"%016llx",
        (unsigned long long)hash];
    return [[self alloc] initWithSnapshot:snapshot calibration:calibration
        canonicalInputData:canonicalInputData fingerprint:opaqueFingerprint];
}

- (instancetype)initWithSnapshot:(MeasurementDomainSnapshot *)snapshot
                       calibration:(MeasurementCalibrationReference *)calibration
                  canonicalInputData:(NSData *)canonicalInputData
                         fingerprint:(NSString *)fingerprint
{
    self = [super init];
    if (self) {
        _snapshot = [snapshot copy];
        _calibration = [calibration copy];
        _canonicalInputData = [canonicalInputData copy];
        _inputFingerprint = [fingerprint copy];
    }
    return self;
}

- (BOOL)hasSameInputsAsAssociation:(MeasurementReviewAssociation *)other
{
    return other != nil &&
        [self.canonicalInputData isEqualToData:other.canonicalInputData];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end
