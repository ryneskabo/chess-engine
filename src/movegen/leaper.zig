const std = @import("std");
const fen = @import("../fen.zig");
const brd = @import("../board.zig");
const att = @import("../attacks.zig");
const move = @import("move.zig");

const Board = brd.Board;
const Color = brd.Color;
const Piece = brd.Piece;

const Move = move.Move;
const MoveFlags = move.MoveFlags;
const MoveList = move.MoveList;
const addMovesFromTargets = move.addMovesFromTargets;

pub fn leaperMoves(board: *const Board, color: Color, comptime piece: Piece, move_list: *MoveList) void {
    var bb = board.getBoard(color, piece);
    const attack_table = switch (piece) {
        .knight => &att.knight_attacks,
        .king => &att.king_attacks,
        else => @compileError("leaperMoves needs a knight or king"),
    };
    const own_occupancy = board.occupancy[@backingInt(color)];
    const opponent_occupancy = board.occupancy[@backingInt(color.opposite())];

    while (bb != 0) : (bb &= bb - 1) {
        const sq: brd.Square = @intCast(@ctz(bb));
        const targets = attack_table[sq] & ~own_occupancy;

        addMovesFromTargets(move_list, sq, targets, opponent_occupancy);
    }
}

test "knight on e4 in an empty board produces 8 quiet moves" {
    const b = try fen.parseFen("8/8/8/8/4N3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 8), list.count);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expectEqual(MoveFlags.quiet_move, m.flags);
    }
}

test "knight on e4 with a friendly piece on one target produces 7 quiet moves" {
    // White knight on e4 (28), friendly pawn on d6 (43)
    const b = try fen.parseFen("8/8/3P4/8/4N3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 7), list.count);
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expectEqual(MoveFlags.quiet_move, m.flags);
        try std.testing.expect(m.to != 43);
    }
}

test "knight on e4 with an enemy piece on one target produces 7 quiet moves and 1 capture" {
    // White knight on e4 (28), black pawn on d6 (43)
    const b = try fen.parseFen("8/8/3p4/8/4N3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 8), list.count);

    var quiet_count: usize = 0;
    var capture_count: usize = 0;
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        if (m.flags == .quiet_move) {
            quiet_count += 1;
            try std.testing.expect(m.to != 43);
        } else if (m.flags == .capture) {
            capture_count += 1;
            try std.testing.expectEqual(@as(brd.Square, 43), m.to);
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 7), quiet_count);
    try std.testing.expectEqual(@as(usize, 1), capture_count);
}

test "knight on a1 produces 2 moves" {
    const b = try fen.parseFen("8/8/8/8/8/8/8/N7 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .knight, &list);

    try std.testing.expectEqual(@as(u16, 2), list.count);
    // a1 (0) -> c2 (10), b3 (17)
    try std.testing.expectEqual(Move{ .from = 0, .to = 10, .flags = .quiet_move }, list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 0, .to = 17, .flags = .quiet_move }, list.moves[1]);
}

test "king on e4 produces 8 moves and king on a1 produces 3" {
    const b_center = try fen.parseFen("8/8/8/8/4K3/8/8/8 w - - 0 1");
    var center_list = MoveList{};
    leaperMoves(&b_center, .white, .king, &center_list);

    try std.testing.expectEqual(@as(u16, 8), center_list.count);
    for (center_list.moves[0..center_list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expectEqual(MoveFlags.quiet_move, m.flags);
    }

    const b_corner = try fen.parseFen("8/8/8/8/8/8/8/K7 w - - 0 1");
    var corner_list = MoveList{};
    leaperMoves(&b_corner, .white, .king, &corner_list);

    try std.testing.expectEqual(@as(u16, 3), corner_list.count);
    // a1 (0) -> b1 (1), a2 (8), b2 (9)
    try std.testing.expectEqual(Move{ .from = 0, .to = 1, .flags = .quiet_move }, corner_list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 0, .to = 8, .flags = .quiet_move }, corner_list.moves[1]);
    try std.testing.expectEqual(Move{ .from = 0, .to = 9, .flags = .quiet_move }, corner_list.moves[2]);
}

test "starting position leaper moves: 4 knight moves and 0 king moves for both sides" {
    const b = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    // White: 4 knight moves (b1->a3, b1->c3, g1->f3, g1->h3) and 0 king moves
    var white_king_list = MoveList{};
    leaperMoves(&b, .white, .king, &white_king_list);
    try std.testing.expectEqual(@as(u16, 0), white_king_list.count);

    var white_list = MoveList{};
    leaperMoves(&b, .white, .knight, &white_list);
    leaperMoves(&b, .white, .king, &white_list);
    try std.testing.expectEqual(@as(u16, 4), white_list.count);
    try std.testing.expectEqual(Move{ .from = 1, .to = 16, .flags = .quiet_move }, white_list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 1, .to = 18, .flags = .quiet_move }, white_list.moves[1]);
    try std.testing.expectEqual(Move{ .from = 6, .to = 21, .flags = .quiet_move }, white_list.moves[2]);
    try std.testing.expectEqual(Move{ .from = 6, .to = 23, .flags = .quiet_move }, white_list.moves[3]);

    // Black: 4 knight moves (b8->a6, b8->c6, g8->f6, g8->h6) and 0 king moves
    var black_list = MoveList{};
    leaperMoves(&b, .black, .knight, &black_list);
    leaperMoves(&b, .black, .king, &black_list);
    try std.testing.expectEqual(@as(u16, 4), black_list.count);
    try std.testing.expectEqual(Move{ .from = 57, .to = 40, .flags = .quiet_move }, black_list.moves[0]);
    try std.testing.expectEqual(Move{ .from = 57, .to = 42, .flags = .quiet_move }, black_list.moves[1]);
    try std.testing.expectEqual(Move{ .from = 62, .to = 45, .flags = .quiet_move }, black_list.moves[2]);
    try std.testing.expectEqual(Move{ .from = 62, .to = 47, .flags = .quiet_move }, black_list.moves[3]);
}

test "king captures enemy piece and is blocked by friendly piece" {
    // White king on e4 (28), friendly pawn on e5 (36), black pawn on d5 (35)
    const b = try fen.parseFen("8/8/8/3pP3/4K3/8/8/8 w - - 0 1");
    var list = MoveList{};
    leaperMoves(&b, .white, .king, &list);

    try std.testing.expectEqual(@as(u16, 7), list.count);

    var quiet_count: usize = 0;
    var capture_count: usize = 0;
    for (list.moves[0..list.count]) |m| {
        try std.testing.expectEqual(@as(brd.Square, 28), m.from);
        try std.testing.expect(m.to != 36); // blocked by own pawn on e5
        if (m.flags == .quiet_move) {
            quiet_count += 1;
        } else if (m.flags == .capture) {
            capture_count += 1;
            try std.testing.expectEqual(@as(brd.Square, 35), m.to);
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 6), quiet_count);
    try std.testing.expectEqual(@as(usize, 1), capture_count);
}
