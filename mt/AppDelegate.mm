//
//  AppDelegate.mm
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import "AppDelegate.h"
#import "TerminalView.h"
#import "../mtCore/mtCore.h"

@implementation AppDelegate {
    NSWindow *window;
    TerminalView *view;
    mtCore *core;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {

    core = new mtCore();
    if (!core->start()) [NSApp terminate:nil];

    NSRect frame = NSMakeRect(100, 100, 800, 600);
    window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:(NSWindowStyleMaskTitled |
                                                    NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskResizable)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:@"mt"];
    [window makeKeyAndOrderFront:nil];

    view = [[TerminalView alloc] initWithFrame:window.contentView.bounds];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.core = core;
    [window setContentView:view];

    core->onOutput = [&](const char* buf, size_t len) {
        fwrite(buf, 1, len, stdout); // for now
    };

    [window makeFirstResponder:view];
}

- (void)applicationWillTerminate:(NSNotification *)note {
    delete core;
}

@end
