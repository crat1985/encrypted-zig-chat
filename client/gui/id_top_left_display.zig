const std = @import("std");
const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub fn draw_id_top_left_display(id: [32]u8, cursor: *c_int) !void {
    const my_id_hexz = try allocator.dupeZ(u8, &std.fmt.bytesToHex(id, .lower));
    defer allocator.free(my_id_hexz);
    const my_id_text = try std.fmt.allocPrintZ(allocator, "{s} (click to copy)", .{my_id_hexz});
    defer allocator.free(my_id_text);
    const my_id_text_width = Font.measureText(my_id_text, GUI.FONT_SIZE);

    const my_id_rect = C.Rectangle{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(my_id_text_width + 10),
        .height = @floatFromInt(GUI.FONT_SIZE + 10),
    };

    Font.drawText(my_id_text, 5, 5, GUI.FONT_SIZE, C.WHITE);

    if (C.CheckCollisionPointRec(C.GetMousePosition(), my_id_rect)) {
        cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            C.SetClipboardText(my_id_hexz);
        }
    }
}
