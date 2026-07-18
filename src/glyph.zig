pub fn positionToBitmask(x: u16, y: u16) u8 {
    // translate to braille unicode bit mapping
    // [2800-28ff](https://www.unicode.org/charts/PDF/U2800.pdf)
    const lut: [8]u8 = comptime .{
        0x01, 0x02, 0x04, 0x40, // x = 0
        0x08, 0x10, 0x20, 0x80, // x = 1
    };
    return lut[@intCast((x & 1) << 2 | (y & 3))];
}

pub fn encodeGlyphUtf8(bits: u8) [3]u8 {
    // we must apply the upper part (0x28) of the code point manually
    // 1st constant is 0xe0, combined with 0x2
    // 2nd constant is 0x80, combined with 0x8
    // 3rd constant is left unchanged
    // [explainer](https://en.wikipedia.org/wiki/UTF-8#Description)
    return .{
        0xe2,
        0xa0 | bits >> 6,
        0x80 | (bits & 0b0011_1111),
    };
}

pub fn decodeGlyphUtf8(glyph: [3]u8) u8 {
    // we reverse the operations of `encodeGlyphUtf8`
    // 1st byte can be ignored,
    // 2nd byte contains the upper bits
    // 3rd byte contains the lower bits
    std.debug.assert(glyph[0] == 0xe2);
    return ((glyph[1] & 0b11) << 6) | (glyph[2] & 0b0011_1111);
}

pub const Codec = struct {
    pub const Error = std.Io.Reader.Error || std.Io.Writer.Error;

    reader: *std.Io.Reader,
    writer: *std.Io.Writer,

    pub fn encode(codec: Codec, limit: usize) Error!void {
        for (0..limit) |_| {
            const bits = try codec.reader.takeByte();
            try codec.writer.writeAll(&encodeGlyphUtf8(bits));
        }
    }

    pub fn decode(codec: Codec, limit: usize) Error!void {
        for (0..limit) |_| {
            const glyph = try codec.reader.takeArray(3);
            try codec.writer.writeByte(decodeGlyphUtf8(glyph.*));
        }
    }
};

test "unicode from combined pos" {
    const combined = positionToBitmask(0, 0) | positionToBitmask(1, 0);
    const codepoint = 0x2800 | @as(u16, combined);
    try std.testing.expectEqual('\u{2809}', codepoint);
}

test "unicode from wrapped pos" {
    const codepoint = 0x2800 | @as(u16, positionToBitmask(16, 33));
    try std.testing.expectEqual('\u{2802}', codepoint);
}

test "encode utf-8 from pos" {
    const glyphs: [8]u16 = .{
        '\u{2801}', '\u{2808}',
        '\u{2802}', '\u{2810}',
        '\u{2804}', '\u{2820}',
        '\u{2840}', '\u{2880}',
    };

    inline for (0..4) |y| inline for (0..2) |x| {
        const expected = std.unicode.utf8EncodeComptime(glyphs[y * 2 + x]);
        const actual = encodeGlyphUtf8(positionToBitmask(x, y));
        try std.testing.expectEqualSlices(u8, &expected, &actual);
    };
}

test "encode/decode utf-8 all masks" {
    for ('\u{2800}'..'\u{28ff}') |codepoint| {
        var utf8: [3]u8 = undefined;
        const written = try std.unicode.utf8Encode(@truncate(codepoint), &utf8);
        try std.testing.expectEqual(3, written);

        const encoded = encodeGlyphUtf8(@truncate(codepoint));
        try std.testing.expectEqualSlices(u8, &utf8, &encoded);

        const decoded = 0x2800 | @as(u16, decodeGlyphUtf8(encoded));
        try std.testing.expectEqual(codepoint, decoded);
    }
}

test Codec {
    const dots_expected: u8 = 0x11;
    const utf8_expected: [3]u8 = comptime encodeGlyphUtf8(dots_expected);

    var dots_buffer: [1]u8 = undefined;
    var utf8_buffer: [3]u8 = undefined;

    {
        dots_buffer[0] = dots_expected;
        utf8_buffer = @splat(0);

        var in: std.Io.Reader = .fixed(&dots_buffer);
        var out: std.Io.Writer = .fixed(&utf8_buffer);

        try (Codec{ .reader = &in, .writer = &out }).encode(1);
        try std.testing.expectEqualSlices(u8, &utf8_expected, &utf8_buffer);
    }

    {
        dots_buffer = @splat(0);
        utf8_buffer = utf8_expected;

        var in: std.Io.Reader = .fixed(&utf8_buffer);
        var out: std.Io.Writer = .fixed(&dots_buffer);

        try (Codec{ .reader = &in, .writer = &out }).decode(1);
        try std.testing.expectEqual(dots_expected, dots_buffer[0]);
    }
}

const std = @import("std");
