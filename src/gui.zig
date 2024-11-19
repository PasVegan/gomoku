const std = @import("std");
const capy = @import("capy");
const board = @import("board.zig");
const start = @import("commands/start.zig");
const turn = @import("commands/turn.zig");


var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var grid_info: struct {
    start_x: i32 = 0,
    start_y: i32 = 0,
    cell_size: i32 = 0,
} = .{};

var game_won: bool = false;

var canva: *capy.Canvas = undefined;

var start_command: []u8 = undefined;


pub fn run_gui() !void {
    try capy.init();

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    var size: [2]u8 = .{'1', '5'};

    if (args.len > 1 and std.mem.eql(u8, "--size", args[1])) {
        const s = std.fmt.parseUnsigned(u8, args[2], 10) catch |err| {
            std.debug.print("Invalid size: {}\n", .{err});
            return;
        };
        if (s > 32 or s < 5) {
            std.debug.print("Invalid size: {}\n", .{s});
            return;
        }
        size[0] = args[2][0];
        size[1] = args[2][1];
    }

    var start_buf = [_]u8{0} ** 10;
    start_command = try std.fmt.bufPrint(&start_buf, "START {s}", .{size});

    try start.handle(start_command, std.io.getStdOut().writer().any());

    var window = try capy.Window.init();
    canva = capy.canvas(.{
        .preferredSize = capy.Size.init(500, 500),
        .ondraw = @as(*const fn (*anyopaque, *capy.DrawContext) anyerror!void, @ptrCast(&onDraw)),
        .name = "zomoku-canvas",
    });
    try canva.addMouseButtonHandler(&onCellClicked);

    try window.set(capy.column(.{.spacing = 10}, .{
        capy.row(.{},.{capy.button(.{ .label = "RESET" , .onclick=resetButton })}),
        capy.expanded(
            capy.row(.{.spacing = 10}, .{
                capy.column(.{}, .{}),
                capy.expanded(
                    canva,
                ),
                capy.column(.{}, .{}),
            }),
        ),
        capy.row(.{},.{}),
    }));

    window.setTitle("Zomoku");
    window.setPreferredSize(500, 500);
    window.show();
    capy.runEventLoop();
}

fn onCellClicked(widget: *capy.Canvas, button: capy.MouseButton, pressed: bool, x: i32, y: i32) !void {
    if (button == .Left and pressed and !game_won) {
        // Calculate which cell was clicked
        const relative_x = x - grid_info.start_x;
        const relative_y = y - grid_info.start_y;

        // Check if click is within grid bounds
        if (relative_x >= 0 and relative_y >= 0) {
            const col = @divFloor(relative_x, grid_info.cell_size);
            const row = @divFloor(relative_y, grid_info.cell_size);

            if (col >= 0 and col < board.game_board.width and
                row >= 0 and row < board.game_board.height) {
                std.debug.print("Clicked on cell ({d}, {d})\n", .{col, row});

                turn.setEnnemyStone(@as(u32, @intCast(col)), @as(u32, @intCast(row))) catch |err| {
                    switch (err) {
                        turn.PlayError.OUTSIDE => std.debug.print("Coordinates are outside the board\n", .{}),
                        turn.PlayError.OCCUPIED => std.debug.print("Cell is not empty\n", .{}),
                    }
                    return;
                };

                if (try board.game_board.addWinningLine(@as(u32, @intCast(col)), @as(u32, @intCast(row)))) {
                    // Request redraw to update the board
                    try widget.requestDraw();
                    game_won = true;
                    return;
                } else {
                    // Request redraw to update the board
                    try widget.requestDraw();
                }

                const ai_move = turn.AIPlay();
                std.debug.print("AI played on cell ({d}, {d})\n", .{ai_move[0], ai_move[1]});

                if (try board.game_board.addWinningLine(ai_move[0], ai_move[1]))
                    game_won = true;

                // Request redraw to update the board
                try widget.requestDraw();
            }
        }
    }
}

fn resetButton(_: *anyopaque) !void {
    try start.handle(start_command, std.io.getStdOut().writer().any());
    game_won = false;
    try canva.requestDraw();
}

fn onDraw(widget: *capy.Canvas, ctx: *capy.DrawContext) !void {
    std.debug.print("Drawing board\n", .{});
    const width = @as(i32, @intCast(widget.getWidth()));
    const height = @as(i32, @intCast(widget.getHeight()));

    // Draw background
    ctx.setColor(0.862745098039, 0.701960784314, 0.360784313725);
    ctx.rectangle(0, 0, @as(u32, @intCast(width)), @as(u32, @intCast(height)));
    ctx.fill();

    // Calculate usable area for the grid
    const min_dimension = @min(width, height);
    const margin: i32 = @divFloor(min_dimension, 50); // Fixed relative margin
    const grid_size = min_dimension - 2 * margin;
    const cell_size = @divFloor(grid_size, @as(i32, @intCast(board.game_board.width)));

    // Recalculate actual grid size and starting position to center the grid
    const actual_grid_size = cell_size * @as(i32, @intCast(board.game_board.width));
    const start_x = @divFloor(width - actual_grid_size, 2);
    const start_y = @divFloor(height - actual_grid_size, 2);

    // Update grid info for mouse handling
    grid_info.start_x = start_x;
    grid_info.start_y = start_y;
    grid_info.cell_size = cell_size;

    // Draw grid lines
    ctx.setColor(0, 0, 0);

    // Vertical lines
    var col: u32 = 0;
    while (col <= board.game_board.width) : (col += 1) {
        const x = start_x + @as(i32, @intCast(col)) * cell_size;
        ctx.line(x, start_y, x, start_y + actual_grid_size);
        ctx.stroke();
    }

    // Horizontal lines
    var row: u32 = 0;
    while (row <= board.game_board.height) : (row += 1) {
        const y = start_y + @as(i32, @intCast(row)) * cell_size;
        ctx.line(start_x, y, start_x + actual_grid_size, y);
        ctx.stroke();
    }

    // Draw stones
    row = 0;
    while (row < board.game_board.height) : (row += 1) {
        col = 0;
        while (col < board.game_board.width) : (col += 1) {
            const cell = board.game_board.getCellByCoordinates(col, row);
            if (cell != .empty) {
                const center_x = start_x + @as(i32, @intCast(col)) * cell_size + @divFloor(cell_size, 2);
                const center_y = start_y + @as(i32, @intCast(row)) * cell_size + @divFloor(cell_size, 2);
                const stone_radius = @divFloor(cell_size * 4, 10); // Make stones slightly smaller than cell

            // Set color based on cell type
            switch (cell) {
                    .opponent => ctx.setColor(0, 0, 0),  // Black stones for own
                .own => ctx.setColor(1, 1, 1),  // White stones for opponent
                .winning_line_or_forbidden => ctx.setColor(1, 0, 0),  // Red for winning/forbidden
                .empty => continue,
                }

                ctx.ellipse(
                    center_x - stone_radius,
                    center_y - stone_radius,
                    @as(u32, @intCast(stone_radius * 2)),
                    @as(u32, @intCast(stone_radius * 2))
                );
                ctx.fill();
            }
        }
    }
}