const testing = @import("std").testing;

pub const about = @import("about.zig");
pub const begin = @import("begin.zig");
pub const board = @import("board.zig");
pub const end = @import("end.zig");
pub const info = @import("info.zig");
pub const start = @import("start.zig");
pub const turn = @import("turn.zig");

test {
    testing.refAllDecls(@This());
}