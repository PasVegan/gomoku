const std = @import("std");
const main = @import("../main.zig");

pub fn handle(_: []const u8, _: std.io.AnyWriter) !void {
    main.should_stop = true;
}

test "handleEnd command" {
    main.should_stop = false;
    try handle("", undefined);
    try std.testing.expect(main.should_stop);
}
