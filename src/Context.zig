pub const Operation = enum(u2) { dot_set, dot_and, dot_xor, dot_or };

buffer: []u8,
columns: u16,
rows: u16,
x_min: u16,
x_max: u16,
y_min: u16,
y_max: u16,
aspect: f32,

pub fn init(buffer: []u8, width: u16, height: u16) error{BufferTooSmall}!Context {
    const columns, const rows = dots.mem.calculateBufferDimensions(width, height);
    const required_size = columns * rows;
    return if (buffer.len < required_size) error.BufferTooSmall else .{
        .buffer = buffer,
        .columns = @intCast(columns),
        .rows = @intCast(rows),
        .x_min = 0,
        .x_max = width,
        .y_min = 0,
        .y_max = height,
        .aspect = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(width)),
    };
}

pub fn region(context: *const Context, x: i17, y: i17, width: u16, height: u16) Context {
    const x_min: u16 = @intCast(@max(context.x_min + x, 0));
    const y_min: u16 = @intCast(@max(context.y_min + y, 0));
    const x_max: u16 = @min(x_min + width, context.x_max);
    const y_max: u16 = @min(y_min + height, context.y_max);
    const aspect: f32 = @as(f32, @floatFromInt(y_max -| y_min)) / @as(f32, @floatFromInt(x_max -| x_min));
    return .{
        .buffer = context.buffer,
        .columns = context.columns,
        .rows = context.rows,
        .x_min = x_min,
        .x_max = x_max,
        .y_min = y_min,
        .y_max = y_max,
        .aspect = aspect,
    };
}

pub fn dimensions(context: *const Context) struct { u16, u16 } {
    return .{
        context.x_max - context.x_min,
        context.y_max - context.y_min,
    };
}

pub fn bitset(context: *const Context, x: i17, y: i17, op: Operation, v: u1) void {
    if (x < context.x_min or x >= context.x_max or
        y < context.y_min or y >= context.y_max) return;
    const index = dots.mem.positionToBufferIndex(@intCast(x), @intCast(y), context.columns);
    const mask = dots.glyph.positionToBitmask(@intCast(x), @intCast(y));
    const bits = mask & 0 -% @as(u8, v);
    const byte = context.buffer[index];
    context.buffer[index] = switch (op) {
        .dot_set => (byte & ~mask) | bits,
        .dot_and => (byte & ~mask) | (bits & byte),
        .dot_xor => (byte & ~mask) | (bits ^ byte),
        .dot_or => byte | bits,
    };
}

pub fn bitget(context: *const Context, x: i17, y: i17) u1 {
    if (x < context.x_min or x >= context.x_max or
        y < context.y_min or y >= context.y_max) return 0;
    const index = dots.mem.positionToBufferIndex(@intCast(x), @intCast(y), context.columns);
    const mask = dots.glyph.positionToBitmask(@intCast(x), @intCast(y));
    return @intFromBool(context.buffer[index] & mask > 0);
}

pub fn clear(context: *const Context) void {
    for (context.y_min..context.y_max) |y| for (context.x_min..context.x_max) |x| {
        context.bitset(@intCast(x), @intCast(y), .dot_set, 0);
    };
}

pub fn blit(target: *const Context, x: i17, y: i17, op: Operation, source: *const Context) Context {
    const width, const height = source.dimensions();
    var target_region = target.region(x, y, width, height);
    for (0..width) |y_| for (0..height) |x_| {
        target_region.bitset(
            target.x_min + x + @as(i17, @intCast(x_)),
            target.y_min + y + @as(i17, @intCast(y_)),
            op,
            source.bitget(
                source.x_min + @as(i17, @intCast(x_)),
                source.y_min + @as(i17, @intCast(y_)),
            ),
        );
    };
    return target_region;
}

pub fn set(context: *const Context, x: f32, y: f32, op: Operation, v: u1) void {
    context.bitset(
        screenspaceTransform(x * context.aspect, context.x_min, context.x_max),
        screenspaceTransform(y, context.y_min, context.y_max),
        op,
        v,
    );
}

pub fn get(context: *const Context, x: f32, y: f32) u1 {
    return context.bitget(
        screenspaceTransform(x * context.aspect, context.x_min, context.x_max),
        screenspaceTransform(y, context.y_min, context.y_max),
    );
}

pub fn line(context: *const Context, x1: f32, y1: f32, x2: f32, y2: f32, op: Operation, v: u1) void {
    if (outOfBounds(x1 * context.aspect, y1, x2 * context.aspect, y2)) {
        @branchHint(.unlikely);
        return;
    }
    const ax = screenspaceTransform(x1 * context.aspect, context.x_min, context.x_max);
    const ay = screenspaceTransform(y1, context.y_min, context.y_max);
    const bx = screenspaceTransform(x2 * context.aspect, context.x_min, context.x_max);
    const by = screenspaceTransform(y2, context.y_min, context.y_max);
    const dx = bx - ax;
    const dy = by - ay;
    const steps: u32 = @max(@abs(dx), @abs(dy));
    const x_increment = @as(f32, @floatFromInt(dx)) / @as(f32, @floatFromInt(steps));
    const y_increment = @as(f32, @floatFromInt(dy)) / @as(f32, @floatFromInt(steps));
    for (0..steps + 1) |step| context.bitset(
        ax + @as(i17, @intFromFloat(x_increment * @as(f32, @floatFromInt(step)))),
        ay + @as(i17, @intFromFloat(y_increment * @as(f32, @floatFromInt(step)))),
        op,
        v,
    );
}

pub fn arc(context: *const Context, x: f32, y: f32, angle_begin: f32, angle_end: f32, radius: f32, segments: u8, op: Operation, v: u1) void {
    if (segments == 0) {
        return;
    }
    const increment = (angle_end - angle_begin) / @as(f32, @floatFromInt(segments));
    var prev_x = x + @cos(angle_begin) * radius;
    var prev_y = y + @sin(angle_begin) * radius;
    for (1..segments + 1) |step| {
        const next_x = x + @cos(angle_begin + @as(f32, @floatFromInt(step)) * increment) * radius;
        const next_y = y + @sin(angle_begin + @as(f32, @floatFromInt(step)) * increment) * radius;
        context.line(prev_x, prev_y, next_x, next_y, op, v);
        prev_x = next_x;
        prev_y = next_y;
    }
}

const PointIteratorOptions = struct {
    values_per_point: usize,
    points_per_chunk: usize,
    window_step_size: usize,
};

fn PointIterator(opts: PointIteratorOptions) type {
    return struct {
        const values_per_point = opts.values_per_point;
        const points_per_chunk = opts.points_per_chunk;
        const buffer_step_size = opts.window_step_size * values_per_point;

        pub const Point = @Tuple(&@as([opts.values_per_point]type, @splat(f32)));
        pub const Chunk = [points_per_chunk]Point;

        buffer: []const f32,
        buffer_index: usize,

        pub fn init(buffer: []const f32) Self {
            return .{ .buffer = buffer, .buffer_index = 0 };
        }

        pub fn next(pit: *Self) ?*const Chunk {
            const window_idx_start = pit.buffer_index;
            const window_idx_end = window_idx_start + points_per_chunk * values_per_point;
            if (window_idx_end > pit.buffer.len) {
                return null;
            }
            pit.buffer_index += buffer_step_size;
            return @ptrCast(&pit.buffer[window_idx_start]);
        }

        pub const Self = @This();
    };
}

pub fn points(context: *const Context, data: []const f32, op: Operation, v: u1) void {
    var pit: PointIterator(.{
        .values_per_point = 2,
        .points_per_chunk = 1,
        .window_step_size = 1,
    }) = .init(data);
    while (pit.next()) |coord| {
        const x, const y = coord[0];
        context.set(x, y, op, v);
    }
}

pub fn lines(context: *const Context, data: []const f32, op: Operation, v: u1) void {
    var pit: PointIterator(.{
        .values_per_point = 2,
        .points_per_chunk = 2,
        .window_step_size = 1,
    }) = .init(data);
    while (pit.next()) |segment| {
        const x1, const y1 = segment[0];
        const x2, const y2 = segment[1];
        context.line(x1, y1, x2, y2, op, v);
    }
}

pub fn triangles(context: *const Context, data: []const f32, op: Operation, v: u1) void {
    var pit: PointIterator(.{
        .values_per_point = 2,
        .points_per_chunk = 3,
        .window_step_size = 3,
    }) = .init(data);
    while (pit.next()) |triangle| {
        const p1 = triangle[0];
        const p2 = triangle[1];
        const p3 = triangle[2];
        context.line(p1.@"0", p1.@"1", p2.@"0", p2.@"1", op, v);
        context.line(p2.@"0", p2.@"1", p3.@"0", p3.@"1", op, v);
        context.line(p3.@"0", p3.@"1", p1.@"0", p1.@"1", op, v);
    }
}

pub fn quadratic(context: *const Context, data: []const f32, op: Operation, v: u1) void {
    var pit: PointIterator(.{
        .values_per_point = 2,
        .points_per_chunk = 3,
        .window_step_size = 2,
    }) = .init(data);
    const Point = @TypeOf(pit).Point;
    while (pit.next()) |curve| {
        var prev_point: Point = curve[0];
        var curr_point: Point = undefined;
        const segments: usize = @intFromFloat(16 *
            distanceApprox(curve[0].@"0", curve[0].@"1", curve[1].@"0", curve[1].@"1") +
            distanceApprox(curve[1].@"0", curve[1].@"1", curve[2].@"0", curve[2].@"1"));
        for (1..segments + 1) |step| {
            const dt: f32 = @as(f32, @floatFromInt(step)) / (@as(f32, @floatFromInt(segments)) + std.math.floatEps(f32));
            const dt_sqr = dt * dt;
            const dt_inverse = 1 - dt;
            const dt_inverse_sqr = dt_inverse * dt_inverse;
            curr_point = .{
                dt_inverse_sqr * curve[0].@"0" + 2 * dt_inverse * dt * curve[1].@"0" + dt_sqr * curve[2].@"0",
                dt_inverse_sqr * curve[0].@"1" + 2 * dt_inverse * dt * curve[1].@"1" + dt_sqr * curve[2].@"1",
            };
            const x1, const y1 = curr_point;
            const x2, const y2 = prev_point;
            context.line(x1, y1, x2, y2, op, v);
            prev_point = curr_point;
        }
    }
}

pub fn cubic(context: *const Context, data: []const f32, op: Operation, v: u1) void {
    var pit: PointIterator(.{
        .values_per_point = 2,
        .points_per_chunk = 4,
        .window_step_size = 3,
    }) = .init(data);
    const Point = @TypeOf(pit).Point;
    while (pit.next()) |curve| {
        var prev_point: Point = curve[0];
        var curr_point: Point = undefined;
        const segments: usize = @intFromFloat(24 *
            distanceApprox(curve[0].@"0", curve[0].@"1", curve[1].@"0", curve[1].@"1") +
            distanceApprox(curve[1].@"0", curve[1].@"1", curve[2].@"0", curve[2].@"1") +
            distanceApprox(curve[2].@"0", curve[2].@"1", curve[3].@"0", curve[3].@"1"));
        for (1..segments + 1) |step| {
            const dt: f32 = @as(f32, @floatFromInt(step)) / (@as(f32, @floatFromInt(segments)) + std.math.floatEps(f32));
            const dt_sqr = dt * dt;
            const dt_cub = dt_sqr * dt;
            const dt_inverse = 1 - dt;
            const dt_inverse_sqr = dt_inverse * dt_inverse;
            const dt_inverse_cub = dt_inverse_sqr * dt_inverse;
            curr_point = .{
                dt_inverse_cub * curve[0].@"0" + 3 * dt_inverse_sqr * dt * curve[1].@"0" + 3 * dt_inverse * dt_sqr * curve[2].@"0" + dt_cub * curve[3].@"0",
                dt_inverse_cub * curve[0].@"1" + 3 * dt_inverse_sqr * dt * curve[1].@"1" + 3 * dt_inverse * dt_sqr * curve[2].@"1" + dt_cub * curve[3].@"1",
            };
            const x1, const y1 = curr_point;
            const x2, const y2 = prev_point;
            context.line(x1, y1, x2, y2, op, v);
            prev_point = curr_point;
        }
    }
}

pub const Allocated = struct {
    context: Context,
    buffer: []u8,

    pub fn init(gpa: Allocator, width: u16, height: u16) error{OutOfMemory}!Allocated {
        const buffer_size = dots.mem.calculateBufferSize(width, height);
        const buffer = try gpa.alloc(u8, buffer_size * 2);
        return .{
            .context = Context.init(
                buffer[0..buffer_size],
                width,
                height,
            ) catch unreachable,
            .buffer = buffer,
        };
    }

    pub fn swap(allocated: *Allocated) []const u8 {
        const back_buffer = &allocated.context.buffer;
        const front_buffer = back_buffer.*;
        if (back_buffer.ptr == allocated.buffer.ptr) {
            back_buffer.ptr = allocated.buffer.ptr + back_buffer.len;
        } else {
            back_buffer.ptr = allocated.buffer.ptr;
        }
        return front_buffer;
    }

    pub fn swapAndClear(allocated: *Allocated) []const u8 {
        const front_buffer = allocated.swap();
        allocated.context.clear();
        return front_buffer;
    }

    pub fn deinit(allocated: *const Allocated, gpa: Allocator) void {
        gpa.free(allocated.buffer);
    }
};

test PointIterator {
    const buffer = [_]f32{
        0.0,
        0.5,
        1.0,
    };

    var pit: PointIterator(.{
        .values_per_point = 1,
        .points_per_chunk = 1,
        .window_step_size = 1,
    }) = .init(&buffer);

    try std.testing.expectEqual(@as(*const f32, @ptrCast(pit.next().?)), &buffer[0]);
    try std.testing.expectEqual(@as(*const f32, @ptrCast(pit.next().?)), &buffer[1]);
    try std.testing.expectEqual(@as(*const f32, @ptrCast(pit.next().?)), &buffer[2]);
}

fn expectNumberOfDots(target: usize, context: *const Context) !void {
    var counted: usize = 0;
    for (context.y_min..context.y_max) |y| for (context.x_min..context.x_max) |x| {
        counted += context.bitget(@intCast(x), @intCast(y));
    };
    try std.testing.expectEqual(target, counted);
}

test Context {
    var buffer: [2]u8 = @splat(0);

    var context: Context = try .init(&buffer, 4, 4);

    context.bitset(0, 0, .dot_set, 1);
    try std.testing.expectEqual(0x01, buffer[0]);

    context.bitset(0, 0, .dot_and, 1);
    try std.testing.expectEqual(0x01, buffer[0]);

    context.bitset(0, 0, .dot_xor, 1);
    try std.testing.expectEqual(0x00, buffer[0]);

    context.bitset(0, 0, .dot_or, 1);
    try std.testing.expectEqual(0x01, buffer[0]);

    context.clear();
    try std.testing.expectEqual(0x00, buffer[0]);

    context.line(-1.0, -1.0, 1.0, 1.0, .dot_set, 1);
    try std.testing.expectEqual(0x11, buffer[0]);
    try std.testing.expectEqual(0x84, buffer[1]);
}

test "bounds with various sizes of Context" {
    const gpa = std.testing.allocator;

    for (4..32) |size| {
        const buffer_size = dots.mem.calculateBufferSize(@intCast(size), @intCast(size));
        const buffer = try gpa.alloc(u8, buffer_size);
        defer gpa.free(buffer);
        const context = try dots.Context.init(buffer, @intCast(size), @intCast(size));
        context.clear();
        context.lines(&.{
            -1.0, -1.0,
            1.0,  -1.0,
            1.0,  1.0,
            -1.0, 1.0,
            -1.0, -1.0,
        }, .dot_set, 1);
        try expectNumberOfDots(size * 4 - 4, &context);
    }
}

test Allocated {
    const gpa = std.testing.allocator;

    var canvas: Allocated = try .init(gpa, 8, 8);
    defer canvas.deinit(gpa);

    canvas.context.bitset(0, 0, .dot_set, 1);
    const front_buffer = canvas.swap();
    canvas.context.bitset(0, 0, .dot_set, 1);

    try std.testing.expect(@intFromPtr(front_buffer.ptr) != @intFromPtr(canvas.context.buffer.ptr));
    try std.testing.expectEqualSlices(u8, front_buffer, canvas.context.buffer);
}

const Context = @This();
const dots = @import("dots");
const Allocator = std.mem.Allocator;
const std = @import("std");

fn screenspaceTransform(v: f32, min: u16, max: u16) i17 {
    // subtracts 1 from `max` to ensure 1.0 is within bounds rather than just outside of it
    const norm = (v + 1.0) / 2.0;
    const scale = @as(f32, @floatFromInt(max - min - 1));
    return @as(i17, @intFromFloat(norm * scale)) + min;
}

fn outOfBounds(x1: f32, y1: f32, x2: f32, y2: f32) bool {
    // simple check whether two points would be entirely outside the bounds
    // [explainer](https://en.wikipedia.org/wiki/Cohen-Sutherland_algorithm)
    // zig fmt: off
    return @max(x1, x2) < -1.0
        or @min(x1, x2) >  1.0
        or @max(y1, y2) < -1.0
        or @min(y1, y2) >  1.0;
    // zig fmt: on
}

fn distanceApprox(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    // approximate distance calculation using 'alpha max plus beta min'
    // [explainer](https://en.wikipedia.org/wiki/Alpha_max_plus_beta_min_algorithm)
    const dx = @abs(x2 - x1);
    const dy = @abs(y2 - y1);
    return (0.941246 * @max(dx, dy) + 0.415692 * @min(dx, dy));
}
