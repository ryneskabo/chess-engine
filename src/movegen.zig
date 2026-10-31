const std = @import("std");
const fen = @import("fen.zig");
const brd = @import("board.zig");

const Board = brd.Board;
const Color = brd.Color;
const Piece = brd.Piece;
const rank_3: u64 = 0x0000000000FF0000;
const rank_6: u64 = 0x0000FF0000000000;
pub fn generatePawnPushes(board: *const Board, color: Color) struct { single: u64, double: u64 } {
    const occupied = board.occupancy[@backingInt(Color.white)] | board.occupancy[@backingInt(Color.black)];
    const empty = ~occupied;

    const pawns = board.pieces[@backingInt(color)][@backingInt(Piece.pawn)];
    if (color == .white) {
        const single_push = (pawns << 8) & empty;
        const double_push = ((single_push & rank_3) << 8) & empty;
        return .{ .single = single_push, .double = double_push };
    } else {
        const single_push = (pawns >> 8) & empty;
        const double_push = ((single_push & rank_6) >> 8) & empty;
        return .{ .single = single_push, .double = double_push };
    }
}

const squareBit = brd.squareBit;

test "pushes from the starting position" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    const w = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(@as(u64, 0x0000000000FF0000), w.single); // rank 3
    try std.testing.expectEqual(@as(u64, 0x00000000FF000000), w.double); // rank 4

    const k = generatePawnPushes(&b, .black);
    try std.testing.expectEqual(@as(u64, 0x0000FF0000000000), k.single); // rank 6
    try std.testing.expectEqual(@as(u64, 0x000000FF00000000), k.double); // rank 5
}

test "white pawn on e2 with a clear path" {
    const b = try fen.parseFen("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(20), p.single); // e3
    try std.testing.expectEqual(squareBit(28), p.double); // e4
}

test "enemy piece directly in front blocks both pushes" {
    const b = try fen.parseFen("4k3/8/8/8/8/4p3/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(@as(u64, 0), p.single);
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "own piece directly in front blocks both pushes" {
    const b = try fen.parseFen("4k3/8/8/8/8/4N3/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(@as(u64, 0), p.single);
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "piece two squares ahead blocks only the double push" {
    const b = try fen.parseFen("4k3/8/8/8/4p3/8/4P3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(20), p.single); // e3
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "pawn off its starting rank gets no double push" {
    const b = try fen.parseFen("4k3/8/8/8/8/4P3/8/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(28), p.single); // e4
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "one blocked pawn does not affect its neighbor" {
    // d2 is blocked by the black pawn on d3, e2 is free
    const b = try fen.parseFen("4k3/8/8/8/8/3p4/3PP3/4K3 w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(20), p.single); // e3
    try std.testing.expectEqual(squareBit(28), p.double); // e4
}

test "black pawn on e7 with a clear path" {
    const b = try fen.parseFen("4k3/4p3/8/8/8/8/8/4K3 b - - 0 1");
    const p = generatePawnPushes(&b, .black);
    try std.testing.expectEqual(squareBit(44), p.single); // e6
    try std.testing.expectEqual(squareBit(36), p.double); // e5
}

test "black pawn blocked by a white piece" {
    const b = try fen.parseFen("4k3/4p3/4P3/8/8/8/8/4K3 b - - 0 1");
    const p = generatePawnPushes(&b, .black);
    try std.testing.expectEqual(@as(u64, 0), p.single);
    try std.testing.expectEqual(@as(u64, 0), p.double);
}

test "pawn on the seventh rank pushes onto the last rank" {
    // Needed later for promotion: the push must land on e8 and shift nothing off the board.
    const b = try fen.parseFen("8/4P3/8/8/8/8/8/K6k w - - 0 1");
    const p = generatePawnPushes(&b, .white);
    try std.testing.expectEqual(squareBit(60), p.single); // e8
    try std.testing.expectEqual(@as(u64, 0), p.double);
}
