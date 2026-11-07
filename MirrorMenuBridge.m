// SPDX-License-Identifier: Apache-2.0
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static NSString *const showControlsNotification = @"org.scrcpy.desktop-launcher.showControls";
typedef bool (*SDLKeySender)(uint64_t, uint32_t, int, int, bool);
typedef void (*InsertTextIMP)(id, SEL, id, NSRange);

static SDLKeySender sendSDLKey;
static InsertTextIMP originalInsertText;
static NSPasteboard *(*originalGeneralPasteboard)(id, SEL);
static NSMutableArray<NSString *> *pendingText;
static NSPasteboard *activePasteboard;
static BOOL pasteInProgress;

static NSPasteboard *bridgeGeneralPasteboard(id receiver, SEL selector) {
    return activePasteboard ?: originalGeneralPasteboard(receiver, selector);
}

static void sendNextText(void) {
    if (pasteInProgress || !pendingText.count) { return; }
    NSString *text = pendingText.firstObject;
    NSPasteboard *temporary = [NSPasteboard pasteboardWithUniqueName];
    [temporary clearContents];
    if (![temporary setString:text forType:NSPasteboardTypeString]) {
        [temporary releaseGlobally];
        [pendingText removeObjectAtIndex:0];
        fprintf(stderr, "Mac IME clipboard transfer failed\n");
        sendNextText();
        return;
    }

    pasteInProgress = YES;
    activePasteboard = temporary;
    dispatch_async(dispatch_get_main_queue(), ^{
        // scrcpy's Alt+V shortcut sets the Android clipboard and pastes it.
        sendSDLKey(0, 1, 0, 226, true);
        sendSDLKey(0, 1, 0, 25, true);
        sendSDLKey(0, 1, 0, 25, false);
        sendSDLKey(0, 1, 0, 226, false);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4),
                       dispatch_get_main_queue(), ^{
            activePasteboard = nil;
            [temporary releaseGlobally];
            [pendingText removeObjectAtIndex:0];
            pasteInProgress = NO;
            sendNextText();
        });
    });
}

static void insertMacText(id responder, SEL selector, id input, NSRange replacementRange) {
    NSString *text = nil;
    if ([input isKindOfClass:NSString.class]) { text = input; }
    else if ([input isKindOfClass:NSAttributedString.class]) { text = [input string]; }
    if (!text.length || [text canBeConvertedToEncoding:NSASCIIStringEncoding]) {
        originalInsertText(responder, selector, input, replacementRange);
        return;
    }

    SEL clearPendingKey = NSSelectorFromString(@"clearPendingKey");
    if ([responder respondsToSelector:clearPendingKey]) {
        ((void (*)(id, SEL))[responder methodForSelector:clearPendingKey])(responder, clearPendingKey);
    }
    originalInsertText(responder, selector, @"", NSMakeRange(NSNotFound, 0));
    [pendingText addObject:text];
    sendNextText();
}

static void installMacIMEBridge(void) {
    Class responder = objc_getClass("SDL3TranslatorResponder");
    Method method = responder ? class_getInstanceMethod(responder,
        @selector(insertText:replacementRange:)) : NULL;
    Method pasteboardMethod = class_getClassMethod(NSPasteboard.class,
                                                   @selector(generalPasteboard));
    sendSDLKey = (SDLKeySender)dlsym(RTLD_DEFAULT, "SDL_SendKeyboardKey");
    if (!method || !pasteboardMethod || !sendSDLKey) {
        fprintf(stderr, "Mac IME bridge unavailable\n");
        return;
    }
    pendingText = [NSMutableArray array];
    originalGeneralPasteboard = (NSPasteboard *(*)(id, SEL))method_setImplementation(
        pasteboardMethod, (IMP)bridgeGeneralPasteboard);
    originalInsertText = (InsertTextIMP)method_setImplementation(method, (IMP)insertMacText);
    fprintf(stderr, "Mac IME bridge enabled\n");
}

@interface MirrorMenuBridge : NSObject
- (void)showControls:(id)sender;
@end

@implementation MirrorMenuBridge
- (void)showControls:(id)sender {
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:showControlsNotification object:nil userInfo:nil deliverImmediately:YES];
}
@end

__attribute__((constructor)) static void installMenuBridge(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        const char *imeBridge = getenv("SCRCPY_MAC_IME_BRIDGE");
        if (imeBridge && strcmp(imeBridge, "1") == 0) {
            installMacIMEBridge();
        }
        static MirrorMenuBridge *bridge;
        bridge = [MirrorMenuBridge new];
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *activeTimer) {
            if (!NSApp || NSApp.windows.count == 0 || NSApp.mainMenu.numberOfItems == 0) { return; }
            NSMenu *menu = [NSApp.mainMenu itemAtIndex:0].submenu;
            if (!menu) { return; }
            NSMenuItem *item = [menu itemWithTitle:@"Settings…"];
            if (!item) { item = [menu itemWithTitle:@"Preferences…"]; }
            if (!item) {
                item = [[NSMenuItem alloc] initWithTitle:@"连接与设置…" action:NULL keyEquivalent:@","];
                [menu insertItem:item atIndex:MIN(1, menu.numberOfItems)];
            }
            item.title = @"连接与设置…";
            item.target = bridge;
            item.action = @selector(showControls:);
            item.keyEquivalent = @",";
            item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
            item.enabled = YES;
            [activeTimer invalidate];
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    });
}
