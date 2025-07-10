const std = @import("std");
const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const Font = @import("font.zig");
// const txt_mod = @import("txt.zig");
const Button = @import("button.zig").Button;

const allocator = std.heap.page_allocator;

pub fn draw_id_top_left_display(id: [32]u8, cursor: *c_int, bounds: C.Rectangle) !void {
    const my_id_hexz = try allocator.dupeZ(u8, &std.fmt.bytesToHex(id, .lower));
    defer allocator.free(my_id_hexz);
    const my_id_text = try std.fmt.allocPrintZ(allocator, "{s} (click to copy)", .{my_id_hexz});
    defer allocator.free(my_id_text);

    const copy_id_button = Button(u8).init_default_text_button_center(bounds, my_id_text, true);
    copy_id_button.set_cursor(cursor);
    copy_id_button.draw();

    if (copy_id_button.is_clicked()) {
        C.SetClipboardText(my_id_hexz);
    }
}
