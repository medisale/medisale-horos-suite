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

static ImageContext *SizedContext(NSString *study, NSString *series, NSString *sop,
                                  NSInteger frame, NSInteger width, NSInteger height,
                                  double spacingX, double spacingY)
{
    return [[ImageContext alloc] initWithStudyInstanceUID:study
        seriesInstanceUID:series sopInstanceUID:sop frameNumber:frame
        pixelWidth:width pixelHeight:height pixelSpacingX:spacingX
        pixelSpacingY:spacingY];
}

static ImageContext *Context(NSString *study, NSString *series, NSString *sop,
                             NSInteger frame, double spacingX, double spacingY)
{
    return SizedContext(study, series, sop, frame, 640, 480, spacingX, spacingY);
}

static MeasurementReviewSnapshot *SnapshotWithPrecision(ImageContext *identity,
    CalibrationProvenanceModel *calibration, NSPoint a, NSPoint b,
    double result, NSString *method, NSString *rounding, NSUInteger precision,
    NSInteger schema)
{
    return [[MeasurementReviewSnapshot alloc] initWithImageIdentity:identity
        pointA:a pointB:b calibration:calibration
        calculationMethodVersion:method rawResult:result
        displayRoundingPolicyVersion:rounding displayPrecision:precision
        modelSchemaVersion:schema];
}

static MeasurementReviewSnapshot *Snapshot(ImageContext *identity,
    CalibrationProvenanceModel *calibration, NSPoint a, NSPoint b,
    NSString *method, NSString *rounding, NSInteger schema)
{
    return SnapshotWithPrecision(identity, calibration, a, b,
        hypot(b.x - a.x, b.y - a.y), method, rounding,
        MedisaleDisplayPrecision, schema);
}

static MeasurementReviewSnapshot *ValidSnapshot(ImageContext *identity,
    CalibrationProvenanceModel *calibration, NSPoint a, NSPoint b)
{
    return Snapshot(identity, calibration, a, b,
        MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion);
}

static void AssertSnapshotDictionaryRejected(NSDictionary *dictionary,
                                              NSString *message)
{
    NSError *error = nil;
    MeasurementReviewSnapshot *snapshot = [MeasurementReviewSnapshot
        snapshotFromDictionary:dictionary error:&error];
    Assert(snapshot == nil, message);
    Assert(error != nil, @"invalid snapshot reports a bounded error");
}

static void AssertCalibrationDictionaryRejected(NSDictionary *dictionary,
                                                 NSString *message)
{
    NSError *error = nil;
    CalibrationProvenanceModel *model = [CalibrationProvenanceModel
        modelFromDictionary:dictionary error:&error];
    Assert(model == nil, message);
    Assert(error != nil, @"invalid calibration reports a bounded error");
}

static void TestCalibrationStates(void)
{
    ImageContext *anisotropicContext = Context(@"study-a", @"series-a", @"sop-a",
                                                0, 0.4, 0.2);
    CalibrationProvenanceModel *runtimeSpacing =
        [CalibrationProvenanceModel modelFromImageContext:anisotropicContext];
    Assert(runtimeSpacing.state == MedisaleCalibrationStateDICOMSpacingOnly,
           @"runtime image spacing remains uncalibrated");
    Assert(runtimeSpacing.sourceCategory ==
           MedisaleCalibrationSourceCategoryHorosRuntimeImageSpacing,
           @"source is the Horos runtime image-spacing boundary");
    Assert(runtimeSpacing.derivationStatus ==
           MedisaleCalibrationDerivationStatusTagLevelUnverified,
           @"tag-level provenance remains unverified");
    Assert([runtimeSpacing.sourceIdentifier
        isEqualToString:@"horos-runtime-image-spacing"],
        @"runtime source does not identify a specific DICOM tag");
    Assert([runtimeSpacing.methodVersion
        isEqualToString:@"horos-adapter-image-context-v1"],
        @"adapter boundary method is versioned");
    Assert(runtimeSpacing.rowSpacing == 0.2,
           @"row spacing uses ImageContext Y");
    Assert(runtimeSpacing.columnSpacing == 0.4,
           @"column spacing uses ImageContext X");
    Assert([runtimeSpacing.units isEqualToString:@"mm"],
           @"spacing units retained");
    Assert(runtimeSpacing.hasUsableSpacing && runtimeSpacing.isStructurallyValid,
           @"uncalibrated runtime spacing is structurally usable");
    Assert([runtimeSpacing.warnings containsObject:@"uncalibrated-runtime-spacing"],
           @"uncalibrated status is explicit");
    Assert([runtimeSpacing.warnings containsObject:@"tag-provenance-unverified"],
           @"tag provenance limitation is explicit");
    Assert([runtimeSpacing.warnings containsObject:@"anisotropic-spacing"],
           @"anisotropic warning retained");
    Assert(runtimeSpacing.state != MedisaleCalibrationStateCalibrated,
           @"runtime spacing never auto-promotes to calibrated");
    double distance = [runtimeSpacing
        physicalDistanceForPointA:NSMakePoint(1, 1) pointB:NSMakePoint(4, 5)];
    Assert(fabs(distance - hypot(1.2, 0.8)) < 1e-12,
           @"row and column spacing apply independently");

    NSError *error = nil;
    CalibrationProvenanceModel *calibrated =
        [CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic-ruler"
            methodVersion:@"method-v1" rowSpacing:0.25 columnSpacing:0.25
            error:&error];
    Assert(calibrated != nil && error == nil,
           @"explicit calibrated fixture accepted");
    Assert(calibrated.state == MedisaleCalibrationStateCalibrated,
           @"explicit source is calibrated");
    Assert(calibrated.sourceCategory ==
           MedisaleCalibrationSourceCategoryExplicitCalibration,
           @"explicit source category retained");
    Assert(calibrated.derivationStatus ==
           MedisaleCalibrationDerivationStatusExplicit,
           @"explicit derivation retained");
    Assert(calibrated.hasUsableSpacing && calibrated.isStructurallyValid,
           @"explicit calibrated spacing usable");

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
        Assert(!unknown.hasUsableSpacing && unknown.isStructurallyValid,
               @"unknown spacing is valid but not usable");
        Assert(isnan([unknown physicalDistanceForPointA:NSZeroPoint
                                                  pointB:NSMakePoint(1, 1)]),
               @"unknown spacing has no physical distance");
        Assert(unknown.warnings.count > 0, @"unknown state explains why with codes");
    }

    NSDictionary *serialized = [runtimeSpacing dictionaryRepresentation];
    error = nil;
    CalibrationProvenanceModel *restored =
        [CalibrationProvenanceModel modelFromDictionary:serialized error:&error];
    Assert(restored != nil && error == nil, @"runtime spacing round-trip succeeds");
    Assert([runtimeSpacing isEquivalentToModel:restored],
           @"runtime spacing round-trip is equivalent");

    CalibrationProvenanceModel *unknown =
        [CalibrationProvenanceModel unknownModelWithWarnings:
            @[@"spacing-provenance-unknown"]];
    error = nil;
    CalibrationProvenanceModel *unknownRestored =
        [CalibrationProvenanceModel modelFromDictionary:
            unknown.dictionaryRepresentation error:&error];
    Assert(unknownRestored != nil && error == nil,
           @"unknown calibration round-trip succeeds");
    Assert([unknown isEquivalentToModel:unknownRestored],
           @"unknown calibration round-trip preserves NaN and reason code");

    CalibrationProvenanceModel *sanitized =
        [CalibrationProvenanceModel unknownModelWithWarnings:@[
            @"spacing-provenance-unknown", @"../../private/path",
            @"patient-identifier-not-a-warning"
        ]];
    Assert([sanitized.warnings isEqualToArray:@[@"spacing-provenance-unknown"]],
           @"unsafe arbitrary warning text is never retained");

    NSMutableDictionary *bad = [serialized mutableCopy];
    bad[@"modelSchemaVersion"] = @(MedisaleCalibrationModelSchemaVersion + 1);
    AssertCalibrationDictionaryRejected(bad,
        @"incompatible calibration schema rejected");
    bad = [serialized mutableCopy];
    bad[@"state"] = @99;
    AssertCalibrationDictionaryRejected(bad, @"unknown calibration enum rejected");
    bad = [serialized mutableCopy];
    bad[@"sourceCategory"] = @99;
    AssertCalibrationDictionaryRejected(bad, @"unknown source enum rejected");
    bad = [serialized mutableCopy];
    bad[@"derivationStatus"] = @99;
    AssertCalibrationDictionaryRejected(bad, @"unknown derivation enum rejected");
    bad = [serialized mutableCopy];
    bad[@"sourceIdentifier"] = @"dicom-pixel-spacing";
    AssertCalibrationDictionaryRejected(bad,
        @"specific-tag claim is incompatible with runtime provenance");
    bad = [serialized mutableCopy];
    bad[@"warnings"] = @[@"/private/path"];
    AssertCalibrationDictionaryRejected(bad, @"path-like warning rejected");
    bad = [serialized mutableCopy];
    bad[@"warnings"] = @[@"patient-identifier-not-a-warning"];
    AssertCalibrationDictionaryRejected(bad, @"unrecognized warning rejected");
    bad = [serialized mutableCopy];
    bad[@"warnings"] = @[@"tag-provenance-unverified",
                          @"tag-provenance-unverified"];
    AssertCalibrationDictionaryRejected(bad, @"duplicate warning rejected");
    bad = [serialized mutableCopy];
    bad[@"warnings"] = @[[@"x" stringByPaddingToLength:49
        withString:@"x" startingAtIndex:0]];
    AssertCalibrationDictionaryRejected(bad, @"overlong warning rejected");
    bad = [serialized mutableCopy];
    bad[@"modelSchemaVersion"] = @YES;
    AssertCalibrationDictionaryRejected(bad, @"boolean schema rejected");
    bad = [serialized mutableCopy];
    bad[@"extra"] = @"unrecognized";
    AssertCalibrationDictionaryRejected(bad, @"unknown calibration field rejected");

    NSMutableDictionary *silentUpgrade =
        [unknown.dictionaryRepresentation mutableCopy];
    silentUpgrade[@"state"] = @(MedisaleCalibrationStateCalibrated);
    AssertCalibrationDictionaryRejected(silentUpgrade,
        @"unknown provenance cannot decode as calibrated");
}

static void TestSnapshotValidation(void)
{
    ImageContext *identity = Context(@"study-a", @"series-a", @"sop-a", 0,
                                     0.4, 0.2);
    CalibrationProvenanceModel *calibration =
        [CalibrationProvenanceModel modelFromImageContext:identity];
    MeasurementReviewSnapshot *valid = ValidSnapshot(identity, calibration,
        NSMakePoint(10, 20), NSMakePoint(30, 50));
    Assert(valid.isStructurallyValid, @"valid snapshot is structurally sound");

    NSError *error = nil;
    MeasurementReviewSnapshot *restored = [MeasurementReviewSnapshot
        snapshotFromDictionary:valid.dictionaryRepresentation error:&error];
    Assert(restored != nil && error == nil, @"valid snapshot round-trip succeeds");
    Assert([valid isEquivalentToSnapshot:restored],
           @"valid snapshot round-trip remains equivalent");

    ImageContext *unknownIdentity = Context(@"study-u", @"series-u", @"sop-u",
                                             0, NAN, NAN);
    CalibrationProvenanceModel *unknown =
        [CalibrationProvenanceModel modelFromImageContext:unknownIdentity];
    MeasurementReviewSnapshot *unknownSnapshot = ValidSnapshot(unknownIdentity, unknown,
        NSMakePoint(4, 5), NSMakePoint(8, 10));
    Assert(unknownSnapshot.isStructurallyValid,
           @"unknown calibration snapshot can remain structurally valid");
    error = nil;
    MeasurementReviewSnapshot *unknownRoundTrip = [MeasurementReviewSnapshot
        snapshotFromDictionary:unknownSnapshot.dictionaryRepresentation error:&error];
    Assert(unknownRoundTrip != nil && error == nil,
           @"unknown calibration snapshot round-trip succeeds");
    Assert([unknownSnapshot isEquivalentToSnapshot:unknownRoundTrip],
           @"unknown snapshot round-trip is equivalent");

    NSDictionary *base = valid.dictionaryRepresentation;
    NSArray<NSDictionary *> *invalidValues = @[
        @{@"frame": @-1}, @{@"width": @0}, @{@"width": @-1},
        @{@"height": @0}, @{@"height": @-1},
        @{@"pointAX": @-0.01}, @{@"pointAX": @640.0},
        @{@"pointAY": @-0.01}, @{@"pointAY": @480.0},
        @{@"pointBX": @(NAN)}, @{@"pointBY": @(INFINITY)},
        @{@"rawResult": @(NAN)}, @{@"rawResult": @(INFINITY)},
        @{@"rawResult": @(valid.rawResult + 0.1)},
        @{@"calculationMethodVersion": @"distance-image-v2"},
        @{@"displayRoundingPolicyVersion": @"fixed-decimal-v2"},
        @{@"displayPrecision": @3}, @{@"displayPrecision": @-1},
        @{@"modelSchemaVersion": @(MedisaleConfirmationModelSchemaVersion + 1)},
        @{@"frame": @0.5}, @{@"displayPrecision": @2.5},
        @{@"frame": @YES}, @{@"spacingX": @YES},
    ];
    NSArray<NSString *> *messages = @[
        @"negative frame rejected", @"zero width rejected", @"negative width rejected",
        @"zero height rejected", @"negative height rejected",
        @"negative point X rejected", @"point X at width rejected",
        @"negative point Y rejected", @"point Y at height rejected",
        @"NaN coordinate rejected", @"infinite coordinate rejected",
        @"NaN result rejected", @"infinite result rejected",
        @"result inconsistent with endpoints rejected",
        @"calculation version rejected", @"rounding version rejected",
        @"unsupported precision rejected", @"negative precision rejected",
        @"snapshot schema rejected",
        @"fractional frame rejected", @"fractional precision rejected",
        @"boolean frame rejected", @"boolean spacing rejected",
    ];
    for (NSUInteger index = 0; index < invalidValues.count; index++) {
        NSMutableDictionary *candidate = [base mutableCopy];
        [candidate addEntriesFromDictionary:invalidValues[index]];
        AssertSnapshotDictionaryRejected(candidate, messages[index]);
    }

    NSMutableDictionary *extraField = [base mutableCopy];
    extraField[@"extra"] = @"unrecognized";
    AssertSnapshotDictionaryRejected(extraField, @"unknown snapshot field rejected");

    NSMutableDictionary *badCalibration = [base mutableCopy];
    NSMutableDictionary *calibrationDictionary =
        [badCalibration[@"calibration"] mutableCopy];
    calibrationDictionary[@"warnings"] = @[@"local/path"];
    badCalibration[@"calibration"] = calibrationDictionary;
    AssertSnapshotDictionaryRejected(badCalibration,
        @"snapshot with unsafe calibration warning rejected");

    badCalibration = [base mutableCopy];
    calibrationDictionary = [badCalibration[@"calibration"] mutableCopy];
    calibrationDictionary[@"sourceCategory"] =
        @(MedisaleCalibrationSourceCategoryExplicitCalibration);
    badCalibration[@"calibration"] = calibrationDictionary;
    AssertSnapshotDictionaryRejected(badCalibration,
        @"calibration state/source mismatch rejected");

    badCalibration = [base mutableCopy];
    calibrationDictionary = [badCalibration[@"calibration"] mutableCopy];
    calibrationDictionary[@"methodVersion"] = @"horos-adapter-image-context-v2";
    badCalibration[@"calibration"] = calibrationDictionary;
    AssertSnapshotDictionaryRejected(badCalibration,
        @"runtime spacing method version change rejected");

    ImageContext *badFrame = SizedContext(@"study-a", @"series-a", @"sop-a", -1,
        640, 480, 0.4, 0.2);
    MeasurementReviewSnapshot *directInvalid = ValidSnapshot(badFrame, calibration,
        NSMakePoint(1, 1), NSMakePoint(2, 2));
    Assert(!directInvalid.isStructurallyValid,
           @"direct snapshot with negative frame is invalid");
    ConfirmationStateModel *blocked = [[ConfirmationStateModel alloc] init];
    [blocked updateCurrentSnapshot:directInvalid];
    Assert(![blocked confirmCurrentSnapshot],
           @"malformed direct snapshot cannot be confirmed");
}

static void TestConfirmationTransitions(void)
{
    ImageContext *identity = Context(@"study-a", @"series-a", @"sop-a", 0,
                                     0.4, 0.2);
    CalibrationProvenanceModel *runtimeSpacing =
        [CalibrationProvenanceModel modelFromImageContext:identity];
    MeasurementReviewSnapshot *original = ValidSnapshot(identity, runtimeSpacing,
        NSMakePoint(10, 20), NSMakePoint(30, 50));
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
    Assert(confirmation.currentSnapshot.calibration.state ==
           MedisaleCalibrationStateDICOMSpacingOnly,
           @"confirmation does not upgrade runtime spacing");

    MeasurementReviewSnapshot *equivalent = ValidSnapshot(identity, runtimeSpacing,
        original.pointA, original.pointB);
    [confirmation updateCurrentSnapshot:equivalent];
    Assert(confirmation.state == MedisaleConfirmationStateUserConfirmed,
           @"equivalent snapshot remains confirmed");

    MeasurementReviewSnapshot *endpointChanged = ValidSnapshot(identity, runtimeSpacing,
        NSMakePoint(11, 20), original.pointB);
    [confirmation updateCurrentSnapshot:endpointChanged];
    Assert(confirmation.state == MedisaleConfirmationStateModifiedAfterConfirmation,
           @"actual endpoint/result change marks modified");
    Assert([confirmation confirmCurrentSnapshot], @"modified state can be reconfirmed");

    MeasurementReviewSnapshot *artificialResult = SnapshotWithPrecision(identity,
        runtimeSpacing, endpointChanged.pointA, endpointChanged.pointB,
        endpointChanged.rawResult + 0.1, MedisaleDistanceCalculationMethodVersion,
        MedisaleDisplayRoundingPolicyVersion, MedisaleDisplayPrecision,
        MedisaleConfirmationModelSchemaVersion);
    Assert(!artificialResult.isStructurallyValid,
           @"artificial raw-result mutation is not structurally valid");
    [confirmation updateCurrentSnapshot:artificialResult];
    Assert(confirmation.state == MedisaleConfirmationStateInvalidated,
           @"artificial result mutation invalidates rather than marks modified");

    CalibrationProvenanceModel *explicitOne =
        [CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic-a"
            methodVersion:@"method-v1" rowSpacing:0.2 columnSpacing:0.5 error:nil];
    CalibrationProvenanceModel *explicitTwo =
        [CalibrationProvenanceModel calibratedModelWithSourceIdentifier:@"synthetic-b"
            methodVersion:@"method-v2" rowSpacing:0.2 columnSpacing:0.5 error:nil];
    MeasurementReviewSnapshot *explicitSnapshot = ValidSnapshot(identity, explicitOne,
        NSMakePoint(11, 20), NSMakePoint(30, 50));
    ConfirmationStateModel *provenance = [[ConfirmationStateModel alloc] init];
    [provenance updateCurrentSnapshot:explicitSnapshot];
    Assert([provenance confirmCurrentSnapshot], @"explicit snapshot confirms");
    [provenance updateCurrentSnapshot:ValidSnapshot(identity, explicitTwo,
        explicitSnapshot.pointA, explicitSnapshot.pointB)];
    Assert(provenance.state == MedisaleConfirmationStateModifiedAfterConfirmation,
           @"calibration source and method version change marks modified");
    Assert([provenance confirmCurrentSnapshot],
           @"changed provenance can be explicitly reviewed again");

    CalibrationProvenanceModel *unknown =
        [CalibrationProvenanceModel unknownModelWithWarnings:@[@"provenance-lost"]];
    [provenance updateCurrentSnapshot:ValidSnapshot(identity, unknown,
        explicitSnapshot.pointA, explicitSnapshot.pointB)];
    Assert(provenance.state == MedisaleConfirmationStateInvalidated,
           @"provenance loss invalidates confirmation");
    Assert(![provenance confirmCurrentSnapshot],
           @"invalidated state cannot be silently reconfirmed");

    NSArray<ImageContext *> *mismatches = @[
        Context(@"study-b", @"series-a", @"sop-a", 0, 0.4, 0.2),
        Context(@"study-a", @"series-b", @"sop-a", 0, 0.4, 0.2),
        Context(@"study-a", @"series-a", @"sop-b", 0, 0.4, 0.2),
        Context(@"study-a", @"series-a", @"sop-a", 1, 0.4, 0.2),
        SizedContext(@"study-a", @"series-a", @"sop-a", 0,
                     641, 480, 0.4, 0.2),
    ];
    for (ImageContext *mismatch in mismatches) {
        ConfirmationStateModel *bound = [[ConfirmationStateModel alloc] init];
        [bound updateCurrentSnapshot:original];
        Assert([bound confirmCurrentSnapshot], @"identity fixture confirmed");
        [bound updateCurrentSnapshot:ValidSnapshot(mismatch,
            [CalibrationProvenanceModel modelFromImageContext:mismatch],
            original.pointA, original.pointB)];
        Assert(bound.state == MedisaleConfirmationStateInvalidated,
               @"Study/Series/SOP/frame/dimensions mismatch invalidates");
    }

    ConfirmationStateModel *versioned = [[ConfirmationStateModel alloc] init];
    [versioned updateCurrentSnapshot:original];
    Assert([versioned confirmCurrentSnapshot], @"version fixture confirmed");
    [versioned updateCurrentSnapshot:Snapshot(identity, runtimeSpacing,
        original.pointA, original.pointB, @"distance-image-v2",
        MedisaleDisplayRoundingPolicyVersion,
        MedisaleConfirmationModelSchemaVersion)];
    Assert(versioned.state == MedisaleConfirmationStateInvalidated,
           @"incompatible calculation method invalidates");

    ConfirmationStateModel *rounding = [[ConfirmationStateModel alloc] init];
    [rounding updateCurrentSnapshot:original];
    Assert([rounding confirmCurrentSnapshot], @"presentation fixture confirmed");
    [rounding updateCurrentSnapshot:Snapshot(identity, runtimeSpacing,
        original.pointA, original.pointB,
        MedisaleDistanceCalculationMethodVersion, @"fixed-decimal-v2",
        MedisaleConfirmationModelSchemaVersion)];
    Assert(rounding.state == MedisaleConfirmationStateInvalidated,
           @"invalidated presentation version cannot remain modified-confirmable");

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
        precision:MedisaleDisplayPrecision
        locale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    NSString *japanese = [MeasurementValueFormatter displayStringForRawValue:raw
        precision:MedisaleDisplayPrecision
        locale:[[NSLocale alloc] initWithLocaleIdentifier:@"ja_JP"]];
    NSString *french = [MeasurementValueFormatter displayStringForRawValue:raw
        precision:MedisaleDisplayPrecision
        locale:[[NSLocale alloc] initWithLocaleIdentifier:@"fr_FR"]];
    Assert([english isEqualToString:@"12.35"], @"English display rounds raw value");
    Assert([japanese isEqualToString:@"12.35"], @"Japanese display uses same raw value");
    Assert([french containsString:@","], @"locale decimal separator affects display only");
    Assert(raw == 12.345678901234, @"display formatting does not alter raw value");
    Assert(![english isEqualToString:[NSString stringWithFormat:@"%.14f", raw]],
           @"rounded display remains distinct from internal value");

    ImageContext *identity = Context(@"study-r", @"series-r", @"sop-r", 0,
                                     0.4, 0.2);
    MeasurementReviewSnapshot *snapshot = ValidSnapshot(identity,
        [CalibrationProvenanceModel modelFromImageContext:identity],
        NSMakePoint(0, 0), NSMakePoint(7, 10));
    double rawBeforeFormatting = snapshot.rawResult;
    NSString *display = [MeasurementValueFormatter
        displayStringForRawValue:snapshot.rawResult precision:MedisaleDisplayPrecision
        locale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    Assert(snapshot.rawResult == rawBeforeFormatting,
           @"snapshot retains raw value after display formatting");
    Assert(![display isEqualToString:[NSString stringWithFormat:@"%.15g",
        snapshot.rawResult]], @"snapshot raw and rounded presentation stay separate");
    Assert([[MeasurementValueFormatter displayStringForRawValue:NAN
        precision:MedisaleDisplayPrecision locale:NSLocale.currentLocale] length] == 0,
        @"NaN display is unavailable");
    Assert([[MeasurementValueFormatter displayStringForRawValue:INFINITY
        precision:MedisaleDisplayPrecision locale:NSLocale.currentLocale] length] == 0,
        @"infinite display is unavailable");
}

int main(void)
{
    @autoreleasepool {
        TestCalibrationStates();
        TestSnapshotValidation();
        TestConfirmationTransitions();
        TestInternalAndDisplayValues();
        NSLog(@"PASS: calibration and user-confirmation state (%lu assertions)",
              (unsigned long)assertionCount);
    }
    return 0;
}
