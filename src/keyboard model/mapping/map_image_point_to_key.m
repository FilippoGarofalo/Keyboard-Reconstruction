function keyIndices = map_image_point_to_key(pointsPx, H_image_to_plane, virtualKeyboard)
%MAP_IMAGE_POINT_TO_KEY Map original-image pixels to white-key indices.
%
%   keyIndices = MAP_IMAGE_POINT_TO_KEY(pointsPx, H_image_to_plane, ...
%       virtualKeyboard) projects pixel coordinates from the original
%   (un-rectified) frame onto the keyboard plane via the supplied
%   homography, then assigns each projected point to a white-key index.
%
%   This is the entry point for fingertip-to-key mapping: feed it the
%   output of getFingers (Nx2 [x, y] in original-image pixels) together
%   with calibration.H_image_to_plane and calibration.virtualKeyboard.
%
%   INPUT
%     pointsPx          Nx2 double — [x, y] in original-image pixels
%     H_image_to_plane  3x3 double — image -> plane (mm) homography
%     virtualKeyboard   struct from build_virtual_white_keyboard
%
%   OUTPUT
%     keyIndices        Nx1 uint32 — key index in 1..numKeys, or 0 if outside

    if isempty(pointsPx)
        keyIndices = zeros(0, 1, 'uint32');
        return;
    end

    validateattributes(pointsPx, {'numeric'}, {'2d', 'ncols', 2, 'real'});
    validateattributes(H_image_to_plane, {'numeric'}, {'size', [3, 3], 'real', 'finite'});
    validateattributes(virtualKeyboard, {'struct'}, {'scalar'});

    finiteMask = all(isfinite(pointsPx), 2);
    keyIndices = zeros(size(pointsPx, 1), 1, 'uint32');

    if ~any(finiteMask)
        return;
    end

    pointsMm = apply_homography(H_image_to_plane, pointsPx(finiteMask, :));
    keyIndices(finiteMask) = map_point_to_key(pointsMm, virtualKeyboard);
end
