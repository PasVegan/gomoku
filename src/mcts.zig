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
    untried_moves: []Coordinates(u32),
    untried_moves_index: u32,
    coordinates: ?Coordinates(u32),

    // Method used to initialize the Node.
    pub fn init(
        game: *GameSettings,
        board: Board,
        parent: ?*Node,
        coordinates: ?Coordinates(u32),
        allocator: *std.mem.Allocator,
    ) !*Node {
        const node = try allocator.create(Node);
        var untried_moves = try allocator.alloc(
            Coordinates(u32),
            board.map.len
        );
        const index_in_array = board.getEmptyPositions(&untried_moves);
        node.* = Node{
            .game = game,
            .board = try board.clone(allocator.*),
            .parent = parent,
            .children = std.ArrayList(*Node).init(allocator.*),
            .untried_moves = untried_moves,
            .untried_moves_index = index_in_array,
            .statistics = Statistics {
                .total_reward = 0,
                .visit_count = 0,
            },
            .coordinates = coordinates,
        };
        return node;
    }

    // Method used to destroy the Node and the tree of node.
    pub fn deinit(self: *Node, allocator: *std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.board.deinit(allocator.*);
        self.children.deinit();
        allocator.free(self.untried_moves);
        allocator.destroy(self);
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
            self.statistics.total_reward / self.statistics.visit_count
        ) + (
            C * @sqrt(
                @log(
                    top_node.statistics.visit_count
                ) / self.statistics.visit_count
            )
        );
    }

    pub fn expand(self: *Node, allocator: *std.mem.Allocator) !void {
        // Verify if untried moves are available.
        if (self.untried_moves_index == 0)
            return;

        // Pick a random untried move.
        const child_index = std.Random.uintLessThan(
            random,
            u64,
            self.untried_moves_index
        );

        // Get the coordinates for expansion.
        const child_coordinates = self.untried_moves[child_index];

        // Clone the board and apply the move.
        var new_board = try self.board.clone(allocator.*);
        defer new_board.deinit(allocator.*);
        new_board.setCellByCoordinates(
            child_coordinates.x,
            child_coordinates.y,
            .own
        );

        // Remove the move from untried moves.
        popElementFromCoordinateSlice(
            &self.untried_moves,
            &self.untried_moves_index,
            child_index
        );

        // Create a new child node.
        const new_node = try Node.init(
            self.game, new_board, self,
            child_coordinates, allocator
        );
        try self.children.append(new_node);
    }

    pub fn simulate(self: Node, allocator: *std.mem.Allocator) !i32 {
        // Obtain a temporary board from our current board state.
        var temporary_board = try self.board.clone(allocator.*);
        defer temporary_board.deinit(allocator.*);

        // Get valid cells.
        var valid_cells = try allocator.*.alloc(
            Coordinates(u32),
            self.board.map.len
        );
        defer allocator.free(valid_cells);
        var array_index = temporary_board.getEmptyPositions
            (&valid_cells);

        var current_coordinates = self.coordinates orelse Coordinates(u32) {
            .x = 0,
            .y = 0,
        };
        var current_player = Cell.own;

        while (
            !temporary_board.isWin(current_coordinates.x, current_coordinates.y)
                and !temporary_board.isFull()
        ) {
            // Get a random move.
            const current_coordinates_index = std.Random.uintLessThan(
                random,
                u64,
                array_index
            );
            current_coordinates = valid_cells.ptr[current_coordinates_index];

            // Set the cell on the board.
            temporary_board.setCellByCoordinates(
                current_coordinates.x,
                current_coordinates.y,
                current_player
            );

            popElementFromCoordinateSlice(
                &valid_cells,
                &array_index,
                current_coordinates_index
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
    array: *[]Coordinates(u32),
    array_index: *u32,
    index: u64
) void {
    array.*[index] = array.*[array_index.* - 1];
    array_index.* -= 1;
}

pub const MCTS = struct {
    allocator: std.mem.Allocator,
    root: *Node,

    pub fn init(
        game: *GameSettings,
        board: Board,
        allocator: *std.mem.Allocator
    ) !MCTS {
        return MCTS{
            .allocator = allocator.*,
            .root = try Node.init(game, board, null, null, allocator),
        };
    }

    pub fn deinit(self: *MCTS) void {
        self.root.deinit(&self.allocator);
    }

    pub fn selectBestChild(self: *MCTS) !*Node {
        var best_score: f64 = -std.math.inf(f64);
        var best_child: ?*Node = null;

        for (self.root.children.items) |child| {
            if (child.statistics.visit_count == 0) continue;
            const score = child.statistics.visit_count;
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
                    const score = child.getUCBScore() orelse continue;
                    if (score > best_score) {
                        best_score = score;
                        best_child = child;
                    }
                }

                current = best_child orelse break;
            }

            // Expansion
            if (current.untried_moves_index > 0) {
                try current.expand(&self.allocator);
                current = current.children.items[current.children.items.len - 1];
            }

            // Simulation
            const reward = try current.simulate(&self.allocator);

            // Backpropagation
            current.backpropagate(@floatFromInt(reward));
        }
    }
};


test "MCTS initialization" {
    var allocator = std.testing.allocator;
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

    var mcts = try MCTS.init(&game_settings, board, &allocator);
    defer mcts.deinit();

    try std.testing.expect(mcts.root.parent == null);
    try std.testing.expectEqual(mcts.root.children.items.len, 0);
}

test "Node UCB score calculation" {
    var allocator = std.testing.allocator;
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

    var node = try Node.init(&game_settings, board, null, null, &allocator);
    defer node.deinit(&allocator);

    // Test unvisited node
    const max_score = node.getUCBScore();
    try std.testing.expect(max_score.? == std.math.floatMax(f64));

    // Test visited node
    node.statistics.visit_count = 10;
    node.statistics.total_reward = 5;
    const ucb_score = node.getUCBScore();
    try std.testing.expect(ucb_score.? < std.math.floatMax(f64));
}

test "Node expansion" {
    var allocator = std.testing.allocator;
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

    var board = try Board.init(allocator, 3, 3);
    defer board.deinit(std.testing.allocator);

    var node = try Node.init(&game_settings, board, null, null, &allocator);
    defer node.deinit(&allocator);

    const initial_untried_moves = node.untried_moves.len;
    try node.expand(&allocator);

    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expect(
        node.untried_moves_index == initial_untried_moves - 1
    );
}

test "MCTS search and best child selection" {
    var allocator = std.testing.allocator;
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

    var board = try Board.init(allocator, 10, 10);
    defer board.deinit(std.testing.allocator);

    var mcts = try MCTS.init(&game_settings, board, &allocator);
    defer mcts.deinit();

    try mcts.performMCTSSearch(100);

    // After search, root should have children
    try std.testing.expect(mcts.root.children.items.len > 0);

    // Test if we can select best child
    const best_child = try mcts.selectBestChild();
    try std.testing.expect(best_child.statistics.visit_count > 0);
}

test "Simulation and backpropagation" {
    var allocator = std.testing.allocator;
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

    var board = try Board.init(allocator, 3, 3);
    defer board.deinit(std.testing.allocator);

    var node = try Node.init(&game_settings, board, null, Coordinates(u32){ .x = 1, .y = 1 }, &allocator);
    defer node.deinit(&allocator);

    const reward = try node.simulate(&allocator);
    try std.testing.expect(reward >= -1 and reward <= 1);

    const initial_visits = node.statistics.visit_count;
    node.backpropagate(@floatFromInt(reward));
    try std.testing.expect(node.statistics.visit_count == initial_visits + 1);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

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
    var board = try Board.init(allocator, 10, 10);
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
        // Initialize MCTS with RAVE
        var mcts = try MCTS.init(&game_settings, board, &allocator);

        // Perform MCTS search
        try mcts.performMCTSSearch(250000);

        // Select the best move
        const best_child = try mcts.selectBestChild();
        const ai_move = best_child.coordinates orelse return error.NoValidMove;
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
        mcts.deinit();

        if (board.isWin(ai_move.x, ai_move.y)) {
            try stdout.writeAll("AI wins!\n");
            break;
        }
        if (board.isFull()) {
            try stdout.writeAll("Draw!\n");
            break;
        }
        return;
    }
}
