use fontdue::Font;
use metal::*;
use std::collections::HashMap;
use std::path::Path;

/// Represents metadata for a single glyph in the atlas.
pub struct GlyphInfo {
    pub x: usize,
    pub y: usize,
    pub width: usize,
    pub height: usize,
    pub baseline: f32,
}

/// The FontAtlas struct that holds the texture and glyph metadata.
pub struct FontAtlas {
    pub texture: Texture,
    glyphs: HashMap<char, GlyphInfo>,
    pub atlas_width: usize,
    pub atlas_height: usize,
    pub line_height: f32,
}

impl FontAtlas {
    /// Creates a new FontAtlas from a TTF font file.
    ///
    /// # Arguments
    ///
    /// * `device` - The Metal device.
    /// * `font_path` - Path to the TTF font file.
    /// * `font_size` - Desired font size in pixels.
    ///
    /// # Returns
    ///
    /// A Result containing the FontAtlas or an error message.
    pub fn new(device: &Device, font_path: &Path, font_size: f32) -> Result<Self, String> {
        // Load the font
        let font_data = std::fs
            ::read(font_path)
            .map_err(|e| format!("Failed to read font file: {}", e))?;
        let font = Font::from_bytes(font_data, fontdue::FontSettings::default()).map_err(|e|
            format!("Failed to parse font: {:?}", e)
        )?;

        // Define ASCII range
        let ascii_start = 32;
        let ascii_end = 126; // Printable ASCII

        // Rasterize glyphs and collect metrics
        let mut glyphs = HashMap::new();
        let mut max_width = 0;
        let mut max_height = 0;
        let mut line_height = 0.0;

        // Store glyph bitmaps temporarily
        let mut glyph_bitmaps = Vec::new();

        let char_set =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~";
        for c in char_set.chars() {
            let character = c;
            let (metrics, bitmap) = font.rasterize(character, font_size);
            glyphs.insert(character, GlyphInfo {
                x: 0, // To be updated when placing in atlas
                y: 0,
                width: metrics.width,
                height: metrics.height,
                baseline: (metrics.ymin as f32) + font_size, // Adjust as needed
            });
            glyph_bitmaps.push((character, bitmap, metrics));
            if metrics.width > max_width {
                max_width = metrics.width;
            }
            if metrics.height > max_height {
                max_height = metrics.height;
            }
            if metrics.height > (line_height as usize) {
                line_height = metrics.height as f32;
            }
        }

        // Determine atlas dimensions
        let glyph_count = ascii_end - ascii_start + 1;
        let cols: usize = 16; // 16 columns for the atlas
        let rows: usize = (glyph_count + cols - 1) / cols;

        let atlas_width = (max_width * cols) as usize;
        let atlas_height = (max_height * rows) as usize;

        // Create a blank bitmap (grayscale)
        let mut atlas_bitmap = vec![0u8; atlas_width * atlas_height];

        // Place each glyph bitmap into the atlas
        for (i, (character, bitmap, metrics)) in glyph_bitmaps.iter().enumerate() {
            let col = i % cols;
            let row = i / cols;

            let x = col * max_width;
            let y = row * max_height;

            // Update glyph position
            if let Some(glyph_info) = glyphs.get_mut(character) {
                glyph_info.x = x;
                glyph_info.y = y;
            }

            // Blit the bitmap into the atlas
            for row_idx in 0..metrics.height {
                for col_idx in 0..metrics.width {
                    let atlas_x = x + col_idx;
                    let atlas_y = y + row_idx;
                    if atlas_x < atlas_width && atlas_y < atlas_height {
                        atlas_bitmap[atlas_y * atlas_width + atlas_x] = bitmap[
                            row_idx * metrics.width + col_idx
                        ];
                    }
                }
            }
        }

        // save the atlas_bitmap to a file for debugging
        let image = image::GrayImage
            ::from_raw(atlas_width as u32, atlas_height as u32, atlas_bitmap.clone())
            .unwrap();
        image.save("atlas.png").unwrap();

        // Create a Metal texture from the bitmap
        let texture = Self::create_metal_texture(device, &atlas_bitmap, atlas_width, atlas_height)?;

        Ok(FontAtlas {
            texture,
            glyphs,
            atlas_width,
            atlas_height,
            line_height,
        })
    }

    /// Creates a Metal texture from raw bitmap data.
    ///
    /// # Arguments
    ///
    /// * `device` - The Metal device.
    /// * `bitmap` - The raw bitmap data (grayscale).
    /// * `width` - Width of the bitmap.
    /// * `height` - Height of the bitmap.
    ///
    /// # Returns
    ///
    /// A Result containing the Metal texture or an error message.
    fn create_metal_texture(
        device: &Device,
        bitmap: &[u8],
        width: usize,
        height: usize
    ) -> Result<Texture, String> {
        // Define texture descriptor
        let texture_descriptor = TextureDescriptor::new();
        texture_descriptor.set_width(width as u64);
        texture_descriptor.set_height(height as u64);
        texture_descriptor.set_depth(1);
        texture_descriptor.set_mipmap_level_count(1);
        texture_descriptor.set_sample_count(1);
        texture_descriptor.set_array_length(1);
        texture_descriptor.set_pixel_format(MTLPixelFormat::R8Unorm);
        texture_descriptor.set_usage(MTLTextureUsage::ShaderRead | MTLTextureUsage::ShaderWrite);

        // Create texture
        let texture = device.new_texture(&texture_descriptor);

        // Upload bitmap data to texture
        let region = MTLRegion {
            origin: MTLOrigin {
                x: 0,
                y: 0,
                z: 0,
            },
            size: MTLSize {
                width: width as u64,
                height: height as u64,
                depth: 1,
            },
        };

        // Assuming the bitmap is in row-major order and single channel
        texture.replace_region(
            region,
            0, // bytes_per_row (width * bytes_per_pixel)
            bitmap.as_ptr() as *const _,
            width as u64 // bytes_per_row for R8Unorm
        );

        // Wrap the Metal texture in a custom type or use it directly
        Ok(texture)
    }

    pub fn glyph_info(&self, character: char) -> Option<&GlyphInfo> {
        self.glyphs.get(&character)
    }
}
