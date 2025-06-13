const Queue = @import("queue.zig").Queue;

///0
pub var read_messages_receive_queue: Queue = undefined;
///1
pub var send_actions_receive_queue: Queue = undefined;
