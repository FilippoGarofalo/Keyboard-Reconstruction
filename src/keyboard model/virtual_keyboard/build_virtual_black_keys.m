function blackKeys = build_virtual_black_keys(whiteVirtualKeyboard, startNote)
%BUILD_VIRTUAL_BLACK_KEYS Derive black-key regions from the white-key model.
%   blackKeys = BUILD_VIRTUAL_BLACK_KEYS(whiteVK, startNote) returns a
%   struct array of black keys whose positions are computed analytically
%   from the white-key grid and the standard piano octave pattern.
%
%   Inside each contiguous group of N blacks (N=2 for C#/D#, N=3 for
%   F#/G#/A#) the keys are positioned so that every white key shows the
%   same visible width below the black band. The required asymmetric
%   offset is derived from whiteKeyWidthMm and blackKeyWidthMm via:
%       gap = whiteW - N * blackW / (N + 1)
%       center_i = leftEdge + i*gap + (i - 0.5)*blackW   for i = 1..N
%   No per-keyboard tuning needed: changing the two dimensions in
%   keyboard_constants.m propagates everywhere.
%
%   INPUT
%     whiteVirtualKeyboard  struct from build_virtual_white_keyboard,
%                           must contain xEdgesMm, xEdgesPx, pixelsPerMm,
%                           keyboardHeightMm, rectifiedImageSizePx.
%     startNote             char/string — leftmost white note of the
%                           keyboard (e.g. 'A0' for an 88-key piano).
%                           Accepts {'A','B','C','D','E','F','G'} with an
%                           optional octave number (ignored, only the
%                           letter matters for pattern alignment).
%
%   OUTPUT
%     blackKeys             Mx1 struct with fields mirroring the white
%                           keys: index, name, xRangeMm, yRangeMm,
%                           polygonMm, polygonPx, boundingBoxPx, centerMm,
%                           centerPx. Index starts at numWhiteKeys+1.

    constants = keyboard_constants();

    requiredFields = {'xEdgesMm', 'xEdgesPx', 'pixelsPerMm', ...
                      'numKeys', 'rectifiedImageSizePx'};
    for k = 1:numel(requiredFields)
        if ~isfield(whiteVirtualKeyboard, requiredFields{k})
            error('Missing field in whiteVirtualKeyboard: %s', requiredFields{k});
        end
    end

    if nargin < 2 || isempty(startNote)
        startNote = constants.defaultStartNote;
    end

    numWhite = whiteVirtualKeyboard.numKeys;
    xEdgesMm = whiteVirtualKeyboard.xEdgesMm;
    pixelsPerMm = whiteVirtualKeyboard.pixelsPerMm;
    imageHeightPx = whiteVirtualKeyboard.rectifiedImageSizePx(1);

    whiteWidthMm  = constants.whiteKeyWidthMm;
    blackWidthMm  = constants.blackKeyWidthMm;
    blackLengthMm = constants.blackKeyLengthMm;
    halfWidthMm   = blackWidthMm / 2;

    % Build a hasBlackAfter vector of length (numWhite - 1):
    % for each white key i, is there a black key immediately to its right?
    startLetter = upper(startNote(1));
    % octavePattern is indexed starting from C; rotate so it starts at
    % the requested letter.
    letters = 'CDEFGAB';
    startIdx = strfind(letters, startLetter);
    if isempty(startIdx)
        error('Invalid start note letter: %s', startLetter);
    end
    rotatedPattern = circshift(constants.octavePattern, -(startIdx - 1));

    % Tile the rotated pattern to cover (numWhite - 1) positions.
    repsNeeded = ceil((numWhite - 1) / 7);
    hasBlackAfter = repmat(rotatedPattern, 1, repsNeeded);
    hasBlackAfter = hasBlackAfter(1:numWhite - 1);

    numBlack = sum(hasBlackAfter);

    keyTemplate = struct( ...
        'index', [], ...
        'name', '', ...
        'type', 'black', ...
        'xRangeMm', [], ...
        'yRangeMm', [], ...
        'polygonMm', [], ...
        'xRangePx', [], ...
        'yRangePx', [], ...
        'polygonPx', [], ...
        'boundingBoxPx', [], ...
        'centerMm', [], ...
        'centerPx', []);
    blackKeys = repmat(keyTemplate, numBlack, 1);

    blackLengthPx = round(blackLengthMm * pixelsPerMm);
    blackLengthPx = min(blackLengthPx, imageHeightPx);

    % --- Pass 1: walk hasBlackAfter, identify groups, compute centers ---
    centersMm = zeros(numBlack, 1);
    bIdx = 0;
    w = 1;
    while w <= numel(hasBlackAfter)
        if ~hasBlackAfter(w)
            w = w + 1;
            continue;
        end
        groupStart = w;
        while w <= numel(hasBlackAfter) && hasBlackAfter(w)
            w = w + 1;
        end
        groupSize = w - groupStart;            % N = 2 or 3
        leftEdgeMm = xEdgesMm(groupStart);     % left edge of first white in group
        gap = whiteWidthMm - groupSize * blackWidthMm / (groupSize + 1);
        for i = 1:groupSize
            bIdx = bIdx + 1;
            centersMm(bIdx) = leftEdgeMm + i*gap + (i - 0.5)*blackWidthMm;
        end
    end

    % --- Pass 2: build struct array from the computed centers ---
    for bIdx = 1:numBlack
        centerXMm = centersMm(bIdx);
        xStartMm = centerXMm - halfWidthMm;
        xEndMm   = centerXMm + halfWidthMm;

        xStartPx = max(1, round(xStartMm * pixelsPerMm) + 1);
        xEndPx   = min(whiteVirtualKeyboard.rectifiedImageSizePx(2), ...
                       round(xEndMm * pixelsPerMm));
        xEndPx   = max(xEndPx, xStartPx);

        blackKeys(bIdx).index    = numWhite + bIdx;
        blackKeys(bIdx).name     = sprintf('B%d', bIdx);
        blackKeys(bIdx).xRangeMm = [xStartMm, xEndMm];
        blackKeys(bIdx).yRangeMm = [0, blackLengthMm];
        blackKeys(bIdx).polygonMm = [
            xStartMm, 0;
            xEndMm,   0;
            xEndMm,   blackLengthMm;
            xStartMm, blackLengthMm
        ];
        blackKeys(bIdx).xRangePx = [xStartPx, xEndPx];
        blackKeys(bIdx).yRangePx = [1, blackLengthPx];
        blackKeys(bIdx).polygonPx = [
            xStartPx, 1;
            xEndPx,   1;
            xEndPx,   blackLengthPx;
            xStartPx, blackLengthPx
        ];
        blackKeys(bIdx).boundingBoxPx = [ ...
            xStartPx, ...
            1, ...
            xEndPx - xStartPx + 1, ...
            blackLengthPx];
        blackKeys(bIdx).centerMm = [centerXMm, blackLengthMm / 2];
        blackKeys(bIdx).centerPx = [(xStartPx + xEndPx) / 2, ...
                                    (1 + blackLengthPx) / 2];
    end
end
