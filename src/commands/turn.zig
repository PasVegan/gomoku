const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");

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
    try board.game_board.setCellByCoordinates(x, y, board.Cell.opponent);

    const empty_cell = board.findRandomValidCell(board.game_board, main.random) catch |err| {
        try message.sendLogF(.ERROR, "error during the search of a random cell: {}", .{err}, writer);
        return;
    };
    try board.game_board.setCellByCoordinates(empty_cell.x, empty_cell.y, board.Cell.own);

    try message.sendMessageF("{d},{d}", .{empty_cell.x, empty_cell.y}, writer);
}

test "handleTurn command valid input" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    main.width = 20; main.height = 20;
    board.game_board = try board.Board.init(std.testing.allocator, std.testing.allocator, 20, 20);
    defer board.game_board.deinit(std.testing.allocator);

    try handle("TURN 5,5", list.writer().any());
    // Check if we received the coordinates
    const comma_pos = std.mem.indexOf(u8, list.items, ",");
    try std.testing.expect(comma_pos != null);

    // Check that the player2 stone was placed
    try std.testing.expectEqual(board.Cell.opponent, board.game_board.getCellByCoordinates(5, 5));

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

    main.width = 20; main.height = 20;
    board.game_board = try board.Board.init(std.testing.allocator, std.testing.allocator, 20, 20);
    defer board.game_board.deinit(std.testing.allocator);

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

    main.width = 20; main.height = 20;
    board.game_board = try board.Board.init(std.testing.allocator, std.testing.allocator, 20, 20);
    defer board.game_board.deinit(std.testing.allocator);

    // First place a stone
    try handle("TURN 5,5", list.writer().any());
    list.clearRetainingCapacity();

    // Try to place another stone in the same spot
    try handle("TURN 5,5", list.writer().any());
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
    board.game_board = try board.Board.init(std.testing.allocator, std.testing.allocator, 5, 5);
    defer board.game_board.deinit(std.testing.allocator);

    // Fill the board
    var x: u32 = 0;
    var y: u32 = 0;
    outer: while (y < main.height) {
        while (x < main.width) {
            try board.game_board.setCellByCoordinates(x, y, board.Cell.own);
            x += 1;
            if (y == main.height - 1 and x == main.width - 1) {
                break :outer;
            }
        }
        x = 0;
        y += 1;
    }

    // Fill the last cell
    try handle("TURN 4,4", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the search of a random cell: error.NoEmptyCells\n",
        list.items
    );
}
