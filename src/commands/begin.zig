const std = @import("std");
const message = @import("../message.zig");
const board = @import("../board.zig");
const main = @import("../main.zig");

pub fn handle(_: []const u8, writer: std.io.AnyWriter) !void {
    const empty_cell = try board.findRandomValidCell(board.game_board, main.random);
    try board.game_board.setCellByCoordinates(empty_cell.x, empty_cell.y, board.Cell.own);

    try message.sendMessageF("{d},{d}", .{empty_cell.x, empty_cell.y}, writer);
}

test "handle Begin command" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(std.testing.allocator);

    main.width = 20; main.height = 20;
    board.game_board = try board.Board.init(std.testing.allocator, std.testing.allocator, 20, 20);
    defer board.game_board.deinit(std.testing.allocator);

    try handle("BEGIN", list.writer().any());
    // Check if we received the coordinates
    const comma_pos = std.mem.indexOf(u8, list.items, ",");
    try std.testing.expect(comma_pos != null);

    const x = try std.fmt.parseUnsigned(u32, list.items[0..comma_pos.?], 10);
    const y = try std.fmt.parseUnsigned(u32, list.items[comma_pos.? + 1..list.items.len - 1], 10);
    try std.testing.expectEqual(u32, @TypeOf(x));
    try std.testing.expectEqual(u32, @TypeOf(y));
    try std.testing.expectEqual(board.Cell.own, board.game_board.getCellByCoordinates(x, y));
}
