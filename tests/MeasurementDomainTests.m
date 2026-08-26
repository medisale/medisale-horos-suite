#import <Foundation/Foundation.h>

#import "ImageContext.h"
#import "LegacyDistanceMeasurementAdapter.h"
#import "MeasurementDomain.h"
#import "MeasurementPersistenceDTO.h"
#import "MeasurementRecord.h"
#import <math.h>

static NSUInteger assertionCount = 0;

static void Assert(BOOL condition, NSString *message)
{
    assertionCount++;
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static MeasurementImageContext *Context(void)
{
    NSError *error = nil;
    MeasurementImageContext *context = [MeasurementImageContext
        contextWithStudyInstanceUID:@"synthetic-study"
        seriesInstanceUID:@"synthetic-series" sopInstanceUID:@"synthetic-sop"
        frameNumber:0 pixelWidth:640 pixelHeight:480 error:&error];
    Assert(context != nil && error == nil, @"valid context accepted");
    return context;
}

static NamedImageLandmark *Landmark(MedisaleLandmarkIdentifier identifier,
                                    double x, double y)
{
    NSError *error = nil;
    NamedImageLandmark *landmark = [NamedImageLandmark
        landmarkWithIdentifier:identifier imagePoint:NSMakePoint(x, y) error:&error];
    Assert(landmark != nil && error == nil, @"valid named landmark accepted");
    return landmark;
}

static MeasurementDomainSnapshot *Snapshot(double bx, double by)
{
    MeasurementMethodDefinition *method =
        [MeasurementMethodDefinition legacyImageDistanceV1];
    NSError *error = nil;
    NamedLandmarkSnapshot *landmarks = [NamedLandmarkSnapshot
        snapshotWithMethod:method imageContext:Context() landmarks:@[
            Landmark(MedisaleLandmarkIdentifierEndpointB, bx, by),
            Landmark(MedisaleLandmarkIdentifierEndpointA, 10.25, 20.5)] error:&error];
    Assert(landmarks != nil && error == nil, @"complete landmark snapshot accepted");
    VersionedMeasurementResult *result = [VersionedMeasurementResult
        resultWithMethod:method rawValue:hypot(bx - 10.25, by - 20.5)
        unit:MedisaleMeasurementUnitPixels validity:MedisaleMeasurementValidityValid
        warningCodes:@[@(MedisaleMeasurementWarningCalibrationUnknown)] error:&error];
    Assert(result != nil && error == nil, @"valid raw result accepted");
    MeasurementDomainSnapshot *snapshot = [MeasurementDomainSnapshot
        snapshotWithLandmarks:landmarks result:result error:&error];
    Assert(snapshot != nil && error == nil, @"valid domain snapshot accepted");
    return snapshot;
}

static MeasurementPersistenceDTO *DTO(void)
{
    NSError *error = nil;
    MeasurementPersistenceDTO *DTO = [MeasurementPersistenceDTO
        DTOWithMeasurementID:@"synthetic-measurement-1"
        domainSnapshot:Snapshot(70.75, 90.125)
        createdAt:[NSDate dateWithTimeIntervalSince1970:1000.25]
        updatedAt:[NSDate dateWithTimeIntervalSince1970:1001.5] error:&error];
    Assert(DTO != nil && error == nil, @"valid DTO accepted");
    return DTO;
}

static NSMutableDictionary *MutableDTO(void)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:DTO().dictionaryRepresentation
        options:0 error:NULL];
    return [NSJSONSerialization JSONObjectWithData:data
        options:NSJSONReadingMutableContainers error:NULL];
}

static void RejectDTO(NSDictionary *dictionary, NSString *message)
{
    NSError *error = nil;
    Assert([MeasurementPersistenceDTO DTOFromDictionary:dictionary error:&error] == nil,
           message);
    Assert(error != nil, @"invalid DTO returns a bounded error");
}

static void TestMethodAndContextValidation(void)
{
    MeasurementMethodDefinition *method =
        [MeasurementMethodDefinition legacyImageDistanceV1];
    Assert(method.kind == MedisaleMeasurementKindLegacyImageDistance,
           @"stable measurement kind retained");
    Assert([method.stableIdentifier isEqualToString:@"image-distance"],
           @"stable method identifier does not use a class name");
    Assert(method.version == 1 && method.resultUnit == MedisaleMeasurementUnitPixels,
           @"method and result versions are explicit");
    Assert([method.requiredLandmarkIdentifiers isEqualToArray:@[@1, @2]],
           @"required landmarks are explicitly named identifiers");
    NSError *error = nil;
    Assert([MeasurementMethodDefinition definitionForKind:method.kind version:2
        error:&error] == nil && error != nil, @"future method version fails closed");
    error = nil;
    Assert([MeasurementMethodDefinition definitionForKind:99 version:1
        error:&error] == nil && error != nil, @"unknown method kind fails closed");

    NSArray *invalidContexts = @[
        @[@"s", @"r", @"i", @(-1), @(640), @(480)],
        @[@"s", @"r", @"i", @(0), @(0), @(480)],
        @[@"s", @"r", @"i", @(0), @(-1), @(480)],
        @[@"s", @"r", @"i", @(0), @(640), @(0)],
        @[@"", @"r", @"i", @(0), @(640), @(480)],
        @[@"s", @"unsafe/value", @"i", @(0), @(640), @(480)],
    ];
    for (NSArray *values in invalidContexts) {
        error = nil;
        MeasurementImageContext *context = [MeasurementImageContext
            contextWithStudyInstanceUID:values[0] seriesInstanceUID:values[1]
            sopInstanceUID:values[2] frameNumber:[values[3] integerValue]
            pixelWidth:[values[4] integerValue] pixelHeight:[values[5] integerValue]
            error:&error];
        Assert(context == nil && error != nil, @"invalid context fails closed");
    }
}

static void TestNamedLandmarks(void)
{
    MeasurementMethodDefinition *method =
        [MeasurementMethodDefinition legacyImageDistanceV1];
    MeasurementImageContext *context = Context();
    NamedImageLandmark *a = Landmark(MedisaleLandmarkIdentifierEndpointA, 1, 2);
    NamedImageLandmark *b = Landmark(MedisaleLandmarkIdentifierEndpointB, 3, 4);
    NSMutableArray *callerOwned = [NSMutableArray arrayWithObjects:b, a, nil];
    NSError *error = nil;
    NamedLandmarkSnapshot *snapshot = [NamedLandmarkSnapshot
        snapshotWithMethod:method imageContext:context landmarks:callerOwned error:&error];
    Assert(snapshot != nil && error == nil, @"order-independent named set accepted");
    Assert(snapshot.landmarks.firstObject.identifier ==
        MedisaleLandmarkIdentifierEndpointA, @"snapshot canonicalizes by identifier");
    [callerOwned removeAllObjects];
    Assert(snapshot.landmarks.count == 2, @"snapshot is immutable from caller array");
    Assert([snapshot landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointB].imagePoint.x == 3,
           @"landmarks are addressed by name rather than input order");

    error = nil;
    Assert([NamedLandmarkSnapshot snapshotWithMethod:method imageContext:context
        landmarks:@[a] error:&error] == nil && error != nil,
        @"missing landmark rejected");
    error = nil;
    Assert([NamedLandmarkSnapshot snapshotWithMethod:method imageContext:context
        landmarks:@[a, a] error:&error] == nil && error != nil,
        @"duplicate landmark rejected");
    error = nil;
    Assert([NamedImageLandmark landmarkWithIdentifier:99 imagePoint:NSZeroPoint
        error:&error] == nil && error != nil, @"unknown landmark identifier rejected");
    for (NSValue *value in @[
        [NSValue valueWithPoint:NSMakePoint(NAN, 1)],
        [NSValue valueWithPoint:NSMakePoint(1, INFINITY)],
        [NSValue valueWithPoint:NSMakePoint(-1, 1)],
        [NSValue valueWithPoint:NSMakePoint(640, 1)],
        [NSValue valueWithPoint:NSMakePoint(1, 480)]]) {
        error = nil;
        NamedImageLandmark *candidate = [NamedImageLandmark
            landmarkWithIdentifier:MedisaleLandmarkIdentifierEndpointB
            imagePoint:value.pointValue error:&error];
        if (candidate == nil) {
            Assert(error != nil, @"non-finite point rejected before set creation");
        } else {
            Assert([NamedLandmarkSnapshot snapshotWithMethod:method imageContext:context
                landmarks:@[a, candidate] error:&error] == nil && error != nil,
                @"out-of-bounds point rejected by image context");
        }
    }
}

static void TestResultValidation(void)
{
    MeasurementMethodDefinition *method =
        [MeasurementMethodDefinition legacyImageDistanceV1];
    NSError *error = nil;
    for (NSNumber *value in @[@(NAN), @(INFINITY), @(-1.0)]) {
        error = nil;
        Assert([VersionedMeasurementResult resultWithMethod:method
            rawValue:value.doubleValue unit:MedisaleMeasurementUnitPixels
            validity:MedisaleMeasurementValidityValid warningCodes:@[]
            error:&error] == nil && error != nil, @"invalid raw result rejected");
    }
    error = nil;
    Assert([VersionedMeasurementResult resultWithMethod:method rawValue:1
        unit:99 validity:MedisaleMeasurementValidityValid warningCodes:@[]
        error:&error] == nil && error != nil, @"unsupported unit rejected");
    error = nil;
    Assert([VersionedMeasurementResult resultWithMethod:method rawValue:1
        unit:MedisaleMeasurementUnitPixels validity:99 warningCodes:@[]
        error:&error] == nil && error != nil, @"unsupported validity rejected");
    error = nil;
    Assert([VersionedMeasurementResult resultWithMethod:method rawValue:1
        unit:MedisaleMeasurementUnitPixels validity:MedisaleMeasurementValidityValid
        warningCodes:@[@1, @1] error:&error] == nil && error != nil,
        @"duplicate warning rejected");
    error = nil;
    Assert([VersionedMeasurementResult resultWithMethod:method rawValue:1
        unit:MedisaleMeasurementUnitPixels validity:MedisaleMeasurementValidityValid
        warningCodes:@[@99] error:&error] == nil && error != nil,
        @"unknown warning rejected");

    NamedLandmarkSnapshot *landmarks = Snapshot(30, 40).landmarkSnapshot;
    VersionedMeasurementResult *mismatch = [VersionedMeasurementResult
        resultWithMethod:method rawValue:1 unit:MedisaleMeasurementUnitPixels
        validity:MedisaleMeasurementValidityValid warningCodes:@[] error:&error];
    error = nil;
    Assert([MeasurementDomainSnapshot snapshotWithLandmarks:landmarks result:mismatch
        error:&error] == nil && error != nil,
        @"raw result cannot diverge from actual endpoint input");
}

static void TestDTO(void)
{
    MeasurementPersistenceDTO *DTOValue = DTO();
    NSError *error = nil;
    NSData *first = [DTOValue serializedDataWithError:&error];
    NSData *second = [DTOValue serializedDataWithError:&error];
    Assert(first != nil && [first isEqualToData:second],
           @"serialization is deterministic");
    MeasurementPersistenceDTO *restored = [MeasurementPersistenceDTO
        DTOFromSerializedData:first error:&error];
    Assert(restored != nil && error == nil, @"serialized DTO round trip succeeds");
    Assert(restored.domainSnapshot.result.rawValue ==
        DTOValue.domainSnapshot.result.rawValue, @"raw unrounded value round trips exactly");
    NSDictionary *resultDictionary = restored.dictionaryRepresentation[@"domain"][@"result"];
    Assert(resultDictionary[@"display"] == nil &&
        resultDictionary[@"formattedValue"] == nil,
        @"display presentation is not stored with raw result");

    NSDictionary *original = DTOValue.dictionaryRepresentation;
    NSMutableDictionary *reordered = [NSMutableDictionary dictionary];
    for (NSString *key in [original.allKeys reverseObjectEnumerator]) {
        reordered[key] = original[key];
    }
    error = nil;
    Assert([MeasurementPersistenceDTO DTOFromDictionary:reordered error:&error] != nil &&
        error == nil, @"dictionary field order is irrelevant");

    NSMutableDictionary *bad = MutableDTO();
    bad[@"dtoVersion"] = @2;
    RejectDTO(bad, @"future DTO version rejected");
    bad = MutableDTO();
    bad[@"domain"][@"schemaVersion"] = @2;
    RejectDTO(bad, @"future domain schema rejected");
    bad = MutableDTO();
    bad[@"domain"][@"method"][@"version"] = @2;
    RejectDTO(bad, @"future method version rejected");
    bad = MutableDTO();
    bad[@"domain"][@"method"][@"kind"] = @"unknown-kind";
    RejectDTO(bad, @"unknown measurement kind rejected");
    bad = MutableDTO();
    bad[@"domain"][@"result"][@"unit"] = @"unsupported";
    RejectDTO(bad, @"unsupported unit DTO rejected");
    bad = MutableDTO();
    bad[@"domain"][@"result"][@"warnings"] = @[@"../../private/path"];
    RejectDTO(bad, @"unsafe arbitrary warning rejected");
    bad = MutableDTO();
    [bad removeObjectForKey:@"measurementID"];
    RejectDTO(bad, @"partial DTO rejected");
    bad = MutableDTO();
    bad[@"unexpected"] = @1;
    RejectDTO(bad, @"unknown DTO field rejected");
    bad = MutableDTO();
    bad[@"dtoVersion"] = @YES;
    RejectDTO(bad, @"boolean version rejected");
    bad = MutableDTO();
    bad[@"domain"][@"landmarks"][0][@"id"] = @"unknown-landmark";
    RejectDTO(bad, @"unknown named landmark DTO rejected");
    bad = MutableDTO();
    [bad[@"domain"][@"landmarks"] removeLastObject];
    RejectDTO(bad, @"missing named landmark DTO rejected");
    bad = MutableDTO();
    bad[@"domain"][@"landmarks"][1][@"id"] =
        bad[@"domain"][@"landmarks"][0][@"id"];
    RejectDTO(bad, @"duplicate named landmark DTO rejected");
    bad = MutableDTO();
    bad[@"domain"][@"context"][@"frame"] = @(-1);
    RejectDTO(bad, @"negative frame DTO rejected");
    bad = MutableDTO();
    bad[@"domain"][@"context"][@"width"] = @0;
    RejectDTO(bad, @"non-positive dimension DTO rejected");
    bad = MutableDTO();
    bad[@"domain"][@"landmarks"][0][@"x"] = @640;
    RejectDTO(bad, @"out-of-bounds landmark DTO rejected");
}

static void TestLegacyCompatibility(void)
{
    ImageContext *context = [[ImageContext alloc]
        initWithStudyInstanceUID:@"synthetic-study"
        seriesInstanceUID:@"synthetic-series" sopInstanceUID:@"synthetic-sop"
        frameNumber:0 pixelWidth:640 pixelHeight:480
        pixelSpacingX:0.25 pixelSpacingY:0.5];
    double raw = hypot(50.125 - 10.25, 80.75 - 20.5);
    MeasurementRecord *record = [[MeasurementRecord alloc]
        initWithMeasurementID:@"legacy-distance-1" imageContext:context
        endpointAX:10.25 endpointAY:20.5 endpointBX:50.125 endpointBY:80.75
        pixelDistance:raw schemaVersion:MedisaleMeasurementSchemaVersion
        createdAt:[NSDate dateWithTimeIntervalSince1970:10]
        updatedAt:[NSDate dateWithTimeIntervalSince1970:11]];
    NSError *error = nil;
    MeasurementPersistenceDTO *DTOValue = [LegacyDistanceMeasurementAdapter
        DTOFromRecord:record error:&error];
    Assert(DTOValue != nil && error == nil, @"legacy record converts to typed DTO");
    Assert([DTOValue.domainSnapshot.landmarkSnapshot
        landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointA].imagePoint.x == 10.25,
        @"legacy A converts by explicit name");
    Assert([DTOValue.domainSnapshot.landmarkSnapshot
        landmarkForIdentifier:MedisaleLandmarkIdentifierEndpointB].imagePoint.y == 80.75,
        @"legacy B converts by explicit name");
    Assert(DTOValue.domainSnapshot.result.rawValue == raw,
        @"legacy conversion does not round or alter raw value");
    MeasurementRecord *restored = [LegacyDistanceMeasurementAdapter
        recordFromDTO:DTOValue restorationContext:context error:&error];
    Assert(restored != nil && error == nil, @"typed DTO restores legacy record");
    Assert(restored.pixelDistance == record.pixelDistance &&
        restored.endpointAX == record.endpointAX && restored.endpointBY == record.endpointBY,
        @"legacy save and restore is exact");
    Assert(restored.imageContext.pixelSpacingX == context.pixelSpacingX,
        @"restoration retains current context calibration boundary");

    ImageContext *other = [[ImageContext alloc]
        initWithStudyInstanceUID:@"synthetic-study"
        seriesInstanceUID:@"synthetic-series" sopInstanceUID:@"different-sop"
        frameNumber:0 pixelWidth:640 pixelHeight:480
        pixelSpacingX:0.25 pixelSpacingY:0.5];
    error = nil;
    Assert([LegacyDistanceMeasurementAdapter recordFromDTO:DTOValue
        restorationContext:other error:&error] == nil && error != nil,
        @"legacy DTO is never applied to another image");

    MeasurementRecord *future = [[MeasurementRecord alloc]
        initWithMeasurementID:@"future" imageContext:context
        endpointAX:10 endpointAY:20 endpointBX:30 endpointBY:40
        pixelDistance:hypot(20, 20) schemaVersion:2
        createdAt:[NSDate dateWithTimeIntervalSince1970:10]
        updatedAt:[NSDate dateWithTimeIntervalSince1970:11]];
    error = nil;
    Assert([LegacyDistanceMeasurementAdapter DTOFromRecord:future error:&error] == nil &&
        error != nil, @"future legacy schema fails closed without upgrade");
}

static void TestCalibrationAndConfirmationAssociation(void)
{
    NSError *error = nil;
    MeasurementCalibrationReference *unknown = [MeasurementCalibrationReference
        referenceWithState:MedisaleMeasurementCalibrationStateUnknown
        provenance:MedisaleMeasurementCalibrationProvenanceNone schemaVersion:1
        methodVersion:1 rowSpacing:NAN columnSpacing:NAN error:&error];
    Assert(unknown != nil && error == nil, @"unknown calibration is explicit and valid");
    MeasurementCalibrationReference *runtime = [MeasurementCalibrationReference
        referenceWithState:MedisaleMeasurementCalibrationStateRuntimeSpacingUncalibrated
        provenance:MedisaleMeasurementCalibrationProvenanceHorosRuntimeSpacing
        schemaVersion:1 methodVersion:1 rowSpacing:0.4 columnSpacing:0.2 error:&error];
    Assert(runtime != nil && error == nil, @"runtime spacing remains uncalibrated");
    MeasurementCalibrationReference *explicitCalibration = [MeasurementCalibrationReference
        referenceWithState:MedisaleMeasurementCalibrationStateExplicit
        provenance:MedisaleMeasurementCalibrationProvenanceExplicit schemaVersion:1
        methodVersion:1 rowSpacing:0.3 columnSpacing:0.3 error:&error];
    Assert(explicitCalibration != nil && error == nil,
        @"explicit calibration provenance accepted");

    error = nil;
    Assert([MeasurementCalibrationReference
        referenceWithState:MedisaleMeasurementCalibrationStateRuntimeSpacingUncalibrated
        provenance:MedisaleMeasurementCalibrationProvenanceExplicit schemaVersion:1
        methodVersion:1 rowSpacing:0.4 columnSpacing:0.2 error:&error] == nil &&
        error != nil, @"calibration state and provenance mismatch rejected");
    error = nil;
    Assert([MeasurementCalibrationReference
        referenceWithState:MedisaleMeasurementCalibrationStateExplicit
        provenance:MedisaleMeasurementCalibrationProvenanceExplicit schemaVersion:2
        methodVersion:1 rowSpacing:0.3 columnSpacing:0.3 error:&error] == nil &&
        error != nil, @"future calibration schema rejected");
    error = nil;
    Assert([MeasurementCalibrationReference
        referenceWithState:MedisaleMeasurementCalibrationStateExplicit
        provenance:MedisaleMeasurementCalibrationProvenanceExplicit schemaVersion:1
        methodVersion:2 rowSpacing:0.3 columnSpacing:0.3 error:&error] == nil &&
        error != nil, @"future calibration method rejected");

    MeasurementReviewAssociation *first = [MeasurementReviewAssociation
        associationWithSnapshot:Snapshot(70, 90) calibration:unknown error:&error];
    MeasurementReviewAssociation *same = [MeasurementReviewAssociation
        associationWithSnapshot:Snapshot(70, 90) calibration:unknown error:&error];
    Assert([first hasSameInputsAsAssociation:same],
        @"same domain and calibration inputs retain confirmation fingerprint");
    Assert(first.inputFingerprint.length == 16 &&
        [first.inputFingerprint rangeOfString:@"synthetic"].location == NSNotFound,
        @"public confirmation fingerprint is opaque and contains no image identity");
    MeasurementReviewAssociation *endpointChanged = [MeasurementReviewAssociation
        associationWithSnapshot:Snapshot(71, 90) calibration:unknown error:&error];
    Assert(![first hasSameInputsAsAssociation:endpointChanged],
        @"real endpoint and result change invalidates confirmation fingerprint");
    MeasurementReviewAssociation *calibrationChanged = [MeasurementReviewAssociation
        associationWithSnapshot:Snapshot(70, 90) calibration:runtime error:&error];
    Assert(![first hasSameInputsAsAssociation:calibrationChanged],
        @"real calibration change invalidates confirmation fingerprint");
    Assert(first.snapshot.result.rawValue == same.snapshot.result.rawValue,
        @"confirmation comparison never fabricates a raw numeric change");
}

int main(void)
{
    @autoreleasepool {
        TestMethodAndContextValidation();
        TestNamedLandmarks();
        TestResultValidation();
        TestDTO();
        TestLegacyCompatibility();
        TestCalibrationAndConfirmationAssociation();
        NSLog(@"PASS: %lu measurement domain assertions", (unsigned long)assertionCount);
    }
    return 0;
}
