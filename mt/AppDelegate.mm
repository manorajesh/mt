//
//  AppDelegate.mm
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#import "AppDelegate.h"
#import "TerminalView.h"

#import "../mtCore/pty.h"
#import "../mtCore/parser.hpp"
#import "../mtCore/render_backend.hpp"
#import "../mtCore/terminal_model.hpp"

#include <thread>
#include <atomic>

@interface AppDelegate () {
    NSWindow *_window;
    TerminalView *_terminalView;
    
#ifdef __cplusplus
    Pty *_pty;
    
    // Terminal core objects (C++)
    std::unique_ptr<RenderBackend> _renderBackend;
    std::unique_ptr<TerminalParser> _parser;
    
    std::thread _terminalThread;
    std::atomic<bool> _running;
#endif
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self setupWindow];
    [self setupTerminal];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note {
#ifdef __cplusplus
    _running.store(false, std::memory_order_release);
    if (_terminalThread.joinable()) {
        _terminalThread.join();
    }
    if (_pty) {
        _pty->onOutput = nullptr;
    }
    delete _pty;
    _pty = nullptr;
#endif
}

#pragma mark - Window / View

- (void)setupWindow {
    NSRect frame = NSMakeRect(100, 100, 900, 600);
    
    _window = [[NSWindow alloc]
               initWithContentRect:frame
               styleMask:(NSWindowStyleMaskTitled |
                          NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable)
               backing:NSBackingStoreBuffered
               defer:NO];
    
    _window.title = @"mt";
    _window.backgroundColor = NSColor.blackColor;
    
    _terminalView =
    [[TerminalView alloc] initWithFrame:_window.contentView.bounds];
    _terminalView.autoresizingMask =
    NSViewWidthSizable | NSViewHeightSizable;
    
    [_window.contentView addSubview:_terminalView];
    [_window makeKeyAndOrderFront:nil];
}

#pragma mark - Terminal Core

- (void)setupTerminal {
#ifdef __cplusplus
    // --- Grid size (initial guess; resize later on drawableSize change) ---
    const uint16_t cols = 120;
    const uint16_t rows = 40;
    
    // --- Render backend ---
    _renderBackend = std::make_unique<RenderBackend>();
    _renderBackend->configure({cols, rows});
    
    // Attach backend to view (main thread)
    [_terminalView attachRenderBackend:_renderBackend.get()];
    
    // --- PTY ---
    _pty = new Pty();
    _terminalView.pty = _pty;
    
    if (!_pty->start(rows, cols)) {
        NSLog(@"Failed to start PTY");
        return;
    }
    
    // --- Terminal model + parser ---
    // You must implement a TerminalOps-backed model that:
    // - updates grid
    // - tracks dirty rows
    // - writes into RenderBackend back buffer
    //
    // Assume you have:
    //   class TerminalModel : public TerminalOps
    //
    auto *model = new TerminalModel(cols, rows, *_renderBackend);
    _parser = std::make_unique<TerminalParser>(*model);
    
    // --- Terminal thread ---
    _running.store(true, std::memory_order_release);
    
    TerminalParser *parser = _parser.get();
    RenderBackend *backend = _renderBackend.get();
    __weak TerminalView *weakView = _terminalView;

    _pty->onOutput = [parser, backend, weakView](const char *bytes, size_t len) {
        // This runs on the PTY serial queue thread.
        // Feed parser directly; no locks.
        if (parser) {
            parser->consume(reinterpret_cast<const uint8_t *>(bytes), len);
        }

        // Publish render frame
        if (backend) {
            backend->publish();
        }

        // Wake main thread to draw
        dispatch_async(dispatch_get_main_queue(), ^{
            TerminalView *strongView = weakView;
            if (strongView) {
                [strongView setNeedsDisplay:YES];
            }
        });
    };
    
#endif
}

@end

