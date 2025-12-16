//
//  main.mm
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}
