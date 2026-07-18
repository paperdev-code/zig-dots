pub fn main(init: std.process.Init) !void {
    // setting up -----------------------------------------------------------------
    var buffer: [0xffa]u8 = @splat(0);
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    if (!(stdout.file.supportsAnsiEscapeCodes(init.io) catch unreachable)) {
        std.log.err("file does not support ansi escape codes", .{});
        return;
    }

    var canvas: dots.Context.Allocated = try .init(init.gpa, 96, 96);
    defer canvas.deinit(init.gpa);

    // draw to the context --------------------------------------------------------
    var ctx = &canvas.context;

    ctx.clear();

    ctx.region(16, 16, 64, 64).cubic(&.{
        // zig fmt: off
        -0.7,  0.0,
        -1.7,  0.3,
         1.7,  0.3,
         0.8,  0.0,
        // zig fmt: on
    }, .dot_set, 1);

    ctx.arc(0.0, 0.0, 0.0, std.math.tau, 0.5, 7, .dot_set, 1);

    const star_region = ctx.region(8, 8, 5, 5);
    star_region.lines(&.{
        // zig fmt: off
        -1.0,  0.0,
         0.0,  1.0,
         1.0,  0.0,
         0.0, -1.0,
        -1.0,  0.0,
        // zig fmt: on
    }, .dot_set, 1);

    _ = ctx.blit(82, 32, .dot_set, &star_region);
    _ = ctx.blit(64, 13, .dot_set, &star_region);
    _ = ctx.blit(53, 91, .dot_set, &star_region);
    _ = ctx.blit(10, 56, .dot_set, &star_region);

    // render to the terminal -----------------------------------------------------
    const cols = canvas.context.columns;

    var front_buffer: std.Io.Reader = .fixed(canvas.swap());

    var codec: dots.glyph.Codec = .{
        .reader = &front_buffer,
        .writer = &stdout.interface,
    };

    while (codec.encode(cols)) {
        try stdout.interface.print("\x1b[1B\x1b[{d}D", .{cols});
    } else |err| switch (err) {
        error.EndOfStream => {
            try stdout.interface.print("~ made with dots!\n", .{});
            try stdout.interface.flush();
        },
        else => return err,
    }
}

const dots = @import("dots");
const std = @import("std");
