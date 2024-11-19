const std = @import("std");
const Coordinates = @import("coordinates.zig").Coordinates(u32);
const message = @import("message.zig");

// Global variable holding game settings.
pub var gameSettings = GameSettings{
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

/// Enumeration representing the game types.
pub const GameType = enum(u8) {
    opponent_is_human = 0, // The opponent is an human.
    opponent_is_brain = 1, // The opponent is a brain.
    tournament = 2, // The game is in tournament mode.
    network_tournament = 3, // The game is in network tournament mode.

    /// Helper function to check if a value is a valid GameType.
    pub fn isValid(value: u8) bool {
        return switch (value) {
            0...3 => true,
            else => false,
        };
    }
};

/// Structure representing the actual game rule.
/// - Notes:
///     - (from protocol) bitmask or sum of :
///         - 1 = exactly five in a row win
///         - 2 = continuous game
///         - 4 = renju
///         - 8 = caro
pub const GameRule = struct {
    rule: u8,

    pub const EXACT_FIVE: u8 = 1;
    pub const CONTINUOUS: u8 = 2;
    pub const RENJU: u8 = 4;
    pub const CARO: u8 = 8;
    pub const VALID_MASK: u8 = EXACT_FIVE | CONTINUOUS | RENJU | CARO;

    pub fn init(rule: u8) GameRule {
        return GameRule{ .rule = rule };
    }

    pub fn hasExactFive(self: GameRule) bool {
        return (self.rule & 1) != 0;
    }

    pub fn isContinuous(self: GameRule) bool {
        return (self.rule & 2) != 0;
    }

    pub fn isRenju(self: GameRule) bool {
        return (self.rule & 4) != 0;
    }

    pub fn isCaro(self: GameRule) bool {
        return (self.rule & 8) != 0;
    }
};

/// Structure representing the game settings.
///     - timeout_turn: Time limit for each move.
///     - current_time: Stock the current time spent.
///     - timeout_match: Time limit of a whole match in milliseconds.
///         0 = no limit
///     - max_memory: Memory limit in bytes.
///         0 = no limit
///     - time_left: Remaining time limit of a whole match in milliseconds.
///     - game_type: The type of the game. See GameType enumeration.
///     - rule: The game rule. See GameRule structure.
///     - folder: Folder for persistent files.
///     - started: Stocking if the game already started.
pub const GameSettings = struct {
    /// Sent before the first move (after or before START command).
    /// Turn limit equal to zero means that the brain should play
    /// as fast as possible (eg count only a static evaluation and
    /// don't search possible moves).
    timeout_turn: u64,
    /// Time for a turn includes processing of all commands
    /// except initialization (commands START, RECTSTART, RESTART).
    turn_time: u64,
    /// Time for a match is measured from creating a process to the
    /// end of a game (but not during opponent's turn).
    current_time: u64 = 0,
    /// Sent before the first move (after or before START command).
    timeout_match: u64 = 0,
    // max_memory is sent before the first move (after or before START
    // command).
    max_memory: u64 = 0,
    // The manager is required to send info time_left if the time is limited,
    // so that the brain can ignore info timeout_match and only rely
    // on info time_left.
    time_left: i32 = 2147483647, // If the time for a whole match is unlimited.
    game_type: GameType,
    rule: GameRule,
    /// Folder is used to determine a folder for files that are permanent.
    /// Because this folder is common for all brains and maybe other
    /// applications, the brain must create its own subfolder which name
    /// must be the same as the name of the brain.
    /// If the manager does not send INFO folder, then the brain
    /// cannot store permanent files.
    folder: []u8,
    started: bool,
    allocator: std.mem.Allocator,

    /// Method to call to deinitialize the struct.
    pub fn deinit(self: *GameSettings) void {
        self.allocator.free(self.folder);
    }
};
