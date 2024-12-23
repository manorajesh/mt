mod font_atlas;
mod buffer;
mod ansi_parser;
mod pty;

use cocoa::{ appkit::NSView, base::id as cocoa_id };
use core_graphics_types::geometry::CGSize;
use metal::*;
use objc::{ rc::autoreleasepool, runtime::YES };
use std::{ mem, sync::{ Arc, Mutex }, time::Instant };
use winit::{
    event::{ Event, KeyEvent, WindowEvent },
    event_loop::{ ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy },
    keyboard::{ Key, NamedKey },
    raw_window_handle::{ HasWindowHandle, RawWindowHandle },
    window::{ Window, WindowBuilder },
};

use font_atlas::FontAtlas;

#[repr(C)]
#[derive(Clone)]
pub struct Vertex {
    position: [f32; 2], // Position in normalized device coordinates (NDC)
    tex_coords: [f32; 2], // Texture coordinates (u, v)
}

pub struct TerminalView {
    device: Device,
    command_queue: CommandQueue,
    font_atlas: FontAtlas,
    vertex_buffer: Buffer,
    pipeline_state: RenderPipelineState,
    sampler_state: SamplerState,
    window_width: f32,
    window_height: f32,
    buffer: Arc<Mutex<buffer::Buffer>>,
    pty: pty::Pty,
    max_vertex_count: usize,
}

impl TerminalView {
    fn new(proxy: EventLoopProxy<CustomEvent>, device: Device, width: f32, height: f32) -> Self {
        let command_queue = device.new_command_queue();

        let pipeline_state = Self::create_pipeline_state(&device);
        let sampler_state = Self::create_sampler_state(&device);
        let font_atlas = Self::create_font_atlas(&device);
        let buffer = Arc::new(Mutex::new(buffer::Buffer::new(100, 80)));
        let parser = ansi_parser::AnsiParser::new(buffer.clone());
        let pty = pty::Pty::new(proxy, parser, 100, 80);

        let initial_vertex_count = 100 * 80 * 6;
        let vertex_buffer = Self::create_empty_buffer(&device, initial_vertex_count);

        return Self {
            device,
            command_queue,
            font_atlas,
            vertex_buffer: vertex_buffer,
            pipeline_state: pipeline_state,
            sampler_state: sampler_state,
            window_width: width,
            window_height: height,
            buffer: buffer,
            pty: pty,
            max_vertex_count: initial_vertex_count,
        };
    }

    fn create_pipeline_state(device: &Device) -> RenderPipelineState {
        // Load the compiled shader library
        let library_path = std::path::PathBuf
            ::from(env!("CARGO_MANIFEST_DIR"))
            .join("src/shader.metallib");
        let library = device
            .new_library_with_file(library_path)
            .expect("Failed to load shader library");

        // Create the pipeline state
        let vertex_function = library
            .get_function("vertex_main", None)
            .expect("Failed to find vertex_main");
        let fragment_function = library
            .get_function("fragment_main", None)
            .expect("Failed to find fragment_main");

        let pipeline_state_descriptor = RenderPipelineDescriptor::new();
        pipeline_state_descriptor.set_vertex_function(Some(&vertex_function));
        pipeline_state_descriptor.set_fragment_function(Some(&fragment_function));
        pipeline_state_descriptor
            .color_attachments()
            .object_at(0)
            .unwrap()
            .set_pixel_format(MTLPixelFormat::BGRA8Unorm);

        // Enable blending on the color attachment
        let color_attachment = pipeline_state_descriptor.color_attachments().object_at(0).unwrap();
        color_attachment.set_blending_enabled(true);

        // Configure the blend operations and factors
        color_attachment.set_rgb_blend_operation(MTLBlendOperation::Add);
        color_attachment.set_alpha_blend_operation(MTLBlendOperation::Add);
        color_attachment.set_source_rgb_blend_factor(MTLBlendFactor::SourceAlpha);
        color_attachment.set_destination_rgb_blend_factor(MTLBlendFactor::OneMinusSourceAlpha);
        color_attachment.set_source_alpha_blend_factor(MTLBlendFactor::SourceAlpha);
        color_attachment.set_destination_alpha_blend_factor(MTLBlendFactor::OneMinusSourceAlpha);

        // Define the vertex descriptor
        let vertex_descriptor = VertexDescriptor::new();

        // Position attribute
        vertex_descriptor.attributes().object_at(0).unwrap().set_format(MTLVertexFormat::Float2);
        vertex_descriptor.attributes().object_at(0).unwrap().set_offset(0);
        vertex_descriptor.attributes().object_at(0).unwrap().set_buffer_index(0);

        // Texture Coordinates attribute
        vertex_descriptor.attributes().object_at(1).unwrap().set_format(MTLVertexFormat::Float2);
        vertex_descriptor
            .attributes()
            .object_at(1)
            .unwrap()
            .set_offset(mem::size_of::<[f32; 2]>() as u64);
        vertex_descriptor.attributes().object_at(1).unwrap().set_buffer_index(0);

        // Layout for buffer 0
        vertex_descriptor
            .layouts()
            .object_at(0)
            .unwrap()
            .set_stride(mem::size_of::<Vertex>() as u64);
        vertex_descriptor
            .layouts()
            .object_at(0)
            .unwrap()
            .set_step_function(MTLVertexStepFunction::PerVertex);
        vertex_descriptor.layouts().object_at(0).unwrap().set_step_rate(1);

        pipeline_state_descriptor.set_vertex_descriptor(Some(&vertex_descriptor));

        // Set up blending (optional for transparent textures)
        let pipeline_state = device
            .new_render_pipeline_state(&pipeline_state_descriptor)
            .expect("Failed to create pipeline state");

        pipeline_state
    }

    fn create_sampler_state(device: &Device) -> SamplerState {
        let descriptor = SamplerDescriptor::new();
        descriptor.set_min_filter(MTLSamplerMinMagFilter::Linear);
        descriptor.set_mag_filter(MTLSamplerMinMagFilter::Linear);
        descriptor.set_address_mode_s(MTLSamplerAddressMode::ClampToEdge);
        descriptor.set_address_mode_t(MTLSamplerAddressMode::ClampToEdge);
        return device.new_sampler(&descriptor);
    }

    fn create_empty_buffer(device: &Device, vertex_count: usize) -> Buffer {
        let buffer_size = (vertex_count * mem::size_of::<Vertex>()) as NSUInteger;
        return device.new_buffer(buffer_size, MTLResourceOptions::StorageModeShared);
    }

    fn create_font_atlas(device: &Device) -> FontAtlas {
        let font_size = 25.0;

        let data = include_bytes!("../fonts/monaco.ttf");

        let font_atlas = FontAtlas::new(device, data, font_size).expect(
            "Failed to create font atlas"
        );
        return font_atlas;
    }

    pub fn generate_quad(
        &self,
        c: char,
        screen_position: [f32; 2],
        scale: [f32; 2]
    ) -> Option<([Vertex; 6], f32)> {
        // Retrieve glyph information
        let glyph_info = match self.font_atlas.glyph(c) {
            Some(g) => g,
            None => {
                // Return an empty quad or a default quad if glyph not found
                return None;
            }
        };

        // Compute quad size based on glyph size and scale
        let width = glyph_info.size.0 * scale[0];
        let height = glyph_info.size.1 * scale[1];

        // Position in pixels
        let line_height = self.font_atlas.line_height;
        let x = screen_position[0] + glyph_info.offset.0 * scale[0];
        let y =
            screen_position[1] +
            line_height -
            (glyph_info.offset.1 * scale[1] + glyph_info.size.1 * scale[1]);

        // Convert pixel positions to NDC
        let ndc_x = (x / self.window_width) * 2.0 - 1.0;
        let ndc_y = 1.0 - (y / self.window_height) * 2.0;
        let ndc_width = (width / self.window_width) * 2.0;
        let ndc_height = (height / self.window_height) * 2.0;

        // Define quad corners in NDC
        let top_left = [ndc_x, ndc_y];
        let bottom_left = [ndc_x, ndc_y - ndc_height];
        let bottom_right = [ndc_x + ndc_width, ndc_y - ndc_height];
        let top_right = [ndc_x + ndc_width, ndc_y];

        // Texture coordinates from the font atlas
        let tex_min = [glyph_info.tex_coords[0], glyph_info.tex_coords[1]];
        let tex_max = [glyph_info.tex_coords[2], glyph_info.tex_coords[3]];

        // Create six vertices for two triangles
        Some((
            [
                // First triangle
                Vertex { position: top_left, tex_coords: [tex_min[0], tex_min[1]] },
                Vertex { position: bottom_left, tex_coords: [tex_min[0], tex_max[1]] },
                Vertex { position: bottom_right, tex_coords: [tex_max[0], tex_max[1]] },

                // Second triangle
                Vertex { position: top_left, tex_coords: [tex_min[0], tex_min[1]] },
                Vertex { position: bottom_right, tex_coords: [tex_max[0], tex_max[1]] },
                Vertex { position: top_right, tex_coords: [tex_max[0], tex_min[1]] },
            ],
            glyph_info.advance,
        ))
    }

    fn update_vertices_for_buffer(&mut self) {
        let buffer: std::sync::MutexGuard<'_, buffer::Buffer> = self.buffer.lock().unwrap();
        let rows = buffer.rows;
        let cols = buffer.cols;
        let total_vertices = rows * cols * 6;

        // Check if current buffer is sufficient
        if total_vertices > self.max_vertex_count {
            // Recreate the buffer with increased size
            self.vertex_buffer = Self::create_empty_buffer(&self.device, total_vertices);
            self.max_vertex_count = total_vertices;
            tracing::info!("Resized vertex buffer to {} vertices", total_vertices);
        }

        let mut vertex_data = Vec::with_capacity(total_vertices);
        let mut x = 0.0;
        let mut y = 0.0;
        for row in 0..buffer.rows {
            for col in 0..buffer.cols {
                let cell = buffer.get_cell(row, col);
                let c = cell.ascii_code as char;
                if let Some((quad, width)) = self.generate_quad(c, [x, y], [1.0, 1.0]) {
                    vertex_data.extend_from_slice(&quad);
                    x += width;
                } else {
                    x += self.font_atlas.char_width;
                }
            }
            x = 0.0;
            y += self.font_atlas.line_height;
        }
        // for idx_start in &buffer.rows {
        //     let row = buffer.get_row(*idx_start);
        //     for cell in row {
        //         let c = buffer.get_char(*cell);
        //         if let Some((quad, width)) = self.generate_quad(c, [x, y], [1.0, 1.0]) {
        //             vertex_data.extend_from_slice(&quad);
        //             x += width;
        //         } else {
        //             x += self.font_atlas.char_width;
        //         }
        //     }
        //     x = 0.0;
        //     y += self.font_atlas.line_height;
        // }
        drop(buffer);
        unsafe {
            let buffer_ptr = self.vertex_buffer.contents() as *mut Vertex;
            buffer_ptr.copy_from_nonoverlapping(vertex_data.as_ptr(), vertex_data.len());
        }
    }

    fn draw(&mut self, drawable: &MetalDrawableRef) {
        self.update_vertices_for_buffer();

        // Create a render pass descriptor
        let render_pass_descriptor = RenderPassDescriptor::new();
        let color_attachment = render_pass_descriptor.color_attachments().object_at(0).unwrap();
        color_attachment.set_texture(Some(drawable.texture()));
        color_attachment.set_load_action(MTLLoadAction::Clear);
        color_attachment.set_clear_color(MTLClearColor::new(0.0, 0.0, 0.0, 1.0)); // Dark background
        color_attachment.set_store_action(MTLStoreAction::Store);

        // Create a command buffer
        let command_buffer = self.command_queue.new_command_buffer();

        // Create a render command encoder
        let render_encoder = command_buffer.new_render_command_encoder(&render_pass_descriptor);

        // Set the pipeline state
        render_encoder.set_render_pipeline_state(&self.pipeline_state);

        // Set the vertex buffer (offset is 0)
        render_encoder.set_vertex_buffer(0, Some(&self.vertex_buffer), 0);

        // Set the texture and sampler
        render_encoder.set_fragment_texture(0, Some(&self.font_atlas.texture));
        render_encoder.set_fragment_sampler_state(0, Some(&self.sampler_state));

        // Calculate the number of vertices to draw
        // let buffer = self.buffer.lock().unwrap();
        // let vertex_count = (self.max_vertex_count as u64).min(
        //     (buffer.rows * buffer.cols * 6) as u64
        // );

        // Draw the triangles
        render_encoder.draw_primitives(MTLPrimitiveType::Triangle, 0, self.max_vertex_count as u64);

        // End encoding
        render_encoder.end_encoding();

        // Present the drawable
        command_buffer.present_drawable(drawable);

        // Commit the command buffer
        command_buffer.commit();
    }
}

#[derive(Debug, Clone)]
pub enum CustomEvent {
    RequestRedraw,
}

fn main() {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Create the event loop with proxy
    let event_loop = EventLoopBuilder::<CustomEvent>::with_user_event().build().unwrap();
    let proxy = event_loop.create_proxy();

    // Build the window
    let window = WindowBuilder::new()
        .with_title("mt")
        .with_inner_size(winit::dpi::LogicalSize::new(800.0, 600.0))
        .build(&event_loop)
        .unwrap();

    // Initialize Metal
    let device = Device::system_default().expect("No Metal device found");

    // Create a Metal layer
    let layer = MetalLayer::new();
    layer.set_device(&device);
    layer.set_pixel_format(MTLPixelFormat::BGRA8Unorm);
    layer.set_framebuffer_only(true);
    layer.set_maximum_drawable_count(3);

    // Associate the Metal layer with the window's NSView
    unsafe {
        if let Ok(RawWindowHandle::AppKit(rw)) = window.window_handle().map(|wh| wh.as_raw()) {
            let view = rw.ns_view.as_ptr() as cocoa_id;
            view.setWantsLayer(YES);
            view.setLayer(mem::transmute(layer.as_ref()));
        }
    }

    // Set the drawable size
    let size = window.inner_size();
    layer.set_drawable_size(CGSize::new(size.width as f64, size.height as f64));

    let mut terminal_view = TerminalView::new(proxy, device, size.width as f32, size.height as f32);

    // Run the event loop
    event_loop
        .run(move |event, event_loop| {
            event_loop.set_control_flow(ControlFlow::Poll);

            match event {
                // Event::AboutToWait => window.request_redraw(),
                Event::WindowEvent { event, .. } =>
                    match event {
                        WindowEvent::CloseRequested => event_loop.exit(),
                        WindowEvent::RedrawRequested => {
                            autoreleasepool(|| {
                                // Get the next drawable
                                let drawable = match layer.next_drawable() {
                                    Some(drawable) => drawable,
                                    None => {
                                        return;
                                    }
                                };

                                terminal_view.draw(drawable);
                            });
                        }
                        WindowEvent::Resized(size) => {
                            layer.set_drawable_size(
                                CGSize::new(size.width as f64, size.height as f64)
                            );
                            let rows = ((size.height as f32) /
                                terminal_view.font_atlas.line_height) as usize;
                            let cols = ((size.width as f32) /
                                terminal_view.font_atlas.char_width) as usize;

                            tracing::info!("Resized to {}x{}", rows, cols);
                            let vertex_count = rows * cols * 6;
                            terminal_view.max_vertex_count = vertex_count;
                            terminal_view.vertex_buffer = TerminalView::create_empty_buffer(
                                &terminal_view.device,
                                vertex_count
                            );

                            terminal_view.buffer.lock().unwrap().resize(rows, cols);
                            terminal_view.pty.resize(rows, cols);
                            terminal_view.window_width = size.width as f32;
                            terminal_view.window_height = size.height as f32;
                            let drawable = match layer.next_drawable() {
                                Some(drawable) => drawable,
                                None => {
                                    return;
                                }
                            };

                            terminal_view.draw(drawable);
                        }
                        WindowEvent::KeyboardInput { event, .. } => {
                            match event {
                                KeyEvent { logical_key: Key::Character(c), state, .. } => if
                                    state == winit::event::ElementState::Pressed
                                {
                                    terminal_view.pty.write(c.as_bytes());
                                }
                                // enter key
                                KeyEvent { logical_key: Key::Named(c), state, .. } => if
                                    state == winit::event::ElementState::Pressed
                                {
                                    match c {
                                        NamedKey::Enter => terminal_view.pty.write(b"\n"),
                                        NamedKey::Tab => terminal_view.pty.write(b"\t"),
                                        NamedKey::Space => terminal_view.pty.write(b" "),
                                        NamedKey::Backspace => terminal_view.pty.write(b"\x7f"),
                                        _ => (),
                                    }
                                }
                                _ => (),
                            }
                        }
                        _ => (),
                    }
                Event::UserEvent(CustomEvent::RequestRedraw) => {
                    window.request_redraw();
                }
                _ => (),
            }
        })
        .unwrap();
}
