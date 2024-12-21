mod font_atlas;

use cocoa::{ appkit::NSView, base::id as cocoa_id };
use core_graphics_types::geometry::CGSize;
use fontdue::Font;
use metal::*;
use objc::{ rc::autoreleasepool, runtime::YES };
use std::mem;
use winit::{
    event::{ Event, WindowEvent },
    event_loop::{ ControlFlow, EventLoop },
    raw_window_handle::{ HasWindowHandle, RawWindowHandle },
    window::WindowBuilder,
};

use font_atlas::FontAtlas;

#[repr(C)]
#[derive(Clone)]
struct Vertex {
    position: [f32; 2], // Position in normalized device coordinates (NDC)
    tex_coords: [f32; 2], // Texture coordinates (u, v)
}

struct TerminalView {
    device: Device,
    command_queue: CommandQueue,
    font_atlas: FontAtlas,
    vertex_buffer: Option<Buffer>,
    pipeline_state: RenderPipelineState,
    sampler_state: SamplerState,
}

impl TerminalView {
    fn new(device: Device) -> Self {
        let command_queue = device.new_command_queue();

        let pipeline_state = Self::create_pipeline_state(&device);
        let sampler_state = Self::create_sampler_state(&device);
        let font_atlas = Self::create_font_atlas(&device);

        return Self {
            device,
            command_queue,
            font_atlas,
            vertex_buffer: None,
            pipeline_state: pipeline_state,
            sampler_state: sampler_state,
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

    fn create_font_atlas(device: &Device) -> FontAtlas {
        let font_size = 500.0;

        let font_path = std::path::PathBuf
            ::from(env!("CARGO_MANIFEST_DIR"))
            .join("fonts/monaco.ttf");

        let font_atlas = FontAtlas::new(device, font_path.as_path(), font_size);
        return font_atlas.unwrap();
    }

    fn set_vertex_buffer(
        &mut self,
        bytes: *const std::ffi::c_void,
        length: NSUInteger,
        options: MTLResourceOptions
    ) {
        self.vertex_buffer = Some(self.device.new_buffer_with_data(bytes, length, options));
    }

    pub fn generate_quad(
        &self,
        c: char,
        screen_position: [f32; 2],
        scale: [f32; 2]
    ) -> [Vertex; 6] {
        // Retrieve glyph info
        let glyph_info = match self.font_atlas.glyph_info(c) {
            Some(info) => info,
            None => {
                // Return an empty quad or a default quad if character not found
                return [
                    Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0] },
                    Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0] },
                    Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0] },
                    Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0] },
                    Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0] },
                    Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0] },
                ];
            }
        };

        // Calculate texture coordinates
        let u0 = (glyph_info.x as f32) / (self.font_atlas.atlas_width as f32);
        let v0 = (glyph_info.y as f32) / (self.font_atlas.atlas_height as f32);
        let u1 = ((glyph_info.x + glyph_info.width) as f32) / (self.font_atlas.atlas_width as f32);
        let v1 =
            ((glyph_info.y + glyph_info.height) as f32) / (self.font_atlas.atlas_height as f32);

        // Convert screen position and scale to NDC (-1 to 1)
        // Assuming screen dimensions are known; for simplicity, let's assume 800x600
        let screen_width = 800.0;
        let screen_height = 600.0;

        let x = screen_position[0];
        let y = screen_position[1];
        let w = scale[0];
        let h = scale[1];

        // Convert pixel positions to NDC
        let ndc_x0 = (x / screen_width) * 2.0 - 1.0;
        let ndc_y0 = 1.0 - (y / screen_height) * 2.0;
        let ndc_x1 = ((x + w) / screen_width) * 2.0 - 1.0;
        let ndc_y1 = 1.0 - ((y + h) / screen_height) * 2.0;

        // Define the quad vertices (two triangles)
        [
            // First Triangle
            Vertex { position: [ndc_x0, ndc_y1], tex_coords: [u0, v1] }, // Top-left
            Vertex { position: [ndc_x0, ndc_y0], tex_coords: [u0, v0] }, // Bottom-left
            Vertex { position: [ndc_x1, ndc_y0], tex_coords: [u1, v0] }, // Bottom-right

            // Second Triangle
            Vertex { position: [ndc_x0, ndc_y1], tex_coords: [u0, v1] }, // Top-left
            Vertex { position: [ndc_x1, ndc_y0], tex_coords: [u1, v0] }, // Bottom-right
            Vertex { position: [ndc_x1, ndc_y1], tex_coords: [u1, v1] }, // Top-right
        ]
    }

    fn draw(&self, drawable: &MetalDrawableRef) {
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

        // Set the vertex buffer
        if let Some(buffer) = &self.vertex_buffer {
            render_encoder.set_vertex_buffer(0, Some(buffer), 0);
        }

        // Set the texture and sampler
        render_encoder.set_fragment_texture(0, Some(&self.font_atlas.texture));
        render_encoder.set_fragment_sampler_state(0, Some(&self.sampler_state));

        // Draw the triangles
        if let Some(buffer) = &self.vertex_buffer {
            let vertex_count = buffer.length() / (mem::size_of::<Vertex>() as u64);
            render_encoder.draw_primitives(MTLPrimitiveType::Triangle, 0, vertex_count as u64);
        }

        // End encoding
        render_encoder.end_encoding();

        // Present the drawable
        command_buffer.present_drawable(&drawable);

        // Commit the command buffer
        command_buffer.commit();
    }

    pub fn render_text(&mut self, text: &str, position: [f32; 2], scale: [f32; 2]) {
        let mut vertices: Vec<Vertex> = Vec::new();
        let mut cursor = position;

        for c in text.chars() {
            let quad = self.generate_quad(c, cursor, scale);
            vertices.extend_from_slice(&quad);

            // Advance cursor based on glyph's width
            if let Some(glyph_info) = self.font_atlas.glyph_info(c) {
                cursor[0] +=
                    ((glyph_info.width as f32) * scale[0]) / (self.font_atlas.atlas_width as f32);
            }
        }

        // Create a vertex buffer
        let buffer_length = vertices.len() * mem::size_of::<Vertex>();
        let vertex_buffer = self.device.new_buffer_with_bytes_no_copy(
            vertices.as_ptr() as *const _,
            buffer_length as u64,
            MTLResourceOptions::CPUCacheModeDefaultCache | MTLResourceOptions::StorageModeShared,
            None
        );

        self.vertex_buffer = Some(vertex_buffer);
    }
}

fn main() {
    // Initialize logging
    env_logger::init();

    // Create the event loop
    let event_loop = EventLoop::new().unwrap();

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

    let mut terminal_view = TerminalView::new(device);

    terminal_view.render_text("Hello, Metal!", [100.0, 100.0], [1.0, 1.0]);

    // Run the event loop
    event_loop
        .run(move |event, event_loop| {
            event_loop.set_control_flow(ControlFlow::Poll);

            match event {
                Event::AboutToWait => window.request_redraw(),
                Event::WindowEvent { event, .. } =>
                    match event {
                        WindowEvent::CloseRequested => event_loop.exit(),
                        WindowEvent::Resized(size) => {
                            layer.set_drawable_size(
                                CGSize::new(size.width as f64, size.height as f64)
                            );
                        }
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
                        _ => (),
                    }
                _ => (),
            }
        })
        .unwrap();
}
