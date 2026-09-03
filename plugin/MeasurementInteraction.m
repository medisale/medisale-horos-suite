#import "MeasurementInteraction.h"

#import <math.h>

NSErrorDomain const MedisaleMeasurementInteractionErrorDomain =
    @"jp.medisale.horos.measurement-interaction";

typedef NS_ENUM(NSInteger, MedisaleMeasurementInteractionErrorCode) {
    MedisaleMeasurementInteractionErrorInvalidDefinition = 1,
    MedisaleMeasurementInteractionErrorInvalidOwner,
    MedisaleMeasurementInteractionErrorInvalidPoint,
    MedisaleMeasurementInteractionErrorInvalidSnapshot,
};

static void MedisaleInteractionSetError(NSError **error,
                                        MedisaleMeasurementInteractionErrorCode code,
                                        NSString *description)
{
    if (error != NULL) {
        *error = [NSError errorWithDomain:MedisaleMeasurementInteractionErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
}

static BOOL MedisaleInteractionIdentifierIsValid(NSString *value)
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

static BOOL MedisaleInteractionPointIsInside(NSPoint point,
                                              MeasurementImageContext *context)
{
    return isfinite(point.x) && isfinite(point.y) && point.x >= 0.0 &&
        point.y >= 0.0 && point.x < context.pixelWidth &&
        point.y < context.pixelHeight;
}

static BOOL MedisaleInteractionContextsMatch(MeasurementImageContext *a,
                                              MeasurementImageContext *b)
{
    return a != nil && b != nil && a.frameNumber == b.frameNumber &&
        a.pixelWidth == b.pixelWidth && a.pixelHeight == b.pixelHeight &&
        [a.studyInstanceUID isEqualToString:b.studyInstanceUID] &&
        [a.seriesInstanceUID isEqualToString:b.seriesInstanceUID] &&
        [a.sopInstanceUID isEqualToString:b.sopInstanceUID];
}

@interface MeasurementOverlaySegment ()
- (instancetype)initWithStart:(MedisaleLandmarkIdentifier)start
                           end:(MedisaleLandmarkIdentifier)end;
@end

@implementation MeasurementOverlaySegment
- (instancetype)initWithStart:(MedisaleLandmarkIdentifier)start
                           end:(MedisaleLandmarkIdentifier)end
{
    self = [super init];
    if (self) {
        _startIdentifier = start;
        _endIdentifier = end;
    }
    return self;
}

+ (instancetype)segmentFrom:(MedisaleLandmarkIdentifier)startIdentifier
                          to:(MedisaleLandmarkIdentifier)endIdentifier
                       error:(NSError **)error
{
    if (startIdentifier <= 0 || endIdentifier <= 0 ||
        startIdentifier == endIdentifier) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidDefinition,
            @"The overlay segment endpoints are invalid.");
        return nil;
    }
    return [[self alloc] initWithStart:startIdentifier end:endIdentifier];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface MeasurementInteractionDefinition ()
- (instancetype)initWithIdentifier:(NSString *)identifier
                             method:(MeasurementMethodDefinition *)method
                              order:(NSArray<NSNumber *> *)order
                           segments:(NSArray<MeasurementOverlaySegment *> *)segments;
@end

@implementation MeasurementInteractionDefinition
- (instancetype)initWithIdentifier:(NSString *)identifier
                             method:(MeasurementMethodDefinition *)method
                              order:(NSArray<NSNumber *> *)order
                           segments:(NSArray<MeasurementOverlaySegment *> *)segments
{
    self = [super init];
    if (self) {
        _stableIdentifier = [identifier copy];
        _method = [method copy];
        _collectionOrder = [order copy];
        _overlaySegments = [[NSArray alloc] initWithArray:segments copyItems:YES];
    }
    return self;
}

+ (instancetype)definitionWithStableIdentifier:(NSString *)stableIdentifier
                                          method:(MeasurementMethodDefinition *)method
                                 collectionOrder:(NSArray<NSNumber *> *)collectionOrder
                                 overlaySegments:(NSArray<MeasurementOverlaySegment *> *)overlaySegments
                                           error:(NSError **)error
{
    if (!MedisaleInteractionIdentifierIsValid(stableIdentifier) || method == nil ||
        ![collectionOrder isKindOfClass:NSArray.class] ||
        ![overlaySegments isKindOfClass:NSArray.class]) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidDefinition,
            @"The interaction definition is invalid.");
        return nil;
    }
    NSSet<NSNumber *> *required = [NSSet setWithArray:method.requiredLandmarkIdentifiers];
    NSSet<NSNumber *> *ordered = [NSSet setWithArray:collectionOrder];
    if (collectionOrder.count < 2 || collectionOrder.count > 5 ||
        ordered.count != collectionOrder.count ||
        ![ordered isEqualToSet:required]) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidDefinition,
            @"The collection order must contain two to five required landmarks exactly once.");
        return nil;
    }
    for (id candidate in overlaySegments) {
        if (![candidate isKindOfClass:MeasurementOverlaySegment.class]) {
            MedisaleInteractionSetError(error,
                MedisaleMeasurementInteractionErrorInvalidDefinition,
                @"The overlay topology contains an invalid segment.");
            return nil;
        }
        MeasurementOverlaySegment *segment = candidate;
        if (![required containsObject:@(segment.startIdentifier)] ||
            ![required containsObject:@(segment.endIdentifier)]) {
            MedisaleInteractionSetError(error,
                MedisaleMeasurementInteractionErrorInvalidDefinition,
                @"An overlay segment references an unknown landmark.");
            return nil;
        }
    }
    return [[self alloc] initWithIdentifier:stableIdentifier method:method
        order:collectionOrder segments:overlaySegments];
}

- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@interface MeasurementInteractionSession ()
@property(nonatomic, copy, readwrite) NSString *viewerOwnershipIdentifier;
@property(nonatomic, copy, readwrite) MeasurementInteractionDefinition *definition;
@property(nonatomic, copy, readwrite) MeasurementImageContext *imageContext;
@property(nonatomic, readwrite) MedisaleMeasurementInteractionState state;
@property(nonatomic, readwrite) MedisaleLandmarkIdentifier selectedLandmarkIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NamedImageLandmark *> *mutableLandmarks;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSNumber *, NamedImageLandmark *> *> *undoStack;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSNumber *, NamedImageLandmark *> *> *redoStack;
@property(nonatomic, copy, nullable) NSDictionary<NSNumber *, NamedImageLandmark *> *dragOrigin;
@end

@implementation MeasurementInteractionSession

- (instancetype)initWithOwner:(NSString *)owner
                    definition:(MeasurementInteractionDefinition *)definition
                  imageContext:(MeasurementImageContext *)context
                     landmarks:(NSDictionary<NSNumber *, NamedImageLandmark *> *)landmarks
{
    self = [super init];
    if (self) {
        _viewerOwnershipIdentifier = [owner copy];
        _definition = [definition copy];
        _imageContext = [context copy];
        _mutableLandmarks = [landmarks mutableCopy];
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];
        _state = landmarks.count == definition.collectionOrder.count
            ? MedisaleMeasurementInteractionStateComplete
            : MedisaleMeasurementInteractionStateCollecting;
    }
    return self;
}

+ (instancetype)sessionWithViewerOwnershipIdentifier:(NSString *)viewerOwnershipIdentifier
                                            definition:(MeasurementInteractionDefinition *)definition
                                          imageContext:(MeasurementImageContext *)imageContext
                                                 error:(NSError **)error
{
    if (!MedisaleInteractionIdentifierIsValid(viewerOwnershipIdentifier) ||
        definition == nil || imageContext == nil) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidOwner,
            @"The Viewer ownership or image identity is invalid.");
        return nil;
    }
    return [[self alloc] initWithOwner:viewerOwnershipIdentifier
        definition:definition imageContext:imageContext landmarks:@{}];
}

+ (instancetype)sessionWithViewerOwnershipIdentifier:(NSString *)viewerOwnershipIdentifier
                                            definition:(MeasurementInteractionDefinition *)definition
                                      landmarkSnapshot:(NamedLandmarkSnapshot *)landmarkSnapshot
                                                 error:(NSError **)error
{
    if (!MedisaleInteractionIdentifierIsValid(viewerOwnershipIdentifier) ||
        definition == nil || landmarkSnapshot == nil ||
        definition.method.kind != landmarkSnapshot.method.kind ||
        definition.method.version != landmarkSnapshot.method.version ||
        ![definition.method.stableIdentifier
            isEqualToString:landmarkSnapshot.method.stableIdentifier]) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidSnapshot,
            @"The landmark snapshot does not match the interaction method.");
        return nil;
    }
    NSMutableDictionary *landmarks = [NSMutableDictionary dictionary];
    for (NamedImageLandmark *landmark in landmarkSnapshot.landmarks) {
        landmarks[@(landmark.identifier)] = landmark;
    }
    if (landmarks.count != definition.collectionOrder.count) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidSnapshot,
            @"The landmark snapshot is incomplete.");
        return nil;
    }
    return [[self alloc] initWithOwner:viewerOwnershipIdentifier
        definition:definition imageContext:landmarkSnapshot.imageContext
        landmarks:landmarks];
}

- (NSUInteger)collectedLandmarkCount { return self.mutableLandmarks.count; }
- (BOOL)canUndo { return self.undoStack.count > 0; }
- (BOOL)canRedo { return self.redoStack.count > 0; }

- (NSArray<NamedImageLandmark *> *)landmarks
{
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSNumber *identifier in self.definition.collectionOrder) {
        NamedImageLandmark *landmark = self.mutableLandmarks[identifier];
        if (landmark != nil) [ordered addObject:landmark];
    }
    return [ordered copy];
}

- (NSDictionary<NSNumber *, NamedImageLandmark *> *)landmarkState
{
    return [[NSDictionary alloc] initWithDictionary:self.mutableLandmarks
                                           copyItems:YES];
}

- (void)restoreLandmarkState:(NSDictionary<NSNumber *, NamedImageLandmark *> *)state
{
    self.mutableLandmarks = [state mutableCopy];
    self.selectedLandmarkIdentifier = 0;
    self.dragOrigin = nil;
    self.state = state.count == self.definition.collectionOrder.count
        ? MedisaleMeasurementInteractionStateComplete
        : MedisaleMeasurementInteractionStateCollecting;
}

- (BOOL)acceptsEventsForViewerOwnershipIdentifier:(NSString *)viewerOwnershipIdentifier
                                      imageContext:(MeasurementImageContext *)imageContext
{
    return self.state != MedisaleMeasurementInteractionStateInvalidated &&
        self.state != MedisaleMeasurementInteractionStateCancelled &&
        [self.viewerOwnershipIdentifier isEqualToString:viewerOwnershipIdentifier] &&
        MedisaleInteractionContextsMatch(self.imageContext, imageContext);
}

- (BOOL)collectImagePoint:(NSPoint)imagePoint error:(NSError **)error
{
    if (self.state != MedisaleMeasurementInteractionStateCollecting ||
        !MedisaleInteractionPointIsInside(imagePoint, self.imageContext) ||
        self.mutableLandmarks.count >= self.definition.collectionOrder.count) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidPoint,
            @"The image point cannot be collected in the current state.");
        return NO;
    }
    [self.undoStack addObject:[self landmarkState]];
    [self.redoStack removeAllObjects];
    NSNumber *identifier = self.definition.collectionOrder[self.mutableLandmarks.count];
    NamedImageLandmark *landmark = [NamedImageLandmark
        landmarkWithIdentifier:identifier.integerValue imagePoint:imagePoint error:error];
    if (landmark == nil) {
        [self.undoStack removeLastObject];
        return NO;
    }
    self.mutableLandmarks[identifier] = landmark;
    if (self.mutableLandmarks.count == self.definition.collectionOrder.count) {
        self.state = MedisaleMeasurementInteractionStateComplete;
    }
    return YES;
}

- (BOOL)selectLandmarkIdentifier:(MedisaleLandmarkIdentifier)identifier
{
    if (self.state != MedisaleMeasurementInteractionStateComplete ||
        self.mutableLandmarks[@(identifier)] == nil) {
        return NO;
    }
    self.selectedLandmarkIdentifier = identifier;
    return YES;
}

- (BOOL)beginSelectedLandmarkDrag
{
    if (self.state != MedisaleMeasurementInteractionStateComplete ||
        self.selectedLandmarkIdentifier <= 0) return NO;
    self.dragOrigin = [self landmarkState];
    self.state = MedisaleMeasurementInteractionStateEditing;
    return YES;
}

- (BOOL)updateSelectedLandmarkToImagePoint:(NSPoint)imagePoint error:(NSError **)error
{
    if (self.state != MedisaleMeasurementInteractionStateEditing ||
        !MedisaleInteractionPointIsInside(imagePoint, self.imageContext)) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidPoint,
            @"The edited landmark must remain inside the owned image.");
        return NO;
    }
    NamedImageLandmark *landmark = [NamedImageLandmark
        landmarkWithIdentifier:self.selectedLandmarkIdentifier
        imagePoint:imagePoint error:error];
    if (landmark == nil) return NO;
    self.mutableLandmarks[@(self.selectedLandmarkIdentifier)] = landmark;
    return YES;
}

- (BOOL)endSelectedLandmarkDrag
{
    if (self.state != MedisaleMeasurementInteractionStateEditing ||
        self.dragOrigin == nil) return NO;
    NSDictionary *origin = self.dragOrigin;
    self.dragOrigin = nil;
    if (![origin isEqualToDictionary:self.mutableLandmarks]) {
        [self.undoStack addObject:origin];
        [self.redoStack removeAllObjects];
    }
    self.state = MedisaleMeasurementInteractionStateComplete;
    return YES;
}

- (void)cancelCurrentOperation
{
    if (self.state == MedisaleMeasurementInteractionStateEditing &&
        self.dragOrigin != nil) {
        [self restoreLandmarkState:self.dragOrigin];
        return;
    }
    if (self.selectedLandmarkIdentifier != 0) {
        self.selectedLandmarkIdentifier = 0;
        return;
    }
    if (self.state == MedisaleMeasurementInteractionStateCollecting) {
        [self.mutableLandmarks removeAllObjects];
        [self.undoStack removeAllObjects];
        [self.redoStack removeAllObjects];
        self.state = MedisaleMeasurementInteractionStateCancelled;
    }
}

- (void)handleFocusLoss
{
    if (self.state == MedisaleMeasurementInteractionStateEditing &&
        self.dragOrigin != nil) {
        [self restoreLandmarkState:self.dragOrigin];
    } else {
        self.selectedLandmarkIdentifier = 0;
    }
}

- (BOOL)undo
{
    if (self.state == MedisaleMeasurementInteractionStateEditing ||
        self.undoStack.count == 0) return NO;
    [self.redoStack addObject:[self landmarkState]];
    NSDictionary *state = self.undoStack.lastObject;
    [self.undoStack removeLastObject];
    [self restoreLandmarkState:state];
    return YES;
}

- (BOOL)redo
{
    if (self.state == MedisaleMeasurementInteractionStateEditing ||
        self.redoStack.count == 0) return NO;
    [self.undoStack addObject:[self landmarkState]];
    NSDictionary *state = self.redoStack.lastObject;
    [self.redoStack removeLastObject];
    [self restoreLandmarkState:state];
    return YES;
}

- (BOOL)invalidateIfImageContextChanged:(MeasurementImageContext *)imageContext
{
    if (MedisaleInteractionContextsMatch(self.imageContext, imageContext)) return NO;
    [self invalidate];
    return YES;
}

- (void)invalidate
{
    self.state = MedisaleMeasurementInteractionStateInvalidated;
    self.selectedLandmarkIdentifier = 0;
    self.dragOrigin = nil;
    [self.mutableLandmarks removeAllObjects];
    [self.undoStack removeAllObjects];
    [self.redoStack removeAllObjects];
}

- (NamedImageLandmark *)landmarkForIdentifier:(MedisaleLandmarkIdentifier)identifier
{
    return self.mutableLandmarks[@(identifier)];
}

- (NamedLandmarkSnapshot *)immutableLandmarkSnapshotWithError:(NSError **)error
{
    if (self.state != MedisaleMeasurementInteractionStateComplete) {
        MedisaleInteractionSetError(error,
            MedisaleMeasurementInteractionErrorInvalidSnapshot,
            @"Only a complete interaction can produce a landmark snapshot.");
        return nil;
    }
    return [NamedLandmarkSnapshot snapshotWithMethod:self.definition.method
        imageContext:self.imageContext landmarks:self.landmarks error:error];
}
@end

@implementation MeasurementLandmarkHitTester
+ (MedisaleLandmarkIdentifier)nearestLandmarkToViewPoint:(NSPoint)viewPoint
                                    displayPointsByIdentifier:
                                        (NSDictionary<NSNumber *,NSValue *> *)displayPoints
                                               hitRadius:(double)hitRadius
{
    if (!isfinite(viewPoint.x) || !isfinite(viewPoint.y) ||
        !isfinite(hitRadius) || hitRadius <= 0.0) return 0;
    MedisaleLandmarkIdentifier nearest = 0;
    double nearestDistanceSquared = hitRadius * hitRadius;
    for (NSNumber *identifier in displayPoints) {
        NSValue *value = displayPoints[identifier];
        if (![identifier isKindOfClass:NSNumber.class] ||
            ![value isKindOfClass:NSValue.class]) continue;
        NSPoint point = value.pointValue;
        double deltaX = viewPoint.x - point.x;
        double deltaY = viewPoint.y - point.y;
        double distanceSquared = deltaX * deltaX + deltaY * deltaY;
        if (isfinite(distanceSquared) && distanceSquared <= nearestDistanceSquared) {
            if (distanceSquared < nearestDistanceSquared || nearest == 0 ||
                identifier.integerValue < nearest) {
                nearest = identifier.integerValue;
                nearestDistanceSquared = distanceSquared;
            }
        }
    }
    return nearest;
}
@end
