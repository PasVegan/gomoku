const Coordinates = @import("coordinates.zig").Coordinates(u32);
const board = @import("board.zig");
const std = @import("std");

// Represents a potential move with its position and evaluation score
pub const Threat = struct {
    row: u16,
    col: u16,
    score: i32,
};

// Evaluates a single direction from a given position for potential threats
// Returns a score based on the number of consecutive pieces and spaces found
fn evaluateDirection(current_board: *board.Board, board_coord: Coordinates, comptime direction_coord: [2]i32, comptime player: board.Cell) i32 {
    const len = current_board.map.len;
    const width = current_board.width;
    // Determine the opponent's cell type
    const opponent = comptime if (player == board.Cell.own) board.Cell.opponent else board.Cell.own;

    @setRuntimeSafety(false);

    // Convert board coordinates to integer values for calculations
    const base_row: i32 = @as(i32, @intCast(board_coord.y));
    const base_col: i32 = @as(i32, @intCast(board_coord.x));

    // Track consecutive pieces and empty spaces
    var count: u8 = 1;  // Start at 1 for the current position
    var space: u8 = 0;  // Count empty spaces

    // Check 4 positions in the given direction
    inline for ([_]i32{1,2,3,4}) |i| {
        const row_direction = direction_coord[0] * i;
        const col_direction = direction_coord[1] * i;
        const newRow = base_row + row_direction;
        const newCol = base_col + col_direction;
        const index: u32 = @as(u32, @bitCast(newRow)) * width + @as(u32, @bitCast(newCol));

        // Check if position is within board boundaries
        if (newRow < 0 or newCol < 0 or index >= len)
            return 0;

        const cell_content = current_board.map[index];
        // If opponent's piece found, this direction is blocked
        if (cell_content == opponent)
            return 0;

        if (cell_content == board.Cell.empty) {
            space += 1;
        } else {
            count += 1;
        }
    }

    // Need at least 5 positions (pieces + spaces) to win
    if (space + count < 5)
        return 0;

    // Score based on number of consecutive pieces
    const scores = comptime [6]i32{ 1, 1, 50, 500, 10000, 100000 };
    return scores[count];
}

// Evaluates a position by checking all 8 directions
pub fn evaluateMove(current_board: *board.Board, board_coord: Coordinates, comptime player: board.Cell) i32 {
    var score: i32 = 0;
    // Define all possible directions to check
    const directions: [4][2]i32 = comptime .{.{1, 0}, .{0, 1}, .{1, 1}, .{1, -1}}; // Right, down, diagonal directions
    const n_directions: [4][2]i32 = comptime .{.{-1, 0}, .{0, -1}, .{-1, -1}, .{-1, 1}}; // Left, up, opposite diagonal directions

    // Evaluate all 8 directions and sum the scores
    score += evaluateDirection(current_board, board_coord, directions[0], player);
    score += evaluateDirection(current_board, board_coord, directions[1], player);
    score += evaluateDirection(current_board, board_coord, directions[2], player);
    score += evaluateDirection(current_board, board_coord, directions[3], player);

    score += evaluateDirection(current_board, board_coord, n_directions[0], player);
    score += evaluateDirection(current_board, board_coord, n_directions[1], player);
    score += evaluateDirection(current_board, board_coord, n_directions[2], player);
    score += evaluateDirection(current_board, board_coord, n_directions[3], player);

    return score;
}

// Comparison function for sorting threats by score in descending order
fn compareThreatsByScore(_: void, a: Threat, b: Threat) bool {
    return b.score < a.score;
}

// Finds all potential threats on the board for a given player
pub fn findThreats(current_board: *board.Board, threats: []Threat, comptime player: board.Cell) u16 {
    const width = current_board.width;
    const height = current_board.height;
    var nb_threats: u16 = 0;
    const map = current_board.map;

    // Scan entire board for empty cells
    var row: u16 = 0;
    while (row < height) : (row += 1) {
        var col: u16 = 0;
        const row_offset = row * width;
        while (col < width) : (col += 1) {
            const index = row_offset + col;
            if (map[index] == board.Cell.empty) {
                // Evaluate empty position
                const score = evaluateMove(current_board, .{ .x = col, .y = row }, player);
                if (score > 0) {
                    threats[nb_threats] = .{ .row = row, .col = col, .score = score };
                    nb_threats += 1;
                }
            }
        }
    }

    // Sort threats by score
    std.sort.block(Threat, threats[0..nb_threats], {}, compareThreatsByScore);
    return nb_threats;
}

// Evaluates the entire board position
fn evaluatePosition(current_board: *board.Board) i32 {
    const width = current_board.width;
    const height = current_board.height;
    const map = current_board.map;
    var score: i32 = 0;

    // Evaluate all pieces on the board
    var row: u16 = 0;
    while (row < height) : (row += 1) {
        var col: u16 = 0;
        const row_offset = row * width;
        while (col < width) : (col += 1) {
            const cell = map[row_offset + col];
            if (cell != board.Cell.empty) {
                // Add score for own pieces, subtract for opponent's
                if (cell == board.Cell.own) {
                    score += evaluateMove(current_board, .{.x = col, .y = row}, board.Cell.own);
                } else {
                    score -= evaluateMove(current_board, .{.x = col, .y = row}, board.Cell.opponent);
                }
            }
        }
    }
    return score;
}

// Minimax algorithm with alpha-beta pruning
pub fn minimax(current_board: *board.Board, depth: u8, comptime isMaximizing: bool, alpha_in: i32, beta_in: i32) i32 {
    // Base case: evaluate position when depth is reached
    if (depth == 0) {
        return evaluatePosition(current_board);
    }

    var threats: [1024]Threat = undefined;

    const player = comptime if (isMaximizing) board.Cell.own else board.Cell.opponent;

    const nb_threats = findThreats(current_board, &threats, player);

    if (isMaximizing) {
        // Maximizing player's turn
        var maxScore: i32 = std.math.minInt(i32);
        var alpha = alpha_in;
        var i: u16 = 0;
        while (i < nb_threats): (i += 1) {
            const index = threats[i].row * current_board.width + threats[i].col;
            current_board.map[index] = board.Cell.own;
            const score = minimax(current_board, depth - 1, false, alpha, beta_in);
            current_board.map[index] = board.Cell.empty;
            maxScore = @max(maxScore, score);
            alpha = @max(alpha, score);
            if (beta_in <= alpha) {
                break; // Beta cutoff
            }
        }
        return maxScore;
    } else {
        // Minimizing player's turn
        var minScore: i32 = std.math.maxInt(i32);
        var beta = beta_in;
        var i: u16 = 0;
        while (i < nb_threats): (i += 1) {
            const index = threats[i].row * current_board.width + threats[i].col;
            current_board.map[index] = board.Cell.opponent;
            const score = minimax(current_board, depth - 1, true, alpha_in, beta);
            current_board.map[index] = board.Cell.empty;
            minScore = @min(minScore, score);
            beta = @min(beta, score);
            if (beta <= alpha_in) {
                break; // Alpha cutoff
            }
        }
        return minScore;
    }
}

// Finds the best move for the AI using minimax algorithm
pub fn findBestMove(current_board: *board.Board) Threat {
    var bestScore: i32 = std.math.minInt(i32);
    var bestMove: Threat = Threat{ .row = 0, .col = 0, .score = 0 };
    var threats: [1024]Threat = undefined;

    const nb_threats= findThreats(current_board, &threats, board.Cell.own);

    // Check for immediate winning moves
    var i: u16 = 0;
    while (i < nb_threats): (i += 1) {
        if (threats[i].score >= 100000) {
            return threats[i];
        }
    }

    // Use minimax to evaluate moves
    var alpha: i32 = std.math.minInt(i32);
    const beta: i32 = std.math.maxInt(i32);

    i = 0;
    while (i < nb_threats): (i += 1) {
        current_board.setCellByCoordinates(threats[i].col, threats[i].row, board.Cell.own);
        const score = minimax(current_board, 4 - 1, false, alpha, beta);
        current_board.setCellByCoordinates(threats[i].col, threats[i].row, board.Cell.empty);

        if (score > bestScore) {
            bestScore = score;
            bestMove = threats[i];
        }
        alpha = @max(alpha, score);
    }
    return bestMove;
}