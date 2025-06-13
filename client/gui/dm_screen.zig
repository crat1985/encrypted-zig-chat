const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const messgaes = @import("messages.zig");
const txt_input = @import("text_input.zig");
const std = @import("std");

const allocator = std.heap.page_allocator;

pub fn ask_message(my_id: [32]u8, dm: [32]u8) ![]u8 {
    var message = try allocator.allocSentinel(u8, 0, 0);

    while (true) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @intCast(C.GetScreenWidth());
        GUI.HEIGHT = @intCast(C.GetScreenHeight());

        try @import("id_top_left_display.zig").draw_id_top_left_display(my_id);

        try draw_close_dm_button();
    }
}

fn draw_close_dm_button() !void {
    const SIDE = 25;
    const OFFSET = 5;

    const close_button_rect = C.Rectangle{
        .x = @floatFromInt(GUI.WIDTH - SIDE),
        .y = 0,
        .width = SIDE,
        .height = SIDE,
    };

    C.DrawLine(@intFromFloat(close_button_rect.x + OFFSET), OFFSET, @intCast(GUI.WIDTH - OFFSET), SIDE + OFFSET, C.WHITE);
    C.DrawLine(@intFromFloat(close_button_rect.x + OFFSET), SIDE + OFFSET, @intCast(GUI.WIDTH - OFFSET), OFFSET, C.WHITE);

    if (C.CheckCollisionPointRec(C.GetMousePosition(), close_button_rect)) {
        C.SetMouseCursor(C.MOUSE_CURSOR_POINTING_HAND);

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            return error.DMExit;
        }
    }
}
