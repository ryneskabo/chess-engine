// TODO: Add knight attack array, account for edges
/// each spot in array holds bitboards with squares flipped on that the knight on [square] attacks.
pub const knight_attacks: [64]u64 = blk: {
    var a: [64]u64 = @splat(0);
    
    break :blk a;
};

// TODO: Add king attack array, account for edges
/// each spot in array holds bitboards with squares flipped on that the king on [square] attacks.
pub const king_attacks: [64]u64 = blk: {
    var a: [64]u64 = @splat(0);
    
    break :blk a;
};
