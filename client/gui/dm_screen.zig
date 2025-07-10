const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const messages = @import("messages.zig");
const txt_input = @import("text_input.zig");
const std = @import("std");
const Font = @import("font.zig");
const Mutex = @import("../../mutex.zig").Mutex;
const api = @import("../api.zig");
const request = @import("../api/request.zig");
const Button = @import("button.zig").Button;
const txt_mod = @import("txt.zig");

const allocator = std.heap.page_allocator;

pub fn draw_dm_screen(my_id: [32]u8, dm: [32]u8, current_message: *[:0]c_int, _bounds: C.Rectangle, keyboard_enabled: bool, cursor: *c_int, symmetric_key: [32]u8, target_id: *?[32]u8) !void {
    const my_id_hex = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(my_id, .lower)});
    defer allocator.free(my_id_hex);
    const dm_hexz = try std.fmt.allocPrintZ(allocator, "{s}", .{std.fmt.bytesToHex(dm, .lower)});
    defer allocator.free(dm_hexz);

    const dm_with_txt: [:0]const u8 = if (std.mem.eql(u8, &my_id, &dm)) "Me" else try std.fmt.allocPrintZ(allocator, "DM with {s}", .{dm_hexz});
    defer if (!std.mem.eql(u8, &my_id, &dm)) allocator.free(dm_with_txt);

    var bounds = _bounds;

    const close_button_rect = C.Rectangle{
        .x = bounds.x + bounds.width - GUI.FONT_SIZE * 4,
        .y = bounds.y,
        .width = GUI.FONT_SIZE * 4,
        .height = GUI.FONT_SIZE,
    };

    try draw_close_dm_button(cursor, target_id, close_button_rect);

    bounds.y += close_button_rect.height;
    bounds.height -= close_button_rect.height;

    {
        const txt_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = GUI.FONT_SIZE,
        };

        txt_mod.drawText(u8, dm_with_txt, txt_bounds, GUI.FONT_SIZE, C.DARKGREEN, .Center, .Center);

        bounds.y += txt_bounds.height;
        bounds.height -= txt_bounds.height;
    }

    {
        const input_text_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.y + bounds.height - GUI.FONT_SIZE * 4,
            .width = bounds.width,
            .height = GUI.FONT_SIZE * 4,
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

fn draw_message_input_text(message: *[:0]c_int, _bounds: C.Rectangle, symmetric_key: [32]u8, target_id: [32]u8, is_enabled: bool) !void {
    var bounds = _bounds;

    {
        const enter_message_txt = "Enter message :";

        const enter_message_txt_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width / 7,
            .height = bounds.height,
        };

        txt_mod.drawText(u8, enter_message_txt, enter_message_txt_bounds, GUI.FONT_SIZE, C.WHITE, .Center, .Center);

        bounds.x += enter_message_txt_bounds.width;
        bounds.width -= enter_message_txt_bounds.height;
    }

    if (is_enabled) {
        if (C.IsKeyPressed(C.KEY_ENTER)) {
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

        try txt_input.draw_text_input(c_int, @ptrCast(message), bounds, GUI.FONT_SIZE, .Start, .Center);
    } else {
        txt_mod.drawText(c_int, message.*, bounds, GUI.FONT_SIZE, C.WHITE, .Start, .Center);
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

        if (bounds.height < GUI.FONT_SIZE * 5) break;

        const author_hexz = switch (discussion_message.sent_by) {
            .Me => "Me",
            .NotMe => dm_hexz,
        };

        var len: c_int = undefined;
        const msg_content_codepoints = C.LoadCodepoints(discussion_message.content.ptr, &len);
        defer C.UnloadCodepoints(msg_content_codepoints);

        const msg_bounds_height = @min(bounds.height, GUI.FONT_SIZE * 4);
        var msg_bounds = bounds;
        msg_bounds.y += msg_bounds.height - msg_bounds_height;
        msg_bounds.height = msg_bounds_height;

        txt_mod.drawText(c_int, msg_content_codepoints[0..@intCast(len)], msg_bounds, GUI.FONT_SIZE, C.WHITE, .Start, .Center);

        bounds.height -= msg_bounds_height;

        if (discussion_message.is_file) {
            if (C.CheckCollisionPointRec(C.GetMousePosition(), msg_bounds)) {
                cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

                if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
                    const relative_path = try std.fs.path.join(allocator, &.{ @import("../api/constants.zig").FILE_OUTPUT_DIR, discussion_message.content });
                    defer allocator.free(relative_path);

                    //TODO open them somehow ?
                }
            }

            //TODO underline
            // C.DrawLineV(.{ .x = msg_bounds.x, .y = msg_bounds.y + msg_bounds.height + 3 }, .{ .x = msg_bounds.x + msg_bounds.width, .y = msg_bounds.y + msg_bounds.height + 3 }, C.BLUE);
        }

        const author_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.y + bounds.height - GUI.FONT_SIZE,
            .width = bounds.width,
            .height = GUI.FONT_SIZE,
        };

        txt_mod.drawText(u8, author_hexz, author_bounds, GUI.FONT_SIZE, C.BLUE, .Start, .Center);

        bounds.height -= author_bounds.height;
    }
}

fn draw_close_dm_button(cursor: *c_int, target_id: *?[32]u8, bounds: C.Rectangle) !void {
    const close_dm_button_txt = "Close DM";
    const close_dm_button = Button(u8).init_default_text_button_center(bounds, close_dm_button_txt, true);
    close_dm_button.draw();
    close_dm_button.set_cursor(cursor);

    if (close_dm_button.is_clicked()) {
        target_id.* = null;
    }
}
