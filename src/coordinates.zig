const std = @import("std");

/// # Structure representing coordinates.
/// - Attributes:
///     - T: The type of the coordinates.
pub fn Coordinates(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}
