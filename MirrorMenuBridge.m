// SPDX-License-Identifier: Apache-2.0
#import <AppKit/AppKit.h>

static NSString *const showControlsNotification = @"org.scrcpy.desktop-launcher.showControls";

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
