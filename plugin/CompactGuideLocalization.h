#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CompactGuideLocalization : NSObject

- (instancetype)initWithPrimaryStrings:(NSDictionary<NSString *, NSString *> *)primaryStrings
                         fallbackStrings:(NSDictionary<NSString *, NSString *> *)fallbackStrings
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)pluginLocalization;
- (NSString *)stringForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
