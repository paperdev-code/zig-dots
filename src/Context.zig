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
    const x_abs, const y_abs = .{ x + context.x_min, y + context.y_min };
    if (x_abs < context.x_min or x_abs >= context.x_max or
        y_abs < context.y_min or y_abs >= context.y_max) return;
    const index = dots.mem.positionToBufferIndex(@intCast(x_abs), @intCast(y_abs), context.columns);
    const mask = dots.glyph.positionToBitmask(@intCast(x_abs), @intCast(y_abs));
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
    const x_abs, const y_abs = .{ x + context.x_min, y + context.y_min };
    if (x_abs < context.x_min or x_abs >= context.x_max or
        y_abs < context.y_min or y_abs >= context.y_max) return 0;
    const index = dots.mem.positionToBufferIndex(@intCast(x_abs), @intCast(y_abs), context.columns);
    const mask = dots.glyph.positionToBitmask(@intCast(x_abs), @intCast(y_abs));
    return @intFromBool(context.buffer[index] & mask > 0);
}

pub fn clear(context: *const Context) void {
    const width, const height = context.dimensions();
    for (0..height) |y| for (0..width) |x| {
        context.bitset(@intCast(x), @intCast(y), .dot_set, 0);
    };
}

pub fn blit(target: *const Context, x: i17, y: i17, op: Operation, source: *const Context) Context {
    const width, const height = source.dimensions();
    var target_region = target.region(x, y, width, height);
    for (0..height) |region_y| for (0..width) |region_x| {
        target_region.bitset(
            @as(i17, @intCast(region_x)),
            @as(i17, @intCast(region_y)),
            op,
            source.bitget(
                @as(i17, @intCast(region_x)),
                @as(i17, @intCast(region_y)),
            ),
        );
    };
    return target_region;
}

pub fn set(context: *const Context, x: f32, y: f32, op: Operation, v: u1) void {
    const width, const height = context.dimensions();
    context.bitset(
        screenspaceTransform(x * context.aspect, width),
        screenspaceTransform(y, height),
        op,
        v,
    );
}

pub fn get(context: *const Context, x: f32, y: f32) u1 {
    const width, const height = context.dimensions();
    return context.bitget(
        screenspaceTransform(x * context.aspect, width),
        screenspaceTransform(y, height),
    );
}

pub fn line(context: *const Context, x1: f32, y1: f32, x2: f32, y2: f32, op: Operation, v: u1) void {
    const width, const height = context.dimensions();
    const ax = screenspaceTransform(x1 * context.aspect, width);
    const ay = screenspaceTransform(y1, height);
    const bx = screenspaceTransform(x2 * context.aspect, width);
    const by = screenspaceTransform(y2, height);
    // zig fmt: off
    const ax_clip,
    const ay_clip,
    const bx_clip,
    const by_clip = calculateLineClip(ax, ay, bx, by, width, height) orelse return;
    // zig fmt: on
    const dx = bx_clip - ax_clip;
    const dy = by_clip - ay_clip;
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
const PointIterator = dots.point_iterator.PointIterator;
const dots = @import("dots");
const Allocator = std.mem.Allocator;
const std = @import("std");

fn screenspaceTransform(v: f32, max: u16) i17 {
    // subtracts 1 from `max` to ensure 1.0 is within bounds rather than just outside of it
    const norm = (v + 1.0) / 2.0;
    const scale = @as(f32, @floatFromInt(max - 1));
    return @as(i17, @intFromFloat(norm * scale));
}

fn calculateLineClip(ax: i17, ay: i17, bx: i17, by: i17, width: u16, height: u16) ?@Tuple(&@as([4]type, @splat(i17))) {
    // calculate the line clip, i.e the points which intersect the viewport
    // [explainer](https://en.wikipedia.org/wiki/Cohen-Sutherland_algorithm)
    const OutCode = packed struct(u4) {
        above: u1,
        below: u1,
        left: u1,
        right: u1,

        pub fn inside(oc: @This()) bool {
            return builtins.backingInt(oc) == 0;
        }

        pub fn sharedZone(oc: @This(), other: @This()) bool {
            return builtins.backingInt(oc) & builtins.backingInt(other) != 0;
        }

        pub fn get(x: i17, y: i17, x_max: u16, y_max: u16) @This() {
            var code = builtins.fromBackingInt(@This(), 0);
            if (x < 0)
                code.left = 1
            else
                code.right = @intFromBool(x > x_max);
            if (y < 0)
                code.below = 1
            else
                code.above = @intFromBool(y > y_max);
            return code;
        }
    };

    // zig fmt: off
    var ax_tmp,
    var ay_tmp,
    var bx_tmp,
    var by_tmp = .{ ax, ay, bx, by };
    // zig fmt: on

    var a_oc = OutCode.get(ax, ay, width, height);
    var b_oc = OutCode.get(bx, by, width, height);

    for (0..4) |_| {
        if (a_oc.inside() and b_oc.inside()) return .{ ax, ay, bx, by };
        if (a_oc.sharedZone(b_oc)) return null;

        const outside = if (!a_oc.inside()) a_oc else b_oc;
        var x: i17, var y: i17 = .{ undefined, undefined };

        if (outside.above != 0) {
            x = ax_tmp + (bx_tmp - ax_tmp) * @divFloor(height - ay_tmp, by_tmp - ay_tmp);
            y = height;
        } else if (outside.below != 0) {
            x = ax_tmp + (bx_tmp - ax_tmp) * @divFloor(-ay_tmp, by_tmp - ay_tmp);
            y = 0;
        } else if (outside.right != 0) {
            x = width;
            y = ay_tmp + (by_tmp - ay_tmp) * @divFloor(width - ax_tmp, bx_tmp - ax_tmp);
        } else if (outside.left != 0) {
            x = 0;
            y = ay_tmp + (by_tmp - ay_tmp) * @divFloor(-ay_tmp, bx_tmp - ax_tmp);
        }

        if (a_oc == outside) {
            ax_tmp = x;
            ay_tmp = y;
            a_oc = OutCode.get(ax_tmp, ay_tmp, width, height);
        } else {
            bx_tmp = x;
            by_tmp = y;
            b_oc = OutCode.get(bx_tmp, by_tmp, width, height);
        }
    }

    unreachable;
}

fn distanceApprox(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    // approximate distance calculation using 'alpha max plus beta min'
    // [explainer](https://en.wikipedia.org/wiki/Alpha_max_plus_beta_min_algorithm)
    const dx = @abs(x2 - x1);
    const dy = @abs(y2 - y1);
    return (0.941246 * @max(dx, dy) + 0.415692 * @min(dx, dy));
}

const builtins = @import("future_builtins.zig");
