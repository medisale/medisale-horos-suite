#import "CompactGuideLocalization.h"

@interface CompactGuideLocalization ()
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *primaryStrings;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *fallbackStrings;
@end

@implementation CompactGuideLocalization

- (instancetype)initWithPrimaryStrings:(NSDictionary<NSString *,NSString *> *)primaryStrings
                         fallbackStrings:(NSDictionary<NSString *,NSString *> *)fallbackStrings
{
    self = [super init];
    if (self) {
        _primaryStrings = [primaryStrings copy];
        _fallbackStrings = [fallbackStrings copy];
    }
    return self;
}

+ (instancetype)pluginLocalization
{
    NSBundle *bundle = [NSBundle bundleForClass:self];
    NSArray<NSString *> *available = @[@"ja", @"en"];
    NSString *preferred = [NSBundle preferredLocalizationsFromArray:available
                                                      forPreferences:NSLocale.preferredLanguages].firstObject ?: @"en";
    NSDictionary *primary = [self stringsForLocalization:preferred bundle:bundle];
    NSDictionary *fallback = [self stringsForLocalization:@"en" bundle:bundle];
    return [[self alloc] initWithPrimaryStrings:primary fallbackStrings:fallback];
}

+ (NSDictionary<NSString *, NSString *> *)stringsForLocalization:(NSString *)localization
                                                            bundle:(NSBundle *)bundle
{
    NSString *path = [bundle pathForResource:@"Localizable"
                                      ofType:@"strings"
                                 inDirectory:nil
                             forLocalization:localization];
    NSDictionary *strings = path == nil ? nil : [NSDictionary dictionaryWithContentsOfFile:path];
    return strings ?: @{};
}

- (NSString *)stringForKey:(NSString *)key
{
    NSString *value = self.primaryStrings[key];
    if (value.length == 0) {
        value = self.fallbackStrings[key];
    }
    return value.length > 0 ? value : key;
}

@end
