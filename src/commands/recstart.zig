const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");

/// Function representing the recstart command, allocate the board.
pub fn handle(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len < 12 or msg[8] != ' ') { // at least "RECSTART " + 2 digit
        try message.sendLogC(.ERROR, "wrong RECSTART command format", writer);
        return;
    }
    const comma_pos = std.mem.indexOf(u8, msg, ",");
    if (comma_pos == null) {
        try message.sendLogC(.ERROR, "wrong RECSTART command format1", writer);
        return;
    }
    const width = std.fmt.parseUnsigned(u32, msg[9..comma_pos.?], 10) catch
    |err| {
        try message.sendLogF(
            .ERROR,
            "error during the parsing of the width: {}, val:{s}",
            .{err, msg[9..comma_pos.?]}, writer
        );
        return;
    };
    const height = std.fmt.parseUnsigned(u32, msg[comma_pos.? + 1..], 10) catch
    |err| {
        try message.sendLogF(
            .ERROR,
            "error during the parsing of the height: {}, val:{s}",
            .{err, msg[comma_pos.? + 1..]}, writer
        );
        return;
    };
    if (width == height) {
        try message.sendLogC(
            .ERROR,
            "impossible to create a square board " ++
            "using RECSTART (consider using START instead)",
            writer,
        );
        return;
    }
    if (width * height > 1024 or width < 5 or height < 5) {
        try message.sendLogC(.ERROR, "invalid size", writer);
        return;
    }
    main.width = width;
    main.height = height;
    board.game_board = board.Board.init(
        main.allocator,
        height,
        width
    ) catch |err| {
        try message.sendLogF(.ERROR, "error during the initialization of the board: {}", .{err}, writer);
        return;
    };
    try message.sendMessageComptime("OK", writer);
}

test "handleRecstart command valid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART 10,5", list.writer().any());
    try std.testing.expectEqualStrings("OK\n", list.items);
    try std.testing.expectEqual(10, main.width);
    try std.testing.expectEqual(5, main.height);
    board.game_board.deinit(std.testing.allocator);
}

test "handleRecstart command invalid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR wrong RECSTART command format\n",
        list.items
    );
}

test "handleRecstart command too large size" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART 200,250", list.writer().any());
    try std.testing.expectEqualStrings( "ERROR invalid size\n", list.items);
}

test "handleRecstart command too small" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART 2,4", list.writer().any());
    try std.testing.expectEqualStrings( "ERROR invalid size\n", list.items);
}

test "handleRecstart command invalid width" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART TNBC,NI", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the "
        ++ "width: error.InvalidCharacter, val:TNBC\n",
        list.items
    );
}

test "handleRecstart command invalid height" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART 10,NI", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the "
            ++ "height: error.InvalidCharacter, val:NI\n",
        list.items
    );
}

test "handleRecstart failed alloc" {
    var failing_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator, .{.fail_index = 0}
    ); // Will fail all allocations.
    main.allocator = failing_allocator.allocator();

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    try handle("RECSTART 10,15", list.writer().any());

    try std.testing.expectEqualStrings(
        "ERROR error during the initialization of the board: error.OutOfMemory\n",
        list.items
    );
}

test "handleRecstart command invalid format" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART 10 15", list.writer().any());
    try std.testing.expectEqualStrings( "ERROR wrong RECSTART command format1\n", list.items);
}

test "handleRecstart square provided" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("RECSTART 10,10", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR impossible to create a square board " ++
        "using RECSTART (consider using START instead)\n",
        list.items
    );
}
