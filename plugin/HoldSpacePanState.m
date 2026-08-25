#import "HoldSpacePanState.h"

#import "ImageContext.h"

@interface HoldSpacePanState ()
@property(nonatomic, readwrite, getter=isActive) BOOL active;
@property(nonatomic, copy, readwrite, nullable) ImageContext *imageIdentity;
@property(nonatomic, readwrite) NSUInteger activationCount;
@end

@implementation HoldSpacePanState

+ (HoldSpacePanFocusKind)focusKindForResponder:(NSResponder *)responder
                                      imageView:(NSView *)imageView
{
    if ([responder isKindOfClass:[NSTextView class]] ||
        [responder isKindOfClass:[NSTextField class]]) {
        return HoldSpacePanFocusKindTextEntry;
    }
    if ([responder isKindOfClass:[NSButton class]]) {
        return HoldSpacePanFocusKindButton;
    }
    if ([responder isKindOfClass:[NSView class]] && imageView != nil) {
        NSView *view = (NSView *)responder;
        if (view == imageView || [view isDescendantOf:imageView] ||
            [imageView isDescendantOf:view]) {
            return HoldSpacePanFocusKindViewer;
        }
    }
    return HoldSpacePanFocusKindOther;
}

+ (BOOL)shouldBeginForKeyCode:(unsigned short)keyCode
                 modifierFlags:(NSEventModifierFlags)modifierFlags
                      isRepeat:(BOOL)isRepeat
                     focusKind:(HoldSpacePanFocusKind)focusKind
{
    NSEventModifierFlags relevant = modifierFlags &
        NSEventModifierFlagDeviceIndependentFlagsMask;
    return keyCode == 49 && relevant == 0 && !isRepeat &&
        focusKind == HoldSpacePanFocusKindViewer;
}

- (BOOL)beginWithImageContext:(ImageContext *)imageContext
{
    if (self.active || imageContext == nil) {
        return NO;
    }
    self.imageIdentity = [imageContext copy];
    self.active = YES;
    self.activationCount++;
    return YES;
}

- (BOOL)matchesImageContext:(ImageContext *)imageContext
{
    ImageContext *expected = self.imageIdentity;
    return self.active && expected != nil && imageContext != nil &&
        [expected.studyInstanceUID isEqualToString:imageContext.studyInstanceUID] &&
        [expected.seriesInstanceUID isEqualToString:imageContext.seriesInstanceUID] &&
        [expected.sopInstanceUID isEqualToString:imageContext.sopInstanceUID] &&
        expected.frameNumber == imageContext.frameNumber;
}

- (void)end
{
    self.active = NO;
    self.imageIdentity = nil;
}

@end
