const std = @import("std");

// Use single bit of data to indicate color
pub const Color = enum(u1) {
    white = 0,
    black = 1,
};

// use 3 bits to indicate piece
pub const Piece = enum(u3) { pawn = 0, knight = 1, bishop = 2, rook = 3, queen = 4, king = 5 };

// 0-63 represent each square: 0 = a1, 1 = b1, ..., 63 = h8.
pub const Square = u6;

// Describing Castling Rights
pub const CastlingRights = u4;
pub const white_kingside: CastlingRights = 0b0001;
pub const white_queenside: CastlingRights = 0b0010;
pub const black_kingside: CastlingRights = 0b0100;
pub const black_queenside: CastlingRights = 0b1000;
// if move starts or ends on one of these squares, clear castling rights. Accounts for rook and king movement and rook being captured.
pub const castling_mask: [64]CastlingRights = blk: {
    var m: [64]CastlingRights = @splat(0b1111);
    m[0] = 0b1101; // a1: clears white queenside
    m[4] = 0b1100; // e1: clears both white rights
    m[7] = 0b1110; // h1: clears white kingside
    m[56] = 0b0111; // a8: clears black queenside
    m[60] = 0b0011; // e8: clears both black rights
    m[63] = 0b1011; // h8: clears black kingside
    break :blk m;
};

pub const Board = struct {
    pieces: [2][6]u64, // [color][piece]
    occupancy: [2]u64, // [color], helps when generating moves, so you don't have to compute from all 12 boards each time.
    side_to_move: Color,
    castling_rights: CastlingRights,
    en_passant: ?Square, // could be null
    halfmove_clock: u8, // tracks 50 move rule
    fullmove_number: u16, // tracks moves on both sides, not needed for calculation, but nice to have for printing

    pub fn getBoard(self: *const Board, color: Color, piece: Piece) u64 {
        return self.pieces[@backingInt(color)][@backingInt(piece)];
    }

    pub fn getMutableBoard(self: *Board, color: Color, piece: Piece) *u64 {
        return &self.pieces[@backingInt(color)][@backingInt(piece)];
    }

    pub fn setPiece(self: *Board, color: Color, piece: Piece, sq: Square) void {
        const board: *u64 = self.getMutableBoard(color, piece);
        const bit: u64 = (@as(u64, 1) << sq);
        board.* |= bit;
        self.occupancy[@backingInt(color)] |= bit;
    }

    pub fn removePiece(self: *Board, color: Color, piece: Piece, sq: Square) void {
        const board: *u64 = self.getMutableBoard(color, piece);
        const bit: u64 = (@as(u64, 1) << sq);
        board.* &= ~bit;
        self.occupancy[@backingInt(color)] &= ~bit;
    }

    pub const PieceOnSquare = struct { color: Color, piece: Piece };

    pub fn pieceAt(self: *const Board, sq: Square) ?PieceOnSquare {
        const bit: u64 = (@as(u64, 1) << sq);
        const occupied_by_white: bool = bit & self.occupancy[@backingInt(Color.white)] != 0;
        const occupied_by_black: bool = bit & self.occupancy[@backingInt(Color.black)] != 0;

        // Check if square is occupied at all
        if (!(occupied_by_white or occupied_by_black)) {
            return null;
        }

        std.debug.assert(!(occupied_by_white and occupied_by_black));

        const color: Color = if (occupied_by_white) .white else .black;

        inline for (std.enums.values(Piece)) |piece| {
            if (bit & self.getBoard(color, piece) != 0) {
                return .{ .color = color, .piece = piece };
            }
        }

        @panic("occupancy out of sync with pieces board");
    }
};

pub const empty: Board = .{
    .pieces = @splat(@splat(0)),
    .occupancy = @splat(0),
    .side_to_move = .white,
    .castling_rights = 0b0000,
    .en_passant = null,
    .fullmove_number = 1,
    .halfmove_clock = 0,
};

test "set-piece-test" {
    var board: Board = empty;
    board.setPiece(.white, .knight, 28);
    try std.testing.expectEqual(board.getBoard(.white, .knight), 1 << 28);
    try std.testing.expectEqual(board.occupancy[0], 1 << 28);

    // Check side effects
    inline for (std.enums.values(Color)) |color| {
        inline for (std.enums.values(Piece)) |piece| {
            if (color != .white or piece != .knight) {
                try std.testing.expectEqual(board.getBoard(color, piece), 0);
            }
        }
    }

    try std.testing.expectEqual(board.occupancy[@backingInt(Color.black)], 0);
}

test "remove-piece-test" {
    var board: Board = empty;
    board.setPiece(.white, .knight, 28);
    try std.testing.expectEqual(board.getBoard(.white, .knight), 1 << 28);
    try std.testing.expectEqual(board.occupancy[0], 1 << 28);

    inline for (std.enums.values(Color)) |color| {
        inline for (std.enums.values(Piece)) |piece| {
            if (color != .white or piece != .knight) {
                try std.testing.expectEqual(board.getBoard(color, piece), 0);
            }
        }
    }

    try std.testing.expectEqual(board.occupancy[@backingInt(Color.black)], 0);

    board.removePiece(.white, .knight, 28);
    // Make sure piece is gone
    try std.testing.expectEqual(board.getBoard(.white, .knight), 0);
    try std.testing.expectEqual(board.occupancy[@backingInt(Color.white)], 0);

    // Check side effects
    inline for (std.enums.values(Color)) |color| {
        inline for (std.enums.values(Piece)) |piece| {
            if (color != .white or piece != .knight) {
                try std.testing.expectEqual(board.getBoard(color, piece), 0);
            }
        }
    }

    try std.testing.expectEqual(board.occupancy[@backingInt(Color.black)], 0);
}

test "piece at" {
    var board: Board = empty;
    try std.testing.expectEqual(null, board.pieceAt(28));

    board.setPiece(.white, .knight, 28);

    try std.testing.expectEqual(Board.PieceOnSquare{
        .color = .white,
        .piece = .knight,
    }, board.pieceAt(28));
}

test "piece at on a populated board" {
    var board: Board = empty;
    board.setPiece(.black, .king, 60);
    board.setPiece(.white, .knight, 28);

    // Empty square, with a black piece elsewhere on the board
    try std.testing.expectEqual(null, board.pieceAt(0));
}

test "piece at returns a black piece" {
    var board: Board = empty;
    board.setPiece(.black, .queen, 59);

    try std.testing.expectEqual(Board.PieceOnSquare{
        .color = .black,
        .piece = .queen,
    }, board.pieceAt(59));
}

test "piece at finds every piece type for both colors" {
    for (std.enums.values(Color)) |color| {
        var board: Board = empty;

        // Place one of each piece type on its own square
        for (std.enums.values(Piece), 0..) |piece, i| {
            const sq: Square = @intCast(8 * i + 3);
            board.setPiece(color, piece, sq);
        }

        // Check each one comes back as the same color and type
        for (std.enums.values(Piece), 0..) |piece, i| {
            const sq: Square = @intCast(8 * i + 3);
            try std.testing.expectEqual(Board.PieceOnSquare{
                .color = color,
                .piece = piece,
            }, board.pieceAt(sq));
        }
    }
}

test "piece at is null after removePiece" {
    var board: Board = empty;
    board.setPiece(.white, .knight, 28);
    board.setPiece(.black, .king, 60);

    board.removePiece(.white, .knight, 28);

    // The removed square is empty and the other piece is untouched
    try std.testing.expectEqual(null, board.pieceAt(28));
    try std.testing.expectEqual(Board.PieceOnSquare{
        .color = .black,
        .piece = .king,
    }, board.pieceAt(60));

    // Both bitboards for the removed piece are cleared
    try std.testing.expectEqual(@as(u64, 0), board.getBoard(.white, .knight));
    try std.testing.expectEqual(@as(u64, 0), board.occupancy[@backingInt(Color.white)]);
}
