#import <Cocoa/Cocoa.h>

#import "CalibrationConfirmationState.h"
#import "ImageContext.h"
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

static ImageContext *Context(NSString *study, NSString *series, NSString *sop,
                             NSInteger frame, double spacingX, double spacingY)
{
    return [[ImageContext alloc] initWithStudyInstanceUID:study
        seriesInstanceUID:series sopInstanceUID:sop frameNumber:frame
        pixelWidth:640 pixelHeight:480 pixelSpacingX:spacingX
        pixelSpacingY:spacingY];
}

static MeasurementReviewSnapshot *Snapshot(ImageContext *identity,
    CalibrationProvenanceModel *calibration, NSPoint a, NSPoint b,
    double result, NSString *method, NSString *rounding, NSInteger schema)
{
    return [[MeasurementReviewSnapshot alloc] initWithImageIdentity:identity
        pointA:a pointB:b calibration:calibration
        calculationMethodVersion:method rawResult:result
        displayRoundingPolicyVersion:rounding displayPrecision:2
        modelSchemaVersion:schema];
}

static void TestCalibrationStates(void)
{
    ImageContext *anisotropicContext = Context(@"study-a", @"series-a", @"sop-a",
                                                0, 0.4, 0.2);
    CalibrationProvenanceModel *dicom =
        [CalibrationProvenanceModel modelFromImageContext:anisotropicContext];
    Assert(dicom.state == MedisaleCalibrationStateDICOMSpacingOnly,
           @"valid ImageContext is DICOM spacing only");
    Assert(dicom.sourceCategory == MedisaleCalibrationSourceCategoryDICOMDerived,
           @"DICOM source category retained");
    Assert(dicom.derivationStatus == MedisaleCalibrationDerivationStatusDICOMDerived,
           @"DICOM derivation retained");
    Assert([dicom.sourceIdentifier isEqualToString:@"dicom-pixel-spacing"],
           @"DICOM source identifier explicit");
    Assert([dicom.methodVersion isEqualToString:@"image-context-v1"],
           @"DICOM method version explicit");
    Assert(dicom.rowSpacing == 0.2, @"row spacing uses ImageContext Y");
    Assert(dicom.columnSpacing == 0.4, @"column spacing uses ImageContext X");
    Assert([dicom.units isEqualToString:@"mm"], @"spacing units retained");
    Assert(dicom.hasUsableSpacing, @"anisotropic spacing remains usable");
    Assert([dicom.warnings containsObject:@"anisotropic-spacing"],
           @"anisotropic warning retained");
    double distance = [dicom physicalDistanceForPointA:NSMakePoint(1, 1)
                                                 pointB:NSMakePoint(4, 5)];
    Assert(fabs(distance - hypot(1.2, 0.8)) < 1e-12,
           @"row and column spacing applied independently");

    NSError *error = nil;
    CalibrationProvenanceModel *calibrated =
        [CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic-ruler"
            methodVersion:@"method-v1" rowSpacing:0.25 columnSpacing:0.25
            error:&error];
    Assert(calibrated != nil && error == nil, @"explicit calibrated fixture accepted");
    Assert(calibrated.state == MedisaleCalibrationStateCalibrated,
           @"explicit source is calibrated");
    Assert(calibrated.sourceCategory ==
           MedisaleCalibrationSourceCategoryExplicitCalibration,
           @"explicit source category retained");
    Assert(calibrated.derivationStatus == MedisaleCalibrationDerivationStatusExplicit,
           @"explicit derivation retained");
    Assert(calibrated.hasUsableSpacing, @"explicit calibrated spacing usable");

    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@""
        methodVersion:@"method-v1" rowSpacing:0.25 columnSpacing:0.25
        error:&error] == nil && error != nil, @"missing provenance rejected");
    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"local/path"
        methodVersion:@"method-v1" rowSpacing:0.25 columnSpacing:0.25
        error:&error] == nil && error != nil, @"path-like provenance rejected");
    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic"
        methodVersion:@"" rowSpacing:0.25 columnSpacing:0.25
        error:&error] == nil && error != nil, @"missing method version rejected");
    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic"
        methodVersion:@"method-v1" rowSpacing:0.0 columnSpacing:0.25
        error:&error] == nil && error != nil, @"zero row rejected");
    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic"
        methodVersion:@"method-v1" rowSpacing:0.25 columnSpacing:-1.0
        error:&error] == nil && error != nil, @"negative column rejected");
    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic"
        methodVersion:@"method-v1" rowSpacing:NAN columnSpacing:0.25
        error:&error] == nil && error != nil, @"NaN row rejected");
    error = nil;
    Assert([CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic"
        methodVersion:@"method-v1" rowSpacing:0.25 columnSpacing:INFINITY
        error:&error] == nil && error != nil, @"infinite column rejected");

    NSArray<ImageContext *> *unknownContexts = @[
        Context(@"s", @"r", @"zero-x", 0, 0.0, 0.2),
        Context(@"s", @"r", @"zero-y", 0, 0.2, 0.0),
        Context(@"s", @"r", @"negative", 0, -0.2, 0.2),
        Context(@"s", @"r", @"nan", 0, NAN, 0.2),
        Context(@"s", @"r", @"infinity", 0, 0.2, INFINITY),
    ];
    for (ImageContext *context in unknownContexts) {
        CalibrationProvenanceModel *unknown =
            [CalibrationProvenanceModel modelFromImageContext:context];
        Assert(unknown.state == MedisaleCalibrationStateUnknown,
               @"invalid or one-axis spacing is unknown");
        Assert(!unknown.hasUsableSpacing, @"unknown spacing is not usable");
        Assert(isnan([unknown physicalDistanceForPointA:NSZeroPoint
                                                  pointB:NSMakePoint(1, 1)]),
               @"unknown spacing has no physical distance");
        Assert(unknown.warnings.count > 0, @"unknown state explains why");
    }

    NSDictionary *serialized = [dicom dictionaryRepresentation];
    error = nil;
    CalibrationProvenanceModel *restored =
        [CalibrationProvenanceModel modelFromDictionary:serialized error:&error];
    Assert(restored != nil && error == nil, @"calibration round-trip succeeds");
    Assert([dicom isEquivalentToModel:restored], @"round-trip calibration equivalent");
    NSMutableDictionary *badSchema = [serialized mutableCopy];
    badSchema[@"modelSchemaVersion"] = @(MedisaleCalibrationModelSchemaVersion + 1);
    error = nil;
    Assert([CalibrationProvenanceModel modelFromDictionary:badSchema error:&error] == nil,
           @"incompatible calibration schema rejected");
    Assert(error != nil, @"incompatible schema reports reason");
    NSMutableDictionary *silentUpgrade = [[CalibrationProvenanceModel
        unknownModelWithWarnings:@[@"unknown"]].dictionaryRepresentation mutableCopy];
    silentUpgrade[@"state"] = @(MedisaleCalibrationStateCalibrated);
    error = nil;
    Assert([CalibrationProvenanceModel modelFromDictionary:silentUpgrade
        error:&error] == nil, @"unknown provenance cannot decode as calibrated");
    Assert(error != nil, @"silent calibration upgrade reports reason");
}

static void TestConfirmationTransitions(void)
{
    ImageContext *identity = Context(@"study-a", @"series-a", @"sop-a", 0,
                                     0.4, 0.2);
    CalibrationProvenanceModel *dicom =
        [CalibrationProvenanceModel modelFromImageContext:identity];
    MeasurementReviewSnapshot *original = Snapshot(identity, dicom,
        NSMakePoint(10, 20), NSMakePoint(30, 50), 36.05551275463989,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion);
    ConfirmationStateModel *confirmation = [[ConfirmationStateModel alloc] init];
    Assert(confirmation.state == MedisaleConfirmationStateUnreviewed,
           @"initial confirmation unreviewed");
    Assert(![confirmation confirmCurrentSnapshot], @"cannot confirm without snapshot");
    [confirmation updateCurrentSnapshot:original];
    Assert(confirmation.state == MedisaleConfirmationStateUnreviewed,
           @"new snapshot remains unreviewed");
    Assert([confirmation confirmCurrentSnapshot], @"explicit confirm succeeds");
    Assert(confirmation.state == MedisaleConfirmationStateUserConfirmed,
           @"explicit confirm state");
    Assert(confirmation.confirmedSnapshot == original,
           @"exact independent snapshot bound");
    Assert(confirmation.currentSnapshot.calibration.state ==
           MedisaleCalibrationStateDICOMSpacingOnly,
           @"confirmation does not upgrade calibration");

    NSError *error = nil;
    MeasurementReviewSnapshot *restored = [MeasurementReviewSnapshot
        snapshotFromDictionary:[original dictionaryRepresentation] error:&error];
    Assert(restored != nil && error == nil, @"snapshot round-trip succeeds");
    Assert([original isEquivalentToSnapshot:restored], @"restored snapshot equivalent");
    [confirmation updateCurrentSnapshot:restored];
    Assert(confirmation.state == MedisaleConfirmationStateUserConfirmed,
           @"equivalent restored state remains confirmed");

    MeasurementReviewSnapshot *endpointChanged = Snapshot(identity, dicom,
        NSMakePoint(11, 20), original.pointB, original.rawResult + 0.5,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion);
    [confirmation updateCurrentSnapshot:endpointChanged];
    Assert(confirmation.state == MedisaleConfirmationStateModifiedAfterConfirmation,
           @"endpoint/result change marks modified");
    Assert([confirmation confirmCurrentSnapshot], @"modified state can be reconfirmed");
    Assert(confirmation.state == MedisaleConfirmationStateUserConfirmed,
           @"reconfirm returns confirmed");

    ImageContext *changedSpacingIdentity = Context(@"study-a", @"series-a", @"sop-a",
                                                    0, 0.5, 0.2);
    CalibrationProvenanceModel *changedSpacing =
        [CalibrationProvenanceModel modelFromImageContext:changedSpacingIdentity];
    MeasurementReviewSnapshot *spacingChanged = Snapshot(identity, changedSpacing,
        endpointChanged.pointA, endpointChanged.pointB, endpointChanged.rawResult,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion);
    [confirmation updateCurrentSnapshot:spacingChanged];
    Assert(confirmation.state == MedisaleConfirmationStateModifiedAfterConfirmation,
           @"spacing change marks modified");

    CalibrationProvenanceModel *explicitOne =
        [CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic-a"
            methodVersion:@"method-v1" rowSpacing:0.2 columnSpacing:0.5 error:nil];
    MeasurementReviewSnapshot *explicitSnapshot = Snapshot(identity, explicitOne,
        endpointChanged.pointA, endpointChanged.pointB, endpointChanged.rawResult,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion);
    ConfirmationStateModel *provenance = [[ConfirmationStateModel alloc] init];
    [provenance updateCurrentSnapshot:explicitSnapshot];
    Assert([provenance confirmCurrentSnapshot], @"explicit snapshot confirm");
    CalibrationProvenanceModel *explicitTwo =
        [CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic-b"
            methodVersion:@"method-v2" rowSpacing:0.2 columnSpacing:0.5 error:nil];
    [provenance updateCurrentSnapshot:Snapshot(identity, explicitTwo,
        explicitSnapshot.pointA, explicitSnapshot.pointB, explicitSnapshot.rawResult,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion)];
    Assert(provenance.state == MedisaleConfirmationStateModifiedAfterConfirmation,
           @"valid provenance/method change marks modified");
    Assert([provenance confirmCurrentSnapshot], @"changed provenance can be reviewed again");
    CalibrationProvenanceModel *unknown =
        [CalibrationProvenanceModel unknownModelWithWarnings:@[@"provenance-lost"]];
    [provenance updateCurrentSnapshot:Snapshot(identity, unknown,
        explicitSnapshot.pointA, explicitSnapshot.pointB, explicitSnapshot.rawResult,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion)];
    Assert(provenance.state == MedisaleConfirmationStateInvalidated,
           @"provenance loss invalidates confirmation");
    Assert(![provenance confirmCurrentSnapshot],
           @"invalidated state cannot be silently reconfirmed");

    NSArray<ImageContext *> *mismatches = @[
        Context(@"study-b", @"series-a", @"sop-a", 0, 0.4, 0.2),
        Context(@"study-a", @"series-b", @"sop-a", 0, 0.4, 0.2),
        Context(@"study-a", @"series-a", @"sop-b", 0, 0.4, 0.2),
        Context(@"study-a", @"series-a", @"sop-a", 1, 0.4, 0.2),
    ];
    for (ImageContext *mismatch in mismatches) {
        ConfirmationStateModel *bound = [[ConfirmationStateModel alloc] init];
        [bound updateCurrentSnapshot:original];
        Assert([bound confirmCurrentSnapshot], @"identity fixture confirmed");
        [bound updateCurrentSnapshot:Snapshot(mismatch,
            [CalibrationProvenanceModel modelFromImageContext:mismatch],
            original.pointA, original.pointB, original.rawResult,
            MedisaleDistanceCalculationMethodVersion,
            MedisaleDisplayRoundingPolicyVersion,
            MedisaleConfirmationModelSchemaVersion)];
        Assert(bound.state == MedisaleConfirmationStateInvalidated,
               @"Study/Series/SOP/frame mismatch invalidates");
    }

    ConfirmationStateModel *versioned = [[ConfirmationStateModel alloc] init];
    [versioned updateCurrentSnapshot:original];
    Assert([versioned confirmCurrentSnapshot], @"version fixture confirmed");
    [versioned updateCurrentSnapshot:Snapshot(identity, dicom, original.pointA,
        original.pointB, original.rawResult, @"distance-image-v2",
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion)];
    Assert(versioned.state == MedisaleConfirmationStateInvalidated,
           @"incompatible calculation method invalidates");

    ConfirmationStateModel *schema = [[ConfirmationStateModel alloc] init];
    [schema updateCurrentSnapshot:original];
    Assert([schema confirmCurrentSnapshot], @"schema fixture confirmed");
    MeasurementReviewSnapshot *incompatible = Snapshot(identity, dicom,
        original.pointA, original.pointB, original.rawResult,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion + 1);
    Assert(!incompatible.isStructurallyValid, @"incompatible schema structurally invalid");
    [schema updateCurrentSnapshot:incompatible];
    Assert(schema.state == MedisaleConfirmationStateInvalidated,
           @"incompatible model schema invalidates");

    ConfirmationStateModel *rounding = [[ConfirmationStateModel alloc] init];
    [rounding updateCurrentSnapshot:original];
    Assert([rounding confirmCurrentSnapshot], @"rounding fixture confirmed");
    [rounding updateCurrentSnapshot:Snapshot(identity, dicom, original.pointA,
        original.pointB, original.rawResult,
        MedisaleDistanceCalculationMethodVersion, @"fixed-decimal-v2",
        MedisaleConfirmationModelSchemaVersion)];
    Assert(rounding.state == MedisaleConfirmationStateModifiedAfterConfirmation,
           @"rounding policy version change marks modified");

    [rounding reset];
    Assert(rounding.state == MedisaleConfirmationStateUnreviewed,
           @"reset returns unreviewed");
    Assert(rounding.currentSnapshot == nil && rounding.confirmedSnapshot == nil,
           @"reset clears snapshots");
    [rounding invalidate];
    Assert(rounding.state == MedisaleConfirmationStateInvalidated,
           @"explicit invalidation state");
}

static void TestInternalAndDisplayValues(void)
{
    double raw = 12.345678901234;
    NSString *english = [MeasurementValueFormatter displayStringForRawValue:raw
        precision:2 locale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    NSString *japanese = [MeasurementValueFormatter displayStringForRawValue:raw
        precision:2 locale:[[NSLocale alloc] initWithLocaleIdentifier:@"ja_JP"]];
    NSString *french = [MeasurementValueFormatter displayStringForRawValue:raw
        precision:2 locale:[[NSLocale alloc] initWithLocaleIdentifier:@"fr_FR"]];
    Assert([english isEqualToString:@"12.35"], @"English display rounds raw value");
    Assert([japanese isEqualToString:@"12.35"], @"Japanese display uses same raw value");
    Assert([french containsString:@","], @"locale decimal separator affects display only");
    Assert(raw == 12.345678901234, @"display formatting does not alter raw value");
    Assert(![english isEqualToString:[NSString stringWithFormat:@"%.14f", raw]],
           @"rounded display remains distinct from internal value");
    Assert([[MeasurementValueFormatter displayStringForRawValue:NAN precision:2
        locale:NSLocale.currentLocale] length] == 0, @"nonfinite display is unavailable");
}

int main(void)
{
    @autoreleasepool {
        TestCalibrationStates();
        TestConfirmationTransitions();
        TestInternalAndDisplayValues();
        NSLog(@"PASS: calibration and user-confirmation state (%lu assertions)",
              (unsigned long)assertionCount);
    }
    return 0;
}
