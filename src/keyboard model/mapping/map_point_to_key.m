function keyIndices = map_point_to_key(pointsMm, virtualKeyboard)
%MAP_POINT_TO_KEY Map metric points on the keyboard plane to white-key indices.
%
%   keyIndices = MAP_POINT_TO_KEY(pointsMm, virtualKeyboard) returns, for
%   each input point in millimetres, the index of the white key it falls
%   into, or 0 if the point lies outside the keyboard region.
%
%   INPUT
%     pointsMm         Nx2 double — [X, Y] coordinates on the keyboard plane (mm)
%     virtualKeyboard  struct returned by build_virtual_white_keyboard
%
%   OUTPUT
%     keyIndices       Nx1 uint32 — key index in 1..numKeys, or 0 if outside

    if isempty(pointsMm)
        keyIndices = zeros(0, 1, 'uint32');
        return;
    end

    validateattributes(pointsMm, {'numeric'}, {'2d', 'ncols', 2, 'real'});
    validateattributes(virtualKeyboard, {'struct'}, {'scalar'});

    xEdgesMm = virtualKeyboard.xEdgesMm;
    keyboardHeightMm = virtualKeyboard.keyboardHeightMm;
    numKeys = virtualKeyboard.numKeys;

    x = pointsMm(:, 1);
    y = pointsMm(:, 2);

    insideX = x >= xEdgesMm(1) & x <= xEdgesMm(end);
    insideY = y >= 0 & y <= keyboardHeightMm;
    inside = insideX & insideY & isfinite(x) & isfinite(y);

    keyIndices = zeros(numel(x), 1, 'uint32');

    if any(inside)
        % discretize: bin = i means xEdgesMm(i) <= x < xEdgesMm(i+1)
        bins = discretize(x(inside), xEdgesMm);
        % points exactly on the right edge get NaN from discretize -> last key
        bins(isnan(bins) & x(inside) == xEdgesMm(end)) = numKeys;
        keyIndices(inside) = uint32(bins);
    end
end
