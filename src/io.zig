const std = @import("std");
const message = @import("message.zig");

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
