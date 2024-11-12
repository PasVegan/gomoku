const std = @import("std");
const message = @import("message.zig");
const main = @import("main.zig");

/// Function used to read a line into a buffer.
/// - Parameters:
///     - input_reader: The reader to read from.
///     - read_buffer: The buffer to write into.
///     - writer: The writer used for logging message.
pub fn readLineIntoBuffer(
    input_reader: std.io.AnyReader,
    read_buffer: *std.BoundedArray(u8, 256),
    writer: std.io.AnyWriter
) !void {
    read_buffer.len = 0;
    input_reader.streamUntilDelimiter(read_buffer.writer(), '\n', 256) catch |err| {
        try message.sendLogF(.ERROR, "error during the stream capture: {}", .{err}, writer);
        return;
    };
    // EOF handling
    if (read_buffer.len == 0)
        return;
    if (read_buffer.buffer[read_buffer.len - 1] == '\r') { // remove the \r if there is one
        read_buffer.len -= 1;
    }
}

const TestReader = struct {
    block: []const u8,
    reads_allowed: usize,
    curr_read: usize,

    pub const Error = error{NoError};
    const Self = @This();
    const Reader = std.io.Reader(*Self, Error, read);

    fn init(block: []const u8, reads_allowed: usize) Self {
        return Self{
            .block = block,
            .reads_allowed = reads_allowed,
            .curr_read = 0,
        };
    }

    pub fn read(self: *Self, dest: []u8) Error!usize {
        if (self.curr_read >= self.reads_allowed) return 0;
        @memcpy(dest[0..self.block.len], self.block);
        self.curr_read += 1;
        return self.block.len;
    }

    fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

test "readLineIntoBuffer - successful read" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    const block = "test\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list
    .writer().any());
    try std.testing.expectEqualStrings("test", buffer.slice());
}

test "readLineIntoBuffer - empty line" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    const block = "\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list
    .writer().any());
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
}

test "readLineIntoBuffer - line too long" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    const block = "a" ** 256 ++ "\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list
    .writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the stream capture: error.StreamTooLong\n"));
}
