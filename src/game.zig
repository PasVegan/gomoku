const std = @import("std");
const Coordinates = @import("coordinates.zig").Coordinates(u32);
const Allocator = std.mem.Allocator;

const message = @import("message.zig");

const stdout = std.io.getStdOut().writer();

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

    const EXACT_FIVE: u8 = 1;
    const CONTINUOUS: u8 = 2;
    const RENJU: u8 = 4;
    const CARO: u8 = 8;
    const VALID_MASK: u8 = EXACT_FIVE | CONTINUOUS | RENJU | CARO;

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
    allocator: Allocator,

    /// Method to call to deinitialize the struct.
    pub fn deinit(self: *GameSettings) void {
        self.allocator.free(self.folder);
    }

    /// Method used to parse and set timeout_turn parameter from message.
    fn handleTimeoutTurn(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        // If fails, brain should play as fast as possible.
        self.timeout_turn = std.fmt.parseInt(@TypeOf(self.timeout_turn),
            msg, 10) catch 0;
    }

    /// Method used to parse and set timeout_match parameter from message.
    fn handleTimeoutMatch(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        // If fails, the game have no limit of time.
        self.timeout_match = std.fmt.parseInt(@TypeOf(self.timeout_match),
            msg, 10) catch 0;
    }

    /// Method used to parse and set max_memory parameter from message.
    fn handleMaxMemory(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        // If fails, the game have no limit of memory.
        self.max_memory = std.fmt.parseInt(@TypeOf(self.max_memory),
            msg, 10) catch 0;
    }

    /// Method used to parse and set time_left parameter from message.
    fn handleTimeLeft(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        // If fails, the time left doesn't change.
        self.time_left = std.fmt.parseInt(@TypeOf(self.time_left),
            msg, 10) catch self.time_left;
    }

    /// Method used to parse and set game_type parameter from message.
    fn handleGameType(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        // If fails, the game type doesn't change.
        const number = std.fmt.parseInt(u8, msg, 10) catch {
            return;
        };

        // If valid, modify the attribute.
        if (GameType.isValid(number)) {
            self.game_type = @enumFromInt(number);
            return;
        }
    }

    /// Method used to parse and set rule parameter from message.
    fn handleRule(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        // If fails, the game rule doesn't change.
        const number = std.fmt.parseInt(u8, msg, 10) catch {
            return;
        };

        // Verify no invalid bits are set
        if (number & ~GameRule.VALID_MASK != 0) {
            return;
        }

        // Verify Renju and Caro are not set simultaneously
        if ((number & GameRule.RENJU != 0) and (number & GameRule.CARO != 0)) {
            return;
        }

        self.rule = GameRule.init(number);
    }

    /// Method used to parse and set folder parameter from message.
    fn handleFolder(self: *GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
        _ = writer;
        if (self.folder.len > 0) {
            self.allocator.free(self.folder);
        }
        self.folder = self.allocator.dupe(u8, msg) catch {
            self.folder = "";
            return;
        };
    }
};

/// Structure representing the command mapping.
/// - Attributes:
///     - cmd: The command.
///     - func: The associated function to call on command.
const InfoCommandMapping = struct {
    cmd: []const u8,
    func: *const fn (*GameSettings, []const u8, std.io.AnyWriter) void,
};

/// Map of pointer on function (info commands).
const infoCommandMappings: []const InfoCommandMapping = &[_]InfoCommandMapping{
    .{ .cmd = "timeout_turn", .func = GameSettings.handleTimeoutTurn },
    .{ .cmd = "timeout_match", .func = GameSettings.handleTimeoutMatch },
    .{ .cmd = "max_memory", .func = GameSettings.handleMaxMemory },
    .{ .cmd = "time_left", .func = GameSettings.handleTimeLeft },
    .{ .cmd = "game_type", .func = GameSettings.handleGameType },
    .{ .cmd = "rule", .func = GameSettings.handleRule },
    .{ .cmd = "folder", .func = GameSettings.handleFolder },
};

/// Function used to handle info commands.
/// - Parameters:
///     - cmd: An info command to executes.
pub fn handleInfoCommand(cmd: []const u8, writer: std.io.AnyWriter) void {
    for (infoCommandMappings) |mapping| {
        // Verifying if there is
        if (std.ascii.startsWithIgnoreCase(cmd, mapping.cmd)) {
            // Calculating the command offset with the command lenght plus a
            // space.
            const command_offset = mapping.cmd.len + 1;
            // Verifying the command lenght.
            if (cmd.len <= command_offset)
                return;
            return @call(.auto, mapping.func, .{
                &gameSettings,
                cmd[command_offset..],
                writer
            });
        }
    }
}

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
    .allocator = std.heap.page_allocator,
};

test "GameType.isValid" {
    const testing = std.testing;

    // Test valid values
    try testing.expect(GameType.isValid(0));
    try testing.expect(GameType.isValid(1));
    try testing.expect(GameType.isValid(2));
    try testing.expect(GameType.isValid(3));

    // Test invalid values
    try testing.expect(!GameType.isValid(4));
    try testing.expect(!GameType.isValid(255));
}

test "GameRule" {
    const testing = std.testing;

    // Test individual rules.
    const rule1 = GameRule.init(1);
    try testing.expect(rule1.hasExactFive());
    try testing.expect(!rule1.isContinuous());
    try testing.expect(!rule1.isRenju());
    try testing.expect(!rule1.isCaro());

    // Test combined rules.
    const rule6 = GameRule.init(6); // Continuous (2) + Renju (4)
    try testing.expect(!rule6.hasExactFive());
    try testing.expect(rule6.isContinuous());
    try testing.expect(rule6.isRenju());
    try testing.expect(!rule6.isCaro());

    // Test all rules.
    const ruleAll = GameRule.init(15); // 1 + 2 + 4 + 8
    try testing.expect(ruleAll.hasExactFive());
    try testing.expect(ruleAll.isContinuous());
    try testing.expect(ruleAll.isRenju());
    try testing.expect(ruleAll.isCaro());
}

test "GameSettings basic initialization" {
    const testing = std.testing;
    const settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };

    try testing.expectEqual(@as(u64, 0), settings.timeout_turn);
    try testing.expectEqual(@as(u64, 0), settings.turn_time);
    try testing.expectEqual(@as(u64, 0), settings.current_time);
    try testing.expectEqual(@as(u64, 0), settings.timeout_match);
    try testing.expectEqual(@as(u64, 0), settings.max_memory);
    try testing.expectEqual(@as(i32, 2147483647), settings.time_left);
    try testing.expectEqual(GameType.opponent_is_human, settings.game_type);
    try testing.expectEqual(@as(u8, 0), settings.rule.rule);
    try testing.expectEqualStrings("", settings.folder);
    try testing.expect(!settings.started);
}

test "GameSettings handle timeout commands" {
    const testing = std.testing;
    var settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };
    defer settings.deinit();

    // Test valid timeout_turn
    settings.handleTimeoutTurn("5000", stdout.any());
    try testing.expectEqual(@as(u64, 5000), settings.timeout_turn);

    // Test invalid timeout_turn (should default to 0)
    settings.handleTimeoutTurn("invalid", stdout.any());
    try testing.expectEqual(@as(u64, 0), settings.timeout_turn);

    // Test valid timeout_match
    settings.handleTimeoutMatch("10000", stdout.any());
    try testing.expectEqual(@as(u64, 10000), settings.timeout_match);

    // Test invalid timeout_match (should default to 0)
    settings.handleTimeoutMatch("invalid", stdout.any());
    try testing.expectEqual(@as(u64, 0), settings.timeout_match);
}

test "GameSettings handle memory and time commands" {
    const testing = std.testing;
    var settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };
    defer settings.deinit();

    // Test max_memory
    settings.handleMaxMemory("1048576", stdout.any());
    try testing.expectEqual(@as(u64, 1048576), settings.max_memory);

    // Test invalid max_memory (should default to 0)
    settings.handleMaxMemory("invalid", stdout.any());
    try testing.expectEqual(@as(u64, 0), settings.max_memory);

    // Test time_left
    settings.handleTimeLeft("30000", stdout.any());
    try testing.expectEqual(@as(i32, 30000), settings.time_left);

    // Test invalid time_left (should keep previous value)
    const previous_time_left = settings.time_left;
    settings.handleTimeLeft("invalid", stdout.any());
    try testing.expectEqual(previous_time_left, settings.time_left);
}

test "GameSettings handle game type and rule" {
    const testing = std.testing;
    var settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };
    defer settings.deinit();

    // Test game_type
    settings.handleGameType("1", stdout.any());
    try testing.expectEqual(GameType.opponent_is_brain, settings.game_type);

    // Test rule
    settings.handleRule("7", stdout.any()); // 1 + 2 + 4 (exact five + continuous + renju)
    try testing.expect(settings.rule.hasExactFive());
    try testing.expect(settings.rule.isContinuous());
    try testing.expect(settings.rule.isRenju());
    try testing.expect(!settings.rule.isCaro());
}

test "GameSettings invalid game type" {
    const testing = std.testing;
    var settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };
    defer settings.deinit();

    // Test invalid game type
    const original_type = settings.game_type;
    settings.handleGameType("4", stdout.any());
    try testing.expectEqual(original_type, settings.game_type);

    // Test invalid format
    settings.handleGameType("invalid", stdout.any());
    try testing.expectEqual(original_type, settings.game_type);
}

test "GameSettings invalid rule combinations" {
    const testing = std.testing;
    var settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };
    defer settings.deinit();

    // Test Renju + Caro combination (invalid)
    const original_rule = settings.rule.rule;
    settings.handleRule("12", stdout.any()); // 4 + 8 (Renju + Caro)
    try testing.expectEqual(original_rule, settings.rule.rule);

    // Test invalid bits
    settings.handleRule("16", stdout.any()); // Invalid bit
    try testing.expectEqual(original_rule, settings.rule.rule);

    // Test invalid format
    settings.handleRule("invalid", stdout.any());
    try testing.expectEqual(original_rule, settings.rule.rule);
}

test "GameSettings handle folder" {
    const testing = std.testing;
    var settings = GameSettings{
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
        .allocator = std.heap.page_allocator,
    };
    defer settings.deinit();

    // Test folder setting
    settings.handleFolder("/test/path", stdout.any());
    try testing.expectEqualStrings("/test/path", settings.folder);

    // Test changing folder
    settings.handleFolder("/new/path", stdout.any());
    try testing.expectEqualStrings("/new/path", settings.folder);
}

test "GameSettings handle failing allocation on folder modification" {
    const testing = std.testing;
    // Create a failing allocator that fails after N allocations
    var failing_allocator = testing.FailingAllocator.init(
        testing.allocator, .{.fail_index = 1}
    ); // Will fail after 1 successful allocation.
    var settings = GameSettings{
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
        .allocator = failing_allocator.allocator(),
    };
    defer settings.deinit();

    // First allocation should succeed.
    settings.handleFolder("/test/path", stdout.any());
    try testing.expectEqualStrings("/test/path", settings.folder);

    // Second allocation should fail.
    settings.handleFolder("/new/path", stdout.any());
    try testing.expectEqualStrings("", settings.folder);
}

test "handleInfoCommand" {
    const testing = std.testing;

    // Test valid commands
    handleInfoCommand("timeout_turn 5000", stdout.any());
    try testing.expectEqual(@as(u64, 5000), gameSettings.timeout_turn);

    handleInfoCommand("game_type 1", stdout.any());
    try testing.expectEqual(GameType.opponent_is_brain, gameSettings.game_type);

    // Test invalid command
    const original_type = gameSettings.game_type;
    handleInfoCommand("invalid_command 1", stdout.any());
    try testing.expectEqual(original_type, gameSettings.game_type);

    // Test command without parameter
    handleInfoCommand("timeout_turn", stdout.any());
    try testing.expectEqual(@as(u64, 5000), gameSettings.timeout_turn);
}
