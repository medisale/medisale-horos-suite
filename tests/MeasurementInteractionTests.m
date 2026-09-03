#import <Foundation/Foundation.h>

#import "LegacyDistanceInteractionAdapter.h"
#import "MeasurementInteraction.h"

static NSUInteger assertionCount = 0;

static void Assert(BOOL condition, NSString *message)
{
    assertionCount++;
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface MeasurementMethodDefinition (InteractionTestFactory)
- (instancetype)initWithEvaluator:(id<MeasurementMethodEvaluating>)evaluator;
@end

@interface SyntheticScalarEvaluator : NSObject <MeasurementMethodEvaluating>
@property(nonatomic) NSUInteger landmarkCount;
@end

@implementation SyntheticScalarEvaluator
- (MedisaleMeasurementKind)measurementKind { return (MedisaleMeasurementKind)700; }
- (NSString *)stableKindCode { return @"synthetic-scalar"; }
- (NSString *)stableMethodIdentifier { return @"synthetic-interaction-only"; }
- (NSInteger)methodVersion { return 1; }
- (MedisaleMeasurementUnit)resultUnit { return MedisaleMeasurementUnitPixels; }
- (NSArray<NSNumber *> *)requiredLandmarkIdentifiers
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger index = 0; index < self.landmarkCount; index++) {
        [result addObject:@(100 + index)];
    }
    return result;
}
- (NSString *)stableCodeForLandmarkIdentifier:(MedisaleLandmarkIdentifier)identifier
{
    return [NSString stringWithFormat:@"point-%ld", (long)identifier];
}
- (MedisaleLandmarkIdentifier)landmarkIdentifierForStableCode:(NSString *)stableCode
{
    if (![stableCode hasPrefix:@"point-"]) return 0;
    return (MedisaleLandmarkIdentifier)[[stableCode substringFromIndex:6] integerValue];
}
- (BOOL)validateLandmarkSnapshot:(NamedLandmarkSnapshot *)landmarks
                          result:(VersionedMeasurementResult *)result
                           error:(NSError **)error
{
    (void)error;
    return landmarks.landmarks.count == self.landmarkCount && result.rawValue >= 0.0;
}
@end

static MeasurementImageContext *Context(NSString *instance, NSInteger frame)
{
    return [MeasurementImageContext contextWithStudyInstanceUID:@"synthetic-study"
        seriesInstanceUID:@"synthetic-series" sopInstanceUID:instance
        frameNumber:frame pixelWidth:256 pixelHeight:192 error:nil];
}

static MeasurementInteractionDefinition *Definition(NSUInteger count)
{
    SyntheticScalarEvaluator *evaluator = [[SyntheticScalarEvaluator alloc] init];
    evaluator.landmarkCount = count;
    MeasurementMethodDefinition *method = [[MeasurementMethodDefinition alloc]
        initWithEvaluator:evaluator];
    NSMutableArray<MeasurementOverlaySegment *> *segments = [NSMutableArray array];
    for (NSUInteger index = 1; index < count; index++) {
        MeasurementOverlaySegment *segment = [MeasurementOverlaySegment
            segmentFrom:(MedisaleLandmarkIdentifier)(99 + index)
            to:(MedisaleLandmarkIdentifier)(100 + index) error:nil];
        [segments addObject:segment];
    }
    return [MeasurementInteractionDefinition
        definitionWithStableIdentifier:[NSString stringWithFormat:
            @"synthetic-interaction-%lu", (unsigned long)count]
        method:method collectionOrder:evaluator.requiredLandmarkIdentifiers
        overlaySegments:segments error:nil];
}

static MeasurementInteractionSession *Session(NSUInteger count, NSString *owner,
                                               NSString *instance, NSInteger frame)
{
    NSError *error = nil;
    MeasurementInteractionSession *session = [MeasurementInteractionSession
        sessionWithViewerOwnershipIdentifier:owner definition:Definition(count)
        imageContext:Context(instance, frame) error:&error];
    Assert(session != nil && error == nil, @"valid interaction session created");
    return session;
}

static void CollectAll(MeasurementInteractionSession *session)
{
    NSUInteger count = session.definition.collectionOrder.count;
    for (NSUInteger index = 0; index < count; index++) {
        NSError *error = nil;
        NSPoint point = NSMakePoint(20.25 + index * 15.0, 30.5 + index * 10.0);
        Assert([session collectImagePoint:point error:&error] && error == nil,
            @"method-defined landmark collected");
        Assert(session.collectedLandmarkCount == index + 1,
            @"collection progress follows method order");
    }
    Assert(session.state == MedisaleMeasurementInteractionStateComplete,
        @"session completes at method-defined count");
}

static void TestDefinitions(void)
{
    MeasurementInteractionDefinition *legacy =
        [LegacyDistanceInteractionAdapter interactionDefinition];
    Assert(legacy != nil && legacy.collectionOrder.count == 2 &&
        legacy.overlaySegments.count == 1,
        @"legacy topology is supplied by its adapter");

    for (NSUInteger count = 2; count <= 5; count++) {
        MeasurementInteractionDefinition *definition = Definition(count);
        Assert(definition != nil, @"synthetic definition accepted");
        Assert(definition.collectionOrder.count == count,
            @"definition retains generic collection order");
        Assert(definition.overlaySegments.count == count - 1,
            @"definition retains typed segment topology");
        Assert(definition.method.requiredLandmarkIdentifiers.count == count,
            @"method and interaction landmark sets agree");
        for (MeasurementOverlaySegment *segment in definition.overlaySegments) {
            Assert(segment.startIdentifier > 0 && segment.endIdentifier > 0,
                @"segment contains typed landmark identifiers");
        }
    }

    NSError *error = nil;
    MeasurementInteractionDefinition *valid = Definition(3);
    Assert([MeasurementInteractionDefinition definitionWithStableIdentifier:@"bad order"
        method:valid.method collectionOrder:valid.collectionOrder
        overlaySegments:valid.overlaySegments error:&error] == nil && error != nil,
        @"unsafe stable identifier rejected");
    error = nil;
    Assert([MeasurementInteractionDefinition definitionWithStableIdentifier:@"duplicate"
        method:valid.method collectionOrder:@[@100, @100, @102]
        overlaySegments:valid.overlaySegments error:&error] == nil && error != nil,
        @"duplicate collection identifier rejected");
    error = nil;
    MeasurementOverlaySegment *unknown = [MeasurementOverlaySegment
        segmentFrom:100 to:999 error:nil];
    Assert([MeasurementInteractionDefinition definitionWithStableIdentifier:@"unknown-segment"
        method:valid.method collectionOrder:valid.collectionOrder
        overlaySegments:@[unknown] error:&error] == nil && error != nil,
        @"segment outside required set rejected");
    error = nil;
    Assert([MeasurementOverlaySegment segmentFrom:100 to:100 error:&error] == nil &&
        error != nil, @"self segment rejected");

    error = nil;
    Assert(Definition(1) == nil,
        @"single-landmark topology is rejected");
    error = nil;
    Assert(Definition(6) == nil,
        @"topology above five landmarks is rejected");
}

static void TestCollectionAndSnapshots(void)
{
    for (NSUInteger count = 2; count <= 5; count++) {
        MeasurementInteractionSession *session = Session(count, @"viewer-one",
                                                          @"image-a", 0);
        Assert(session.state == MedisaleMeasurementInteractionStateCollecting,
            @"new session starts collecting");
        Assert(session.collectedLandmarkCount == 0, @"new session starts empty");
        Assert([session acceptsEventsForViewerOwnershipIdentifier:@"viewer-one"
            imageContext:Context(@"image-a", 0)], @"owned Viewer and image accepted");
        Assert(![session acceptsEventsForViewerOwnershipIdentifier:@"viewer-two"
            imageContext:Context(@"image-a", 0)], @"other Viewer rejected");
        Assert(![session acceptsEventsForViewerOwnershipIdentifier:@"viewer-one"
            imageContext:Context(@"image-b", 0)], @"other SOP rejected");
        Assert(![session acceptsEventsForViewerOwnershipIdentifier:@"viewer-one"
            imageContext:Context(@"image-a", 1)], @"other frame rejected");
        NSError *error = nil;
        Assert(![session collectImagePoint:NSMakePoint(-1, 10) error:&error] &&
            error != nil, @"outside point rejected without state mutation");
        Assert(session.collectedLandmarkCount == 0, @"rejected point preserves input");
        CollectAll(session);
        error = nil;
        NamedLandmarkSnapshot *snapshot =
            [session immutableLandmarkSnapshotWithError:&error];
        Assert(snapshot != nil && error == nil, @"complete immutable snapshot emitted");
        Assert(snapshot.landmarks.count == count, @"snapshot retains every landmark");
        for (NSUInteger index = 0; index < count; index++) {
            NamedImageLandmark *landmark = snapshot.landmarks[index];
            Assert(landmark.identifier ==
                session.definition.collectionOrder[index].integerValue,
                @"snapshot preserves method-defined order");
        }
        MeasurementInteractionSession *restored = [MeasurementInteractionSession
            sessionWithViewerOwnershipIdentifier:@"viewer-one"
            definition:session.definition landmarkSnapshot:snapshot error:&error];
        Assert(restored != nil && restored.state ==
            MedisaleMeasurementInteractionStateComplete,
            @"immutable snapshot restores a complete session");
    }
}

static void TestEditingHistoryAndCancel(void)
{
    MeasurementInteractionSession *session = Session(4, @"viewer-one", @"image-a", 0);
    CollectAll(session);
    MedisaleLandmarkIdentifier selected =
        session.definition.collectionOrder[2].integerValue;
    NSPoint original = [session landmarkForIdentifier:selected].imagePoint;
    Assert([session selectLandmarkIdentifier:selected], @"named landmark selected");
    Assert(session.selectedLandmarkIdentifier == selected, @"selection is explicit");
    Assert([session beginSelectedLandmarkDrag], @"selected landmark drag begins");
    Assert(session.state == MedisaleMeasurementInteractionStateEditing,
        @"drag enters editing state");
    Assert(![session updateSelectedLandmarkToImagePoint:NSMakePoint(300, 20)
        error:nil], @"out-of-bounds drag rejected");
    NSPoint edited = NSMakePoint(111.25, 77.5);
    Assert([session updateSelectedLandmarkToImagePoint:edited error:nil],
        @"in-bounds drag updates image coordinate");
    Assert(NSEqualPoints([session landmarkForIdentifier:selected].imagePoint, edited),
        @"edited coordinate is image-coordinate truth");
    [session cancelCurrentOperation];
    Assert(NSEqualPoints([session landmarkForIdentifier:selected].imagePoint, original),
        @"Escape-style cancellation restores drag origin");
    Assert(session.state == MedisaleMeasurementInteractionStateComplete,
        @"cancelled drag returns complete state");

    Assert([session selectLandmarkIdentifier:selected] &&
        [session beginSelectedLandmarkDrag], @"second drag begins");
    Assert([session updateSelectedLandmarkToImagePoint:edited error:nil] &&
        [session endSelectedLandmarkDrag], @"second drag commits");
    Assert(session.canUndo && !session.canRedo, @"committed edit enters local history");
    Assert([session undo], @"edit undo succeeds");
    Assert(NSEqualPoints([session landmarkForIdentifier:selected].imagePoint, original),
        @"undo restores prior image coordinate");
    Assert([session redo], @"edit redo succeeds");
    Assert(NSEqualPoints([session landmarkForIdentifier:selected].imagePoint, edited),
        @"redo restores edited image coordinate");
    Assert([session selectLandmarkIdentifier:selected] &&
        [session beginSelectedLandmarkDrag], @"focus-loss drag begins");
    Assert([session updateSelectedLandmarkToImagePoint:NSMakePoint(90, 90) error:nil],
        @"focus-loss drag can update temporarily");
    [session handleFocusLoss];
    Assert(NSEqualPoints([session landmarkForIdentifier:selected].imagePoint, edited),
        @"focus loss safely restores uncommitted drag");
    Assert(session.selectedLandmarkIdentifier == 0,
        @"focus loss clears selection");

    MeasurementInteractionSession *partial = Session(3, @"viewer-one", @"image-a", 0);
    Assert([partial collectImagePoint:NSMakePoint(10, 10) error:nil],
        @"partial collection accepted");
    [partial cancelCurrentOperation];
    Assert(partial.state == MedisaleMeasurementInteractionStateCancelled,
        @"Escape-style collection cancellation is explicit");
    Assert(partial.collectedLandmarkCount == 0,
        @"cancelled collection leaves no partial point");
    Assert(![partial collectImagePoint:NSMakePoint(20, 20) error:nil],
        @"cancelled session accepts no post-cancel event");
}

static void TestHitTestingAndLifecycle(void)
{
    NSDictionary *display = @{
        @100: [NSValue valueWithPoint:NSMakePoint(10, 10)],
        @101: [NSValue valueWithPoint:NSMakePoint(30, 10)],
        @102: [NSValue valueWithPoint:NSMakePoint(50, 10)],
    };
    Assert([MeasurementLandmarkHitTester nearestLandmarkToViewPoint:NSMakePoint(11, 10)
        displayPointsByIdentifier:display hitRadius:8] == 100,
        @"hit tester selects nearest named landmark");
    Assert([MeasurementLandmarkHitTester nearestLandmarkToViewPoint:NSMakePoint(20, 10)
        displayPointsByIdentifier:display hitRadius:10] == 100,
        @"hit tester tie is deterministic");
    Assert([MeasurementLandmarkHitTester nearestLandmarkToViewPoint:NSMakePoint(80, 80)
        displayPointsByIdentifier:display hitRadius:8] == 0,
        @"hit tester rejects empty area");
    Assert([MeasurementLandmarkHitTester nearestLandmarkToViewPoint:NSMakePoint(10, 10)
        displayPointsByIdentifier:display hitRadius:0] == 0,
        @"invalid hit radius rejected");

    for (NSUInteger iteration = 0; iteration < 20; iteration++) {
        MeasurementInteractionSession *session = Session(3,
            [NSString stringWithFormat:@"viewer-%lu", (unsigned long)iteration],
            @"image-a", 0);
        CollectAll(session);
        Assert([session invalidateIfImageContextChanged:Context(@"image-b", 0)],
            @"SOP switch invalidates stale session");
        Assert(session.state == MedisaleMeasurementInteractionStateInvalidated,
            @"identity invalidation is terminal");
        Assert(session.collectedLandmarkCount == 0,
            @"identity invalidation removes stale landmarks");
        Assert(![session selectLandmarkIdentifier:100],
            @"invalidated session accepts no selection");
        Assert(![session acceptsEventsForViewerOwnershipIdentifier:
            [NSString stringWithFormat:@"viewer-%lu", (unsigned long)iteration]
            imageContext:Context(@"image-b", 0)],
            @"invalidated session accepts no post-cleanup event");
    }

    MeasurementInteractionSession *first = Session(2, @"viewer-one", @"image-a", 0);
    MeasurementInteractionSession *second = Session(2, @"viewer-two", @"image-a", 0);
    Assert([first collectImagePoint:NSMakePoint(10, 10) error:nil],
        @"Viewer one collects independently");
    Assert(second.collectedLandmarkCount == 0,
        @"Viewer two remains isolated");
    [first invalidate];
    Assert([second collectImagePoint:NSMakePoint(20, 20) error:nil],
        @"closing Viewer one does not affect Viewer two");
    [second invalidate];
    Assert(second.state == MedisaleMeasurementInteractionStateInvalidated,
        @"plugin stop or termination invalidates remaining session");
}

int main(void)
{
    @autoreleasepool {
        TestDefinitions();
        TestCollectionAndSnapshots();
        TestEditingHistoryAndCancel();
        TestHitTestingAndLifecycle();
        NSLog(@"PASS: %lu measurement interaction assertions",
              (unsigned long)assertionCount);
    }
    return 0;
}
