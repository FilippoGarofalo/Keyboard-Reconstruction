function constants = keyboard_constants()
%KEYBOARD_CONSTANTS Physical and pattern constants of a standard piano keyboard.
%   constants = KEYBOARD_CONSTANTS() returns a struct with the geometric
%   dimensions of white and black keys (in millimetres) and the pattern of
%   black keys within an octave. These values are the single source of truth
%   for any module that builds the virtual keyboard model.
%
%   FIELDS
%     whiteKeyWidthMm    23.5  — standard white-key width
%     whiteKeyLengthMm   150   — visible (front-to-back) length of a white key
%     blackKeyWidthMm    13.7  — standard black-key width (~7/12 of a white)
%     blackKeyLengthMm   95    — visible length of a black key (shorter than white)
%     octavePattern      1x7 logical — for each white key in an octave starting
%                        from C [C D E F G A B], 1 if a black key sits on its
%                        right edge, 0 otherwise. Pattern: [1 1 0 1 1 1 0].
%     defaultStartNote   'A0'  — leftmost note on a standard 88-key piano
%
%   NOTES
%     - Black-key offsets within a group of 2 or 3 are approximated as
%       centred on the white-white boundary. Real pianos have small (~1-2 mm)
%       asymmetric offsets which are negligible for video-based finger
%       detection.
%     - All lengths refer to the visible top face of the key on the
%       rectified (top-down) plane. Vertical (physical) height of keys is
%       NOT modelled — keys are assumed coplanar.

    constants.whiteKeyWidthMm   = 23.5;
    constants.whiteKeyLengthMm  = 150;
    constants.blackKeyWidthMm   = 13.7;
    constants.blackKeyLengthMm  = 95;
    constants.octavePattern     = logical([1 1 0 1 1 1 0]);
    constants.defaultStartNote  = 'A0';
end
