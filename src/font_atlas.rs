use image::GrayImage;
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
use rusttype::{ Font, Scale, point, PositionedGlyph, Rect };
use std::collections::HashMap;

pub struct GlyphInfo {
    pub char: char,
    pub tex_coords: [f32; 4], // [u_min, v_min, u_max, v_max]
    pub offset: (f32, f32), // (x, y) position for rendering
    pub size: (f32, f32), // (width, height) of the glyph
}

pub struct FontAtlas {
    bitmap: Vec<u8>, // Grayscale bitmap
    width: usize,
    height: usize,
    glyphs: HashMap<char, GlyphInfo>,
    pub texture: metal::Texture,
}

impl FontAtlas {
    /// Creates a new FontAtlas from the given font data and scale.
    pub fn new(device: &Device, font_data: &[u8], scale: Scale) -> Result<Self, String> {
        let font = Font::try_from_bytes(font_data).ok_or("Error loading font")?;

        // Define printable ASCII range
        let char_set =
            " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";

        // Estimate atlas dimensions
        let atlas_width = 4096;
        let atlas_height = 4096;

        let mut bitmap = vec![0u8; atlas_width * atlas_height];
        let mut glyph_infos = HashMap::new();

        let mut x = 0;
        let mut y = 0;
        let line_height = (scale.y as usize) + 1;

        for c in char_set.chars() {
            let glyph = font.glyph(c).scaled(scale);
            let glyph = glyph.positioned(point(0.0, scale.y));

            if let Some(bounding_box) = glyph.pixel_bounding_box() {
                let width = bounding_box.width() as usize;
                let height = bounding_box.height() as usize;

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
                glyph.draw(|gx, gy, v| {
                    let px = x + (gx as usize);
                    let py = y + (gy as usize);
                    if px < atlas_width && py < atlas_height {
                        bitmap[py * atlas_width + px] = (v * 255.0) as u8;
                    }
                });

                // Store glyph info
                let tex_coords = [
                    (x as f32) / (atlas_width as f32),
                    (y as f32) / (atlas_height as f32),
                    ((x + width) as f32) / (atlas_width as f32),
                    ((y + height) as f32) / (atlas_height as f32),
                ];

                let offset = (bounding_box.min.x as f32, bounding_box.min.y as f32);
                let size = (width as f32, height as f32);

                glyph_infos.insert(c, GlyphInfo {
                    char: c,
                    tex_coords,
                    offset,
                    size,
                });

                x += width + 1; // 1 pixel padding
            }
        }

        let texture_descriptor = TextureDescriptor::new();
        texture_descriptor.set_texture_type(MTLTextureType::D2);
        texture_descriptor.set_pixel_format(MTLPixelFormat::R8Unorm);
        texture_descriptor.set_width(atlas_width as u64);
        texture_descriptor.set_height(atlas_height as u64);
        texture_descriptor.set_usage(MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite);

        let texture = device.new_texture(&texture_descriptor);

        let region = MTLRegion {
            origin: MTLOrigin { x: 0, y: 0, z: 0 },
            size: MTLSize { width: atlas_width as u64, height: atlas_height as u64, depth: 1 },
        };

        let bytes_per_row = atlas_width;

        texture.replace_region(region, 0, bitmap.as_ptr() as *const _, bytes_per_row as u64);

        let image: GrayImage = image::ImageBuffer
            ::from_raw(atlas_width as u32, atlas_height as u32, bitmap.clone())
            .unwrap();
        image.save("font_atlas.png").unwrap();

        Ok(FontAtlas {
            bitmap,
            width: atlas_width,
            height: atlas_height,
            glyphs: glyph_infos,
            texture,
        })
    }

    /// Retrieves glyph information for the given character.
    pub fn glyph(&self, c: char) -> Option<&GlyphInfo> {
        self.glyphs.get(&c)
    }

    /// Optionally, expose the bitmap and dimensions for uploading to Metal.
    pub fn get_bitmap(&self) -> &[u8] {
        &self.bitmap
    }

    pub fn atlas_dimensions(&self) -> (usize, usize) {
        (self.width, self.height)
    }
}
