const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");

/// Function representing the start command, allocate the board.
pub fn handle(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len > 7) { // "RESTART"
        try message.sendLogC(.ERROR, "wrong RESTART command format", writer);
        return;
    }
    if (board.game_board.width == 0 or board.game_board.height == 0) {
        try message.sendLogC(
            .ERROR,
            "nothing to restart (consider using START or RECSTART before)",
            writer
        );
        return;
    }
    board.game_board.reset();
    try message.sendMessageComptime("OK", writer);
}

test "handleRestart command valid input" {
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

    // Set a cell at coordinate 0,0.
    board.game_board.setCellByCoordinates(0, 0, .own);

    try handle("RESTART", list.writer().any());
    try std.testing.expectEqualStrings("OK\n", list.items);
    try std.testing.expectEqual(10, board.game_board.width);
    try std.testing.expectEqual(10, board.game_board.height);
    for (board.game_board.map) |cell| {
        try std.testing.expectEqual(cell, board.Cell.empty);
    }
}

test "handleRestart command no game started" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    // Initialize the board with default data.
    board.game_board = board.Board.init(
        main.allocator,
        0, 0
    ) catch |err| { return err; };
    defer board.game_board.deinit(main.allocator);

    try handle("RESTART", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR nothing to restart (consider using START or RECSTART before)\n",
        list.items
    );
}

test "handleRestart command invalid command" {
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

    // Try with a " " after RESTART.
    try handle("RESTART ", list.writer().any());

    try std.testing.expectEqualStrings("ERROR wrong RESTART command format\n", list.items);
}
