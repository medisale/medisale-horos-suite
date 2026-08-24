#import <Foundation/Foundation.h>

@class LineOverlayModel;
@class GuideEngine;
@class CompactGuideViewState;
@class MeasurementRecord;
@class ViewerController;
@protocol MeasurementPersistenceStore;

NS_ASSUME_NONNULL_BEGIN

typedef void (^MedisalePanelHostInvalidation)(void);
typedef void (^MedisalePanelHostCancellation)(void);

@protocol MeasurementPanelHost <NSObject>

@property(nonatomic, readonly, getter=isVisible) BOOL visible;
@property(nonatomic, readonly, getter=isBound) BOOL bound;

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(nullable LineOverlayModel *)model
                      guideState:(CompactGuideViewState *)guideState
                     guideEngine:(GuideEngine *)guideEngine
                persistenceStore:(nullable id<MeasurementPersistenceStore>)persistenceStore
             existingMeasurement:(nullable MeasurementRecord *)existingMeasurement
                    cancellation:(nullable MedisalePanelHostCancellation)cancellation
                    invalidation:(MedisalePanelHostInvalidation)invalidation;
- (void)bindModel:(LineOverlayModel *)model
 persistenceStore:(id<MeasurementPersistenceStore>)persistenceStore
existingMeasurement:(nullable MeasurementRecord *)existingMeasurement;
- (BOOL)present;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
