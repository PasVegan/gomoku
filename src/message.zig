const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

const Allocator = std.mem.Allocator;
const WriteError = std.posix.WriteError;

/// Application memory allocator (arena).
var allocator: std.mem.Allocator = undefined;

/// Function used to send a message.
pub fn sendMessage(msg: []const u8, writer: std.io.AnyWriter) !void {
    try writer.writeAll(msg);
    return writer.writeAll("\n");
}

/// Function used to send a comptime message.
pub fn sendMessageComptime(comptime msg: []const u8, writer: std.io.AnyWriter) !void {
    return writer.writeAll(msg ++ "\n");
}

/// Function used to send a raw message.
pub fn sendMessageRaw(msg: []const u8, writer: std.io.AnyWriter) !void {
    return writer.writeAll(msg);
}

/// Structure representing the log type.
pub const LogType = enum {
    UNKNOWN,
    ERROR,
    MESSAGE,
    DEBUG,
};

/// Function used to send a format logging message message.
pub fn sendLogF(
    comptime log_type: LogType,
    comptime fmt: []const u8,
    args: anytype,
    writer: std.io.AnyWriter
) !void {
    const out = try std.fmt.allocPrint(allocator, @tagName(log_type) ++ " " ++ fmt ++ "\n", args);
    defer allocator.free(out);
    return sendMessageRaw(out, writer);
}

/// Function used to send a basic logging message (calculated at compile).
pub fn sendLogC(
    comptime log_type: LogType,
    comptime msg: []const u8,
    writer: std.io.AnyWriter
) !void {
    return sendMessageComptime(@tagName(log_type) ++ " " ++ msg, writer);
}

/// Initializes the allocator for message.
pub fn init(allocat: std.mem.Allocator) void {
    allocator = allocat;
}
