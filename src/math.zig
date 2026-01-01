/// Matrix type
pub const Mat = [4]F32x4;
pub const F32x4 = @Vector(4, f32);

/// 2D orthographic projection matrix
pub fn ortho2d(left: f32, right: f32, bottom: f32, top: f32) Mat {
    const w = right - left;
    const h = top - bottom;
    return .{
        .{ 2 / w, 0, 0, 0 },
        .{ 0, 2 / h, 0, 0 },
        .{ 0.0, 0.0, -1.0, 0.0 },
        .{ -(right + left) / w, -(top + bottom) / h, 0.0, 1.0 },
    };
}

const std = @import("std");
const testing = std.testing;

test "ortho2d basic symmetric projection" {
    const mat = ortho2d(-1.0, 1.0, -1.0, 1.0);
    
    // Check matrix dimensions (Mat is [4]F32x4, so 4 rows)
    try testing.expectEqual(@as(usize, 4), mat.len);
    
    // For symmetric bounds [-1, 1], scaling should be 1.0
    try testing.expectApproxEqAbs(@as(f32, 1.0), mat[0][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), mat[1][1], 0.0001);
    
    // Translation should be 0 for symmetric bounds
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[3][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[3][1], 0.0001);
    
    // Z component should be -1
    try testing.expectApproxEqAbs(@as(f32, -1.0), mat[2][2], 0.0001);
    
    // Bottom-right should be 1.0
    try testing.expectApproxEqAbs(@as(f32, 1.0), mat[3][3], 0.0001);
}

test "ortho2d square projection" {
    const mat = ortho2d(0.0, 100.0, 0.0, 100.0);
    
    // For square 100x100, scaling should be 0.02 (2/100)
    try testing.expectApproxEqAbs(@as(f32, 0.02), mat[0][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.02), mat[1][1], 0.0001);
    
    // Translation should be -1.0 (-(100+0)/100)
    try testing.expectApproxEqAbs(@as(f32, -1.0), mat[3][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, -1.0), mat[3][1], 0.0001);
}

test "ortho2d asymmetric dimensions" {
    const mat = ortho2d(0.0, 800.0, 0.0, 600.0);
    
    // Width = 800, Height = 600
    try testing.expectApproxEqAbs(@as(f32, 0.0025), mat[0][0], 0.0001); // 2/800
    try testing.expectApproxEqAbs(@as(f32, 0.003333), mat[1][1], 0.0001); // 2/600
    
    // Translation
    try testing.expectApproxEqAbs(@as(f32, -1.0), mat[3][0], 0.0001); // -(800+0)/800
    try testing.expectApproxEqAbs(@as(f32, -1.0), mat[3][1], 0.0001); // -(600+0)/600
}

test "ortho2d negative bounds" {
    const mat = ortho2d(-100.0, -50.0, -50.0, 50.0);
    
    const w = -50.0 - (-100.0); // 50
    const h = 50.0 - (-50.0); // 100
    
    // Check scaling
    try testing.expectApproxEqAbs(2.0 / w, mat[0][0], 0.0001);
    try testing.expectApproxEqAbs(2.0 / h, mat[1][1], 0.0001);
    
    // Check translation: -(-50 + -100)/50 = 150/50 = 3
    try testing.expectApproxEqAbs(@as(f32, 3.0), mat[3][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[3][1], 0.0001); // -(50 + -50)/100 = 0
}

test "ortho2d non-zero origin" {
    const mat = ortho2d(10.0, 110.0, 20.0, 120.0);
    
    // Both width and height are 100
    try testing.expectApproxEqAbs(@as(f32, 0.02), mat[0][0], 0.0001); // 2/100
    try testing.expectApproxEqAbs(@as(f32, 0.02), mat[1][1], 0.0001); // 2/100
    
    // Translation: -(110+10)/100 = -1.2
    try testing.expectApproxEqAbs(@as(f32, -1.2), mat[3][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, -1.4), mat[3][1], 0.0001); // -(120+20)/100 = -1.4
}

test "ortho2d zero off-diagonal elements" {
    const mat = ortho2d(0.0, 10.0, 0.0, 10.0);
    
    // Check all off-diagonal elements are zero (except last column)
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[0][1], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[0][2], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[0][3], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[1][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[1][2], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[1][3], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[2][0], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[2][1], 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), mat[2][3], 0.0001);
}

test "ortho2d matrix structure validation" {
    const mat = ortho2d(0.0, 1.0, 0.0, 1.0);
    
    // Verify 4x4 matrix structure (4 rows, each with 4 columns via vector)
    try testing.expectEqual(@as(usize, 4), mat.len);
    
    // Access elements to verify vector structure
    _ = mat[0][0]; // Should work if it's a vector
    _ = mat[1][1];
    _ = mat[2][2];
    _ = mat[3][3];
    
    // Verify last row has translation components
    try testing.expect(mat[3][0] != 0.0);
    try testing.expect(mat[3][1] != 0.0);
    
    // Verify bottom-right element is 1.0
    try testing.expectApproxEqAbs(@as(f32, 1.0), mat[3][3], 0.0001);
}

test "ortho2d scaling components" {
    const left: f32 = -50.0;
    const right: f32 = 150.0;
    const bottom: f32 = -75.0;
    const top: f32 = 225.0;
    
    const mat = ortho2d(left, right, bottom, top);
    
    const expected_w = right - left; // 200
    const expected_h = top - bottom; // 300
    
    // Verify scaling components
    try testing.expectApproxEqAbs(2.0 / expected_w, mat[0][0], 0.0001);
    try testing.expectApproxEqAbs(2.0 / expected_h, mat[1][1], 0.0001);
}

test "ortho2d translation components" {
    const left: f32 = 25.0;
    const right: f32 = 75.0;
    const bottom: f32 = 10.0;
    const top: f32 = 60.0;
    
    const mat = ortho2d(left, right, bottom, top);
    
    const expected_w = right - left; // 50
    const expected_h = top - bottom; // 50
    
    // Verify translation components
    try testing.expectApproxEqAbs(-(right + left) / expected_w, mat[3][0], 0.0001);
    try testing.expectApproxEqAbs(-(top + bottom) / expected_h, mat[3][1], 0.0001);
}

test "ortho2d very small dimensions" {
    const mat = ortho2d(0.0, 0.001, 0.0, 0.001);
    
    // Should handle small values without division by zero
    try testing.expect(mat[0][0] > 0.0); // 2/0.001 = 2000
    try testing.expect(mat[1][1] > 0.0); // 2/0.001 = 2000
}

test "ortho2d large dimensions" {
    const mat = ortho2d(-1000000.0, 1000000.0, -1000000.0, 1000000.0);
    
    // Should handle large values
    try testing.expectApproxEqAbs(@as(f32, 0.000001), mat[0][0], 0.0000001); // 2/2000000
    try testing.expectApproxEqAbs(@as(f32, 0.000001), mat[1][1], 0.0000001); // 2/2000000
}
