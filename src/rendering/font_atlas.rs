use fontdue::Font;
use metal::{
    Device,
    MTLOrigin,
    MTLPixelFormat,
    MTLRegion,
    MTLSize,
    MTLTextureType,
    MTLTextureUsage,
    TextureDescriptor,
};
use std::collections::HashMap;

pub struct GlyphInfo {
    pub char: char,
    pub tex_coords: [f32; 4], // [u_min, v_min, u_max, v_max]
    pub offset: (f32, f32), // (x, y) offset relative to baseline
    pub size: (f32, f32), // (width, height) of the glyph
    pub advance: f32, // Advance width for cursor movement
}

pub struct FontAtlas {
    glyphs: HashMap<char, GlyphInfo>,
    pub texture: metal::Texture,
    pub line_height: f32,
    pub char_width: f32,
}

impl FontAtlas {
    /// Creates a new FontAtlas from the given font data and scale using fontdue.
    pub fn new(device: &Device, font_data: &[u8], font_size: f32) -> Result<Self, String> {
        // Initialize fontdue font
        let font = Font::from_bytes(font_data, fontdue::FontSettings::default()).map_err(|_|
            "Error loading font with fontdue".to_string()
        )?;

        // Define printable ASCII range
        let char_set =
            " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

        // Estimate atlas dimensions (adjust as needed)
        let atlas_width = 4096;
        let atlas_height = 4096;

        let mut bitmap = vec![0u8; atlas_width * atlas_height];
        let mut glyph_infos = HashMap::new();

        let mut x = 0;
        let mut y = 0;
        let line_height = (font_size as usize) + 1;

        for c in char_set.chars() {
            // Rasterize glyph using fontdue
            let (metrics, bitmap_glyph) = font.rasterize(c, font_size);

            let width = metrics.width;
            let height = metrics.height;

            // Move to next line if glyph doesn't fit horizontally
            if x + width > atlas_width {
                x = 0;
                y += line_height;
            }

            // Check if there's enough vertical space
            if y + height > atlas_height {
                return Err("Font atlas size insufficient".to_string());
            }

            // Render glyph into bitmap
            for gy in 0..height {
                for gx in 0..width {
                    let pixel_index = gy * width + gx;
                    let px = x + gx;
                    let py = y + gy;
                    if px < atlas_width && py < atlas_height {
                        // fontdue returns bitmap with values from 0..255
                        bitmap[py * atlas_width + px] = bitmap_glyph[pixel_index];
                    }
                }
            }

            // Store glyph info
            let tex_coords = [
                (x as f32) / (atlas_width as f32),
                (y as f32) / (atlas_height as f32),
                ((x + width) as f32) / (atlas_width as f32),
                ((y + height) as f32) / (atlas_height as f32),
            ];

            let offset = (metrics.bounds.xmin, metrics.bounds.ymin);
            let size = (width as f32, height as f32);
            let advance = metrics.advance_width;

            glyph_infos.insert(c, GlyphInfo {
                char: c,
                tex_coords,
                offset,
                size,
                advance,
            });

            x += width + 1; // 1 pixel padding
        }

        // Create Metal texture descriptor
        let texture_descriptor = TextureDescriptor::new();
        texture_descriptor.set_texture_type(MTLTextureType::D2);
        texture_descriptor.set_pixel_format(MTLPixelFormat::R8Unorm);
        texture_descriptor.set_width(atlas_width as u64);
        texture_descriptor.set_height(atlas_height as u64);
        texture_descriptor.set_usage(MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite);

        let texture = device.new_texture(&texture_descriptor);

        let region = MTLRegion {
            origin: MTLOrigin { x: 0, y: 0, z: 0 },
            size: MTLSize {
                width: atlas_width as u64,
                height: atlas_height as u64,
                depth: 1,
            },
        };

        let bytes_per_row = atlas_width;

        // Upload bitmap to Metal texture
        texture.replace_region(region, 0, bitmap.as_ptr() as *const _, bytes_per_row as u64);

        // Optionally, save the atlas as a PNG for debugging
        // let image: GrayImage = image::ImageBuffer
        //     ::from_raw(atlas_width as u32, atlas_height as u32, bitmap.clone())
        //     .ok_or("Failed to create image buffer")?;
        // image.save("font_atlas.png").map_err(|e| e.to_string())?;

        Ok(FontAtlas {
            glyphs: glyph_infos,
            texture,
            line_height: font.metrics('G', font_size).bounds.height + 10.0,
            char_width: font.metrics('G', font_size).advance_width,
        })
    }

    /// Retrieves glyph information for the given character.
    pub fn glyph(&self, c: char) -> Option<&GlyphInfo> {
        self.glyphs.get(&c)
    }
}
