fn BackingInt(T: type) type {
    return @typeInfo(T).@"struct".backing_integer.?;
}

pub inline fn fromBackingInt(T: type, v: BackingInt(T)) T {
    return @bitCast(v);
}

pub inline fn backingInt(v: anytype) BackingInt(@TypeOf(v)) {
    return @bitCast(v);
}

const builtin = @import("builtin");
