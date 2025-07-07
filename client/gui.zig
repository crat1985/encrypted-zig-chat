const C = @import("gui/c.zig").C;
const std = @import("std");
pub const connect_to_server = @import("gui/connect_screen.zig").connect_to_server;
pub const handle_auth = @import("gui/auth_screen.zig").handle_auth;
const messages = @import("gui/messages.zig");
pub const handle_new_message = messages.handle_new_message;
pub const draw_choose_discussion_sidebar = @import("gui/dm_chooser_screen.zig").draw_choose_discussion_sidebar;
pub const draw_dm_screen = @import("gui/dm_screen.zig").draw_dm_screen;

pub var WIDTH: c_int = 720;
pub var HEIGHT: c_int = 480;

const allocator = std.heap.page_allocator;

const NEW_MESSAGE_SOUND_FILE_CONTENT = @embedFile("gui/media/new-notification.mp3");
pub var NEW_MESSAGE_NOTIFICATION_SOUND: C.Sound = undefined;

pub fn init() void {
    messages.init();

    // C.SetExitKey(C.KEY_NULL);

    C.InitWindow(@intCast(WIDTH), @intCast(HEIGHT), "Encrypted Zig chat");

    C.SetTargetFPS(60);

    C.InitAudioDevice();

    const wave = C.LoadWaveFromMemory(".mp3", NEW_MESSAGE_SOUND_FILE_CONTENT, NEW_MESSAGE_SOUND_FILE_CONTENT.len);
    NEW_MESSAGE_NOTIFICATION_SOUND = C.LoadSoundFromWave(wave);
}

pub const FONT_SIZE = 20;
pub const button_padding = 10;

pub fn deinit() void {
    C.UnloadSound(NEW_MESSAGE_NOTIFICATION_SOUND);
    C.CloseAudioDevice();
    C.CloseWindow();
    messages.deinit();
}
