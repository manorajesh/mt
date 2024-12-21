use cocoa::{ appkit::NSView, base::id as cocoa_id };
use core_graphics_types::geometry::CGSize;
use metal::*;
use objc::{ rc::autoreleasepool, runtime::YES };
use std::mem;
use winit::{
    event::{ Event, WindowEvent },
    event_loop::{ ControlFlow, EventLoop },
    raw_window_handle::{ HasWindowHandle, RawWindowHandle },
    window::WindowBuilder,
};

#[repr(C)]
struct Vertex {
    position: [f32; 2],
    color: [f32; 4],
}

struct TerminalView {
    device: Device,
    command_queue: CommandQueue,
    // fontAtlas: Font,
    vertex_buffer: Option<Buffer>,
    pipeline_state: RenderPipelineState,
    sampler_state: SamplerState,
}

impl TerminalView {
    fn new(device: Device) -> Self {
        let command_queue = device.new_command_queue();

        let pipeline_state = Self::create_pipeline_state(&device);
        let sampler_state = Self::create_sampler_state(&device);

        return Self {
            device,
            command_queue,
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

        // Color attribute
        vertex_descriptor.attributes().object_at(1).unwrap().set_format(MTLVertexFormat::Float4);
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

        // Set up blending (optional for solid colors)
        let pipeline_state = device
            .new_render_pipeline_state(&pipeline_state_descriptor)
            .expect("Failed to create pipeline state");

        return pipeline_state;
    }

    fn create_sampler_state(device: &Device) -> SamplerState {
        let descriptor = SamplerDescriptor::new();
        descriptor.set_min_filter(MTLSamplerMinMagFilter::Linear);
        descriptor.set_mag_filter(MTLSamplerMinMagFilter::Linear);
        descriptor.set_address_mode_s(MTLSamplerAddressMode::ClampToEdge);
        descriptor.set_address_mode_t(MTLSamplerAddressMode::ClampToEdge);
        return device.new_sampler(&descriptor);
    }

    fn set_vertex_buffer(
        &mut self,
        bytes: *const std::ffi::c_void,
        length: NSUInteger,
        options: MTLResourceOptions
    ) {
        self.vertex_buffer = Some(self.device.new_buffer_with_data(bytes, length, options));
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

        let vertex_count =
            (self.vertex_buffer.as_ref().unwrap().length() as u64) /
            (mem::size_of::<Vertex>() as u64);

        // Set the vertex buffer
        render_encoder.set_vertex_buffer(0, Some(self.vertex_buffer.as_ref().unwrap()), 0);

        // println!(
        //     "{}",
        //     std::mem::size_of::<Vertex>() / std::mem::size_of::<f32>()
        // );

        // Draw the triangle
        render_encoder.draw_primitives(MTLPrimitiveType::Triangle, 0, vertex_count);

        // End encoding
        render_encoder.end_encoding();

        // Present the drawable
        command_buffer.present_drawable(&drawable);

        // Commit the command buffer
        command_buffer.commit();
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

    let vertex_data = [
        Vertex {
            position: [0.0, 1.0], // Top vertex
            color: [1.0, 0.0, 0.0, 1.0], // Red
        },
        Vertex {
            position: [-1.0, -1.0], // Bottom-left vertex
            color: [0.0, 1.0, 0.0, 1.0], // Red
        },
        Vertex {
            position: [1.0, -1.0], // Bottom-right vertex
            color: [0.0, 1.0, 1.0, 1.0], // Red
        },
    ];

    // Create a vertex buffer
    terminal_view.set_vertex_buffer(
        vertex_data.as_ptr() as *const _,
        (vertex_data.len() * mem::size_of::<Vertex>()) as u64,
        MTLResourceOptions::CPUCacheModeDefaultCache | MTLResourceOptions::StorageModeShared
    );

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
