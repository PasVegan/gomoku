const std = @import("std");
const board = @import("board.zig");
const message = @import("message.zig");
const game = @import("game.zig");
const cmd = @import("commands/cmd.zig");
const io = @import("io.zig");

const test_allocator = std.testing.allocator;
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

var prng = std.rand.DefaultPrng.init(0);
pub const random = prng.random();

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
    .{ .cmd = "ABOUT", .func = cmd.about.handle },
    .{ .cmd = "START", .func = cmd.start.handle },
    .{ .cmd = "END", .func = cmd.end.handle },
    .{ .cmd = "INFO", .func = cmd.info.handle },
    .{ .cmd = "BEGIN", .func = cmd.begin.handle },
    .{ .cmd = "TURN", .func = cmd.turn.handle },
    .{ .cmd = "BOARD", .func = cmd.board.handle },
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

    // Initialize the board.
    board.game_board = board.Board.init(
        allocator,
        allocator,
        height, width
    ) catch |err| { return err; };
    defer board.game_board.deinit(allocator);

    var read_buffer = try std.BoundedArray(u8, 256).init(0);

    while (!should_stop) {
        try io.readLineIntoBuffer(stdin.any(), &read_buffer, stdout.any());
        try handleCommand(read_buffer.slice(), stdout.any());
    }
}

// This is a test that will run all the tests in all the other files in the project.
test {
    std.testing.refAllDecls(@This());
}

test "handleCommand unknown command" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

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
    message.init(allocator);

    const block = "test\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try io.readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list
    .writer().any());
    try std.testing.expectEqualStrings("test", buffer.slice());
}

test "readLineIntoBuffer - empty line" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    const block = "\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try io.readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list
    .writer().any());
    try std.testing.expectEqual(@as(usize, 0), buffer.len);
}

test "readLineIntoBuffer - line too long" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    const block = "a" ** 256 ++ "\n";
    var test_buf_reader = std.io.BufferedReader(block.len, TestReader){
        .unbuffered_reader = TestReader.init(block, 2),
    };

    var buffer = try std.BoundedArray(u8, 256).init(0);
    try io.readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list
    .writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the stream capture: error.StreamTooLong\n"));
}
