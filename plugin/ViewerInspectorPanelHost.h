#import <Cocoa/Cocoa.h>

#import "MeasurementPanelHost.h"

NS_ASSUME_NONNULL_BEGIN

@interface ViewerInspectorPanelHost : NSObject <MeasurementPanelHost, NSWindowDelegate>

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(nullable LineOverlayModel *)model
                      guideState:(CompactGuideViewState *)guideState
                     guideEngine:(GuideEngine *)guideEngine
                persistenceStore:(nullable id<MeasurementPersistenceStore>)persistenceStore
             existingMeasurement:(nullable MeasurementRecord *)existingMeasurement
                    cancellation:(nullable MedisalePanelHostCancellation)cancellation
                    invalidation:(MedisalePanelHostInvalidation)invalidation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
