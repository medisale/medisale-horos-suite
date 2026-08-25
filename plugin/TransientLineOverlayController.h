#import <Foundation/Foundation.h>

@class LineOverlayModel;
@class HoldSpacePanState;
@class ViewerController;

NS_ASSUME_NONNULL_BEGIN

typedef void (^MedisaleOverlayInvalidation)(void);

@interface TransientLineOverlayController : NSObject

@property(nonatomic, weak, readonly) ViewerController *viewer;
@property(nonatomic, strong, readonly) LineOverlayModel *model;
@property(nonatomic, readonly, getter=isActive) BOOL active;

- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(LineOverlayModel *)model
                        panState:(nullable HoldSpacePanState *)panState
                    invalidation:(MedisaleOverlayInvalidation)invalidation NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithViewer:(ViewerController *)viewer
                           model:(LineOverlayModel *)model
                    invalidation:(MedisaleOverlayInvalidation)invalidation;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)start;
- (void)cancelCurrentInteraction;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
