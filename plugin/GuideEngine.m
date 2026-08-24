#import "GuideEngine.h"

#import "CompactGuideLocalization.h"
#import "GuidePreferenceStore.h"

NSNotificationName const GuideEngineDidChangeNotification =
    @"MedisaleGuideEngineDidChangeNotification";

@interface GuideEngine ()
@property(nonatomic, strong) id<GuidePreferenceStore> preferenceStore;
@property(nonatomic, copy, readwrite) NSString *shortInstructionsText;
@property(nonatomic, copy, readwrite) NSString *detailedInstructionsText;
@property(nonatomic, readwrite, getter=isDetailedGuideEnabled) BOOL detailedGuideEnabled;
@end

@implementation GuideEngine

- (instancetype)initWithPreferenceStore:(id<GuidePreferenceStore>)preferenceStore
{
    self = [super init];
    if (self) {
        _preferenceStore = preferenceStore;
        CompactGuideLocalization *localization =
            [CompactGuideLocalization pluginLocalization];
        _shortInstructionsText =
            [localization stringForKey:@"guide.short.instructions"];
        _detailedInstructionsText =
            [localization stringForKey:@"guide.detailed.instructions"];
        _detailedGuideEnabled = preferenceStore.isDetailedGuideEnabled;
    }
    return self;
}

- (BOOL)setDetailedGuideEnabled:(BOOL)enabled error:(NSError **)error
{
    if (self.detailedGuideEnabled == enabled) {
        return YES;
    }
    if (![self.preferenceStore setDetailedGuideEnabled:enabled error:error]) {
        return NO;
    }
    self.detailedGuideEnabled = self.preferenceStore.isDetailedGuideEnabled;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:GuideEngineDidChangeNotification object:self];
    return YES;
}

@end
