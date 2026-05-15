function virtualKeyboard = build_virtual_keyboard(calibration, varargin)
%BUILD_VIRTUAL_KEYBOARD Build the full virtual keyboard (white + black keys).
%   virtualKeyboard = BUILD_VIRTUAL_KEYBOARD(calibration) returns the
%   rectified keyboard model including both white and black keys, derived
%   analytically from the calibration and the standard piano geometry.
%
%   virtualKeyboard = BUILD_VIRTUAL_KEYBOARD(..., 'StartNote', 'A0', ...
%       'IncludeBlackKeys', true) accepts the following name-value pairs:
%
%   'StartNote'         char/string — leftmost white note of the keyboard.
%                       Default: keyboard_constants().defaultStartNote ('A0').
%   'IncludeBlackKeys'  logical — if false, returns only the white-key
%                       model (equivalent to build_virtual_white_keyboard).
%                       Default: true.
%
%   The returned struct preserves all fields of build_virtual_white_keyboard
%   for backward compatibility, and adds:
%     whiteKeys      alias of .keys (the white-key array)
%     blackKeys      Mx1 struct array of black keys (empty if disabled)
%     allKeys        unified array [whiteKeys; blackKeys] for iteration
%     numBlackKeys   number of black keys
%     startNote      the start-note used to align the octave pattern
%     labelImage     uint16 label image with black keys painted over whites
%                    in the upper region (pixel value 0 = outside keyboard)

    parser = inputParser;
    parser.addParameter('StartNote', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('IncludeBlackKeys', true, @(x) islogical(x) || isnumeric(x));
    parser.parse(varargin{:});

    constants = keyboard_constants();
    startNote = parser.Results.StartNote;
    if isempty(startNote)
        if isfield(calibration, 'firstVisibleNote') && ...
                ~isempty(calibration.firstVisibleNote)
            startNote = calibration.firstVisibleNote;
        else
            startNote = constants.defaultStartNote;
        end
    end
    includeBlack = logical(parser.Results.IncludeBlackKeys);

    whiteVK = build_virtual_white_keyboard(calibration);

    % Tag the existing white keys with a type field, in place, so that the
    % unified .allKeys array is homogeneous.
    for i = 1:numel(whiteVK.keys)
        whiteVK.keys(i).type = 'white';
    end

    virtualKeyboard = whiteVK;
    virtualKeyboard.whiteKeys = whiteVK.keys;
    virtualKeyboard.startNote = startNote;

    if ~includeBlack
        virtualKeyboard.blackKeys = repmat(struct(), 0, 1);
        virtualKeyboard.numBlackKeys = 0;
        virtualKeyboard.allKeys = whiteVK.keys;
        return;
    end

    blackKeys = build_virtual_black_keys(whiteVK, startNote);
    virtualKeyboard.blackKeys = blackKeys;
    virtualKeyboard.numBlackKeys = numel(blackKeys);

    % Build a unified array. Use a common field set to allow concatenation
    % (white and black structs already share the relevant geometric fields).
    virtualKeyboard.allKeys = merge_key_arrays(whiteVK.keys, blackKeys);

    % Paint black keys onto the label image (only in their vertical band).
    virtualKeyboard.labelImage = paint_blacks_on_label( ...
        whiteVK.labelImage, blackKeys);
end


function merged = merge_key_arrays(whiteKeys, blackKeys)
% Concatenate white and black key structs by aligning fields.
    commonFields = intersect(fieldnames(whiteKeys), fieldnames(blackKeys));
    extraWhite = setdiff(fieldnames(whiteKeys), commonFields);
    extraBlack = setdiff(fieldnames(blackKeys), commonFields);

    % Add missing fields on each side as empty so concatenation works.
    for k = 1:numel(extraWhite)
        for b = 1:numel(blackKeys)
            blackKeys(b).(extraWhite{k}) = [];
        end
    end
    for k = 1:numel(extraBlack)
        for w = 1:numel(whiteKeys)
            whiteKeys(w).(extraBlack{k}) = [];
        end
    end

    merged = [whiteKeys(:); blackKeys(:)];
end


function labelImage = paint_blacks_on_label(whiteLabelImage, blackKeys)
% Overwrite the upper portion of the label image with black-key indices.
    labelImage = whiteLabelImage;
    for b = 1:numel(blackKeys)
        bb = blackKeys(b).boundingBoxPx;
        if isempty(bb), continue; end
        x0 = bb(1);  y0 = bb(2);
        x1 = bb(1) + bb(3) - 1;
        y1 = bb(2) + bb(4) - 1;
        x0 = max(1, x0);  y0 = max(1, y0);
        x1 = min(size(labelImage, 2), x1);
        y1 = min(size(labelImage, 1), y1);
        if x1 >= x0 && y1 >= y0
            labelImage(y0:y1, x0:x1) = uint16(blackKeys(b).index);
        end
    end
end
