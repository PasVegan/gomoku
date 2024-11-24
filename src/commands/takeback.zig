const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");

/// Function representing the takeback command.
pub fn handle(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len < 12 or msg[8] != ' ') { // at least "TAKEBACK " + 2 digit
        try message.sendLogC(.ERROR, "wrong TAKEBACK command format", writer);
        return;
    }
    const comma_pos = std.mem.indexOf(u8, msg, ",");
    if (comma_pos == null) {
        try message.sendLogC(.ERROR, "wrong TAKEBACK command format1", writer);
        return;
    }
    const x = std.fmt.parseUnsigned(u32, msg[9..comma_pos.?], 10) catch
    |err| {
        try message.sendLogF(
            .ERROR,
            "error during the parsing of the x coordinate: {}, val:{s}",
            .{err, msg[9..comma_pos.?]}, writer
        );
        return;
    };
    const y = std.fmt.parseUnsigned(u32, msg[comma_pos.? + 1..], 10) catch
    |err| {
        try message.sendLogF(
            .ERROR,
            "error during the parsing of the y coordinate: {}, val:{s}",
            .{err, msg[comma_pos.? + 1..]}, writer
        );
        return;
    };
    if (x >= board.game_board.width) {
        try message.sendLogC(
            .ERROR,
            "wrong x coordinate (outside of the board)",
            writer,
        );
        return;
    }
    if (y >= board.game_board.height) {
        try message.sendLogC(
            .ERROR,
            "wrong y coordinate (outside of the board)",
            writer,
        );
        return;
    }
    board.game_board.setCellByCoordinates(x, y, .empty);
    try message.sendMessageComptime("OK", writer);
}

test "handleTakeback command valid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    // Make a move.
    board.game_board.setCellByCoordinates(5, 5, .own);
    try std.testing.expectEqual(board.game_board.getCellByCoordinates(5, 5), board.Cell.own);

    try handle("TAKEBACK 5,5", list.writer().any());
    try std.testing.expectEqualStrings("OK\n", list.items);

    // Verify the cell.
    try std.testing.expectEqual(board.game_board.getCellByCoordinates(5, 5), board.Cell.empty);
}

test "handleTakeback command both coordinates outside" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("TAKEBACK 15,15", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong x coordinate (outside of the board)\n",
        list.items
    );
}

test "handleTakeback command x coordinates outside" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("TAKEBACK 15,5", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong x coordinate (outside of the board)\n",
        list.items
    );
}

test "handleTakeback command y coordinates outside" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("TAKEBACK 5,15", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong y coordinate (outside of the board)\n",
        list.items
    );
}

test "handleTakeback command invalid x coordinates" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("RECSTART TNBC,5", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the "
        ++ "x coordinate: error.InvalidCharacter, val:TNBC\n",
        list.items
    );
}

test "handleTakeback command invalid y coordinates" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("RECSTART 5,TNBC", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the "
            ++ "y coordinate: error.InvalidCharacter, val:TNBC\n",
        list.items
    );
}

test "handleTakeback command incomplete command" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("TAKEBACK ", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong TAKEBACK command format\n",
        list.items
    );
}

test "handleTakeback command without comma" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board.
    board.game_board = board.Board.init(
        main.allocator,
        10, 10
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("TAKEBACK 5 5", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong TAKEBACK command format1\n",
        list.items
    );
}
