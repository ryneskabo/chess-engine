const std = @import("std");
const brd = @import("board.zig");

const not_a_file: u64 = 0xfefefefefefefefe; // clears a file bits: 0, 8, 16, 24, etc.
const not_b_file: u64 = 0xfdfdfdfdfdfdfdfd; // clears b file bits: 1, 9, 17, 25, etc.
const not_ab_file: u64 = not_a_file & not_b_file; // clears both a and b file bits
const not_g_file: u64 = 0xbfbfbfbfbfbfbfbf; // clears g file bits: 6, 14, 22, 30, etc.
const not_h_file: u64 = 0x7f7f7f7f7f7f7f7f; // clears h file bits: 7, 15, 23, 31, etc.
const not_gh_file: u64 = not_g_file & not_h_file; // clears both g and h file bits

/// each spot in array holds bitboards with squares set that the knight on [square] attacks.
pub const knight_attacks: [64]u64 = blk: {
    var a: [64]u64 = @splat(0);
    for (0..64) |sq| {
        const knight_square = squareBit(@intCast(sq));
        const north_north_east = (knight_square << 17) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const north_north_west = (knight_square << 15) & not_h_file; // make sure we don't wrap around to h file by going too far west
        const north_east_east = (knight_square << 10) & not_ab_file; // make sure we don't wrap around to a or b file by going too far east
        const north_west_west = (knight_square << 6) & not_gh_file; // make sure we don't wrap around to g or h file by going too far west

        const south_east_east = (knight_square >> 6) & not_ab_file; // make sure we don't wrap around to a or b file by going too far east
        const south_west_west = (knight_square >> 10) & not_gh_file; // make sure we don't wrap around to g or h file by going too far west
        const south_south_east = (knight_square >> 15) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const south_south_west = (knight_square >> 17) & not_h_file; // make sure we don't wrap around to h file by going too far west

        a[sq] = north_north_east | north_north_west | north_east_east | north_west_west | south_east_east | south_west_west | south_south_east | south_south_west;
    }

    break :blk a;
};

/// each spot in array holds bitboards with squares set that the king on [square] attacks.
pub const king_attacks: [64]u64 = blk: {
    var a: [64]u64 = @splat(0);
    for (0..64) |sq| {
        const king_square = squareBit(@intCast(sq));

        const north_east = (king_square << 9) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const north = (king_square << 8);
        const north_west = (king_square << 7) & not_h_file; // make sure we don't wrap around to h file by going too far west
        const east = (king_square << 1) & not_a_file; // make sure we don't wrap around to a file by going too far east

        const west = (king_square >> 1) & not_h_file; // make sure we don't wrap around to h file by going too far west
        const south_east = (king_square >> 7) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const south = (king_square >> 8);
        const south_west = (king_square >> 9) & not_h_file; // make sure we don't wrap around to h file by going too far west

        a[sq] = north_east | north | north_west | east | west | south_east | south | south_west;
    }

    break :blk a;
};

/// each spot in array holds bitboards with squares set that the pawn of that color on [square] attacks. This only deals with attacks and not pushes.
pub const pawn_attacks: [2][64]u64 = blk: { // pawn attacks need to be split, as white and black pawns attack in opposite directions
    var a: [2][64]u64 = @splat(@splat(0));

    for (0..64) |sq| {
        const pawn_square = squareBit(@intCast(sq));

        // These are white pawn attacks
        const north_west = (pawn_square << 7) & not_h_file; // make sure we don't wrap around to h file by going too far west
        const north_east = (pawn_square << 9) & not_a_file; // make sure we don't wrap around to a file by going too far east

        // These are black pawn attacks
        const south_east = (pawn_square >> 7) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const south_west = (pawn_square >> 9) & not_h_file; // make sure we don't wrap around to h file by going too far west

        a[0][sq] = north_west | north_east;
        a[1][sq] = south_east | south_west;
    }

    break :blk a;
};

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

test "knight attacks on corners" {
    // a1 (0) -> b3 (17), c2 (10)
    try std.testing.expectEqual(squareBit(10) | squareBit(17), knight_attacks[0]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[0]));

    // h1 (7) -> f2 (13), g3 (22)
    try std.testing.expectEqual(squareBit(13) | squareBit(22), knight_attacks[7]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[7]));

    // a8 (56) -> b6 (41), c7 (50)
    try std.testing.expectEqual(squareBit(41) | squareBit(50), knight_attacks[56]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[56]));

    // h8 (63) -> f7 (53), g6 (46)
    try std.testing.expectEqual(squareBit(46) | squareBit(53), knight_attacks[63]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[63]));
}

test "knight attacks on edges and near-edges (no wrap-around)" {
    // b1 (1) -> a3 (16), c3 (18), d2 (11)
    try std.testing.expectEqual(squareBit(16) | squareBit(18) | squareBit(11), knight_attacks[1]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(knight_attacks[1]));

    // a4 (24) -> b6 (41), c5 (34), c3 (18), b2 (9)
    try std.testing.expectEqual(squareBit(41) | squareBit(34) | squareBit(18) | squareBit(9), knight_attacks[24]);
    try std.testing.expectEqual(@as(u7, 4), @popCount(knight_attacks[24]));

    // h4 (31) -> g6 (46), f5 (37), f3 (21), g2 (14)
    try std.testing.expectEqual(squareBit(46) | squareBit(37) | squareBit(21) | squareBit(14), knight_attacks[31]);
    try std.testing.expectEqual(@as(u7, 4), @popCount(knight_attacks[31]));

    // b4 (25) -> a6 (40), c6 (42), d5 (35), d3 (19), c2 (10), a2 (8) (no wrap to h-file)
    try std.testing.expectEqual(squareBit(40) | squareBit(42) | squareBit(35) | squareBit(19) | squareBit(10) | squareBit(8), knight_attacks[25]);
    try std.testing.expectEqual(@as(u7, 6), @popCount(knight_attacks[25]));

    // g4 (30) -> f6 (45), h6 (47), e5 (36), e3 (20), f2 (13), h2 (15) (no wrap to a-file)
    try std.testing.expectEqual(squareBit(45) | squareBit(47) | squareBit(36) | squareBit(20) | squareBit(13) | squareBit(15), knight_attacks[30]);
    try std.testing.expectEqual(@as(u7, 6), @popCount(knight_attacks[30]));
}

test "knight attacks in the center" {
    // e4 (28) -> d6 (43), f6 (45), c5 (34), g5 (38), c3 (18), g3 (22), d2 (11), f2 (13)
    const expected = squareBit(43) | squareBit(45) | squareBit(34) | squareBit(38) | squareBit(18) | squareBit(22) | squareBit(11) | squareBit(13);
    try std.testing.expectEqual(expected, knight_attacks[28]);
    try std.testing.expectEqual(@as(u7, 8), @popCount(knight_attacks[28]));
}

test "knight attacks symmetry and no self-attacks" {
    for (0..64) |i| {
        const sq_i: u6 = @intCast(i);
        // Never attacks own square
        try std.testing.expectEqual(@as(u64, 0), knight_attacks[i] & squareBit(sq_i));

        // Symmetry: i attacks j iff j attacks i
        for (0..64) |j| {
            const sq_j: u6 = @intCast(j);
            const i_attacks_j = (knight_attacks[i] & squareBit(sq_j)) != 0;
            const j_attacks_i = (knight_attacks[j] & squareBit(sq_i)) != 0;
            try std.testing.expectEqual(i_attacks_j, j_attacks_i);
        }
    }
}

test "king attacks on corners" {
    // a1 (0) -> b1 (1), a2 (8), b2 (9)
    try std.testing.expectEqual(squareBit(1) | squareBit(8) | squareBit(9), king_attacks[0]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[0]));

    // h1 (7) -> g1 (6), g2 (14), h2 (15)
    try std.testing.expectEqual(squareBit(6) | squareBit(14) | squareBit(15), king_attacks[7]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[7]));

    // a8 (56) -> a7 (48), b7 (49), b8 (57)
    try std.testing.expectEqual(squareBit(48) | squareBit(49) | squareBit(57), king_attacks[56]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[56]));

    // h8 (63) -> g7 (54), h7 (55), g8 (62)
    try std.testing.expectEqual(squareBit(54) | squareBit(55) | squareBit(62), king_attacks[63]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[63]));
}

test "king attacks on edges (no wrap-around)" {
    // e1 (4) -> d1 (3), f1 (5), d2 (11), e2 (12), f2 (13)
    try std.testing.expectEqual(squareBit(3) | squareBit(5) | squareBit(11) | squareBit(12) | squareBit(13), king_attacks[4]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[4]));

    // a4 (24) -> a5 (32), b5 (33), b4 (25), a3 (16), b3 (17)
    try std.testing.expectEqual(squareBit(32) | squareBit(33) | squareBit(25) | squareBit(16) | squareBit(17), king_attacks[24]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[24]));

    // h4 (31) -> g5 (38), h5 (39), g4 (30), g3 (22), h3 (23)
    try std.testing.expectEqual(squareBit(38) | squareBit(39) | squareBit(30) | squareBit(22) | squareBit(23), king_attacks[31]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[31]));

    // e8 (60) -> d8 (59), f8 (61), d7 (51), e7 (52), f7 (53)
    try std.testing.expectEqual(squareBit(59) | squareBit(61) | squareBit(51) | squareBit(52) | squareBit(53), king_attacks[60]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[60]));
}

test "king attacks in the center" {
    // e4 (28) -> d5 (35), e5 (36), f5 (37), d4 (27), f4 (29), d3 (19), e3 (20), f3 (21)
    const expected = squareBit(35) | squareBit(36) | squareBit(37) | squareBit(27) | squareBit(29) | squareBit(19) | squareBit(20) | squareBit(21);
    try std.testing.expectEqual(expected, king_attacks[28]);
    try std.testing.expectEqual(@as(u7, 8), @popCount(king_attacks[28]));
}

test "king attacks symmetry and no self-attacks" {
    for (0..64) |i| {
        const sq_i: u6 = @intCast(i);
        // Never attacks own square
        try std.testing.expectEqual(@as(u64, 0), king_attacks[i] & squareBit(sq_i));

        // Symmetry: i attacks j iff j attacks i
        for (0..64) |j| {
            const sq_j: u6 = @intCast(j);
            const i_attacks_j = (king_attacks[i] & squareBit(sq_j)) != 0;
            const j_attacks_i = (king_attacks[j] & squareBit(sq_i)) != 0;
            try std.testing.expectEqual(i_attacks_j, j_attacks_i);
        }
    }
}

test "knight and king attack table totals" {
    var knight_total: u32 = 0;
    var king_total: u32 = 0;
    for (0..64) |i| {
        knight_total += @popCount(knight_attacks[i]);
        king_total += @popCount(king_attacks[i]);
    }
    try std.testing.expectEqual(@as(u32, 336), knight_total);
    try std.testing.expectEqual(@as(u32, 420), king_total);
}

const white = @backingInt(brd.Color.white);
const black = @backingInt(brd.Color.black);

test "white pawn attacks" {
    // e2 (12) -> d3 (19), f3 (21)
    try std.testing.expectEqual(squareBit(19) | squareBit(21), pawn_attacks[white][12]);
    // a2 (8) -> b3 (17) only, no wrap to the h-file
    try std.testing.expectEqual(squareBit(17), pawn_attacks[white][8]);
    // h2 (15) -> g3 (22) only, no wrap to the a-file
    try std.testing.expectEqual(squareBit(22), pawn_attacks[white][15]);
}

test "black pawn attacks" {
    // e7 (52) -> d6 (43), f6 (45)
    try std.testing.expectEqual(squareBit(43) | squareBit(45), pawn_attacks[black][52]);
    // a7 (48) -> b6 (41) only
    try std.testing.expectEqual(squareBit(41), pawn_attacks[black][48]);
    // h7 (55) -> g6 (46) only
    try std.testing.expectEqual(squareBit(46), pawn_attacks[black][55]);
}

test "pawn attack totals" {
    // Pawns only stand on ranks 2 to 7 (squares 8 to 55). Each rank has
    // 2 edge-file squares with 1 attack and 6 others with 2 attacks: 14 per rank.
    var white_total: u32 = 0;
    var black_total: u32 = 0;
    for (8..56) |i| {
        white_total += @popCount(pawn_attacks[white][i]);
        black_total += @popCount(pawn_attacks[black][i]);
    }
    try std.testing.expectEqual(@as(u32, 84), white_total);
    try std.testing.expectEqual(@as(u32, 84), black_total);
}

test "pawn attack symmetry between colors" {
    // A white pawn on i attacks j exactly when a black pawn on j attacks i.
    for (0..64) |i| {
        for (0..64) |j| {
            const white_hits = (pawn_attacks[white][i] & squareBit(@intCast(j))) != 0;
            const black_hits = (pawn_attacks[black][j] & squareBit(@intCast(i))) != 0;
            try std.testing.expectEqual(white_hits, black_hits);
        }
    }
}
