#import "LegacyDistanceMeasurementAdapter.h"

#import "ImageContext.h"
#import "MeasurementDomain.h"
#import "MeasurementPersistenceDTO.h"
#import "MeasurementRecord.h"

@implementation LegacyDistanceMeasurementAdapter

+ (MeasurementPersistenceDTO *)DTOFromRecord:(MeasurementRecord *)record
                                        error:(NSError **)error
{
    if (record == nil || record.schemaVersion != MedisaleMeasurementSchemaVersion) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MedisaleMeasurementDTOErrorDomain code:20
                userInfo:@{NSLocalizedDescriptionKey:
                    @"The legacy record schema is unsupported."}];
        }
        return nil;
    }
    ImageContext *legacyContext = record.imageContext;
    MeasurementImageContext *context = [MeasurementImageContext
        contextWithStudyInstanceUID:legacyContext.studyInstanceUID
        seriesInstanceUID:legacyContext.seriesInstanceUID
        sopInstanceUID:legacyContext.sopInstanceUID
        frameNumber:legacyContext.frameNumber pixelWidth:legacyContext.pixelWidth
        pixelHeight:legacyContext.pixelHeight error:error];
    if (context == nil) return nil;
    MeasurementMethodDefinition *method =
        [MeasurementMethodDefinition legacyImageDistanceV1];
    NamedImageLandmark *a = [NamedImageLandmark
        landmarkWithIdentifier:MedisaleLandmarkIdentifierEndpointA
        imagePoint:NSMakePoint(record.endpointAX, record.endpointAY) error:error];
    NamedImageLandmark *b = [NamedImageLandmark
        landmarkWithIdentifier:MedisaleLandmarkIdentifierEndpointB
        imagePoint:NSMakePoint(record.endpointBX, record.endpointBY) error:error];
    if (a == nil || b == nil) return nil;
    NamedLandmarkSnapshot *landmarks = [NamedLandmarkSnapshot
        snapshotWithMethod:method imageContext:context landmarks:@[a, b] error:error];
    if (landmarks == nil) return nil;
    VersionedMeasurementResult *result = [VersionedMeasurementResult
        resultWithMethod:method rawValue:record.pixelDistance
        unit:MedisaleMeasurementUnitPixels validity:MedisaleMeasurementValidityValid
        warningCodes:@[] error:error];
    if (result == nil) return nil;
    MeasurementDomainSnapshot *snapshot = [MeasurementDomainSnapshot
        snapshotWithLandmarks:landmarks result:result error:error];
    if (snapshot == nil) return nil;
    return [MeasurementPersistenceDTO DTOWithMeasurementID:record.measurementID
        domainSnapshot:snapshot createdAt:record.createdAt updatedAt:record.updatedAt
        error:error];
}

+ (MeasurementRecord *)recordFromDTO:(MeasurementPersistenceDTO *)DTO
                    restorationContext:(ImageContext *)restorationContext
                                 error:(NSError **)error
{
    MeasurementDomainSnapshot *snapshot = DTO.domainSnapshot;
    MeasurementImageContext *context = snapshot.landmarkSnapshot.imageContext;
    BOOL contextMatches = restorationContext != nil &&
        [context.studyInstanceUID isEqualToString:restorationContext.studyInstanceUID] &&
        [context.seriesInstanceUID isEqualToString:restorationContext.seriesInstanceUID] &&
        [context.sopInstanceUID isEqualToString:restorationContext.sopInstanceUID] &&
        context.frameNumber == restorationContext.frameNumber &&
        context.pixelWidth == restorationContext.pixelWidth &&
        context.pixelHeight == restorationContext.pixelHeight;
    MeasurementMethodDefinition *method = snapshot.landmarkSnapshot.method;
    if (DTO == nil || !contextMatches ||
        method.kind != MedisaleMeasurementKindLegacyImageDistance ||
        method.version != MedisaleLegacyDistanceMethodVersion ||
        snapshot.result.unit != MedisaleMeasurementUnitPixels ||
        snapshot.result.validity != MedisaleMeasurementValidityValid) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MedisaleMeasurementDTOErrorDomain code:21
                userInfo:@{NSLocalizedDescriptionKey:
                    @"The DTO cannot be restored as a legacy distance record."}];
        }
        return nil;
    }
    NamedImageLandmark *a = [snapshot.landmarkSnapshot
        landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointA];
    NamedImageLandmark *b = [snapshot.landmarkSnapshot
        landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointB];
    if (a == nil || b == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MedisaleMeasurementDTOErrorDomain code:22
                userInfo:@{NSLocalizedDescriptionKey:
                    @"The legacy endpoint landmarks are incomplete."}];
        }
        return nil;
    }
    return [[MeasurementRecord alloc] initWithMeasurementID:DTO.measurementID
        imageContext:restorationContext endpointAX:a.imagePoint.x
        endpointAY:a.imagePoint.y endpointBX:b.imagePoint.x endpointBY:b.imagePoint.y
        pixelDistance:snapshot.result.rawValue
        schemaVersion:MedisaleMeasurementSchemaVersion createdAt:DTO.createdAt
        updatedAt:DTO.updatedAt];
}

+ (MeasurementRecord *)canonicalRecordFromRecord:(MeasurementRecord *)record
                                             error:(NSError **)error
{
    MeasurementPersistenceDTO *DTO = [self DTOFromRecord:record error:error];
    if (DTO == nil) return nil;
    return [self recordFromDTO:DTO restorationContext:record.imageContext error:error];
}

@end
