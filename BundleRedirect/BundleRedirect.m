#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "BundleRedirect.h"

// The canonical path of an existing folder: symbolic links resolved, so
// /tmp and /private/tmp compare equal. Nil when the folder does not exist.
static NSString *CKRealPath(NSString *path) {
    if (path == nil) { return nil; }
    char resolved[PATH_MAX];
    if (realpath(path.fileSystemRepresentation, resolved) == NULL) { return nil; }
    return [NSString stringWithUTF8String:resolved];
}

// The path SwiftPM asks for, redirected to Contents/Resources when it names a
// .bundle directly in the app's root folder that does not exist there, and
// the same bundle exists in Contents/Resources. Every other path is unchanged,
// so the redirect can only ever point at the app's own signed resources.
static NSString *CKRedirectedPath(NSString *path) {
    if (path == nil || ![path.pathExtension isEqualToString:@"bundle"]) { return path; }
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) { return path; }
    NSString *name = path.lastPathComponent;
    // A name only: no separators and no parent references can come through.
    if (name.length == 0 || [name containsString:@"/"] || [name hasPrefix:@"."]) { return path; }
    NSBundle *main = [NSBundle mainBundle];
    NSString *root = CKRealPath(main.bundlePath);
    NSString *parent = CKRealPath(path.stringByDeletingLastPathComponent);
    if (root == nil || parent == nil || ![parent isEqualToString:root]) { return path; }
    NSString *candidate = [main.resourcePath stringByAppendingPathComponent:name];
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) { return candidate; }
    return path;
}

@implementation NSBundle (CKBundleRedirect)

- (instancetype)ck_initWithPath:(NSString *)path {
    // After the exchange below, this call runs the original -initWithPath:.
    return [self ck_initWithPath:CKRedirectedPath(path)];
}

@end

void CKInstallBundleRedirect(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method original = class_getInstanceMethod([NSBundle class], @selector(initWithPath:));
        Method replacement = class_getInstanceMethod([NSBundle class], @selector(ck_initWithPath:));
        if (original != NULL && replacement != NULL) {
            method_exchangeImplementations(original, replacement);
        }
    });
}
