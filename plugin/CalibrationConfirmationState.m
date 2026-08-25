#import "CalibrationConfirmationState.h"

#import "ImageContext.h"
#import <float.h>
#import <math.h>

NSInteger const MedisaleCalibrationModelSchemaVersion = 2;
NSInteger const MedisaleConfirmationModelSchemaVersion = 2;
NSString * const MedisaleDistanceCalculationMethodVersion = @"distance-image-v1";
NSString * const MedisaleDisplayRoundingPolicyVersion = @"fixed-decimal-v1";
NSUInteger const MedisaleDisplayPrecision = 2;

static NSString * const MedisaleStateErrorDomain = @"jp.medisale.calibration-confirmation";
static NSString * const MedisaleRuntimeSpacingSourceIdentifier =
    @"horos-runtime-image-spacing";
static NSString * const MedisaleRuntimeSpacingMethodVersion =
    @"horos-adapter-image-context-v1";
static NSUInteger const MedisaleMaximumWarningCount = 8;
static NSUInteger const MedisaleMaximumWarningCodeLength = 48;

static NSString * const MedisaleWarningRowSpacingUnavailable =
    @"row-spacing-unavailable";
static NSString * const MedisaleWarningColumnSpacingUnavailable =
    @"column-spacing-unavailable";
static NSString * const MedisaleWarningSpacingProvenanceUnknown =
    @"spacing-provenance-unknown";
static NSString * const MedisaleWarningAnisotropicSpacing =
    @"anisotropic-spacing";
static NSString * const MedisaleWarningUncalibratedRuntimeSpacing =
    @"uncalibrated-runtime-spacing";
static NSString * const MedisaleWarningTagProvenanceUnverified =
    @"tag-provenance-unverified";
static NSString * const MedisaleWarningProvenanceLost = @"provenance-lost";

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

static BOOL MedisaleExactIntegerNumber(NSNumber *number)
{
    if (![number isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID()) {
        return NO;
    }
    double value = number.doubleValue;
    return isfinite(value) && floor(value) == value &&
        value >= (double)NSIntegerMin && value <= (double)NSIntegerMax;
}

static BOOL MedisaleNonBooleanNumber(id value)
{
    return [value isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}

static NSSet<NSString *> *MedisaleKnownWarningCodes(void)
{
    static NSSet<NSString *> *codes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        codes = [NSSet setWithArray:@[
            MedisaleWarningRowSpacingUnavailable,
            MedisaleWarningColumnSpacingUnavailable,
            MedisaleWarningSpacingProvenanceUnknown,
            MedisaleWarningAnisotropicSpacing,
            MedisaleWarningUncalibratedRuntimeSpacing,
            MedisaleWarningTagProvenanceUnverified,
            MedisaleWarningProvenanceLost,
        ]];
    });
    return codes;
}

static BOOL MedisaleWarningCodeIsSafe(NSString *code)
{
    if (![code isKindOfClass:NSString.class] || code.length == 0 ||
        code.length > MedisaleMaximumWarningCodeLength ||
        ![MedisaleKnownWarningCodes() containsObject:code]) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet
        characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
    return [code rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static BOOL MedisaleWarningCodesAreValid(NSArray *warnings, BOOL allowEmpty)
{
    if (![warnings isKindOfClass:NSArray.class] ||
        warnings.count > MedisaleMaximumWarningCount ||
        (!allowEmpty && warnings.count == 0)) {
        return NO;
    }
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id value in warnings) {
        if (!MedisaleWarningCodeIsSafe(value) || [seen containsObject:value]) {
            return NO;
        }
        [seen addObject:value];
    }
    return YES;
}

static NSArray<NSString *> *MedisaleSanitizedUnknownWarnings(NSArray *warnings)
{
    NSSet<NSString *> *unknownCodes = [NSSet setWithArray:@[
        MedisaleWarningRowSpacingUnavailable,
        MedisaleWarningColumnSpacingUnavailable,
        MedisaleWarningSpacingProvenanceUnknown,
        MedisaleWarningProvenanceLost,
    ]];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id value in warnings) {
        if (result.count == MedisaleMaximumWarningCount) {
            break;
        }
        if (MedisaleWarningCodeIsSafe(value) &&
            [unknownCodes containsObject:value] &&
            ![result containsObject:value]) {
            [result addObject:value];
        }
    }
    if (result.count == 0) {
        [result addObject:MedisaleWarningSpacingProvenanceUnknown];
    }
    return result;
}

static BOOL MedisaleArraysContainSameObjects(NSArray<NSString *> *left,
                                              NSArray<NSString *> *right)
{
    return left.count == right.count &&
        [[NSSet setWithArray:left] isEqualToSet:[NSSet setWithArray:right]];
}

static BOOL MedisalePointIsInsideImage(NSPoint point, NSInteger width,
                                        NSInteger height)
{
    return isfinite(point.x) && isfinite(point.y) && point.x >= 0.0 &&
        point.y >= 0.0 && point.x < (double)width && point.y < (double)height;
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
        [warnings addObject:MedisaleWarningRowSpacingUnavailable];
    }
    if (!MedisaleFinitePositive(column)) {
        [warnings addObject:MedisaleWarningColumnSpacingUnavailable];
    }
    if (warnings.count > 0) {
        return [self unknownModelWithWarnings:warnings];
    }
    [warnings addObject:MedisaleWarningUncalibratedRuntimeSpacing];
    [warnings addObject:MedisaleWarningTagProvenanceUnverified];
    if (row != column) {
        [warnings addObject:MedisaleWarningAnisotropicSpacing];
    }
    return [[self alloc] initWithState:MedisaleCalibrationStateDICOMSpacingOnly
        sourceCategory:MedisaleCalibrationSourceCategoryHorosRuntimeImageSpacing
        sourceIdentifier:MedisaleRuntimeSpacingSourceIdentifier
        methodVersion:MedisaleRuntimeSpacingMethodVersion
        rowSpacing:row columnSpacing:column units:@"mm"
        derivationStatus:MedisaleCalibrationDerivationStatusTagLevelUnverified
        warnings:warnings modelSchemaVersion:MedisaleCalibrationModelSchemaVersion];
}

+ (instancetype)unknownModelWithWarnings:(NSArray<NSString *> *)warnings
{
    NSArray<NSString *> *reasons = MedisaleSanitizedUnknownWarnings(warnings);
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
        ? @[] : @[MedisaleWarningAnisotropicSpacing];
    return [[self alloc] initWithState:MedisaleCalibrationStateCalibrated
        sourceCategory:MedisaleCalibrationSourceCategoryExplicitCalibration
        sourceIdentifier:sourceIdentifier methodVersion:methodVersion
        rowSpacing:rowSpacing columnSpacing:columnSpacing units:@"mm"
        derivationStatus:MedisaleCalibrationDerivationStatusExplicit
        warnings:warnings modelSchemaVersion:MedisaleCalibrationModelSchemaVersion];
}

- (BOOL)hasUsableSpacing
{
    return self.isStructurallyValid &&
        self.state != MedisaleCalibrationStateUnknown;
}

- (BOOL)isStructurallyValid
{
    if (self.modelSchemaVersion != MedisaleCalibrationModelSchemaVersion ||
        ![self.units isEqualToString:@"mm"] ||
        !MedisaleWarningCodesAreValid(self.warnings,
            self.state != MedisaleCalibrationStateUnknown)) {
        return NO;
    }
    switch (self.state) {
        case MedisaleCalibrationStateCalibrated: {
            if (self.sourceCategory !=
                    MedisaleCalibrationSourceCategoryExplicitCalibration ||
                self.derivationStatus != MedisaleCalibrationDerivationStatusExplicit ||
                !MedisaleSafeIdentifier(self.sourceIdentifier) ||
                !MedisaleSafeIdentifier(self.methodVersion) ||
                !MedisaleFinitePositive(self.rowSpacing) ||
                !MedisaleFinitePositive(self.columnSpacing)) {
                return NO;
            }
            NSArray<NSString *> *expected = self.rowSpacing == self.columnSpacing
                ? @[] : @[MedisaleWarningAnisotropicSpacing];
            return MedisaleArraysContainSameObjects(self.warnings, expected);
        }
        case MedisaleCalibrationStateDICOMSpacingOnly: {
            if (self.sourceCategory !=
                    MedisaleCalibrationSourceCategoryHorosRuntimeImageSpacing ||
                self.derivationStatus !=
                    MedisaleCalibrationDerivationStatusTagLevelUnverified ||
                ![self.sourceIdentifier
                    isEqualToString:MedisaleRuntimeSpacingSourceIdentifier] ||
                ![self.methodVersion
                    isEqualToString:MedisaleRuntimeSpacingMethodVersion] ||
                !MedisaleFinitePositive(self.rowSpacing) ||
                !MedisaleFinitePositive(self.columnSpacing)) {
                return NO;
            }
            NSMutableArray<NSString *> *expected = [NSMutableArray arrayWithArray:@[
                MedisaleWarningUncalibratedRuntimeSpacing,
                MedisaleWarningTagProvenanceUnverified,
            ]];
            if (self.rowSpacing != self.columnSpacing) {
                [expected addObject:MedisaleWarningAnisotropicSpacing];
            }
            return MedisaleArraysContainSameObjects(self.warnings, expected);
        }
        case MedisaleCalibrationStateUnknown: {
            NSSet<NSString *> *allowed = [NSSet setWithArray:@[
                MedisaleWarningRowSpacingUnavailable,
                MedisaleWarningColumnSpacingUnavailable,
                MedisaleWarningSpacingProvenanceUnknown,
                MedisaleWarningProvenanceLost,
            ]];
            return self.sourceCategory == MedisaleCalibrationSourceCategoryNone &&
                self.derivationStatus == MedisaleCalibrationDerivationStatusMissing &&
                self.sourceIdentifier.length == 0 && self.methodVersion.length == 0 &&
                isnan(self.rowSpacing) && isnan(self.columnSpacing) &&
                [[NSSet setWithArray:self.warnings] isSubsetOfSet:allowed];
        }
        default:
            return NO;
    }
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
    NSSet<NSString *> *requiredKeys = [NSSet setWithArray:@[
        @"state", @"sourceCategory", @"sourceIdentifier", @"methodVersion",
        @"rowSpacing", @"columnSpacing", @"units", @"derivationStatus",
        @"warnings", @"modelSchemaVersion",
    ]];
    if (![dictionary isKindOfClass:NSDictionary.class] ||
        ![[NSSet setWithArray:dictionary.allKeys] isEqualToSet:requiredKeys]) {
        MedisaleSetError(error, 2, @"Calibration model schema or values are incompatible.");
        return nil;
    }
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
    if (!MedisaleExactIntegerNumber(schema) ||
        schema.integerValue != MedisaleCalibrationModelSchemaVersion ||
        !MedisaleExactIntegerNumber(state) ||
        !MedisaleExactIntegerNumber(source) ||
        !MedisaleExactIntegerNumber(derivation) ||
        !MedisaleNonBooleanNumber(row) ||
        !MedisaleNonBooleanNumber(column) ||
        ![sourceIdentifier isKindOfClass:NSString.class] ||
        ![methodVersion isKindOfClass:NSString.class] ||
        ![units isKindOfClass:NSString.class] ||
        ![warnings isKindOfClass:NSArray.class]) {
        MedisaleSetError(error, 2, @"Calibration model schema or values are incompatible.");
        return nil;
    }
    CalibrationProvenanceModel *model = [[self alloc]
        initWithState:state.integerValue
        sourceCategory:source.integerValue sourceIdentifier:sourceIdentifier
        methodVersion:methodVersion rowSpacing:row.doubleValue
        columnSpacing:column.doubleValue units:units
        derivationStatus:derivation.integerValue warnings:warnings
        modelSchemaVersion:schema.integerValue];
    if (!model.isStructurallyValid) {
        MedisaleSetError(error, 3, @"Calibration provenance is invalid.");
        return nil;
    }
    return model;
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
    ImageContext *identity = self.imageIdentity;
    if (!MedisaleSafeIdentifier(identity.studyInstanceUID) ||
        !MedisaleSafeIdentifier(identity.seriesInstanceUID) ||
        !MedisaleSafeIdentifier(identity.sopInstanceUID) ||
        identity.frameNumber < 0 || identity.pixelWidth <= 0 ||
        identity.pixelHeight <= 0 ||
        !MedisalePointIsInsideImage(self.pointA, identity.pixelWidth,
                                    identity.pixelHeight) ||
        !MedisalePointIsInsideImage(self.pointB, identity.pixelWidth,
                                    identity.pixelHeight) ||
        !isfinite(self.rawResult) ||
        ![self.calculationMethodVersion
            isEqualToString:MedisaleDistanceCalculationMethodVersion] ||
        ![self.displayRoundingPolicyVersion
            isEqualToString:MedisaleDisplayRoundingPolicyVersion] ||
        self.displayPrecision != MedisaleDisplayPrecision ||
        self.modelSchemaVersion != MedisaleConfirmationModelSchemaVersion ||
        !self.calibration.isStructurallyValid) {
        return NO;
    }

    double expectedResult = hypot(self.pointB.x - self.pointA.x,
                                  self.pointB.y - self.pointA.y);
    double tolerance = DBL_EPSILON * fmax(1.0, expectedResult) * 8.0;
    if (fabs(self.rawResult - expectedResult) > tolerance) {
        return NO;
    }

    BOOL contextSpacingAvailable =
        MedisaleFinitePositive(identity.pixelSpacingX) &&
        MedisaleFinitePositive(identity.pixelSpacingY);
    switch (self.calibration.state) {
        case MedisaleCalibrationStateDICOMSpacingOnly:
            return contextSpacingAvailable &&
                self.calibration.columnSpacing == identity.pixelSpacingX &&
                self.calibration.rowSpacing == identity.pixelSpacingY;
        case MedisaleCalibrationStateUnknown:
            return !contextSpacingAvailable;
        case MedisaleCalibrationStateCalibrated:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)matchesImageIdentity:(ImageContext *)imageIdentity
{
    BOOL spacingXEqual = imageIdentity != nil &&
        ((isnan(self.imageIdentity.pixelSpacingX) &&
          isnan(imageIdentity.pixelSpacingX)) ||
         self.imageIdentity.pixelSpacingX == imageIdentity.pixelSpacingX);
    BOOL spacingYEqual = imageIdentity != nil &&
        ((isnan(self.imageIdentity.pixelSpacingY) &&
          isnan(imageIdentity.pixelSpacingY)) ||
         self.imageIdentity.pixelSpacingY == imageIdentity.pixelSpacingY);
    return imageIdentity != nil &&
        [self.imageIdentity.studyInstanceUID isEqualToString:imageIdentity.studyInstanceUID] &&
        [self.imageIdentity.seriesInstanceUID isEqualToString:imageIdentity.seriesInstanceUID] &&
        [self.imageIdentity.sopInstanceUID isEqualToString:imageIdentity.sopInstanceUID] &&
        self.imageIdentity.frameNumber == imageIdentity.frameNumber &&
        self.imageIdentity.pixelWidth == imageIdentity.pixelWidth &&
        self.imageIdentity.pixelHeight == imageIdentity.pixelHeight &&
        spacingXEqual && spacingYEqual;
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
    NSSet<NSString *> *requiredKeys = [NSSet setWithArray:@[
        @"study", @"series", @"sop", @"frame", @"width", @"height",
        @"spacingX", @"spacingY", @"pointAX", @"pointAY", @"pointBX",
        @"pointBY", @"calibration", @"calculationMethodVersion",
        @"rawResult", @"displayRoundingPolicyVersion", @"displayPrecision",
        @"modelSchemaVersion",
    ]];
    if (![dictionary isKindOfClass:NSDictionary.class] ||
        ![[NSSet setWithArray:dictionary.allKeys] isEqualToSet:requiredKeys]) {
        MedisaleSetError(error, 4, @"Confirmation snapshot schema is incompatible.");
        return nil;
    }
    NSArray<NSString *> *stringKeys = @[@"study", @"series", @"sop",
        @"calculationMethodVersion", @"displayRoundingPolicyVersion"];
    for (NSString *key in stringKeys) {
        if (![dictionary[key] isKindOfClass:NSString.class]) {
            MedisaleSetError(error, 4, @"Confirmation snapshot text value is missing.");
            return nil;
        }
    }
    NSArray<NSString *> *integerKeys = @[@"frame", @"width", @"height",
        @"displayPrecision", @"modelSchemaVersion"];
    for (NSString *key in integerKeys) {
        if (!MedisaleExactIntegerNumber(dictionary[key])) {
            MedisaleSetError(error, 5, @"Confirmation snapshot integer value is invalid.");
            return nil;
        }
    }
    NSArray<NSString *> *numberKeys = @[@"spacingX", @"spacingY", @"pointAX",
        @"pointAY", @"pointBX", @"pointBY", @"rawResult"];
    for (NSString *key in numberKeys) {
        if (!MedisaleNonBooleanNumber(dictionary[key])) {
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
        displayPrecision:(NSUInteger)[dictionary[@"displayPrecision"] integerValue]
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
