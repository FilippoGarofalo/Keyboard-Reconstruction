function cartesianPoints = normalize_homogeneous(homogeneousPoints)
%NORMALIZE_HOMOGENEOUS Convert homogeneous points to Cartesian coordinates.

validateattributes(homogeneousPoints, {'numeric'}, {'2d', 'real', 'finite'});

scale = homogeneousPoints(:, end);
if any(abs(scale) < eps)
    error('Cannot normalize points with last homogeneous coordinate equal to zero.');
end

cartesianPoints = homogeneousPoints(:, 1:end-1) ./ scale;
end
