//
//  TerminalView.h
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import <MetalKit/MetalKit.h>

#ifdef __cplusplus
class Pty;
class RenderBackend;
#endif

@interface TerminalView : MTKView <MTKViewDelegate>

/// PTY used only for sending input (keyDown).
/// Output is handled entirely by the terminal core / parser thread.
@property (nonatomic, assign) Pty *pty;

#ifdef __cplusplus
/// Attach the render backend owned by the terminal core.
/// Must be called once after backend is configured (rows/cols known).
- (void)attachRenderBackend:(RenderBackend *)backend;
#endif

@end
