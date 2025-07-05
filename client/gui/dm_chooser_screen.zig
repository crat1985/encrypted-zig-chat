const messages = @import("messages.zig");

const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");
const txt_input = @import("text_input.zig");
const Font = @import("font.zig");

const TARGET_ID_HEIGHT = 80;
const SPACE_BETWEEN = 15;

const allocator = std.heap.page_allocator;

pub fn ask_target_id(my_id: [32]u8) ![32]u8 {
    var target_id: ?[32]u8 = null;
    var is_manual = false;
    var manual_target_id = std.mem.zeroes([64:0]u8);
    var manual_target_id_index: usize = 0;
    var cursor = C.MOUSE_CURSOR_DEFAULT;

    while (!C.WindowShouldClose() and target_id == null) {
        cursor = C.MOUSE_CURSOR_DEFAULT;

        C.BeginDrawing();
        defer C.EndDrawing();

        defer C.SetMouseCursor(cursor);

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = C.GetScreenWidth();
        GUI.HEIGHT = C.GetScreenHeight();

        try @import("id_top_left_display.zig").draw_id_top_left_display(my_id, &cursor);

        draw_manual_button(&is_manual);

        switch (is_manual) {
            true => try ManualScreen.draw_manual_screen(&manual_target_id, &manual_target_id_index, &target_id),
            false => {
                var y_offset: usize = 25 + 5; //a bit below the y of the manual button

                const messages_lock = messages.messages.lock();
                defer messages.messages.unlock();

                var iterator = messages_lock.iterator();

                while (iterator.next()) |discussion| {
                    try display_target_id(discussion.key_ptr.*, discussion.value_ptr.items.len, &y_offset, &target_id);
                }
            },
        }
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return target_id.?;
}

const ManualScreen = struct {
    pub fn draw_manual_screen(manual_target_id: *[64:0]u8, manual_target_id_index: *usize, target_id: *?[32]u8) !void {
        const x_center = @divTrunc(GUI.WIDTH, 2);

        if (manual_target_id_index.* == manual_target_id.len) {
            if (C.IsKeyPressed(C.KEY_ENTER)) {
                try set_target_id(target_id, manual_target_id.*);
                return;
            }
        }

        const txt = "Enter the target ID (hexadecimal) :";

        const txt_length = Font.measureText(txt, GUI.FONT_SIZE * 2 / 3);

        const y_center = @divTrunc(GUI.HEIGHT, 2);

        Font.drawText(txt, x_center - @divTrunc(txt_length, 2), y_center - GUI.FONT_SIZE * 2, GUI.FONT_SIZE * 2 / 3, C.WHITE);

        txt_input.draw_text_input_array(64, x_center, y_center - GUI.FONT_SIZE / 2, manual_target_id, manual_target_id_index, .Center);

        try ManualScreen.draw_paste_target_id_button(manual_target_id, manual_target_id_index, target_id);
    }

    fn draw_paste_target_id_button(manual_target_id: *[64:0]u8, manual_target_id_index: *usize, target_id: *?[32]u8) !void {
        const paste_txt = "Paste ID from clipboard";
        const paste_txt_length = Font.measureText(paste_txt, GUI.FONT_SIZE * 2 / 3);

        const x_center = @divTrunc(GUI.WIDTH, 2);
        const y_center = @divTrunc(GUI.HEIGHT, 2);

        const paste_txt_rect = C.Rectangle{
            .x = @floatFromInt(x_center - @divTrunc(paste_txt_length, 2)),
            .y = @floatFromInt(y_center + GUI.FONT_SIZE),
            .width = @floatFromInt(paste_txt_length),
            .height = @floatFromInt(GUI.FONT_SIZE * 2 / 3),
        };

        var paste_txt_button_rect = paste_txt_rect;
        paste_txt_button_rect.x -= GUI.FONT_SIZE;
        paste_txt_button_rect.width += GUI.FONT_SIZE * 2;

        var paste_txt_rect_bg_color = C.BLACK;

        if (C.CheckCollisionPointRec(C.GetMousePosition(), paste_txt_rect)) {
            paste_txt_rect_bg_color = C.DARKGRAY;

            if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
                paste_txt_rect_bg_color = C.GRAY;
            }

            if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
                const clipboard_data = C.GetClipboardText();
                const len = C.TextLength(clipboard_data);
                if (len != 64) {
                    std.log.err("Invalid ID length {d}", .{len});
                    return;
                }

                @memcpy(manual_target_id, clipboard_data[0..64]);
                manual_target_id_index.* = manual_target_id.len;
                try set_target_id(target_id, manual_target_id.*);
                return;
            }
        }

        C.DrawRectangleRec(paste_txt_button_rect, paste_txt_rect_bg_color);

        Font.drawText(paste_txt, @intFromFloat(paste_txt_rect.x), @intFromFloat(paste_txt_rect.y), GUI.FONT_SIZE * 2 / 3, C.WHITE);
    }
};

fn draw_manual_button(is_manual: *bool) void {
    if (C.IsKeyPressed(C.KEY_ESCAPE) or C.IsKeyPressedRepeat(C.KEY_ESCAPE)) {
        is_manual.* = false;
        return;
    }

    const manual_button = C.Rectangle{
        .x = @floatFromInt(GUI.WIDTH - 25),
        .y = 5,
        .width = 20,
        .height = 20,
    };

    var close_button_bg_color = if (is_manual.*) C.BLUE else C.BLACK;

    if (C.CheckCollisionPointRec(C.GetMousePosition(), manual_button)) {
        close_button_bg_color = C.DARKGRAY;

        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            close_button_bg_color = C.GRAY;
        }

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            is_manual.* = !is_manual.*;
        }
    }

    C.DrawRectangleRec(manual_button, close_button_bg_color);

    C.DrawLine(@intCast(GUI.WIDTH - 25), 15, @intCast(GUI.WIDTH - 5), 15, C.WHITE);
    C.DrawLine(@intCast(GUI.WIDTH - 15), 5, @intCast(GUI.WIDTH - 15), 25, C.WHITE);
}

fn set_target_id(target_id_ptr: *?[32]u8, target_id: [64]u8) !void {
    var target_id_unwrap: [32]u8 = undefined;

    _ = try std.fmt.hexToBytes(&target_id_unwrap, &target_id);

    target_id_ptr.* = target_id_unwrap;
}

fn display_target_id(id: [32]u8, messages_count: usize, y_offset: *usize, target_id: *?[32]u8) !void {
    const rect = C.Rectangle{
        .x = 0,
        .y = @floatFromInt(y_offset.*),
        .width = @floatFromInt(GUI.WIDTH),
        .height = TARGET_ID_HEIGHT,
    };

    var rect_color = C.BLACK;

    if (C.CheckCollisionPointRec(C.GetMousePosition(), rect)) {
        rect_color = C.DARKGRAY;

        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            rect_color = C.GRAY;
        }

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            target_id.* = id; //TODO perhaps stop the loop execution
        }
    }

    C.DrawRectangleRec(rect, rect_color);
    const id_hex = std.fmt.bytesToHex(id, .lower);
    Font.drawText(&id_hex, GUI.button_padding, @intCast(y_offset.* + GUI.button_padding), GUI.FONT_SIZE, C.WHITE);

    const number_of_messages_text: [:0]u8 = try std.fmt.allocPrintZ(allocator, "{d} message(s)", .{messages_count});
    defer allocator.free(number_of_messages_text);

    Font.drawText(number_of_messages_text, GUI.button_padding, @intCast(y_offset.* + GUI.button_padding + GUI.FONT_SIZE), GUI.FONT_SIZE, C.WHITE);

    y_offset.* += TARGET_ID_HEIGHT;

    y_offset.* += SPACE_BETWEEN;
}
