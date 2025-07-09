const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const messages = @import("messages.zig");
const txt_input = @import("text_input.zig");
const std = @import("std");
const Font = @import("font.zig");
const Mutex = @import("../../mutex.zig").Mutex;
const api = @import("../api.zig");
const request = @import("../api/request.zig");

const allocator = std.heap.page_allocator;

pub fn draw_dm_screen(my_id: [32]u8, dm: [32]u8, current_message: *[:0]c_int, bounds: C.Rectangle, keyboard_enabled: bool, cursor: *c_int, symmetric_key: [32]u8, target_id: *?[32]u8) !void {
    const my_id_hex = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(my_id, .lower)});
    defer allocator.free(my_id_hex);
    const dm_hexz = try std.fmt.allocPrintZ(allocator, "{s}", .{std.fmt.bytesToHex(dm, .lower)});
    defer allocator.free(dm_hexz);

    const dm_with_txt: [:0]const u8 = if (std.mem.eql(u8, &my_id, &dm)) "Me" else try std.fmt.allocPrintZ(allocator, "DM with {s}", .{dm_hexz});
    defer if (!std.mem.eql(u8, &my_id, &dm)) allocator.free(dm_with_txt);

    const dm_with_txt_length = Font.measureText(dm_with_txt, GUI.FONT_SIZE);

    try draw_close_dm_button(cursor, target_id);

    var y_min_messages: c_int = @intFromFloat(bounds.y + 25 + 10);

    const x_center: c_int = @intFromFloat(bounds.x + bounds.width / 2);

    Font.drawText(dm_with_txt, x_center - @divTrunc(dm_with_txt_length, 2), y_min_messages, GUI.FONT_SIZE, C.DARKGREEN);

    y_min_messages += GUI.FONT_SIZE + 5;

    {
        const input_text_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.height - GUI.FONT_SIZE,
            .width = bounds.width,
            .height = GUI.FONT_SIZE,
        };

        try draw_message_input_text(
            current_message,
            input_text_bounds,
            symmetric_key,
            dm,
            keyboard_enabled,
        );
    }

    const messages_bounds = C.Rectangle{
        .x = bounds.x,
        .y = @floatFromInt(y_min_messages),
        .width = bounds.width,
        .height = bounds.height - @as(f32, @floatFromInt(y_min_messages)),
    };

    try draw_messages(dm, dm_hexz, messages_bounds, cursor);
}

fn draw_message_input_text(message: *[:0]c_int, bounds: C.Rectangle, symmetric_key: [32]u8, target_id: [32]u8, is_enabled: bool) !void {
    const txt_y: c_int = @intFromFloat(bounds.y + bounds.height / 2 - GUI.FONT_SIZE);

    const enter_message_txt = "Enter message :";
    const enter_message_txt_length = Font.measureText(enter_message_txt, GUI.FONT_SIZE);
    Font.drawText(enter_message_txt, @intFromFloat(bounds.x), txt_y, GUI.FONT_SIZE, C.WHITE);

    if (is_enabled) {
        if (C.IsKeyPressed(C.KEY_ENTER) or C.IsKeyPressedRepeat(C.KEY_ENTER)) {
            if (message.len > 0) {
                const msg_utf8_raylib = C.LoadUTF8(message.ptr, @intCast(message.len));
                defer C.UnloadUTF8(msg_utf8_raylib);
                const n = C.TextLength(msg_utf8_raylib);

                const msg_utf8_owned = try allocator.dupe(u8, msg_utf8_raylib[0..n]);

                try request.send_request(.{
                    .data = .{ .raw_message = msg_utf8_owned },
                    .symmetric_key = symmetric_key,
                    .target_id = target_id,
                });
                allocator.free(message.*);

                message.* = try allocator.allocSentinel(c_int, 0, 0);
            }
        }

        try txt_input.draw_text_input(@as(c_int, @intFromFloat(bounds.x)) + enter_message_txt_length + 5, txt_y, .{ .UTF8 = @ptrCast(message) }, GUI.FONT_SIZE, .Left);
    } else {
        txt_input.draw_text_input_no_events(@as(c_int, @intFromFloat(bounds.x)) + enter_message_txt_length + 5, txt_y, .{ .UTF8 = @ptrCast(message) }, GUI.FONT_SIZE, .Left);
    }
}

fn draw_messages(dm: [32]u8, dm_hexz: [:0]u8, bounds: C.Rectangle, cursor: *c_int) !void {
    const discussion_messages: []const messages.Message = blk: {
        const msgs_lock = &messages.messages;

        const msgs = msgs_lock.get(dm) orelse break :blk try allocator.alloc(messages.Message, 0);

        const owned_msg = try allocator.dupe(messages.Message, msgs.items);

        break :blk owned_msg;
    };
    defer allocator.free(discussion_messages);

    var y_msg_offset = bounds.y + bounds.height - GUI.FONT_SIZE * 3;

    for (0..discussion_messages.len) |i| {
        const reverse_i = discussion_messages.len - 1 - i;
        const discussion_message = discussion_messages[reverse_i];
        if (y_msg_offset - GUI.FONT_SIZE * 2 - 10 < bounds.y) break;
        // defer y_msg_offset -= GUI.FONT_SIZE * 2 + 10;

        const author_hexz = switch (discussion_message.sent_by) {
            .Me => "Me",
            .NotMe => dm_hexz,
        };

        var len: c_int = undefined;
        const msg_content_codepoints = C.LoadCodepoints(discussion_message.content.ptr, &len);
        defer C.UnloadCodepoints(msg_content_codepoints);
        Font.drawCodepoints(msg_content_codepoints[0..@intCast(len)], @intFromFloat(bounds.x + 5), @intFromFloat(y_msg_offset), GUI.FONT_SIZE, if (discussion_message.is_file) C.BLUE else C.WHITE);
        if (discussion_message.is_file) {
            const msg_content_codepoints_width = Font.measureCodepoints(msg_content_codepoints[0..@intCast(len)], GUI.FONT_SIZE);

            const rect = C.Rectangle{
                .x = bounds.x,
                .y = y_msg_offset,
                .width = @floatFromInt(msg_content_codepoints_width),
                .height = GUI.FONT_SIZE + 3,
            };

            if (C.CheckCollisionPointRec(C.GetMousePosition(), rect)) {
                cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

                if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
                    const relative_path = try std.fs.path.join(allocator, &.{ @import("../api/constants.zig").FILE_OUTPUT_DIR, discussion_message.content });
                    defer allocator.free(relative_path);

                    //TODO open them somehow ?
                }
            }

            C.DrawLine(@intFromFloat(rect.x), @intFromFloat(rect.y + GUI.FONT_SIZE + 3), @intFromFloat(rect.x + rect.width), @intFromFloat(rect.y + GUI.FONT_SIZE + 3), C.BLUE);
        }

        y_msg_offset -= GUI.FONT_SIZE + 5;

        Font.drawText(author_hexz, @intFromFloat(bounds.x + 5), @intFromFloat(y_msg_offset), GUI.FONT_SIZE, C.BLUE);

        y_msg_offset -= GUI.FONT_SIZE * 3 / 2 + 5;
    }
}

fn draw_close_dm_button(cursor: *c_int, target_id: *?[32]u8) !void {
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
        cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            target_id.* = null;
        }
    }
}
