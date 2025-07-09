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

pub fn draw_dm_screen(my_id: [32]u8, dm: [32]u8, current_message: *[:0]c_int, _bounds: C.Rectangle, keyboard_enabled: bool, cursor: *c_int, symmetric_key: [32]u8, target_id: *?[32]u8) !void {
    const my_id_hex = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(my_id, .lower)});
    defer allocator.free(my_id_hex);
    const dm_hexz = try std.fmt.allocPrintZ(allocator, "{s}", .{std.fmt.bytesToHex(dm, .lower)});
    defer allocator.free(dm_hexz);

    const dm_with_txt: [:0]const u8 = if (std.mem.eql(u8, &my_id, &dm)) "Me" else try std.fmt.allocPrintZ(allocator, "DM with {s}", .{dm_hexz});
    defer if (!std.mem.eql(u8, &my_id, &dm)) allocator.free(dm_with_txt);

    // const dm_with_txt_length = Font.measureText(dm_with_txt, GUI.FONT_SIZE);

    var bounds = _bounds;

    const close_button_rect = C.Rectangle{
        .x = bounds.x + bounds.width - GUI.FONT_SIZE,
        .y = bounds.y,
        .width = GUI.FONT_SIZE,
        .height = GUI.FONT_SIZE,
    };

    try draw_close_dm_button(cursor, target_id, close_button_rect);

    const dm_with_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width - GUI.FONT_SIZE,
        .height = GUI.FONT_SIZE,
    };

    Font.drawText(dm_with_txt, dm_with_bounds, GUI.FONT_SIZE, C.DARKGREEN, .Center, .Center);

    bounds.y += GUI.FONT_SIZE;
    bounds.height -= GUI.FONT_SIZE;

    {
        const input_text_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.y + bounds.height - GUI.FONT_SIZE * 1.5,
            .width = bounds.width,
            .height = GUI.FONT_SIZE * 1.5,
        };

        try draw_message_input_text(
            current_message,
            input_text_bounds,
            symmetric_key,
            dm,
            keyboard_enabled,
        );

        bounds.height -= input_text_bounds.height;
    }

    try draw_messages(dm, dm_hexz, bounds, cursor);
}

fn draw_message_input_text(message: *[:0]c_int, bounds: C.Rectangle, symmetric_key: [32]u8, target_id: [32]u8, is_enabled: bool) !void {
    const enter_message_txt = "Enter message :";
    // const enter_message_txt_length = Font.measureText(enter_message_txt, GUI.FONT_SIZE);

    const enter_message_txt_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width / 7,
        .height = bounds.height,
    };

    Font.drawText(enter_message_txt, enter_message_txt_bounds, GUI.FONT_SIZE, C.WHITE, .Center, .Center);

    const input_txt_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width - enter_message_txt_bounds.width,
        .height = bounds.height,
    };

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

        try txt_input.draw_text_input(input_txt_bounds, .{ .UTF8 = @ptrCast(message) }, GUI.FONT_SIZE, .Start, .Center);
    } else {
        Font.drawCodepoints(message.*, input_txt_bounds, GUI.FONT_SIZE, C.WHITE, .Start, .Center);
    }
}

fn draw_messages(dm: [32]u8, dm_hexz: [:0]u8, _bounds: C.Rectangle, cursor: *c_int) !void {
    const discussion_messages: []const messages.Message = blk: {
        const msgs_lock = &messages.messages;

        const msgs = msgs_lock.get(dm) orelse break :blk try allocator.alloc(messages.Message, 0);

        const owned_msg = try allocator.dupe(messages.Message, msgs.items);

        break :blk owned_msg;
    };
    defer allocator.free(discussion_messages);

    var bounds = _bounds;

    for (0..discussion_messages.len) |i| {
        const reverse_i = discussion_messages.len - 1 - i;
        const discussion_message = discussion_messages[reverse_i];

        if (bounds.height - GUI.FONT_SIZE * 2 - 10 > 0) break;

        const author_hexz = switch (discussion_message.sent_by) {
            .Me => "Me",
            .NotMe => dm_hexz,
        };

        var len: c_int = undefined;
        const msg_content_codepoints = C.LoadCodepoints(discussion_message.content.ptr, &len);
        defer C.UnloadCodepoints(msg_content_codepoints);

        const text_size = Font.measureSliceBounds(.{ .Codepoints = msg_content_codepoints[0..@intCast(len)] }, GUI.FONT_SIZE, bounds);

        Font.drawCodepoints(msg_content_codepoints[0..@intCast(len)], bounds, GUI.FONT_SIZE, if (discussion_message.is_file) C.BLUE else C.WHITE, .Start, .End);
        bounds.height -= text_size.y;

        if (discussion_message.is_file) {
            // const msg_content_codepoints_width = Font.measureCodepoints(msg_content_codepoints[0..@intCast(len)], GUI.FONT_SIZE);

            const rect = C.Rectangle{
                .x = bounds.x,
                .y = bounds.y + bounds.height,
                .width = bounds.width,
                .height = text_size.y,
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

        const txt_size = Font.measureSliceBounds(.{ .Bytes = author_hexz }, GUI.FONT_SIZE, bounds);

        Font.drawText(author_hexz, bounds, GUI.FONT_SIZE, C.BLUE, .Start, .End);

        bounds.height -= txt_size.y;
    }
}

fn draw_close_dm_button(cursor: *c_int, target_id: *?[32]u8, bounds: C.Rectangle) !void {
    C.DrawLineV(.{ .x = bounds.x, .y = bounds.y }, .{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height }, C.WHITE);
    C.DrawLineV(.{ .x = bounds.x, .y = bounds.y + bounds.height }, .{ .x = bounds.x + bounds.width, .y = bounds.y }, C.WHITE);

    if (C.CheckCollisionPointRec(C.GetMousePosition(), bounds)) {
        cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            target_id.* = null;
        }
    }
}
