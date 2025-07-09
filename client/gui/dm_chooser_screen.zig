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

fn draw_message_request(bounds: C.Rectangle, cursor: *c_int) !void {
    var iter = request.unvalidated_receive_requests.iterator();
    const entry = iter.next() orelse return;

    const msg_id = entry.key_ptr.*;
    const value = entry.value_ptr.*;

    const author_id = std.fmt.bytesToHex(value.target_id, .lower);

    const message_req_msg = switch (value.data) {
        .raw_message => |msg| try std.fmt.allocPrint(allocator, "Message request of size {d}o from {s}", .{ msg.len, author_id }),
        .file => |f| try std.fmt.allocPrint(allocator, "File request of size {d}o from {s} and name {s}", .{ value.total_size, author_id, f.filename[0..f.filename_len] }),
    };

    Font.drawText(message_req_msg, @intFromFloat(bounds.x), @intFromFloat(bounds.y), GUI.FONT_SIZE, C.WHITE);

    const side = @min(bounds.height - GUI.FONT_SIZE, bounds.width / 5);

    const accept_rect = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y + GUI.FONT_SIZE,
        .width = side,
        .height = side,
    };

    C.DrawRectangleRec(accept_rect, C.GREEN);

    if (C.CheckCollisionPointRec(C.GetMousePosition(), accept_rect)) {
        cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

        if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
            try listen.send_accept_or_decline(msg_id, value.symmetric_key, value.target_id, true);
        }
    }

    const refuse_rect = C.Rectangle{
        .x = accept_rect.x + side * 2,
        .y = accept_rect.y,
        .width = side,
        .height = side,
    };

    C.DrawRectangleRec(refuse_rect, C.RED);

    if (C.CheckCollisionPointRec(C.GetMousePosition(), refuse_rect)) {
        cursor.* = C.MOUSE_CURSOR_POINTING_HAND;

        if (C.IsMouseButtonPressed(C.MOUSE_BUTTON_LEFT)) {
            try listen.send_accept_or_decline(msg_id, value.symmetric_key, value.target_id, false);
        }
    }
}

fn draw_validated_message_request_avancement(bounds: C.Rectangle) !void {
    var iter = request.receive_requests.iterator();
    const entry = iter.next() orelse return;

    const value = entry.value_ptr.*;

    const author_id = std.fmt.bytesToHex(value.target_id, .lower);

    const message_req_msg = switch (value.data) {
        .raw_message => |msg| try std.fmt.allocPrint(allocator, "Message of size {d}o from {s} :", .{ msg.len, author_id }),
        .file => |f| try std.fmt.allocPrint(allocator, "File `{s}` of size {d}o from {s} :", .{ f.filename[0..f.filename_len], (try f.file.metadata()).size(), author_id }),
    };

    Font.drawText(message_req_msg, @intFromFloat(bounds.x), @intFromFloat(bounds.y), GUI.FONT_SIZE, C.WHITE);

    const done = @min(@as(u64, value.index) * @import("../api/constants.zig").PAYLOAD_AND_PADDING_SIZE, value.total_size);

    const avancement: f32 = @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(value.total_size));

    const avancement_text = try std.fmt.allocPrint(allocator, "{d:.2}%", .{avancement * 100});
    defer allocator.free(avancement_text);

    Font.drawText(avancement_text, @intFromFloat(bounds.x), @as(c_int, @intFromFloat(bounds.y)) + GUI.FONT_SIZE, GUI.FONT_SIZE / 2, C.WHITE);

    const loading_rect = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y + GUI.FONT_SIZE * 2,
        .width = bounds.width,
        .height = GUI.FONT_SIZE * 2,
    };

    //Draw the rect lines
    {
        C.DrawLineV(.{ .x = loading_rect.x, .y = loading_rect.y }, .{ .x = loading_rect.x + loading_rect.width, .y = loading_rect.y }, C.BLUE);
        C.DrawLineV(.{ .x = loading_rect.x, .y = loading_rect.y + loading_rect.height }, .{ .x = loading_rect.x + loading_rect.width, .y = loading_rect.y + loading_rect.height }, C.BLUE);
        C.DrawLineV(.{ .x = loading_rect.x, .y = loading_rect.y }, .{ .x = loading_rect.x, .y = loading_rect.y + loading_rect.height }, C.BLUE);
        C.DrawLineV(.{ .x = loading_rect.x + loading_rect.width, .y = loading_rect.y }, .{ .x = loading_rect.x + loading_rect.width, .y = loading_rect.y + loading_rect.height }, C.BLUE);
    }

    const loading_filling_rect = C.Rectangle{
        .x = loading_rect.x + 2,
        .y = loading_rect.y + 2,
        .width = (loading_rect.width - 2) * avancement,
        .height = loading_rect.height - 2,
    };

    C.DrawRectangleRec(loading_filling_rect, C.BLUE);
}

pub fn draw_choose_discussion_sidebar(my_id: [32]u8, target_id: *?[32]u8, cursor: *c_int, rect: C.Rectangle, dm_state: *Client.DMState) !void {
    var y_offset: f32 = 0;

    try @import("id_top_left_display.zig").draw_id_top_left_display(my_id, cursor);
    y_offset += GUI.FONT_SIZE + 10;

    {
        const manual_button_rect = C.Rectangle{
            .x = rect.x + rect.width - 20,
            .y = rect.y + y_offset,
            .width = 20,
            .height = 20,
        };
        draw_manual_button(dm_state, manual_button_rect);

        y_offset += manual_button_rect.height + 5;
    }

    switch (dm_state.*) {
        .Manual => |*manual_data| try ManualScreen.draw_manual_screen(&manual_data.manual_target_id, &manual_data.manual_target_id_index, target_id, rect, dm_state),
        .NotManual => {
            const messages_lock = &messages.messages;

            var iterator = messages_lock.iterator();

            while (iterator.next()) |discussion| {
                try display_target_id(discussion.key_ptr.*, discussion.value_ptr.items.len, &y_offset, target_id, rect);
            }
        },
    }

    const request_msg_bounds = C.Rectangle{
        .x = @floatFromInt(GUI.WIDTH - 150),
        .y = GUI.FONT_SIZE,
        .width = 125,
        .height = 100,
    };

    try draw_message_request(request_msg_bounds, cursor);

    const validated_requests_msg_bounds = C.Rectangle{
        .x = request_msg_bounds.x,
        .y = request_msg_bounds.y + request_msg_bounds.height * 1.5,
        .width = request_msg_bounds.width,
        .height = request_msg_bounds.height,
    };

    try draw_validated_message_request_avancement(validated_requests_msg_bounds);
}

const ManualScreen = struct {
    pub fn draw_manual_screen(manual_target_id: *[64:0]u8, manual_target_id_index: *usize, target_id: *?[32]u8, bounds: C.Rectangle, dm_state: *Client.DMState) !void {
        const x_center: c_int = @intFromFloat(bounds.x + bounds.width / 2);

        if (manual_target_id_index.* == manual_target_id.len) {
            if (C.IsKeyPressed(C.KEY_ENTER)) {
                try set_target_id(target_id, manual_target_id.*, dm_state);
                return;
            }
        }

        const txt = "Enter the target ID (hexadecimal) :";

        const txt_length = Font.measureText(txt, GUI.FONT_SIZE * 2 / 3);

        const y_center = bounds.y + bounds.height / 2;

        Font.drawText(txt, x_center - @divTrunc(txt_length, 2), @intFromFloat(y_center - GUI.FONT_SIZE * 2), GUI.FONT_SIZE * 2 / 3, C.WHITE);

        txt_input.draw_text_input_array(64, x_center, @intFromFloat(y_center - GUI.FONT_SIZE / 2), manual_target_id, manual_target_id_index, .Center);

        try ManualScreen.draw_paste_target_id_button(manual_target_id, manual_target_id_index, target_id, dm_state);
    }

    fn draw_paste_target_id_button(manual_target_id: *[64:0]u8, manual_target_id_index: *usize, target_id: *?[32]u8, dm_state: *Client.DMState) !void {
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
                try set_target_id(target_id, manual_target_id.*, dm_state);
                return;
            }
        }

        C.DrawRectangleRec(paste_txt_button_rect, paste_txt_rect_bg_color);

        Font.drawText(paste_txt, @intFromFloat(paste_txt_rect.x), @intFromFloat(paste_txt_rect.y), GUI.FONT_SIZE * 2 / 3, C.WHITE);
    }
};

fn draw_manual_button(dm_state: *Client.DMState, rect: C.Rectangle) void {
    if (C.IsKeyPressed(C.KEY_ESCAPE) or C.IsKeyPressedRepeat(C.KEY_ESCAPE)) {
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

fn display_target_id(id: [32]u8, messages_count: usize, y_offset: *f32, target_id: *?[32]u8, bounds: C.Rectangle) !void {
    const rect = C.Rectangle{
        .x = bounds.x,
        .y = y_offset.*,
        .width = bounds.width,
        .height = TARGET_ID_HEIGHT,
    };

    var rect_color = C.BLACK;

    if (C.CheckCollisionPointRec(C.GetMousePosition(), rect)) {
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

    C.DrawRectangleRec(rect, rect_color);
    const id_hex = std.fmt.bytesToHex(id, .lower);
    Font.drawText(&id_hex, @intFromFloat(rect.x + GUI.button_padding), @intFromFloat(y_offset.* + GUI.button_padding), GUI.FONT_SIZE, C.WHITE);

    const number_of_messages_text: [:0]u8 = try std.fmt.allocPrintZ(allocator, "{d} message(s)", .{messages_count});
    defer allocator.free(number_of_messages_text);

    Font.drawText(number_of_messages_text, @intFromFloat(rect.x + GUI.button_padding), @intFromFloat(y_offset.* + GUI.button_padding + GUI.FONT_SIZE), GUI.FONT_SIZE, C.WHITE);

    y_offset.* += TARGET_ID_HEIGHT + SPACE_BETWEEN;
}
