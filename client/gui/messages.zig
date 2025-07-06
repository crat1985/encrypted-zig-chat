const std = @import("std");
const GUI = @import("../gui.zig");

const HashMapContext = @import("../../id_hashmap_ctx.zig").HashMapContext;

const HashMapType = std.HashMap([32]u8, std.ArrayList(Message), HashMapContext, 70);

const Mutex = @import("../../mutex.zig").Mutex;

const allocator = std.heap.page_allocator;

pub var messages: HashMapType = undefined;

pub fn insert_message(discussion_id: [32]u8, msg: Message) !void {
    const entry = try messages.getOrPut(discussion_id);
    if (entry.found_existing) {
        try entry.value_ptr.append(msg);
    } else {
        var list = std.ArrayList(Message).init(allocator);
        try list.append(msg);
        entry.value_ptr.* = list;
    }
}

pub const DMMessageAuthor = enum(u1) {
    Me,
    NotMe,
};

pub const Message = struct {
    sent_by: DMMessageAuthor,
    content: [:0]u8,
};

pub fn init() void {
    messages = HashMapType.init(allocator);
}

pub fn deinit() void {
    defer messages.deinit();

    var iterator = messages.valueIterator();

    while (iterator.next()) |value| {
        for (value.items) |message| {
            allocator.free(message.content);
        }
        value.deinit();
    }
}

///`dm` is set when the author is myself, to someone else
pub fn handle_new_message(msg: Message, dm_id: [32]u8) !void {
    std.log.info("New message received : {s}", .{msg.content});

    if (msg.sent_by != .Me) {
        const C = @import("c.zig").C;

        C.PlaySound(GUI.NEW_MESSAGE_NOTIFICATION_SOUND);
    }

    try insert_message(dm_id, msg);
}
