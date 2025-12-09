# mt - /ˈem(p)tē/

Fastest[^1] MacOS Terminal Emulator

Prioritizing performance and latency above all else.

---

Short version: the computer parts of that loop can be well under a millisecond; the screen is usually the limiting factor (≈8–17 ms on a 60 Hz display).

Let’s walk the path and put rough lower bounds on each step for macOS.

⸻

1. Keyboard → your terminal app

Path: key press → keyboard controller → USB/Bluetooth → macOS HID stack → WindowServer → your app gets a keyDown event.

Theoretical-ish numbers on a modern Mac with a wired keyboard:
• Keyboard hardware scan rate: typically 500–1000 Hz
→ 1–2 ms worst case, ~0.5–1 ms typical.
• OS input stack + WindowServer dispatch into your app:
• Well-optimized path: tens of microseconds to a few hundred µs.

Best case: ~0.5–1.5 ms from physical press to your process seeing the keyDown.

You don’t really beat this in software; it’s mostly hardware and OS.

⸻

2. Terminal app → pty → shell

Once your process has the key event: 1. Convert keyDown → byte (e.g., “a” or escape sequence). 2. Write to master side of the pty with write() or similar. 3. Kernel queues it, wakes the process on the slave side (shell).

If your app and shell are both running and scheduled:
• User–kernel crossing + pty buffering: a few microseconds.
• Waking shell (already resident) + context switch: a few µs–tens of µs.
• Shell reads a single byte (canonical/ICANON/etc. aside) and echoes it:
• read() + write() back to the pty: again microseconds of pure work.

In a steady-state, hot-cache situation, you’re realistically in the 10–50 µs range for:

terminal → kernel → shell → kernel → terminal (data only)

The biggest variability here is scheduler timing. If either process is descheduled and has to wait for its next timeslice, you can easily add hundreds of microseconds to a few ms. But the theoretical floor with both runnable is in the tens of µs.

⸻

3. Terminal app → render → frame on screen

Now your terminal gets data from the master pty, updates its backing store, and the OS shows it.

Breakdown: 1. Read from pty + parse + layout update
• With a fast renderer (GPU-backed, minimal text shaping), echoing a single glyph is extremely cheap.
• Budget: <50–100 µs for the entire “got a byte → updated buffer” path in a highly optimized app. 2. Compositing and vsync
Here’s the real killer:
• macOS (like most composited desktops) queues your drawn buffer for display.
• The panel refresh is usually 60 Hz → frame every 16.67 ms.
• If your draw lands just after a vsync boundary, you may wait nearly a full frame for it to appear. On average, you pay about half a frame.
So with a 60 Hz display:
• Best case: you finish drawing right before scanout → ~0 ms extra.
• Typical case: ≈8 ms latency from “done drawing” to “photons updated”.
• Worst case (single-buffered experience): almost 16.7 ms.
High-refresh monitors (120 Hz, 144 Hz, etc.) cut this proportionally, but laptops are often 60–120 Hz.

⸻

4. End-to-end latency budget

Putting it together for a very fast terminal on macOS, on a 60 Hz display, and assuming:
• Wired keyboard,
• Shell is idle and runnable,
• All processes hot and not descheduled,
• Rendering pipeline is optimized, minimal work per key:

Theoretical “near-ideal” best case
• Key press → event in your app: ~1 ms
• App → pty → shell → pty → app: ~20–50 µs
• App → draw updated glyph: ~50–100 µs
• Draw → display scanout: 0–1 ms (you caught the current frame)

Total absolute best-case floor: roughly 1.2–2 ms from physical keypress to first pixel being scanned out on a really lucky frame.

You might occasionally hit something in this range, but it’s not what you can rely on.

More realistic “good” case on 60 Hz
• Keyboard & input path: 1–2 ms
• Terminal ↔ pty ↔ shell: ~50–200 µs
• Rendering: ~0.1–0.5 ms
• Vsync / scanout: ~8 ms average

Total practical low-latency budget: around 9–11 ms for a snappy terminal on a 60 Hz panel.

On a 120 Hz display (8.33 ms per frame), that typical ~half-frame vsync cost becomes ~4 ms, so you might see ~5–7 ms end-to-end when well-tuned.

⸻

What you can and can’t optimize

Things you mostly can’t improve:
• Keyboard hardware scan and USB/Bluetooth latency.
• macOS event delivery architecture.
• The display’s refresh interval and vsync behavior (outside variable refresh or special modes).

Things you can really optimize:
• Avoid any extra buffering or threads in your I/O path.
• Minimize work per byte from pty (parsing + layout + GPU command submission).
• Avoid synchronous, blocking calls on the render hot path.
• Try to line up your draw calls just ahead of vsync (frame pacing).

⸻

If you want, next step we can sketch a concrete architecture (single-threaded I/O loop vs dedicated render thread, pty usage patterns, and how to benchmark your actual key→photon latency so you can see how close you get to these bounds).

[^1]: So I really don't know if this is true
