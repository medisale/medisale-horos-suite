#import <Cocoa/Cocoa.h>

@class ViewerController;
@class HoldSpacePanState;

NS_ASSUME_NONNULL_BEGIN

typedef void (^MedisaleTwoPointCompletion)(BOOL cancelled, NSArray<NSValue *> *points);
typedef void (^MedisaleTwoPointProgress)(NSUInteger pointCount);

@interface TwoPointInputController : NSObject

@property(nonatomic, weak, readonly) ViewerController *viewer;
@property(nonatomic, copy, readonly) NSArray<NSValue *> *points;

- (instancetype)initWithViewer:(ViewerController *)viewer
                       panState:(nullable HoldSpacePanState *)panState
                       progress:(nullable MedisaleTwoPointProgress)progress
                     completion:(MedisaleTwoPointCompletion)completion NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithViewer:(ViewerController *)viewer
                       progress:(nullable MedisaleTwoPointProgress)progress
                     completion:(MedisaleTwoPointCompletion)completion;
- (instancetype)initWithViewer:(ViewerController *)viewer
                     completion:(MedisaleTwoPointCompletion)completion;
- (instancetype)init NS_UNAVAILABLE;
- (void)start;
- (void)cancel;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
