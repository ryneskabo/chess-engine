const std = @import("std");
const brd = @import("board.zig");

pub const InvalidFen = error {
    InvalidNumberOfFields,
    InvalidPiecePlacement,
    InvalidSideToMove,
    InvalidCastlingAbility,
    InvalidEnPassantSquare,
    InvalidHalfmoveClock,
    InvalidFullmoveCounter
};

fn parsePiecePlacement(board: *brd.Board, pieces: []const u8) InvalidFen!void {
    var ranks = std.mem.splitScalar(u8, pieces, '/');
    var rank_count: u8 = 0;
    var current_file: u8 = 0;

    while (ranks.next()) |rank| : (current_file = 0) {
        if (rank_count >= 8) return InvalidFen.InvalidPiecePlacement;
        const current_rank = 7 - rank_count;
        for (rank) |c| {
            if (c >= '1' and c <= '8') {
                current_file += c - '0';
                if (current_file > 8) {
                    return InvalidFen.InvalidPiecePlacement;
                }
                continue;
            }

            if (current_file >= 8) {
                return InvalidFen.InvalidPiecePlacement;
            }

            const square: brd.Square = @intCast(current_rank * 8 + current_file);
            switch (c) {
                'P' =>  board.setPiece(.white, .pawn, square),
                'p' =>  board.setPiece(.black, .pawn, square),
                'N' =>  board.setPiece(.white, .knight, square),
                'n' =>  board.setPiece(.black, .knight, square),
                'B' =>  board.setPiece(.white, .bishop, square),
                'b' =>  board.setPiece(.black, .bishop, square),
                'R' =>  board.setPiece(.white, .rook, square),
                'r' =>  board.setPiece(.black, .rook, square),
                'Q' =>  board.setPiece(.white, .queen, square),
                'q' =>  board.setPiece(.black, .queen, square),
                'K' =>  board.setPiece(.white, .king, square),
                'k' =>  board.setPiece(.black, .king, square),
                else => return InvalidFen.InvalidPiecePlacement,
            }
            current_file += 1;
        }
        rank_count += 1;
        if (current_file != 8) {
            return InvalidFen.InvalidPiecePlacement;
        }
    }
    if (rank_count != 8) {
        return InvalidFen.InvalidPiecePlacement;
    }
}

fn parseSideToMove(board: *brd.Board, side: []const u8) InvalidFen!void {
    if (side.len != 1) {
        return InvalidFen.InvalidSideToMove;
    }

    switch (side[0]) {
        'w' => board.side_to_move = .white,
        'b' => board.side_to_move = .black,
        else => {
            return InvalidFen.InvalidSideToMove;
        }
    }
}

fn parseCastlingAbility(board: *brd.Board, castling_ability: []const u8) InvalidFen!void {
    if (castling_ability.len == 0) {
        return InvalidFen.InvalidCastlingAbility;
    }

    // Neither side has castling rights
    if (std.mem.eql(u8, castling_ability, "-")) {
        return; // Already 0b0000
    }

    for (castling_ability) |right| {
        switch (right) {
            'K' => board.castling_rights |= brd.white_kingside,
            'k' => board.castling_rights |= brd.black_kingside,
            'Q' => board.castling_rights |= brd.white_queenside,
            'q' => board.castling_rights |= brd.black_queenside,
            else => {
                return InvalidFen.InvalidCastlingAbility;
            }
        }
    }
}

/// Square can be "-" if en passant is not available or in algebraic notation e.g. f6. Rank must be 3 or 6.
fn parseEnPassantSquare(board: *brd.Board, en_passant_square: []const u8) InvalidFen!void {
    if (std.mem.eql(u8, en_passant_square, "-")) {
        return; // Already null
    }

    if (en_passant_square.len != 2) {
        return InvalidFen.InvalidEnPassantSquare;
    }

    const file = en_passant_square[0];
    const rank = en_passant_square[1];

    if (file < 'a' or file > 'h') {
        return InvalidFen.InvalidEnPassantSquare;
    }

    if (rank != '3' and rank != '6') {
        return InvalidFen.InvalidEnPassantSquare;
    }

    board.en_passant = @intCast((rank - '1') * 8 + file - 'a');
}

/// Clock must be a number. Does not check if >= 100, engine can just declare it a draw when it runs. Maybe should make sure it fits into a u8
fn parseHalfmoveClock(board: *brd.Board, halfmove_clock: []const u8) InvalidFen!void {
    const count: u8 = std.fmt.parseUnsigned(u8, halfmove_clock, 10) catch {
        return InvalidFen.InvalidHalfmoveClock;
    };
    board.halfmove_clock = count;
}

/// Counter must be a number. Maybe should make sure the number fits into a u16.
fn parseFullmoveCounter(board: *brd.Board, fullmove_counter: []const u8) InvalidFen!void {
    const count: u16 = std.fmt.parseUnsigned(u16, fullmove_counter, 10) catch {
        return InvalidFen.InvalidFullmoveCounter;
    };
    board.fullmove_number = count;
}

fn nextField(fields: *std.mem.SplitIterator(u8, .scalar)) InvalidFen![]const u8 {
    const field = fields.next() orelse return InvalidFen.InvalidNumberOfFields;
    return field;
}

pub fn parseFen(fen: []const u8) InvalidFen!brd.Board {
    var board: brd.Board = brd.empty;

    // Separate FEN into fields iterator
    var fields: std.mem.SplitIterator(u8, .scalar) = std.mem.splitScalar(u8, fen, ' ');

    try parsePiecePlacement(&board, try nextField(&fields));

    try parseSideToMove(&board, try nextField(&fields));

    try parseCastlingAbility(&board, try nextField(&fields));

    try parseEnPassantSquare(&board, try nextField(&fields));

    try parseHalfmoveClock(&board, try nextField(&fields));

    try parseFullmoveCounter(&board, try nextField(&fields));

    if (fields.next() != null) {
        return InvalidFen.InvalidNumberOfFields;
    }

    return board;
}

test "parses starting position" {
    const b = try parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    // White pawns
    try std.testing.expectEqual(@as(u64, 0x000000000000FF00), b.getBoard(.white, .pawn));
    // Black pawns
    try std.testing.expectEqual(@as(u64, 0x00FF000000000000), b.getBoard(.black, .pawn));

    // White knights
    try std.testing.expectEqual(@as(u64, 0x42), b.getBoard(.white, .knight));

    // White king
    try std.testing.expectEqual(@as(u64, 1 << 4), b.getBoard(.white, .king));
    // Black king
    try std.testing.expectEqual(@as(u64, 1 << 60), b.getBoard(.black, .king));

    // White occupancy
    try std.testing.expectEqual(@as(u64, 0x000000000000FFFF), b.occupancy[@intFromEnum(brd.Color.white)]);
    // Black occupancy
    try std.testing.expectEqual(@as(u64, 0xFFFF000000000000), b.occupancy[@intFromEnum(brd.Color.black)]);

    // Side to move
    try std.testing.expectEqual(brd.Color.white, b.side_to_move);

    // Castling Rights
    try std.testing.expectEqual(0b1111, b.castling_rights);

    // En passant
    try std.testing.expectEqual(null, b.en_passant);

    // halfmove
    try std.testing.expectEqual(0, b.halfmove_clock);

    // fullmove
    try std.testing.expectEqual(1, b.fullmove_number);

    // Occupancy check, same across all tests
    var white_occ: u64 = 0;
    for (b.pieces[@intFromEnum(brd.Color.white)]) |bb| {
        white_occ |= bb;
    }
    try std.testing.expectEqual(b.occupancy[@intFromEnum(brd.Color.white)], white_occ);

    var black_occ: u64 = 0;
    for (b.pieces[@intFromEnum(brd.Color.black)]) |bb| {
        black_occ |= bb;
    }
    try std.testing.expectEqual(b.occupancy[@intFromEnum(brd.Color.black)], black_occ);

    // No overlap
    try std.testing.expectEqual(0, b.occupancy[@intFromEnum(brd.Color.white)] & b.occupancy[@intFromEnum(brd.Color.black)]);
}

test "parses after 1.e4" {
    const b = try parseFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1");

    // White pawns
    try std.testing.expectEqual(@as(u64, 0x000000001000EF00), b.getBoard(.white, .pawn));

    // En passant
    try std.testing.expectEqual(@as(brd.Square, 20), b.en_passant);

    // Side to move
    try std.testing.expectEqual(brd.Color.black, b.side_to_move);
}

test "partial castling and large counters" {
    const b = try parseFen("r3k2r/8/8/8/8/8/8/R3K2R w Kq - 12 40");

    // Castling rights
    try std.testing.expectEqual(brd.white_kingside | brd.black_queenside, b.castling_rights);

    // halfmove
    try std.testing.expectEqual(12, b.halfmove_clock);
 
    // fullmove
    try std.testing.expectEqual(40, b.fullmove_number);
}

test "no castling rights" {
    const b = try parseFen("4k3/8/8/8/8/8/8/4K3 w - - 0 1");

    // Castling rights
    try std.testing.expectEqual(0, b.castling_rights);

    // Pieces, should have only two bits set in board.
    try std.testing.expectEqual(1, @popCount(b.occupancy[@intFromEnum(brd.Color.white)]));
    try std.testing.expectEqual(1, @popCount(b.occupancy[@intFromEnum(brd.Color.black)]));

    var total: u32 = 0;
    for (b.pieces) |per_color| {
        for (per_color) |bb| {
            total += @popCount(bb);
        }
    }
    try std.testing.expectEqual(@as(u32, 2), total);

    try std.testing.expectEqual(@as(u64, 1 << 4), b.getBoard(.white, .king));
    try std.testing.expectEqual(@as(u64, 1 << 60), b.getBoard(.black, .king));

    // Castling Rights
    try std.testing.expectEqual(0b0000, b.castling_rights);

    // En passant
    try std.testing.expectEqual(null, b.en_passant);
}

test "kiwipete" {
    const b = try parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");

    // Pieces
    try std.testing.expectEqual(16, @popCount(b.occupancy[@intFromEnum(brd.Color.white)]));
    try std.testing.expectEqual(16, @popCount(b.occupancy[@intFromEnum(brd.Color.black)]));

    try std.testing.expect(b.getBoard(.white, .knight) & @as(u64, 1 << 36) != 0);
    try std.testing.expect(b.getBoard(.black, .pawn) & @as(u64, 1 << 25) != 0);
    try std.testing.expect(b.getBoard(.black, .queen) & @as(u64, 1 << 52) != 0);
    try std.testing.expect(b.getBoard(.white, .queen) & @as(u64, 1 << 21) != 0);
}

// INVALID INPUT TESTS
test "rejects invalid FENs" {
    const start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";

    const cases = [_]struct { fen: []const u8, err: anyerror }{
        // Piece placement
        .{ .fen = "", .err = InvalidFen.InvalidPiecePlacement },
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // 7 ranks
        .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // 9 ranks
        .{ .fen = "rnbqkbnrr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // 9 files
        .{ .fen = "rnbqkbn/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // 7 files
        .{ .fen = "rnbqkbnx/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // unknown piece
        .{ .fen = "9/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // digit 9
        .{ .fen = "rnbqkbnr/pppppppp/08/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // digit 0
        .{ .fen = "45/8/8/8/8/8/8/8 w - - 0 1", .err = InvalidFen.InvalidPiecePlacement }, // digits sum to 9

        // Field count
        .{ .fen = start ++ " w KQkq - 0", .err = InvalidFen.InvalidNumberOfFields }, // missing field
        .{ .fen = start ++ " w KQkq - 0 1 x", .err = InvalidFen.InvalidNumberOfFields }, // extra field

        // Side to move
        .{ .fen = start ++ " x KQkq - 0 1", .err = InvalidFen.InvalidSideToMove },
        .{ .fen = start ++ " ww KQkq - 0 1", .err = InvalidFen.InvalidSideToMove },

        // Castling
        .{ .fen = start ++ " w KQkx - 0 1", .err = InvalidFen.InvalidCastlingAbility },
        .{ .fen = start ++ " w  - 0 1", .err = InvalidFen.InvalidCastlingAbility }, // empty field (double space)

        // En passant
        .{ .fen = start ++ " w KQkq e4 0 1", .err = InvalidFen.InvalidEnPassantSquare }, // wrong rank
        .{ .fen = start ++ " w KQkq z3 0 1", .err = InvalidFen.InvalidEnPassantSquare }, // off the board
        .{ .fen = start ++ " w KQkq e 0 1", .err = InvalidFen.InvalidEnPassantSquare }, // wrong length

        // Counters
        .{ .fen = start ++ " w KQkq - a 1", .err = InvalidFen.InvalidHalfmoveClock },
        .{ .fen = start ++ " w KQkq - 256 1", .err = InvalidFen.InvalidHalfmoveClock }, // overflows u8
        .{ .fen = start ++ " w KQkq - 0 -1", .err = InvalidFen.InvalidFullmoveCounter },
        .{ .fen = start ++ " w KQkq - 0 70000", .err = InvalidFen.InvalidFullmoveCounter }, // overflows u16
    };

    for (cases) |c| {
        std.testing.expectError(c.err, parseFen(c.fen)) catch |e| {
            std.debug.print("failed case: \"{s}\"\n", .{c.fen});
            return e;
        };
    }
}
