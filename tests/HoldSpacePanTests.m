#import <Cocoa/Cocoa.h>

#import "HoldSpacePanState.h"
#import "ImageContext.h"

static NSUInteger assertionCount = 0;

static void Assert(BOOL condition, NSString *message)
{
    assertionCount++;
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static ImageContext *Context(NSString *study, NSString *series,
                             NSString *instance, NSInteger frame)
{
    return [[ImageContext alloc] initWithStudyInstanceUID:study
        seriesInstanceUID:series sopInstanceUID:instance frameNumber:frame
        pixelWidth:64 pixelHeight:64 pixelSpacingX:0.5 pixelSpacingY:0.75];
}

static void TestKeyboardPolicy(void)
{
    Assert([HoldSpacePanState shouldBeginForKeyCode:49 modifierFlags:0
        isRepeat:NO focusKind:HoldSpacePanFocusKindViewer], @"bare Space begins");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:48 modifierFlags:0
        isRepeat:NO focusKind:HoldSpacePanFocusKindViewer], @"non-Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49
        modifierFlags:NSEventModifierFlagCommand isRepeat:NO
        focusKind:HoldSpacePanFocusKindViewer], @"Command-Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49
        modifierFlags:NSEventModifierFlagControl isRepeat:NO
        focusKind:HoldSpacePanFocusKindViewer], @"Control-Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49
        modifierFlags:NSEventModifierFlagOption isRepeat:NO
        focusKind:HoldSpacePanFocusKindViewer], @"Option-Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49
        modifierFlags:NSEventModifierFlagShift isRepeat:NO
        focusKind:HoldSpacePanFocusKindViewer], @"Shift-Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49
        modifierFlags:NSEventModifierFlagCapsLock isRepeat:NO
        focusKind:HoldSpacePanFocusKindViewer], @"Caps-Lock Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49
        modifierFlags:NSEventModifierFlagFunction isRepeat:NO
        focusKind:HoldSpacePanFocusKindViewer], @"Function-Space rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49 modifierFlags:0
        isRepeat:YES focusKind:HoldSpacePanFocusKindViewer], @"repeat rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49 modifierFlags:0
        isRepeat:NO focusKind:HoldSpacePanFocusKindTextEntry], @"text entry rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49 modifierFlags:0
        isRepeat:NO focusKind:HoldSpacePanFocusKindButton], @"button focus rejected");
    Assert(![HoldSpacePanState shouldBeginForKeyCode:49 modifierFlags:0
        isRepeat:NO focusKind:HoldSpacePanFocusKindOther], @"other focus rejected");
}

static void TestViewerFocusPolicy(void)
{
    NSView *viewerRoot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    NSView *imageView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 80, 80)];
    NSView *imageChild = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    NSView *unrelated = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [viewerRoot addSubview:imageView];
    [imageView addSubview:imageChild];

    Assert([HoldSpacePanState focusKindForResponder:imageView imageView:imageView] ==
        HoldSpacePanFocusKindViewer, @"image view focus accepted");
    Assert([HoldSpacePanState focusKindForResponder:imageChild imageView:imageView] ==
        HoldSpacePanFocusKindViewer, @"image descendant focus accepted");
    Assert([HoldSpacePanState focusKindForResponder:viewerRoot imageView:imageView] ==
        HoldSpacePanFocusKindViewer, @"verified Viewer ancestor focus accepted");
    Assert([HoldSpacePanState focusKindForResponder:unrelated imageView:imageView] ==
        HoldSpacePanFocusKindOther, @"unrelated view focus rejected");
    Assert([HoldSpacePanState focusKindForResponder:[[NSTextField alloc] init]
        imageView:imageView] == HoldSpacePanFocusKindTextEntry,
        @"text field focus rejected before Viewer ancestry");
    Assert([HoldSpacePanState focusKindForResponder:[[NSButton alloc] init]
        imageView:imageView] == HoldSpacePanFocusKindButton,
        @"button focus rejected before Viewer ancestry");
}

static void TestIdentityBoundLifecycle(void)
{
    HoldSpacePanState *state = [[HoldSpacePanState alloc] init];
    ImageContext *identity = Context(@"study-a", @"series-a", @"instance-a", 0);
    Assert(!state.isActive, @"initially inactive");
    Assert(state.imageIdentity == nil, @"initial identity absent");
    Assert(state.activationCount == 0, @"initial activation count");
    Assert(![state beginWithImageContext:nil], @"nil identity rejected");
    Assert([state beginWithImageContext:identity], @"first activation accepted");
    Assert(state.isActive, @"active after begin");
    Assert(state.activationCount == 1, @"activation counted once");
    Assert(state.imageIdentity != nil, @"independent identity retained");
    Assert([state matchesImageContext:identity], @"exact identity matches");
    Assert(![state matchesImageContext:Context(@"study-b", @"series-a",
        @"instance-a", 0)], @"study isolation");
    Assert(![state matchesImageContext:Context(@"study-a", @"series-b",
        @"instance-a", 0)], @"series isolation");
    Assert(![state matchesImageContext:Context(@"study-a", @"series-a",
        @"instance-b", 0)], @"SOP isolation");
    Assert(![state matchesImageContext:Context(@"study-a", @"series-a",
        @"instance-a", 1)], @"frame isolation");
    Assert(![state matchesImageContext:nil], @"nil current identity rejected");
    Assert(![state beginWithImageContext:identity], @"duplicate begin rejected");
    [state end];
    Assert(!state.isActive, @"end deactivates");
    Assert(state.imageIdentity == nil, @"end releases identity");
    Assert(![state matchesImageContext:identity], @"inactive state cannot route");
    [state end];
    Assert(!state.isActive, @"end is idempotent");
    Assert([state beginWithImageContext:Context(@"study-a", @"series-a",
        @"instance-a", 1)], @"new frame can begin after end");
    Assert(state.activationCount == 2, @"second activation counted");
    [state end];
}

static void TestNativeEventConstruction(void)
{
    CGEventRef source = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown,
                                                CGPointMake(20, 30),
                                                kCGMouseButtonLeft);
    CGEventRef downEvent = CGEventCreateCopy(source);
    CGEventSetType(downEvent, kCGEventOtherMouseDown);
    CGEventSetIntegerValueField(downEvent, kCGMouseEventButtonNumber,
                                kCGMouseButtonCenter);
    NSEvent *down = [NSEvent eventWithCGEvent:downEvent];
    CGEventRef dragEvent = CGEventCreateCopy(source);
    CGEventSetType(dragEvent, kCGEventOtherMouseDragged);
    CGEventSetIntegerValueField(dragEvent, kCGMouseEventButtonNumber,
                                kCGMouseButtonCenter);
    NSEvent *drag = [NSEvent eventWithCGEvent:dragEvent];
    CGEventRef upEvent = CGEventCreateCopy(source);
    CGEventSetType(upEvent, kCGEventOtherMouseUp);
    CGEventSetIntegerValueField(upEvent, kCGMouseEventButtonNumber,
                                kCGMouseButtonCenter);
    NSEvent *up = [NSEvent eventWithCGEvent:upEvent];
    Assert(down.type == NSEventTypeOtherMouseDown, @"native other down type");
    Assert(drag.type == NSEventTypeOtherMouseDragged, @"native other drag type");
    Assert(up.type == NSEventTypeOtherMouseUp, @"native other up type");
    Assert(down.buttonNumber == 2, @"other down uses middle button");
    Assert(drag.buttonNumber == 2, @"other drag uses middle button");
    Assert(up.buttonNumber == 2, @"other up uses middle button");
    CGPoint retained = CGEventGetLocation(drag.CGEvent);
    Assert(retained.x == 20 && retained.y == 30,
           @"native event retains source coordinate");
    CFRelease(upEvent);
    CFRelease(dragEvent);
    CFRelease(downEvent);
    CFRelease(source);
}

int main(void)
{
    @autoreleasepool {
        TestKeyboardPolicy();
        TestViewerFocusPolicy();
        TestIdentityBoundLifecycle();
        TestNativeEventConstruction();
        NSLog(@"PASS: Hold-Space PAN policy/state (%lu assertions)",
              (unsigned long)assertionCount);
    }
    return 0;
}
