const std = @import("std");
const Coordinates = @import("coordinates.zig").Coordinates(u32);
const GameContext = @import("game_context.zig").GameContext;
const Cell = @import("board.zig").Cell;
const Board = @import("board.zig").Board;

var prng = std.Random.DefaultPrng.init(0);
pub var random = prng.random();

/// Width of dilations for heatmap.
const MAX_DILATIONS = 2;
const DILATION_THRESHOLD = 1;

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

pub const HeatMap = struct {
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
        height: u32, width: u32,
        board: ?Board,
    ) !HeatMap {
        const map = try map_allocator.alloc(CellData, height * width);

        if (board == null) {
            // Initialize the heatmap to zero.
            @memset(map, CellData {
                .cell = .empty,
                .importance = 0,
            });
        } else {
            for (board.?.map, 0..board.?.map.len) |cell, i| {
                map[i] = CellData{
                    .cell = cell,
                    .importance = 0,
                };
            }
        }
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

        var new_map = try HeatMap.init(allocator, new_height, new_width, null);

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

        var new_map = try HeatMap.init(allocator, new_height, new_width, null);

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
        const new_map = try HeatMap.init(
            allocator,
            self.height,
            self.width,
            null
        );
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
    pub fn coordinatesToIndex(self: HeatMap, x: u32, y: u32) u32 {
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

    /// Method used to clean the heatmap by removing importance on already
    /// filled cells.
    pub fn cleanHeatMap(
        self: *HeatMap,
    ) void {
        for (0..self.*.map.len) |index| {
            if (self.*.map[index].cell != .empty) {
                self.*.map[index].importance = 0.0;
            }
            continue;
        }
    }

    /// Method used to get the importance sum.
    pub fn getImportanceSum(self: HeatMap) f32 {
        var sum: f32 = 0;
        for (self.map) |cell| {
            sum += cell.importance;
        }
        return sum;
    }

    /// Method used to get the number of important values.
    pub fn getNbOfImportantValues(self: HeatMap) u64 {
        var count: u64 = 0;
        for (self.map) |cell| {
            if (cell.importance > 0) {
                count += 1;
            }
        }
        return count;
    }

    /// # Method used to obtain coordinates from index.
    /// - Parameters:
    ///     - self: The current board.
    ///     - index: The index in the map array.
    /// - Returns:
    ///     - The coordinates in the map.
    pub fn indexToCoordinates(self: HeatMap, index: u64) Coordinates {
        const y: u32 = @as(u32, @intCast(index)) / self.width;
        const x: u32 = @as(u32, @intCast(index)) % self.width;
        return Coordinates {
            .x = x,
            .y = y,
        };
    }

    /// Method used to obtain an array of coordinate chosen by random
    /// based on the heatmap values.
    pub fn getRandomIndexes(
        self: HeatMap,
        allocator: std.mem.Allocator,
    ) !std.ArrayList(u64) {
        // Get the number of important values.
        var nb_of_important_values = self.getNbOfImportantValues();

        // Initialize array of index (output).
        var array = try std.ArrayList(u64).initCapacity(
            allocator,
            nb_of_important_values
        );

        // Initialize a temporary heatmap.
        var temp_heatmap = try self.clone(allocator);
        defer temp_heatmap.deinit(allocator);

        // Loop in order to fill the array.
        while (nb_of_important_values > 0) {

            // Sum of weights.
            const sum = temp_heatmap.getImportanceSum();

            // Guard against zero or negative sums
            if (sum <= 0) break;

            // Pick a random float in [0; sum).
            // Use sum - std.math.f32_min to ensure random_value < sum
            const random_value = random.float(f32) * (sum - std.math.floatMin(f32));

            // Obtain an index randomly.
            var cursor: f32 = 0;
            var index: u64 = 0;
            for (temp_heatmap.map) |cell| {
                cursor += cell.importance;
                if (cursor > random_value) {
                    try array.append(index);
                    break;
                }
                index += 1;
            }

            // Set the new index to zero in order to exclude it for the next
            // times.
            temp_heatmap.map[index].importance = 0;

            // Decrement the number of important values.
            nb_of_important_values -= 1;
        }

        return array;
    }

    /// Method used to obtain a coordinate chosen by random
    /// based on the heatmap values.
    pub fn getRandomIndex(self: HeatMap)!u64 {
        // Sum of weights.
        const sum = self.getImportanceSum();

        // Guard against zero or negative sums
        if (sum <= 0) return 0;

        // Pick a random float in [0; sum).
        // Use sum - std.math.f32_min to ensure random_value < sum
        const random_value = random.float(f32) * (sum - std.math.floatMin(f32));

        // Obtain an index randomly.
        var cursor: f32 = 0;
        var index: u64 = 0;
        for (self.map) |cell| {
            cursor += cell.importance;
            if (cursor > random_value) {
                return index;
            }
            index += 1;
        }

        return 0;
    }

    pub fn getBestMovesArray(
        self: HeatMap,
        allocator: std.mem.Allocator
    ) ![]Coordinates {
        // Create an array containing important indexes.
        var important_index_array = try allocator.alloc(
            u64,
            self.getNbOfImportantValues()
        );
        defer allocator.free(important_index_array);

        var count: u32 = 0;
        for (0..self.map.len, self.map)
        |i, cell_data| {
            if (cell_data.importance > 0) {
                important_index_array[count] = i;
                count += 1;
            }
        }

        // Create context for sorting.
        const Context = struct {
            heatmap: HeatMap,

            pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                return ctx.heatmap.map[a].importance > ctx.heatmap.map[b].importance;
            }
        };

        const ctx = Context{ .heatmap = self };

        // Sort indices based on importance values
        std.sort.insertion(u64, important_index_array, ctx, Context
        .lessThan);

        // Convert into an array of coordinates.
        var important_coordinates_array = try allocator.alloc(
            Coordinates,
            important_index_array.len
        );
        for (0..important_coordinates_array.len) |i| {
            important_coordinates_array[i] =
                self.indexToCoordinates(important_index_array[i]);
        }

        return important_coordinates_array;
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

    pub fn transformCoordinates(
        self: ReshapedHeatmap,
        original_coords: Coordinates,
    ) Coordinates {
        const padding_x = (self.heatmap.width - self.original_width) / 2;
        const padding_y = (self.heatmap.height - self.original_height) / 2;

        return Coordinates{
            .x = original_coords.x + padding_x,
            .y = original_coords.y + padding_y,
        };
    }

    /// Convert padded array coordinates back to original coordinates
    /// - Parameters:
    ///     - self: The current ReshapedHeatmap
    ///     - padded_coords: The coordinates in the padded array
    /// - Returns:
    ///     - The corresponding coordinates in the original array
    pub fn toPaddedCoordinates(
        self: ReshapedHeatmap,
        original_coords: Coordinates,
    ) Coordinates {
        const padding_x = (self.heatmap.width - self.original_width) / 2;
        const padding_y = (self.heatmap.height - self.original_height) / 2;

        return Coordinates{
            .x = original_coords.x + padding_x,
            .y = original_coords.y + padding_y,
        };
    }

    pub fn extractPatch(
        self: ReshapedHeatmap,
        coordinates: Coordinates,
        data: []CellData,
        kernel_size: u32
    ) void {
        const half_kernel = kernel_size / 2;
        const start_x =
            ((self.heatmap.width - self.original_width) / 2) +
                coordinates.x;
        const start_y =
            ((self.heatmap.height - self.original_height) / 2) +
                coordinates.y;

        var y: u32 = 0;
        while (y < kernel_size) : (y += 1) {
            var x: u32 = 0;
            while (x < kernel_size) : (x += 1) {
                const source_idx = self.heatmap.coordinatesToIndex(
                    start_x - half_kernel + x,
                    start_y - half_kernel + y
                );
                const target_idx = y * kernel_size + x;
                data[target_idx] = self.heatmap.map[source_idx];
            }
        }
    }

    pub fn dilateWithKernel(
        self: *ReshapedHeatmap,
        kernel: []const f32,
        kernel_size: u32,
        allocator: std.mem.Allocator,
    ) !void {
        // Allocate temporary arrays.
        const extracted_data: []CellData = try allocator.alloc(
            CellData,
            kernel_size * kernel_size
        );
        defer allocator.free(extracted_data);
        var masked_values: []f32 = try allocator.alloc(
            f32,
            kernel_size * kernel_size
        );
        defer allocator.free(masked_values);
        for (0..self.original_height) |y| {
            for (0..self.original_width) |x| {
                // Convert x and y to coordinates.
                const coo = Coordinates{
                    .x = @as(u32, @intCast(x)),
                    .y = @as(u32, @intCast(y)),
                };

                // Extract patch of the same size of the kernel.
                self.extractPatch(coo, extracted_data, kernel_size);

                // Obtain coordinates into the padded array.
                const padded_coordinates = self.toPaddedCoordinates(coo);
                const idx = self.heatmap.coordinatesToIndex(
                    padded_coordinates.x,
                    padded_coordinates.y
                );

                // Reset the masked_values array.
                @memset(masked_values, 0.0);

                // Get the kernel values only non-empty cells.
                for (0..extracted_data.len) |i| {
                    masked_values[i] =
                        @as(f32, @floatFromInt(@intFromBool(extracted_data[i].cell !=
                        .empty))) * kernel[i];
                }

                // Get the maximum value of the resulting array.
                self.heatmap.map[idx].importance =
                    @max(
                        self.heatmap.map[idx].importance,
                        getMaxValueFromArray(masked_values)
                    );
            }
        }
    }
};

fn getMaxValueFromArray(array: []const f32) f32 {
    var max: f32 = array[0];
    for (1..array.len) |i| {
        if (array[i] > max) {
            max = array[i];
        }
    }
    return max;
}

fn getHiglightWidthHeight(size: u32) ?u32 {
    if (size < 5) {
        return null;
    } else if (size >= 5 and size <= 10) {
        return 5;
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
        .importance = 0.1,
    };
}

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
        array[index] = if (distance_kernel[index] != 0) calculateInterest(
            distance_kernel[index] - DILATION_THRESHOLD,
            width
        ) else 1.0;
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
        board.width,
        board
    );
    defer heatmap.deinit(allocator);

    // Higlight the middle of the map in order to favorise action in the
    // middle in early rounds.
    const higlightMiddleZones = getMaxHiglightZone(board);
    if (higlightMiddleZones != null and context.round < 8) {
        heatmap.applyZone(higlightMiddleZones.?);
    }

    // Create the distance kernel.
    const distance_kernel = createDistanceKernel(MAX_DILATIONS * 2 + 1);

    // Create the interest kernel.
    const interest_kernel = createInterestKernel(
        MAX_DILATIONS * 2 + 1,
        &distance_kernel
    );

    // Highlight 4 of width from existing tokens on map.
    var padded_heatmap = try heatmap.cloneWithPadding(
        allocator,
        MAX_DILATIONS * 2 + 1,
    );
    defer padded_heatmap.heatmap.deinit(allocator);

    try padded_heatmap.dilateWithKernel(
        &interest_kernel,
        MAX_DILATIONS * 2 + 1,
        allocator
    );

    // Reshape the heatmap in order to have the same shape than start.
    var reshaped_heatmap = try padded_heatmap.heatmap.getShape(
        allocator,
        board.width,
        board.height
    );

    // Clean the heatmap.
    reshaped_heatmap.heatmap.cleanHeatMap();

    return reshaped_heatmap.heatmap;
}

test "getHiglightWidthHeight handles different sizes" {
    // Less than 10
    try std.testing.expectEqual(getHiglightWidthHeight(5), 5);
    try std.testing.expectEqual(getHiglightWidthHeight(9), 5);

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

    // Test case 3: Invalid board with width < 5
    {
        var board = try Board.init(std.testing.allocator, 4, 30);
        board.deinit(std.testing.allocator);
        const zone = getMaxHiglightZone(board);
        try std.testing.expectEqual(zone, null);
    }

    // Test case 4: Invalid board with height < 5
    {
        var board = try Board.init(std.testing.allocator, 30, 3);
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

    var heatmap = try HeatMap.init(allocator, height, width, null);
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

    var heatmap = try HeatMap.init(allocator, 5, 5, null);
    defer heatmap.deinit(allocator);

    try testing.expectEqual(heatmap.coordinatesToIndex(0, 0), 0);
    try testing.expectEqual(heatmap.coordinatesToIndex(4, 0), 4);
    try testing.expectEqual(heatmap.coordinatesToIndex(0, 4), 20);
    try testing.expectEqual(heatmap.coordinatesToIndex(4, 4), 24);
}

test "getHiglightWidthHeight" {
    const testing = std.testing;
    try testing.expectEqual(getHiglightWidthHeight(5), 5);
    try testing.expectEqual(getHiglightWidthHeight(15), 7);
    try testing.expectEqual(getHiglightWidthHeight(25), 10);
}

test "getMaxHiglightZone" {
    const testing = std.testing;
    var board1 = try Board.init(std.testing.allocator, 4, 5);
    defer board1.deinit(std.testing.allocator);
    try testing.expectEqual(getMaxHiglightZone(board1), null);

    var board2 = try Board.init(std.testing.allocator, 15, 15);
    defer board2.deinit(std.testing.allocator);
    const zone2 = getMaxHiglightZone(board2).?;
    try testing.expectEqual(zone2.start.x, 4);
    try testing.expectEqual(zone2.start.y, 4);
    try testing.expectEqual(zone2.end.x, 11);
    try testing.expectEqual(zone2.end.y, 11);

    var board3 = try Board.init(std.testing.allocator, 25, 25);
    defer board3.deinit(std.testing.allocator);
    const zone3 = getMaxHiglightZone(board3).?;
    try testing.expectEqual(zone3.start.x, 7);
    try testing.expectEqual(zone3.start.y, 7);
    try testing.expectEqual(zone3.end.x, 17);
    try testing.expectEqual(zone3.end.y, 17);
}

test "HeatMap applyZone" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var heatmap = try HeatMap.init(allocator, 5, 5, null);
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
    defer board.deinit(std.testing.allocator);

    const context = GameContext{
        .round = 5,
    };

    // Set points in the top of the map.
    board.setCellByCoordinates(0, 0, .own);
    board.setCellByCoordinates(6, 0, .own);

    var heatmap = try bestActionHeatmap(board, context, allocator);
    defer heatmap.?.deinit(allocator);

    // Check that center is highlighted
    const center_idx = heatmap.?.coordinatesToIndex(7, 7);
    try testing.expect(heatmap.?.map[center_idx].importance > 0);

    // There is a token on the left.
    try testing.expectEqual(heatmap.?.map[1].importance, 1);

    // Nothing here.
    try testing.expectEqual(heatmap.?.map[14].importance, 0);
    try testing.expectEqual(heatmap.?.map[210].importance, 0);
    try testing.expectEqual(heatmap.?.map[224].importance, 0);
}

test "bestActionHeatmap late game" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var board = try Board.init(std.testing.allocator, 15, 15);
    defer board.deinit(std.testing.allocator);

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
        0.66, 0.66, 0.66, 0.66, 0.66,
        0.66, 1.0, 1.0, 1.0, 0.66,
        0.66, 1.0, 1.0, 1.0, 0.66,
        0.66, 1.0, 1.0, 1.0, 0.66,
        0.66, 0.66, 0.66, 0.66, 0.66,
    };

    for (interest_kernel, expected) |actual, exp| {
        try std.testing.expectApproxEqAbs(exp, actual, 0.01);
    }
}

test "ReshapedHeatmap.extractPatch - Basic extraction" {
    var allocator = std.testing.allocator;

    // Create a 5x5 heatmap
    var original = try HeatMap.init(allocator, 5, 5, null);
    defer original.deinit(allocator);

    // Fill with test data
    for (0..5) |y| {
        for (0..5) |x| {
            original.map[original.coordinatesToIndex(
                @as(u32, @intCast(x)),
                @as(u32, @intCast(y))
            )] = CellData{
                .cell = .empty,
                .importance = @as(f32, @floatFromInt(y * 5 + x)),
            };
        }
    }

    // Add padding of 1 on each side to make it 7x7
    var padded = try original.cloneWithPadding(allocator, 1);
    defer padded.heatmap.deinit(allocator);

    // Create buffer for 3x3 patch
    const patch = try allocator.alloc(CellData, 9); // 3x3
    defer allocator.free(patch);

    // Extract patch from center
    padded.extractPatch(
        Coordinates{ .x = 2, .y = 2 },
        patch,
        3
    );

    // Verify central patch values
    try std.testing.expectEqual(@as(f32, 6), patch[0].importance); // Top-left
    try std.testing.expectEqual(@as(f32, 7), patch[1].importance); //
    // Top-middle
    try std.testing.expectEqual(@as(f32, 8), patch[2].importance); // Top-right
    try std.testing.expectEqual(@as(f32, 11), patch[3].importance); //
    // Middle-left
    try std.testing.expectEqual(@as(f32, 12), patch[4].importance); // Center
    try std.testing.expectEqual(@as(f32, 13), patch[5].importance); //
    // Middle-right
    try std.testing.expectEqual(@as(f32, 16), patch[6].importance); //
    // Bottom-left
    try std.testing.expectEqual(@as(f32, 17), patch[7].importance); //
    // Bottom-middle
    try std.testing.expectEqual(@as(f32, 18), patch[8].importance); //
    // Bottom-right
}

test "ReshapedHeatmap.extractPatch - Corner extraction" {
    var allocator = std.testing.allocator;

    // Create a 4x4 heatmap
    var original = try HeatMap.init(allocator, 4, 4, null);
    defer original.deinit(allocator);

    // Fill with test data
    for (0..4) |y| {
        for (0..4) |x| {
            original.map[original.coordinatesToIndex(
                @as(u32, @intCast(x)),
                @as(u32, @intCast(y))
            )] = CellData{
                .cell = .empty,
                .importance = @as(f32, @floatFromInt(y * 4 + x)),
            };
        }
    }

    // Add padding of 1 on each side to make it 6x6
    var padded = try original.cloneWithPadding(allocator, 1);
    defer padded.heatmap.deinit(allocator);

    // Create buffer for 3x3 patch
    const patch = try allocator.alloc(CellData, 9); // 3x3
    defer allocator.free(patch);

    // Extract patch from top-left corner
    padded.extractPatch(
        Coordinates{ .x = 1, .y = 1 },
        patch,
        3
    );

    try std.testing.expectEqual(@as(f32, 5), patch[4].importance);
    try std.testing.expectEqual(@as(f32, 6), patch[5].importance);
    try std.testing.expectEqual(@as(f32, 9), patch[7].importance);
    try std.testing.expectEqual(@as(f32, 10), patch[8].importance);
}

test "ReshapedHeatmap.extractPatch - Different kernel sizes" {
    var allocator = std.testing.allocator;

    // Create a 6x6 heatmap
    var original = try HeatMap.init(allocator, 6, 6, null);
    defer original.deinit(allocator);

    // Fill with test data
    for (0..6) |y| {
        for (0..6) |x| {
            original.map[original.coordinatesToIndex(
                @as(u32, @intCast(x)),
                @as(u32, @intCast(y))
            )] = CellData{
                .cell = .empty,
                .importance = @as(f32, @floatFromInt(y * 6 + x)),
            };
        }
    }

    // Add padding of 2 on each side to make it 10x10
    var padded = try original.cloneWithPadding(allocator, 2);
    defer padded.heatmap.deinit(allocator);

    // Test with 5x5 kernel
    const large_patch = try allocator.alloc(CellData, 25); // 5x5
    defer allocator.free(large_patch);

    padded.extractPatch(
        Coordinates{ .x = 3, .y = 3 },
        large_patch,
        5
    );

    // Verify center value
    try std.testing.expectEqual(@as(f32, 21), large_patch[12].importance);
}

test "ReshapedHeatmap - coordinate transformations" {
    // Initialize a test heatmap (5x5) with padding of 2 on each side
    var original_map = try HeatMap.init(std.testing.allocator, 5, 5, null);
    defer original_map.deinit(std.testing.allocator);

    var padded_map = try original_map.cloneWithPadding(std.testing.allocator,
        2);
    defer padded_map.heatmap.deinit(std.testing.allocator);

    // Test case 1: Convert origin coordinates
    {
        const original_coords = Coordinates{ .x = 0, .y = 0 };
        const padded_coords = padded_map.toPaddedCoordinates(original_coords);

        try std.testing.expectEqual(@as(u32, 2), padded_coords.x);
        try std.testing.expectEqual(@as(u32, 2), padded_coords.y);

        // Test inverse transformation
        const restored_coords = padded_map.transformCoordinates(original_coords);
        try std.testing.expectEqual(padded_coords.x, restored_coords.x);
        try std.testing.expectEqual(padded_coords.y, restored_coords.y);
    }

    // Test case 2: Convert center coordinates
    {
        const original_coords = Coordinates{ .x = 2, .y = 2 };
        const padded_coords = padded_map.toPaddedCoordinates(original_coords);

        try std.testing.expectEqual(@as(u32, 4), padded_coords.x);
        try std.testing.expectEqual(@as(u32, 4), padded_coords.y);

        // Test inverse transformation
        const restored_coords = padded_map.transformCoordinates(original_coords);
        try std.testing.expectEqual(padded_coords.x, restored_coords.x);
        try std.testing.expectEqual(padded_coords.y, restored_coords.y);
    }

    // Test case 3: Convert edge coordinates
    {
        const original_coords = Coordinates{ .x = 4, .y = 4 };
        const padded_coords = padded_map.toPaddedCoordinates(original_coords);

        try std.testing.expectEqual(@as(u32, 6), padded_coords.x);
        try std.testing.expectEqual(@as(u32, 6), padded_coords.y);

        // Test inverse transformation
        const restored_coords = padded_map.transformCoordinates(original_coords);
        try std.testing.expectEqual(padded_coords.x, restored_coords.x);
        try std.testing.expectEqual(padded_coords.y, restored_coords.y);
    }

    // Test case 4: Different padding size
    {
        var larger_padding = try original_map.cloneWithPadding(std.testing
        .allocator, 3);
        defer larger_padding.heatmap.deinit(std.testing.allocator);

        const original_coords = Coordinates{ .x = 2, .y = 2 };
        const padded_coords = larger_padding.toPaddedCoordinates(original_coords);

        try std.testing.expectEqual(@as(u32, 5), padded_coords.x);
        try std.testing.expectEqual(@as(u32, 5), padded_coords.y);

        // Test inverse transformation
        const restored_coords = larger_padding.transformCoordinates(original_coords);
        try std.testing.expectEqual(padded_coords.x, restored_coords.x);
        try std.testing.expectEqual(padded_coords.y, restored_coords.y);
    }

    // Test case 5: Asymmetric dimensions
    {
        var asymmetric_map = try HeatMap.init(std.testing.allocator, 4, 6,
            null);
        defer asymmetric_map.deinit(std.testing.allocator);

        var asymmetric_padded = try asymmetric_map.cloneWithPadding(std.testing
        .allocator, 2);
        defer asymmetric_padded.heatmap.deinit(std.testing.allocator);

        const original_coords = Coordinates{ .x = 3, .y = 2 };
        const padded_coords = asymmetric_padded.toPaddedCoordinates(original_coords);

        try std.testing.expectEqual(@as(u32, 5), padded_coords.x);
        try std.testing.expectEqual(@as(u32, 4), padded_coords.y);

        // Test inverse transformation
        const restored_coords = asymmetric_padded.transformCoordinates(original_coords);
        try std.testing.expectEqual(padded_coords.x, restored_coords.x);
        try std.testing.expectEqual(padded_coords.y, restored_coords.y);
    }
}

test "HeatMap.getImportanceSum" {
    const allocator = std.testing.allocator;

    // Test case 1: Empty map with zero importance
    {
        var heatmap = try HeatMap.init(allocator, 2, 2, null);
        defer heatmap.deinit(allocator);

        try std.testing.expectApproxEqAbs(
            @as(f32, 0.0),
            heatmap.getImportanceSum(),
            0.001
        );
    }

    // Test case 2: Map with mixed importance values
    {
        var heatmap = try HeatMap.init(allocator, 2, 2, null);
        defer heatmap.deinit(allocator);

        const zone1 = Zone{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 1, .y = 1 },
            .importance = 0.5,
        };

        const zone2 = Zone{
            .start = .{ .x = 1, .y = 1 },
            .end = .{ .x = 2, .y = 2 },
            .importance = 1.0,
        };

        heatmap.applyZone(zone1);
        heatmap.applyZone(zone2);

        try std.testing.expectApproxEqAbs(
            @as(f32, 1.5), // 0.5 + 1.0
            heatmap.getImportanceSum(),
            0.001
        );
    }

    // Test case 3: Map with all cells having same importance
    {
        var heatmap = try HeatMap.init(allocator, 3, 3, null);
        defer heatmap.deinit(allocator);

        const zone = Zone{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 3, .y = 3 },
            .importance = 1.0,
        };

        heatmap.applyZone(zone);

        try std.testing.expectApproxEqAbs(
            @as(f32, 9.0), // 1.0 * 9 cells
            heatmap.getImportanceSum(),
            0.001
        );
    }

    // Test case 4: Map with cleaned cells (importance set to 0)
    {
        var heatmap = try HeatMap.init(allocator, 2, 2, null);
        defer heatmap.deinit(allocator);

        const zone = Zone{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 2, .y = 2 },
            .importance = 1.0,
        };

        heatmap.applyZone(zone);
        heatmap.cleanHeatMap();

        try std.testing.expectApproxEqAbs(
            @as(f32, 4.0), // All cells should still have importance 1.0 as they're empty
            heatmap.getImportanceSum(),
            0.001
        );
    }
}
