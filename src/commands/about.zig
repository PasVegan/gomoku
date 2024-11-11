const std = @import("std");
const message = @import("../message.zig");

/// Function used to handle the about command.
/// - Behavior:
///     - Sending basic informations about the bot.
pub fn handle(_: []const u8, writer: std.io.AnyWriter) !void {
    const bot_name = "TNBC";
    const about_answer = "name=\"" ++ bot_name ++ "\", version=\"0.1\"";

    return message.sendMessageComptime(about_answer, writer);
}

// Test command handlers
test "handleAbout command" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try handle("", list.writer().any());
    try std.testing.expectEqualStrings("name=\"TNBC\", version=\"0.1\"\n", list.items);
}
