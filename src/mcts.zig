const std = @import("std");
const math = std.math;
const Board = @import("board.zig").Board;
const findRandomValidCell = @import("board.zig").findRandomValidCell;
const Cell = @import("board.zig").Cell;
const GameSettings = @import("game.zig").GameSettings;
const GameRule = @import("game.zig").GameRule;
const Coordinates = @import("coordinates.zig").Coordinates(u32);
const GameContext = @import("game_context.zig").GameContext;
const heatmap = @import("heatmap.zig");

var prng = std.Random.DefaultPrng.init(0);
pub var random = prng.random();

// Constants.
// The exploration parameter, theoretically equal to √2.
// In practice usually chosen empirically.
// Will give more or less value to the second term.
const C: f64 = @sqrt(2.0);

/// Structure representing MCTS statistics.
/// - Attributes:
///     - total_reward: Representing the weight of the node.
///     - visit_count: Representing the number of time the node has been
///     explored.
pub const Statistics = struct {
    total_reward: f64 = 0,
    visit_count: f64 = 0,
};

pub const Node = struct {
    parent: ?*Node,
    children: std.ArrayList(*Node),

    statistics: Statistics,
    board: Board,
    game: *GameSettings,
    untried_moves: []Coordinates,
    untried_moves_index: u32,
    coordinates: Coordinates,

    // Method used to initialize the Node.
    pub fn init(
        game: *GameSettings,
        board: Board,
        parent: ?*Node,
        coordinates: Coordinates,
        untried_moves: []Coordinates,
        untried_moves_index: u32,
        allocator: std.mem.Allocator,
    ) !*Node {
        const node = try allocator.create(Node);
        const new_untried_moves = try allocator.alloc(
            Coordinates,
            untried_moves_index,
        );
        @memcpy(new_untried_moves, untried_moves[0..untried_moves_index]);
        node.* = Node{
            .game = game,
            .board = try board.clone(allocator),
            .parent = parent,
            .children = std.ArrayList(*Node).init(allocator),
            .untried_moves = new_untried_moves,
            .untried_moves_index = untried_moves_index,
            .statistics = Statistics {
                .total_reward = 0,
                .visit_count = 0,
            },
            .coordinates = coordinates,
        };
        return node;
    }

    // Method used to destroy the Node and the tree of node.
    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.board.deinit(allocator);
        self.children.deinit();
        allocator.free(self.untried_moves);
        allocator.destroy(self);
    }

    pub fn getUCBScore(self: *Node, allocator: std.mem.Allocator) ?f64 {
        // Unexplored nodes have maximum values so we favour exploration.
        if (self.statistics.visit_count == 0)
            return std.math.floatMax(f64);

        // Obtain the parent, or self if not existing.
        const top_node = if (self.parent == null) self else self.parent.?;

        // Calculate the basic UCB score
        const exploitation = self.statistics.total_reward / self.statistics.visit_count;
        const exploration = C * @sqrt(
            @log(top_node.statistics.visit_count) / self.statistics.visit_count
        );

        // Strategic position evaluation
        var position_bonus: f64 = 0;

        // Actual coordinates.
        const coords = self.coordinates;

        // Center proximity bonus (encourages playing near the center)
        const center_x = @as(f64, @floatFromInt(self.board.width)) / 2;
        const center_y = @as(f64, @floatFromInt(self.board.height)) / 2;
        const dist_x = @abs(@as(f64, @floatFromInt(coords.x)) - center_x);
        const dist_y = @abs(@as(f64, @floatFromInt(coords.y)) - center_y);
        const center_distance = @sqrt(dist_x * dist_x + dist_y * dist_y);
        const max_distance = @sqrt(
            center_x * center_x + center_y * center_y
        );
        position_bonus += 0.2 * (1 - center_distance / max_distance);

        // Pattern recognition bonus
        position_bonus += evaluatePosition(self.board, coords);

        // Defensive and offensive bonuses
        var test_board = self.board.clone(allocator) catch return null;
        defer test_board.deinit(allocator);

        // Check defensive value
        test_board.setCellByCoordinates(coords.x, coords.y, .opponent);
        if (test_board.isWin(coords.x, coords.y)) {
            position_bonus += 0.3;
        }

        // Undo.
        test_board.setCellByCoordinates(coords.x, coords.y, .empty);

        // Check offensive value
        test_board.setCellByCoordinates(coords.x, coords.y, .own);
        if (test_board.isWin(coords.x, coords.y)) {
            position_bonus += 0.25;
        }

        return exploitation + exploration + position_bonus;
    }

    fn evaluatePosition(board: Board, coords: Coordinates) f64 {
        var bonus: f64 = 0;
        const directions = [_][2]i32{
            [_]i32{ 1, 0 },   // horizontal
            [_]i32{ 0, 1 },   // vertical
            [_]i32{ 1, 1 },   // diagonal right
            [_]i32{ 1, -1 },  // diagonal left
        };

        // Check each direction for potential patterns
        for (directions) |dir| {
            var consecutive: u32 = 1;
            var space_before: bool = false;
            var space_after: bool = false;

            // Check both directions
            inline for ([_]i32{-1, 1}) |multiplier| {
                inline for ([_]i32{1, 2, 3, 4, 5}) |i| {
                    const new_x = @as(i32, @intCast(coords.x)) +
                        (dir[0] * i * multiplier);
                    const new_y = @as(i32, @intCast(coords.y)) +
                        (dir[1] * i * multiplier);

                    if (isValidPosition(board, new_x, new_y)) {
                        const cell = board.getCellByCoordinates(
                            @intCast(new_x),
                            @intCast(new_y)
                        );
                        if (cell == .own) {
                            consecutive += 1;
                        } else if (cell == .empty) {
                            if (i == 1) {
                                if (multiplier == -1) space_before = true;
                                if (multiplier == 1) space_after = true;
                            }
                            break;
                        } else break;
                    }
                }
            }

            // Award bonus based on patterns
            if (consecutive >= 2) {
                if (space_before and space_after) {
                    bonus += 0.1 * @as(f64, @floatFromInt(consecutive)); // Open ends
                } else if (space_before or space_after) {
                    bonus += 0.05 * @as(f64, @floatFromInt(consecutive)); // One open end
                }
            }
        }

        return bonus;
    }

    fn isValidPosition(board: Board, x: i32, y: i32) bool {
        return x >= 0 and y >= 0 and
            x < @as(i32, @intCast(board.width)) and
            y < @as(i32, @intCast(board.height));
    }

    pub fn expand(self: *Node, allocator: std.mem.Allocator) !void {
        // Verify if untried moves are available.
        if (self.untried_moves_index == 0)
            return;

        // Get the coordinates for expansion.
        const child_coordinates = self.untried_moves[0];

        // Clone the board and apply the move.
        var new_board = try self.board.clone(allocator);
        defer new_board.deinit(allocator);
        new_board.setCellByCoordinates(
            child_coordinates.x,
            child_coordinates.y,
            .own
        );

        // Remove the move from untried moves.
        for (1..self.untried_moves_index) |i| {
            self.untried_moves[i - 1] = self.untried_moves[i];
        }
        self.untried_moves_index -= 1;

        // Create a new child node.
        const new_node = try Node.init(
            self.game,
            new_board,
            self,
            child_coordinates,
            self.untried_moves,
            self.untried_moves_index,
            allocator
        );
        try self.children.append(new_node);
    }

    pub fn simulate(self: Node, allocator: std.mem.Allocator) !i32 {
        // Obtain a temporary board from our current board state.
        var temporary_board = try self.board.clone(allocator);
        defer temporary_board.deinit(allocator);

        var current_coordinates = self.coordinates;
        var current_player = Cell.own;

        // Arena allocator for MCTS operations
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        while (
            !temporary_board.isWin(current_coordinates.x, current_coordinates.y)
                and !temporary_board.isFull()
        ) {
            // Reset arena for this turn
            _ = arena.reset(.retain_capacity);
            const arena_allocator = arena.allocator();

            // Obtain a heatmap of important regions.
            var game_heatmap = try heatmap.bestActionHeatmap(
                temporary_board,
                self.game.context,
                arena_allocator
            );

            // Get valid, random cell (weighted random).
            const cell_index = try game_heatmap.?.getRandomIndex();
            current_coordinates =
                game_heatmap.?.indexToCoordinates(cell_index);

            // Set the cell on the board.
            temporary_board.setCellByCoordinates(
                current_coordinates.x,
                current_coordinates.y,
                current_player
            );

            // Set the turn to the other player.
            current_player =
                if (current_player == Cell.own) Cell.opponent else Cell.own;
        }

        // Returns 1 on win, -1 on failure, 0 on draw.
        if (temporary_board.isWin(current_coordinates.x, current_coordinates.y)) {
            const winner = if (current_player == Cell.own)
                Cell.opponent else Cell.own;
            return if (winner == Cell.own) 1 else -1;
        }
        return 0;
    }

    pub fn backpropagate(self: *Node, reward: f64) void {
        var current_node: ?*Node = self;

        while (current_node != null) {
            current_node.?.statistics.visit_count += 1;
            current_node.?.statistics.total_reward += reward;
            current_node = current_node.?.parent;
        }
    }
};

// Function used to pop an element from the coordinate slice.
fn popElementFromCoordinateSlice(
    array: *[]Coordinates,
    array_index: *u32,
    index: u64
) void {
    array.*[index] = array.*[array_index.* - 1];
    array_index.* -= 1;
}

pub const MCTS = struct {
    allocator: std.mem.Allocator,
    root: *Node,
    heatmap: heatmap.HeatMap,

    pub fn init(
        game: *GameSettings,
        board: Board,
        allocator: std.mem.Allocator
    ) !MCTS {
        // Obtain a heatmap of important regions.
        var game_heatmap = try heatmap.bestActionHeatmap(
            board,
            game.context,
            allocator
        );

        // Create an array containing important indexes.
        const important_coordinates_array =
            try game_heatmap.?.getBestMovesArray(allocator);
        defer allocator.free(important_coordinates_array);

        // std.debug.print("{}", .{game_heatmap.?});

        return MCTS{
            .allocator = allocator,
            .root = try Node.init(
                game,
                board,
                null,
                important_coordinates_array[0],
                important_coordinates_array
                    [1..important_coordinates_array.len],
                @as(u32, @intCast(important_coordinates_array.len - 1)),
                allocator
            ),
            .heatmap = game_heatmap.?,
        };
    }

    pub fn deinit(self: *MCTS) void {
        self.root.deinit(self.allocator);
        self.heatmap.deinit(self.allocator);
    }

    pub fn selectBestChild(self: *MCTS) !*Node {
        var best_score: f64 = -std.math.inf(f64);
        var best_child: ?*Node = null;

        for (self.root.children.items) |child| {
            if (child.statistics.visit_count == 0) continue;
            const score =
                child.statistics.total_reward / child.statistics.visit_count;
            if (score > best_score) {
                best_score = score;
                best_child = child;
            }
        }

        return best_child orelse return error.NoValidMove;
    }

    pub fn performMCTSSearch(
        self: *MCTS,
        iterations: usize,
    ) !void {
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            var current = self.root;

            // Selection
            while (current.untried_moves_index == 0 and
                current.children.items.len > 0) {
                var best_score: f64 = -std.math.inf(f64);
                var best_child: ?*Node = null;

                for (current.children.items) |child| {
                    var score = child.getUCBScore(self.allocator) orelse
                        continue;
                    const cell_data_index = self.heatmap.coordinatesToIndex
                        (child.coordinates.x, child.coordinates.y);
                    score *= self.heatmap.map[cell_data_index].importance;
                    if (score > best_score) {
                        best_score = score;
                        best_child = child;
                    }
                }

                current = best_child orelse break;
            }

            // Expansion
            if (current.untried_moves_index > 0) {
                try current.expand(self.allocator);
                current = current.children.items[current.children.items.len - 1];
            }

            // Simulation
            const reward = try current.simulate(self.allocator);

            // Backpropagation
            current.backpropagate(@floatFromInt(reward));
        }
    }
};


test "MCTS initialization" {
    const allocator = std.testing.allocator;
    var game_settings = GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = undefined,
        .context = .{ .round = 0 },
    };

    var board = try Board.init(allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    try std.testing.expect(mcts.root.parent == null);
    try std.testing.expectEqual(mcts.root.children.items.len, 0);
}

test "Node expansion" {
    const allocator = std.testing.allocator;
    var game_settings = GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = undefined,
        .context = .{ .round = 0 },
    };

    var board = try Board.init(allocator, 3, 3);
    defer board.deinit(std.testing.allocator);

    var untried_moves: [1]Coordinates = [1]Coordinates{
        .{ .x = 0, .y = 0 },
    };

    var node = try Node.init(&game_settings, board, null,
        Coordinates{.x = 0, .y = 0}, &untried_moves, 1, allocator);
    defer node.deinit(allocator);

    const initial_untried_moves = node.untried_moves.len;
    try node.expand(allocator);

    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expect(
        node.untried_moves_index == initial_untried_moves - 1
    );
}

test "MCTS search and best child selection" {
    const allocator = std.testing.allocator;
    var game_settings = GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = undefined,
        .context = .{ .round = 0 },
    };

    var board = try Board.init(allocator, 10, 10);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    try mcts.performMCTSSearch(100);

    // After search, root should have children
    try std.testing.expect(mcts.root.children.items.len > 0);

    // Test if we can select best child
    const best_child = try mcts.selectBestChild();
    try std.testing.expect(best_child.statistics.visit_count > 0);
}

test "Simulation and backpropagation" {
    const allocator = std.testing.allocator;
    var game_settings = GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = undefined,
        .context = .{ .round = 0 },
    };

    var board = try Board.init(allocator, 3, 3);
    defer board.deinit(std.testing.allocator);

    var untried_moves: [1]Coordinates = [1]Coordinates{
        .{ .x = 0, .y = 0 },
    };

    var node = try Node.init(&game_settings, board, null, Coordinates{ .x =
    1, .y = 1 }, &untried_moves, 1, allocator);
    defer node.deinit(allocator);

    const reward = try node.simulate(allocator);
    try std.testing.expect(reward >= -1 and reward <= 1);

    const initial_visits = node.statistics.visit_count;
    node.backpropagate(@floatFromInt(reward));
    try std.testing.expect(node.statistics.visit_count == initial_visits + 1);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize game settings
    var game_settings = GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .context = GameContext {
            .round = 0,
        },
        .allocator = allocator,
    };

    // Initialize board
    var board = try Board.init(allocator, 10, 10);
    defer board.deinit(allocator);

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Arena allocator for MCTS operations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    while (true) {
        // Display board
        try stdout.print("\n{}", .{board});

        // Human's turn
        try stdout.writeAll("Your turn (x y): ");
        var buffer: [100]u8 = undefined;
        const input = try stdin.readUntilDelimiter(&buffer, '\n');
        var iterator = std.mem.splitScalar(u8, input, ' ');
        const x = try std.fmt.parseInt(u32, iterator.next() orelse "", 10);
        const y = try std.fmt.parseInt(u32, iterator.next() orelse "", 10);

        // Make human move
        board.setCellByCoordinates(x, y, .opponent);
        if (board.isWin(x, y)) {
            try stdout.writeAll("You win!\n");
            break;
        }
        if (board.isFull()) {
            try stdout.writeAll("Draw!\n");
            break;
        }

        // AI's turn
        try stdout.writeAll("AI is thinking...\n");

        const time1 = std.time.milliTimestamp();

        // Reset arena for this turn
        _ = arena.reset(.free_all);
        const arena_allocator = arena.allocator();

        // Initialize MCTS.
        var mcts = try MCTS.init(&game_settings, board, arena_allocator);

        // Perform MCTS search
        try mcts.performMCTSSearch(100000);

        // Select the best move
        const best_child = try mcts.selectBestChild();
        const ai_move = best_child.coordinates;
        const time2 = std.time.milliTimestamp();
        const time_diff = time2 - time1;
        try stdout.print(
            "AI took: {d} milliseconds\n",
            .{time_diff}
        );

        // Make AI move
        board.setCellByCoordinates(ai_move.x, ai_move.y, .own);
        try stdout.print("AI plays: {d} {d}\n", .{ai_move.x, ai_move.y});

        // Clean up MCTS
        // mcts.deinit();

        if (board.isWin(ai_move.x, ai_move.y)) {
            try stdout.writeAll("AI wins!\n");
            break;
        }
        if (board.isFull()) {
            try stdout.writeAll("Draw!\n");
            break;
        }
        game_settings.context.round += 1;
        // return;
    }
}
