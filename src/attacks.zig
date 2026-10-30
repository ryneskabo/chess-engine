const std = @import("std");

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
        const knight_square = @as(u64, 1) << sq;

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
        const king_square = @as(u64, 1) << sq;

        const north_east = (king_square << 9) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const north = (king_square << 8);
        const north_west = (king_square << 7) & not_h_file; // make sure we don't wrap around to h file by going too far west
        const east = (king_square << 1) & not_a_file; // make sure we don't wrap around to a file by going too far east

        const west = (king_square >> 1) & not_h_file; // make sure we don't wrap around to h file by going too far west
        const south_east = (king_square >> 7) & not_a_file; // make sure we don't wrap around to a file by going too far east
        const south = (king_square >> 8);
        const south_west = (king_square >> 9) & not_h_file; // make sure we don't wrap around to h file by going too far west

        a[sq]= north_east | north | north_west | east | west | south_east | south | south_west;
    }

    break :blk a;
};

fn bit(sq: u6) u64 {
    return @as(u64, 1) << sq;
}

test "knight attacks on corners" {
    // a1 (0) -> b3 (17), c2 (10)
    try std.testing.expectEqual(bit(10) | bit(17), knight_attacks[0]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[0]));

    // h1 (7) -> f2 (13), g3 (22)
    try std.testing.expectEqual(bit(13) | bit(22), knight_attacks[7]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[7]));

    // a8 (56) -> b6 (41), c7 (50)
    try std.testing.expectEqual(bit(41) | bit(50), knight_attacks[56]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[56]));

    // h8 (63) -> f7 (53), g6 (46)
    try std.testing.expectEqual(bit(46) | bit(53), knight_attacks[63]);
    try std.testing.expectEqual(@as(u7, 2), @popCount(knight_attacks[63]));
}

test "knight attacks on edges and near-edges (no wrap-around)" {
    // b1 (1) -> a3 (16), c3 (18), d2 (11)
    try std.testing.expectEqual(bit(16) | bit(18) | bit(11), knight_attacks[1]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(knight_attacks[1]));

    // a4 (24) -> b6 (41), c5 (34), c3 (18), b2 (9)
    try std.testing.expectEqual(bit(41) | bit(34) | bit(18) | bit(9), knight_attacks[24]);
    try std.testing.expectEqual(@as(u7, 4), @popCount(knight_attacks[24]));

    // h4 (31) -> g6 (46), f5 (37), f3 (21), g2 (14)
    try std.testing.expectEqual(bit(46) | bit(37) | bit(21) | bit(14), knight_attacks[31]);
    try std.testing.expectEqual(@as(u7, 4), @popCount(knight_attacks[31]));

    // b4 (25) -> a6 (40), c6 (42), d5 (35), d3 (19), c2 (10), a2 (8) (no wrap to h-file)
    try std.testing.expectEqual(bit(40) | bit(42) | bit(35) | bit(19) | bit(10) | bit(8), knight_attacks[25]);
    try std.testing.expectEqual(@as(u7, 6), @popCount(knight_attacks[25]));

    // g4 (30) -> f6 (45), h6 (47), e5 (36), e3 (20), f2 (13), h2 (15) (no wrap to a-file)
    try std.testing.expectEqual(bit(45) | bit(47) | bit(36) | bit(20) | bit(13) | bit(15), knight_attacks[30]);
    try std.testing.expectEqual(@as(u7, 6), @popCount(knight_attacks[30]));
}

test "knight attacks in the center" {
    // e4 (28) -> d6 (43), f6 (45), c5 (34), g5 (38), c3 (18), g3 (22), d2 (11), f2 (13)
    const expected = bit(43) | bit(45) | bit(34) | bit(38) | bit(18) | bit(22) | bit(11) | bit(13);
    try std.testing.expectEqual(expected, knight_attacks[28]);
    try std.testing.expectEqual(@as(u7, 8), @popCount(knight_attacks[28]));
}

test "knight attacks symmetry and no self-attacks" {
    for (0..64) |i| {
        const sq_i: u6 = @intCast(i);
        // Never attacks own square
        try std.testing.expectEqual(@as(u64, 0), knight_attacks[i] & bit(sq_i));

        // Symmetry: i attacks j iff j attacks i
        for (0..64) |j| {
            const sq_j: u6 = @intCast(j);
            const i_attacks_j = (knight_attacks[i] & bit(sq_j)) != 0;
            const j_attacks_i = (knight_attacks[j] & bit(sq_i)) != 0;
            try std.testing.expectEqual(i_attacks_j, j_attacks_i);
        }
    }
}

test "king attacks on corners" {
    // a1 (0) -> b1 (1), a2 (8), b2 (9)
    try std.testing.expectEqual(bit(1) | bit(8) | bit(9), king_attacks[0]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[0]));

    // h1 (7) -> g1 (6), g2 (14), h2 (15)
    try std.testing.expectEqual(bit(6) | bit(14) | bit(15), king_attacks[7]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[7]));

    // a8 (56) -> a7 (48), b7 (49), b8 (57)
    try std.testing.expectEqual(bit(48) | bit(49) | bit(57), king_attacks[56]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[56]));

    // h8 (63) -> g7 (54), h7 (55), g8 (62)
    try std.testing.expectEqual(bit(54) | bit(55) | bit(62), king_attacks[63]);
    try std.testing.expectEqual(@as(u7, 3), @popCount(king_attacks[63]));
}

test "king attacks on edges (no wrap-around)" {
    // e1 (4) -> d1 (3), f1 (5), d2 (11), e2 (12), f2 (13)
    try std.testing.expectEqual(bit(3) | bit(5) | bit(11) | bit(12) | bit(13), king_attacks[4]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[4]));

    // a4 (24) -> a5 (32), b5 (33), b4 (25), a3 (16), b3 (17)
    try std.testing.expectEqual(bit(32) | bit(33) | bit(25) | bit(16) | bit(17), king_attacks[24]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[24]));

    // h4 (31) -> g5 (38), h5 (39), g4 (30), g3 (22), h3 (23)
    try std.testing.expectEqual(bit(38) | bit(39) | bit(30) | bit(22) | bit(23), king_attacks[31]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[31]));

    // e8 (60) -> d8 (59), f8 (61), d7 (51), e7 (52), f7 (53)
    try std.testing.expectEqual(bit(59) | bit(61) | bit(51) | bit(52) | bit(53), king_attacks[60]);
    try std.testing.expectEqual(@as(u7, 5), @popCount(king_attacks[60]));
}

test "king attacks in the center" {
    // e4 (28) -> d5 (35), e5 (36), f5 (37), d4 (27), f4 (29), d3 (19), e3 (20), f3 (21)
    const expected = bit(35) | bit(36) | bit(37) | bit(27) | bit(29) | bit(19) | bit(20) | bit(21);
    try std.testing.expectEqual(expected, king_attacks[28]);
    try std.testing.expectEqual(@as(u7, 8), @popCount(king_attacks[28]));
}

test "king attacks symmetry and no self-attacks" {
    for (0..64) |i| {
        const sq_i: u6 = @intCast(i);
        // Never attacks own square
        try std.testing.expectEqual(@as(u64, 0), king_attacks[i] & bit(sq_i));

        // Symmetry: i attacks j iff j attacks i
        for (0..64) |j| {
            const sq_j: u6 = @intCast(j);
            const i_attacks_j = (king_attacks[i] & bit(sq_j)) != 0;
            const j_attacks_i = (king_attacks[j] & bit(sq_i)) != 0;
            try std.testing.expectEqual(i_attacks_j, j_attacks_i);
        }
    }
}

test "attack table totals" {
    var knight_total: u32 = 0;
    var king_total: u32 = 0;
    for (0..64) |i| {
        knight_total += @popCount(knight_attacks[i]);
        king_total += @popCount(king_attacks[i]);
    }
    try std.testing.expectEqual(@as(u32, 336), knight_total);
    try std.testing.expectEqual(@as(u32, 420), king_total);
}
