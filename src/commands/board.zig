const std = @import("std");
const board = @import("../board.zig");
const io = @import("../io.zig");
const message = @import("../message.zig");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

const ParseBoardLineError = error {
/// Occur when not enough values are provided into the line (ex: 2/3).
    NotEnoughValues,
};

/// Function used to obtain values from a board line.
/// Ex: "10,10,1"
/// - Parameters:
///     - line: The line to parse.
///     - parsed_values: A pointer on a array of 3 optional u32.
///     - writer: The writer used for logging message.
fn getValuesFromBoardLine(
    line: []const u8,
    parsed_values: *[3]?u32,
) !void {
    var it = std.mem.split(u8, line, ",");
    for (0..3) |i| {
        const word = it.next();
        if (word == null) {
            parsed_values[i] = null;
            return ParseBoardLineError.NotEnoughValues;
        }
        parsed_values[i] = std.fmt.parseInt(u32, word.?, 10)
            catch |err| return err;
    }
}

pub fn handle(_: []const u8, writer: std.io.AnyWriter) !void {
    var read_buffer = try std.BoundedArray(u8, 256).init(0);
    var parsed_values: [3]?u32 = undefined;

    while (true) {
        @memset(&parsed_values, null);
        try io.readLineIntoBuffer(stdin.any(), &read_buffer, stdout.any());
        if (std.ascii.startsWithIgnoreCase(read_buffer.slice(), "DONE")) {
            // The command is terminated.
            return;
        }
        // Parse values and sets them into parsed_values array.
        getValuesFromBoardLine(
            read_buffer.slice(),
            &parsed_values
        ) catch |err| {
            try message.sendLogF(
                .ERROR,
                "error during board command parsing: {}",
                .{err},
                writer
            );
            continue;
        };
        // Verify the cell type.
        if (!board.Cell.isAvailableCell(parsed_values[2].?)) {
            try message.sendLogF(
                .ERROR,
                "the cell type is not recognized: {}",
                .{parsed_values[2].?},
                writer
            );
            continue;
        }
        // Verify the cell coordinates.
        if (board.game_board.isCoordinatesOutside(
            parsed_values[0].?,
            parsed_values[1].?
        )) {
            try message.sendLogF(
                .ERROR,
                "error the coordinates are outside the map: x:{} y:{}"
                ++ "map_width:{} map_height:{}",
                .{parsed_values[0].?, parsed_values[1].?,
                    board.game_board.width, board.game_board.height},
                writer
            );
            continue;
        }
        // Finally set the cell on the board.
        board.game_board.setCellByCoordinates(
            parsed_values[0].?,
            parsed_values[1].?,
            @enumFromInt(parsed_values[2].?)
        ) catch |err| {
            try message.sendLogF(.ERROR, "error: {}", .{err}, writer);
        };
    }
}

test "getValuesFromBoardLine valid input" {
    const testing = std.testing;
    var parsed_values: [3]?u32 = undefined;
    try getValuesFromBoardLine("10,20,1", &parsed_values);

    try testing.expectEqual(@as(?u32, 10), parsed_values[0]);
    try testing.expectEqual(@as(?u32, 20), parsed_values[1]);
    try testing.expectEqual(@as(?u32, 1), parsed_values[2]);
}

test "getValuesFromBoardLine not enough values" {
    const testing = std.testing;
    var parsed_values: [3]?u32 = undefined;
    try testing.expectError(
        ParseBoardLineError.NotEnoughValues,
        getValuesFromBoardLine("10,20", &parsed_values)
    );
}

test "getValuesFromBoardLine invalid number" {
    const testing = std.testing;
    var parsed_values: [3]?u32 = undefined;
    try testing.expectError(
        error.InvalidCharacter,
        getValuesFromBoardLine("10,abc,1", &parsed_values)
    );
}

test "Cell.isAvailableCell valid values" {
    const testing = std.testing;
    try testing.expect(board.Cell.isAvailableCell(1));
    try testing.expect(board.Cell.isAvailableCell(2));
    try testing.expect(board.Cell.isAvailableCell(3));
}

test "Cell.isAvailableCell invalid values" {
    const testing = std.testing;
    try testing.expect(!board.Cell.isAvailableCell(0));
    try testing.expect(!board.Cell.isAvailableCell(4));
}

test "Board initialization and deinitialization" {
    const testing = std.testing;
    const height: u32 = 10;
    const width: u32 = 10;

    var test_board = try board.Board.init(
        testing.allocator,
        testing.allocator,
        height,
        width
    );
    defer test_board.deinit(testing.allocator);

    try testing.expectEqual(height, test_board.height);
    try testing.expectEqual(width, test_board.width);
    try testing.expectEqual(height * width, test_board.map.len);
}

test "findRandomValidCell with empty board" {
    const testing = std.testing;
    const height: u32 = 3;
    const width: u32 = 3;

    var test_board = try board.Board.init(
        testing.allocator,
        testing.allocator,
        height,
        width
    );
    defer test_board.deinit(testing.allocator);

    var prng = std.rand.DefaultPrng.init(42);
    const coords = try board.findRandomValidCell(test_board, prng.random());

    try testing.expect(coords.x < width);
    try testing.expect(coords.y < height);
}

test "findRandomValidCell with full board" {
    const testing = std.testing;
    const height: u32 = 3;
    const width: u32 = 3;

    var test_board = try board.Board.init(
        testing.allocator,
        testing.allocator,
        height,
        width
    );
    defer test_board.deinit(testing.allocator);

    // Fill the board
    for (0..height) |y| {
        for (0..width) |x| {
            try test_board.setCellByCoordinates(
                @intCast(x),
                @intCast(y),
                board.Cell.own
            );
        }
    }

    var prng = std.rand.DefaultPrng.init(42);
    try testing.expectError(
        error.NoEmptyCells,
        board.findRandomValidCell(test_board, prng.random())
    );
}

test "Board move history" {
    const testing = std.testing;
    const height: u32 = 3;
    const width: u32 = 3;

    var test_board = try board.Board.init(
        testing.allocator,
        testing.allocator,
        height,
        width
    );
    defer test_board.deinit(testing.allocator);

    try test_board.setCellByCoordinates(1, 1, board.Cell.own);
    try test_board.setCellByCoordinates(2, 2, board.Cell.opponent);

    try testing.expectEqual(@as(usize, 2), test_board.move_history.items.len);
    try testing.expectEqual(@as(u32, 1), test_board.move_history.items[0].x);
    try testing.expectEqual(@as(u32, 1), test_board.move_history.items[0].y);
    try testing.expectEqual(@as(u32, 2), test_board.move_history.items[1].x);
    try testing.expectEqual(@as(u32, 2), test_board.move_history.items[1].y);
}
