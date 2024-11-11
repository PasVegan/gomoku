const std = @import("std");
const game = @import("../game.zig");
const message = @import("../message.zig");
const main = @import("../main.zig");

const stdout = std.io.getStdOut().writer();

/// Method used to parse and set timeout_turn parameter from message.
fn handleTimeoutTurn(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    // If fails, brain should play as fast as possible.
    game_settings.timeout_turn = std.fmt.parseInt(@TypeOf(game_settings.timeout_turn),
    msg, 10) catch 0;
}

/// Method used to parse and set timeout_match parameter from message.
fn handleTimeoutMatch(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    // If fails, the game have no limit of time.
    game_settings.timeout_match = std.fmt.parseInt(@TypeOf(game_settings.timeout_match),
    msg, 10) catch 0;
}

/// Method used to parse and set max_memory parameter from message.
fn handleMaxMemory(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    // If fails, the game have no limit of memory.
    game_settings.max_memory = std.fmt.parseInt(@TypeOf(game_settings.max_memory),
    msg, 10) catch 0;
}

/// Method used to parse and set time_left parameter from message.
fn handleTimeLeft(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    // If fails, the time left doesn't change.
    game_settings.time_left = std.fmt.parseInt(@TypeOf(game_settings.time_left),
    msg, 10) catch game_settings.time_left;
}

/// Method used to parse and set game_type parameter from message.
fn handleGameType(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    // If fails, the game type doesn't change.
        const number = std.fmt.parseInt(u8, msg, 10) catch {
        return;
    };
    
        // If valid, modify the attribute.
        if (game.GameType.isValid(number)) {
        game_settings.game_type = @enumFromInt(number);
        return;
    }
}

/// Method used to parse and set rule parameter from message.
fn handleRule(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    // If fails, the game rule doesn't change.
        const number = std.fmt.parseInt(u8, msg, 10) catch {
        return;
    };

    // Verify no invalid bits are set
        if (number & ~game.GameRule.VALID_MASK != 0) {
        return;
    }

    // Verify Renju and Caro are not set simultaneously
        if ((number & game.GameRule.RENJU != 0) and (number & game.GameRule.CARO != 0)) {
        return;
    }

    game_settings.rule = game.GameRule.init(number);
}

/// Method used to parse and set folder parameter from message.
fn handleFolder(game_settings: *game.GameSettings, msg: []const u8, writer: std.io.AnyWriter) void {
    _ = writer;
    if (game_settings.folder.len > 0) {
        game_settings.allocator.free(game_settings.folder);
    }
    game_settings.folder = game_settings.allocator.dupe(u8, msg) catch {
        game_settings.folder = "";
        return;
    };
}


/// Structure representing the command mapping.
/// - Attributes:
///     - cmd: The command.
///     - func: The associated function to call on command.
const InfoCommandMapping = struct {
    cmd: []const u8,
    func: *const fn (*game.GameSettings, []const u8, std.io.AnyWriter) void,
};

/// Map of pointer on function (info commands).
const infoCommandMappings: []const InfoCommandMapping = &[_]InfoCommandMapping{
    .{ .cmd = "timeout_turn", .func = handleTimeoutTurn },
    .{ .cmd = "timeout_match", .func = handleTimeoutMatch },
    .{ .cmd = "max_memory", .func = handleMaxMemory },
    .{ .cmd = "time_left", .func = handleTimeLeft },
    .{ .cmd = "game_type", .func = handleGameType },
    .{ .cmd = "rule", .func = handleRule },
    .{ .cmd = "folder", .func = handleFolder },
};

pub fn handle(msg: []const u8, writer: std.io.AnyWriter) !void {
    // Skip "INFO ".
    if (msg.len <= 5) {
        // Ignore it, it is probably not important. (Protocol)
        return;
    }
    // Parse while removing the "INFO " bytes.
    for (infoCommandMappings) |mapping| {
        // Verifying if there is
        if (std.ascii.startsWithIgnoreCase(msg[5..], mapping.cmd)) {
            // Calculating the command offset with the command lenght plus a
            // space.
            const command_offset = mapping.cmd.len + 1;
            // Verifying the command lenght.
            if (msg[5..].len <= command_offset)
                return;
            return @call(.auto, mapping.func, .{
                &game.gameSettings,
                msg[5 + command_offset..],
                writer
            });
        }
    }
    return;
}

test "GameType.isValid" {
    const testing = std.testing;

    // Test valid values
    try testing.expect(game.GameType.isValid(0));
    try testing.expect(game.GameType.isValid(1));
    try testing.expect(game.GameType.isValid(2));
    try testing.expect(game.GameType.isValid(3));

    // Test invalid values
    try testing.expect(!game.GameType.isValid(4));
    try testing.expect(!game.GameType.isValid(255));
}

test "GameRule" {
    const testing = std.testing;

    // Test individual rules.
    const rule1 = game.GameRule.init(1);
    try testing.expect(rule1.hasExactFive());
    try testing.expect(!rule1.isContinuous());
    try testing.expect(!rule1.isRenju());
    try testing.expect(!rule1.isCaro());

    // Test combined rules.
    const rule6 = game.GameRule.init(6); // Continuous (2) + Renju (4)
    try testing.expect(!rule6.hasExactFive());
    try testing.expect(rule6.isContinuous());
    try testing.expect(rule6.isRenju());
    try testing.expect(!rule6.isCaro());

    // Test all rules.
    const ruleAll = game.GameRule.init(15); // 1 + 2 + 4 + 8
    try testing.expect(ruleAll.hasExactFive());
    try testing.expect(ruleAll.isContinuous());
    try testing.expect(ruleAll.isRenju());
    try testing.expect(ruleAll.isCaro());
}

test "GameSettings basic initialization" {
    const testing = std.testing;
    const settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };

    try testing.expectEqual(@as(u64, 0), settings.timeout_turn);
    try testing.expectEqual(@as(u64, 0), settings.turn_time);
    try testing.expectEqual(@as(u64, 0), settings.current_time);
    try testing.expectEqual(@as(u64, 0), settings.timeout_match);
    try testing.expectEqual(@as(u64, 0), settings.max_memory);
    try testing.expectEqual(@as(i32, 2147483647), settings.time_left);
    try testing.expectEqual(game.GameType.opponent_is_human, settings.game_type);
    try testing.expectEqual(@as(u8, 0), settings.rule.rule);
    try testing.expectEqualStrings("", settings.folder);
    try testing.expect(!settings.started);
}

test "GameSettings handle timeout commands" {
    const testing = std.testing;
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };
    defer settings.deinit();

    // Test valid timeout_turn
    handleTimeoutTurn(&settings, "5000", stdout.any());
    try testing.expectEqual(@as(u64, 5000), settings.timeout_turn);

    // Test invalid timeout_turn (should default to 0)
    handleTimeoutTurn(&settings, "invalid", stdout.any());
    try testing.expectEqual(@as(u64, 0), settings.timeout_turn);

    // Test valid timeout_match
    handleTimeoutMatch(&settings, "10000", stdout.any());
    try testing.expectEqual(@as(u64, 10000), settings.timeout_match);

    // Test invalid timeout_match (should default to 0)
    handleTimeoutMatch(&settings, "invalid", stdout.any());
    try testing.expectEqual(@as(u64, 0), settings.timeout_match);
}

test "GameSettings handle memory and time commands" {
    const testing = std.testing;
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };
    defer settings.deinit();

    // Test max_memory
    handleMaxMemory(&settings, "1048576", stdout.any());
    try testing.expectEqual(@as(u64, 1048576), settings.max_memory);

    // Test invalid max_memory (should default to 0)
    handleMaxMemory(&settings, "invalid", stdout.any());
    try testing.expectEqual(@as(u64, 0), settings.max_memory);

    // Test time_left
    handleTimeLeft(&settings, "30000", stdout.any());
    try testing.expectEqual(@as(i32, 30000), settings.time_left);

    // Test invalid time_left (should keep previous value)
    const previous_time_left = settings.time_left;
    handleTimeLeft(&settings, "invalid", stdout.any());
    try testing.expectEqual(previous_time_left, settings.time_left);
}

test "GameSettings handle game type and rule" {
    const testing = std.testing;
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };
    defer settings.deinit();

    // Test game_type
    handleGameType(&settings, "1", stdout.any());
    try testing.expectEqual(game.GameType.opponent_is_brain, settings.game_type);

    // Test rule
    handleRule(&settings, "7", stdout.any()); // 1 + 2 + 4 (exact five + continuous + renju)
    try testing.expect(settings.rule.hasExactFive());
    try testing.expect(settings.rule.isContinuous());
    try testing.expect(settings.rule.isRenju());
    try testing.expect(!settings.rule.isCaro());
}

test "GameSettings invalid game type" {
    const testing = std.testing;
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };
    defer settings.deinit();

    // Test invalid game type
    const original_type = settings.game_type;
    handleGameType(&settings, "4", stdout.any());
    try testing.expectEqual(original_type, settings.game_type);

    // Test invalid format
    handleGameType(&settings, "invalid", stdout.any());
    try testing.expectEqual(original_type, settings.game_type);
}

test "GameSettings invalid rule combinations" {
    const testing = std.testing;
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };
    defer settings.deinit();

    // Test Renju + Caro combination (invalid)
    const original_rule = settings.rule.rule;
    handleRule(&settings, "12", stdout.any()); // 4 + 8 (Renju + Caro)
    try testing.expectEqual(original_rule, settings.rule.rule);

    // Test invalid bits
    handleRule(&settings, "16", stdout.any()); // Invalid bit
    try testing.expectEqual(original_rule, settings.rule.rule);

    // Test invalid format
    handleRule(&settings, "invalid", stdout.any());
    try testing.expectEqual(original_rule, settings.rule.rule);
}

test "GameSettings handle folder" {
    const testing = std.testing;
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = testing.allocator,
    };
    defer settings.deinit();

    // Test folder setting
    handleFolder(&settings, "/test/path", stdout.any());
    try testing.expectEqualStrings("/test/path", settings.folder);

    // Test changing folder
    handleFolder(&settings, "/new/path", stdout.any());
    try testing.expectEqualStrings("/new/path", settings.folder);
}

test "GameSettings handle failing allocation on folder modification" {
    const testing = std.testing;
    // Create a failing allocator that fails after N allocations
    var failing_allocator = testing.FailingAllocator.init(
        testing.allocator, .{.fail_index = 1}
    ); // Will fail after 1 successful allocation.
    var settings = game.GameSettings{
        .timeout_turn = 0,
        .turn_time = 0,
        .current_time = 0,
        .timeout_match = 0,
        .max_memory = 0,
        .time_left = 2147483647,
        .game_type = .opponent_is_human,
        .rule = game.GameRule{ .rule = 0 },
        .folder = "",
        .started = false,
        .allocator = failing_allocator.allocator(),
    };
    defer settings.deinit();

    // First allocation should succeed.
    handleFolder(&settings, "/test/path", stdout.any());
    try testing.expectEqualStrings("/test/path", settings.folder);

    // Second allocation should fail.
    handleFolder(&settings, "/new/path", stdout.any());
    try testing.expectEqualStrings("", settings.folder);
}

test "handleInfoCommand" {
    const testing = std.testing;

    // Test valid commands
    try handle("INFO timeout_turn 5000", stdout.any());
    try testing.expectEqual(@as(u64, 5000), game.gameSettings.timeout_turn);

    try handle("INFO game_type 1", stdout.any());
    try testing.expectEqual(game.GameType.opponent_is_brain, game.gameSettings.game_type);

    // Test invalid command
    const original_type = game.gameSettings.game_type;
    try handle("INFO invalid_command 1", stdout.any());
    try testing.expectEqual(original_type, game.gameSettings.game_type);

    // Test command without parameter
    try handle("INFO timeout_turn", stdout.any());
    try testing.expectEqual(@as(u64, 5000), game.gameSettings.timeout_turn);
}

test "handleInfo command invalid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("INFO", list.writer().any());
    try std.testing.expectEqualStrings("", list.items);
}

test "handleInfo command valid input" {
    main.allocator = std.testing.allocator;
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    message.init(main.allocator);

    try handle("INFO timeout_turn 6000", list.writer().any());
    try std.testing.expectEqualStrings("", list.items);
    try std.testing.expectEqual(6000, game.gameSettings.timeout_turn);
}
