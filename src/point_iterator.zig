pub const PointIteratorOptions = struct {
    values_per_point: usize,
    points_per_chunk: usize,
    window_step_size: usize,
};

pub fn PointIterator(opts: PointIteratorOptions) type {
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

const std = @import("std");
