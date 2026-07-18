pub fn positionToBufferIndex(x: u16, y: u16, columns: u16) usize {
    return (y >> 2) * columns + (x >> 1);
}

pub fn calculateBufferDimensions(width: u16, height: u16) struct { usize, usize } {
    return .{ ceilDivision(width, 2), ceilDivision(height, 4) };
}

pub fn calculateBufferSize(width: u16, height: u16) usize {
    const dims = calculateBufferDimensions(width, height);
    return dims.@"0" * dims.@"1";
}

fn ceilDivision(x: anytype, y: anytype) @TypeOf(x / y) {
    return x / y + @intFromBool(x % y != 0);
}

test calculateBufferSize {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(1, calculateBufferSize(1, 1));
    try expectEqual(1, calculateBufferSize(2, 2));
    try expectEqual(1, calculateBufferSize(2, 4));

    try expectEqual(2, calculateBufferSize(3, 4));
    try expectEqual(2, calculateBufferSize(2, 5));
    try expectEqual(2, calculateBufferSize(2, 8));

    try expectEqual(3, calculateBufferSize(5, 4));
    try expectEqual(3, calculateBufferSize(2, 9));
    try expectEqual(3, calculateBufferSize(6, 4));

    try expectEqual(4, calculateBufferSize(4, 8));
    try expectEqual(4, calculateBufferSize(8, 2));
    try expectEqual(4, calculateBufferSize(2, 14));
}

const std = @import("std");
