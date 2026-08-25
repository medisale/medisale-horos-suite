#import <Cocoa/Cocoa.h>

@class ImageContext;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HoldSpacePanFocusKind) {
    HoldSpacePanFocusKindViewer = 0,
    HoldSpacePanFocusKindTextEntry,
    HoldSpacePanFocusKindButton,
    HoldSpacePanFocusKindOther,
};

@interface HoldSpacePanState : NSObject

@property(nonatomic, readonly, getter=isActive) BOOL active;
@property(nonatomic, copy, readonly, nullable) ImageContext *imageIdentity;
@property(nonatomic, readonly) NSUInteger activationCount;

+ (BOOL)shouldBeginForKeyCode:(unsigned short)keyCode
                 modifierFlags:(NSEventModifierFlags)modifierFlags
                      isRepeat:(BOOL)isRepeat
                     focusKind:(HoldSpacePanFocusKind)focusKind;
+ (HoldSpacePanFocusKind)focusKindForResponder:(nullable NSResponder *)responder
                                      imageView:(nullable NSView *)imageView;
- (BOOL)beginWithImageContext:(nullable ImageContext *)imageContext;
- (BOOL)matchesImageContext:(nullable ImageContext *)imageContext;
- (void)end;

@end

NS_ASSUME_NONNULL_END
