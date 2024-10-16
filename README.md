# mt - /ˈem(p)tē/
Fastest[^1] MacOS Terminal Emulator

Built with SwiftUI prioritizing performance and latency above all else.

## Architecture

### Text Buffer
- buffer (2D array of CharacterCells)
- viewport (Top and bottom row index that is visible)
- dirtyRows (Rows that need to be rerendered)

### Renderer
- Render only the dirtyRows
- should handle textwrapping

[^1]: So I really don't know if this is true
