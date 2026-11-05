const std = @import("std");
const fen = @import("../fen.zig");
const brd = @import("../board.zig");
const query = @import("../attacks/query.zig");
const leaper_gen = @import("../movegen/leaper.zig");
const pawn_gen = @import("../movegen/pawn.zig");
const slider_gen = @import("../movegen/slider.zig");

const Piece = brd.Piece;

pub const MoveFlags = enum(u4) {
    quiet_move = 0b0000,
    double_pawn_push = 0b0001,
    kingside_castle = 0b0010,
    queenside_castle = 0b0011,
    capture = 0b0100,
    en_passant_capture = 0b0101,
    knight_promotion = 0b1000,
    bishop_promotion = 0b1001,
    rook_promotion = 0b1010,
    queen_promotion = 0b1011,
    knight_promotion_capture = 0b1100,
    bishop_promotion_capture = 0b1101,
    rook_promotion_capture = 0b1110,
    queen_promotion_capture = 0b1111,

    pub fn isPromotion(self: MoveFlags) bool {
        return @backingInt(self) & @as(u4, 0b1000) != 0;
    }

    pub fn isCapture(self: MoveFlags) bool {
        return @backingInt(self) & @as(u4, 0b0100) != 0;
    }

    pub fn piecePromoted(self: MoveFlags) ?Piece {
        if (!self.isPromotion()) return null;

        return switch (@backingInt(self) & @as(u4, 0b0011)) {
            0b0000 => .knight,
            0b0001 => .bishop,
            0b0010 => .rook,
            0b0011 => .queen,
            else => unreachable, // All promotion flags encode one of the four piece bits.
        };
    }
};

pub const Move = packed struct(u16) {
    from: brd.Square,
    to: brd.Square,
    flags: MoveFlags,
};

pub const MoveList = struct {
    moves: [256]Move = undefined,
    count: u16 = 0, // Avoiding overflow

    pub fn add(self: *MoveList, move: Move) void {
        std.debug.assert(self.count < self.moves.len);

        self.moves[self.count] = move;
        self.count += 1;
    }
};

pub const IllegalMove = error{
    InvalidFrom,
    InvalidTo,
    KingInCheck,
};

const quiet_promotion_flags = [_]MoveFlags{
    .knight_promotion,
    .bishop_promotion,
    .rook_promotion,
    .queen_promotion,
};

const capture_promotion_flags = [_]MoveFlags{
    .knight_promotion_capture,
    .bishop_promotion_capture,
    .rook_promotion_capture,
    .queen_promotion_capture,
};

/// Emits all four promotion moves (knight, bishop, rook, queen) for a pawn moving
/// from `from` to `to`, using either quiet or capture promotion flags.
pub fn addPromotionMoves(move_list: *MoveList, from: brd.Square, to: brd.Square, is_capture: bool) void {
    const flags = if (is_capture) capture_promotion_flags else quiet_promotion_flags;
    for (flags) |flag| {
        move_list.add(.{
            .from = from,
            .to = to,
            .flags = flag,
        });
    }
}

pub fn addMovesFromTargets(move_list: *MoveList, from: brd.Square, targets: u64, opponent_occupancy: u64) void {
    var captures = targets & opponent_occupancy;
    var quiet_moves = targets & ~opponent_occupancy;

    while (quiet_moves != 0) : (quiet_moves &= quiet_moves - 1) {
        const target_square: brd.Square = @intCast(@ctz(quiet_moves));
        move_list.add(.{
            .from = from,
            .to = target_square,
            .flags = .quiet_move,
        });
    }

    while (captures != 0) : (captures &= captures - 1) {
        const target_square: brd.Square = @intCast(@ctz(captures));
        move_list.add(.{
            .from = from,
            .to = target_square,
            .flags = .capture,
        });
    }
}

fn anySquareAttacked(board: *const brd.Board, squares: u64, by_color: brd.Color) bool {
    var remaining = squares;
    while (remaining != 0) : (remaining &= remaining - 1) {
        const square: brd.Square = @intCast(@ctz(remaining));
        if (query.isSquareAttacked(board, square, by_color)) return true;
    }
    return false;
}

fn castlingMoves(board: *const brd.Board, color: brd.Color, list: *MoveList) void {
    if (board.castling_rights == 0) return;

    const king_from: brd.Square = if (color == .white) 4 else 60;
    if (board.getBoard(color, .king) & brd.squareBit(king_from) == 0) return;

    const occupancy = board.occupancy[@backingInt(brd.Color.white)] | board.occupancy[@backingInt(brd.Color.black)];
    const rooks = board.getBoard(color, .rook);
    const enemy = color.opposite();

    const Config = struct {
        right: brd.CastlingRights,
        rook_from: brd.Square,
        king_to: brd.Square,
        empty_squares: u64,
        safe_squares: u64,
        flags: MoveFlags,
    };

    const configs = if (color == .white) [_]Config{
        .{
            .right = brd.white_kingside,
            .rook_from = 7,
            .king_to = 6,
            .empty_squares = brd.squareBit(5) | brd.squareBit(6),
            .safe_squares = brd.squareBit(4) | brd.squareBit(5) | brd.squareBit(6),
            .flags = .kingside_castle,
        },
        .{
            .right = brd.white_queenside,
            .rook_from = 0,
            .king_to = 2,
            .empty_squares = brd.squareBit(1) | brd.squareBit(2) | brd.squareBit(3),
            .safe_squares = brd.squareBit(2) | brd.squareBit(3) | brd.squareBit(4),
            .flags = .queenside_castle,
        },
    } else [_]Config{
        .{
            .right = brd.black_kingside,
            .rook_from = 63,
            .king_to = 62,
            .empty_squares = brd.squareBit(61) | brd.squareBit(62),
            .safe_squares = brd.squareBit(60) | brd.squareBit(61) | brd.squareBit(62),
            .flags = .kingside_castle,
        },
        .{
            .right = brd.black_queenside,
            .rook_from = 56,
            .king_to = 58,
            .empty_squares = brd.squareBit(57) | brd.squareBit(58) | brd.squareBit(59),
            .safe_squares = brd.squareBit(58) | brd.squareBit(59) | brd.squareBit(60),
            .flags = .queenside_castle,
        },
    };

    for (configs) |config| {
        if (board.castling_rights & config.right == 0) continue;
        if (rooks & brd.squareBit(config.rook_from) == 0) continue;
        if (occupancy & config.empty_squares != 0) continue;
        if (anySquareAttacked(board, config.safe_squares, enemy)) continue;

        list.add(.{
            .from = king_from,
            .to = config.king_to,
            .flags = config.flags,
        });
    }
}

pub fn makeMove(old_board: *const brd.Board, move: Move) brd.Board {
    var new_board: brd.Board = old_board.*;
    const mover = old_board.pieceAt(move.from);
    std.debug.assert(mover != null);
    const mover_color = mover.?.color;
    const mover_piece = mover.?.piece;

    // remove captured piece, if there is one
    if (move.flags == .en_passant_capture) {
        const location = if (mover_color == .white) move.to - 8 else move.to + 8;
        new_board.removePiece(mover_color.opposite(), .pawn, location);
    } else if (move.flags.isCapture()) {
        const captured_piece = old_board.pieceAt(move.to);
        std.debug.assert(captured_piece != null);
        new_board.removePiece(captured_piece.?.color, captured_piece.?.piece, move.to);
    }

    // move piece from 'from' to 'to', accounting for promotion
    new_board.removePiece(mover_color, mover_piece, move.from);
    if (move.flags.isPromotion()) {
        std.debug.assert(move.flags.piecePromoted() != null);
        new_board.setPiece(mover_color, move.flags.piecePromoted().?, move.to);
    } else {
        new_board.setPiece(mover_color, mover_piece, move.to);
    }

    // move rook when castling
    if (move.flags == .kingside_castle) {
        // white kingside castle: rook goes from h1 (7) to f1 (5)
        if (mover_color == .white) {
            new_board.removePiece(.white, .rook, 7);
            new_board.setPiece(.white, .rook, 5);
        } else { // black kingside castle: rook goes from h8 (63) to f8 (61)
            new_board.removePiece(.black, .rook, 63);
            new_board.setPiece(.black, .rook, 61);
        }
    } else if (move.flags == .queenside_castle) {
        // white queenside castle: rook goes from a1 (0) to d1 (3)
        if (mover_color == .white) {
            new_board.removePiece(.white, .rook, 0);
            new_board.setPiece(.white, .rook, 3);
        } else { // black queenside castle: rook goes from a8 (56) to d8 (59)
            new_board.removePiece(.black, .rook, 56);
            new_board.setPiece(.black, .rook, 59);
        }
    }

    // clear castling rights if rook was captured or moved, or if king was moved
    new_board.castling_rights &= brd.castling_mask[move.from] & brd.castling_mask[move.to];

    // set en passant
    if (move.flags == .double_pawn_push) {
        new_board.en_passant = if (mover_color == .white) move.to - 8 else move.to + 8;
    } else {
        new_board.en_passant = null;
    }

    // if pawn move or capture, reset halfmove clock, otherwise increment it
    if (mover_piece == .pawn or move.flags.isCapture()) {
        new_board.halfmove_clock = 0;
    } else {
        new_board.halfmove_clock +|= 1; // saturating add, won't go beyond 255
    }

    // increment side to move after black's turn
    if (mover_color == .black) {
        new_board.fullmove_number += 1;
    }

    // flip side to move
    new_board.side_to_move = mover_color.opposite();

    return new_board;
}

pub fn makeMoveIfLegal(board: *const brd.Board, move: Move) ?brd.Board {
    const next = makeMove(board, move);
    const mover = board.pieceAt(move.from);
    std.debug.assert(board.getBoard(mover.?.color, .king) != 0);

    const king_position: brd.Square = @intCast(@ctz(next.getBoard(mover.?.color, .king)));
    if (query.isSquareAttacked(&next, king_position, mover.?.color.opposite())) {
        return null;
    }
    return next;
}

pub fn generateMoves(board: *const brd.Board, list: *MoveList) void {
    const color = board.side_to_move;
    const pushes = pawn_gen.generatePawnPushes(board, color);
    pawn_gen.singlePawnPushesToMoves(pushes.single, color, list);
    pawn_gen.doublePawnPushesToMoves(pushes.double, color, list);
    pawn_gen.pawnCapturesToMoves(board, color, list);

    leaper_gen.leaperMoves(board, color, .king, list);
    leaper_gen.leaperMoves(board, color, .knight, list);

    slider_gen.sliderMoves(board, color, .bishop, list);
    slider_gen.sliderMoves(board, color, .rook, list);
    slider_gen.sliderMoves(board, color, .queen, list);

    castlingMoves(board, color, list);
}

pub fn perft(board: *const brd.Board, depth: u32) u64 {
    if (depth == 0) return 1;
    var nodes: u64 = 0;
    var list = MoveList{};
    generateMoves(board, &list);
    for (list.moves[0..list.count]) |move| {
        if (makeMoveIfLegal(board, move)) |next| {
            nodes += perft(&next, depth - 1);
        }
    }
    return nodes;
}

test "Move size is 2 bytes" {
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(Move));
    try std.testing.expectEqual(@as(usize, 16), @bitSizeOf(Move));
}

test "Move round trip and packed bit layout" {
    const m = Move{
        .from = 12,
        .to = 28,
        .flags = .double_pawn_push,
    };

    try std.testing.expectEqual(@as(brd.Square, 12), m.from);
    try std.testing.expectEqual(@as(brd.Square, 28), m.to);
    try std.testing.expectEqual(MoveFlags.double_pawn_push, m.flags);

    // Packed structs place the first field (from) in the lowest bits:
    // bits 0..5 = from (12), bits 6..11 = to (28), bits 12..15 = flags (0b0001)
    const raw: u16 = @bitCast(m);
    const expected_raw: u16 = @as(u16, 12) | (@as(u16, 28) << 6) | (@as(u16, 0b0001) << 12);
    try std.testing.expectEqual(expected_raw, raw);

    const unpacked: Move = @bitCast(raw);
    try std.testing.expectEqual(m, unpacked);
}

test "Move extremes for squares and flags" {
    const min_move = Move{ .from = 0, .to = 0, .flags = .quiet_move };
    try std.testing.expectEqual(@as(u16, 0), @as(u16, @bitCast(min_move)));
    try std.testing.expectEqual(@as(brd.Square, 0), min_move.from);
    try std.testing.expectEqual(@as(brd.Square, 0), min_move.to);
    try std.testing.expectEqual(MoveFlags.quiet_move, min_move.flags);

    const max_move = Move{ .from = 63, .to = 63, .flags = .queen_promotion_capture };
    try std.testing.expectEqual(@as(u16, 0xFFFF), @as(u16, @bitCast(max_move)));
    try std.testing.expectEqual(@as(brd.Square, 63), max_move.from);
    try std.testing.expectEqual(@as(brd.Square, 63), max_move.to);
    try std.testing.expectEqual(MoveFlags.queen_promotion_capture, max_move.flags);
}

test "MoveFlags capture and promotion helpers" {
    try std.testing.expect(!MoveFlags.quiet_move.isCapture());
    try std.testing.expect(!MoveFlags.quiet_move.isPromotion());
    try std.testing.expectEqual(@as(?Piece, null), MoveFlags.quiet_move.piecePromoted());

    try std.testing.expect(!MoveFlags.double_pawn_push.isCapture());
    try std.testing.expect(!MoveFlags.kingside_castle.isCapture());
    try std.testing.expect(!MoveFlags.queenside_castle.isCapture());

    // Non-promotion captures
    try std.testing.expect(MoveFlags.capture.isCapture());
    try std.testing.expect(!MoveFlags.capture.isPromotion());
    try std.testing.expectEqual(@as(?Piece, null), MoveFlags.capture.piecePromoted());

    try std.testing.expect(MoveFlags.en_passant_capture.isCapture());
    try std.testing.expect(!MoveFlags.en_passant_capture.isPromotion());
    try std.testing.expectEqual(@as(?Piece, null), MoveFlags.en_passant_capture.piecePromoted());

    // Quiet promotions
    const quiet_promos = [_]struct { flag: MoveFlags, piece: Piece }{
        .{ .flag = .knight_promotion, .piece = .knight },
        .{ .flag = .bishop_promotion, .piece = .bishop },
        .{ .flag = .rook_promotion, .piece = .rook },
        .{ .flag = .queen_promotion, .piece = .queen },
    };
    for (quiet_promos) |case| {
        try std.testing.expect(case.flag.isPromotion());
        try std.testing.expect(!case.flag.isCapture());
        try std.testing.expectEqual(@as(?Piece, case.piece), case.flag.piecePromoted());
    }

    // Capture promotions
    const capture_promos = [_]struct { flag: MoveFlags, piece: Piece }{
        .{ .flag = .knight_promotion_capture, .piece = .knight },
        .{ .flag = .bishop_promotion_capture, .piece = .bishop },
        .{ .flag = .rook_promotion_capture, .piece = .rook },
        .{ .flag = .queen_promotion_capture, .piece = .queen },
    };
    for (capture_promos) |case| {
        try std.testing.expect(case.flag.isPromotion());
        try std.testing.expect(case.flag.isCapture());
        try std.testing.expectEqual(@as(?Piece, case.piece), case.flag.piecePromoted());
    }
}

test "MoveList starts empty and adds three moves" {
    var list = MoveList{};
    try std.testing.expectEqual(@as(u16, 0), list.count);

    const m1 = Move{ .from = 12, .to = 28, .flags = .double_pawn_push }; // e2e4
    const m2 = Move{ .from = 6, .to = 21, .flags = .quiet_move }; // g1f3
    const m3 = Move{ .from = 28, .to = 35, .flags = .capture }; // e4xd5

    list.add(m1);
    list.add(m2);
    list.add(m3);

    try std.testing.expectEqual(@as(u16, 3), list.count);
    try std.testing.expectEqual(m1, list.moves[0]);
    try std.testing.expectEqual(m2, list.moves[1]);
    try std.testing.expectEqual(m3, list.moves[2]);
}

fn expectMoveResult(start_fen: []const u8, move: Move, expected_fen: []const u8) !void {
    const start = try fen.parseFen(start_fen);
    const actual = makeMove(&start, move);
    const expected = try fen.parseFen(expected_fen);
    try std.testing.expectEqualDeep(expected, actual);
}

fn expectLegalMoveResult(start_fen: []const u8, move: Move, expected_fen: []const u8) !void {
    const start = try fen.parseFen(start_fen);
    const actual = makeMoveIfLegal(&start, move) orelse return error.TestUnexpectedResult;
    const expected = try fen.parseFen(expected_fen);
    try std.testing.expectEqualDeep(expected, actual);
}

fn expectIllegalMove(start_fen: []const u8, move: Move) !void {
    const start = try fen.parseFen(start_fen);
    try std.testing.expect(makeMoveIfLegal(&start, move) == null);
}

test "makeMove applies quiet moves and updates clocks and side to move" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "4k3/8/8/8/8/8/8/4K1N1 w - - 0 1",
            .move = .{ .from = 6, .to = 21, .flags = .quiet_move }, // Ng1-f3
            .expected = "4k3/8/8/8/8/5N2/8/4K3 b - - 1 1",
        },
        .{
            .start = "4k1n1/8/8/8/8/8/8/4K3 b - - 0 1",
            .move = .{ .from = 62, .to = 45, .flags = .quiet_move }, // Ng8-f6
            .expected = "4k3/8/5n2/8/8/8/8/4K3 w - - 1 2",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMove applies double pawn pushes and sets en passant" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
            .move = .{ .from = 12, .to = 28, .flags = .double_pawn_push }, // e2-e4
            .expected = "4k3/8/8/8/4P3/8/8/4K3 b - e3 0 1",
        },
        .{
            .start = "4k3/4p3/8/8/8/8/8/4K3 b - - 0 1",
            .move = .{ .from = 52, .to = 36, .flags = .double_pawn_push }, // e7-e5
            .expected = "4k3/8/8/4p3/8/8/8/4K3 w - e6 0 2",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMove applies captures and resets the halfmove clock" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "4k3/8/4p3/8/4R3/8/8/4K3 w - - 0 1",
            .move = .{ .from = 28, .to = 44, .flags = .capture }, // Re4xe6
            .expected = "4k3/8/4R3/8/8/8/8/4K3 b - - 0 1",
        },
        .{
            .start = "4k3/8/8/3p4/2P5/8/8/4K3 b - - 0 1",
            .move = .{ .from = 35, .to = 26, .flags = .capture }, // pd5xc4
            .expected = "4k3/8/8/8/2p5/8/8/4K3 w - - 0 2",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMove applies en passant captures" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
            .move = .{ .from = 36, .to = 43, .flags = .en_passant_capture }, // e5xd6 e.p.
            .expected = "4k3/8/3P4/8/8/8/8/4K3 b - - 0 1",
        },
        .{
            .start = "4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1",
            .move = .{ .from = 27, .to = 20, .flags = .en_passant_capture }, // d4xe3 e.p.
            .expected = "4k3/8/8/8/8/4p3/8/4K3 w - - 0 2",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMove applies quiet promotions to every piece" {
    const start_fen = "k7/4P3/8/8/8/8/8/7K w - - 0 1";
    const cases = [_]struct { flag: MoveFlags, expected: []const u8 }{
        .{ .flag = .knight_promotion, .expected = "k3N3/8/8/8/8/8/8/7K b - - 0 1" },
        .{ .flag = .bishop_promotion, .expected = "k3B3/8/8/8/8/8/8/7K b - - 0 1" },
        .{ .flag = .rook_promotion, .expected = "k3R3/8/8/8/8/8/8/7K b - - 0 1" },
        .{ .flag = .queen_promotion, .expected = "k3Q3/8/8/8/8/8/8/7K b - - 0 1" },
    };

    for (cases) |case| {
        try expectMoveResult(start_fen, .{ .from = 52, .to = 60, .flags = case.flag }, case.expected);
    }
}

test "makeMove applies capture promotions to every piece" {
    const start_fen = "k2r4/4P3/8/8/8/8/8/7K w - - 0 1";
    const cases = [_]struct { flag: MoveFlags, expected: []const u8 }{
        .{ .flag = .knight_promotion_capture, .expected = "k2N4/8/8/8/8/8/8/7K b - - 0 1" },
        .{ .flag = .bishop_promotion_capture, .expected = "k2B4/8/8/8/8/8/8/7K b - - 0 1" },
        .{ .flag = .rook_promotion_capture, .expected = "k2R4/8/8/8/8/8/8/7K b - - 0 1" },
        .{ .flag = .queen_promotion_capture, .expected = "k2Q4/8/8/8/8/8/8/7K b - - 0 1" },
    };

    for (cases) |case| {
        try expectMoveResult(start_fen, .{ .from = 52, .to = 59, .flags = case.flag }, case.expected);
    }
}

test "makeMove applies white kingside castling" {
    try expectMoveResult(
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        .{ .from = 4, .to = 6, .flags = .kingside_castle }, // e1-g1
        "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1",
    );
}

test "makeMove applies white queenside castling" {
    try expectMoveResult(
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        .{ .from = 4, .to = 2, .flags = .queenside_castle }, // e1-c1
        "r3k2r/8/8/8/8/8/8/2KR3R b kq - 1 1",
    );
}

test "makeMove applies black kingside castling" {
    try expectMoveResult(
        "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
        .{ .from = 60, .to = 62, .flags = .kingside_castle }, // e8-g8
        "r4rk1/8/8/8/8/8/8/R3K2R w KQ - 1 2",
    );
}

test "makeMove applies black queenside castling" {
    try expectMoveResult(
        "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
        .{ .from = 60, .to = 58, .flags = .queenside_castle }, // e8-c8
        "2kr3r/8/8/8/8/8/8/R3K2R w KQ - 1 2",
    );
}

test "makeMove clears castling rights when kings and rooks move or are captured" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
            .move = .{ .from = 4, .to = 12, .flags = .quiet_move }, // Ke1-e2
            .expected = "r3k2r/8/8/8/8/8/4K3/R6R b kq - 1 1",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
            .move = .{ .from = 0, .to = 8, .flags = .quiet_move }, // Ra1-a2
            .expected = "r3k2r/8/8/8/8/8/R7/4K2R b Kkq - 1 1",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
            .move = .{ .from = 7, .to = 15, .flags = .quiet_move }, // Rh1-h2
            .expected = "r3k2r/8/8/8/8/8/7R/R3K3 b Qkq - 1 1",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
            .move = .{ .from = 60, .to = 52, .flags = .quiet_move }, // Ke8-e7
            .expected = "r6r/4k3/8/8/8/8/8/R3K2R w KQ - 1 2",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
            .move = .{ .from = 56, .to = 48, .flags = .quiet_move }, // Ra8-a7
            .expected = "4k2r/r7/8/8/8/8/8/R3K2R w KQk - 1 2",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
            .move = .{ .from = 63, .to = 7, .flags = .capture }, // Rh8xh1
            .expected = "r3k3/8/8/8/8/8/8/R3K2r w Qq - 0 2",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1",
            .move = .{ .from = 56, .to = 0, .flags = .capture }, // Ra8xa1
            .expected = "4k2r/8/8/8/8/8/8/r3K2R w Kk - 0 2",
        },
        .{
            .start = "4k2r/8/6N1/8/8/8/8/4K3 w kq - 0 1",
            .move = .{ .from = 46, .to = 63, .flags = .capture }, // Ng6xh8
            .expected = "4k2N/8/8/8/8/8/8/4K3 b q - 0 1",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMove clears en passant after quiet, capture, promotion, and castling moves" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1",
            .move = .{ .from = 4, .to = 12, .flags = .quiet_move }, // Ke1-e2
            .expected = "4k3/8/8/3pP3/8/8/4K3/8 b - - 1 1",
        },
        .{
            .start = "r3k3/8/8/8/8/8/8/R3K3 w - d6 0 1",
            .move = .{ .from = 0, .to = 56, .flags = .capture }, // Ra1xa8
            .expected = "R3k3/8/8/8/8/8/8/4K3 b - - 0 1",
        },
        .{
            .start = "k7/4P3/8/8/8/8/8/7K w - d6 0 1",
            .move = .{ .from = 52, .to = 60, .flags = .queen_promotion }, // e7-e8=Q
            .expected = "k3Q3/8/8/8/8/8/8/7K b - - 0 1",
        },
        .{
            .start = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq d6 0 1",
            .move = .{ .from = 4, .to = 6, .flags = .kingside_castle }, // O-O
            .expected = "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMove applies black quiet promotions to every piece" {
    const start_fen = "k7/8/8/8/8/8/4p3/7K b - - 0 1";
    const cases = [_]struct { flag: MoveFlags, expected: []const u8 }{
        .{ .flag = .knight_promotion, .expected = "k7/8/8/8/8/8/8/4n2K w - - 0 2" },
        .{ .flag = .bishop_promotion, .expected = "k7/8/8/8/8/8/8/4b2K w - - 0 2" },
        .{ .flag = .rook_promotion, .expected = "k7/8/8/8/8/8/8/4r2K w - - 0 2" },
        .{ .flag = .queen_promotion, .expected = "k7/8/8/8/8/8/8/4q2K w - - 0 2" },
    };

    for (cases) |case| {
        try expectMoveResult(start_fen, .{ .from = 12, .to = 4, .flags = case.flag }, case.expected);
    }
}

test "makeMove applies black capture promotions to every piece" {
    const start_fen = "k7/8/8/8/8/8/4p3/3R3K b - - 0 1";
    const cases = [_]struct { flag: MoveFlags, expected: []const u8 }{
        .{ .flag = .knight_promotion_capture, .expected = "k7/8/8/8/8/8/8/3n3K w - - 0 2" },
        .{ .flag = .bishop_promotion_capture, .expected = "k7/8/8/8/8/8/8/3b3K w - - 0 2" },
        .{ .flag = .rook_promotion_capture, .expected = "k7/8/8/8/8/8/8/3r3K w - - 0 2" },
        .{ .flag = .queen_promotion_capture, .expected = "k7/8/8/8/8/8/8/3q3K w - - 0 2" },
    };

    for (cases) |case| {
        try expectMoveResult(start_fen, .{ .from = 12, .to = 3, .flags = case.flag }, case.expected);
    }
}

test "makeMove increments the halfmove clock and saturates at 255" {
    const cases = [_]struct { start: []const u8, expected: []const u8 }{
        .{
            .start = "4k3/8/8/8/8/8/8/4K1N1 w - - 41 1",
            .expected = "4k3/8/8/8/8/5N2/8/4K3 b - - 42 1",
        },
        .{
            .start = "4k3/8/8/8/8/8/8/4K1N1 w - - 255 1",
            .expected = "4k3/8/8/8/8/5N2/8/4K3 b - - 255 1",
        },
    };

    const move = Move{ .from = 6, .to = 21, .flags = .quiet_move }; // Ng1-f3
    for (cases) |case| {
        try expectMoveResult(case.start, move, case.expected);
    }
}

test "makeMove resets the halfmove clock for pawn moves, captures, en passant, and promotions" {
    const cases = [_]struct { start: []const u8, move: Move, expected: []const u8 }{
        .{
            .start = "4k3/8/8/8/8/8/4P3/4K3 w - - 41 1",
            .move = .{ .from = 12, .to = 20, .flags = .quiet_move }, // e2-e3
            .expected = "4k3/8/8/8/8/4P3/8/4K3 b - - 0 1",
        },
        .{
            .start = "4k3/8/4p3/8/4R3/8/8/4K3 w - - 41 1",
            .move = .{ .from = 28, .to = 44, .flags = .capture }, // Re4xe6
            .expected = "4k3/8/4R3/8/8/8/8/4K3 b - - 0 1",
        },
        .{
            .start = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 41 1",
            .move = .{ .from = 36, .to = 43, .flags = .en_passant_capture }, // e5xd6 e.p.
            .expected = "4k3/8/3P4/8/8/8/8/4K3 b - - 0 1",
        },
        .{
            .start = "k7/4P3/8/8/8/8/8/7K w - - 41 1",
            .move = .{ .from = 52, .to = 60, .flags = .queen_promotion }, // e7-e8=Q
            .expected = "k3Q3/8/8/8/8/8/8/7K b - - 0 1",
        },
    };

    for (cases) |case| {
        try expectMoveResult(case.start, case.move, case.expected);
    }
}

test "makeMoveIfLegal accepts a legal move" {
    try expectLegalMoveResult(
        "4k3/8/8/8/8/8/8/4K1N1 w - - 0 1",
        .{ .from = 6, .to = 21, .flags = .quiet_move }, // Ng1-f3
        "4k3/8/8/8/8/5N2/8/4K3 b - - 1 1",
    );
}

test "makeMoveIfLegal rejects moves that expose or move the king into check" {
    try expectIllegalMove(
        "k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1",
        .{ .from = 12, .to = 13, .flags = .quiet_move }, // Re2-f2 exposes Ke1 to Re8
    );

    try expectIllegalMove(
        "k3r3/8/8/8/8/8/8/4K3 w - - 0 1",
        .{ .from = 4, .to = 12, .flags = .quiet_move }, // Ke1-e2 moves onto the e-file
    );
}

test "makeMoveIfLegal accepts king escapes and captures of the checking piece" {
    try expectLegalMoveResult(
        "k3r3/8/8/8/8/8/8/4K3 w - - 0 1",
        .{ .from = 4, .to = 3, .flags = .quiet_move }, // Ke1-d1
        "k3r3/8/8/8/8/8/8/3K4 b - - 1 1",
    );

    try expectLegalMoveResult(
        "k7/8/8/8/8/8/R3r3/4K3 w - - 0 1",
        .{ .from = 8, .to = 12, .flags = .capture }, // Ra2xe2
        "k7/8/8/8/8/8/4R3/4K3 b - - 0 1",
    );
}

fn hasMove(list: *const MoveList, move: Move) bool {
    for (list.moves[0..list.count]) |candidate| {
        if (candidate == move) return true;
    }
    return false;
}

fn expectCastlingAvailability(board: *const brd.Board, color: brd.Color, kingside: bool, queenside: bool) !void {
    var list = MoveList{};
    generateMoves(board, &list);

    const king_from: brd.Square = if (color == .white) 4 else 60;
    const kingside_to: brd.Square = if (color == .white) 6 else 62;
    const queenside_to: brd.Square = if (color == .white) 2 else 58;

    try std.testing.expectEqual(kingside, hasMove(&list, .{ .from = king_from, .to = kingside_to, .flags = .kingside_castle }));
    try std.testing.expectEqual(queenside, hasMove(&list, .{ .from = king_from, .to = queenside_to, .flags = .queenside_castle }));
}

test "generateMoves adds all four castling moves in an open position" {
    const white_board = try fen.parseFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
    try expectCastlingAvailability(&white_board, .white, true, true);

    const black_board = try fen.parseFen("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1");
    try expectCastlingAvailability(&black_board, .black, true, true);
}

test "castlingMoves is blocked by a piece of either color in every castle path" {
    const cases = [_]struct {
        fen: []const u8,
        color: brd.Color,
        kingside: bool,
        queenside: bool,
    }{
        // White kingside blocked on f1 by a friendly or enemy knight.
        .{ .fen = "r3k2r/8/8/8/8/8/8/R3KN1R w KQkq - 0 1", .color = .white, .kingside = false, .queenside = true },
        .{ .fen = "r3k2r/8/8/8/8/8/8/R3Kn1R w KQkq - 0 1", .color = .white, .kingside = false, .queenside = true },
        // White queenside blocked on b1 by a friendly or enemy knight.
        .{ .fen = "r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1", .color = .white, .kingside = true, .queenside = false },
        .{ .fen = "r3k2r/8/8/8/8/8/8/Rn2K2R w KQkq - 0 1", .color = .white, .kingside = true, .queenside = false },
        // Black kingside blocked on f8 by a friendly or enemy knight.
        .{ .fen = "r3kN1r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", .color = .black, .kingside = false, .queenside = true },
        .{ .fen = "r3kn1r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", .color = .black, .kingside = false, .queenside = true },
        // Black queenside blocked on b8 by a friendly or enemy knight.
        .{ .fen = "rN2k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", .color = .black, .kingside = true, .queenside = false },
        .{ .fen = "rn2k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", .color = .black, .kingside = true, .queenside = false },
    };

    for (cases) |case| {
        const board = try fen.parseFen(case.fen);
        try expectCastlingAvailability(&board, case.color, case.kingside, case.queenside);
    }
}

test "castlingMoves requires rights and the rook on its home square" {
    const cases = [_]struct {
        fen: []const u8,
        color: brd.Color,
        kingside: bool,
        queenside: bool,
    }{
        // Rights are present, but the corresponding rook is missing.
        .{ .fen = "r3k2r/8/8/8/8/8/8/R3K3 w KQkq - 0 1", .color = .white, .kingside = false, .queenside = true },
        .{ .fen = "r3k2r/8/8/8/8/8/8/4K2R w KQkq - 0 1", .color = .white, .kingside = true, .queenside = false },
        .{ .fen = "r3k3/8/8/8/8/8/8/R3K2R b KQkq - 0 1", .color = .black, .kingside = false, .queenside = true },
        .{ .fen = "4k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", .color = .black, .kingside = true, .queenside = false },
        // No castling rights at all.
        .{ .fen = "r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1", .color = .white, .kingside = false, .queenside = false },
        // Starting position has rights, but both paths are blocked.
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .color = .white, .kingside = false, .queenside = false },
    };

    for (cases) |case| {
        const board = try fen.parseFen(case.fen);
        try expectCastlingAvailability(&board, case.color, case.kingside, case.queenside);
    }
}

test "castlingMoves rejects check and attacked king paths" {
    const cases = [_]struct {
        fen: []const u8,
        color: brd.Color,
        kingside: bool,
        queenside: bool,
    }{
        // White king is in check on e1.
        .{ .fen = "r3k2r/8/8/8/8/8/4r3/R3K2R w KQkq - 0 1", .color = .white, .kingside = false, .queenside = false },
        // White king cannot pass through f1.
        .{ .fen = "r3kr2/8/8/8/8/8/8/R3K2R w KQkq - 0 1", .color = .white, .kingside = false, .queenside = true },
        // White king cannot pass through d1.
        .{ .fen = "r2rk3/8/8/8/8/8/8/R3K2R w KQkq - 0 1", .color = .white, .kingside = true, .queenside = false },
        // White king cannot land on g1.
        .{ .fen = "r3k1r1/8/8/8/8/8/8/R3K2R w KQkq - 0 1", .color = .white, .kingside = false, .queenside = true },
        // White king cannot land on c1.
        .{ .fen = "r1r1k3/8/8/8/8/8/8/R3K2R w KQkq - 0 1", .color = .white, .kingside = true, .queenside = false },
        // Only b1 is attacked, so queenside castling is still legal.
        .{ .fen = "1r2k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", .color = .white, .kingside = true, .queenside = true },
        // Only the rook squares are attacked, which does not prevent castling.
        .{ .fen = "rr2k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", .color = .white, .kingside = true, .queenside = true },
        // Black king is in check on e8.
        .{ .fen = "r3k2r/8/8/8/8/8/4R3/R3K3 b KQkq - 0 1", .color = .black, .kingside = false, .queenside = false },
        // Black king cannot pass through f8.
        .{ .fen = "r3k2r/8/8/8/8/8/5R2/R3K3 b KQkq - 0 1", .color = .black, .kingside = false, .queenside = true },
        // Black king cannot land on g8.
        .{ .fen = "r3k2r/8/8/8/8/8/6R1/R3K3 b KQkq - 0 1", .color = .black, .kingside = false, .queenside = true },
        // Black king cannot land on c8.
        .{ .fen = "r3k2r/8/8/8/8/8/2R5/R3K3 b KQkq - 0 1", .color = .black, .kingside = true, .queenside = false },
    };

    for (cases) |case| {
        const board = try fen.parseFen(case.fen);
        try expectCastlingAvailability(&board, case.color, case.kingside, case.queenside);
    }
}

test "perft from starting position through depth 4" {
    const starting_position = try fen.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    try std.testing.expectEqual(@as(u64, 1), perft(&starting_position, 0));
    try std.testing.expectEqual(@as(u64, 20), perft(&starting_position, 1));
    try std.testing.expectEqual(@as(u64, 400), perft(&starting_position, 2));
    try std.testing.expectEqual(@as(u64, 8902), perft(&starting_position, 3));
    try std.testing.expectEqual(@as(u64, 197281), perft(&starting_position, 4));
}

test "perft on a castling-free endgame position through depth 4" {
    // ChessProgramming perft position 3. It has no castling rights.
    const position = try fen.parseFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");

    try std.testing.expectEqual(@as(u64, 14), perft(&position, 1));
    try std.testing.expectEqual(@as(u64, 191), perft(&position, 2));
    try std.testing.expectEqual(@as(u64, 2812), perft(&position, 3));
    try std.testing.expectEqual(@as(u64, 43238), perft(&position, 4));
}

test "perft on a castling-free middlegame position through depth 3" {
    // ChessProgramming perft position 6. Both kings have already castled and
    // there are no castling rights, so the standard counts apply here.
    const position = try fen.parseFen("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10");

    try std.testing.expectEqual(@as(u64, 46), perft(&position, 1));
    try std.testing.expectEqual(@as(u64, 2079), perft(&position, 2));
    try std.testing.expectEqual(@as(u64, 89890), perft(&position, 3));
}

test "perft on promotion-heavy position 4 with no castling rights through depth 4" {
    // ChessProgramming perft position 4, with black's castling rights removed.
    const position = try fen.parseFen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w - - 0 1");

    try std.testing.expectEqual(@as(u64, 6), perft(&position, 1));
    try std.testing.expectEqual(@as(u64, 258), perft(&position, 2));
    try std.testing.expectEqual(@as(u64, 9221), perft(&position, 3));
    try std.testing.expectEqual(@as(u64, 404587), perft(&position, 4));
}

test "perft on promotion-heavy position 5 with no castling rights through depth 4" {
    // ChessProgramming perft position 5, with white's castling rights removed.
    const position = try fen.parseFen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w - - 1 8");

    try std.testing.expectEqual(@as(u64, 43), perft(&position, 1));
    try std.testing.expectEqual(@as(u64, 1452), perft(&position, 2));
    try std.testing.expectEqual(@as(u64, 59922), perft(&position, 3));
    try std.testing.expectEqual(@as(u64, 2018609), perft(&position, 4));
}

test "perft with castling rights matches standard counts" {
    // Position 4 with black's kq rights.
    const position4 = try fen.parseFen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");
    try std.testing.expectEqual(@as(u64, 6), perft(&position4, 1));
    try std.testing.expectEqual(@as(u64, 264), perft(&position4, 2));
    try std.testing.expectEqual(@as(u64, 9467), perft(&position4, 3));
    try std.testing.expectEqual(@as(u64, 422333), perft(&position4, 4));

    // Position 5 with white's KQ rights.
    const position5 = try fen.parseFen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
    try std.testing.expectEqual(@as(u64, 44), perft(&position5, 1));
    try std.testing.expectEqual(@as(u64, 1486), perft(&position5, 2));
    try std.testing.expectEqual(@as(u64, 62379), perft(&position5, 3));
}

test "Kiwipete perft through depth 4" {
    const position = try fen.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");

    try std.testing.expectEqual(@as(u64, 48), perft(&position, 1));
    try std.testing.expectEqual(@as(u64, 2039), perft(&position, 2));
    try std.testing.expectEqual(@as(u64, 97862), perft(&position, 3));
    try std.testing.expectEqual(@as(u64, 4085603), perft(&position, 4));
}
