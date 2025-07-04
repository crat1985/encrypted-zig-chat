const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const messages = @import("messages.zig");
const txt_input = @import("text_input.zig");
const std = @import("std");
const Font = @import("font.zig");

const allocator = std.heap.page_allocator;

pub fn ask_message(my_id: [32]u8, dm: [32]u8) ![]u8 {
    var message = try allocator.allocSentinel(c_int, 0, 0);
    defer allocator.free(message);

    const my_id_hex = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(my_id, .lower)});
    defer allocator.free(my_id_hex);
    const dm_hexz = try std.fmt.allocPrintZ(allocator, "{s}", .{std.fmt.bytesToHex(dm, .lower)});
    defer allocator.free(dm_hexz);

    const dm_with_txt: [:0]const u8 = if (std.mem.eql(u8, &my_id, &dm)) "Me" else try std.fmt.allocPrintZ(allocator, "DM with {s}", .{dm_hexz});
    defer if (!std.mem.eql(u8, &my_id, &dm)) allocator.free(dm_with_txt);

    const dm_with_txt_length = Font.measureText(dm_with_txt, GUI.FONT_SIZE);

    var should_continue = true;

    var cursor = C.MOUSE_CURSOR_DEFAULT;

    while (!C.WindowShouldClose() and should_continue) {
        cursor = C.MOUSE_CURSOR_DEFAULT;

        C.BeginDrawing();
        defer C.EndDrawing();

        defer C.SetMouseCursor(cursor);

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @intCast(C.GetScreenWidth());
        GUI.HEIGHT = @intCast(C.GetScreenHeight());

        try @import("id_top_left_display.zig").draw_id_top_left_display(my_id, &cursor);

        try draw_close_dm_button(&cursor);

        var y_min_messages: u64 = 25 + 10;

        Font.drawText(dm_with_txt, @divTrunc(GUI.WIDTH, 2) - @divTrunc(dm_with_txt_length, 2), @intCast(y_min_messages), GUI.FONT_SIZE, C.DARKGREEN);

        y_min_messages += GUI.FONT_SIZE + 5;

        try draw_message_input_text(&should_continue, &message);

        try draw_messages(dm, dm_hexz, y_min_messages);
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    const msg_utf8_raylib = C.LoadUTF8(message.ptr, @intCast(message.len));
    defer C.UnloadUTF8(msg_utf8_raylib);
    const n = C.TextLength(msg_utf8_raylib);
    const message_utf8 = try allocator.alloc(u8, n);
    @memcpy(message_utf8, msg_utf8_raylib);

    return message_utf8;
}

fn draw_message_input_text(should_continue: *bool, message: *[:0]c_int) !void {
    const enter_message_txt = "Enter message :";
    const enter_message_txt_length = Font.measureText(enter_message_txt, GUI.FONT_SIZE);
    Font.drawText(enter_message_txt, 0, @intCast(GUI.HEIGHT - GUI.FONT_SIZE), GUI.FONT_SIZE, C.WHITE);

    if (C.IsKeyPressed(C.KEY_ENTER) or C.IsKeyPressedRepeat(C.KEY_ENTER)) {
        if (message.len > 0) {
            should_continue.* = false;
        }
    }

    try txt_input.draw_text_input(enter_message_txt_length + 20, @intCast(GUI.HEIGHT - GUI.FONT_SIZE), .{ .UTF8 = @ptrCast(message) }, GUI.FONT_SIZE, .Left);
}

fn draw_messages(dm: [32]u8, dm_hexz: [:0]u8, y_min_messages: u64) !void {
    const discussion_messages: []const messages.Message = blk: {
        const msgs_lock = messages.messages.lock();
        defer messages.messages.unlock();

        const msgs = msgs_lock.get(dm) orelse break :blk try allocator.alloc(messages.Message, 0);

        const owned_msg = try allocator.dupe(messages.Message, msgs.items);

        break :blk owned_msg;
    };
    defer allocator.free(discussion_messages);

    var y_msg_offset = GUI.HEIGHT - GUI.FONT_SIZE * 2 - 5;

    for (0..discussion_messages.len) |i| {
        const reverse_i = discussion_messages.len - 1 - i;
        const discussion_message = discussion_messages[reverse_i];
        if (y_msg_offset - GUI.FONT_SIZE * 2 - 10 < y_min_messages) break;
        // defer y_msg_offset -= GUI.FONT_SIZE * 2 + 10;

        const author_hexz = switch (discussion_message.sent_by) {
            .Me => "Me",
            .NotMe => dm_hexz,
        };

        var len: c_int = undefined;
        const msg_content_codepoints = C.LoadCodepoints(discussion_message.content.ptr, &len);
        defer C.UnloadCodepoints(msg_content_codepoints);
        Font.drawCodepoints(msg_content_codepoints[0..@intCast(len)], 5, @intCast(y_msg_offset), GUI.FONT_SIZE, C.WHITE);

        y_msg_offset -= GUI.FONT_SIZE + 5;

        Font.drawText(author_hexz, 5, @intCast(y_msg_offset), GUI.FONT_SIZE, C.BLUE);

        y_msg_offset -= GUI.FONT_SIZE * 3 / 2 + 5;
    }
}

fn draw_close_dm_button(cursor: *c_int) !void {
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
            return error.DMExit;
        }
    }
}
