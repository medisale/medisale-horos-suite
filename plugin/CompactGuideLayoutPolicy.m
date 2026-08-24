#import "CompactGuideLayoutPolicy.h"

static CGFloat MedisaleClamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
    return MIN(MAX(value, minimum), maximum);
}

@implementation CompactGuideLayoutPolicy

+ (CompactGuideLayoutMode)layoutModeForViewerContentSize:(NSSize)viewerContentSize
{
    return viewerContentSize.width >= 640.0 && viewerContentSize.height >= 480.0
        ? CompactGuideLayoutModeStandard : CompactGuideLayoutModeNarrow;
}

+ (NSSize)compactContentSizeForViewerContentSize:(NSSize)viewerContentSize
{
    if ([self layoutModeForViewerContentSize:viewerContentSize] ==
        CompactGuideLayoutModeStandard) {
        return NSMakeSize(248.0, 124.0);
    }
    CGFloat width = MedisaleClamp(viewerContentSize.width * 0.38, 180.0, 220.0);
    CGFloat height = MedisaleClamp(viewerContentSize.height * 0.36, 140.0, 180.0);
    return NSMakeSize(width, height);
}

+ (NSSize)expandedContentSizeForViewerContentSize:(NSSize)viewerContentSize
{
    NSSize compact = [self compactContentSizeForViewerContentSize:viewerContentSize];
    CGFloat width = MIN(280.0, MAX(compact.width, 248.0));
    CGFloat height = MedisaleClamp(viewerContentSize.height * 0.45,
                                   compact.height + 80.0, 360.0);
    return NSMakeSize(width, height);
}

+ (NSPoint)originForViewerFrame:(NSRect)viewerFrame
               viewerContentFrame:(NSRect)viewerContentFrame
                screenVisibleFrame:(NSRect)screenVisibleFrame
                         panelSize:(NSSize)panelSize
                         placement:(CompactGuidePlacement *)placement
{
    static const CGFloat gap = 8.0;
    CGFloat y = MedisaleClamp(NSMaxY(viewerFrame) - panelSize.height,
                              NSMinY(screenVisibleFrame),
                              NSMaxY(screenVisibleFrame) - panelSize.height);
    CGFloat rightX = NSMaxX(viewerFrame) + gap;
    if (rightX + panelSize.width <= NSMaxX(screenVisibleFrame)) {
        if (placement != NULL) {
            *placement = CompactGuidePlacementRight;
        }
        return NSMakePoint(rightX, y);
    }
    CGFloat leftX = NSMinX(viewerFrame) - gap - panelSize.width;
    if (leftX >= NSMinX(screenVisibleFrame)) {
        if (placement != NULL) {
            *placement = CompactGuidePlacementLeft;
        }
        return NSMakePoint(leftX, y);
    }
    if (placement != NULL) {
        *placement = CompactGuidePlacementTopRightFloating;
    }
    CGFloat x = NSMaxX(viewerContentFrame) - panelSize.width - 12.0;
    CGFloat contentY = NSMaxY(viewerContentFrame) - panelSize.height - 12.0;
    x = MedisaleClamp(x, NSMinX(screenVisibleFrame),
                      NSMaxX(screenVisibleFrame) - panelSize.width);
    contentY = MedisaleClamp(contentY, NSMinY(screenVisibleFrame),
                             NSMaxY(screenVisibleFrame) - panelSize.height);
    return NSMakePoint(x, contentY);
}

@end
