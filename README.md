# Dots, a semigraphical drawing library made in Zig.
I created this library as a way to learn my way around the Zig programming language. It is a type of virtual dot matrix that can be either printed to the terminal, or returned as a string that consists of **Unicode** Braille characters.

## Example code
A basic example showing how to use Dots. Explore the source code for more details.

```zig
const std = @import("std");
const dots = @import("dots");

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.milliTimestamp()));

    const config = dots.Config.init(48, 48, &gpa.allocator);
    var buffer = try dots.Buffer.create(&config);
    var display = try dots.Display.create(&config);

    // Fill buffer with random data.
    var y : u8 = 0;
    while (y < 48) : (y += 1) {
        var x : u8 = 0;
        while(x < 48) : (x += 1) {
            buffer.set(x, y, .{.bitset = rng.random.uintAtMost(u1, 1)});
        }
    }

    // For printing to any location (row, column) on the terminal.
    // To get the output as a string, use display.string().
    try display.print(&buffer, 0, 0, &stdout);

    defer {
        buffer.destroy();
        display.destroy();
        _ = gpa.deinit();
    }
}
```
Produces an output similar to this:
```
⢴⢰⢂⣥⡴⢵⢻⣊⡼⢚⣈⠜⢱⡥⠷⡍⡮⡔⣥⢉⡅⢁⡆⢔
⠎⣍⢐⢁⢛⢻⡶⡩⠷⠂⠒⣹⠞⢊⠸⡏⢞⢴⢀⣔⣺⡃⠞⠚
⣨⠕⣨⣺⠦⢈⣈⢞⠋⠥⠃⢞⡃⢇⢓⡜⢭⢒⣩⡱⠐⠔⠷⢆
⣄⠄⡐⠍⣽⢡⠄⡀⡲⠩⢩⠩⣩⡇⠞⡘⠶⣮⢣⡳⢰⡱⠢⢓
⠌⢬⡫⣢⠑⢜⠬⢌⠰⡐⠫⣉⣜⢛⡂⡈⣅⡦⠼⢠⠆⡉⣛⡜
⢺⡞⢈⢹⡯⢅⠧⡵⣆⢗⢿⠥⠥⢓⣁⠏⢰⠌⠑⡭⢬⢦⡧⡏
⣓⡢⡵⢤⣯⢫⡟⣖⡥⠵⠑⢅⠹⠉⡳⢦⠫⡭⡓⣄⡂⠦⡩⠕
⡂⣧⣓⡴⢕⣖⢨⠶⠑⠬⠳⣕⢶⠡⢗⡜⣧⣓⠓⢈⠱⡟⣾⣕
⣎⣠⢙⠑⣢⣲⢤⠂⣮⠤⡛⠷⣶⡒⣍⡙⣨⢸⠏⡌⡴⣏⣈⣺
⠖⣧⣖⣭⡼⡁⢰⣷⠑⢇⢌⢹⠛⡛⢔⡆⢄⣻⠖⣿⢗⣀⢭⠌
⢸⣚⢙⠳⢟⠬⡳⠩⣮⢸⢺⠣⣱⠦⣯⡤⠱⢮⢛⣥⠜⣅⣗⠤
⢢⣴⡵⡓⠳⡞⣗⢫⡋⠂⣐⣠⢲⠕⡫⢭⣤⢱⢶⠋⠄⣖⡏⠘
```