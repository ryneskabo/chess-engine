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

const PerftArgs = struct {
    fen_string: []u8,
    board: chess.board.Board,
    depth: u32,
};

const PerftArgError = error{
    MissingArgs,
    InvalidDepth,
    OutOfMemory,
} || chess.fen.InvalidFen;

fn parsePerftArgs(allocator: std.mem.Allocator, args: []const [:0]const u8) PerftArgError!PerftArgs {
    if (args.len < 2) return error.MissingArgs;

    const depth_arg = args[args.len - 1];
    const depth = std.fmt.parseUnsigned(u32, depth_arg, 10) catch return error.InvalidDepth;

    const fen_string = try joinFen(allocator, args[0 .. args.len - 1]);
    errdefer allocator.free(fen_string);

    const board = try chess.fen.parseFen(fen_string);
    return .{
        .fen_string = fen_string,
        .board = board,
        .depth = depth,
    };
}

fn computeNps(nodes: u64, elapsed_ns: i96) u64 {
    return if (elapsed_ns > 0)
        @intCast(@as(u128, nodes) * std.time.ns_per_s / @as(u128, @intCast(elapsed_ns)))
    else
        0;
}

fn writePerftReport(writer: *std.Io.Writer, fen_string: []const u8, depth: u32, nodes: u64, elapsed_ns: i96) !void {
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    const nps = computeNps(nodes, elapsed_ns);

    try writer.print("FEN:   {s}\n", .{fen_string});
    try writer.print("Depth: {d}\n", .{depth});
    try writer.print("Nodes: {d}\n", .{nodes});
    try writer.print("Time:  {d:.3}s\n", .{elapsed_s});
    try writer.print("NPS:   {d}\n", .{nps});
}

fn runPerft(io: std.Io, arena: std.mem.Allocator, args: []const [:0]const u8) !void {
    const parsed = parsePerftArgs(arena, args) catch |err| switch (err) {
        error.MissingArgs => std.process.fatal("perft requires a FEN and a depth\n\n{s}", .{usage}),
        error.InvalidDepth => std.process.fatal("invalid depth: '{s}'", .{args[args.len - 1]}),
        error.OutOfMemory => return error.OutOfMemory,
        else => |fen_err| {
            const fen_string = try joinFen(arena, args[0 .. args.len - 1]);
            std.process.fatal("invalid FEN '{s}': {t}", .{ fen_string, fen_err });
        },
    };

    const start_ns = std.Io.Clock.awake.now(io).nanoseconds;
    const nodes = chess.movegen.perft(&parsed.board, parsed.depth);
    const elapsed_ns = std.Io.Clock.awake.now(io).nanoseconds - start_ns;

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try writePerftReport(stdout, parsed.fen_string, parsed.depth, nodes, elapsed_ns);
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

test "parsePerftArgs accepts quoted or split FEN and rejects malformed args" {
    const allocator = std.testing.allocator;

    const quoted = try parsePerftArgs(allocator, &.{ "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "3" });
    defer allocator.free(quoted.fen_string);
    try std.testing.expectEqual(@as(u32, 3), quoted.depth);
    try std.testing.expectEqualStrings("4k3/8/8/8/8/8/8/4K3 w - - 0 1", quoted.fen_string);

    const split = try parsePerftArgs(allocator, &.{ "4k3/8/8/8/8/8/8/4K3", "w", "-", "-", "0", "1", "4" });
    defer allocator.free(split.fen_string);
    try std.testing.expectEqual(@as(u32, 4), split.depth);
    try std.testing.expectEqualDeep(quoted.board, split.board);

    try std.testing.expectError(error.MissingArgs, parsePerftArgs(allocator, &.{}));
    try std.testing.expectError(error.MissingArgs, parsePerftArgs(allocator, &.{"4k3/8/8/8/8/8/8/4K3 w - - 0 1"}));
    try std.testing.expectError(error.InvalidDepth, parsePerftArgs(allocator, &.{ "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "abc" }));
    try std.testing.expectError(error.InvalidDepth, parsePerftArgs(allocator, &.{ "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "-1" }));
    try std.testing.expectError(chess.fen.InvalidFen.InvalidPiecePlacement, parsePerftArgs(allocator, &.{ "invalid-fen", "2" }));
}

test "computeNps and writePerftReport format output and handle zero elapsed time" {
    try std.testing.expectEqual(@as(u64, 0), computeNps(1000, 0));
    try std.testing.expectEqual(@as(u64, 0), computeNps(1000, -5));
    try std.testing.expectEqual(@as(u64, 2000), computeNps(1000, std.time.ns_per_s / 2));

    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try writePerftReport(&writer, "4k3/8/8/8/8/8/8/4K3 w - - 0 1", 2, 25, std.time.ns_per_s / 4);

    const expected =
        \\FEN:   4k3/8/8/8/8/8/8/4K3 w - - 0 1
        \\Depth: 2
        \\Nodes: 25
        \\Time:  0.250s
        \\NPS:   100
        \\
    ;
    try std.testing.expectEqualStrings(expected, writer.buffered());
}
