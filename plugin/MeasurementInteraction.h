#import <Foundation/Foundation.h>

#import "MeasurementDomain.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MedisaleMeasurementInteractionState) {
    MedisaleMeasurementInteractionStateCollecting = 1,
    MedisaleMeasurementInteractionStateComplete,
    MedisaleMeasurementInteractionStateEditing,
    MedisaleMeasurementInteractionStateCancelled,
    MedisaleMeasurementInteractionStateInvalidated,
};

@interface MeasurementOverlaySegment : NSObject <NSCopying>
@property(nonatomic, readonly) MedisaleLandmarkIdentifier startIdentifier;
@property(nonatomic, readonly) MedisaleLandmarkIdentifier endIdentifier;
+ (nullable instancetype)segmentFrom:(MedisaleLandmarkIdentifier)startIdentifier
                                  to:(MedisaleLandmarkIdentifier)endIdentifier
                               error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementInteractionDefinition : NSObject <NSCopying>
@property(nonatomic, copy, readonly) NSString *stableIdentifier;
@property(nonatomic, copy, readonly) MeasurementMethodDefinition *method;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *collectionOrder;
@property(nonatomic, copy, readonly) NSArray<MeasurementOverlaySegment *> *overlaySegments;
+ (nullable instancetype)definitionWithStableIdentifier:(NSString *)stableIdentifier
                                                  method:(MeasurementMethodDefinition *)method
                                         collectionOrder:(NSArray<NSNumber *> *)collectionOrder
                                         overlaySegments:(NSArray<MeasurementOverlaySegment *> *)overlaySegments
                                                   error:(NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementInteractionSession : NSObject
@property(nonatomic, copy, readonly) NSString *viewerOwnershipIdentifier;
@property(nonatomic, copy, readonly) MeasurementInteractionDefinition *definition;
@property(nonatomic, copy, readonly) MeasurementImageContext *imageContext;
@property(nonatomic, readonly) MedisaleMeasurementInteractionState state;
@property(nonatomic, readonly) NSUInteger collectedLandmarkCount;
@property(nonatomic, readonly) BOOL canUndo;
@property(nonatomic, readonly) BOOL canRedo;
@property(nonatomic, readonly) MedisaleLandmarkIdentifier selectedLandmarkIdentifier;
@property(nonatomic, copy, readonly) NSArray<NamedImageLandmark *> *landmarks;

+ (nullable instancetype)sessionWithViewerOwnershipIdentifier:(NSString *)viewerOwnershipIdentifier
                                                    definition:(MeasurementInteractionDefinition *)definition
                                                  imageContext:(MeasurementImageContext *)imageContext
                                                         error:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)sessionWithViewerOwnershipIdentifier:(NSString *)viewerOwnershipIdentifier
                                                    definition:(MeasurementInteractionDefinition *)definition
                                              landmarkSnapshot:(NamedLandmarkSnapshot *)landmarkSnapshot
                                                         error:(NSError * _Nullable * _Nullable)error;
- (BOOL)acceptsEventsForViewerOwnershipIdentifier:(NSString *)viewerOwnershipIdentifier
                                      imageContext:(MeasurementImageContext *)imageContext;
- (BOOL)collectImagePoint:(NSPoint)imagePoint
                    error:(NSError * _Nullable * _Nullable)error;
- (BOOL)selectLandmarkIdentifier:(MedisaleLandmarkIdentifier)identifier;
- (BOOL)beginSelectedLandmarkDrag;
- (BOOL)updateSelectedLandmarkToImagePoint:(NSPoint)imagePoint
                                     error:(NSError * _Nullable * _Nullable)error;
- (BOOL)endSelectedLandmarkDrag;
- (void)cancelCurrentOperation;
- (void)handleFocusLoss;
- (BOOL)undo;
- (BOOL)redo;
- (BOOL)invalidateIfImageContextChanged:(MeasurementImageContext *)imageContext;
- (void)invalidate;
- (nullable NamedImageLandmark *)landmarkForIdentifier:
    (MedisaleLandmarkIdentifier)identifier;
- (nullable NamedLandmarkSnapshot *)immutableLandmarkSnapshotWithError:
    (NSError * _Nullable * _Nullable)error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface MeasurementLandmarkHitTester : NSObject
+ (MedisaleLandmarkIdentifier)nearestLandmarkToViewPoint:(NSPoint)viewPoint
                                    displayPointsByIdentifier:
                                        (NSDictionary<NSNumber *, NSValue *> *)displayPoints
                                               hitRadius:(double)hitRadius;
@end

NS_ASSUME_NONNULL_END
