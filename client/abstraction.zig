const gui = @import("gui.zig");
const cli = @import("cli.zig");
const std = @import("std");

var is_GUI: bool = undefined;

//// Choose if GUI or CLI
pub fn init(is_gui: bool) void {
    is_GUI = is_gui;

    if (is_gui) {
        gui.init();
    }
}

pub fn connect_to_server(next_args: [][:0]u8) !std.net.Stream {
    return switch (is_GUI) {
        true => try gui.connect_to_server(),
        false => try cli.connect_to_server(next_args),
    };
}

pub fn handle_auth(stream: std.net.Stream) !std.crypto.dh.X25519.KeyPair {
    return switch (is_GUI) {
        true => try gui.handle_auth(stream),
        false => try cli.handle_auth(stream),
    };
}

pub fn handle_new_message(author: [32]u8, dm: ?[32]u8, message: []const u8) !void {
    switch (is_GUI) {
        true => try gui.handle_new_message(author, dm, message),
        false => cli.handle_new_message(author, dm, message),
    }
}

pub fn ask_target_id(my_id: [32]u8) ![32]u8 {
    return switch (is_GUI) {
        true => try gui.ask_target_id(my_id),
        false => try cli.ask_target_id(),
    };
}

pub fn ask_message(my_id: [32]u8, dm: [32]u8) ![]u8 {
    return switch (is_GUI) {
        true => try gui.ask_message(my_id, dm),
        false => try cli.ask_message(),
    };
}

pub fn deinit() void {
    if (is_GUI) {
        gui.deinit();
    }
}
