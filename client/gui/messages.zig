const std = @import("std");

const HashMapContext = @import("../../id_hashmap_ctx.zig").HashMapContext;

const HashMapType = std.HashMap([32]u8, std.ArrayList(Message), HashMapContext, 70);

const Mutex = @import("../../mutex.zig").Mutex;

const allocator = std.heap.page_allocator;

pub var messages: Mutex(HashMapType) = undefined;

pub fn insert_message(discussion_id: [32]u8, msg: Message) !void {
    const messages_lock = messages.lock();
    defer messages.unlock();

    const entry = try messages_lock.getOrPut(discussion_id);
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
    messages = Mutex(HashMapType).init(HashMapType.init(allocator));
}

pub fn deinit() void {
    var iterator = messages._data.valueIterator();

    while (iterator.next()) |value| {
        for (value.items) |message| {
            allocator.free(message.content);
        }
        value.deinit();
    }

    messages._data.deinit();
}

const NEW_MESSAGE_SOUND = @embedFile("media/new-notification.mp3");

///`dm` is set when the author is myself, to someone else
pub fn handle_new_message(author: [32]u8, dm: ?[32]u8, message: []const u8) !void {
    const discussion_id = if (dm) |dm_id| dm_id else author;
    const sender = if (dm) |_| DMMessageAuthor.Me else DMMessageAuthor.NotMe;

    const owned_message = try allocator.dupeZ(u8, message);

    std.log.info("New message received : {s}", .{owned_message});

    if (sender == .Me) {
        const C = @import("c.zig").C;
        const wave = C.LoadWaveFromMemory(".mp3", NEW_MESSAGE_SOUND, NEW_MESSAGE_SOUND.len);
        const sound = C.LoadSoundFromWave(wave);
        C.PlaySound(sound);
    }

    try insert_message(discussion_id, .{ .content = owned_message, .sent_by = sender });
}
