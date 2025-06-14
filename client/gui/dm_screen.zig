const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const messages = @import("messages.zig");
const txt_input = @import("text_input.zig");
const std = @import("std");

const allocator = std.heap.page_allocator;

pub fn ask_message(my_id: [32]u8, dm: [32]u8) ![]u8 {
    var message = try allocator.allocSentinel(u8, 0, 0);

    const my_id_hexz = try std.fmt.allocPrintZ(allocator, "{s}", .{std.fmt.bytesToHex(my_id, .lower)});
    defer allocator.free(my_id_hexz);
    const dm_hexz = try std.fmt.allocPrintZ(allocator, "{s}", .{std.fmt.bytesToHex(dm, .lower)});
    defer allocator.free(dm_hexz);

    const dm_with_txt = try std.fmt.allocPrintZ(allocator, "DM with {s}", .{dm_hexz});
    defer allocator.free(dm_with_txt);

    const dm_with_txt_length: u32 = @intCast(C.MeasureText(dm_with_txt, GUI.FONT_SIZE));

    var should_continue = true;

    while (!C.WindowShouldClose() and should_continue) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @intCast(C.GetScreenWidth());
        GUI.HEIGHT = @intCast(C.GetScreenHeight());

        try @import("id_top_left_display.zig").draw_id_top_left_display(my_id);

        try draw_close_dm_button();

        var y_min_messages: u64 = 25 + 10;

        C.DrawText(dm_with_txt, @intCast(GUI.WIDTH / 2 - dm_with_txt_length / 2), @intCast(y_min_messages), GUI.FONT_SIZE, C.WHITE);

        y_min_messages += GUI.FONT_SIZE + 5;

        try draw_message_input_text(&should_continue, &message);

        try draw_messages(my_id_hexz, dm, dm_hexz, y_min_messages);
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return message;
}

fn draw_message_input_text(should_continue: *bool, message: *[:0]u8) !void {
    const enter_message_txt = "Enter message :";
    const enter_message_txt_length = C.MeasureText(enter_message_txt, GUI.FONT_SIZE);
    C.DrawText(enter_message_txt, 0, @intCast(GUI.HEIGHT - GUI.FONT_SIZE), GUI.FONT_SIZE, C.WHITE);

    if (C.IsKeyPressed(C.KEY_ENTER) or C.IsKeyPressedRepeat(C.KEY_ENTER)) {
        if (message.len > 0) {
            should_continue.* = false;
        }
    }

    try txt_input.draw_text_input(enter_message_txt_length + 20, @intCast(GUI.HEIGHT - GUI.FONT_SIZE), message, GUI.FONT_SIZE, .Left);
}

fn draw_messages(my_id_hexz: [:0]u8, dm: [32]u8, dm_hexz: [:0]u8, y_min_messages: u64) !void {
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
            .Me => my_id_hexz,
            .NotMe => dm_hexz,
        };

        C.DrawText(discussion_message.content, 5, @intCast(y_msg_offset), GUI.FONT_SIZE, C.WHITE);

        y_msg_offset -= GUI.FONT_SIZE / 2 + 5;

        C.DrawText(author_hexz, 5, @intCast(y_msg_offset), GUI.FONT_SIZE, C.BLUE);

        y_msg_offset -= GUI.FONT_SIZE * 3 / 2 + 5;
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
