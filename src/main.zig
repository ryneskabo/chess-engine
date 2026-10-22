const std = @import("std");
const Io = std.Io;

const chess_engine = @import("chess_engine");

pub fn main() !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}

