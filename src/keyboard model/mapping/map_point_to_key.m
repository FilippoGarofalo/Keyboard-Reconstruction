function keyIndices = map_point_to_key(pointsMm, virtualKeyboard)
%MAP_POINT_TO_KEY Map metric points on the keyboard plane to key indices.
%
%   keyIndices = MAP_POINT_TO_KEY(pointsMm, virtualKeyboard) returns, for
%   each input point in millimetres, the index of the key it falls into,
%   or 0 if the point lies outside the keyboard region.
%
%   If virtualKeyboard contains black keys (field 'blackKeys' non-empty),
%   the lookup is two-stage:
%     1. If the point lies in the black-key band (y within the black-key
%        length) and inside any black-key x-range, the corresponding black
%        key index is returned.
%     2. Otherwise the white-key index is returned via binning on xEdgesMm.
%
%   This matches the physical reality of a piano: black keys sit on top of
%   the upper portion of the white keys, so a finger in that region is on
%   the black key, not the white one beneath it.
%
%   INPUT
%     pointsMm         Nx2 double — [X, Y] coordinates on the keyboard plane (mm)
%     virtualKeyboard  struct returned by build_virtual_keyboard (or
%                      build_virtual_white_keyboard for whites-only behaviour)
%
%   OUTPUT
%     keyIndices       Nx1 uint32 — key index, or 0 if outside the keyboard

    if isempty(pointsMm)
        keyIndices = zeros(0, 1, 'uint32');
        return;
    end

    validateattributes(pointsMm, {'numeric'}, {'2d', 'ncols', 2, 'real'});
    validateattributes(virtualKeyboard, {'struct'}, {'scalar'});

    xEdgesMm = virtualKeyboard.xEdgesMm;
    keyboardHeightMm = virtualKeyboard.keyboardHeightMm;
    numWhiteKeys = virtualKeyboard.numKeys;

    x = pointsMm(:, 1);
    y = pointsMm(:, 2);

    insideX = x >= xEdgesMm(1) & x <= xEdgesMm(end);
    insideY = y >= 0 & y <= keyboardHeightMm;
    insideKeyboard = insideX & insideY & isfinite(x) & isfinite(y);

    keyIndices = zeros(numel(x), 1, 'uint32');

    % --- STAGE 1: black keys (priority over whites in the upper band) ---
    hasBlacks = isfield(virtualKeyboard, 'blackKeys') && ...
                ~isempty(virtualKeyboard.blackKeys);

    if hasBlacks
        bk = virtualKeyboard.blackKeys;
        % all blacks share the same y-range upper band; take it from the first
        blackBandTopMm    = bk(1).yRangeMm(1);
        blackBandBottomMm = bk(1).yRangeMm(2);

        inBlackBand = insideKeyboard & ...
                      y >= blackBandTopMm & y <= blackBandBottomMm;

        if any(inBlackBand)
            % Build sorted edges for vectorised lookup:
            %   blackEdges = [x0_1 x1_1 x0_2 x1_2 ...] (already sorted left→right)
            blackEdges = zeros(2 * numel(bk), 1);
            blackIdx   = zeros(2 * numel(bk), 1, 'uint32');
            for b = 1:numel(bk)
                blackEdges(2*b - 1) = bk(b).xRangeMm(1);
                blackEdges(2*b)     = bk(b).xRangeMm(2);
                blackIdx(2*b - 1)   = uint32(bk(b).index);
                blackIdx(2*b)       = uint32(bk(b).index);
            end
            % discretize returns bin index i such that
            %   blackEdges(i) <= xq < blackEdges(i+1)
            % Odd bins (1, 3, 5, ...) are inside a black key;
            % even bins are gaps between blacks.
            bins = discretize(x(inBlackBand), blackEdges);
            insideBlack = ~isnan(bins) & mod(bins, 2) == 1;

            blackHit = false(numel(x), 1);
            blackHit(inBlackBand) = insideBlack;
            assignedIdx = blackIdx(bins(insideBlack));

            keyIndices(blackHit) = assignedIdx;
        end
    end

    % --- STAGE 2: white keys (only points not already assigned to a black) ---
    needsWhite = insideKeyboard & keyIndices == 0;
    if any(needsWhite)
        bins = discretize(x(needsWhite), xEdgesMm);
        % points exactly on the right edge get NaN from discretize -> last key
        rightEdgeHit = isnan(bins) & x(needsWhite) == xEdgesMm(end);
        bins(rightEdgeHit) = numWhiteKeys;
        validWhite = ~isnan(bins);

        whiteAssigned = false(numel(x), 1);
        whiteAssigned(needsWhite) = validWhite;
        bins = bins(validWhite);
        keyIndices(whiteAssigned) = uint32(bins);
    end
end
