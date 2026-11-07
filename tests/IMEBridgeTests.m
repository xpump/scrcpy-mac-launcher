#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdbool.h>
#include <stdint.h>

static NSPasteboard *testPasteboard;
static NSMutableArray<NSNumber *> *keyEvents;
static NSMutableArray<NSString *> *pastedTexts;

static NSPasteboard *mockGeneralPasteboard(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return testPasteboard;
}

__attribute__((visibility("default")))
bool SDL_SendKeyboardKey(uint64_t timestamp, uint32_t keyboardID,
                         int rawcode, int scancode, bool down) {
    (void)timestamp;
    (void)keyboardID;
    (void)rawcode;
    [keyEvents addObject:@(scancode * (down ? 1 : -1))];
    if (scancode == 25 && down) {
        [pastedTexts addObject:[[NSPasteboard generalPasteboard]
                                stringForType:NSPasteboardTypeString] ?: @""];
    }
    return true;
}

@interface SDL3TranslatorResponder : NSObject
@property (nonatomic, copy) NSString *lastText;
- (void)insertText:(id)text replacementRange:(NSRange)range;
- (void)clearPendingKey;
@end

@implementation SDL3TranslatorResponder
- (void)insertText:(id)text replacementRange:(NSRange)range {
    if (range.location != NSNotFound) {
        SDL_SendKeyboardKey(0, 1, 0, 42, true);
        SDL_SendKeyboardKey(0, 1, 0, 42, false);
    }
    self.lastText = [text isKindOfClass:NSAttributedString.class] ? [text string] : text;
}
- (void)clearPendingKey {}
@end

int main(void) {
    @autoreleasepool {
        testPasteboard = [NSPasteboard pasteboardWithUniqueName];
        NSPasteboardItem *item = [NSPasteboardItem new];
        [item setString:@"original" forType:NSPasteboardTypeString];
        [item setData:[@"rich" dataUsingEncoding:NSUTF8StringEncoding]
                forType:@"org.scrcpy.test-rich"];
        [testPasteboard writeObjects:@[item]];
        Method generalPasteboard = class_getClassMethod(NSPasteboard.class,
                                                         @selector(generalPasteboard));
        method_setImplementation(generalPasteboard, (IMP)mockGeneralPasteboard);
        keyEvents = [NSMutableArray array];
        pastedTexts = [NSMutableArray array];

        dispatch_async(dispatch_get_main_queue(), ^{
            SDL3TranslatorResponder *responder = [SDL3TranslatorResponder new];
            [responder insertText:@"abc" replacementRange:NSMakeRange(NSNotFound, 0)];
            NSCAssert([responder.lastText isEqualToString:@"abc"], @"ASCII should use SDK input");
            [responder insertText:@"测试" replacementRange:NSMakeRange(0, 1)];
            [responder insertText:[[NSAttributedString alloc] initWithString:@"中文"]
                replacementRange:NSMakeRange(NSNotFound, 0)];
            NSCAssert([responder.lastText isEqualToString:@""], @"Chinese should bypass SDK input");

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                NSArray *expectedKeys = @[@226, @25, @(-25), @(-226),
                                          @226, @25, @(-25), @(-226)];
                NSArray *expectedTexts = @[@"测试", @"中文"];
                NSCAssert([keyEvents isEqualToArray:expectedKeys], @"paste key sequence changed");
                NSCAssert([pastedTexts isEqualToArray:expectedTexts],
                          @"committed text did not reach paste shortcut");
                NSCAssert([[testPasteboard stringForType:NSPasteboardTypeString]
                           isEqualToString:@"original"], @"system clipboard text changed");
                NSCAssert([[[testPasteboard.pasteboardItems firstObject]
                            dataForType:@"org.scrcpy.test-rich"]
                           isEqualToData:[@"rich" dataUsingEncoding:NSUTF8StringEncoding]],
                          @"system clipboard metadata changed");
                NSCAssert([NSPasteboard generalPasteboard] == testPasteboard,
                          @"temporary clipboard remained active");
                puts("IME bridge tests passed");
                exit(0);
            });
        });
        dispatch_main();
    }
}
