//
//  TerminalView.h
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import <Cocoa/Cocoa.h>

class mtCore;

@interface TerminalView : NSView
@property(nonatomic) mtCore *core;
@end
