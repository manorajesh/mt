use crate::{ ansi_parser, buffer, rendering::font_atlas::FontAtlas, pty };
use metal::*;
use std::{ mem, sync::{ Arc, Mutex } };
use winit::{ event_loop::EventLoopProxy, window::Window };

#[repr(C)]
#[derive(Clone)]
pub struct Vertex {
    position: [f32; 2], // Position in normalized device coordinates (NDC)
    tex_coords: [f32; 2], // Texture coordinates (u, v)
}

pub struct TerminalView {
    pub device: Device,
    command_queue: CommandQueue,
    pub font_atlas: FontAtlas,
    pub vertex_buffer: Buffer,
    pipeline_state: RenderPipelineState,
    sampler_state: SamplerState,
    pub window_width: Option<f32>,
    pub window_height: Option<f32>,
    pub buffer: Arc<Mutex<buffer::TextBuffer>>,
    pub pty: pty::Pty,
    pub max_vertex_count: usize,
    pub window: Option<Window>,
    pub layer: Option<MetalLayer>,
}

impl TerminalView {
    pub fn new(proxy: EventLoopProxy<()>) -> Self {
        // Initialize Metal
        let device = Device::system_default().expect("No Metal device found");

        let command_queue = device.new_command_queue();

        let pipeline_state = Self::create_pipeline_state(&device);
        let sampler_state = Self::create_sampler_state(&device);
        let font_atlas = Self::create_font_atlas(&device);
        let buffer = Arc::new(Mutex::new(buffer::TextBuffer::new(100, 80)));
        let parser = ansi_parser::AnsiSimdParser::new(buffer.clone());
        let pty = pty::Pty::new(proxy, parser, 100, 80);

        let initial_vertex_count = 100 * 80 * 6;
        let vertex_buffer = Self::create_empty_buffer(&device, initial_vertex_count);

        Self {
            device,
            command_queue,
            font_atlas,
            vertex_buffer,
            pipeline_state,
            sampler_state,
            window_width: None,
            window_height: None,
            buffer,
            pty,
            max_vertex_count: initial_vertex_count,
            window: None,
            layer: None,
        }
    }

    fn create_pipeline_state(device: &Device) -> RenderPipelineState {
        // Load the compiled shader library
        let library_path = std::path::PathBuf
            ::from(env!("CARGO_MANIFEST_DIR"))
            .join("src/rendering/shader.metallib");
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

        pipeline_state_descriptor.set_vertex_descriptor(Some(vertex_descriptor));

        // Set up blending (optional for transparent textures)

        device
            .new_render_pipeline_state(&pipeline_state_descriptor)
            .expect("Failed to create pipeline state")
    }

    fn create_sampler_state(device: &Device) -> SamplerState {
        let descriptor = SamplerDescriptor::new();
        descriptor.set_min_filter(MTLSamplerMinMagFilter::Linear);
        descriptor.set_mag_filter(MTLSamplerMinMagFilter::Linear);
        descriptor.set_address_mode_s(MTLSamplerAddressMode::ClampToEdge);
        descriptor.set_address_mode_t(MTLSamplerAddressMode::ClampToEdge);
        device.new_sampler(&descriptor)
    }

    pub fn create_empty_buffer(device: &Device, vertex_count: usize) -> Buffer {
        let buffer_size = (vertex_count * mem::size_of::<Vertex>()) as NSUInteger;
        device.new_buffer(buffer_size, MTLResourceOptions::StorageModeShared)
    }

    fn create_font_atlas(device: &Device) -> FontAtlas {
        let font_size = 25.0;

        let data = include_bytes!("../../fonts/monaco.ttf");

        FontAtlas::new(device, data, font_size).expect("Failed to create font atlas")
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
        let ndc_x = (x / self.window_width.unwrap()) * 2.0 - 1.0;
        let ndc_y = 1.0 - (y / self.window_height.unwrap()) * 2.0;
        let ndc_width = (width / self.window_width.unwrap()) * 2.0;
        let ndc_height = (height / self.window_height.unwrap()) * 2.0;

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
                Vertex {
                    position: top_left,
                    tex_coords: [tex_min[0], tex_min[1]],
                },
                Vertex {
                    position: bottom_left,
                    tex_coords: [tex_min[0], tex_max[1]],
                },
                Vertex {
                    position: bottom_right,
                    tex_coords: [tex_max[0], tex_max[1]],
                },
                // Second triangle
                Vertex {
                    position: top_left,
                    tex_coords: [tex_min[0], tex_min[1]],
                },
                Vertex {
                    position: bottom_right,
                    tex_coords: [tex_max[0], tex_max[1]],
                },
                Vertex {
                    position: top_right,
                    tex_coords: [tex_max[0], tex_min[1]],
                },
            ],
            glyph_info.advance,
        ))
    }

    fn update_vertices_for_buffer(&mut self) {
        let buffer: std::sync::MutexGuard<'_, buffer::TextBuffer> = self.buffer.lock().unwrap();
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
                let c = cell as char;
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

    pub fn draw(&mut self) {
        self.update_vertices_for_buffer();

        let drawable = match self.layer.as_ref().unwrap().next_drawable() {
            Some(drawable) => drawable,
            None => {
                return;
            }
        };

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
        let render_encoder = command_buffer.new_render_command_encoder(render_pass_descriptor);

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

        self.window.as_ref().unwrap().pre_present_notify();

        // Commit the command buffer
        command_buffer.commit();
    }
}
