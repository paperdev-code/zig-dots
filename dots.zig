const std = @import("std");

/// Table containing all possible characters used by a Dots Display.
const UnicodeLookup = [256][]const u8 {
    " ", "⠁", "⠈", "⠉", "⠂", "⠃", "⠊", "⠋", "⠐", "⠑", "⠘", "⠙", "⠒", "⠓", "⠚", "⠛",
    "⠄", "⠅", "⠌", "⠍", "⠆", "⠇", "⠎", "⠏", "⠔", "⠕", "⠜", "⠜", "⠖", "⠗", "⠞", "⠞",
    "⠠", "⠡", "⠡", "⠩", "⠢", "⠣", "⠪", "⠫", "⠰", "⠱", "⠸", "⠹", "⠲", "⠳", "⠺", "⠻",
    "⠤", "⠥", "⠬", "⠭", "⠦", "⠧", "⠮", "⠯", "⠴", "⠵", "⠼", "⠽", "⠶", "⠷", "⠾", "⠿",
    "⡀", "⡁", "⡈", "⡉", "⡂", "⡃", "⡊", "⡋", "⡐", "⡑", "⡘", "⡙", "⡒", "⡓", "⡚", "⡛",
    "⡄", "⡅", "⡌", "⡍", "⡆", "⡇", "⡎", "⡏", "⡔", "⡕", "⡜", "⡜", "⡖", "⡞", "⡞", "⡟",
    "⡠", "⡡", "⡨", "⡩", "⡢", "⡣", "⡪", "⡫", "⡰", "⡱", "⡸", "⡹", "⡲", "⡳", "⡺", "⡻",
    "⡤", "⡥", "⡬", "⡭", "⡦", "⡧", "⡮", "⡯", "⡴", "⡵", "⡼", "⡽", "⡶", "⡷", "⡾", "⡿",
    "⢀", "⢁", "⢈", "⢉", "⢂", "⢃", "⢊", "⢋", "⢐", "⢑", "⢘", "⢙", "⢒", "⢓", "⢚", "⢛",
    "⢄", "⢅", "⢌", "⢍", "⢆", "⢇", "⢎", "⢏", "⢔", "⢕", "⢜", "⢝", "⢖", "⢗", "⢞", "⢟",
    "⢠", "⢡", "⢨", "⢩", "⢢", "⢣", "⢪", "⢫", "⢰", "⢱", "⢸", "⢹", "⢲", "⢳", "⢺", "⢻",
    "⢤", "⢥", "⢬", "⢭", "⢦", "⢧", "⢮", "⢯", "⢴", "⢵", "⢼", "⢽", "⢶", "⢷", "⢾", "⢿",
    "⣀", "⣁", "⣈", "⣉", "⣂", "⣃", "⣊", "⣋", "⣐", "⣑", "⣘", "⣙", "⣒", "⣓", "⣚", "⣛",
    "⣄", "⣅", "⣌", "⣍", "⣆", "⣇", "⣎", "⣏", "⣔", "⣕", "⣜", "⣝", "⣖", "⣗", "⣞", "⣟",
    "⣠", "⣡", "⣨", "⣩", "⣢", "⣣", "⣪", "⣫", "⣰", "⣱", "⣸", "⣹", "⣲", "⣳", "⣺", "⣻",
    "⣤", "⣥", "⣬", "⣭", "⣦", "⣧", "⣮", "⣯", "⣴", "⣵", "⣼", "⣽", "⣶", "⣷", "⣾", "⣿",
};

/// Config containing information required for compatibility between Dots Buffers and Displays.
/// Used in memory management.
pub const Config = struct {
    /// Width measured in dots.
    width  : u16,
    /// Height measured in dots.
    height : u16,
    /// Width measured in bytes.
    cols   : u16,
    /// Height measured in bytes.
    rows   : u16,
    /// Allocator for []u8 allocation.
    allocator : *std.mem.Allocator,

    /// Returns whether two configs are the same.
    /// Actually only checks whether the columns and rows match.
    /// As long as this is true, it is technically compatible and won't cause issues.
    pub fn compare(configA : *const Config, configB : *const Config) bool {
        return (configA.rows == configB.rows) and (configA.cols == configB.cols);
    }

    /// Initializes a config based on preferred width and height measured in dots.
    /// Dots (when displayed) are contained in a character, there are 8 in total. (2x4).
    pub fn init(width : u16, height : u16, allocator : *std.mem.Allocator) Config {
        return Config {
            .width = width,
            .height = height,
            .cols = @divFloor(width,  2) + @as(u16, if (@mod(width,  2) > 0) 1 else 0),
            .rows = @divFloor(height, 4) + @as(u16, if (@mod(height, 4) > 0) 1 else 0),
            .allocator = allocator,
        };
    }
};

/// Buffer containing the data that can be displayed with a Dots display.
/// There is absolutely no need to touch most, if not any of the variables inside of this struct.
/// All interaction is meant to be done via the public methods.
/// But nothing is stopping you from reinventing the wheel.
pub const Buffer = struct {
    /// Enum containing the possible operations for changing dots.
    /// Some of these may emulate each other in certain conditions.
    const Operations = enum {
        bitset,
        bitor,
        bitxor,
        bitand,
    };

    /// Tagged union for ease of use with the op() function.
    const Operation = union(Operations) {
        bitset : u1,
        bitor  : u1,
        bitxor : u1,
        bitand : u1,
    };

    /// A Dots config.
    config : *const Config,
    /// Buffer (structured like a large multi byte bitfield) that contains dots.
    /// To be accessed as a two dimensional array.
    buffer : []u8,

    /// Creates and allocates memory for a Dots buffer.
    pub fn create(config : *const Config) !Buffer {
        const buffer = Buffer {
            .config = config,
            .buffer = try config.allocator.alloc(u8, config.cols * config.rows),
        };
        std.mem.set(u8, buffer.buffer, 0);
        return buffer;
    }

    /// Destroys and frees memory of a Dots buffer.
    pub fn destroy(self : *Buffer) void {
        self.config.allocator.free(self.buffer);
    }

    /// Set the value of a single dot in the buffer.
    /// Choose between the different operations defined in the Operations enum.
    pub fn set(self : *Buffer, x : i32, y : i32, op : Operation) void {
        // Check whether position would result in a valid index.
        if (self.validPosition(x, y)) {
            const _x = @intCast(u16, x);
            const _y = @intCast(u16, y);
            // Get the index of the correct byte, and a bitmask to extract a single dot.
            const i = self.index(_x, _y);
            const m = mask(_x, _y);
            // Depending on the value of the bit, set the byte without the rest of the bytes data.
            var byte : u8 = self.buffer[i];
            switch (op) {
                Operation.bitset => |value| {
                    if ((byte & m) > 0)
                        byte = if ((m * value) > 0) byte else byte ^ m
                    else
                        byte = if ((m * value) > 0) byte | m else byte;
                },
                Operation.bitor => |value| {
                    byte = byte | (m * value);
                },
                Operation.bitand => |value| {
                    byte = byte & (m * value);
                },
                Operation.bitxor => |value| {
                    byte = byte ^ (m * value);
                }
            }
            self.buffer[i] = byte;
        }
    }

    /// Get the value of a single dot in the buffer.
    pub fn get(self : *Buffer, x : i32, y : i32) u1 {
        if (self.validPosition(x, y)) {
            const _x = @intCast(u16, x);
            const _y = @intCast(u16, y);
            const i = self.index(_x, _y);
            const m = mask(_x, _y);
            return @boolToInt((self.buffer[i] & m) > 0);
        }
        else return 0;
    }

    pub fn clear(self : *Buffer) void {
        std.mem.set(u8, self.buffer, 0);
    }

    /// Calculate total memory cost for a dots buffer.
    /// This calculates the total size of the buffer, including possible allocated space.
    /// It guarantees enough memory is available for any operation.
    pub fn calculateSize(width : u16, height : u16) usize {
        const cols : u16 = @divFloor(@as(u16, width),  2) + @as(u16, if (@mod(@as(u16, width),  2) > 0) 1 else 0);
        const rows : u16 = @divFloor(@as(u16, height), 4) + @as(u16, if (@mod(@as(u16, height), 4) > 0) 1 else 0);
        return cols * rows + @sizeOf(@TypeOf(Buffer));
    }

    /// Bitmask for specifying a specific bit in a cell based on a dot's position.
    fn mask(x : u16, y : u16) u8 {
        // A single cell is 2 dots wide and 4 dots high.
        // This converts an X Y value to a mask for any cell.
        const col = @mod(x, 2);
        const row = @mod(y, 4);
        return @as(u8, 1) << @truncate(u3, row * 2 + col);
    }

    /// Index for specifying a specific cell based on the position of a dot.
    fn index(self : *Buffer, x : u16, y : u16) u16 {
        // A single cell is 2 dots wide and 4 dots high.
        // This converts an X Y value to the index for a specific cell.
        const col = @divFloor(x, 2);
        const row = @divFloor(y, 4);
        return row * self.config.cols + col;
    }

    /// Returns whether a dot exists at a given position.
    fn validPosition(self : *Buffer, x : i32, y : i32) bool {
        return (x < self.config.width and y < self.config.height and x >= 0 and y >= 0);
    }
};

/// A Dots display is can be used to print the buffer in a compact shape.
/// It can either be printed to any position on the console, or output as a string to write as a file.
/// There is no need to touch any of the variables inside this struct.
/// All interaction is meant to be done via the public methods.
pub const Display = struct {
    config : *const Config,
    /// Purpose built FixedBufferStream / Buffer combination.
    output : RepurposableBuffer,

    /// Initializes a Dots display and allocate memory for it's buffers.
    pub fn create(config : *const Config) !Display {
        // Calculate the amount of space required for all dots in the display.
        const cols : u16 = @divFloor(config.width,  2) + @as(u16, if (@mod(config.width,  2) > 0) 1 else 0);
        const rows : u16 = @divFloor(config.height, 4) + @as(u16, if (@mod(config.height, 4) > 0) 1 else 0);
        const output_sizes = calculateOutputSize(cols, rows);
        const output = try RepurposableBuffer.init(output_sizes, config.allocator);

        // Initialize display and clear buffer.
        var display = Display {
            .config = config,
            .output = output,
        };
        return display;
    }

    /// Destroys and frees allocated memory.
    pub fn destroy(display : *Display) void {
        display.output.free();
    }

    /// Returns the buffer represented in unicode braille characters.
    pub fn string(self : *Display, buffer : *Buffer) ![]const u8 {
        if (Config.compare(self.config, buffer.config) == false)
            return error.ConfigMismatch;
        // Makes sure the output buffer is configured correctly.
        try self.output.makePurpose(RepurposableBuffer.Purpose.string);
        self.output.clear();
        var i : u32 = 0;
        while (i < buffer.buffer.len) : (i += 1) {
            // Print character from lookuptable.
            try self.output.write(UnicodeLookup[buffer.buffer[i]]);
            // Create a newline where necessary.
            if (@mod(i + 1, self.config.cols) == 0) {
                try self.output.write("\n");
            }
        }
        return self.output.buffer;
    }

    /// Prints the entire display represented in unicode braille characters.
    pub fn print(self : *Display, buffer : *Buffer, row : i32, col : i32, writer : *std.fs.File.Writer) anyerror!void {
        if (Config.compare(self.config, buffer.config) == false)
            return error.ConfigMismatch;
        try self.output.makePurpose(RepurposableBuffer.Purpose.terminal);
        self.output.clear();
        // Start off with hiding the cursor and moving to the preferred column and row. as a starting position. (Top left)
        try self.output.writefmt(16, "\x1b[?25l\x1b[{d};{d}H", .{row, col});
        
        var i : u32 = 0;
        while (i < buffer.buffer.len) : (i += 1) {
            try self.output.write(UnicodeLookup[buffer.buffer[i]]);
            if (@mod(i + 1, self.config.cols) == 0) {
                // Not newlining, but going back and setting to the next position in the terminal.
                // Or unhiding the cursor as it is the last line set.
                if (i < buffer.buffer.len - 1)
                    try self.output.writefmt(16, "\x1b[{d}D\x1b[1B", .{self.config.cols})
                else
                    try self.output.write("\n\x1b[?25h");
            }
        }
        // Write the entire resulting string.
        // Probably to a terminal. This is done in one go to be efficient.
        _ = try writer.write(self.output.buffer);
    }
    
    /// Calculate total memory cost for a dots display.
    /// This calculates the requirements with the purpose of displaying to the terminal.
    /// This cost is slightly higher than the cost of generating it as a string.
    /// But it guarantees enough memory is available for any operation.
    pub fn calculateSize(width : u16, height : u16) usize {
        const cols : u16 = @divFloor(width,  2) + @as(u16, if (@mod(width,  2) > 0) 1 else 0);
        const rows : u16 = @divFloor(height, 4) + @as(u16, if (@mod(height, 4) > 0) 1 else 0);
        const clen : u16 = switch (cols) {
            0...9 => 1,
            10...99 => 2,
            100...999 => 3,
            1000...9999 => 4,
            else => 5,
        };
        var print_size : u16 = cols * rows * 3 + 16 + (rows - 1) * (7 + clen) + 7;
        return @sizeOf(@TypeOf(Display)) + print_size;
    }

    // Calculates the size required for the unicode output string allocation.
    fn calculateOutputSize(c : u16, r : u16) RepurposableBuffer.Sizes {
        const cols : u16 = c;
        const rows : u16 = r;
        const buffer_size : u16 = cols * rows;
        const string_size : u16 = buffer_size * 3 + rows;

        const clen : u16 = switch (cols) {
            0...9 => 1,
            10...99 => 2,
            100...999 => 3,
            1000...9999 => 4,
            else => 5,
        };

        // Calculates the maximum possible size possible with the current configuration.
        var print_size : u16 = buffer_size * 3 + 16 + (rows - 1) * (7 + clen) + 7;

        var sizes = RepurposableBuffer.Sizes {
            .string = string_size,
            .terminal = print_size,
        };
        return sizes;
    }
};

/// Errors that happen with Dots.
const DotsError = error {
    ConfigMismatch,
};

/// Repurposable Buffer is mix of FixedBufferReader, and a way to resize automatically when necessary. 
const RepurposableBuffer = struct {
    /// The different states in which this structure is used.
    const Purpose = enum {
        unassigned,
        terminal,
        string,
    };
    /// The different sizes for each of the states.
    const Sizes = struct {
        unassigned : usize = 1,
        terminal : usize,
        string : usize
    };

    /// Allocator for the memory handled by this buffer object.
    allocator : *std.mem.Allocator,
    /// Data
    buffer : []u8,
    /// Current state
    purpose : Purpose,
    /// The byte sizes associated with each state.
    sizes : Sizes,
    /// Current position in the data, for writing.
    pos : usize = 0,

    /// Create a repurposable buffer, requires an allocator.
    fn init(sizes : Sizes, allocator : *std.mem.Allocator) !RepurposableBuffer {
        return RepurposableBuffer {
            .purpose = Purpose.unassigned,
            .buffer = try allocator.alloc(u8, 1),
            .sizes = sizes,
            .allocator = allocator
        };
    }

    // Returns the buffer, if purpose is different, reallocates the buffer and resets.
    fn makePurpose(self : *RepurposableBuffer, purpose : Purpose) !void {
        if (self.purpose == Purpose.unassigned or self.purpose != purpose) {
            var new_size = switch (purpose) {
                .unassigned => self.sizes.unassigned,
                .terminal => self.sizes.terminal,
                .string => self.sizes.string,
            };
            std.mem.set(u8, self.buffer, 0);
            self.buffer = try self.allocator.realloc(self.buffer, new_size);
            self.purpose = purpose;
            self.pos = 0;
        }
    }

    /// Clears and resets.
    fn clear(self : *RepurposableBuffer) void {
        std.mem.set(u8, self.buffer, 0);
        self.pos = 0;
    }

    /// Writes to the []u8 buffer.
    fn write(self : *RepurposableBuffer, str : []const u8) !void {
        for (str) |c| {
            self.buffer[self.pos] = c;
            self.pos += 1;
        }
    }

    /// Write a formatted string to the []u8 buffer.
    fn writefmt(self : *RepurposableBuffer, comptime size : usize, comptime fmt : []const u8, args : anytype) !void {
        var newline_string : [size]u8 = [1]u8 {0} ** size; 
        const newline_slice = newline_string[0..];
        try self.write(try std.fmt.bufPrint(newline_slice, fmt, args));
    }

    /// Free the buffer.
    fn free(self : *RepurposableBuffer) void {
        self.allocator.free(self.buffer);
    }
};

/// An abstraction layer for drawing to the screen.
/// Features a normalized -1 to 1 coordinate system.
/// Features line drawing and many shapes.
/// Simply give a display and buffer.
pub const Context = struct {
    /// Buffer associated with this context.
    buffer : *Buffer,
    /// width taken from buffer associated config.
    width : u16,
    /// height taken form buffer associated config.
    height : u16,

    /// Initialize a context and point it to a buffer.
    pub fn init(buffer : *Buffer) !Context {
        return Context {
            .buffer = buffer,
            .width  = buffer.config.width,
            .height = buffer.config.height, 
        };
    }

    /// Point to a different buffer.
    pub fn swap(self : *Context, buffer : *Buffer, ) !void {
        self.buffer = buffer;
        self.width  = buffer.config.width;
        self.height = buffer.config.height;
    }

    /// Set based on normalized -1 to 1 coordinate system.
    pub fn set(self : *Context, x : f32, y : f32, op : Buffer.Operation) void {
        var xi = @floatToInt(i32, (x0 + 1.0) * @intToFloat(f32, self.width - 1) / 2);
        var yi = @floatToInt(i32, (y0 + 1.0) * @intToFloat(f32, self.height - 1) / 2);
        self.buffer.set(xi, yi, op);
    }

    /// Draw a line from point (x0, y0) to (x1, y1)
    /// An essential for all other drawing methods.
    pub fn line(self : *Context, x0 : f32, y0 : f32, x1 : f32, y1 : f32, op : Buffer.Operation) void {
        var x0f = (x0 + 1.0) * @intToFloat(f32, self.width - 1) / 2;
        var y0f = (y0 + 1.0) * @intToFloat(f32, self.height - 1) / 2;
        var x1f = (x1 + 1.0) * @intToFloat(f32, self.width - 1) / 2;
        var y1f = (y1 + 1.0) * @intToFloat(f32, self.height - 1) / 2;
        var dx = x1f - x0f;
        var dy = y1f - y0f;
        var absdx = std.math.fabs(dx);
        var absdy = std.math.fabs(dy);
        var steps = if (absdx > absdy) absdx else absdy;
        var xincr = dx / steps;
        var yincr = dy / steps;
        var i : i32 = 0;
        self.buffer.set(@floatToInt(i32, x0f), @floatToInt(i32, y0f), op);
        while (i < @floatToInt(i32, steps)) {
            self.buffer.set(@floatToInt(i32, x0f), @floatToInt(i32, y0f), op);
            x0f += xincr;
            y0f += yincr;
            i += 1;
        }
    }

    /// Draw a rectangle
    pub fn rect(self : *Context, x0 : f32, y0 : f32, x1 : f32, y1 : f32, op : Buffer.Operation) void {
        self.line(x0, y0, x1, y0, op);
        self.line(x1, y0, x1, y1, op);
        self.line(x1, y1, x0, y1, op);
        self.line(x0, y1, x0, y0, op);
    }

    pub fn circ(self : *Context, x : f32, y : f32, begin : f32, end : f32, radius : f32, segments : i32, op : Buffer.Operation) void {

        var _begin = if (end > begin) end else begin;
        var _end   = if (end > begin) begin else end;

        var incr = (_end - _begin) / @intToFloat(f32, segments);
        var i : i32 = 0;
        while (i < segments) {
            var this_x : f32 = std.math.sin(@intToFloat(f32, i) * incr + _begin) * radius + x;
            var this_y : f32 = std.math.cos(@intToFloat(f32, i) * incr + _begin) * radius + y;
            var next_x : f32 = std.math.sin((@intToFloat(f32, i) + 1) * incr + _begin) * radius + x;
            var next_y : f32 = std.math.cos((@intToFloat(f32, i) + 1) * incr + _begin) * radius + y;
            self.line(this_x, this_y, next_x, next_y, op);
            i += 1;
        }
    }

    pub fn clear(self : *Context) void {
        self.buffer.clear();
    }
};