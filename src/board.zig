// Use single bit of data to indicate color
const Color = enum(u1) { 
    white,
    black,
};

// use 3 bits to indicate piece
const Piece = enum(u3) {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king
};

// 0-63 represent each square: 0 = a1, 1 = b1, ..., 63 = h8.
const Square = u6;

// Describing Castling Rights
const CastlingRights = u4;
const white_kingside: CastlingRights = 0b0001;
const white_queenside: CastlingRights = 0b0010;
const black_kingside: CastlingRights = 0b0100;
const black_queenside: CastlingRights = 0b1000;
// if move starts or ends one one of these squares, clear castling rights. Accounts for rook and king movement and rook being captured.
const castling_mask: [64]CastlingRights = blk: {
    var m: [64]CastlingRights = @splat(0b1111);
    m[0] = 0b1101; // a1: clears white queenside
    m[4] = 0b1100; // e1: clears both white rights
    m[7] = 0b1110; // h1: clears white kingside
    m[56] = 0b0111; // a8: clears black queenside
    m[60] = 0b0011; // e8: clears both black rights
    m[63] = 0b1011; // h8: clears black kingside
    break :blk m;
};


const Board = struct {
    pieces: [2][6]u64, // [color][piece]
    occupancy: [2]u64, // [color], helps when generating moves, so you don't have to compute from all 12 boards each time.
    side_to_move: Color,
    castling_rights: CastlingRights,
    en_passant: ?Square, // could be null
    halfmove_clock: u8, // tracks 50 move rule
    fullmove_number: u16, // tracks moves on both sides, not needed for calculation, but nice to have for printing

    pub fn getBoard(self: *Board, color: Color, piece: Piece) u64 {
        return self.pieces[@intFromEnum(color)][@intFromEnum(piece)];
    }
};
