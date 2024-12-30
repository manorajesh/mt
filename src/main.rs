#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

mod ansi_parser;
mod buffer;
mod pty;
mod rendering;

use cocoa::{ appkit::NSView, base::id as cocoa_id };
use core_graphics_types::geometry::CGSize;
use metal::*;
use objc::{ rc::autoreleasepool, runtime::YES };
use std::mem;
use winit::{
    application::ApplicationHandler,
    event::{ KeyEvent, WindowEvent },
    event_loop::EventLoop,
    keyboard::{ Key, NamedKey },
    raw_window_handle::{ HasWindowHandle, RawWindowHandle },
    window::WindowAttributes,
};

use rendering::terminal_view::TerminalView;

impl ApplicationHandler for TerminalView {
    fn window_event(
        &mut self,
        event_loop: &winit::event_loop::ActiveEventLoop,
        _window_id: winit::window::WindowId,
        event: WindowEvent
    ) {
        // Event::AboutToWait => window.request_redraw(),
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::RedrawRequested => {
                autoreleasepool(|| {
                    self.draw();
                });
            }
            WindowEvent::Resized(size) => {
                self.layer
                    .as_ref()
                    .unwrap()
                    .set_drawable_size(CGSize::new(size.width as f64, size.height as f64));
                let rows = ((size.height as f32) / self.font_atlas.line_height) as usize;
                let cols = ((size.width as f32) / self.font_atlas.char_width) as usize;

                tracing::info!("Resized to {}x{}", rows, cols);
                let vertex_count = rows * cols * 6;
                self.max_vertex_count = vertex_count;
                self.vertex_buffer = TerminalView::create_empty_buffer(&self.device, vertex_count);

                self.window.as_mut().unwrap().set_title(&format!("mt - {}x{}", rows, cols));

                self.buffer.lock().unwrap().resize(rows, cols);
                self.pty.resize(rows, cols);
                self.window_width = Some(size.width as f32);
                self.window_height = Some(size.height as f32);

                autoreleasepool(|| {
                    self.draw();
                });
            }
            WindowEvent::KeyboardInput { event, .. } => {
                match event {
                    KeyEvent { logical_key: Key::Character(c), state, .. } => {
                        if state == winit::event::ElementState::Pressed {
                            self.pty.write(c.as_bytes());
                        }
                    }
                    // enter key
                    KeyEvent { logical_key: Key::Named(c), state, .. } => {
                        if state == winit::event::ElementState::Pressed {
                            match c {
                                NamedKey::Enter => self.pty.write(b"\n"),
                                NamedKey::Tab => self.pty.write(b"\t"),
                                NamedKey::Space => self.pty.write(b" "),
                                NamedKey::Backspace => self.pty.write(b"\x7f"),
                                _ => (),
                            }
                        }
                    }
                    _ => (),
                }
            }
            _ => (),
        }
    }

    fn resumed(&mut self, event_loop: &winit::event_loop::ActiveEventLoop) {
        tracing::info!("Resumed");
        // Create a Metal layer
        let layer = MetalLayer::new();
        layer.set_device(&self.device);
        layer.set_pixel_format(MTLPixelFormat::BGRA8Unorm);
        layer.set_framebuffer_only(true);
        layer.set_maximum_drawable_count(3);

        let window_attributes = WindowAttributes::default().with_title("mt");
        let window = event_loop.create_window(window_attributes).unwrap();

        // Associate the Metal layer with the window's NSView
        unsafe {
            if let Ok(RawWindowHandle::AppKit(rw)) = window.window_handle().map(|wh| wh.as_raw()) {
                let view = rw.ns_view.as_ptr() as cocoa_id;
                view.setWantsLayer(YES);
                view.setLayer(mem::transmute(layer.as_ref()));
            }
        }

        self.window_width = Some(window.inner_size().width as f32);
        self.window_height = Some(window.inner_size().height as f32);
        self.layer = Some(layer);
        self.window = Some(window);
    }

    fn memory_warning(&mut self, _event_loop: &winit::event_loop::ActiveEventLoop) {
        tracing::warn!("Memory warning");
    }

    fn user_event(&mut self, _event_loop: &winit::event_loop::ActiveEventLoop, _event: ()) {
        self.window.as_ref().unwrap().request_redraw();
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Create the event loop with proxy
    let event_loop = EventLoop::new()?;
    let proxy = event_loop.create_proxy();

    let mut terminal_view = TerminalView::new(proxy);

    // Run the event loop
    Ok(event_loop.run_app(&mut terminal_view)?)
}
