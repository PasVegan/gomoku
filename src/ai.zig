const Coordinates = @import("coordinates.zig").Coordinates(u32);
const board = @import("board.zig");
const std = @import("std");
const zobrist = @import("zobrist.zig");

// Represents a potential move with its position and evaluation score
pub const Threat = struct {
    row: u16,
    col: u16,
    score: i32,
};

// Evaluates a single direction from a given position for potential threats
// Returns a score based on the number of consecutive pieces and spaces found
fn evaluateDirection(map: []board.Cell, col: u32, row: u32, dx: i32, dy: i32, comptime player: board.Cell, size: u32) i32 {
    // Determine the opponent's cell type
    const opponent = comptime if (player == board.Cell.own) board.Cell.opponent else board.Cell.own;

    @setRuntimeSafety(false);

    // Convert board coordinates to integer values for calculations
    const base_row: i32 = @as(i32, @intCast(row));
    const base_col: i32 = @as(i32, @intCast(col));

    // Track consecutive pieces and empty spaces
    var count: u8 = 1;  // Start at 1 for the current position
    var space: u8 = 0;  // Count empty spaces

    // Check 4 positions in the given direction
    inline for ([_]i32{1,2,3,4}) |i| {
        const row_direction = dx * i;
        const col_direction = dy * i;
        const newRow = base_row + row_direction;
        const newCol = base_col + col_direction;
        const index: u32 = @as(u32, @bitCast(newRow)) * size + @as(u32, @bitCast(newCol));

        // Check if position is within board boundaries
        if (newRow < 0 or newCol < 0 or index >= (size * size))
            return 0;

        const cell_content = map[index];
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
pub fn evaluateMove(current_board: []board.Cell, col: u32, row: u32, comptime player: board.Cell, size: u32) i32 {
    var score: i32 = 0;
    // Evaluate all 8 directions and sum the scores dx = row, dy = col
    score += evaluateDirection(current_board, col, row, 1, 0, player, size); // bottom
    score += evaluateDirection(current_board, col, row, 0, 1, player, size); // right
    score += evaluateDirection(current_board, col, row, 1, 1, player, size); // bottom right
    score += evaluateDirection(current_board, col, row, 1, -1, player, size); // bottom left

    score += evaluateDirection(current_board, col, row, -1, 0, player, size); // top
    score += evaluateDirection(current_board, col, row, 0, -1, player, size); // left
    score += evaluateDirection(current_board, col, row, -1, -1, player, size); // top left
    score += evaluateDirection(current_board, col, row, -1, 1, player, size); // top right

    return score;
}

// Comparison function for sorting threats by score in descending order
fn compareThreatsByScore(_: void, a: Threat, b: Threat) bool {
    return b.score < a.score;
}

// Finds all potential threats on the board for a given player
pub fn findThreats(map: []board.Cell, threats: []Threat, comptime player: board.Cell, size: u32) u16 {
    var nb_threats: u16 = 0;

    // Scan entire board for empty cells
    var row: u16 = 0;
    while (row < size) : (row += 1) {
        var col: u16 = 0;
        const row_offset = row * size;
        while (col < size) : (col += 1) {
            const index = row_offset + col;
            if (map[index] == board.Cell.empty) {
                // Evaluate empty position
                const score = evaluateMove(map, col, row, player, size);
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
fn evaluatePosition(map: []board.Cell, comptime size: u32) i32 {
    var score: i32 = 0;

    // Evaluate all pieces on the board
    comptime var row: u16 = 0;
    inline while (row < size) : (row += 1) {
        comptime var col: u16 = 0;
        const row_offset = comptime row * size;
        inline while (col < size) : (col += 1) {
            const cell = map[row_offset + col];
            if (cell != board.Cell.empty) {
                // Add score for own pieces, subtract for opponent's
                if (cell == board.Cell.own) {
                    score += evaluateMove(map, col, row, board.Cell.own, size);
                } else {
                    score -= evaluateMove(map, col, row, board.Cell.opponent, size);
                }
            }
        }
    }
    return score;
}

// Minimax algorithm with alpha-beta pruning and transposition table
pub fn minimax(map: []board.Cell, zobrist_table: *zobrist.ZobristTable, depth: u8, comptime isMaximizing: bool,
    alpha_in: i32, beta_in: i32, comptime size: u32) i32 {
    // Check transposition table
    if (zobrist_table.lookupPosition(depth, alpha_in, beta_in)) |cached_score| {
        return cached_score;
    }

    // Base case: evaluate position when depth is reached
    if (depth == 0) {
        const score = evaluatePosition(map, size);
        zobrist_table.storePosition(depth, score, .EXACT);
        return score;
    }

    var threats: [size * size]Threat = undefined;
    const player = comptime if (isMaximizing) board.Cell.own else board.Cell.opponent;
    const nb_threats = findThreats(map, &threats, player, size);

    if (isMaximizing) {
        // Maximizing player's turn
        var maxScore: i32 = std.math.minInt(i32);
        var alpha = alpha_in;
        var i: u16 = 0;
        while (i < nb_threats) : (i += 1) {
            const index = threats[i].row * size + threats[i].col;
            map[index] = board.Cell.own;
            zobrist_table.updateHash(board.Cell.own, threats[i].row, threats[i].col);

            const score = minimax(map, zobrist_table, depth - 1, false, alpha, beta_in, size);

            map[index] = board.Cell.empty;
            zobrist_table.updateHash(board.Cell.own, threats[i].row, threats[i].col); // XOR again to undo

            maxScore = @max(maxScore, score);
            alpha = @max(alpha, score);

            if (beta_in <= alpha) {
                zobrist_table.storePosition(depth, maxScore, .LOWERBOUND);
                break; // Beta cutoff
            }
        }
        zobrist_table.storePosition(depth, maxScore, .EXACT);
        return maxScore;
    } else {
        // Minimizing player's turn
        var minScore: i32 = std.math.maxInt(i32);
        var beta = beta_in;
        var i: u16 = 0;
        while (i < nb_threats) : (i += 1) {
            const index = threats[i].row * size + threats[i].col;
            map[index] = board.Cell.opponent;
            zobrist_table.updateHash(board.Cell.opponent, threats[i].row, threats[i].col);

            const score = minimax(map, zobrist_table, depth - 1, true, alpha_in, beta, comptime size);

            map[index] = board.Cell.empty;
            zobrist_table.updateHash(board.Cell.opponent, threats[i].row, threats[i].col); // XOR again to undo

            minScore = @min(minScore, score);
            beta = @min(beta, score);

            if (beta <= alpha_in) {
                zobrist_table.storePosition(depth, minScore, .UPPERBOUND);
                break; // Alpha cutoff
            }
        }
        zobrist_table.storePosition(depth, minScore, .EXACT);
        return minScore;
    }
}

// Finds the best move for the AI using minimax algorithm, zobrist transposition table
pub fn findBestMove(comptime size: comptime_int) Threat {
    var current_board = &board.game_board;
    var bestScore: i32 = std.math.minInt(i32);
    var bestMove: Threat = Threat{ .row = 0, .col = 0, .score = 0 };
    var threats: [size * size]Threat = undefined;

    _ = zobrist.ztable.calculateHash(current_board.map);

    const nb_threats = findThreats(current_board.map, &threats, board.Cell.own, comptime size);

    // Check for immediate winning moves
    var i: u16 = 0;
    while (i < nb_threats) : (i += 1) {
        if (threats[i].score >= 100000) {
            return threats[i];
        }
    }

    // Use minimax to evaluate moves
    var alpha: i32 = std.math.minInt(i32);
    const beta: i32 = std.math.maxInt(i32);

    i = 0;
    while (i < nb_threats) : (i += 1) {
        current_board.setCellByCoordinates(threats[i].col, threats[i].row, board.Cell.own);
        zobrist.ztable.updateHash(board.Cell.own, threats[i].row, threats[i].col);

        const score = minimax(current_board.map, &zobrist.ztable, 4 - 1, false, alpha, beta, comptime size);

        current_board.setCellByCoordinates(threats[i].col, threats[i].row, board.Cell.empty);
        zobrist.ztable.updateHash(board.Cell.own, threats[i].row, threats[i].col);

        if (score > bestScore) {
            bestScore = score;
            bestMove = threats[i];
        }
        alpha = @max(alpha, score);
    }
    return bestMove;
}

pub fn getBotMove5() Threat {
    return findBestMove(5);
}
pub fn getBotMove6() Threat {
    return findBestMove(6);
}
pub fn getBotMove7() Threat {
    return findBestMove(7);
}
pub fn getBotMove8() Threat {
    return findBestMove(8);
}
pub fn getBotMove9() Threat {
    return findBestMove(9);
}
pub fn getBotMove10() Threat {
    return findBestMove(10);
}
pub fn getBotMove11() Threat {
    return findBestMove(11);
}
pub fn getBotMove12() Threat {
    return findBestMove(12);
}
pub fn getBotMove13() Threat {
    return findBestMove(13);
}
pub fn getBotMove14() Threat {
    return findBestMove(14);
}
pub fn getBotMove15() Threat {
    return findBestMove(15);
}
pub fn getBotMove16() Threat {
    return findBestMove(16);
}
pub fn getBotMove17() Threat {
    return findBestMove(17);
}
pub fn getBotMove18() Threat {
    return findBestMove(18);
}
pub fn getBotMove19() Threat {
    return findBestMove(19);
}
pub fn getBotMove20() Threat {
    return findBestMove(20);
}
