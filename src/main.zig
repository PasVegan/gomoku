const std = @import("std");
const board = @import("board.zig");

const test_allocator = std.testing.allocator;
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

/// Application memory allocator (arena).
var allocator: std.mem.Allocator = undefined;

/// Variable containing if the bot should stop.
var should_stop = false;

/// Variable for the game board.
var width: u32 = 0;
var height: u32 = 0;
var game_board: board.Board = undefined;

/// Function used to send a message.
fn sendMessage(msg: []const u8, writer: std.io.AnyWriter) !void {
    try writer.writeAll(msg);
    return writer.writeAll("\n");
}

/// Function used to send a comptime message.
fn sendMessageComptime(comptime msg: []const u8, writer: std.io.AnyWriter) !void {
    return writer.writeAll(msg ++ "\n");
}

/// Function used to send a raw message.
fn sendMessageRaw(msg: []const u8, writer: std.io.AnyWriter) !void {
    return writer.writeAll(msg);
}

/// Structure representing the log type.
const LogType = enum {
    UNKNOWN,
    ERROR,
    MESSAGE,
    DEBUG,
};

/// Function used to send a format logging message message.
fn sendLogF(comptime log_type: LogType, comptime fmt: []const u8, args: anytype, writer: std.io.AnyWriter)
!void {
    const out = try std.fmt.allocPrint(allocator, @tagName(log_type) ++ " " ++ fmt ++ "\n", args);
    defer allocator.free(out);
    return sendMessageRaw(out, writer);
}

/// Function used to send a basic logging message (calculated at compile).
fn sendLogC(comptime log_type: LogType, comptime msg: []const u8, writer: std.io.AnyWriter) !void {
    return sendMessageComptime(@tagName(log_type) ++ " " ++ msg, writer);
}

/// Function used to handle the about command.
/// - Behavior:
///     - Sending basic informations about the bot.
fn handleAbout(_: []const u8, writer: std.io.AnyWriter) !void {
    const bot_name = "TNBC";
    const about_answer = "name=\"" ++ bot_name ++ "\", version=\"0.1\"";

    return sendMessageComptime(about_answer, writer);
}

/// Function representing the start command, allocate the board.
fn handleStart(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len < 7 or msg[5] != ' ') { // at least "START " + 1 digit
        try sendLogC(.ERROR, "wrong start command format", writer);
        return;
    }
    const size = std.fmt.parseUnsigned(u32, msg[6..], 10) catch |err| {
        try sendLogF(.ERROR, "error during the parsing of the size: {}", .{err}, writer);
        return;
    };
    if (size * size > 10000 or size < 5) {
        try sendLogC(.ERROR, "invalid size", writer);
        return;
    }
    width = size;
    height = size;
    game_board = board.Board.init(allocator, allocator, size, size) catch |err| {
        try sendLogF(.ERROR, "error during the initialization of the board: {}", .{err}, writer);
        return;
    };
    try sendMessageComptime("OK", writer);
}

fn handleEnd(_: []const u8, _: std.io.AnyWriter) !void {
    should_stop = true;
}

fn handleInfo(_: []const u8, _: std.io.AnyWriter) !void {
    // Handle infos
}

fn handleBegin(_: []const u8, _: std.io.AnyWriter) !void {
    // Handle begin
}

fn handleTurn(msg: []const u8, _: std.io.AnyWriter) !void {
    // Handle turn
    _ = msg;
}

fn handleBoard(_: []const u8, _: std.io.AnyWriter) !void {
    // Handle board
}

/// Structure representing the command mapping.
/// - Attributes:
///     - cmd: The command.
///     - func: The associated function to call on command.
const CommandMapping = struct {
    cmd: []const u8,
    func: *const fn ([]const u8, std.io.AnyWriter) anyerror!void,
};

/// Map of pointer on function.
const commandMappings: []const CommandMapping = &[_]CommandMapping{
    .{ .cmd = "ABOUT", .func = handleAbout },
    .{ .cmd = "START", .func = handleStart },
    .{ .cmd = "END", .func = handleEnd },
    .{ .cmd = "INFO", .func = handleInfo },
    .{ .cmd = "BEGIN", .func = handleBegin },
    .{ .cmd = "TURN", .func = handleTurn },
    .{ .cmd = "BOARD", .func = handleBoard },
};

/// Function used to handle commands.
/// - Parameters:
///     - cmd: A command to executes.
fn handleCommand(cmd: []const u8, writer: std.io.AnyWriter) !void {
    for (commandMappings) |mapping| {
        if (std.ascii.startsWithIgnoreCase(cmd, mapping.cmd)) {
            return @call(.auto, mapping.func, .{cmd, writer});
        }
    }
    return sendLogC(.UNKNOWN, "command is not implemented", writer);
}

/// Function used to read a line into a buffer.
/// - Parameters:
///     - input_reader: The reader to read from.
///     - read_buffer: The buffer to write into.
///     - writer: The writer used for logging message.
fn readLineIntoBuffer(
    input_reader: std.io.AnyReader,
    read_buffer: *std.BoundedArray(u8, 256),
    writer: std.io.AnyWriter
) !void {
    read_buffer.len = 0;
    input_reader.streamUntilDelimiter(read_buffer.writer(), '\n', 256) catch |err| {
        try sendLogF(.ERROR, "error during the stream capture: {}", .{err}, writer);
        return;
    };
    // EOF handling
    if (read_buffer.len == 0)
        return;
    if (read_buffer.buffer[read_buffer.len - 1] == '\r') { // remove the \r if there is one
        read_buffer.len -= 1;
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    allocator = arena.allocator();

    var read_buffer = try std.BoundedArray(u8, 256).init(0);

    while (!should_stop) {
        try readLineIntoBuffer(stdin.any(), &read_buffer, stdout.any());
        try handleCommand(read_buffer.slice(), stdout.any());
    }
}

// This is a test that will run all the tests in all the other files in the project.
test {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDecls(board);
}

// Test message sending functions
test "sendMessage basic functionality" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try sendMessage("test", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "test\n"));
}

test "sendMessageComptime basic functionality" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try sendMessageComptime("test", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "test\n"));
}

test "sendLogF functionality" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try sendLogF(.ERROR, "test {s}", .{"message"}, list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR test message\n"));
}

// Test command handlers
test "handleAbout command" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleAbout("", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "name=\"TNBC\", version=\"0.1\"\n"));
}

test "handleStart command valid input" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleStart("START 10", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "OK\n"));
    try std.testing.expect(width == 10);
    try std.testing.expect(height == 10);
    game_board.deinit(allocator);
}

test "handleStart command invalid input" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleStart("START", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR wrong start command format\n"));
}

test "handleStart command too large size" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleStart("START 200", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR invalid size\n"));
}

test "handleStart command too small" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleStart("START 2", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR invalid size\n"));
}

test "handleStart command invalid number" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleStart("START TNBC", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the parsing of the size: error.InvalidCharacter\n"));
}

test "handleEnd command" {
    should_stop = false;
    try handleEnd("", undefined);
    try std.testing.expect(should_stop == true);
}

test "handleCommand unknown command" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handleCommand("UNKNOWN", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "UNKNOWN command is not implemented\n"));
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

    const block = "test\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list.writer().any());
    try std.testing.expectEqualStrings("test", buffer.slice());
}

test "readLineIntoBuffer - empty line" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    const block = "\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list.writer().any());
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
}

test "readLineIntoBuffer - line too long" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    const block = "a" ** 256 ++ "\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the stream capture: error.StreamTooLong\n"));
}
