function virtualKeyboard = build_virtual_white_keyboard(calibration)
%BUILD_VIRTUAL_WHITE_KEYBOARD Build white-key regions on the rectified plane.
%   virtualKeyboard = build_virtual_white_keyboard(calibration) returns a
%   rectified keyboard model where each visible white key is represented as
%   a regular region in both metric coordinates (mm) and rectified image
%   coordinates (px).

requiredFields = {
    'numWhiteKeys'
    'whiteKeyWidthMm'
    'keyboardHeightMm'
    'pixelsPerMm'
    'rectifiedImageSizePx'
};

for k = 1:numel(requiredFields)
    if ~isfield(calibration, requiredFields{k})
        error('Missing calibration field: %s', requiredFields{k});
    end
end

numKeys = calibration.numWhiteKeys;
whiteKeyWidthMm = calibration.whiteKeyWidthMm;
keyboardHeightMm = calibration.keyboardHeightMm;
pixelsPerMm = calibration.pixelsPerMm;
rectifiedImageSizePx = calibration.rectifiedImageSizePx;

validateattributes(numKeys, {'numeric'}, {'scalar', 'integer', 'positive'});
validateattributes(whiteKeyWidthMm, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(keyboardHeightMm, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(pixelsPerMm, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(rectifiedImageSizePx, {'numeric'}, {'numel', 2, 'integer', 'positive'});

imageHeightPx = rectifiedImageSizePx(1);
imageWidthPx = rectifiedImageSizePx(2);

xEdgesMm = (0:numKeys) * whiteKeyWidthMm;
xEdgesPx = round(linspace(0, imageWidthPx, numKeys + 1));
labelImage = zeros(imageHeightPx, imageWidthPx, 'uint16');

keyTemplate = struct( ...
    'index', [], ...
    'name', '', ...
    'xRangeMm', [], ...
    'yRangeMm', [], ...
    'polygonMm', [], ...
    'xRangePx', [], ...
    'yRangePx', [], ...
    'polygonPx', [], ...
    'boundingBoxPx', [], ...
    'centerMm', [], ...
    'centerPx', []);
keys = repmat(keyTemplate, numKeys, 1);

for keyIdx = 1:numKeys
    xStartMm = xEdgesMm(keyIdx);
    xEndMm = xEdgesMm(keyIdx + 1);

    xStartPx = xEdgesPx(keyIdx) + 1;
    xEndPx = xEdgesPx(keyIdx + 1);

    xStartPx = min(max(xStartPx, 1), imageWidthPx);
    xEndPx = min(max(xEndPx, xStartPx), imageWidthPx);

    labelImage(:, xStartPx:xEndPx) = uint16(keyIdx);

    keys(keyIdx).index = keyIdx;
    keys(keyIdx).name = sprintf('W%d', keyIdx);
    keys(keyIdx).xRangeMm = [xStartMm, xEndMm];
    keys(keyIdx).yRangeMm = [0, keyboardHeightMm];
    keys(keyIdx).polygonMm = [
        xStartMm, 0;
        xEndMm,   0;
        xEndMm,   keyboardHeightMm;
        xStartMm, keyboardHeightMm
    ];
    keys(keyIdx).xRangePx = [xStartPx, xEndPx];
    keys(keyIdx).yRangePx = [1, imageHeightPx];
    keys(keyIdx).polygonPx = [
        xStartPx, 1;
        xEndPx,   1;
        xEndPx,   imageHeightPx;
        xStartPx, imageHeightPx
    ];
    keys(keyIdx).boundingBoxPx = [ ...
        xStartPx, ...
        1, ...
        xEndPx - xStartPx + 1, ...
        imageHeightPx];
    keys(keyIdx).centerMm = [(xStartMm + xEndMm) / 2, keyboardHeightMm / 2];
    keys(keyIdx).centerPx = [(xStartPx + xEndPx) / 2, (imageHeightPx + 1) / 2];
end

virtualKeyboard = struct();
virtualKeyboard.numKeys = numKeys;
virtualKeyboard.whiteKeyWidthMm = whiteKeyWidthMm;
virtualKeyboard.keyboardHeightMm = keyboardHeightMm;
virtualKeyboard.keyboardWidthMm = numKeys * whiteKeyWidthMm;
virtualKeyboard.pixelsPerMm = pixelsPerMm;
virtualKeyboard.rectifiedImageSizePx = rectifiedImageSizePx;
virtualKeyboard.xEdgesMm = xEdgesMm;
virtualKeyboard.xEdgesPx = xEdgesPx;
virtualKeyboard.keys = keys;
virtualKeyboard.labelImage = labelImage;
end
