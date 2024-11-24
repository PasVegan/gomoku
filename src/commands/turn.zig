const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");
const ai = @import("../ai.zig");
const game = @import("../game.zig");
const MCTS = @import("../mcts.zig").MCTS;

// Number of iteration for MCTS.
const MAX_MCTS_ITERATIONS = 10000;

// Error set
pub const PlayError = error {
    OUTSIDE,
    OCCUPIED,
};

const AIMapping = *const fn () ai.Threat;

const AIMap: []const AIMapping = &[_]AIMapping{
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
    ai.getBotMove5,
    ai.getBotMove6,
    ai.getBotMove7,
    ai.getBotMove8,
    ai.getBotMove9,
    ai.getBotMove10,
    ai.getBotMove11,
    ai.getBotMove12,
    ai.getBotMove13,
    ai.getBotMove14,
    ai.getBotMove15,
    ai.getBotMove16,
    ai.getBotMove17,
    ai.getBotMove18,
    ai.getBotMove19,
    ai.getBotMove20,
};

pub fn setEnnemyStone(x: u32, y: u32) PlayError!void {
    if (board.game_board.isCoordinatesOutside(x, y)) {
        return PlayError.OUTSIDE;
    }
    if (board.game_board.getCellByCoordinates(x, y) != board.Cell.empty) {
        return PlayError.OCCUPIED;
    }
    board.game_board.setCellByCoordinates(x, y, board.Cell.opponent);
}

pub fn AIPlay() [2]u16 {
    const empty_cell = @call(.auto, AIMap[board.game_board.width], .{});
    board.game_board.setCellByCoordinates(empty_cell.col, empty_cell.row, board.Cell.own);
    return .{empty_cell.col, empty_cell.row};
}

pub fn AIPlayMCTS() ![2]u16 {
    // Initialize MCTS with RAVE.
    var mcts = try MCTS.init(&game.gameSettings, board.game_board, main.allocator);

    // Perform MCTS search.
    try mcts.performMCTSSearch(MAX_MCTS_ITERATIONS);

    // Select the best move.
    const best_child = try mcts.selectBestChild();
    const ai_move = best_child.coordinates;
    mcts.deinit();
    board.game_board.setCellByCoordinates(ai_move.x, ai_move.y, .own);

    return .{
        @as(u16, @intCast(ai_move.x)),
        @as(u16, @intCast(ai_move.y))
    };
}

pub fn handle(msg: []const u8, writer: std.io.AnyWriter) !void {
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

    setEnnemyStone(x, y) catch |err| {
        switch (err) {
            PlayError.OUTSIDE => try message.sendLogC(.ERROR, "coordinates are outside the board", writer),
            PlayError.OCCUPIED => try message.sendLogC(.ERROR, "cell is not empty", writer),
        }
        return;
    };

    const ai_move = AIPlay();

    // const ai_move = try AIPlayMCTS();

    try message.sendMessageF("{d},{d}", .{ai_move[0], ai_move[1]}, writer);
}

test "handleTurn command valid input" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    main.width = 5; main.height = 5;
    board.game_board = try board.Board.init(std.testing.allocator, 5, 5);
    defer board.game_board.deinit(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN 0,0", list.writer().any());
    // Check if we received the coordinates
    const comma_pos = std.mem.indexOf(u8, list.items, ",");
    try std.testing.expect(comma_pos != null);

    // Check that the player2 stone was placed
    try std.testing.expectEqual(board.Cell.opponent, board.game_board.getCellByCoordinates(0, 0));

    // Check that that our stone was placed
    const x = try std.fmt.parseUnsigned(u32, list.items[0..comma_pos.?], 10);
    const y = try std.fmt.parseUnsigned(u32, list.items[comma_pos.? + 1..list.items.len - 1], 10);
    try std.testing.expectEqual(u32, @TypeOf(x));
    try std.testing.expectEqual(u32, @TypeOf(y));
    try std.testing.expectEqual(board.Cell.own, board.game_board.getCellByCoordinates(x, y));
}

test "handleTurn command invalid format - too short" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong TURN command format\n",
        list.items
    );
}

test "handleTurn command invalid format - no space" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN5,5", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong TURN command format\n",
        list.items
    );
}

test "handleTurn command missing comma" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN 555", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong TURN command format1\n",
        list.items
    );
}

test "handleTurn command invalid x coordinate" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN a,5", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the x coordinate: error.InvalidCharacter, val:a\n",
        list.items
    );
}

test "handleTurn command invalid y coordinate" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN 5,b", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the y coordinate: error.InvalidCharacter, val:b\n",
        list.items
    );
}

test "handleTurn command coordinates out of bounds" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    main.width = 5; main.height = 5;
    board.game_board = try board.Board.init(std.testing.allocator, 5, 5);
    defer board.game_board.deinit(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    try handle("TURN 25,25", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR coordinates are outside the board\n",
        list.items
    );
}

test "handleTurn command cell already taken" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    main.width = 5; main.height = 5;
    board.game_board = try board.Board.init(std.testing.allocator, 5, 5);
    defer board.game_board.deinit(std.testing.allocator);

    var real_prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    main.random = real_prng.random();

    // First place a stone
    try handle("TURN 0,0", list.writer().any());
    list.clearRetainingCapacity();

    // Try to place another stone in the same spot
    try handle("TURN 0,0", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR cell is not empty\n",
        list.items
    );
}

test "handleTurn command no empty cells" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    main.width = 5; main.height = 5;
    board.game_board = try board.Board.init(std.testing.allocator, 5, 5);
    defer board.game_board.deinit(std.testing.allocator);

    // Fill the board
    inline for (0..5) |y| {
        inline for (0..5) |x| {
            board.game_board.setCellByCoordinates(x, y, board.Cell.own);
        }
    }

    // Fill the last cell
    try handle("TURN 4,4", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR cell is not empty\n",
        list.items
    );
}
