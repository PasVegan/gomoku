const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");
const ai = @import("../ai.zig");

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
    if (board.game_board.isCoordinatesOutside(x, y)) {
        try message.sendLogC(.ERROR, "coordinates are outside the board", writer);
        return;
    }
    if (board.game_board.getCellByCoordinates(x, y) != board.Cell.empty) {
        try message.sendLogC(.ERROR, "cell is not empty", writer);
        return;
    }
    board.game_board.setCellByCoordinates(x, y, board.Cell.opponent);

    const empty_cell = ai.findBestMove(&board.game_board);
    board.game_board.setCellByCoordinates(empty_cell.col, empty_cell.row, board.Cell.own);

    try message.sendMessageF("{d},{d}", .{empty_cell.col, empty_cell.row}, writer);
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
