const std = @import("std");
const api = @import("client/api.zig");
const GUI = @import("client/gui.zig");
const C = @import("client/gui/c.zig").C;
const mutex = @import("mutex.zig");
const Mutex = mutex.Mutex;
const request = @import("client/api/request.zig");

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

        GUI.WIDTH = C.GetScreenWidth();
        GUI.HEIGHT = C.GetScreenHeight();

        const sidebar_rect = C.Rectangle{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(if (target_id) |_| @divTrunc(GUI.WIDTH, 4) else GUI.WIDTH),
            .height = @floatFromInt(GUI.HEIGHT),
        };

        try GUI.draw_choose_discussion_sidebar(pubkey, &target_id, &cursor, sidebar_rect, &dm_state);

        if (target_id) |target| {
            const target_id_parsed = std.crypto.dh.X25519.Curve.fromBytes(target);

            const symmetric_key = try get_symmetric_key(target_id_parsed, x25519_key_pair.secret_key);

            const bounds = C.Rectangle{
                .x = sidebar_rect.width,
                .y = 0,
                .width = @as(f32, @floatFromInt(GUI.WIDTH)) - sidebar_rect.width,
                .height = @floatFromInt(GUI.HEIGHT),
            };

            const message_keyboard_enabled = switch (dm_state) {
                .NotManual => true,
                .Manual => false,
            };

            try GUI.draw_dm_screen(pubkey, target, &current_message, bounds, message_keyboard_enabled, &cursor, symmetric_key, &target_id);

            C.DrawLineV(.{ .x = sidebar_rect.x + sidebar_rect.width, .y = sidebar_rect.y }, .{ .x = sidebar_rect.x + sidebar_rect.width, .y = sidebar_rect.y + sidebar_rect.height }, C.WHITE);

            if (C.IsFileDropped()) {
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
                        .target_id = target,
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
        }
    }
}

pub fn get_symmetric_key(public_key: std.crypto.ecc.Curve25519, priv_key: [32]u8) ![32]u8 {
    return (try public_key.clampedMul(priv_key)).toBytes();
}

const allocator = std.heap.page_allocator;
