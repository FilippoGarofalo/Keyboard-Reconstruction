function synthetic_test_H_white()
%SYNTHETIC_TEST_H_WHITE Minimal DLT sanity check with exact correspondences.

planePoints = [
    0,   0;
    300, 0;
    300, 120;
    0,   120
];

H_gt = [
    2.0,  0.15, 120;
    0.05, 1.8,   80;
    0.001, 0.0005, 1
];

imagePoints = apply_homography(H_gt, planePoints);
[H_est, ~] = estimate_homography_dlt(planePoints, imagePoints);

H_gt = H_gt / H_gt(3, 3);
H_est = H_est / H_est(3, 3);

disp('Ground-truth homography H_gt:');
disp(H_gt);
disp('Estimated homography H_est:');
disp(H_est);
disp('Difference H_est - H_gt:');
disp(H_est - H_gt);
end
