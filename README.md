<p align="center">
<img alt="[Dots]" src="dots.gif"/>
</p>

# A semigraphical drawing library made in Zig.
I created this library as a way to learn my way around the Zig programming language. It is a type of virtual dot matrix that can be either printed to the terminal, or returned as a string that consists of **Unicode** Braille characters.

## Adding to your project.
Add the library either by importing the file, or as a package in build.zig (recommended)
```zig
const dots = .{
    .name = "dots",
    .path = .{.path = "zig-dots/dots.zig"}
};
...
exe.addPackage(dots);
```

## Example code
A basic example showing how to use Dots. Explore the source code for more details.
```zig
/// helloworld.zig
/// Paperdev-code (c)
const std = @import("std");
const dots = @import("dots");

// Dots helloworld program.
pub fn main() !void {
    var stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;
    const config = dots.Config.init(64, 64, allocator);
    
    var buffer = try dots.Buffer.create(&config);
    defer buffer.destroy();
    
    var display = try dots.Display.create(&config);
    defer display.destroy();

    var context = try dots.Context.init(&buffer);

    // d
    context.line(-0.5,-0.2,-0.5, 0.9, .{.bitset = 1});
    context.circ(-0.65, 0.6, 3.14 - 0.56, 3.14 * 2.0 + 0.56, 0.25, 64, .{.bitset = 1});
    // o
    context.circ(-0.2, 0.65, 0, 3.14 * 2.0, 0.2, 64, .{.bitset = 1});
    // t
    context.circ( 0.25, 0.7, 3.14 * 1.5, 3.14 * 2.5, 0.15, 64, .{.bitset = 1});
    context.line( 0.11, 0.2, 0.11, 0.8, .{.bitset = 1});
    context.line( 0.0, 0.3, 0.25, 0.3, .{.bitset = 1});
    // s
    context.circ( 0.65, 0.4, 3.14 / 2.0, 3.14 * 2.0, 0.15, 64, .{.bitset = 1});
    context.circ( 0.65, 0.7, 3.14 * 2.0 + 3.14, 3.14 / 2.0 + 3.14, 0.15, 64, .{.bitset = 1});

    while (true) {
        context.rect(-1.0,-1.0, 1.0, 1.0, .{.bitxor = 1});
        std.time.sleep(std.time.ns_per_s * 0.5);
        try display.print(&buffer, 0, 0, &stdout);
    }
}
```