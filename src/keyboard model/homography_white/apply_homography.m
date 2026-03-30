function mappedPoints = apply_homography(H, points)
%APPLY_HOMOGRAPHY Apply a 3x3 homography to Nx2 or Nx3 points.

validateattributes(H, {'numeric'}, {'size', [3, 3], 'real', 'finite'});
validateattributes(points, {'numeric'}, {'2d', 'real', 'finite'});

if size(points, 2) == 2
    homogeneousPoints = [points, ones(size(points, 1), 1)];
elseif size(points, 2) == 3
    homogeneousPoints = points;
else
    error('points must be an Nx2 or Nx3 array.');
end

mappedHomogeneous = (H * homogeneousPoints')';
mappedPoints = normalize_homogeneous(mappedHomogeneous);
end
