const std = @import("std");
const board = @import("board.zig");
const message = @import("message.zig");
const game = @import("game.zig");
const cmd = @import("commands/cmd.zig");
const io = @import("io.zig");
const build_options = @import("build_options");

const test_allocator = std.testing.allocator;
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

var prng = std.Random.DefaultPrng.init(0);
pub var random = prng.random();

/// Application memory allocator (arena).
pub var allocator: std.mem.Allocator = undefined;

/// Variable containing if the bot should stop.
pub var should_stop = false;

/// Variable for the game board.
pub var width: u32 = 0;
pub var height: u32 = 0;

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
    // Mendatory commands.
    .{ .cmd = "ABOUT", .func = cmd.about.handle },
    .{ .cmd = "START", .func = cmd.start.handle },
    .{ .cmd = "END", .func = cmd.end.handle },
    .{ .cmd = "INFO", .func = cmd.info.handle },
    .{ .cmd = "BEGIN", .func = cmd.begin.handle },
    .{ .cmd = "TURN", .func = cmd.turn.handle },
    .{ .cmd = "BOARD", .func = cmd.board.handle },
    // Optional commands.
    .{ .cmd = "RECSTART", .func = cmd.recstart.handle },
    .{ .cmd = "RESTART", .func = cmd.restart.handle },
};

/// Function used to handle commands.
/// - Parameters:
///     - cmd: A command to executes.
fn handleCommand(command: []const u8, writer: std.io.AnyWriter) !void {
    for (commandMappings) |mapping| {
        if (std.ascii.startsWithIgnoreCase(command, mapping.cmd)) {
            return @call(.auto, mapping.func, .{command, writer});
        }
    }
    return message.sendLogC(.UNKNOWN, "command is not implemented", writer);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    allocator = arena.allocator();

    message.init(allocator);

    game.gameSettings.allocator = allocator;
    defer game.gameSettings.deinit();

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    random = real_prng.random();

    // Initialize the board.
    board.game_board = board.Board.init(
        allocator,
        height, width
    ) catch |err| { return err; };
    defer board.game_board.deinit(allocator);

    var read_buffer = try std.BoundedArray(u8, 256).init(0);

    if (build_options.GUI) {
        const gui = @import("gui.zig");
        try gui.run_gui();
    } else {
        while (!should_stop) {
            try io.readLineIntoBuffer(stdin.any(), &read_buffer, stdout.any());
            try handleCommand(read_buffer.slice(), stdout.any());
        }
    }
}

// This is a test that will run all the tests in all the other files in the project.
test {
    std.testing.refAllDecls(@This());
    should_stop = true;
    try main();
}

test "handleCommand unknown command" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleCommand("UNKNOWN", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "UNKNOWN command is not implemented\n"));
}
