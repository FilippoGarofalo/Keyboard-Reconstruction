function orderedPoints = order_quad_points(points)
%ORDER_QUAD_POINTS Order four image points as TL, TR, BR, BL.

validateattributes(points, {'numeric'}, {'size', [4, 2], 'real', 'finite'});

sumCoords = points(:, 1) + points(:, 2);
diffCoords = points(:, 2) - points(:, 1);

[~, idxTL] = min(sumCoords);
[~, idxBR] = max(sumCoords);
[~, idxTR] = min(diffCoords);
[~, idxBL] = max(diffCoords);

orderedPoints = [
    points(idxTL, :);
    points(idxTR, :);
    points(idxBR, :);
    points(idxBL, :)
];

if numel(unique([idxTL, idxTR, idxBR, idxBL])) < 4
    error('Point ordering failed. Please click the four corners more distinctly.');
end
end
