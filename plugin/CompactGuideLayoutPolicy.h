#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CompactGuideLayoutMode) {
    CompactGuideLayoutModeStandard = 0,
    CompactGuideLayoutModeNarrow,
};

typedef NS_ENUM(NSInteger, CompactGuidePlacement) {
    CompactGuidePlacementRight = 0,
    CompactGuidePlacementLeft,
    CompactGuidePlacementTopRightFloating,
};

@interface CompactGuideLayoutPolicy : NSObject

+ (CompactGuideLayoutMode)layoutModeForViewerContentSize:(NSSize)viewerContentSize;
+ (NSSize)compactContentSizeForViewerContentSize:(NSSize)viewerContentSize;
+ (NSSize)expandedContentSizeForViewerContentSize:(NSSize)viewerContentSize;
+ (NSPoint)originForViewerFrame:(NSRect)viewerFrame
               viewerContentFrame:(NSRect)viewerContentFrame
                screenVisibleFrame:(NSRect)screenVisibleFrame
                         panelSize:(NSSize)panelSize
                         placement:(CompactGuidePlacement *)placement;

@end

NS_ASSUME_NONNULL_END
