const std = @import("std");
const chess = @import("chess-engine");

const usage =
    \\Usage: chess-engine <command> [args]
    \\
    \\Commands:
    \\  perft <fen> <depth>  Count legal leaf nodes at the given depth.
    \\                       Quote the FEN, or pass its fields as separate args.
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    const command = args[1];
    if (std.mem.eql(u8, command, "perft")) {
        try runPerft(io, arena, args[2..]);
        return;
    }

    if (std.mem.eql(u8, command, "help") or
        std.mem.eql(u8, command, "--help") or
        std.mem.eql(u8, command, "-h"))
    {
        try std.Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    std.process.fatal("unknown command: {s}\n\n{s}", .{ command, usage });
}

fn runPerft(io: std.Io, arena: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.process.fatal("perft requires a FEN and a depth\n\n{s}", .{usage});
    }

    const depth_arg = args[args.len - 1];
    const depth = std.fmt.parseUnsigned(u32, depth_arg, 10) catch
        std.process.fatal("invalid depth: '{s}'", .{depth_arg});

    const fen_string = try joinFen(arena, args[0 .. args.len - 1]);
    const board = chess.fen.parseFen(fen_string) catch |err|
        std.process.fatal("invalid FEN '{s}': {t}", .{ fen_string, err });

    const start_ns = std.Io.Clock.awake.now(io).nanoseconds;
    const nodes = chess.movegen.perft(&board, depth);
    const elapsed_ns = std.Io.Clock.awake.now(io).nanoseconds - start_ns;
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    const nps: u64 = if (elapsed_ns > 0)
        @intCast(@as(u128, nodes) * std.time.ns_per_s / @as(u128, @intCast(elapsed_ns)))
    else
        0;

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("FEN:   {s}\n", .{fen_string});
    try stdout.print("Depth: {d}\n", .{depth});
    try stdout.print("Nodes: {d}\n", .{nodes});
    try stdout.print("Time:  {d:.3}s\n", .{elapsed_s});
    try stdout.print("NPS:   {d}\n", .{nps});
    try stdout.flush();
}

/// Joins command-line arguments with spaces, so the FEN can be passed either as
/// one quoted argument or as its individual fields.
fn joinFen(allocator: std.mem.Allocator, parts: []const [:0]const u8) ![]u8 {
    const slices = try allocator.alloc([]const u8, parts.len);
    defer allocator.free(slices);

    for (parts, slices) |part, *slice| slice.* = part;
    return std.mem.join(allocator, " ", slices);
}

test "joinFen accepts a quoted FEN or separate fields" {
    const allocator = std.testing.allocator;

    const quoted = try joinFen(allocator, &.{"4k3/8/8/8/8/8/8/4K3 w - - 0 1"});
    defer allocator.free(quoted);
    try std.testing.expectEqualStrings("4k3/8/8/8/8/8/8/4K3 w - - 0 1", quoted);

    const split = try joinFen(allocator, &.{ "4k3/8/8/8/8/8/8/4K3", "w", "-", "-", "0", "1" });
    defer allocator.free(split);
    try std.testing.expectEqualStrings("4k3/8/8/8/8/8/8/4K3 w - - 0 1", split);
}
