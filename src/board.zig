const std = @import("std");
const Coordinates = @import("coordinates.zig").Coordinates(u32);

/// # Enumeration representing a map cell.
pub const Cell = enum {
    empty,
    own,
    opponent,
    winning_line_or_forbidden,

    // Method used to check
    pub fn isAvailableCell(number: u32) bool {
        switch (number) {
            1...3 => return true,
            else => return false,
        }
    }
};

/// # Structure containing the board of the gomoku.
/// - Attributes:
///     - map: 1D array representing the map of the gomoku.
///     - height: The height of the map.
///     - width: The width of the map.
pub const Board = struct {
    map: []Cell,
    height: u32,
    width: u32,

    /// # Method used to initialize a board.
    /// - Parameters:
    ///     - map_allocator: The allocator we want to use in order to
    ///     initialize the array's map.
    ///     the map.
    ///     - height: The height of the map (square).
    ///     - width: The width of the map (square).
    /// - Returns:
    ///     - The initialized map.
    pub fn init(
        map_allocator: std.mem.Allocator,
        height: u32, width: u32
    ) !Board {
        const map = try map_allocator.alloc(Cell, height * width);
        // Initialize the map to zero bytes.
        @memset(map, Cell.empty);
        return Board {
            .map = map,
            .height = height,
            .width = width
        };
    }

    /// # Method used to free a board.
    /// - Parameters:
    ///     - map_allocator: The allocator used to initialize the map.
    ///     - size: The width or height of the map (square).
    pub fn deinit(
        self: *Board,
        map_allocator: std.mem.Allocator,
    ) void {
        map_allocator.free(self.map);
    }

    /// # Method used to clone a board.
    pub fn clone(
        self: Board,
        map_allocator: std.mem.Allocator,
    ) !Board {
        // Create a new board.
        const new_map = try map_allocator.alloc(
            Cell, self.height * self.width
        );

        // Copy the existing map data into the new map
        @memcpy(new_map, self.map);

        return Board{
            .map = new_map,
            .height = self.height,
            .width = self.width,
        };
    }

    /// # Method used to know if a coordinate is outside the map.
    /// - Parameters:
    ///     - self: The board we want to check.
    ///     - x: The coordinate on x-axis.
    ///     - y: The coordinate on y-axis.
    /// - Returns:
    ///     - True if the coordinate is outside the map, False if inside.
    pub fn isCoordinatesOutside(self: Board, x: u32, y: u32) bool {
        return (coordinatesToIndex(self, x, y)) >= self.map.len;
    }

    /// # Method used to get a cell from the map by coordinate.
    /// - Parameters:
    ///     - self: The board we want to obtain the cell.
    ///     - x: The coordinate on x-axis.
    ///     - y: The coordinate on y-axis.
    /// - Returns:
    ///     - The desired cell.
    pub fn getCellByCoordinates(self: Board, x: u32, y: u32) Cell {
        return self.map[coordinatesToIndex(self, x, y)];
    }

    /// # Method used to set a cell into the map at coordinate.
    /// - Parameters:
    ///     - self: The board on which you want to set the cell.
    ///     - x: The coordinate on x-axis.
    ///     - y: The coordinate on y-axis.
    pub fn setCellByCoordinates(
        self: *Board, x: u32, y: u32, value: Cell
    ) void {
        self.map[coordinatesToIndex(self.*, x, y)] = value;
    }

    /// # Method used to obtain a index from coordinates.
    /// - Parameters:
    ///     - self: The current board.
    ///     - x: The coordinate on x-axis.
    ///     - y: The coordinate on y-axis.
    /// - Returns:
    ///     - The index in the map array.
    fn coordinatesToIndex(self: Board, x: u32, y: u32) u32 {
        return y * self.width + x;
    }

    /// # Method used to obtain coordinates from index.
    /// - Parameters:
    ///     - self: The current board.
    ///     - index: The index in the map array.
    /// - Returns:
    ///     - The coordinates in the map.
    pub fn indexToCoordinates(self: Board, index: u64) Coordinates {
        const y: u32 = @as(u32, @intCast(index)) / self.width;
        const x: u32 = @as(u32, @intCast(index)) % self.width;
        return Coordinates {
            .x = x,
            .y = y,
        };
    }

    /// # Method used to check if the board is full.
    /// - Returns:
    ///     - False if not full, true if full.
    pub fn isFull(self: Board) bool {
        for (self.map) |cell|
            if (cell == .empty)
                return false;
        return true;
    }

    /// Method used to obtain empty positions.
    pub fn getEmptyPositionsArrayList(
        self: Board,
        allocator: std.mem.Allocator
    ) !std.ArrayList(Coordinates) {
        var positions = try std.ArrayList(Coordinates).initCapacity(allocator,
            self.width * self.height);
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                if (getCellByCoordinates(
                    self, @intCast(x), @intCast(y)
                ) == Cell.empty) {
                    try positions.append(Coordinates{
                        .x = @intCast(x),
                        .y = @intCast(y)
                    });
                }
            }
        }
        return positions;
    }

    /// Method used to obtain empty positions.
    pub fn getEmptyPositions(
        self: Board,
        array_to_fill: *[]Coordinates,
    ) u32 {
        var index_in_array: u32 = 0;
        for (0..self.map.len) |index| {
            if (self.map[index] == Cell.empty) {
                array_to_fill.*[index_in_array] = self.indexToCoordinates
                (index);
                index_in_array += 1;
            }
        }
        return index_in_array;
    }

    /// Check if there's a win at the given position by checking all directions
    /// Returns true if there's a win, false otherwise.
    pub fn isWin(board: Board, x: u32, y: u32) bool {
        const directions = [_][2]i32{
            [_]i32{ 1, 0 },   // horizontal
            [_]i32{ 0, 1 },   // vertical
            [_]i32{ 1, 1 },   // diagonal right
            [_]i32{ 1, -1 },  // diagonal left
        };

        const current_cell = board.getCellByCoordinates(x, y);
        if (current_cell == Cell.empty) return false;

        // Helper function to check if coordinates are valid.
        const isValidPosition = struct {
            fn check(brd: Board, pos_x: i32, pos_y: i32) bool {
                return pos_x >= 0 and pos_y >= 0 and
                        pos_x < brd.width and pos_y < brd.height;
            }
        }.check;

        inline for (directions) |dir| {
            var count: i32 = 1;

            // Check both directions in a single loop.
            inline for ([_]i32{1, -1}) |multiplier| {
                inline for ([_]i32{1, 2, 3, 4}) |i| {
                    const new_x = @as(i32, @intCast(x)) + (dir[0] * i * multiplier);
                    const new_y = @as(i32, @intCast(y)) + (dir[1] * i * multiplier);

                    if (!isValidPosition(board, new_x, new_y)) break;

                    const check_x = @as(u32, @intCast(new_x));
                    const check_y = @as(u32, @intCast(new_y));
                    if (board.getCellByCoordinates(check_x, check_y) != current_cell) break;
                    count += 1;
                }
            }

            if (count >= 5) return true;
        }

        return false;
    }

    /// Method used to display the board.
    pub fn display(self: Board, writer: anytype) !void {
        // Print column numbers
        try writer.writeAll("   "); // Padding for row numbers
        for (0..self.width) |x| {
            if (x + 1 == self.width) {
                if (x < 10) {
                    try writer.print(" {d}", .{x});
                } else {
                    try writer.print("{d}", .{x});
                }
            } else {
                if (x < 10) {
                    try writer.print(" {d} ", .{x});
                } else {
                    try writer.print("{d} ", .{x});
                }
            }
        }
        try writer.writeAll("\n");

        // Print the board with row numbers
        for (0..self.height) |y| {
            if (y < 10) {
                try writer.print(" {d} ", .{y});
            } else {
                try writer.print("{d} ", .{y});
            }

            for (0..self.width) |x| {
                const cell = self.getCellByCoordinates(@intCast(x), @intCast(y));
                const symbol = switch (cell) {
                    .empty => ".",
                    .own => "O",
                    .opponent => "X",
                    .winning_line_or_forbidden => "#",
                };
                if (x + 1 == self.width) {
                    try writer.print(" {s}", .{symbol});
                } else {
                    try writer.print(" {s} ", .{symbol});
                }
            }
            try writer.writeAll("\n");
        }
    }

    /// Check if there's a win at the given position by checking all directions
    /// Returns true if there's a win, false otherwise.
    pub fn addWinningLine(board: *Board, x: u32, y: u32) !bool {
        const directions = [_][2]i32{
            [_]i32{ 1, 0 },   // horizontal
            [_]i32{ 0, 1 },   // vertical
            [_]i32{ 1, 1 },   // diagonal right
            [_]i32{ 1, -1 },  // diagonal left
        };

        const current_cell = board.getCellByCoordinates(x, y);
        if (current_cell == Cell.empty) return false;

        // Helper function to check if coordinates are valid.
        const isValidPosition = struct {
            fn check(brd: *Board, pos_x: i32, pos_y: i32) bool {
                return pos_x >= 0 and pos_y >= 0 and
                    pos_x < brd.width and pos_y < brd.height;
            }
        }.check;

        var victory_line = try std.BoundedArray(Coordinates, 5).init(5);

        inline for (directions) |dir| {
            var count: i32 = 1;

            // Reset the victory line
            victory_line.clear();
            // Add the initial position
            try victory_line.append(Coordinates{ .x = x, .y = y });

            // Check both directions in a single loop.
            inline for ([_]i32{1, -1}) |multiplier| {
                inline for ([_]i32{1, 2, 3, 4}) |i| {
                    const new_x = @as(i32, @intCast(x)) + (dir[0] * i * multiplier);
                    const new_y = @as(i32, @intCast(y)) + (dir[1] * i * multiplier);

                    if (!isValidPosition(board, new_x, new_y))
                        break;

                    const check_x = @as(u32, @intCast(new_x));
                    const check_y = @as(u32, @intCast(new_y));
                    if (board.getCellByCoordinates(check_x, check_y) != current_cell)
                        break;
                    try victory_line.append(Coordinates{ .x = check_x, .y = check_y });
                    count += 1;
                }
            }

            if (count >= 5) {
                // Mark the winning line
                for (victory_line.constSlice()) |coord| {
                    std.debug.print("Winning line at ({d}, {d})\n", .{coord.x, coord.y});
                    board.setCellByCoordinates(coord.x, coord.y, Cell.winning_line_or_forbidden);
                }
                return true;
            }
        }

        return false;
    }

    pub fn format(
        self: Board,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        // Print column coordinates
        try writer.writeAll("   "); // Padding for row coordinates
        var x: u32 = 0;
        while (x < self.width) : (x += 1) {
            try writer.print(" {d:2}", .{x});
        }
        try writer.writeAll("\n");

        // Print top border
        try writer.writeAll("   ┌");
        x = 0;
        while (x < self.width) : (x += 1) {
            try writer.writeAll("───");
        }
        try writer.writeAll("┐\n");

        // Print board content with row coordinates
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            try writer.print("{d:2} │", .{y}); // Row coordinate
            x = 0;
            while (x < self.width) : (x += 1) {
                const cell = self.getCellByCoordinates(x, y);
                const symbol = switch (cell) {
                    .empty => ".",
                    .opponent => "●",
                    .own => "○",
                    .winning_line_or_forbidden => "X",
                };
                try writer.print(" {s} ", .{symbol});
            }
            try writer.writeAll("│\n");
        }

        // Print bottom border
        try writer.writeAll("   └");
            x = 0;
            while (x < self.width) : (x += 1) {
                try writer.writeAll("───");
            }
            try writer.writeAll("┘\n");
        }
};

// The game board.
pub var game_board: Board = undefined;

/// ###### This function list the empty cells of the board then make a random choise and return coordinates of the choosen cell.
/// - Parameters:
///     - board: The board we want to find a random empty cell.
///     - random: The random generator we want to use.
pub fn findRandomValidCell(board: Board, random: std.Random) !Coordinates {
    // Count empty cells
    var empty_count: u32 = 0;
    for (board.map) |cell| {
        if (cell == Cell.empty) {
            empty_count += 1;
        }
    }

    // If no empty cells, return error
    if (empty_count == 0) {
        return error.NoEmptyCells;
    }

    // Get a random number between 0 and empty_count - 1
    const target = random.uintLessThan(u32, empty_count);

    // Find the target empty cell
    var current_empty: u32 = 0;
    for (board.map, 0..) |cell, index| {
        if (cell == Cell.empty) {
            if (current_empty == target) {
                // Convert index back to coordinates
                const y = @divTrunc(index, board.width);
                const x = index % board.width;
                return Coordinates{
                    .x = @intCast(x),
                    .y = @intCast(y),
                };
            }
            current_empty += 1;
        }
    }

    unreachable;
}

test "expect board to have a full cell on x: 2 and y: 0" {
    const height = 20;
    const width = 20;
    const x = 2;
    const y = 0;

    // Initialize the board.
    var board = Board.init(std.testing.allocator,
        height, width) catch |err| { return err; };
    defer board.deinit(std.testing.allocator);

    // Set coordinates.
    board.setCellByCoordinates(x, y, Cell.own);

    // Verifying the board.
    try std.testing.expect(board.height == height);
    try std.testing.expect(board.width == width);
    try std.testing.expect(board.getCellByCoordinates(x, y) == Cell.own);
    try std.testing.expect(board.getCellByCoordinates(x + 1, y) == Cell.empty);
    try std.testing.expect(
        board.isCoordinatesOutside(width, height - 1) == true
    );
    try std.testing.expect(
        board.isCoordinatesOutside(width - 1, height - 1) == false
    );
}

test "Gomoku win conditions" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test board 15x15
    var board = try Board.init(allocator, 15, 15);
    defer board.deinit(allocator);

    // Test horizontal win
    board.setCellByCoordinates(0, 0, Cell.own);
    board.setCellByCoordinates(1, 0, Cell.own);
    board.setCellByCoordinates(2, 0, Cell.own);
    board.setCellByCoordinates(3, 0, Cell.own);
    board.setCellByCoordinates(4, 0, Cell.own);
    try testing.expect(board.isWin(2, 0));

    // Reset board
    board = try Board.init(allocator, 15, 15);

    // Test vertical win
    board.setCellByCoordinates(0, 0, Cell.opponent);
    board.setCellByCoordinates(0, 1, Cell.opponent);
    board.setCellByCoordinates(0, 2, Cell.opponent);
    board.setCellByCoordinates(0, 3, Cell.opponent);
    board.setCellByCoordinates(0, 4, Cell.opponent);
    try testing.expect(board.isWin(0, 2));

    // Reset board
    board = try Board.init(allocator, 15, 15);

    // Test diagonal right win
    board.setCellByCoordinates(0, 0, Cell.own);
    board.setCellByCoordinates(1, 1, Cell.own);
    board.setCellByCoordinates(2, 2, Cell.own);
    board.setCellByCoordinates(3, 3, Cell.own);
    board.setCellByCoordinates(4, 4, Cell.own);
    try testing.expect(board.isWin(2, 2));

    // Reset board
    board = try Board.init(allocator, 15, 15);

    // Test diagonal left win
    board.setCellByCoordinates(4, 0, Cell.opponent);
    board.setCellByCoordinates(3, 1, Cell.opponent);
    board.setCellByCoordinates(2, 2, Cell.opponent);
    board.setCellByCoordinates(1, 3, Cell.opponent);
    board.setCellByCoordinates(0, 4, Cell.opponent);
    try testing.expect(board.isWin(2, 2));

    // Test no win conditions
    // Reset board
    board = try Board.init(allocator, 15, 15);

    // Test incomplete line
    board.setCellByCoordinates(0, 0, Cell.own);
    board.setCellByCoordinates(1, 0, Cell.own);
    board.setCellByCoordinates(2, 0, Cell.own);
    board.setCellByCoordinates(3, 0, Cell.own);
    try testing.expect(!board.isWin(2, 0));

    // Test broken line
    board.setCellByCoordinates(4, 0, Cell.opponent);
    try testing.expect(!board.isWin(2, 0));

    // Test empty position
    try testing.expect(!board.isWin(5, 5));

    // Test edge cases
    // Test win at board edge
    board = try Board.init(allocator, 15, 15);
    board.setCellByCoordinates(14, 10, Cell.own);
    board.setCellByCoordinates(14, 11, Cell.own);
    board.setCellByCoordinates(14, 12, Cell.own);
    board.setCellByCoordinates(14, 13, Cell.own);
    board.setCellByCoordinates(14, 14, Cell.own);
    try testing.expect(board.isWin(14, 12));
}

test "clone method creates an independent board" {
    const height = 20;
    const width = 20;

    // Initialize the original board.
    var original_board = try Board.init(std.testing.allocator, height, width);
    defer original_board.deinit(std.testing.allocator);

    // Set some cells in the original board.
    original_board.setCellByCoordinates(1, 1, Cell.own);
    original_board.setCellByCoordinates(2, 2, Cell.opponent);

    // Clone the original board.
    var cloned_board = try original_board.clone(std.testing.allocator);
    defer cloned_board.deinit(std.testing.allocator);

    // Verify that the cloned board has the same properties.
    try std.testing.expect(cloned_board.height == original_board.height);
    try std.testing.expect(cloned_board.width == original_board.width);
    try std.testing.expect(cloned_board.getCellByCoordinates(1, 1) == original_board.getCellByCoordinates(1, 1));
    try std.testing.expect(cloned_board.getCellByCoordinates(2, 2) == original_board.getCellByCoordinates(2, 2));

    // Verify that the cloned board is independent.
    // Change the original board.
    original_board.setCellByCoordinates(1, 1, Cell.empty);

    // Check that the cloned board remains unchanged.
    try std.testing.expect(cloned_board.getCellByCoordinates(1, 1) == Cell.own);
}

test "clone method retains move history" {
    const height = 20;
    const width = 20;

    // Initialize the original board.
    var original_board = try Board.init(std.testing.allocator, height, width);
    defer original_board.deinit(std.testing.allocator);

    // Make some moves.
    original_board.setCellByCoordinates(1, 1, Cell.own);
    original_board.setCellByCoordinates(2, 2, Cell.opponent);

    // Clone the original board.
    var cloned_board = try original_board.clone(std.testing.allocator);
    defer cloned_board.deinit(std.testing.allocator);
}

test "clone method allocates separate memory" {
    const height = 20;
    const width = 20;

    // Initialize the original board.
    var original_board = try Board.init(std.testing.allocator, height, width);
    defer original_board.deinit(std.testing.allocator);

    // Clone the original board.
    var cloned_board = try original_board.clone(std.testing.allocator);
    defer cloned_board.deinit(std.testing.allocator);

    // Check that the original and cloned board map do not share the same
    // pointer.
    try std.testing.expect(cloned_board.map.ptr != original_board.map.ptr);
}

test "display board with various cell states" {
    const height = 5;
    const width = 5;
    var board = try Board.init(std.testing.allocator, height, width);
    defer board.deinit(std.testing.allocator);

    // Set up some test cells
    board.setCellByCoordinates(1, 1, Cell.own);
    board.setCellByCoordinates(2, 2, Cell.opponent);
    board.setCellByCoordinates(3, 3, Cell.winning_line_or_forbidden);

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    try board.display(output.writer());

    const expected =
        \\    0  1  2  3  4
        \\ 0  .  .  .  .  .
        \\ 1  .  O  .  .  .
        \\ 2  .  .  X  .  .
        \\ 3  .  .  .  #  .
        \\ 4  .  .  .  .  .
        \\
    ;

    try std.testing.expectEqualStrings(expected, output.items);
}

test "display larger board" {
    const height = 10;
    const width = 10;
    var board = try Board.init(std.testing.allocator, height, width);
    defer board.deinit(std.testing.allocator);

    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    try board.display(output.writer());

    // Verify first line contains correct column numbers
    const first_line = "    0  1  2  3  4  5  6  7  8  9\n";
    try std.testing.expect(std.mem.startsWith(u8, output.items, first_line));

    // Verify board dimensions
    var line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, output.items, '\n');
    while (lines.next()) |_| {
        line_count += 1;
    }
    try std.testing.expectEqual(height + 2, line_count); // +2 for column numbers and trailing newline
}
