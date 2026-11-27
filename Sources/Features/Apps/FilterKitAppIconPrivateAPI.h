#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FKApplicationIconLookupStatus) {
    FKApplicationIconLookupStatusSuccess = 0,
    FKApplicationIconLookupStatusUnavailable = 1,
    FKApplicationIconLookupStatusEmptyImage = 2,
    FKApplicationIconLookupStatusException = 3,
};

FOUNDATION_EXPORT FKApplicationIconLookupStatus FKLookupApplicationIcon(
    NSString *bundleIdentifier,
    CGFloat scale,
    UIImage * _Nullable * _Nullable imageOut
);

NS_ASSUME_NONNULL_END
