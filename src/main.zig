const std = @import("std");
const Allocator = std.mem.Allocator;

const allocator = std.heap.c_allocator;

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

const WriteError = std.posix.WriteError;
const ReadError = std.posix.ReadError;

const Error = Allocator.Error || WriteError || ReadError;

/// Variable containing if the bot shhould stop.
var should_stop = false;

/// # Function used to send a message.
fn send_message(msg: []const u8) WriteError!void {
    try stdout.writeAll(msg);
    return stdout.writeAll("\n");
}

/// # Function used to send a comptime message.
fn send_message_comptime(comptime msg: []const u8) WriteError!void {
    return stdout.writeAll(msg ++ "\n");
}

/// # Function used to send a raw message.
fn send_message_raw(msg: []const u8) WriteError!void {
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
fn send_log_f(comptime log_type: LogType, comptime fmt: []const u8, args: anytype) (WriteError || Allocator.Error)!void {
    const out = try std.fmt.allocPrint(allocator, @tagName(log_type) ++ " " ++ fmt ++ "\n", args);
    defer allocator.free(out);
    return send_message_raw(out);
}

/// # Function used to send a basic logging message (calculated at compile).
fn send_log_c(comptime log_type: LogType, comptime msg: []const u8) WriteError!void {
    return send_message_comptime(@tagName(log_type) ++ " " ++ msg);
}

/// # Function used to handle the about command.
/// - Behavior:
///     - Sending basic informations about the bot.
fn handle_about(_: []const u8) WriteError!void {
    const bot_name = "zig_template";
    const about_answer = "name=\"" ++ bot_name ++ "\", version=\"0.42\"";

    return send_message_comptime(about_answer);
}

fn handle_start(_: []const u8) !void {
    // Handle start
}

fn handle_end(_: []const u8) !void {
    should_stop = true;
}

fn handle_info(msg: []const u8) !void {
    // Handle infos
    _ = msg;
}

fn handle_begin(_: []const u8) !void {
    // Handle begin
}

fn handle_turn(msg: []const u8) !void {
    // Handle turn
    _ = msg;
}

fn handle_board(_: []const u8) !void {
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
const command_mappings: []const CommandMapping = &[_]CommandMapping{
    .{ .cmd = "ABOUT", .func = handle_about },
    .{ .cmd = "START", .func = handle_start },
    .{ .cmd = "END", .func = handle_end },
    .{ .cmd = "INFO", .func = handle_info },
    .{ .cmd = "BEGIN", .func = handle_begin },
    .{ .cmd = "TURN", .func = handle_turn },
    .{ .cmd = "BOARD", .func = handle_board },
};

/// # Function used to handle comments.
/// - Parameters:
///     - cmd: A command to executes.
fn handle_command(cmd: []const u8) !void {
    for (command_mappings) |mapping| {
        if (std.ascii.startsWithIgnoreCase(cmd, mapping.cmd)) {
            return @call(.auto, mapping.func, .{cmd});
        }
    }
    return send_log_c(.UNKNOWN, "command is not implemented");
}

pub fn main() !void {
    var read_buffer = try std.BoundedArray(u8, 256).init(0);
    while (!should_stop) {
        stdin.streamUntilDelimiter(read_buffer.writer(), '\n', 256)
        catch |err| {
            std.debug.print("Error during the stream capture: {}\n", .{err});
            break;
        };
        // EOF handling
        if (read_buffer.len == 0)
            break;
        try handle_command(&read_buffer.buffer);
    }
}
