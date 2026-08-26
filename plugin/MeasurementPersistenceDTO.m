#import "MeasurementPersistenceDTO.h"

#import "MeasurementDomain.h"
#import <math.h>

NSErrorDomain const MedisaleMeasurementDTOErrorDomain =
    @"jp.medisale.horos.measurement-dto";
const NSInteger MedisaleMeasurementPersistenceDTOVersion = 1;

typedef NS_ENUM(NSInteger, MedisaleMeasurementDTOErrorCode) {
    MedisaleMeasurementDTOErrorInvalidEnvelope = 1,
    MedisaleMeasurementDTOErrorUnsupportedVersion,
    MedisaleMeasurementDTOErrorInvalidDomain,
    MedisaleMeasurementDTOErrorSerialization,
};

static void MedisaleDTOSetError(NSError **error,
                                MedisaleMeasurementDTOErrorCode code,
                                NSString *description)
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:MedisaleMeasurementDTOErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
}

static BOOL MedisaleDTOExactKeys(NSDictionary *dictionary, NSArray<NSString *> *keys)
{
    return [dictionary isKindOfClass:NSDictionary.class] &&
        [[NSSet setWithArray:dictionary.allKeys]
            isEqualToSet:[NSSet setWithArray:keys]];
}

static BOOL MedisaleDTONumber(NSNumber *number)
{
    return [number isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)number) != CFBooleanGetTypeID();
}

static BOOL MedisaleDTOInteger(NSNumber *number)
{
    if (!MedisaleDTONumber(number)) {
        return NO;
    }
    double value = number.doubleValue;
    double minimum = (double)NSIntegerMin;
    double exclusiveMaximum = -minimum;
    return isfinite(value) && floor(value) == value &&
        value >= minimum && value < exclusiveMaximum;
}

static BOOL MedisaleDTOIdentifier(NSString *value)
{
    if (![value isKindOfClass:NSString.class] || value.length == 0 ||
        value.length > 128) {
        return NO;
    }
    static NSCharacterSet *invalid;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        invalid = [[NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"]
            invertedSet];
    });
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static NSString *MedisaleKindCode(MedisaleMeasurementKind kind)
{
    return kind == MedisaleMeasurementKindLegacyImageDistance
        ? @"legacy-image-distance" : nil;
}

static NSString *MedisaleLandmarkCode(MedisaleLandmarkIdentifier identifier)
{
    if (identifier == MedisaleLandmarkIdentifierEndpointA) return @"endpoint-a";
    if (identifier == MedisaleLandmarkIdentifierEndpointB) return @"endpoint-b";
    return nil;
}

static MedisaleLandmarkIdentifier MedisaleLandmarkFromCode(NSString *code)
{
    if ([code isEqualToString:@"endpoint-a"]) return MedisaleLandmarkIdentifierEndpointA;
    if ([code isEqualToString:@"endpoint-b"]) return MedisaleLandmarkIdentifierEndpointB;
    return 0;
}

static NSString *MedisaleUnitCode(MedisaleMeasurementUnit unit)
{
    return unit == MedisaleMeasurementUnitPixels ? @"px" : nil;
}

static NSString *MedisaleValidityCode(MedisaleMeasurementValidity validity)
{
    return validity == MedisaleMeasurementValidityValid ? @"valid" : nil;
}

static NSString *MedisaleWarningCode(MedisaleMeasurementWarningCode warning)
{
    switch (warning) {
        case MedisaleMeasurementWarningCalibrationUnknown:
            return @"calibration-unknown";
        case MedisaleMeasurementWarningRuntimeSpacingUncalibrated:
            return @"runtime-spacing-uncalibrated";
        case MedisaleMeasurementWarningTagProvenanceUnverified:
            return @"tag-provenance-unverified";
    }
    return nil;
}

static MedisaleMeasurementWarningCode MedisaleWarningFromCode(NSString *code)
{
    if ([code isEqualToString:@"calibration-unknown"])
        return MedisaleMeasurementWarningCalibrationUnknown;
    if ([code isEqualToString:@"runtime-spacing-uncalibrated"])
        return MedisaleMeasurementWarningRuntimeSpacingUncalibrated;
    if ([code isEqualToString:@"tag-provenance-unverified"])
        return MedisaleMeasurementWarningTagProvenanceUnverified;
    return 0;
}

@interface MeasurementPersistenceDTO ()
- (instancetype)initWithMeasurementID:(NSString *)measurementID
                        domainSnapshot:(MeasurementDomainSnapshot *)domainSnapshot
                             createdAt:(NSDate *)createdAt
                             updatedAt:(NSDate *)updatedAt;
@end

@implementation MeasurementPersistenceDTO
- (instancetype)initWithMeasurementID:(NSString *)measurementID
                        domainSnapshot:(MeasurementDomainSnapshot *)domainSnapshot
                             createdAt:(NSDate *)createdAt
                             updatedAt:(NSDate *)updatedAt
{
    self = [super init];
    if (self) {
        _dtoVersion = MedisaleMeasurementPersistenceDTOVersion;
        _measurementID = [measurementID copy];
        _domainSnapshot = [domainSnapshot copy];
        _createdAt = [createdAt copy];
        _updatedAt = [updatedAt copy];
    }
    return self;
}

+ (instancetype)DTOWithMeasurementID:(NSString *)measurementID
                        domainSnapshot:(MeasurementDomainSnapshot *)domainSnapshot
                             createdAt:(NSDate *)createdAt
                             updatedAt:(NSDate *)updatedAt
                                 error:(NSError **)error
{
    double created = createdAt.timeIntervalSince1970;
    double updated = updatedAt.timeIntervalSince1970;
    if (!MedisaleDTOIdentifier(measurementID) || domainSnapshot == nil ||
        createdAt == nil || updatedAt == nil || !isfinite(created) ||
        !isfinite(updated) || updated < created) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidEnvelope,
            @"The persistence DTO envelope is incomplete or invalid.");
        return nil;
    }
    return [[self alloc] initWithMeasurementID:measurementID
        domainSnapshot:domainSnapshot createdAt:createdAt updatedAt:updatedAt];
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation
{
    NamedLandmarkSnapshot *landmarks = self.domainSnapshot.landmarkSnapshot;
    MeasurementMethodDefinition *method = landmarks.method;
    MeasurementImageContext *context = landmarks.imageContext;
    NSMutableArray *landmarkValues = [NSMutableArray array];
    for (NamedImageLandmark *landmark in landmarks.landmarks) {
        [landmarkValues addObject:@{
            @"id": MedisaleLandmarkCode(landmark.identifier),
            @"x": @(landmark.imagePoint.x),
            @"y": @(landmark.imagePoint.y),
        }];
    }
    NSMutableArray *warnings = [NSMutableArray array];
    for (NSNumber *warning in self.domainSnapshot.result.warningCodes) {
        [warnings addObject:MedisaleWarningCode(warning.integerValue)];
    }
    NSDictionary *domain = @{
        @"schemaVersion": @(MedisaleMeasurementDomainSchemaVersion),
        @"method": @{
            @"kind": MedisaleKindCode(method.kind),
            @"identifier": method.stableIdentifier,
            @"version": @(method.version),
        },
        @"context": @{
            @"study": context.studyInstanceUID,
            @"series": context.seriesInstanceUID,
            @"sop": context.sopInstanceUID,
            @"frame": @(context.frameNumber),
            @"width": @(context.pixelWidth),
            @"height": @(context.pixelHeight),
        },
        @"landmarks": landmarkValues,
        @"result": @{
            @"rawValue": @(self.domainSnapshot.result.rawValue),
            @"unit": MedisaleUnitCode(self.domainSnapshot.result.unit),
            @"validity": MedisaleValidityCode(self.domainSnapshot.result.validity),
            @"warnings": warnings,
            @"methodIdentifier": method.stableIdentifier,
            @"methodVersion": @(method.version),
        },
    };
    return @{
        @"dtoVersion": @(self.dtoVersion),
        @"measurementID": self.measurementID,
        @"createdAt": @(self.createdAt.timeIntervalSince1970),
        @"updatedAt": @(self.updatedAt.timeIntervalSince1970),
        @"domain": domain,
    };
}

- (NSData *)serializedDataWithError:(NSError **)error
{
    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.dictionaryRepresentation
        options:NSJSONWritingSortedKeys error:&serializationError];
    if (data == nil && error != NULL) {
        *error = [NSError errorWithDomain:MedisaleMeasurementDTOErrorDomain
            code:MedisaleMeasurementDTOErrorSerialization
            userInfo:@{NSLocalizedDescriptionKey:
                @"The persistence DTO could not be serialized."}];
    }
    return data;
}

+ (instancetype)DTOFromSerializedData:(NSData *)data error:(NSError **)error
{
    NSError *serializationError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0
        error:&serializationError];
    if (![object isKindOfClass:NSDictionary.class]) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorSerialization,
            @"The serialized persistence DTO is invalid.");
        return nil;
    }
    return [self DTOFromDictionary:object error:error];
}

+ (instancetype)DTOFromDictionary:(NSDictionary<NSString *,id> *)dictionary
                              error:(NSError **)error
{
    if (!MedisaleDTOExactKeys(dictionary,
            @[@"dtoVersion", @"measurementID", @"createdAt", @"updatedAt", @"domain"])) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidEnvelope,
            @"The persistence DTO envelope is incompatible.");
        return nil;
    }
    NSNumber *dtoVersion = dictionary[@"dtoVersion"];
    NSNumber *createdAt = dictionary[@"createdAt"];
    NSNumber *updatedAt = dictionary[@"updatedAt"];
    NSString *measurementID = dictionary[@"measurementID"];
    NSDictionary *domain = dictionary[@"domain"];
    if (!MedisaleDTOInteger(dtoVersion) ||
        dtoVersion.integerValue != MedisaleMeasurementPersistenceDTOVersion) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorUnsupportedVersion,
            @"The persistence DTO version is unsupported.");
        return nil;
    }
    if (!MedisaleDTOIdentifier(measurementID) || !MedisaleDTONumber(createdAt) ||
        !MedisaleDTONumber(updatedAt) || !isfinite(createdAt.doubleValue) ||
        !isfinite(updatedAt.doubleValue) ||
        !MedisaleDTOExactKeys(domain,
            @[@"schemaVersion", @"method", @"context", @"landmarks", @"result"])) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidEnvelope,
            @"The persistence DTO values are invalid.");
        return nil;
    }
    NSNumber *schema = domain[@"schemaVersion"];
    NSDictionary *methodValues = domain[@"method"];
    NSDictionary *contextValues = domain[@"context"];
    NSArray *landmarkValues = domain[@"landmarks"];
    NSDictionary *resultValues = domain[@"result"];
    if (!MedisaleDTOInteger(schema) ||
        schema.integerValue != MedisaleMeasurementDomainSchemaVersion ||
        !MedisaleDTOExactKeys(methodValues, @[@"kind", @"identifier", @"version"]) ||
        !MedisaleDTOExactKeys(contextValues,
            @[@"study", @"series", @"sop", @"frame", @"width", @"height"]) ||
        ![landmarkValues isKindOfClass:NSArray.class] ||
        !MedisaleDTOExactKeys(resultValues,
            @[@"rawValue", @"unit", @"validity", @"warnings",
              @"methodIdentifier", @"methodVersion"])) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
            @"The measurement domain schema is incompatible.");
        return nil;
    }
    NSString *kindCode = methodValues[@"kind"];
    NSString *methodIdentifier = methodValues[@"identifier"];
    NSNumber *methodVersion = methodValues[@"version"];
    if (![kindCode isEqualToString:@"legacy-image-distance"] ||
        ![methodIdentifier isEqualToString:@"image-distance"] ||
        !MedisaleDTOInteger(methodVersion)) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorUnsupportedVersion,
            @"The measurement method identity is unsupported.");
        return nil;
    }
    MeasurementMethodDefinition *method = [MeasurementMethodDefinition
        definitionForKind:MedisaleMeasurementKindLegacyImageDistance
        version:methodVersion.integerValue error:error];
    if (method == nil) return nil;

    NSString *study = contextValues[@"study"];
    NSString *series = contextValues[@"series"];
    NSString *sop = contextValues[@"sop"];
    NSNumber *frame = contextValues[@"frame"];
    NSNumber *width = contextValues[@"width"];
    NSNumber *height = contextValues[@"height"];
    if (!MedisaleDTOInteger(frame) || !MedisaleDTOInteger(width) ||
        !MedisaleDTOInteger(height)) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
            @"The image context numbers are invalid.");
        return nil;
    }
    MeasurementImageContext *context = [MeasurementImageContext
        contextWithStudyInstanceUID:study seriesInstanceUID:series
        sopInstanceUID:sop frameNumber:frame.integerValue
        pixelWidth:width.integerValue pixelHeight:height.integerValue error:error];
    if (context == nil) return nil;

    NSMutableArray<NamedImageLandmark *> *landmarks = [NSMutableArray array];
    for (id candidate in landmarkValues) {
        if (!MedisaleDTOExactKeys(candidate, @[@"id", @"x", @"y"])) {
            MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
                @"A named landmark DTO is incompatible.");
            return nil;
        }
        NSString *identifierCode = candidate[@"id"];
        NSNumber *x = candidate[@"x"];
        NSNumber *y = candidate[@"y"];
        MedisaleLandmarkIdentifier identifier = MedisaleLandmarkFromCode(identifierCode);
        if (identifier == 0 || !MedisaleDTONumber(x) || !MedisaleDTONumber(y)) {
            MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
                @"A named landmark DTO value is invalid.");
            return nil;
        }
        NamedImageLandmark *landmark = [NamedImageLandmark
            landmarkWithIdentifier:identifier imagePoint:NSMakePoint(x.doubleValue,
            y.doubleValue) error:error];
        if (landmark == nil) return nil;
        [landmarks addObject:landmark];
    }
    NamedLandmarkSnapshot *landmarkSnapshot = [NamedLandmarkSnapshot
        snapshotWithMethod:method imageContext:context landmarks:landmarks error:error];
    if (landmarkSnapshot == nil) return nil;

    NSNumber *rawValue = resultValues[@"rawValue"];
    NSString *unitCode = resultValues[@"unit"];
    NSString *validityCode = resultValues[@"validity"];
    NSArray *warningValues = resultValues[@"warnings"];
    NSString *resultMethodIdentifier = resultValues[@"methodIdentifier"];
    NSNumber *resultMethodVersion = resultValues[@"methodVersion"];
    if (!MedisaleDTONumber(rawValue) || ![unitCode isEqualToString:@"px"] ||
        ![validityCode isEqualToString:@"valid"] ||
        ![warningValues isKindOfClass:NSArray.class] ||
        ![resultMethodIdentifier isEqualToString:method.stableIdentifier] ||
        !MedisaleDTOInteger(resultMethodVersion) ||
        resultMethodVersion.integerValue != method.version) {
        MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
            @"The versioned measurement result is incompatible.");
        return nil;
    }
    NSMutableArray<NSNumber *> *warnings = [NSMutableArray array];
    for (id warningValue in warningValues) {
        if (![warningValue isKindOfClass:NSString.class]) {
            MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
                @"A measurement warning code is invalid.");
            return nil;
        }
        MedisaleMeasurementWarningCode warning = MedisaleWarningFromCode(warningValue);
        if (warning == 0) {
            MedisaleDTOSetError(error, MedisaleMeasurementDTOErrorInvalidDomain,
                @"A measurement warning code is unsupported.");
            return nil;
        }
        [warnings addObject:@(warning)];
    }
    VersionedMeasurementResult *result = [VersionedMeasurementResult
        resultWithMethod:method rawValue:rawValue.doubleValue
        unit:MedisaleMeasurementUnitPixels validity:MedisaleMeasurementValidityValid
        warningCodes:warnings error:error];
    if (result == nil) return nil;
    MeasurementDomainSnapshot *snapshot = [MeasurementDomainSnapshot
        snapshotWithLandmarks:landmarkSnapshot result:result error:error];
    if (snapshot == nil) return nil;
    return [self DTOWithMeasurementID:measurementID domainSnapshot:snapshot
        createdAt:[NSDate dateWithTimeIntervalSince1970:createdAt.doubleValue]
        updatedAt:[NSDate dateWithTimeIntervalSince1970:updatedAt.doubleValue]
        error:error];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end
