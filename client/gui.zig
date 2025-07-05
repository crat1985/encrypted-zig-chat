const C = @import("gui/c.zig").C;
const std = @import("std");
pub const connect_to_server = @import("gui/connect_screen.zig").connect_to_server;
pub const handle_auth = @import("gui/auth_screen.zig").handle_auth;
const messages = @import("gui/messages.zig");
pub const handle_new_message = messages.handle_new_message;
pub const ask_target_id = @import("gui/dm_chooser_screen.zig").ask_target_id;
pub const ask_message = @import("gui/dm_screen.zig").ask_message;

pub var WIDTH: c_int = 720;
pub var HEIGHT: c_int = 480;

const allocator = std.heap.page_allocator;

pub fn init() void {
    messages.init();

    C.SetExitKey(C.KEY_NULL);

    C.InitWindow(@intCast(WIDTH), @intCast(HEIGHT), "Encrypted Zig chat");

    C.InitAudioDevice();
}

pub const FONT_SIZE = 20;
pub const button_padding = 10;

pub fn deinit() void {
    C.CloseAudioDevice();
    C.CloseWindow();
    messages.deinit();
}

test "Test basic window with text and rectangles" {
    init();
    defer deinit();
    _ = try connect_to_server();
}
