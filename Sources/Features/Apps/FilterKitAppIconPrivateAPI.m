#import "FilterKitAppIconPrivateAPI.h"
#import <objc/runtime.h>
#import <math.h>

FKApplicationIconLookupStatus FKLookupApplicationIcon(NSString *bundleIdentifier,
                                                        CGFloat scale,
                                                        UIImage * _Nullable * _Nullable imageOut) {
    if (imageOut != NULL) *imageOut = nil;
    @try {
        SEL selector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        Method method = class_getClassMethod(UIImage.class, selector);
        if (method == NULL) return FKApplicationIconLookupStatusUnavailable;

        typedef id (*IconFunction)(id, SEL, NSString *, NSInteger, CGFloat);
        IconFunction function = (IconFunction)method_getImplementation(method);
        UIImage *image = function(UIImage.class, selector, bundleIdentifier, 0, scale);
        if (image == nil || ![image isKindOfClass:UIImage.class] ||
            !isfinite(image.size.width) || !isfinite(image.size.height) ||
            image.size.width <= 0 || image.size.height <= 0) {
            return FKApplicationIconLookupStatusEmptyImage;
        }
        if (imageOut != NULL) *imageOut = image;
        return FKApplicationIconLookupStatusSuccess;
    } @catch (NSException *exception) {
        (void)exception;
        return FKApplicationIconLookupStatusException;
    }
}
