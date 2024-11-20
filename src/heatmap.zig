const std = @import("std");
const Coordinates = @import("coordinates.zig").Coordinates(u32);
const GameContext = @import("game_context.zig").GameContext;
const Cell = @import("board.zig").Cell;
const Board = @import("board.zig").Board;

/// Width of dilations for heatmap.
const MAX_DILATIONS = 5;

/// # Structure representing the data of a cell.
/// - Attributes:
///     - cell: Represent the cell type.
///     - coordinates: The coordinate of the cell.
///     - importance: The importance of the cell on [0, 1].
pub const CellData = struct {
    cell: Cell,
    importance: f32,
};

const Zone = struct {
    start: Coordinates,
    end: Coordinates,
    importance: f32,
};

const HeatMap = struct {
    map: []CellData,
    height: u32,
    width: u32,

    /// # Method used to initialize a HeatMap.
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
    ) !HeatMap {
        const map = try map_allocator.alloc(CellData, height * width);

        // Initialize the heatmap to zero.
        @memset(map, CellData {
            .cell = .empty,
            .importance = 0,
        });
        return HeatMap {
            .map = map,
            .height = height,
            .width = width
        };
    }

    /// # Method used to free a HeatMap.
    /// - Parameters:
    ///     - map_allocator: The allocator used to initialize the map.
    ///     - size: The width or height of the map (square).
    pub fn deinit(
        self: *HeatMap,
        map_allocator: std.mem.Allocator,
    ) void {
        map_allocator.free(self.map);
    }

    /// Clone the current HeatMap with padding
    /// - Parameters:
    ///     - allocator: The allocator to use for the new map
    ///     - padding: Amount of padding to add on each side
    /// - Returns:
    ///     - A new HeatMap with padding
    pub fn cloneWithPadding(
        self: HeatMap,
        allocator: std.mem.Allocator,
        padding: u32
    ) !ReshapedHeatmap {
        const new_width = self.width + (padding * 2);
        const new_height = self.height + (padding * 2);

        var new_map = try HeatMap.init(allocator, new_height, new_width);

        // Copy the original data to the padded position
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const old_idx = self.coordinatesToIndex(x, y);
                const new_idx = new_map.coordinatesToIndex(x + padding, y + padding);
                new_map.map[new_idx] = self.map[old_idx];
            }
        }

        return ReshapedHeatmap {
            .heatmap = new_map,
            .original_height = self.height,
            .original_width = self.width,
        };
    }

    /// Get a shaped subset of the current HeatMap
    /// - Parameters:
    ///     - allocator: The allocator to use for the new map
    ///     - new_width: Desired width of the new map
    ///     - new_height: Desired height of the new map
    /// - Returns:
    ///     - A new HeatMap with the specified dimensions, centered on the original
    pub fn getShape(
        self: HeatMap,
        allocator: std.mem.Allocator,
        new_width: u32,
        new_height: u32
    ) !ReshapedHeatmap {
        if (new_width > self.width or new_height > self.height) {
            return error.ShapeTooLarge;
        }

        var new_map = try HeatMap.init(allocator, new_height, new_width);

        const start_x = (self.width - new_width) / 2;
        const start_y = (self.height - new_height) / 2;

        var y: u32 = 0;
        while (y < new_height) : (y += 1) {
            var x: u32 = 0;
            while (x < new_width) : (x += 1) {
                const old_idx = self.coordinatesToIndex(start_x + x, start_y + y);
                const new_idx = new_map.coordinatesToIndex(x, y);
                new_map.map[new_idx] = self.map[old_idx];
            }
        }

        return ReshapedHeatmap {
            .heatmap = new_map,
            .original_height = self.height,
            .original_width = self.width,
        };
    }

    /// Clone the current HeatMap
    /// - Parameters:
    ///     - allocator: The allocator to use for the new map
    /// - Returns:
    ///     - A new HeatMap with the same contents
    pub fn clone(
        self: HeatMap,
        allocator: std.mem.Allocator,
    ) !HeatMap {
        const new_map = try HeatMap.init(allocator, self.height, self.width);
        @memcpy(new_map.map, self.map);
        return new_map;
    }

    /// # Method used to obtain a index from coordinates.
    /// - Parameters:
    ///     - self: The current HeatMap.
    ///     - x: The coordinate on x-axis.
    ///     - y: The coordinate on y-axis.
    /// - Returns:
    ///     - The index in the map array.
    fn coordinatesToIndex(self: HeatMap, x: u32, y: u32) u32 {
        return y * self.width + x;
    }

    pub fn applyZone(self: *HeatMap, zone: Zone) void {
        for (zone.start.y..zone.end.y) |y| {
            for (zone.start.x..zone.end.x) |x| {
                self.map[
                self.coordinatesToIndex(
                    @as(u32, @intCast(x)),
                    @as(u32, @intCast(y))
                )
                ].importance = zone.importance;
            }
        }
    }

    /// # Method used to format the HeatMap into a string.
    /// - Parameters:
    ///     - self: The current HeatMap.
    ///     - writer: The writer where to write the formatted string.
    /// - Returns:
    ///     - A formatting error if any occurs.
    pub fn format(
        self: HeatMap,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("HeatMap {\n");
        try writer.print("  dimensions: {}x{}\n", .{self.width, self.height});
        try writer.writeAll("  cells:\n");

        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            try writer.writeAll("    ");
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                const cell = self.map[self.coordinatesToIndex(x, y)];
                try writer.print("{d:.2} ", .{cell.importance});
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("}");
    }
};

pub const ReshapedHeatmap = struct {
    heatmap: HeatMap,
    original_height: u32,
    original_width: u32,

    // pub fn dilateWithValue(
    //     self: *ReshapedHeatmap,
    //     kernel: []f32,
    //     kernel_height: u32,
    //     kernel_width: u32,
    // ) void {
    //     for (1..self.heatmap.width - 1) |y| {
    //         for (1..self.heatmap.height - 1) |x| {
    //
    //         }
    //     }
    // }
};

fn getHiglightWidthHeight(size: u32) ?u32 {
    if (size < 10) {
        return null;
    } else if (size > 10 and size < 20) {
        return size / 2;
    }
    return 10;
}

fn getMaxHiglightZone(board: Board) ?Zone {
    const width = getHiglightWidthHeight(board.width);
    const height = getHiglightWidthHeight(board.height);

    if (width == null or height == null) {
        return null;
    }

    const start_x = (board.width - width.?) / 2;
    const start_y = (board.height - height.?) / 2;
    const end_x = start_x + width.?;
    const end_y = start_y + height.?;

    return Zone {
        .start = Coordinates{ .x = start_x, .y = start_y },
        .end = Coordinates{ .x = end_x, .y = end_y },
        .importance = 0.5,
    };
}

/// # Function used to higlight the map center in the early rounds.
/// - Details:
///     In order to favorise playing in the center.
/// - Parameters:
///     - board: The game board.
///     - context: The game context.
///     - heatmap: The heatmap to modify.
// pub fn highlightMapCenter(
//     board: Board,
//     context: GameContext,
//     heatmap: *std.ArrayList
// ) void {
//     if (board.width >= 10)
// }

/// Function used to obtain the distance between 2 coos.
fn getDistance(point1: Coordinates, point2: Coordinates) u32 {
    const dx = @abs(
        @as(i32, @intCast(point1.x)) -
        @as(i32, @intCast(point2.x))
    );
    const dy = @abs(
        @as(i32, @intCast(point1.y)) -
        @as(i32, @intCast(point2.y))
    );

    // Return the maximum of the two distances
    return @max(dx, dy);
}

/// Function used to create a distance kernel.
fn createDistanceKernel(kernel_size: comptime_int)
    [kernel_size * kernel_size]u32
{
    const center = Coordinates {
        .x = kernel_size / 2,
        .y = kernel_size / 2,
    };
    var array: [kernel_size * kernel_size]u32 = undefined;

    inline for (0..kernel_size) |x| {
        inline for (0..kernel_size) |y| {
            array[y * kernel_size + x] =
                getDistance(center, Coordinates{
                    .x = x,
                    .y = y
                });
        }
    }
    return array;
}

/// Function which calculate f(x, max)=(max-x)/max.
fn calculateInterest(distance: u32, max: u32) f32 {
    return @as(f32, @floatFromInt((max - distance))) /
        @as(f32, @floatFromInt(max));
}

/// Function used to create an interest kernel.
/// Based on f(x, max)=(max-x)/max
fn createInterestKernel(
    kernel_size: comptime_int,
    distance_kernel: []const u32
) [kernel_size * kernel_size]f32 {
    var array: [kernel_size * kernel_size]f32 = undefined;
    const width = (kernel_size / 2) + 1;

    inline for (0..array.len) |index| {
        array[index] = calculateInterest(
            distance_kernel[index],
            width
        );
    }
    return array;
}

/// # Function used to have a heatmap of region where it is favorable to play.
pub fn bestActionHeatmap(
    board: Board,
    context: GameContext,
    allocator: std.mem.Allocator
) !?HeatMap {
    // Initialize the heatmap with a base capacity.
    var heatmap = try HeatMap.init(
        allocator,
        board.height,
        board.width
    );

    // Higlight the middle of the map in order to favorise action in the
    // middle in early rounds.
    const higlightMiddleZones = getMaxHiglightZone(board);
    if (higlightMiddleZones != null and context.round < 8) {
        heatmap.applyZone(higlightMiddleZones.?);
    }

    // Create the distance kernel.
    const distance_kernel = createDistanceKernel(MAX_DILATIONS);
    _ = distance_kernel;

    // Highlight 5 of width from existing tokens on map.
    // const paddedHeatmap = heatmap.cloneWithPadding(allocator, MAX_DILATIONS);
    // _ = paddedHeatmap;

    return heatmap;
}

test "getHiglightWidthHeight handles different sizes" {
    // Less than 10
    try std.testing.expectEqual(getHiglightWidthHeight(5), null);
    try std.testing.expectEqual(getHiglightWidthHeight(9), null);

    // Between 10 and 20
    try std.testing.expectEqual(getHiglightWidthHeight(12), 6);
    try std.testing.expectEqual(getHiglightWidthHeight(15), 7);
    try std.testing.expectEqual(getHiglightWidthHeight(19), 9);

    // 20 or greater
    try std.testing.expectEqual(getHiglightWidthHeight(20), 10);
    try std.testing.expectEqual(getHiglightWidthHeight(30), 10);
}

test "getMaxHiglightZone calculates correct zones" {
    // Test case 1: Valid board with width and height > 20
    {
        var board = try Board.init(std.testing.allocator, 30, 30);
        board.deinit(std.testing.allocator);
        const zone = getMaxHiglightZone(board);
        try std.testing.expect(zone != null);
        try std.testing.expectEqual(zone.?.start.x, 10);
        try std.testing.expectEqual(zone.?.start.y, 10);
        try std.testing.expectEqual(zone.?.end.x, 20);
        try std.testing.expectEqual(zone.?.end.y, 20);
    }

    // Test case 2: Valid board with width and height between 10 and 20
    {
        var board = try Board.init(std.testing.allocator, 16, 16);
        board.deinit(std.testing.allocator);
        const zone = getMaxHiglightZone(board);
        try std.testing.expect(zone != null);
        try std.testing.expectEqual(zone.?.start.x, 4);
        try std.testing.expectEqual(zone.?.start.y, 4);
        try std.testing.expectEqual(zone.?.end.x, 12);
        try std.testing.expectEqual(zone.?.end.y, 12);
    }

    // Test case 3: Invalid board with width < 10
    {
        var board = try Board.init(std.testing.allocator, 8, 30);
        board.deinit(std.testing.allocator);
        const zone = getMaxHiglightZone(board);
        try std.testing.expectEqual(zone, null);
    }

    // Test case 4: Invalid board with height < 10
    {
        var board = try Board.init(std.testing.allocator, 30, 8);
        board.deinit(std.testing.allocator);
        const zone = getMaxHiglightZone(board);
        try std.testing.expectEqual(zone, null);
    }
}

test "HeatMap initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const height: u32 = 10;
    const width: u32 = 10;

    var heatmap = try HeatMap.init(allocator, height, width);
    defer heatmap.deinit(allocator);

    try testing.expectEqual(heatmap.height, height);
    try testing.expectEqual(heatmap.width, width);
    try testing.expectEqual(heatmap.map.len, height * width);

    // Test initial values
    for (heatmap.map) |cell| {
        try testing.expectEqual(cell.cell, Cell.empty);
        try testing.expectEqual(cell.importance, 0);
    }
}

test "HeatMap coordinatesToIndex" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var heatmap = try HeatMap.init(allocator, 5, 5);
    defer heatmap.deinit(allocator);

    try testing.expectEqual(heatmap.coordinatesToIndex(0, 0), 0);
    try testing.expectEqual(heatmap.coordinatesToIndex(4, 0), 4);
    try testing.expectEqual(heatmap.coordinatesToIndex(0, 4), 20);
    try testing.expectEqual(heatmap.coordinatesToIndex(4, 4), 24);
}

test "getHiglightWidthHeight" {
    const testing = std.testing;
    try testing.expectEqual(getHiglightWidthHeight(5), null);
    try testing.expectEqual(getHiglightWidthHeight(15), 7);
    try testing.expectEqual(getHiglightWidthHeight(25), 10);
}

test "getMaxHiglightZone" {
    const testing = std.testing;
    var board1 = try Board.init(std.testing.allocator, 5, 5);
    board1.deinit(std.testing.allocator);
    try testing.expectEqual(getMaxHiglightZone(board1), null);

    var board2 = try Board.init(std.testing.allocator, 15, 15);
    board2.deinit(std.testing.allocator);
    const zone2 = getMaxHiglightZone(board2).?;
    try testing.expectEqual(zone2.start.x, 4);
    try testing.expectEqual(zone2.start.y, 4);
    try testing.expectEqual(zone2.end.x, 11);
    try testing.expectEqual(zone2.end.y, 11);

    var board3 = try Board.init(std.testing.allocator, 25, 25);
    board3.deinit(std.testing.allocator);
    const zone3 = getMaxHiglightZone(board3).?;
    try testing.expectEqual(zone3.start.x, 7);
    try testing.expectEqual(zone3.start.y, 7);
    try testing.expectEqual(zone3.end.x, 17);
    try testing.expectEqual(zone3.end.y, 17);
}

test "HeatMap applyZone" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var heatmap = try HeatMap.init(allocator, 5, 5);
    defer heatmap.deinit(allocator);

    const zone = Zone{
        .start = Coordinates{ .x = 1, .y = 1 },
        .end = Coordinates{ .x = 3, .y = 3 },
        .importance = 0.5,
    };

    heatmap.applyZone(zone);

    // Test cells inside zone
    for (1..3) |y| {
        for (1..3) |x| {
            const idx = heatmap.coordinatesToIndex(@intCast(x), @intCast(y));
            try testing.expectEqual(heatmap.map[idx].importance, 0.5);
        }
    }

    // Test corners (should be unchanged)
    try testing.expectEqual(heatmap.map[0].importance, 0);
    try testing.expectEqual(heatmap.map[4].importance, 0);
    try testing.expectEqual(heatmap.map[20].importance, 0);
    try testing.expectEqual(heatmap.map[24].importance, 0);
}

test "bestActionHeatmap early game" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var board = try Board.init(std.testing.allocator, 15, 15);
    board.deinit(std.testing.allocator);

    const context = GameContext{
        .round = 5,
    };

    var heatmap = try bestActionHeatmap(board, context, allocator);
    defer heatmap.?.deinit(allocator);

    // Check that center is highlighted
    const center_idx = heatmap.?.coordinatesToIndex(7, 7);
    try testing.expect(heatmap.?.map[center_idx].importance > 0);

    // Check corners are not highlighted
    try testing.expectEqual(heatmap.?.map[0].importance, 0);
    try testing.expectEqual(heatmap.?.map[14].importance, 0);
    try testing.expectEqual(heatmap.?.map[210].importance, 0);
    try testing.expectEqual(heatmap.?.map[224].importance, 0);
}

test "bestActionHeatmap late game" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var board = try Board.init(std.testing.allocator, 15, 15);
    board.deinit(std.testing.allocator);

    const context = GameContext{
        .round = 10,
    };

    var heatmap = try bestActionHeatmap(board, context, allocator);
    defer heatmap.?.deinit(allocator);

    // Check that center is not highlighted in late game
    const center_idx = heatmap.?.coordinatesToIndex(7, 7);
    try testing.expectEqual(heatmap.?.map[center_idx].importance, 0);
}

test "getDistance should return correct distances" {
    const p1 = Coordinates{ .x = 3, .y = 4 };
    const p2 = Coordinates{ .x = 2, .y = 2 };
    const p3 = Coordinates{ .x = 3, .y = 2 };
    const p4 = Coordinates{ .x = 1, .y = 1 };

    // Test horizontal distance
    try std.testing.expect(getDistance(p1, p2) == 2);
    // Test vertical distance
    try std.testing.expect(getDistance(p1, p3) == 2);
    // Test diagonal distance (max of dx and dy)
    try std.testing.expect(getDistance(p1, p4) == 3);
    // Test same point
    try std.testing.expect(getDistance(p1, p1) == 0);
}

test "createDistanceKernel should generate correct kernel" {
    const kernel_size = 5;
    const kernel = createDistanceKernel(kernel_size);

    // Check the center value
    try std.testing.expect(kernel[2 * kernel_size + 2] == 0);

    // Check distances to corners
    try std.testing.expect(kernel[0 * kernel_size + 0] == 2); // Top-left corner
    try std.testing.expect(kernel[0 * kernel_size + 4] == 2); // Top-right corner
    try std.testing.expect(kernel[4 * kernel_size + 0] == 2); // Bottom-left corner
    try std.testing.expect(kernel[4 * kernel_size + 4] == 2); // Bottom-right corner

    // Check distances to edges
    try std.testing.expect(kernel[0 * kernel_size + 2] == 2); // Top center
    try std.testing.expect(kernel[4 * kernel_size + 2] == 2); // Bottom center
    try std.testing.expect(kernel[2 * kernel_size + 0] == 2); // Left center
    try std.testing.expect(kernel[2 * kernel_size + 4] == 2); // Right center

    // Check some inner distances
    try std.testing.expect(kernel[1 * kernel_size + 1] == 1);
    try std.testing.expect(kernel[3 * kernel_size + 3] == 1);
}

test "calculateInterest basic cases" {
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        calculateInterest(0, 5),
        0.0001
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.8),
        calculateInterest(1, 5),
        0.0001
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.0),
        calculateInterest(5, 5),
        0.0001
    );
}

test "createInterestKernel 5x5" {
    const distance_kernel = createDistanceKernel(5);
    const interest_kernel = createInterestKernel(5, &distance_kernel);
    const expected = [_]f32{
        0.33, 0.33, 0.33, 0.33, 0.33,
        0.33, 0.66, 0.66, 0.66, 0.33,
        0.33, 0.66, 1.0, 0.66, 0.33,
        0.33, 0.66, 0.66, 0.66, 0.33,
        0.33, 0.33, 0.33, 0.33, 0.33,
    };

    for (interest_kernel, expected) |actual, exp| {
        try std.testing.expectApproxEqAbs(exp, actual, 0.01);
    }
}