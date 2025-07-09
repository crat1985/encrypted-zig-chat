const messages = @import("messages.zig");
const request = @import("../api/request.zig");
const listen = @import("../api/listen.zig");

const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");
const txt_input = @import("text_input.zig");
const Font = @import("font.zig");
const Client = @import("../../client.zig");

const TARGET_ID_HEIGHT = 80;
const SPACE_BETWEEN = 15;

const allocator = std.heap.page_allocator;

pub fn draw_choose_discussion_sidebar(bounds: C.Rectangle, dm_state: *Client.DMState, target_id: *?[32]u8) !void {
    const manual_button_rect = C.Rectangle{
        .x = bounds.x + bounds.width - 20,
        .y = 0,
        .width = 20,
        .height = 20,
    };
    draw_manual_button(dm_state, manual_button_rect);

    var inner_bounds = C.Rectangle{
        .x = bounds.x,
        .y = manual_button_rect.y + manual_button_rect.height,
        .width = bounds.width,
        .height = bounds.height - (manual_button_rect.y + manual_button_rect.height),
    };

    switch (dm_state.*) {
        .Manual => |*manual_data| try ManualScreen.draw_manual_screen(&manual_data.manual_target_id, &manual_data.manual_target_id_index, target_id, inner_bounds, dm_state),
        .NotManual => {
            const messages_lock = &messages.messages;

            var iterator = messages_lock.iterator();

            while (iterator.next()) |discussion| : ({
                inner_bounds.y += TARGET_ID_HEIGHT;
                inner_bounds.height -= TARGET_ID_HEIGHT;
            }) {
                if (inner_bounds.height < 0) break;
                try display_target_id(discussion.key_ptr.*, discussion.value_ptr.items.len, target_id, inner_bounds);
            }
        },
    }
}

const ManualScreen = struct {
    pub fn draw_manual_screen(manual_target_id: *[64:0]u8, manual_target_id_index: *usize, target_id: *?[32]u8, bounds: C.Rectangle, dm_state: *Client.DMState) !void {
        if (manual_target_id_index.* == manual_target_id.len) {
            if (C.IsKeyPressed(C.KEY_ENTER)) {
                try set_target_id(target_id, manual_target_id.*, dm_state);
                return;
            }
        }

        const txt = "Enter the target ID (hexadecimal) :";

        var txt_bounds = C.Rectangle{
            .x = bounds.x,
            .y = bounds.y * 2 / 6,
            .width = bounds.width,
            .height = bounds.y / 6,
        };

        Font.drawText(txt, txt_bounds, GUI.FONT_SIZE, C.WHITE, .Center, .Center);

        txt_bounds.y += bounds.y / 6;

        txt_input.draw_text_input_array(64, txt_bounds, manual_target_id, manual_target_id_index, .Center, .Center, GUI.FONT_SIZE);

        txt_bounds.y += bounds.y / 6;

        try ManualScreen.draw_paste_target_id_button(manual_target_id, manual_target_id_index, target_id, dm_state, txt_bounds);
    }

    fn draw_paste_target_id_button(manual_target_id: *[64:0]u8, manual_target_id_index: *usize, target_id: *?[32]u8, dm_state: *Client.DMState, bounds: C.Rectangle) !void {
        const paste_txt = "Paste ID from clipboard";

        const paste_txt_rect = Font.getRealTextRect(bounds, GUI.button_padding, GUI.button_padding, GUI.FONT_SIZE, .{ .Bytes = paste_txt }, .Center, .Center);

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
                try set_target_id(target_id, manual_target_id.*, dm_state);
                return;
            }
        }

        C.DrawRectangleRec(paste_txt_rect, paste_txt_rect_bg_color);

        Font.drawText(paste_txt, bounds, GUI.FONT_SIZE, C.WHITE, .Center, .Center);
    }
};

fn draw_manual_button(dm_state: *Client.DMState, rect: C.Rectangle) void {
    if (C.IsKeyPressed(C.KEY_ESCAPE)) {
        dm_state.* = .{ .NotManual = {} };
        return;
    }

    var close_button_bg_color = switch (dm_state.*) {
        .Manual => C.BLUE,
        .NotManual => C.BLACK,
    };

    if (C.CheckCollisionPointRec(C.GetMousePosition(), rect)) {
        close_button_bg_color = C.DARKGRAY;

        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            close_button_bg_color = C.GRAY;
        }

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            switch (dm_state.*) {
                .Manual => dm_state.* = .{ .NotManual = {} },
                .NotManual => dm_state.* = .{ .Manual = .{} },
            }
        }
    }

    C.DrawRectangleRec(rect, close_button_bg_color);

    C.DrawLineV(.{ .x = rect.x, .y = rect.y + rect.height / 2 }, .{ .x = rect.x + rect.width, .y = rect.y + rect.height / 2 }, C.WHITE);
    C.DrawLineV(.{ .x = rect.x + rect.width / 2, .y = rect.y }, .{ .x = rect.x + rect.width / 2, .y = rect.y + rect.height }, C.WHITE);
}

fn set_target_id(target_id_ptr: *?[32]u8, target_id: [64]u8, dm_state: *Client.DMState) !void {
    var target_id_unwrap: [32]u8 = undefined;

    _ = try std.fmt.hexToBytes(&target_id_unwrap, &target_id);

    target_id_ptr.* = target_id_unwrap;

    dm_state.* = .{ .NotManual = {} };
}

fn display_target_id(id: [32]u8, messages_count: usize, target_id: *?[32]u8, bounds: C.Rectangle) !void {
    var rect_color = C.BLACK;

    if (C.CheckCollisionPointRec(C.GetMousePosition(), bounds)) {
        rect_color = C.DARKGRAY;

        if (C.IsMouseButtonDown(C.MOUSE_LEFT_BUTTON)) {
            rect_color = C.GRAY;
        }

        if (C.IsMouseButtonPressed(C.MOUSE_LEFT_BUTTON)) {
            target_id.* = id;
            return;
        }
    }

    if (target_id.*) |target| {
        if (std.mem.eql(u8, &id, &target)) {
            rect_color = C.BLUE;
        }
    }

    C.DrawRectangleRec(bounds, rect_color);

    const id_hex = std.fmt.bytesToHex(id, .lower);

    var txt_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width,
        .height = bounds.height / 2,
    };
    Font.drawTextRect(txt_bounds, GUI.button_padding, GUI.button_padding, C.WHITE, GUI.FONT_SIZE, rect_color, .{ .Bytes = &id_hex }, .Center, .Center);

    const number_of_messages_text = try std.fmt.allocPrint(allocator, "{d} message(s)", .{messages_count});
    defer allocator.free(number_of_messages_text);

    txt_bounds.x += bounds.height;

    Font.drawTextRect(txt_bounds, GUI.button_padding, GUI.button_padding, C.WHITE, GUI.FONT_SIZE, rect_color, .{ .Bytes = number_of_messages_text }, .Center, .Center);
}
