const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");

/// Function representing the start command, allocate the board.
pub fn handle(msg: []const u8, writer: std.io.AnyWriter) !void {
    if (msg.len < 7 or msg[5] != ' ') { // at least "START " + 1 digit
        try message.sendLogC(.ERROR, "wrong START command format", writer);
        return;
    }
    const size = std.fmt.parseUnsigned(u32, msg[6..], 10) catch |err| {
        try message.sendLogF(.ERROR, "error during the parsing of the size: {}", .{err}, writer);
        return;
    };
    if (size * size > 1024 or size < 5) {
        try message.sendLogC(.ERROR, "invalid size", writer);
        return;
    }
    main.width = size;
    main.height = size;
    board.game_board = board.Board.init(main.allocator, size, size) catch |err| {
        try message.sendLogF(.ERROR, "error during the initialization of the board: {}", .{err}, writer);
        return;
    };
    try message.sendMessageComptime("OK", writer);
}

test "handleStart command valid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("START 10", list.writer().any());
    try std.testing.expectEqualStrings("OK\n", list.items);
    try std.testing.expectEqual(10, main.width);
    try std.testing.expectEqual(10, main.height);
    board.game_board.deinit(std.testing.allocator);
}

test "handleStart command invalid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("START", list.writer().any());
    try std.testing.expectEqualStrings("ERROR wrong START command format\n", list.items);
}

test "handleStart command too large size" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("START 200", list.writer().any());
    try std.testing.expectEqualStrings( "ERROR invalid size\n", list.items);
}

test "handleStart command too small" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("START 2", list.writer().any());
    try std.testing.expectEqualStrings( "ERROR invalid size\n", list.items);
}

test "handleStart command invalid number" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("START TNBC", list.writer().any());
    try std.testing.expectEqualStrings(
        "ERROR error during the parsing of the size: error.InvalidCharacter\n",
        list.items
    );
}

test "handleStart failed alloc" {
    var failing_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator, .{.fail_index = 0}
    ); // Will fail all allocations.
    main.allocator = failing_allocator.allocator();

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    try handle("START 10", list.writer().any());

    try std.testing.expectEqualStrings(
        "ERROR error during the initialization of the board: error.OutOfMemory\n",
        list.items
    );
}