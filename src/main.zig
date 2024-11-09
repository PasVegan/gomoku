const std = @import("std");
const board = @import("board.zig");


const WriteError = std.posix.WriteError;
const ReadError = std.posix.ReadError;
const AllocationError = std.mem.Allocator.Error;
const Error = AllocationError || WriteError || ReadError;


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
fn sendMessage(msg: []const u8) WriteError!void {
    try stdout.writeAll(msg);
    return stdout.writeAll("\n");
}

/// Function used to send a comptime message.
fn sendMessageComptime(comptime msg: []const u8) WriteError!void {
    return stdout.writeAll(msg ++ "\n");
}

/// Function used to send a raw message.
fn sendMessageRaw(msg: []const u8) WriteError!void {
    return stdout.writeAll(msg);
}

/// Structure representing the log type.
const LogType = enum {
    UNKNOWN,
    ERROR,
    MESSAGE,
    DEBUG,
};

/// Function used to send a format logging message message.
fn sendLogF(comptime log_type: LogType, comptime fmt: []const u8, args: anytype) (WriteError || AllocationError)!void {
    const out = try std.fmt.allocPrint(std.heap.page_allocator, @tagName(log_type) ++ " " ++ fmt ++ "\n", args);
    defer std.heap.page_allocator.free(out);
    return sendMessageRaw(out);
}

/// Function used to send a basic logging message (calculated at compile).
fn sendLogC(comptime log_type: LogType, comptime msg: []const u8) WriteError!void {
    return sendMessageComptime(@tagName(log_type) ++ " " ++ msg);
}

/// Function used to handle the about command.
/// - Behavior:
///     - Sending basic informations about the bot.
fn handleAbout(_: []const u8) WriteError!void {
    const bot_name = "TNBC";
    const about_answer = "name=\"" ++ bot_name ++ "\", version=\"0.1\"";

    return sendMessageComptime(about_answer);
}

/// Function representing the start command, allocate the board.
fn handleStart(msg: []const u8) !void {
    if (msg.len < 7 or msg[5] != ' ') { // at least "START " + 1 digit
        try sendLogC(.ERROR, "wrong start command format");
        return;
    }
    const size = std.fmt.parseUnsigned(u32, msg[6..], 10) catch |err| {
        try sendLogF(.ERROR, "error during the parsing of the size: {}\n", .{err});
        return;
    };
    if (size * size > 10000) {
        try sendLogC(.ERROR, "size is too big");
        return;
    }
    width = size;
    height = size;
    game_board = board.Board.init(allocator, allocator, size, size) catch |err| {
        try sendLogF(.ERROR, "error during the initialization of the board: {}", .{err});
        return;
    };
    try sendMessageComptime("OK");
}

fn handleEnd(_: []const u8) !void {
    should_stop = true;
}

fn handleInfo(msg: []const u8) !void {
    // Handle infos
    _ = msg;
}

fn handleBegin(_: []const u8) !void {
    // Handle begin
}

fn handleTurn(msg: []const u8) !void {
    // Handle turn
    _ = msg;
}

fn handleBoard(_: []const u8) !void {
    // Handle board
}

/// Structure representing the command mapping.
/// - Attributes:
///     - cmd: The command.
///     - func: The associated function to call on command.
const CommandMapping = struct {
    cmd: []const u8,
    func: *const fn ([]const u8) Error!void,
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
fn handleCommand(cmd: []const u8) !void {
    for (commandMappings) |mapping| {
        if (std.ascii.startsWithIgnoreCase(cmd, mapping.cmd)) {
            return @call(.auto, mapping.func, .{cmd});
        }
    }
    return sendLogC(.UNKNOWN, "command is not implemented");
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    allocator = arena.allocator();

    var read_buffer = try std.BoundedArray(u8, 256).init(0);

    while (!should_stop) {
        stdin.streamUntilDelimiter(read_buffer.writer(), '\n', 256) catch |err| {
            try sendLogF(.ERROR, "error during the stream capture: {}\n", .{err});
            break;
        };
        // EOF handling
        if (read_buffer.len == 0)
            break;
        if (read_buffer.buffer[read_buffer.len - 1] == '\r') { // remove the \r if there is one
            read_buffer.len -= 1;
        }
        try handleCommand(read_buffer.slice());
        // Reset the buffer
        read_buffer.len = 0;
    }
}

// This is a test that will run all the tests in all the other files in the project.
test {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDecls(board);
}
