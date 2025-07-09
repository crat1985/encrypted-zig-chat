const std = @import("std");
const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub fn draw_id_top_left_display(id: [32]u8, cursor: *c_int, bounds: C.Rectangle) !void {
    const my_id_hexz = try allocator.dupeZ(u8, &std.fmt.bytesToHex(id, .lower));
    defer allocator.free(my_id_hexz);
    const my_id_text = try std.fmt.allocPrintZ(allocator, "{s} (click to copy)", .{my_id_hexz});
    defer allocator.free(my_id_text);

    const my_id_rect = Font.getRealTextRect(bounds, GUI.button_padding, GUI.button_padding, GUI.FONT_SIZE, .{ .Bytes = my_id_text }, .Center, .Center);
    Font.drawTextRect(bounds, GUI.button_padding, GUI.button_padding, C.WHITE, GUI.FONT_SIZE, C.BLACK, .{ .Bytes = my_id_text }, .Center, .Center);

    if (C.CheckCollisionPointRec(C.GetMousePosition(), my_id_rect)) {
        cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            C.SetClipboardText(my_id_hexz);
        }
    }
}
