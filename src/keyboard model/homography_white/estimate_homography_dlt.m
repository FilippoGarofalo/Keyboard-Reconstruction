function [H, A] = estimate_homography_dlt(planePoints, imagePoints)
%ESTIMATE_HOMOGRAPHY_DLT Estimate a plane-to-image homography with DLT.
%   H maps plane points x = [X, Y, 1]^T to image points u = [x, y, 1]^T:
%   u ~ H x

validateattributes(planePoints, {'numeric'}, {'ncols', 2, 'real', 'finite'});
validateattributes(imagePoints, {'numeric'}, {'ncols', 2, 'real', 'finite'});

numPoints = size(planePoints, 1);
if numPoints ~= size(imagePoints, 1)
    error('planePoints and imagePoints must have the same number of rows.');
end
if numPoints < 4
    error('At least four point correspondences are required.');
end

A = zeros(2 * numPoints, 9);
for i = 1:numPoints
    X = planePoints(i, 1);
    Y = planePoints(i, 2);
    x = imagePoints(i, 1);
    y = imagePoints(i, 2);

    A(2 * i - 1, :) = [-X, -Y, -1,  0,  0,  0, x * X, x * Y, x];
    A(2 * i,     :) = [ 0,  0,  0, -X, -Y, -1, y * X, y * Y, y];
end

[~, ~, V] = svd(A);
h = V(:, end);
H = reshape(h, 3, 3)';

if abs(H(3, 3)) > eps
    H = H / H(3, 3);
end
end
