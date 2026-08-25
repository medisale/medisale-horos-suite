#import "CalibrationConfirmationState.h"

#import "ImageContext.h"
#import <math.h>

NSInteger const MedisaleCalibrationModelSchemaVersion = 1;
NSInteger const MedisaleConfirmationModelSchemaVersion = 1;
NSString * const MedisaleDistanceCalculationMethodVersion = @"distance-image-v1";
NSString * const MedisaleDisplayRoundingPolicyVersion = @"fixed-decimal-v1";

static NSString * const MedisaleStateErrorDomain = @"jp.medisale.calibration-confirmation";

static BOOL MedisaleFinitePositive(double value)
{
    return isfinite(value) && value > 0.0;
}

static BOOL MedisaleSafeIdentifier(NSString *value)
{
    if (value.length == 0 || value.length > 128) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet
        characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static void MedisaleSetError(NSError **error, NSInteger code, NSString *message)
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:MedisaleStateErrorDomain code:code
            userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

@interface CalibrationProvenanceModel ()
@property(nonatomic, readwrite) MedisaleCalibrationState state;
@property(nonatomic, readwrite) MedisaleCalibrationSourceCategory sourceCategory;
@property(nonatomic, copy, readwrite) NSString *sourceIdentifier;
@property(nonatomic, copy, readwrite) NSString *methodVersion;
@property(nonatomic, readwrite) double rowSpacing;
@property(nonatomic, readwrite) double columnSpacing;
@property(nonatomic, copy, readwrite) NSString *units;
@property(nonatomic, readwrite) MedisaleCalibrationDerivationStatus derivationStatus;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *warnings;
@property(nonatomic, readwrite) NSInteger modelSchemaVersion;

- (instancetype)initWithState:(MedisaleCalibrationState)state
                 sourceCategory:(MedisaleCalibrationSourceCategory)sourceCategory
               sourceIdentifier:(NSString *)sourceIdentifier
                  methodVersion:(NSString *)methodVersion
                     rowSpacing:(double)rowSpacing
                  columnSpacing:(double)columnSpacing
                          units:(NSString *)units
               derivationStatus:(MedisaleCalibrationDerivationStatus)derivationStatus
                       warnings:(NSArray<NSString *> *)warnings
             modelSchemaVersion:(NSInteger)modelSchemaVersion;
@end

@implementation CalibrationProvenanceModel

- (instancetype)initWithState:(MedisaleCalibrationState)state
                 sourceCategory:(MedisaleCalibrationSourceCategory)sourceCategory
               sourceIdentifier:(NSString *)sourceIdentifier
                  methodVersion:(NSString *)methodVersion
                     rowSpacing:(double)rowSpacing
                  columnSpacing:(double)columnSpacing
                          units:(NSString *)units
               derivationStatus:(MedisaleCalibrationDerivationStatus)derivationStatus
                       warnings:(NSArray<NSString *> *)warnings
             modelSchemaVersion:(NSInteger)modelSchemaVersion
{
    self = [super init];
    if (self) {
        _state = state;
        _sourceCategory = sourceCategory;
        _sourceIdentifier = [sourceIdentifier copy];
        _methodVersion = [methodVersion copy];
        _rowSpacing = rowSpacing;
        _columnSpacing = columnSpacing;
        _units = [units copy];
        _derivationStatus = derivationStatus;
        _warnings = [warnings copy];
        _modelSchemaVersion = modelSchemaVersion;
    }
    return self;
}

+ (instancetype)modelFromImageContext:(ImageContext *)imageContext
{
    double row = imageContext.pixelSpacingY;
    double column = imageContext.pixelSpacingX;
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    if (!MedisaleFinitePositive(row)) {
        [warnings addObject:@"row-spacing-unavailable"];
    }
    if (!MedisaleFinitePositive(column)) {
        [warnings addObject:@"column-spacing-unavailable"];
    }
    if (warnings.count > 0) {
        return [self unknownModelWithWarnings:warnings];
    }
    if (row != column) {
        [warnings addObject:@"anisotropic-spacing"];
    }
    return [[self alloc] initWithState:MedisaleCalibrationStateDICOMSpacingOnly
        sourceCategory:MedisaleCalibrationSourceCategoryDICOMDerived
        sourceIdentifier:@"dicom-pixel-spacing"
        methodVersion:@"image-context-v1"
        rowSpacing:row columnSpacing:column units:@"mm"
        derivationStatus:MedisaleCalibrationDerivationStatusDICOMDerived
        warnings:warnings modelSchemaVersion:MedisaleCalibrationModelSchemaVersion];
}

+ (instancetype)unknownModelWithWarnings:(NSArray<NSString *> *)warnings
{
    NSArray<NSString *> *reasons = warnings.count > 0
        ? warnings : @[@"spacing-provenance-unknown"];
    return [[self alloc] initWithState:MedisaleCalibrationStateUnknown
        sourceCategory:MedisaleCalibrationSourceCategoryNone
        sourceIdentifier:@"" methodVersion:@"" rowSpacing:NAN columnSpacing:NAN
        units:@"mm" derivationStatus:MedisaleCalibrationDerivationStatusMissing
        warnings:reasons modelSchemaVersion:MedisaleCalibrationModelSchemaVersion];
}

+ (instancetype)calibratedModelWithSourceIdentifier:(NSString *)sourceIdentifier
                                       methodVersion:(NSString *)methodVersion
                                          rowSpacing:(double)rowSpacing
                                       columnSpacing:(double)columnSpacing
                                               error:(NSError **)error
{
    if (!MedisaleSafeIdentifier(sourceIdentifier) ||
        !MedisaleSafeIdentifier(methodVersion) ||
        !MedisaleFinitePositive(rowSpacing) ||
        !MedisaleFinitePositive(columnSpacing)) {
        MedisaleSetError(error, 1, @"Explicit calibration requires safe provenance and positive finite spacing.");
        return nil;
    }
    NSArray<NSString *> *warnings = rowSpacing == columnSpacing
        ? @[] : @[@"anisotropic-spacing"];
    return [[self alloc] initWithState:MedisaleCalibrationStateCalibrated
        sourceCategory:MedisaleCalibrationSourceCategoryExplicitCalibration
        sourceIdentifier:sourceIdentifier methodVersion:methodVersion
        rowSpacing:rowSpacing columnSpacing:columnSpacing units:@"mm"
        derivationStatus:MedisaleCalibrationDerivationStatusExplicit
        warnings:warnings modelSchemaVersion:MedisaleCalibrationModelSchemaVersion];
}

- (BOOL)hasUsableSpacing
{
    return self.modelSchemaVersion == MedisaleCalibrationModelSchemaVersion &&
        self.state != MedisaleCalibrationStateUnknown &&
        MedisaleFinitePositive(self.rowSpacing) &&
        MedisaleFinitePositive(self.columnSpacing) &&
        [self.units isEqualToString:@"mm"];
}

- (double)physicalDistanceForPointA:(NSPoint)pointA pointB:(NSPoint)pointB
{
    if (!self.hasUsableSpacing) {
        return NAN;
    }
    double dx = (pointB.x - pointA.x) * self.columnSpacing;
    double dy = (pointB.y - pointA.y) * self.rowSpacing;
    return hypot(dx, dy);
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation
{
    return @{
        @"state": @(self.state),
        @"sourceCategory": @(self.sourceCategory),
        @"sourceIdentifier": self.sourceIdentifier,
        @"methodVersion": self.methodVersion,
        @"rowSpacing": @(self.rowSpacing),
        @"columnSpacing": @(self.columnSpacing),
        @"units": self.units,
        @"derivationStatus": @(self.derivationStatus),
        @"warnings": self.warnings,
        @"modelSchemaVersion": @(self.modelSchemaVersion),
    };
}

+ (instancetype)modelFromDictionary:(NSDictionary<NSString *,id> *)dictionary
                                error:(NSError **)error
{
    NSNumber *schema = dictionary[@"modelSchemaVersion"];
    NSNumber *state = dictionary[@"state"];
    NSNumber *source = dictionary[@"sourceCategory"];
    NSNumber *derivation = dictionary[@"derivationStatus"];
    NSNumber *row = dictionary[@"rowSpacing"];
    NSNumber *column = dictionary[@"columnSpacing"];
    NSString *sourceIdentifier = dictionary[@"sourceIdentifier"];
    NSString *methodVersion = dictionary[@"methodVersion"];
    NSString *units = dictionary[@"units"];
    NSArray *warnings = dictionary[@"warnings"];
    if (![schema isKindOfClass:NSNumber.class] ||
        schema.integerValue != MedisaleCalibrationModelSchemaVersion ||
        ![state isKindOfClass:NSNumber.class] ||
        ![source isKindOfClass:NSNumber.class] ||
        ![derivation isKindOfClass:NSNumber.class] ||
        ![row isKindOfClass:NSNumber.class] ||
        ![column isKindOfClass:NSNumber.class] ||
        ![sourceIdentifier isKindOfClass:NSString.class] ||
        ![methodVersion isKindOfClass:NSString.class] ||
        ![units isKindOfClass:NSString.class] ||
        ![warnings isKindOfClass:NSArray.class]) {
        MedisaleSetError(error, 2, @"Calibration model schema or values are incompatible.");
        return nil;
    }
    MedisaleCalibrationState calibrationState = state.integerValue;
    BOOL warningsValid = YES;
    for (id warning in warnings) {
        if (![warning isKindOfClass:NSString.class]) {
            warningsValid = NO;
            break;
        }
    }
    BOOL commonKnownValuesValid = MedisaleSafeIdentifier(sourceIdentifier) &&
        MedisaleSafeIdentifier(methodVersion) &&
        MedisaleFinitePositive(row.doubleValue) &&
        MedisaleFinitePositive(column.doubleValue) &&
        [units isEqualToString:@"mm"];
    BOOL stateCombinationValid = NO;
    switch (calibrationState) {
        case MedisaleCalibrationStateCalibrated:
            stateCombinationValid = commonKnownValuesValid &&
                source.integerValue ==
                    MedisaleCalibrationSourceCategoryExplicitCalibration &&
                derivation.integerValue ==
                    MedisaleCalibrationDerivationStatusExplicit;
            break;
        case MedisaleCalibrationStateDICOMSpacingOnly:
            stateCombinationValid = commonKnownValuesValid &&
                source.integerValue == MedisaleCalibrationSourceCategoryDICOMDerived &&
                derivation.integerValue ==
                    MedisaleCalibrationDerivationStatusDICOMDerived;
            break;
        case MedisaleCalibrationStateUnknown:
            stateCombinationValid =
                source.integerValue == MedisaleCalibrationSourceCategoryNone &&
                sourceIdentifier.length == 0 && methodVersion.length == 0 &&
                derivation.integerValue == MedisaleCalibrationDerivationStatusMissing &&
                [units isEqualToString:@"mm"];
            break;
        default:
            stateCombinationValid = NO;
            break;
    }
    if (!warningsValid || !stateCombinationValid) {
        MedisaleSetError(error, 3, @"Calibration provenance is invalid.");
        return nil;
    }
    return [[self alloc] initWithState:calibrationState
        sourceCategory:source.integerValue sourceIdentifier:sourceIdentifier
        methodVersion:methodVersion rowSpacing:row.doubleValue
        columnSpacing:column.doubleValue units:units
        derivationStatus:derivation.integerValue warnings:warnings
        modelSchemaVersion:schema.integerValue];
}

- (BOOL)isEquivalentToModel:(CalibrationProvenanceModel *)other
{
    if (other == nil) {
        return NO;
    }
    BOOL spacingEqual = (isnan(self.rowSpacing) && isnan(other.rowSpacing)) ||
        self.rowSpacing == other.rowSpacing;
    spacingEqual = spacingEqual &&
        ((isnan(self.columnSpacing) && isnan(other.columnSpacing)) ||
         self.columnSpacing == other.columnSpacing);
    return self.state == other.state &&
        self.sourceCategory == other.sourceCategory &&
        [self.sourceIdentifier isEqualToString:other.sourceIdentifier] &&
        [self.methodVersion isEqualToString:other.methodVersion] &&
        spacingEqual && [self.units isEqualToString:other.units] &&
        self.derivationStatus == other.derivationStatus &&
        [self.warnings isEqualToArray:other.warnings] &&
        self.modelSchemaVersion == other.modelSchemaVersion;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

@implementation MeasurementReviewSnapshot

- (instancetype)initWithImageIdentity:(ImageContext *)imageIdentity
                                pointA:(NSPoint)pointA
                                pointB:(NSPoint)pointB
                           calibration:(CalibrationProvenanceModel *)calibration
              calculationMethodVersion:(NSString *)calculationMethodVersion
                             rawResult:(double)rawResult
          displayRoundingPolicyVersion:(NSString *)displayRoundingPolicyVersion
                      displayPrecision:(NSUInteger)displayPrecision
                    modelSchemaVersion:(NSInteger)modelSchemaVersion
{
    self = [super init];
    if (self) {
        _imageIdentity = [imageIdentity copy];
        _pointA = pointA;
        _pointB = pointB;
        _calibration = [calibration copy];
        _calculationMethodVersion = [calculationMethodVersion copy];
        _rawResult = rawResult;
        _displayRoundingPolicyVersion = [displayRoundingPolicyVersion copy];
        _displayPrecision = displayPrecision;
        _modelSchemaVersion = modelSchemaVersion;
    }
    return self;
}

- (BOOL)isStructurallyValid
{
    return self.imageIdentity.studyInstanceUID.length > 0 &&
        self.imageIdentity.seriesInstanceUID.length > 0 &&
        self.imageIdentity.sopInstanceUID.length > 0 &&
        isfinite(self.pointA.x) && isfinite(self.pointA.y) &&
        isfinite(self.pointB.x) && isfinite(self.pointB.y) &&
        isfinite(self.rawResult) &&
        MedisaleSafeIdentifier(self.calculationMethodVersion) &&
        MedisaleSafeIdentifier(self.displayRoundingPolicyVersion) &&
        self.displayPrecision <= 9 &&
        self.modelSchemaVersion == MedisaleConfirmationModelSchemaVersion &&
        self.calibration.modelSchemaVersion == MedisaleCalibrationModelSchemaVersion;
}

- (BOOL)matchesImageIdentity:(ImageContext *)imageIdentity
{
    return imageIdentity != nil &&
        [self.imageIdentity.studyInstanceUID isEqualToString:imageIdentity.studyInstanceUID] &&
        [self.imageIdentity.seriesInstanceUID isEqualToString:imageIdentity.seriesInstanceUID] &&
        [self.imageIdentity.sopInstanceUID isEqualToString:imageIdentity.sopInstanceUID] &&
        self.imageIdentity.frameNumber == imageIdentity.frameNumber;
}

- (BOOL)isEquivalentToSnapshot:(MeasurementReviewSnapshot *)other
{
    return other != nil && [self matchesImageIdentity:other.imageIdentity] &&
        NSEqualPoints(self.pointA, other.pointA) &&
        NSEqualPoints(self.pointB, other.pointB) &&
        [self.calibration isEquivalentToModel:other.calibration] &&
        [self.calculationMethodVersion isEqualToString:other.calculationMethodVersion] &&
        self.rawResult == other.rawResult &&
        [self.displayRoundingPolicyVersion
            isEqualToString:other.displayRoundingPolicyVersion] &&
        self.displayPrecision == other.displayPrecision &&
        self.modelSchemaVersion == other.modelSchemaVersion;
}

- (NSDictionary<NSString *,id> *)dictionaryRepresentation
{
    return @{
        @"study": self.imageIdentity.studyInstanceUID,
        @"series": self.imageIdentity.seriesInstanceUID,
        @"sop": self.imageIdentity.sopInstanceUID,
        @"frame": @(self.imageIdentity.frameNumber),
        @"width": @(self.imageIdentity.pixelWidth),
        @"height": @(self.imageIdentity.pixelHeight),
        @"spacingX": @(self.imageIdentity.pixelSpacingX),
        @"spacingY": @(self.imageIdentity.pixelSpacingY),
        @"pointAX": @(self.pointA.x), @"pointAY": @(self.pointA.y),
        @"pointBX": @(self.pointB.x), @"pointBY": @(self.pointB.y),
        @"calibration": [self.calibration dictionaryRepresentation],
        @"calculationMethodVersion": self.calculationMethodVersion,
        @"rawResult": @(self.rawResult),
        @"displayRoundingPolicyVersion": self.displayRoundingPolicyVersion,
        @"displayPrecision": @(self.displayPrecision),
        @"modelSchemaVersion": @(self.modelSchemaVersion),
    };
}

+ (instancetype)snapshotFromDictionary:(NSDictionary<NSString *,id> *)dictionary
                                   error:(NSError **)error
{
    NSArray<NSString *> *stringKeys = @[@"study", @"series", @"sop",
        @"calculationMethodVersion", @"displayRoundingPolicyVersion"];
    for (NSString *key in stringKeys) {
        if (![dictionary[key] isKindOfClass:NSString.class]) {
            MedisaleSetError(error, 4, @"Confirmation snapshot text value is missing.");
            return nil;
        }
    }
    NSArray<NSString *> *numberKeys = @[@"frame", @"width", @"height",
        @"spacingX", @"spacingY", @"pointAX", @"pointAY", @"pointBX",
        @"pointBY", @"rawResult", @"displayPrecision", @"modelSchemaVersion"];
    for (NSString *key in numberKeys) {
        if (![dictionary[key] isKindOfClass:NSNumber.class]) {
            MedisaleSetError(error, 5, @"Confirmation snapshot numeric value is missing.");
            return nil;
        }
    }
    NSDictionary *calibrationDictionary = dictionary[@"calibration"];
    if (![calibrationDictionary isKindOfClass:NSDictionary.class]) {
        MedisaleSetError(error, 6, @"Confirmation calibration snapshot is missing.");
        return nil;
    }
    CalibrationProvenanceModel *calibration =
        [CalibrationProvenanceModel modelFromDictionary:calibrationDictionary error:error];
    if (calibration == nil) {
        return nil;
    }
    ImageContext *identity = [[ImageContext alloc]
        initWithStudyInstanceUID:dictionary[@"study"]
        seriesInstanceUID:dictionary[@"series"] sopInstanceUID:dictionary[@"sop"]
        frameNumber:[dictionary[@"frame"] integerValue]
        pixelWidth:[dictionary[@"width"] integerValue]
        pixelHeight:[dictionary[@"height"] integerValue]
        pixelSpacingX:[dictionary[@"spacingX"] doubleValue]
        pixelSpacingY:[dictionary[@"spacingY"] doubleValue]];
    MeasurementReviewSnapshot *snapshot = [[self alloc]
        initWithImageIdentity:identity
        pointA:NSMakePoint([dictionary[@"pointAX"] doubleValue],
                           [dictionary[@"pointAY"] doubleValue])
        pointB:NSMakePoint([dictionary[@"pointBX"] doubleValue],
                           [dictionary[@"pointBY"] doubleValue])
        calibration:calibration
        calculationMethodVersion:dictionary[@"calculationMethodVersion"]
        rawResult:[dictionary[@"rawResult"] doubleValue]
        displayRoundingPolicyVersion:dictionary[@"displayRoundingPolicyVersion"]
        displayPrecision:[dictionary[@"displayPrecision"] unsignedIntegerValue]
        modelSchemaVersion:[dictionary[@"modelSchemaVersion"] integerValue]];
    if (!snapshot.isStructurallyValid) {
        MedisaleSetError(error, 7, @"Confirmation snapshot is incompatible or invalid.");
        return nil;
    }
    return snapshot;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

@end

@interface ConfirmationStateModel ()
@property(nonatomic, readwrite) MedisaleConfirmationState state;
@property(nonatomic, copy, readwrite, nullable) MeasurementReviewSnapshot *currentSnapshot;
@property(nonatomic, copy, readwrite, nullable) MeasurementReviewSnapshot *confirmedSnapshot;
@end

@implementation ConfirmationStateModel

- (instancetype)init
{
    self = [super init];
    if (self) {
        _state = MedisaleConfirmationStateUnreviewed;
    }
    return self;
}

- (void)reset
{
    self.state = MedisaleConfirmationStateUnreviewed;
    self.currentSnapshot = nil;
    self.confirmedSnapshot = nil;
}

- (void)updateCurrentSnapshot:(MeasurementReviewSnapshot *)snapshot
{
    self.currentSnapshot = snapshot;
    if (self.state == MedisaleConfirmationStateUnreviewed ||
        self.confirmedSnapshot == nil) {
        return;
    }
    MeasurementReviewSnapshot *confirmed = self.confirmedSnapshot;
    if (snapshot == nil || !snapshot.isStructurallyValid ||
        ![confirmed matchesImageIdentity:snapshot.imageIdentity] ||
        confirmed.modelSchemaVersion != snapshot.modelSchemaVersion ||
        ![confirmed.calculationMethodVersion
            isEqualToString:snapshot.calculationMethodVersion] ||
        (confirmed.calibration.state != MedisaleCalibrationStateUnknown &&
         snapshot.calibration.state == MedisaleCalibrationStateUnknown)) {
        self.state = MedisaleConfirmationStateInvalidated;
        return;
    }
    self.state = [confirmed isEquivalentToSnapshot:snapshot]
        ? MedisaleConfirmationStateUserConfirmed
        : MedisaleConfirmationStateModifiedAfterConfirmation;
}

- (BOOL)confirmCurrentSnapshot
{
    if (self.currentSnapshot == nil || !self.currentSnapshot.isStructurallyValid ||
        self.state == MedisaleConfirmationStateInvalidated) {
        return NO;
    }
    self.confirmedSnapshot = self.currentSnapshot;
    self.state = MedisaleConfirmationStateUserConfirmed;
    return YES;
}

- (void)invalidate
{
    self.state = MedisaleConfirmationStateInvalidated;
    self.currentSnapshot = nil;
}

@end

@implementation MeasurementValueFormatter

+ (NSString *)displayStringForRawValue:(double)rawValue
                             precision:(NSUInteger)precision
                                locale:(NSLocale *)locale
{
    if (!isfinite(rawValue)) {
        return @"";
    }
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.locale = locale;
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    formatter.minimumFractionDigits = precision;
    formatter.maximumFractionDigits = precision;
    return [formatter stringFromNumber:@(rawValue)] ?: @"";
}

@end
