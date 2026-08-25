#import <Cocoa/Cocoa.h>

@class HoldSpacePanState;
@class ViewerController;

NS_ASSUME_NONNULL_BEGIN

@interface TemporaryPanController : NSObject

@property(nonatomic, weak, readonly, nullable) ViewerController *viewer;
@property(nonatomic, strong, readonly) HoldSpacePanState *state;
@property(nonatomic, readonly, getter=isValid) BOOL valid;

- (instancetype)initWithViewer:(ViewerController *)viewer NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)start;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
