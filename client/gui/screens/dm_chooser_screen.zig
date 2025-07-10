const messages = @import("messages.zig");
const request = @import("../api/request.zig");
const listen = @import("../api/listen.zig");

const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const std = @import("std");
const txt_input = @import("text_input.zig");
const Font = @import("font.zig");
const Client = @import("../../client.zig");
const Button = @import("button.zig").Button;
const txt_mod = @import("txt.zig");

const TARGET_ID_HEIGHT = 80;
const SPACE_BETWEEN = 15;

const allocator = std.heap.page_allocator;

pub fn draw_choose_discussion_sidebar(_bounds: C.Rectangle, dm_state: *Client.DMState, target_id: *?[32]u8) !void {
    var bounds = _bounds;

    {
        const manual_button_rect = C.Rectangle{
            .x = bounds.x + bounds.width - 20,
            .y = 0,
            .width = 100,
            .height = 20,
        };
        draw_manual_button(dm_state, manual_button_rect);

        bounds.y += manual_button_rect.height;
        bounds.height -= manual_button_rect.height;
    }

    switch (dm_state.*) {
        .Manual => |*manual_data| try ManualScreen.draw_manual_screen(&manual_data.manual_target_id, &manual_data.manual_target_id_index, target_id, bounds, dm_state),
        .NotManual => {
            const messages_lock = &messages.messages;

            var iterator = messages_lock.iterator();

            while (iterator.next()) |discussion| : ({
                bounds.y += TARGET_ID_HEIGHT;
                bounds.height -= TARGET_ID_HEIGHT;
            }) {
                if (bounds.height < 0) break;
                const target_id_bounds = C.Rectangle{
                    .x = bounds.x,
                    .y = bounds.y,
                    .width = bounds.width,
                    .height = TARGET_ID_HEIGHT,
                };
                try display_target_id(discussion.key_ptr.*, discussion.value_ptr.items.len, target_id, target_id_bounds);
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
            .y = bounds.y / 6,
            .width = bounds.width,
            .height = bounds.y / 6,
        };

        txt_mod.drawText(u8, txt, txt_bounds, GUI.FONT_SIZE, C.WHITE, .{ .x = .Center, .y = .Center });

        txt_bounds.y += txt_bounds.height;

        txt_input.draw_text_input_array(64, u8, manual_target_id, txt_bounds, manual_target_id_index, .{ .x = .Center, .y = .Center }, GUI.FONT_SIZE);

        txt_bounds.y += txt_bounds.height;

        const paste_txt = "Paste ID from clipboard";

        const paste_from_clipboard = Button(u8).init_default_text_button_center(txt_bounds, paste_txt, true);
        paste_from_clipboard.draw();

        if (paste_from_clipboard.is_clicked()) {
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
};

fn draw_manual_button(dm_state: *Client.DMState, rect: C.Rectangle) void {
    if (C.IsKeyPressed(C.KEY_ESCAPE)) {
        dm_state.* = .{ .NotManual = {} };
        return;
    }

    const choose_manual_txt = "Choose manual";

    const choose_manual_button = Button(u8).init_default_text_button_center(rect, choose_manual_txt, true);
    choose_manual_button.draw();

    if (choose_manual_button.is_clicked()) {
        switch (dm_state.*) {
            .Manual => dm_state.* = .{ .NotManual = {} },
            .NotManual => dm_state.* = .{ .Manual = .{} },
        }
    }
}

fn set_target_id(target_id_ptr: *?[32]u8, target_id: [64]u8, dm_state: *Client.DMState) !void {
    var target_id_unwrap: [32]u8 = undefined;

    _ = try std.fmt.hexToBytes(&target_id_unwrap, &target_id);

    target_id_ptr.* = target_id_unwrap;

    dm_state.* = .{ .NotManual = {} };
}

fn display_target_id(id: [32]u8, messages_count: usize, target_id: *?[32]u8, bounds: C.Rectangle) !void {
    var target_id_button = Button(u8).init_default_center(bounds, true);

    if (target_id.*) |target| {
        if (std.mem.eql(u8, &id, &target)) {
            target_id_button.bg = C.BLUE;
        }
    }

    target_id_button.draw();

    if (target_id_button.is_clicked()) {
        target_id.* = id;
        return;
    }

    const id_hex = std.fmt.bytesToHex(id, .lower);

    var button_txt_bounds = target_id_button.txt_bounds;
    button_txt_bounds.height /= 2;

    txt_mod.drawText(u8, &id_hex, button_txt_bounds, GUI.FONT_SIZE, C.WHITE, .{ .x = .Center, .y = .Center });

    const number_of_messages_text = try std.fmt.allocPrint(allocator, "{d} message(s)", .{messages_count});
    defer allocator.free(number_of_messages_text);

    button_txt_bounds.y += bounds.height;

    txt_mod.drawText(u8, number_of_messages_text, button_txt_bounds, GUI.FONT_SIZE, C.WHITE, .{ .x = .Center, .y = .Center });
}
