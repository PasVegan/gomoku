const std = @import("std");
const board = @import("board.zig");
const message = @import("message.zig");
const game = @import("game.zig");

const test_allocator = std.testing.allocator;
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

var prng = std.rand.DefaultPrng.init(0);
const random = prng.random();

/// Application memory allocator (arena).
var allocator: std.mem.Allocator = undefined;

/// Variable containing if the bot should stop.
var should_stop = false;

/// Variable for the game board.
var width: u32 = 0;
var height: u32 = 0;
var game_board: board.Board = undefined;

/// Function used to handle the about command.
/// - Behavior:
///     - Sending basic informations about the bot.
fn handleAbout(_: []const u8, writer: std.io.AnyWriter) !void {
    const bot_name = "TNBC";
    const about_answer = "name=\"" ++ bot_name ++ "\", version=\"0.1\"";

    return message.sendMessageComptime(about_answer, writer);
}

/// Function representing the start command, allocate the board.
fn handleStart(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len < 7 or msg[5] != ' ') { // at least "START " + 1 digit
        try message.sendLogC(.ERROR, "wrong START command format", writer);
        return;
    }
    const size = std.fmt.parseUnsigned(u32, msg[6..], 10) catch |err| {
        try message.sendLogF(.ERROR, "error during the parsing of the size: {}", .{err}, writer);
        return;
    };
    if (size * size > 10000 or size < 5) {
        try message.sendLogC(.ERROR, "invalid size", writer);
        return;
    }
    width = size;
    height = size;
    game_board = board.Board.init(allocator, allocator, size, size) catch |err| {
        try message.sendLogF(.ERROR, "error during the initialization of the board: {}", .{err}, writer);
        return;
    };
    try message.sendMessageComptime("OK", writer);
}

fn handleEnd(_: []const u8, _: std.io.AnyWriter) !void {
    should_stop = true;
}

fn handleInfo(msg: []const u8, writer: std.io.AnyWriter) !void {
    // Skip "INFO ".
    if (msg.len <= 5) {
        // Ignore it, it is probably not important. (Protocol)
        return;
    }
    // Call the handleInfoCommand removing the "INFO " bytes.
    return game.handleInfoCommand(msg[5..], writer);
}

fn handleBegin(_: []const u8, _: std.io.AnyWriter) !void {
    // Handle begin
}

fn handleTurn(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len < 8 or msg[4] != ' ') { // at least "TURN 5,5" for example
        try message.sendLogC(.ERROR, "wrong TURN command format", writer);
        return;
    }
    const comma_pos = std.mem.indexOf(u8, msg, ",");
    if (comma_pos == null) {
        try message.sendLogC(.ERROR, "wrong TURN command format1", writer);
        return;
    }
    const x = std.fmt.parseUnsigned(u32, msg[5..comma_pos.?], 10) catch |err| {
        try message.sendLogF(.ERROR, "error during the parsing of the x coordinate: {}, val:{s}",
            .{err, msg[5..comma_pos.?]}, writer);
        return;
    };
    const y = std.fmt.parseUnsigned(u32, msg[comma_pos.? + 1..], 10) catch |err| {
        try message.sendLogF(.ERROR, "error during the parsing of the y coordinate: {}, val:{s}",
            .{err, msg[comma_pos.? + 1..]}, writer);
        return;
    };
    if (game_board.isCoordinatesOutside(x, y)) {
        try message.sendLogC(.ERROR, "coordinates are outside the board", writer);
        return;
    }
    if (game_board.getCellByCoordinates(x, y) != board.Cell.empty) {
        try message.sendLogC(.ERROR, "cell is not empty", writer);
        return;
    }
    try game_board.setCellByCoordinates(x, y, board.Cell.player2);

    const empty_cell = board.findRandomValidCell(game_board, random) catch |err| {
        try message.sendLogF(.ERROR, "error during the search of a random cell: {}", .{err}, writer);
        return;
    };
    try game_board.setCellByCoordinates(empty_cell.x, empty_cell.y, board.Cell.player1);

    try message.sendMessage(try std.fmt.allocPrint(allocator, "{d},{d}", .{empty_cell.x, empty_cell.y}), writer);
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
    return message.sendLogC(.UNKNOWN, "command is not implemented", writer);
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    allocator = arena.allocator();
    message.init(allocator);
    defer game.gameSettings.deinit();

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
    message.init(allocator);

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
    message.init(allocator);

    try handleStart("START", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR wrong START command format\n"));
}

test "handleStart command too large size" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleStart("START 200", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR invalid size\n"));
}

test "handleStart command too small" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleStart("START 2", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR invalid size\n"));
}

test "handleStart command invalid number" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleStart("START TNBC", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the parsing of the size: error.InvalidCharacter\n"));
}

test "handleInfo command invalid input" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleInfo("INFO", list.writer().any());
    try std.testing.expect(
        std.mem.eql(u8, list.items, "")
    );
}

test "handleInfo command valid input" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleInfo("INFO timeout_turn 5000", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, ""));
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
    message.init(allocator);

    try handleCommand("UNKNOWN", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "UNKNOWN command is not implemented\n"));
}

test "handleTurn command valid input" {
    allocator = std.heap.page_allocator; // testing allocator detect leak but can't find it wtf ???
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    width = 20; height = 20;
    game_board = try board.Board.init(allocator, allocator, 20, 20);
    defer game_board.deinit(allocator);

    try handleTurn("TURN 5,5", list.writer().any());
    // Check if we received the coordinates
    const comma_pos = std.mem.indexOf(u8, list.items, ",");
    try std.testing.expect(comma_pos != null);
    try std.testing.expect(@TypeOf(try std.fmt.parseUnsigned(u32, list.items[0..comma_pos.?], 10)) == u32);
    try std.testing.expect(@TypeOf(try std.fmt.parseUnsigned(u32, list.items[comma_pos.? + 1..list.items.len - 1], 10)) == u32);
    try std.testing.expect(game_board.getCellByCoordinates(5, 5) == board.Cell.player2);
}

test "handleTurn command invalid format - too short" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleTurn("TURN", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR wrong TURN command format\n"));
}

test "handleTurn command invalid format - no space" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleTurn("TURN5,5", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR wrong TURN command format\n"));
}

test "handleTurn command missing comma" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleTurn("TURN 555", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR wrong TURN command format1\n"));
}

test "handleTurn command invalid x coordinate" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleTurn("TURN a,5", list.writer().any());
    try std.testing.expect(std.mem.startsWith(u8, list.items, "ERROR error during the parsing of the x coordinate"));
}

test "handleTurn command invalid y coordinate" {
    allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    try handleTurn("TURN 5,b", list.writer().any());
    try std.testing.expect(std.mem.startsWith(u8, list.items, "ERROR error during the parsing of the y coordinate"));
}

test "handleTurn command coordinates out of bounds" {
    allocator = std.heap.page_allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    width = 20; height = 20;
    game_board = try board.Board.init(allocator, allocator, 20, 20);
    defer game_board.deinit(allocator);

    try handleTurn("TURN 25,25", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR coordinates are outside the board\n"));
}

test "handleTurn command cell already taken" {
    allocator = std.heap.page_allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    width = 20; height = 20;
    game_board = try board.Board.init(allocator, allocator, 20, 20);
    defer game_board.deinit(allocator);

    // First place a piece
    try handleTurn("TURN 5,5", list.writer().any());
    list.clearRetainingCapacity();

    // Try to place another piece in the same spot
    try handleTurn("TURN 5,5", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR cell is not empty\n"));
}

test "handleTurn command no empty cells" {
    allocator = std.heap.page_allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(allocator);

    width = 5; height = 5;
    game_board = try board.Board.init(allocator, allocator, 5, 5);
    defer game_board.deinit(allocator);

    // Fill the board
    var x: u32 = 0;
    var y: u32 = 0;
    outer: while (y < height) {
        while (x < width) {
            try game_board.setCellByCoordinates(x, y, board.Cell.player1);
            x += 1;
            if (y == height - 1 and x == width - 1) {
                break :outer;
            }
        }
        x = 0;
        y += 1;
    }

    // Fill the last cell
    try handleTurn("TURN 4,4", list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the search of a random cell: error.NoEmptyCells\n"));
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
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list.writer().any());
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
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list.writer().any());
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
    try readLineIntoBuffer(test_buf_reader.reader().any(), &buffer, list.writer().any());
    try std.testing.expect(std.mem.eql(u8, list.items, "ERROR error during the stream capture: error.StreamTooLong\n"));
}
