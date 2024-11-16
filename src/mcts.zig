const std = @import("std");
const math = std.math;
const Board = @import("board.zig").Board;
const findRandomValidCell = @import("board.zig").findRandomValidCell;
const Cell = @import("board.zig").Cell;
const GameSettings = @import("game.zig").GameSettings;
const GameRule = @import("game.zig").GameRule;
const Coordinates = @import("coordinates.zig").Coordinates;

var prng = std.Random.DefaultPrng.init(0);
pub var random = prng.random();

// Constants.
const EPSILON = 1e-5;
const N_INITIAL_VISITS = 10; // n0 parameter.

/// Structure representing MCTS statistics.
/// - Attributes:
///     - total_reward: Representing the weight of the node.
///     - visit_count: Representing the number of time the node has been
///     explored.
pub const Statistics = struct {
    total_reward: f64 = 0,
    mean_reward: f64 = 0,
    variance: f64 = 36, // Modified for the PDF.
    visit_count: u64 = 0,
};

pub const Node = struct {
    parent: ?*Node,
    children: std.ArrayList(*Node),

    statistics: Statistics,
    board: Board,
    game: *GameSettings,
    untried_moves: std.ArrayList(Coordinates(u32)),
    coordinates: ?Coordinates(u32),

    allocator: std.mem.Allocator,

    // The exploration parameter, theoretically equal to √2.
    // In practice usually chosen empirically.
    // Will give more or less value to the second term.
    c: f64 = @sqrt(2.0),

    // Method used to initialize the Node.
    pub fn init(
        game: *GameSettings,
        board: Board,
        parent: ?*Node,
        coordinates: ?Coordinates(u32),
        allocator: std.mem.Allocator,
    ) !*Node {
        const node = try allocator.create(Node);
        node.* = Node{
            .game = game,
            .board = try board.clone(allocator),
            .parent = parent,
            .children = std.ArrayList(*Node).init(allocator),
            .allocator = allocator,
            .untried_moves = try board.getEmptyPositions(allocator),
            .statistics = Statistics {
                .mean_reward = 0, // Q(0)_i(si, ai)
                .total_reward = 0,
                .variance = 36, // sigma^2(0)_i(si, ai)
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
        self.untried_moves.deinit();
        self.allocator.destroy(self);
    }

    pub fn getUCBScore(self: *Node) ?f64 {
        // Unexplored nodes have maximum values so we favour exploration.
        if (self.statistics.visit_count == 0)
            return std.math.floatMax(f64);

        // Obtain the parent, or self if not existing.
        const top_node = if (self.parent == null) self else self.parent.?;

        // We use one of the possible MCTS formula for calculating the node
        // value.
        return (
            self.statistics.total_reward /
                @as(f64, @floatFromInt(self.statistics.visit_count))
        ) + (
            self.c * @sqrt(
                @log(
                    @as(f64, @floatFromInt(top_node.statistics.visit_count))
                ) /
                @as(f64, @floatFromInt(self.statistics.visit_count))
            )
        );
    }

    pub fn expand(self: *Node, allocator: std.mem.Allocator) !void {
        // Verify if untried moves are available.
        if (self.untried_moves.items.len == 0)
            return;

        // Pick a random untried move.
        const child_index = std.crypto.random.intRangeAtMost(
            u64, 0, @as(u64, self.untried_moves.items.len - 1));

        // Get the coordinates for expansion.
        const child_coordinates = self.untried_moves.items[child_index];

        // Clone the board and apply the move.
        var new_board = try self.board.clone(allocator);
        defer new_board.deinit(allocator);
        new_board.setCellByCoordinates(
            child_coordinates.x,
            child_coordinates.y,
            .own
        );

        // Remove the move from untried moves.
        _ = self.untried_moves.orderedRemove(child_index);

        // Create a new child node.
        const new_node = try Node.init(
            self.game, new_board, self,
            child_coordinates, self.allocator
        );
        try self.children.append(new_node);
    }

    pub fn simulate(self: Node, allocator: std.mem.Allocator) !i32 {
        // Obtain a temporary board from our current board state.
        var temporary_board = try self.board.clone(allocator);
        defer temporary_board.deinit(allocator);
        var current_coordinates = self.coordinates orelse
            try findRandomValidCell(temporary_board, random);
        var current_player = Cell.own;

        while (
            !temporary_board.isWin(current_coordinates.x, current_coordinates.y)
                and !temporary_board.isFull()
        ) {
            // Get a random move.
            current_coordinates = findRandomValidCell(
                temporary_board,
                random
            ) catch {
                // Draw.
                return 0;
            };

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

const MCTS = struct {
    allocator: std.mem.Allocator,
    root: *Node,

    pub fn init(
        game: *GameSettings,
        board: Board,
        allocator: std.mem.Allocator
    ) !MCTS {
        return MCTS{
            .allocator = allocator,
            .root = try Node.init(game, board, null, null, allocator),
        };
    }

    pub fn deinit(self: *MCTS) void {
        self.root.deinit(self.allocator);
    }

    pub fn selectBestChild(self: *MCTS) !*Node {
        var best_score: f64 = -std.math.inf(f64);
        var best_child: ?*Node = null;

        for (self.root.children.items) |child| {
            if (child.statistics.visit_count == 0) continue;
            const score = @as(f64, @floatFromInt(child.statistics.visit_count));
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
            while (current.untried_moves.items.len == 0 and
                current.children.items.len > 0) {
                var best_score: f64 = -std.math.inf(f64);
                var best_child: ?*Node = null;

                for (current.children.items) |child| {
                    const score = child.getUCBScore() orelse continue;
                    if (score > best_score) {
                        best_score = score;
                        best_child = child;
                    }
                }

                current = best_child orelse break;
            }

            // Expansion
            if (current.untried_moves.items.len > 0) {
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

test "Node initialization" {
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
        .folder = "", // or allocate if you need to modify it later.
        .started = false,
        .allocator = undefined,
    };
    var board = try Board.init(std.testing.allocator,
        20, 20);
    defer board.deinit(std.testing.allocator);

    const coords = Coordinates(u32){ .x = 0, .y = 0 };
    const node = try Node.init(&game_settings, board, null, coords, allocator);
    defer node.deinit(allocator);

    try std.testing.expect(node.parent == null);
    try std.testing.expect(node.children.items.len == 0);
    try std.testing.expectEqual(node.game, &game_settings);
    try std.testing.expectEqual(node.coordinates, coords);
    try std.testing.expectEqual(node.statistics.visit_count, 0);
    try std.testing.expectEqual(node.statistics.total_reward, 0);
    try std.testing.expectEqual(node.statistics.mean_reward, 0);
    try std.testing.expectEqual(node.statistics.variance, 36);
}

test "Node UCB score calculation" {
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
        .folder = "", // or allocate if you need to modify it later.
        .started = false,
        .allocator = undefined,
    };
    var board = try Board.init(std.testing.allocator,
        20, 20);
    defer board.deinit(std.testing.allocator);

    const node = try Node.init(&game_settings, board, null, null, allocator);
    defer node.deinit(allocator);

    // Test unexplored node
    try std.testing.expectEqual(node.getUCBScore().?, std.math.floatMax(f64));

    // Test explored node
    node.statistics.visit_count = 10;
    node.statistics.total_reward = 5;

    const expected_ucb = 0.5 + node.c * @sqrt(@log(10.0) / 10.0);
    const actual_ucb = node.getUCBScore().?;

    try std.testing.expectApproxEqAbs(expected_ucb, actual_ucb, 1e-10);
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
        .folder = "", // or allocate if you need to modify it later.
        .started = false,
        .allocator = undefined,
    };
    var board = try Board.init(std.testing.allocator,
        20, 20);
    defer board.deinit(std.testing.allocator);

    const node = try Node.init(&game_settings, board, null, null, allocator);
    defer node.deinit(allocator);

    const initial_untried_moves = node.untried_moves.items.len;
    try node.expand(allocator);

    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expect(node.untried_moves.items.len ==
        initial_untried_moves - 1);
    try std.testing.expect(node.children.items[0].parent == node);
}

test "Node simulation" {
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
        .folder = "", // or allocate if you need to modify it later.
        .started = false,
        .allocator = undefined,
    };
    var board = try Board.init(std.testing.allocator,
        20, 20);
    defer board.deinit(std.testing.allocator);

    const node = try Node.init(&game_settings, board, null,
        Coordinates(u32){ .x = 0, .y = 0 }, allocator);
    defer node.deinit(allocator);

    const result = try node.simulate(allocator);
    try std.testing.expect(result == 1 or result == -1 or result == 0);
}

test "Node backpropagation" {
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
    };
    var board = try Board.init(std.testing.allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    // Create a root node
    const root = try Node.init(&game_settings, board, null, null, allocator);
    defer root.deinit(allocator);

    // Create a child node
    var child_board = try board.clone(allocator);
    defer child_board.deinit(std.testing.allocator);
    const child = try Node.init(&game_settings, child_board, root,
        Coordinates(u32){ .x = 0, .y = 0 }, allocator);
    try root.children.append(child);

    // Test initial values
    try std.testing.expectEqual(root.statistics.visit_count, 0);
    try std.testing.expectEqual(root.statistics.total_reward, 0);
    try std.testing.expectEqual(child.statistics.visit_count, 0);
    try std.testing.expectEqual(child.statistics.total_reward, 0);

    // Test backpropagation with positive reward
    child.backpropagate(1.0);
    try std.testing.expectEqual(root.statistics.visit_count, 1);
    try std.testing.expectEqual(root.statistics.total_reward, 1.0);
    try std.testing.expectEqual(child.statistics.visit_count, 1);
    try std.testing.expectEqual(child.statistics.total_reward, 1.0);

    // Test backpropagation with negative reward
    child.backpropagate(-1.0);
    try std.testing.expectEqual(root.statistics.visit_count, 2);
    try std.testing.expectEqual(root.statistics.total_reward, 0.0);
    try std.testing.expectEqual(child.statistics.visit_count, 2);
    try std.testing.expectEqual(child.statistics.total_reward, 0.0);
}

test "MCTS initialization and deinitialization" {
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
    };
    var board = try Board.init(allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    try std.testing.expect(mcts.root.parent == null);
    try std.testing.expect(mcts.root.children.items.len == 0);
}

test "MCTS select best child - empty tree" {
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
    };
    var board = try Board.init(allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    try std.testing.expectError(error.NoValidMove, mcts.selectBestChild());
}

test "MCTS select best child - with children" {
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
    };
    var board = try Board.init(allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    // Expand root node to create some children
    try mcts.root.expand(allocator);
    try mcts.root.expand(allocator);

    // Set different visit counts
    mcts.root.children.items[0].statistics.visit_count = 5;
    mcts.root.children.items[1].statistics.visit_count = 10;

    const best_child = try mcts.selectBestChild();
    try std.testing.expectEqual(best_child, mcts.root.children.items[1]);
}

test "MCTS search process" {
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
    };
    var board = try Board.init(allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    // Perform search with a small number of iterations
    try mcts.performMCTSSearch(10);

    // Verify that the search created some children
    try std.testing.expect(mcts.root.children.items.len > 0);

    // Verify that visits were recorded
    try std.testing.expect(mcts.root.statistics.visit_count > 0);

    // Verify that at least one child has been visited
    var found_visited_child = false;
    for (mcts.root.children.items) |child| {
        if (child.statistics.visit_count > 0) {
            found_visited_child = true;
            break;
        }
    }
    try std.testing.expect(found_visited_child);
}

test "MCTS complete game simulation" {
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
    };
    var board = try Board.init(allocator, 20, 20);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, allocator);
    defer mcts.deinit();

    // Simulate several moves
    var moves: usize = 0;
    while (moves < 5) : (moves += 1) {
        try mcts.performMCTSSearch(100);
        const best_move = try mcts.selectBestChild();

        // Verify best move is valid
        try std.testing.expect(best_move.coordinates != null);
        try std.testing.expect(best_move.coordinates.?.x < 20);
        try std.testing.expect(best_move.coordinates.?.y < 20);
    }
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
        .allocator = allocator,
    };

    // Initialize board
    var board = try Board.init(allocator, 15, 15);
    defer board.deinit(allocator);

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        // Display board
        try board.display(stdout);

        // Human's turn
        try stdout.writeAll("Your turn (x y): ");
        var buffer: [100]u8 = undefined;
        const input = try stdin.readUntilDelimiter(&buffer, '\n');
        var iterator = std.mem.splitScalar(u8, input, ' ');
        const x = try std.fmt.parseInt(u32, iterator.next() orelse "", 10);
        const y = try std.fmt.parseInt(u32, iterator.next() orelse "", 10);

        // Make human move
        board.setCellByCoordinates(x, y, .own);
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

        // Create root node for MCTS with AOAP policy.
        var mcts = try MCTS.init(&game_settings, board, allocator);

        // Perform AOAP-MCTS search.
        try mcts.performMCTSSearch(100000);

        // Select best move based on AOAP-MCTS
        const best_child = try mcts.selectBestChild();
        const ai_move = best_child.coordinates orelse return error.NoValidMove;

        // Make AI move
        board.setCellByCoordinates(ai_move.x, ai_move.y, .opponent);
        try stdout.print("AI plays: {d} {d}\n", .{ai_move.x, ai_move.y});

        // Clean up MCTS
        mcts.deinit();

        if (board.isWin(ai_move.x, ai_move.y)) {
            try stdout.writeAll("AI wins!\n");
            break;
        }
        if (board.isFull()) {
            try stdout.writeAll("Draw!\n");
            break;
        }
    }
}
