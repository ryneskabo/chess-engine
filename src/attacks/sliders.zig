const std = @import("std");
const brd = @import("../board.zig");

const squareBit = brd.squareBit;

/// Pass in 0-7 for rank and file
pub fn bitBoardFromRankAndFile(rank: u3, file: u3) u64 {
    return squareBit(@as(u6, rank) * 8 + file);
}

pub const RayDirection = enum(u3) {
    north = 0,
    northeast = 1,
    northwest = 2,
    east = 3,
    south = 4,
    southeast = 5,
    southwest = 6,
    west = 7,
};

pub const ray_table: [8][64]u64 = blk: {
    @setEvalBranchQuota(10000);
    var rays: [8][64]u64 = @splat(@splat(0));

    // Step vectors (rank_step, file_step) ordered to match RayDirection enum values.
    const steps = [8][2]i8{
        .{ 1, 0 }, // north
        .{ 1, 1 }, // northeast
        .{ 1, -1 }, // northwest
        .{ 0, 1 }, // east
        .{ -1, 0 }, // south
        .{ -1, 1 }, // southeast
        .{ -1, -1 }, // southwest
        .{ 0, -1 }, // west
    };

    for (steps, 0..) |step, dir| {
        const rank_step = step[0];
        const file_step = step[1];

        for (0..64) |sq| {
            var rank: i8 = @intCast(sq / 8);
            var file: i8 = @intCast(sq % 8);
            rank += rank_step;
            file += file_step;
            while (rank >= 0 and rank < 8 and file >= 0 and file < 8) : ({
                rank += rank_step;
                file += file_step;
            }) {
                rays[dir][sq] |= bitBoardFromRankAndFile(@intCast(rank), @intCast(file));
            }
        }
    }

    break :blk rays;
};

pub fn rayAttacks(comptime direction: RayDirection, from: brd.Square, occupancy: u64) u64 {
    const dir = @backingInt(direction);
    const blockers = ray_table[dir][from] & occupancy;

    if (blockers == 0) return ray_table[dir][from]; // if no blocker, return whole ray, preventing overflow on the following @intCast and preventing underflow in following 63 - @clz

    // Directions 0-3 move toward higher square indices; 4-7 move toward lower indices.
    const first_blocker: brd.Square = if (dir < 4) @intCast(@ctz(blockers)) else @intCast(63 - @clz(blockers));
    return ray_table[dir][from] ^ ray_table[dir][first_blocker];
}

pub fn rookAttacks(from: brd.Square, occupancy: u64) u64 {
    return rayAttacks(.north, from, occupancy) | rayAttacks(.east, from, occupancy) | rayAttacks(.west, from, occupancy) | rayAttacks(.south, from, occupancy);
}

pub fn bishopAttacks(from: brd.Square, occupancy: u64) u64 {
    return rayAttacks(.northeast, from, occupancy) | rayAttacks(.northwest, from, occupancy) | rayAttacks(.southeast, from, occupancy) | rayAttacks(.southwest, from, occupancy);
}

pub fn queenAttacks(from: brd.Square, occupancy: u64) u64 {
    return bishopAttacks(from, occupancy) | rookAttacks(from, occupancy);
}

test "ray_table from corners a1 and h8" {
    // a1 (0): North = a2..a8, East = b1..h1, Northeast = b2..h8, all others empty
    const a1_north = squareBit(8) | squareBit(16) | squareBit(24) | squareBit(32) | squareBit(40) | squareBit(48) | squareBit(56);
    const a1_east = squareBit(1) | squareBit(2) | squareBit(3) | squareBit(4) | squareBit(5) | squareBit(6) | squareBit(7);
    const a1_ne = squareBit(9) | squareBit(18) | squareBit(27) | squareBit(36) | squareBit(45) | squareBit(54) | squareBit(63);

    try std.testing.expectEqual(a1_north, ray_table[@backingInt(RayDirection.north)][0]);
    try std.testing.expectEqual(a1_east, ray_table[@backingInt(RayDirection.east)][0]);
    try std.testing.expectEqual(a1_ne, ray_table[@backingInt(RayDirection.northeast)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.northwest)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.south)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.southeast)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.southwest)][0]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.west)][0]);

    // h8 (63): South = h1..h7, West = a8..g8, Southwest = a1..g7, all others empty
    const h8_south = squareBit(7) | squareBit(15) | squareBit(23) | squareBit(31) | squareBit(39) | squareBit(47) | squareBit(55);
    const h8_west = squareBit(56) | squareBit(57) | squareBit(58) | squareBit(59) | squareBit(60) | squareBit(61) | squareBit(62);
    const h8_sw = squareBit(0) | squareBit(9) | squareBit(18) | squareBit(27) | squareBit(36) | squareBit(45) | squareBit(54);

    try std.testing.expectEqual(h8_south, ray_table[@backingInt(RayDirection.south)][63]);
    try std.testing.expectEqual(h8_west, ray_table[@backingInt(RayDirection.west)][63]);
    try std.testing.expectEqual(h8_sw, ray_table[@backingInt(RayDirection.southwest)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.north)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.northeast)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.northwest)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.east)][63]);
    try std.testing.expectEqual(@as(u64, 0), ray_table[@backingInt(RayDirection.southeast)][63]);
}

test "ray_table from center square e4 in all 8 directions" {
    // e4 = 28 (rank 3, file 4)
    try std.testing.expectEqual(
        squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60), // e5, e6, e7, e8
        ray_table[@backingInt(RayDirection.north)][28],
    );
    try std.testing.expectEqual(
        squareBit(20) | squareBit(12) | squareBit(4), // e3, e2, e1
        ray_table[@backingInt(RayDirection.south)][28],
    );
    try std.testing.expectEqual(
        squareBit(29) | squareBit(30) | squareBit(31), // f4, g4, h4
        ray_table[@backingInt(RayDirection.east)][28],
    );
    try std.testing.expectEqual(
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24), // d4, c4, b4, a4
        ray_table[@backingInt(RayDirection.west)][28],
    );
    try std.testing.expectEqual(
        squareBit(37) | squareBit(46) | squareBit(55), // f5, g6, h7
        ray_table[@backingInt(RayDirection.northeast)][28],
    );
    try std.testing.expectEqual(
        squareBit(35) | squareBit(42) | squareBit(49) | squareBit(56), // d5, c6, b7, a8
        ray_table[@backingInt(RayDirection.northwest)][28],
    );
    try std.testing.expectEqual(
        squareBit(21) | squareBit(14) | squareBit(7), // f3, g2, h1
        ray_table[@backingInt(RayDirection.southeast)][28],
    );
    try std.testing.expectEqual(
        squareBit(19) | squareBit(10) | squareBit(1), // d3, c2, b1
        ray_table[@backingInt(RayDirection.southwest)][28],
    );
}

test "ray_table has no self-inclusion, disjoint directions, and 14 rook squares per square" {
    for (0..64) |sq| {
        const origin_bit = squareBit(@intCast(sq));

        for (0..8) |d1| {
            // A ray never includes the origin square itself
            try std.testing.expectEqual(@as(u64, 0), ray_table[d1][sq] & origin_bit);

            // Different directions from the same square never overlap
            for ((d1 + 1)..8) |d2| {
                try std.testing.expectEqual(@as(u64, 0), ray_table[d1][sq] & ray_table[d2][sq]);
            }
        }

        // Orthogonal rays from any square always cover 7 rank + 7 file = 14 squares
        const rook_rays = ray_table[@backingInt(RayDirection.north)][sq] |
            ray_table[@backingInt(RayDirection.south)][sq] |
            ray_table[@backingInt(RayDirection.east)][sq] |
            ray_table[@backingInt(RayDirection.west)][sq];
        try std.testing.expectEqual(@as(u7, 14), @popCount(rook_rays));
    }
}

test "ray_table rook and bishop square counts on d4 and a1" {
    // d4 = 27: rook attacks 14 squares, bishop attacks 13 squares
    const d4_rook = ray_table[@backingInt(RayDirection.north)][27] |
        ray_table[@backingInt(RayDirection.south)][27] |
        ray_table[@backingInt(RayDirection.east)][27] |
        ray_table[@backingInt(RayDirection.west)][27];
    const d4_bishop = ray_table[@backingInt(RayDirection.northeast)][27] |
        ray_table[@backingInt(RayDirection.northwest)][27] |
        ray_table[@backingInt(RayDirection.southeast)][27] |
        ray_table[@backingInt(RayDirection.southwest)][27];
    try std.testing.expectEqual(@as(u7, 14), @popCount(d4_rook));
    try std.testing.expectEqual(@as(u7, 13), @popCount(d4_bishop));

    // a1 = 0: rook attacks 14 squares, bishop attacks 7 squares
    const a1_rook = ray_table[@backingInt(RayDirection.north)][0] |
        ray_table[@backingInt(RayDirection.south)][0] |
        ray_table[@backingInt(RayDirection.east)][0] |
        ray_table[@backingInt(RayDirection.west)][0];
    const a1_bishop = ray_table[@backingInt(RayDirection.northeast)][0] |
        ray_table[@backingInt(RayDirection.northwest)][0] |
        ray_table[@backingInt(RayDirection.southeast)][0] |
        ray_table[@backingInt(RayDirection.southwest)][0];
    try std.testing.expectEqual(@as(u7, 14), @popCount(a1_rook));
    try std.testing.expectEqual(@as(u7, 7), @popCount(a1_bishop));
}

test "ray_table blocker masking on d4 north (d6) and south (d2)" {
    // Rook on d4 (27) with a blocker on d6 (43):
    // North ray from d4 masked by North ray from the first blocker (d6) leaves d5 (35) and d6 (43), excluding d7 (51) and d8 (59).
    const north_dir = @backingInt(RayDirection.north);
    const north_blockers = ray_table[north_dir][27] & squareBit(43);
    const first_north_blocker: brd.Square = @intCast(@ctz(north_blockers));
    const north_attacks = ray_table[north_dir][27] ^ ray_table[north_dir][first_north_blocker];
    try std.testing.expectEqual(squareBit(35) | squareBit(43), north_attacks);
    try std.testing.expectEqual(@as(u64, 0), north_attacks & (squareBit(51) | squareBit(59)));

    // Rook on d4 (27) with a blocker on d2 (11):
    // South ray from d4 masked by South ray from the first blocker (d2, highest bit via 63 - @clz) leaves d3 (19) and d2 (11), excluding d1 (3).
    const south_dir = @backingInt(RayDirection.south);
    const south_blockers = ray_table[south_dir][27] & squareBit(11);
    const first_south_blocker: brd.Square = @intCast(63 - @clz(south_blockers));
    const south_attacks = ray_table[south_dir][27] ^ ray_table[south_dir][first_south_blocker];
    try std.testing.expectEqual(squareBit(19) | squareBit(11), south_attacks);
    try std.testing.expectEqual(@as(u64, 0), south_attacks & squareBit(3));
}

test "ray_table totals across all 64 squares for rook, bishop, and queen" {
    var rook_total: u32 = 0;
    var bishop_total: u32 = 0;
    var queen_total: u32 = 0;

    for (0..64) |sq| {
        const rook_rays = ray_table[@backingInt(RayDirection.north)][sq] |
            ray_table[@backingInt(RayDirection.south)][sq] |
            ray_table[@backingInt(RayDirection.east)][sq] |
            ray_table[@backingInt(RayDirection.west)][sq];
        const bishop_rays = ray_table[@backingInt(RayDirection.northeast)][sq] |
            ray_table[@backingInt(RayDirection.northwest)][sq] |
            ray_table[@backingInt(RayDirection.southeast)][sq] |
            ray_table[@backingInt(RayDirection.southwest)][sq];
        const queen_rays = rook_rays | bishop_rays;

        rook_total += @popCount(rook_rays);
        bishop_total += @popCount(bishop_rays);
        queen_total += @popCount(queen_rays);
    }

    try std.testing.expectEqual(@as(u32, 896), rook_total);
    try std.testing.expectEqual(@as(u32, 560), bishop_total);
    try std.testing.expectEqual(@as(u32, 1456), queen_total);
}

test "ray_table opposite-direction symmetry" {
    const pairs = [_][2]RayDirection{
        .{ .north, .south },
        .{ .east, .west },
        .{ .northeast, .southwest },
        .{ .northwest, .southeast },
    };

    for (pairs) |pair| {
        const d_fwd = @backingInt(pair[0]);
        const d_rev = @backingInt(pair[1]);

        for (0..64) |i| {
            for (0..64) |j| {
                const j_in_fwd = (ray_table[d_fwd][i] & squareBit(@intCast(j))) != 0;
                const i_in_rev = (ray_table[d_rev][j] & squareBit(@intCast(i))) != 0;
                try std.testing.expectEqual(j_in_fwd, i_in_rev);
            }
        }
    }
}
const RayStep = struct { rank: i8, file: i8 };

/// Reference implementation: walk one square at a time in the given direction,
/// adding each square until the edge is reached or the first occupied square is hit.
fn naiveRayAttacks(comptime direction: RayDirection, from: brd.Square, occupancy: u64) u64 {
    const step: RayStep = switch (direction) {
        .north => .{ .rank = 1, .file = 0 },
        .northeast => .{ .rank = 1, .file = 1 },
        .northwest => .{ .rank = 1, .file = -1 },
        .east => .{ .rank = 0, .file = 1 },
        .south => .{ .rank = -1, .file = 0 },
        .southeast => .{ .rank = -1, .file = 1 },
        .southwest => .{ .rank = -1, .file = -1 },
        .west => .{ .rank = 0, .file = -1 },
    };

    var rank: i8 = @intCast(from / 8);
    var file: i8 = @intCast(from % 8);
    var attacks: u64 = 0;

    while (true) {
        rank += step.rank;
        file += step.file;
        if (rank < 0 or rank >= 8 or file < 0 or file >= 8) break;

        const sq: brd.Square = @intCast(rank * 8 + file);
        const bit = squareBit(sq);
        attacks |= bit;
        if (occupancy & bit != 0) break;
    }

    return attacks;
}

fn naiveRookAttacks(from: brd.Square, occupancy: u64) u64 {
    return naiveRayAttacks(.north, from, occupancy) |
        naiveRayAttacks(.east, from, occupancy) |
        naiveRayAttacks(.west, from, occupancy) |
        naiveRayAttacks(.south, from, occupancy);
}

fn naiveBishopAttacks(from: brd.Square, occupancy: u64) u64 {
    return naiveRayAttacks(.northeast, from, occupancy) |
        naiveRayAttacks(.northwest, from, occupancy) |
        naiveRayAttacks(.southeast, from, occupancy) |
        naiveRayAttacks(.southwest, from, occupancy);
}

fn naiveQueenAttacks(from: brd.Square, occupancy: u64) u64 {
    return naiveRookAttacks(from, occupancy) | naiveBishopAttacks(from, occupancy);
}

test "rayAttacks returns the full ray when the path is empty" {
    const from: brd.Square = 28; // e4

    try std.testing.expectEqual(
        squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60), // e5-e8
        rayAttacks(.north, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(20) | squareBit(12) | squareBit(4), // e3-e1
        rayAttacks(.south, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(29) | squareBit(30) | squareBit(31), // f4-h4
        rayAttacks(.east, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24), // d4-a4
        rayAttacks(.west, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(37) | squareBit(46) | squareBit(55), // f5-h7
        rayAttacks(.northeast, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(35) | squareBit(42) | squareBit(49) | squareBit(56), // d5-a8
        rayAttacks(.northwest, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(21) | squareBit(14) | squareBit(7), // f3-h1
        rayAttacks(.southeast, from, 0),
    );
    try std.testing.expectEqual(
        squareBit(19) | squareBit(10) | squareBit(1), // d3-b1
        rayAttacks(.southwest, from, 0),
    );
}

test "rayAttacks includes the first blocker and excludes squares behind it" {
    const from: brd.Square = 28; // e4

    try std.testing.expectEqual(
        squareBit(36) | squareBit(44), // e5, e6
        rayAttacks(.north, from, squareBit(44)),
    );
    try std.testing.expectEqual(
        squareBit(20) | squareBit(12), // e3, e2
        rayAttacks(.south, from, squareBit(12)),
    );
    try std.testing.expectEqual(
        squareBit(29) | squareBit(30), // f4, g4
        rayAttacks(.east, from, squareBit(30)),
    );
    try std.testing.expectEqual(
        squareBit(27) | squareBit(26), // d4, c4
        rayAttacks(.west, from, squareBit(26)),
    );
    try std.testing.expectEqual(
        squareBit(37) | squareBit(46), // f5, g6
        rayAttacks(.northeast, from, squareBit(46)),
    );
    try std.testing.expectEqual(
        squareBit(35) | squareBit(42), // d5, c6
        rayAttacks(.northwest, from, squareBit(42)),
    );
    try std.testing.expectEqual(
        squareBit(21) | squareBit(14), // f3, g2
        rayAttacks(.southeast, from, squareBit(14)),
    );
    try std.testing.expectEqual(
        squareBit(19) | squareBit(10), // d3, c2
        rayAttacks(.southwest, from, squareBit(10)),
    );
}

test "rayAttacks chooses the nearest blocker, ignores off-ray blockers, and ignores the origin" {
    const from: brd.Square = 28; // e4
    const full_north = squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60);

    // Blockers on e6 and e7: only e6 and the squares before it are attacked.
    try std.testing.expectEqual(
        squareBit(36) | squareBit(44),
        rayAttacks(.north, from, squareBit(44) | squareBit(52)),
    );

    // An adjacent blocker is the only square returned on that ray.
    try std.testing.expectEqual(
        squareBit(36),
        rayAttacks(.north, from, squareBit(36) | squareBit(52)),
    );

    // A piece on the slider's own square does not block its own ray.
    try std.testing.expectEqual(full_north, rayAttacks(.north, from, squareBit(28)));

    // Blockers that are not on the ray do not affect it.
    try std.testing.expectEqual(
        full_north,
        rayAttacks(.north, from, squareBit(0) | squareBit(7) | squareBit(63)),
    );
}

test "rayAttacks from the corners stays on the board" {
    // a1 (0)
    try std.testing.expectEqual(
        squareBit(8) | squareBit(16) | squareBit(24), // a2-a4
        rayAttacks(.north, 0, squareBit(24)),
    );
    try std.testing.expectEqual(
        squareBit(1) | squareBit(2), // b1, c1
        rayAttacks(.east, 0, squareBit(2)),
    );
    try std.testing.expectEqual(
        squareBit(9) | squareBit(18), // b2, c3
        rayAttacks(.northeast, 0, squareBit(18)),
    );

    // h8 (63)
    try std.testing.expectEqual(
        squareBit(55) | squareBit(47), // h7, h6
        rayAttacks(.south, 63, squareBit(47)),
    );
    try std.testing.expectEqual(
        squareBit(62) | squareBit(61), // g8, f8
        rayAttacks(.west, 63, squareBit(61)),
    );
    try std.testing.expectEqual(
        squareBit(54) | squareBit(45), // g7, f6
        rayAttacks(.southwest, 63, squareBit(45)),
    );
}

test "rayAttacks stops at a single blocker from every square in every direction" {
    inline for (std.enums.values(RayDirection)) |direction| {
        for (0..64) |from_index| {
            const from: brd.Square = @intCast(from_index);

            for (0..64) |blocker_index| {
                const occupancy = squareBit(@intCast(blocker_index));
                try std.testing.expectEqual(
                    naiveRayAttacks(direction, from, occupancy),
                    rayAttacks(direction, from, occupancy),
                );
            }
        }
    }
}

test "rayAttacks matches a naive walk for every square and random occupancies (fixed seed)" {
    var prng = std.Random.DefaultPrng.init(0x9E37_79B9_7F4A_7C15);
    const random = prng.random();

    var iteration: usize = 0;
    while (iteration < 3000) : (iteration += 1) {
        // Keep a guaranteed empty-board case, then use dense random occupancies.
        const occupancy: u64 = if (iteration == 0) 0 else random.int(u64);

        inline for (std.enums.values(RayDirection)) |direction| {
            for (0..64) |sq| {
                const from: brd.Square = @intCast(sq);
                try std.testing.expectEqual(
                    naiveRayAttacks(direction, from, occupancy),
                    rayAttacks(direction, from, occupancy),
                );
            }
        }
    }
}

test "rookAttacks covers the full rank and file on an empty board" {
    const from: brd.Square = 28; // e4
    const expected = squareBit(36) | squareBit(44) | squareBit(52) | squareBit(60) | // e5-e8
        squareBit(20) | squareBit(12) | squareBit(4) | // e3-e1
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | squareBit(26) | squareBit(25) | squareBit(24); // d4-a4

    try std.testing.expectEqual(expected, rookAttacks(from, 0));
    try std.testing.expectEqual(@as(u7, 14), @popCount(expected));
    try std.testing.expectEqual(expected, rookAttacks(from, squareBit(from)));
}

test "rookAttacks stops at the nearest blocker on each ray" {
    // Rook on e4 with blockers on e6, c4, e2, and g4.
    const occupancy = squareBit(44) | squareBit(26) | squareBit(12) | squareBit(30);
    const expected = squareBit(36) | squareBit(44) | // e5, e6
        squareBit(20) | squareBit(12) | // e3, e2
        squareBit(29) | squareBit(30) | // f4, g4
        squareBit(27) | squareBit(26); // d4, c4

    const attacks = rookAttacks(28, occupancy);
    try std.testing.expectEqual(expected, attacks);
    try std.testing.expectEqual(@as(u7, 8), @popCount(attacks));

    // Nothing past any of the blockers.
    try std.testing.expectEqual(@as(u64, 0), attacks & (squareBit(52) | squareBit(25) | squareBit(4) | squareBit(31)));
}

test "rookAttacks with a fully occupied board only reaches adjacent squares" {
    const occupancy: u64 = ~@as(u64, 0);

    try std.testing.expectEqual(
        squareBit(36) | squareBit(29) | squareBit(20) | squareBit(27), // e5, f4, e3, d4
        rookAttacks(28, occupancy),
    );
    try std.testing.expectEqual(
        squareBit(8) | squareBit(1), // a2, b1
        rookAttacks(0, occupancy),
    );
    try std.testing.expectEqual(
        squareBit(55) | squareBit(62), // h7, g8
        rookAttacks(63, occupancy),
    );
}

test "bishopAttacks covers both diagonals on an empty board" {
    const from: brd.Square = 28; // e4
    const expected = squareBit(37) | squareBit(46) | squareBit(55) | // f5-h7
        squareBit(35) | squareBit(42) | squareBit(49) | squareBit(56) | // d5-a8
        squareBit(21) | squareBit(14) | squareBit(7) | // f3-h1
        squareBit(19) | squareBit(10) | squareBit(1); // d3-b1

    try std.testing.expectEqual(expected, bishopAttacks(from, 0));
    try std.testing.expectEqual(@as(u7, 13), @popCount(expected));
    try std.testing.expectEqual(expected, bishopAttacks(from, squareBit(from)));
}

test "bishopAttacks stops on the first blocker of each diagonal" {
    // Bishop on e4 with blockers on c6 and g2.
    const occupancy = squareBit(42) | squareBit(14);
    const expected = squareBit(37) | squareBit(46) | squareBit(55) | // f5, g6, h7
        squareBit(35) | squareBit(42) | // d5, c6
        squareBit(21) | squareBit(14) | // f3, g2
        squareBit(19) | squareBit(10) | squareBit(1); // d3, c2, b1

    const attacks = bishopAttacks(28, occupancy);
    try std.testing.expectEqual(expected, attacks);
    try std.testing.expectEqual(@as(u7, 10), @popCount(attacks));

    // Nothing behind c6 or g2.
    try std.testing.expectEqual(@as(u64, 0), attacks & (squareBit(49) | squareBit(56) | squareBit(7)));
}

test "bishopAttacks with a fully occupied board only reaches adjacent diagonals" {
    const occupancy: u64 = ~@as(u64, 0);

    try std.testing.expectEqual(
        squareBit(35) | squareBit(37) | squareBit(19) | squareBit(21), // d5, f5, d3, f3
        bishopAttacks(28, occupancy),
    );
    try std.testing.expectEqual(squareBit(9), bishopAttacks(0, occupancy)); // b2 only
    try std.testing.expectEqual(squareBit(54), bishopAttacks(63, occupancy)); // g7 only
}

test "queenAttacks combines rook and bishop rays" {
    const from: brd.Square = 28; // e4
    const empty_expected = rookAttacks(from, 0) | bishopAttacks(from, 0);

    try std.testing.expectEqual(empty_expected, queenAttacks(from, 0));
    try std.testing.expectEqual(@as(u7, 27), @popCount(empty_expected));

    // Queen on e4 with blockers on e6, c6, c4, and g2.
    const occupancy = squareBit(44) | squareBit(42) | squareBit(26) | squareBit(14);
    const expected = squareBit(36) | squareBit(44) | // e5, e6
        squareBit(20) | squareBit(12) | squareBit(4) | // e3-e1
        squareBit(29) | squareBit(30) | squareBit(31) | // f4-h4
        squareBit(27) | squareBit(26) | // d4, c4
        squareBit(37) | squareBit(46) | squareBit(55) | // f5-h7
        squareBit(35) | squareBit(42) | // d5, c6
        squareBit(21) | squareBit(14) | // f3, g2
        squareBit(19) | squareBit(10) | squareBit(1); // d3-b1

    try std.testing.expectEqual(expected, queenAttacks(from, occupancy));
    try std.testing.expectEqual(@as(u7, 20), @popCount(expected));
    try std.testing.expectEqual(expected, rookAttacks(from, occupancy) | bishopAttacks(from, occupancy));
}

test "rook, bishop, and queen attacks match naive walks for every square and random occupancies" {
    var prng = std.Random.DefaultPrng.init(0xD1B5_4A32_D192_ED03);
    const random = prng.random();

    var iteration: usize = 0;
    while (iteration < 3000) : (iteration += 1) {
        const occupancy: u64 = if (iteration == 0) 0 else random.int(u64);

        for (0..64) |sq| {
            const from: brd.Square = @intCast(sq);
            try std.testing.expectEqual(
                naiveRookAttacks(from, occupancy),
                rookAttacks(from, occupancy),
            );
            try std.testing.expectEqual(
                naiveBishopAttacks(from, occupancy),
                bishopAttacks(from, occupancy),
            );
            try std.testing.expectEqual(
                naiveQueenAttacks(from, occupancy),
                queenAttacks(from, occupancy),
            );
        }
    }
}
