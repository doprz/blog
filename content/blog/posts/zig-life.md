---
date: '2026-01-10'
draft: false
title: "Conway's Game of Life in Zig: A Weekend Project"
---
This weekend I built Conway's Game of Life in Zig with two build targets: a native terminal application and a WebAssembly module powering a React frontend. What started as an excuse to write more Zig turned into an interesting exercise in designing shared code across very different runtime environments.

The full source is available at https://github.com/doprz/zig_life

## Why Zig?

I've been drawn to Zig for its explicit memory management, lack of hidden control flow, and first-class WASM support. Building a cellular automaton felt like the right level of complexity; simple enough to finish in a weekend, complex enough to exercise the language's strengths.

I also set a secondary goal: **zero external dependencies**. No ncurses, no `cImport`, no third-party deps, just the Zig standard library and raw system calls. I wanted to understand what those libraries abstract away, and Zig's thin libc wrapper made this practical without being painful.

## Architecture

I settled on the following modular file structure on the zig side:

```sh
src
├── core.zig      # Shared cgol logic
├── main.zig      # Entry point for terminal build target
├── terminal.zig  # ANSI terminal renderer + utils
└── wasm.zig      # WebAssembly exports
```

The key constraint I set for myself was making `core.zig` depend only on the standard Zig library. It has no I/O dependencies or a specific allocator, allowing it to be portable across targets.

### core.zig: The Heart of the Simulation

The core module defines `Cell` and `Grid`.

`Cell` is pretty straightforward. It represents a cell's state and has a helpful toggle method. 

```zig
pub const Cell = enum(u8) {
    dead = 0,
    alive = 1,

    pub fn toggle(self: Cell) Cell {
        return if (self == .alive) .dead else .alive;
    }
};
```

Using an `enum(u8)` gives us type safety while guaranteeing a single-byte representation. This is important for the WASM memory layout later.

The `Grid` struct holds the simulation state:

```zig
pub const Grid = struct {
    cells: []Cell,
    width: usize,
    height: usize,
    generation: u64 = 0,

    // ...
};
```

#### Neighbor Counting

```zig
/// Counts the number of alive neighbors surrounding the given cell.
/// Only considers the 8 adjacent cells (excludes diagonals outside bounds).
pub fn countNeighbors(self: *Self, x: usize, y: usize) u8 {
    var count: u8 = 0;
    const offsets = [_]i8{ -1, 0, 1 };
    for (offsets) |dy| {
        for (offsets) |dx| {
            if (dx == 0 and dy == 0) continue;
            const nx = @as(isize, @intCast(x)) + dx;
            const ny = @as(isize, @intCast(y)) + dy;
            if (nx >= 0 and ny >= 0) {
                if (self.get(@intCast(nx), @intCast(ny)) == .alive) {
                    count += 1;
                }
            }
        }
    }

    return count;
}
```

#### The Step Function

Conway's rules are beautifully simple: a live cell survives with 2-3 neighbors, a dead cell is born with exactly 3. The implementation uses double buffering to avoid the classic cellular automaton mistake of updating cells in-place:

```zig
pub fn step(self: *Self, scratch: []Cell) void {
    for (0..self.height) |y| {
        for (0..self.width) |x| {
            const neighbors = self.countNeighbors(x, y);
            const current = self.get(x, y);
            const idx = self.index(x, y);

            scratch[idx] = switch (current) {
                .alive => if (neighbors == 2 or neighbors == 3) .alive else .dead,
                .dead => if (neighbors == 3) .alive else .dead,
            };
        }
    }

    @memcpy(self.cells, scratch[0..self.cells.len]);
    self.generation += 1;
}
```

The caller provides the scratch buffer. This keeps `Grid` allocation-free after initialization and lets different targets manage memory their own way.

## Terminal Rendering

This is where the "no external dependencies" goal got interesting. Libraries like ncurses exist for good reasons; terminal handling is full of edge cases. But for a Game of Life, we only need a small subset of functionality: clear the screen, move the cursor, set colors, and query the terminal size.

### Raw ANSI Escape Codes

The terminal renderer uses ANSI escape sequences directly:

```zig
const ESC = "\x1b";

pub fn moveTo(self: *Self, x: usize, y: usize) !void {
    try self.writer.print(ESC ++ "[{d};{d}H", .{ y + 1, x + 1 });
}

pub fn setColor(self: *Self, fg: u8, bg: u8) !void {
    try self.writer.print(ESC ++ "[0;{d};{d}m", .{ fg, bg });
}
```

These escape sequences are standardized and work on virtually any modern terminal emulator. No library needed, just string formatting.

### Terminal Size via std.posix

For responsive sizing, I needed to query the terminal dimensions. Zig's standard library wraps the necessary POSIX types, so no `@cImport` required:

```zig
pub fn getTermSize(file: std.fs.File) TermSizeError!TermSize {
    if (!file.supportsAnsiEscapeCodes()) {
        return TermSizeError.Unsupported;
    }

    return switch (builtin.os.tag) {
        .linux => {
            var ws: std.posix.winsize = undefined;
            const result = std.os.linux.ioctl(file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));

            if (result != 0) return TermSizeError.TerminalSizeUnavailable;
            return .{
                .width = ws.col,
                .height = ws.row,
            };
        },
        else => TermSizeError.Unsupported,
    };
}
```

### Buffered I/O in Zig 0.15.1

Zig 0.15 introduced a rewritten I/O system with explicit buffering. Instead of the old unbuffered `getStdOut().writer()`, you now pass your own buffer:

```zig
var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

try stdout.print("Hello World!", .{});
try stdout.flush();
```

This is a nice design as buffering behavior is explicit and configurable. For terminal rendering, this matters: without buffering, each `print` call would be a separate `write` syscall, causing visible flicker as the screen updates. With a buffer sized to the grid, we batch all the escape codes and cell data into a single write, producing smooth, flicker-free updates and improved performance.

The render loop redraws the entire grid each frame. This is fine for now although a more efficient implementation would track dirty cells and only update changes. Weekend project constraints won.

## The WASM Target

This is where things get interesting. Zig's WASM support is excellent. You set the target to `wasm32-freestanding` and the compiler handles the rest. But bridging the gap between Zig's type system and JavaScript/TypeScript requires some care.

### wasm.zig: The Export Layer

The WASM module is a thin wrapper around `core.Grid`:

```zig
const std = @import("std");
const core = @import("core.zig");

const allocator = std.heap.page_allocator;

var wasm_grid: ?core.Grid = null;
var wasm_scratch: ?[]core.Cell = null;

export fn init(width: u32, height: u32) bool {
    wasm_grid = core.Grid.init(allocator, .{
        .width = width,
        .height = height,
    }) catch return false;

    const size = width * height;
    wasm_scratch = allocator.alloc(core.Cell, size) catch return false;

    return true;
}

export fn deinit() void {
    if (wasm_grid) |*g| {
        g.deinit(allocator);
        wasm_grid = null;
    }

    if (wasm_scratch) |s| {
        allocator.free(s);
        wasm_scratch = null;
    }
}
```

A few things to note:

1. **Global state**: WASM modules are singletons, so global variables are fine here. The `?core.Grid` optional type lets us represent "not yet initialized."

2. **Page allocator**: For WASM, `std.heap.page_allocator` maps directly to `memory.grow`. It's simple and works.

3. **Memory Cleanup**: Resizing the browser window (which re-initializes the grid) causes a memory leak due to the previous memory allocation not being freed. This is now handled with `deinit`.

### Zero-Copy Cell Access

The most important optimization is exposing direct access to the cell buffer:

```zig
export fn getCellsPtr() ?[*]core.Cell {
    return if (wasm_grid) |g| g.cells.ptr else null;
}

export fn getCellsLen() usize {
    return if (wasm_grid) |g| g.cells.len else 0;
}
```

On the TypeScript side:

```typescript
export interface CGOLWasm {
  memory: WebAssembly.Memory;

  // Match exports in src/wasm.zig
  init(width: number, height: number): boolean;
  deinit(): void;
  getCellsPtr(): number;
  getCellsLen(): number;

  // ...
}

let wasmInstance: CGOLWasm | null = null;

export async function loadWasm(): Promise<CGOLWasm> {
  if (wasmInstance) return wasmInstance;

  const response = await fetch("/zig_life_wasm.wasm");
  const bytes = await response.arrayBuffer();

  const { instance } = await WebAssembly.instantiate(bytes, {});

  wasmInstance = instance.exports as unknown as CGOLWasm;
  return wasmInstance;
}

export function getCellsArray(wasm: CGOLWasm): Uint8Array {
  const ptr = wasm.getCellsPtr();
  const len = wasm.getCellsLen();
  return new Uint8Array(wasm.memory.buffer, ptr, len);
}
```

This returns a *view* into WASM linear memory, hence no copying. The renderer reads directly from this array every frame. For an 80×50 grid that's 4,000 cells; copying that 60 times per second would add up. With zero-copy, it's essentially free.

The trick works because `Cell` is a `u8` under the hood (that `enum(u8)` declaration pays off here). JavaScript sees a flat byte array where `0` is dead and `1` is alive.

### Build Configuration

`build.zig` handles both build targets. Here is the wasm-specific build config:

```zig
// WASM build
const wasm_target = b.resolveTargetQuery(.{
    .cpu_arch = .wasm32,
    .os_tag = .freestanding,
});

const wasm = b.addExecutable(.{
    .name = "zig_life_wasm",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    }),
});
wasm.entry = .disabled;
wasm.rdynamic = true;
```

Key settings:
- `.entry = .disabled` — WASM modules don't have a `main`
- `.rdynamic = true` — Export all `export fn` symbols
- `.optimize = .ReleaseSmall` — Minimize binary size

The resulting `.wasm` file is around 3KiB.

## The React Frontend

The web frontend is straightforward Bun, Vite, React, and TypeScript with a canvas. The interesting parts are the WASM integration and responsive sizing.

### Responsive Grid Sizing

The grid dimensions are calculated from the viewport:

```typescript
useEffect(() => {
    const updateDimensions = () => {
        const width = window.innerWidth;
        const height = window.innerHeight;
        const gridWidth = Math.floor(width / CELL_SIZE);
        const gridHeight = Math.floor(height / CELL_SIZE);

        setDimensions({ width, height });
        setGridSize({ width: gridWidth, height: gridHeight });

        console.log(
        `Window resized: ${width}x${height}, Grid size: ${gridWidth}x${gridHeight}`,
        );
    };

    updateDimensions();
    window.addEventListener("resize", updateDimensions);
    return () => window.removeEventListener("resize", updateDimensions);
}, []);
```

When grid size changes, another effect re-initializes the WASM module:

```typescript
useEffect(() => {
    if (gridSize.width > 0 && gridSize.height > 0) {
        const success = wasm.init(gridSize.width, gridSize.height);
        if (success) {
            wasm.randomize(BigInt(Date.now()), DENSITY);
            setInitialized(true);
        }
    }

    // Free up allocations
    return () => {
        wasm.deinit();
        console.log("wasm.deinit() called");
    };
}, [wasm, gridSize]);
```

That cleanup function in the return statement ensures memory is freed when the component unmounts or before re-initialization. This fixed a memory leak that was causing the tab to balloon in size after several resizes.

### Render Loop

The render loop uses `requestAnimationFrame` with a timestamp check to control simulation speed:

```typescript
useEffect(() => {
    if (!initialized) return;

    const loop = (timestamp: number) => {
        if (running && timestamp - lastStepRef.current >= TICK_SPEED) {
        wasm.step();
        lastStepRef.current = timestamp;
        }
        render();
        animationRef.current = requestAnimationFrame(loop);
    };

    animationRef.current = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(animationRef.current);
}, [wasm, initialized, running, render]);
```

This decouples the render rate (60fps) from the simulation rate (configurable via `TICK_SPEED`). The simulation can run at 10 generations per second while the canvas updates smoothly.

### Canvas Drawing

The actual drawing is intentionally simple:

```typescript
const render = useCallback(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx || !initialized || gridSize.width === 0) return;

    const w = gridSize.width;
    const h = gridSize.height;
    const cells = getCellsArray(wasm);

    // Clear screen
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = "#d65d0e"; // Gruvbox orange
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
        const idx = y * w + x;
        // Cell is alive
        if (cells[idx] === 1) {
            ctx.fillRect(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE);
        }
        }
    }
}, [wasm, initialized, gridSize]);
```

Clear the canvas, iterate over cells, draw filled rectangles for live cells. The Gruvbox orange on black gives it a nice retro terminal aesthetic.

## Lessons Learned

**Zig's standard library is surprisingly complete.** I expected to need `@cImport` for the `ioctl` call, but `std.posix` and `std.os.linux` already expose the necessary types and functions. Truly zero dependencies—not even C headers.

**Zig's optionals are great for FFI.** The `?T` pattern naturally expresses "this might not be initialized yet" and the compiler forces you to handle both cases.

**Zero-copy is worth the setup.** Exposing raw pointers across the WASM boundary felt slightly dangerous, but the performance benefit is worth it.

**Memory management across boundaries requires thought.** The resize memory leak was subtle. In pure Zig, you'd typically free in the same scope you allocated via a `defer`. With WASM + React, the lifecycles are driven by JS/TS, so you need explicit cleanup at those boundaries.

**Zig's build system is underrated.** Configuring both native and WASM targets in a single `build.zig` with proper module dependencies just works. No CMake, no separate toolchains, no wasm-pack.
