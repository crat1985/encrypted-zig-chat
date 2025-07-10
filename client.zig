const std = @import("std");
const api = @import("client/api.zig");
const GUI = @import("client/gui.zig");
const C = @import("client/gui/c.zig").C;
const mutex = @import("mutex.zig");
const Mutex = mutex.Mutex;
const request = @import("client/api/request.zig");
const Font = @import("client/gui/font.zig");
const listen = @import("client/api/listen.zig");
const txt_mod = @import("client/gui/txt.zig");

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub const DMState = union(enum) {
    Manual: struct {
        manual_target_id: [64:0]u8 = std.mem.zeroes([64:0]u8),
        manual_target_id_index: usize = 0,
    },
    NotManual: void,
};

pub fn init_everything() void {
    GUI.init();
    request.send_requests = std.AutoHashMap(u64, request.SendRequest).init(allocator);
    request.receive_requests = std.AutoHashMap(u64, request.ReceiveRequest).init(allocator);
    request.unvalidated_receive_requests = std.AutoHashMap(u64, request.ReceiveRequest).init(allocator);
}

pub fn deinit_everything() void {
    request.unvalidated_receive_requests.deinit();
    request.receive_requests.deinit();

    request.send_requests.deinit();

    GUI.deinit();
}

pub fn main() !void {
    init_everything();
    defer deinit_everything();

    const _stream = try GUI.connect_to_server();
    defer _stream.close();
    api.init(_stream.writer().any());

    const x25519_key_pair = try GUI.handle_auth(_stream.reader().any());

    const pubkey = x25519_key_pair.public_key;

    {
        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("You were authenticated as {s}", .{hex_pubkey});
    }

    _ = try std.Thread.spawn(.{}, api.listen.read_messages, .{ x25519_key_pair.secret_key, x25519_key_pair.public_key, _stream.reader().any() });

    var target_id: ?[32]u8 = null;

    var cursor = C.MOUSE_CURSOR_DEFAULT;

    var dm_state: DMState = .{ .NotManual = {} };

    var current_message: [:0]c_int = try allocator.allocSentinel(c_int, 0, 0);
    defer allocator.free(current_message);

    while (!C.WindowShouldClose()) {
        cursor = C.MOUSE_CURSOR_DEFAULT;

        C.BeginDrawing();
        defer C.EndDrawing();

        defer C.SetMouseCursor(cursor);

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @floatFromInt(C.GetScreenWidth());
        GUI.HEIGHT = @floatFromInt(C.GetScreenHeight());

        var bounds = C.Rectangle{
            .x = 0,
            .y = 0,
            .width = GUI.WIDTH,
            .height = GUI.HEIGHT,
        };

        {
            const top_left_display_bounds = C.Rectangle{
                .x = 0,
                .y = 0,
                .width = GUI.WIDTH,
                .height = GUI.FONT_SIZE,
            };

            try @import("client/gui/id_top_left_display.zig").draw_id_top_left_display(pubkey, &cursor, top_left_display_bounds);

            bounds.y += top_left_display_bounds.height;
            bounds.height -= top_left_display_bounds.height;
        }

        const is_there_req = request.receive_requests.count() != 0 or request.unvalidated_receive_requests.count() != 0;

        {
            const sidebar_width = if (target_id) |_| GUI.WIDTH / 4 else if (is_there_req) GUI.WIDTH * 3 / 4 else GUI.WIDTH;

            const sidebar_rect = C.Rectangle{
                .x = bounds.x,
                .y = bounds.y,
                .width = sidebar_width,
                .height = bounds.height,
            };

            try GUI.draw_choose_discussion_sidebar(sidebar_rect, &dm_state, &target_id);

            bounds.x += sidebar_rect.width;
            bounds.width -= sidebar_rect.width;
        }

        if (target_id) |target| {
            //the line vertical separator
            C.DrawLineV(.{ .x = bounds.x, .y = bounds.y }, .{ .x = bounds.x, .y = bounds.y + bounds.height }, C.WHITE);

            const dm_screen_width = if (is_there_req) bounds.width * 3 / 4 else bounds.width;

            const dm_screen_bounds = C.Rectangle{
                .x = bounds.x,
                .y = bounds.y,
                .width = dm_screen_width,
                .height = bounds.height,
            };

            const target_id_parsed = std.crypto.dh.X25519.Curve.fromBytes(target);

            const symmetric_key = try get_symmetric_key(target_id_parsed, x25519_key_pair.secret_key);

            const message_keyboard_enabled = switch (dm_state) {
                .NotManual => true,
                .Manual => false,
            };

            try GUI.draw_dm_screen(pubkey, target, &current_message, dm_screen_bounds, message_keyboard_enabled, &cursor, symmetric_key, &target_id);

            if (C.IsFileDropped()) {
                try handle_files_dropped(symmetric_key, target);
            }

            bounds.x += dm_screen_bounds.width;
            bounds.width -= dm_screen_bounds.width;
        }

        if (is_there_req) {
            bounds.height /= 4;
            try draw_message_request(bounds, &cursor);

            bounds.y += bounds.height;

            try draw_validated_message_request_avancement(bounds);
        }
    }
}

fn handle_files_dropped(symmetric_key: [32]u8, target_id: [32]u8) !void {
    const files = C.LoadDroppedFiles();
    defer C.UnloadDroppedFiles(files);

    const files_slice = files.paths[0..@intCast(files.count)];

    for (files_slice) |file_path| {
        const file_path_n = C.TextLength(file_path);

        const file_name = C.GetFileName(file_path);
        const file_name_n: usize = @intCast(C.TextLength(file_name));
        var file_name_array: [255]u8 = undefined;
        @memcpy(file_name_array[0..file_name_n], file_name[0..file_name_n]);

        const file = try std.fs.openFileAbsolute(file_path[0..file_path_n], .{});

        const msg = request.SendRequest{
            .symmetric_key = symmetric_key,
            .target_id = target_id,
            .data = .{
                .file = .{
                    .file = file,
                    .name = file_name_array,
                    .name_len = @intCast(file_name_n),
                    .size = (try file.metadata()).size(),
                },
            },
        };

        try request.send_request(msg);
    }
}

pub fn get_symmetric_key(public_key: std.crypto.ecc.Curve25519, priv_key: [32]u8) ![32]u8 {
    return (try public_key.clampedMul(priv_key)).toBytes();
}

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
    defer allocator.free(message_req_msg);

    const txt_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width,
        .height = bounds.height / 2,
    };

    txt_mod.drawText(u8, message_req_msg, txt_bounds, GUI.FONT_SIZE, C.WHITE, .{ .x = .Center, .y = .Center });

    const side = @min(bounds.height / 2, bounds.width / 5);

    const accept_rect = C.Rectangle{
        .x = bounds.x,
        .y = txt_bounds.y + txt_bounds.height,
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

    var txt_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width,
        .height = bounds.height / 3,
    };

    txt_mod.drawText(u8, message_req_msg, txt_bounds, GUI.FONT_SIZE, C.WHITE, .{ .x = .Center, .y = .Center });

    const done = @min(@as(u64, value.index) * @import("client/api/constants.zig").PAYLOAD_AND_PADDING_SIZE, value.total_size);

    const avancement: f32 = @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(value.total_size));

    const avancement_text = try std.fmt.allocPrint(allocator, "{d:.2}%", .{avancement * 100});
    defer allocator.free(avancement_text);

    txt_bounds.y += txt_bounds.height;

    txt_mod.drawText(u8, avancement_text, txt_bounds, GUI.FONT_SIZE, C.WHITE, .{ .x = .Center, .y = .Center });

    txt_bounds.y += txt_bounds.height + 10;
    txt_bounds.x -= 10;
    txt_bounds.height -= 10;
    txt_bounds.width -= 10;

    //Draw the rect lines
    {
        C.DrawLineV(.{ .x = txt_bounds.x, .y = txt_bounds.y }, .{ .x = txt_bounds.x + txt_bounds.width, .y = txt_bounds.y }, C.BLUE);
        C.DrawLineV(.{ .x = txt_bounds.x, .y = txt_bounds.y + txt_bounds.height }, .{ .x = txt_bounds.x + txt_bounds.width, .y = txt_bounds.y + txt_bounds.height }, C.BLUE);
        C.DrawLineV(.{ .x = txt_bounds.x, .y = txt_bounds.y }, .{ .x = txt_bounds.x, .y = txt_bounds.y + txt_bounds.height }, C.BLUE);
        C.DrawLineV(.{ .x = txt_bounds.x + txt_bounds.width, .y = txt_bounds.y }, .{ .x = txt_bounds.x + txt_bounds.width, .y = txt_bounds.y + txt_bounds.height }, C.BLUE);
    }

    const loading_filling_rect = C.Rectangle{
        .x = txt_bounds.x + 2,
        .y = txt_bounds.y + 2,
        .width = (txt_bounds.width - 2) * avancement,
        .height = txt_bounds.height - 2,
    };

    C.DrawRectangleRec(loading_filling_rect, C.BLUE);
}
