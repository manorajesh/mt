//
//  TerminalView.m
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import "TerminalView.h"
#import "../mtCore/mtCore.h"

@implementation TerminalView

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    if (!self.core) return;
    
    NSString *chars = event.characters;
    NSData *data = [chars dataUsingEncoding:NSUTF8StringEncoding];
    self.core->send((const char*)data.bytes, data.length);
}

@end
