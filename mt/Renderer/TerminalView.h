//
//  TerminalView.h
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import <MetalKit/MetalKit.h>

class mtCore;

@interface TerminalView : MTKView <MTKViewDelegate>
@property(nonatomic) mtCore *core;
- (void)appendOutput:(const char *)data length:(size_t)len;
@end
