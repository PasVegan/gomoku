const std = @import("std");
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

const WriteError = std.posix.WriteError;
const ReadError = std.posix.ReadError;

const Error = Allocator.Error || WriteError || ReadError;

/// Variable containing if the bot shhould stop.
var should_stop = false;

/// # Function used to send a message.
fn sendMessage(msg: []const u8) WriteError!void {
    try stdout.writeAll(msg);
    return stdout.writeAll("\n");
}

/// # Function used to send a comptime message.
fn sendMessageComptime(comptime msg: []const u8) WriteError!void {
    return stdout.writeAll(msg ++ "\n");
}

/// # Function used to send a raw message.
fn sendMessageRaw(msg: []const u8) WriteError!void {
    return stdout.writeAll(msg);
}

/// # Structure representing the log type.
const LogType = enum {
    UNKNOWN,
    ERROR,
    MESSAGE,
    DEBUG,
};

/// # Function used to send a format logging message message.
fn sendLogF(comptime log_type: LogType, comptime fmt: []const u8, args: anytype) (WriteError || Allocator.Error)!void {
    const out = try std.fmt.allocPrint(std.heap.page_allocator, @tagName(log_type) ++ " " ++ fmt ++ "\n", args);
    defer std.heap.page_allocator.free(out);
    return sendMessageRaw(out);
}

/// # Function used to send a basic logging message (calculated at compile).
fn sendLogC(comptime log_type: LogType, comptime msg: []const u8) WriteError!void {
    return sendMessageComptime(@tagName(log_type) ++ " " ++ msg);
}

/// # Function used to handle the about command.
/// - Behavior:
///     - Sending basic informations about the bot.
fn handleAbout(_: []const u8) WriteError!void {
    const bot_name = "TNBC";
    const about_answer = "name=\"" ++ bot_name ++ "\", version=\"0.1\"";

    return sendMessageComptime(about_answer);
}

fn handleStart(_: []const u8) !void {
    // Handle start
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

/// # Structure representing the command mapping.
/// - Attributes:
///     - cmd: The command.
///     - func: The associated function to call on command.
const CommandMapping = struct {
    cmd: []const u8,
    func: *const fn ([]const u8) Error!void,
};

/// # Map of pointer on function.
const commandMappings: []const CommandMapping = &[_]CommandMapping{
    .{ .cmd = "ABOUT", .func = handleAbout },
    .{ .cmd = "START", .func = handleStart },
    .{ .cmd = "END", .func = handleEnd },
    .{ .cmd = "INFO", .func = handleInfo },
    .{ .cmd = "BEGIN", .func = handleBegin },
    .{ .cmd = "TURN", .func = handleTurn },
    .{ .cmd = "BOARD", .func = handleBoard },
};

/// # Function used to handle commands.
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
    var read_buffer = try std.BoundedArray(u8, 256).init(0);
    while (!should_stop) {
        stdin.streamUntilDelimiter(read_buffer.writer(), '\n', 256)
        catch |err| {
            try sendLogF(.ERROR, "error during the stream capture: {}\n",
                .{err});
            break;
        };
        // EOF handling
        if (read_buffer.len == 0)
            break;
        try handleCommand(&read_buffer.buffer);
    }
}
