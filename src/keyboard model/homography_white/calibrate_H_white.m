function calibration = calibrate_H_white(inputImage, numWhiteKeys, varargin)
%CALIBRATE_H_WHITE Estimate the white-key plane-to-image homography.
%   The white keyboard is modeled as a planar rectangle and the homography
%   H_white is estimated with DLT + SVD from four manually selected corners.
%
%   calibration = calibrate_H_white(inputImage, numWhiteKeys)
%   calibration = calibrate_H_white(..., 'Name', value)
%
%   Required inputs
%   inputImage     - image matrix or path to an image file
%   numWhiteKeys   - number of visible white keys in the selected region
%
%   Name-value parameters
%   'WhiteKeyWidthMm'         default 23.5
%   'VisibleWhiteKeyHeightMm' default 150
%   'PixelsPerMm'             default 4
%   'ImagePointsPx'           default []
%   'OutputMatFile'           default 'H_white_calibration.mat'
%
%   Output fields
%   calibration.H_white           plane-to-image homography
%   calibration.H_image_to_plane  image-to-plane homography
%   calibration.planePointsMm     4x2 metric corners on the keyboard plane
%   calibration.imagePointsPx     4x2 selected image corners
%   calibration.roiMask           keyboard ROI mask on the source image
%   calibration.reprojection      reprojection diagnostics
%   calibration.rectifiedImage    rectified image of the white-key plane

parser = inputParser;
parser.addParameter('WhiteKeyWidthMm', 23.5, @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('VisibleWhiteKeyHeightMm', 150, @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('PixelsPerMm', 4, @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter('ImagePointsPx', [], @(x) isempty(x) || (isnumeric(x) && isequal(size(x), [4, 2])));
parser.addParameter('OutputMatFile', 'H_white_calibration.mat', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
params = parser.Results;

I = read_input_image(inputImage);
imageSizePx = [size(I, 1), size(I, 2)];

keyboardWidthMm = numWhiteKeys * params.WhiteKeyWidthMm;
keyboardHeightMm = params.VisibleWhiteKeyHeightMm;
planePointsMm = [
    0,               0;
    keyboardWidthMm, 0;
    keyboardWidthMm, keyboardHeightMm;
    0,               keyboardHeightMm
];

if isempty(params.ImagePointsPx)
    rawImagePointsPx = select_white_keyboard_corners(I);
else
    rawImagePointsPx = params.ImagePointsPx;
end
imagePointsPx = order_quad_points(rawImagePointsPx);

[H_white, A] = estimate_homography_dlt(planePointsMm, imagePointsPx);
H_image_to_plane = normalize_homography_matrix(inv(H_white));
reprojection = compute_reprojection_error(H_white, planePointsMm, imagePointsPx);

[roiMask, roiBoundingBoxPx] = build_keyboard_roi_mask(imageSizePx, imagePointsPx);

rectifiedImage = warp_image_inverse( ...
    I, ...
    H_white, ...
    [keyboardHeightMm, keyboardWidthMm], ...
    params.PixelsPerMm);

calibration = struct();
calibration.H_white = H_white;
calibration.H_image_to_plane = H_image_to_plane;
calibration.A = A;
calibration.planePointsMm = planePointsMm;
calibration.imagePointsPx = imagePointsPx;
calibration.numWhiteKeys = numWhiteKeys;
calibration.whiteKeyWidthMm = params.WhiteKeyWidthMm;
calibration.visibleWhiteKeyHeightMm = params.VisibleWhiteKeyHeightMm;
calibration.keyboardWidthMm = keyboardWidthMm;
calibration.keyboardHeightMm = keyboardHeightMm;
calibration.imageSizePx = imageSizePx;
calibration.roiPolygonPx = imagePointsPx;
calibration.roiMask = roiMask;
calibration.roiBoundingBoxPx = roiBoundingBoxPx;
calibration.pixelsPerMm = params.PixelsPerMm;
calibration.reprojection = reprojection;
calibration.rectifiedImage = rectifiedImage;
calibration.rectifiedImageSizePx = [size(rectifiedImage, 1), size(rectifiedImage, 2)];
calibration.source = build_source_metadata(inputImage, imageSizePx);
calibration.transforms = struct( ...
    'planeToImage', H_white, ...
    'imageToPlane', H_image_to_plane);
calibration.plane = struct( ...
    'cornersMm', planePointsMm, ...
    'widthMm', keyboardWidthMm, ...
    'heightMm', keyboardHeightMm);
calibration.image = struct( ...
    'cornersPx', imagePointsPx, ...
    'sizePx', imageSizePx, ...
    'roiMask', roiMask, ...
    'roiBoundingBoxPx', roiBoundingBoxPx);
calibration.rectified = struct( ...
    'image', rectifiedImage, ...
    'sizePx', calibration.rectifiedImageSizePx, ...
    'pixelsPerMm', params.PixelsPerMm);

if ~isempty(params.OutputMatFile)
    save(params.OutputMatFile, 'calibration');
end

show_calibration_summary(I, imagePointsPx, rectifiedImage);
fprintf('Mean reprojection error: %.4f px\n', reprojection.meanPixels);
fprintf('Max reprojection error:  %.4f px\n', reprojection.maxPixels);

end

function source = build_source_metadata(inputImage, imageSizePx)
if ischar(inputImage) || isstring(inputImage)
    source = struct( ...
        'type', 'image_file', ...
        'path', char(inputImage), ...
        'imageSizePx', imageSizePx);
else
    source = struct( ...
        'type', 'image_matrix', ...
        'path', '', ...
        'imageSizePx', imageSizePx);
end
end

function H = normalize_homography_matrix(H)
scale = H(3, 3);

if abs(scale) > eps
    H = H / scale;
end
end

function I = read_input_image(inputImage)
if ischar(inputImage) || isstring(inputImage)
    I = imread(inputImage);
else
    I = inputImage;
end
end

function imagePointsPx = select_white_keyboard_corners(I)
figure('Name', 'H\_white corner selection');
show_image(I);
title({
    'Select the four corners of the white-key planar region'
    'Suggested order: top-left, top-right, bottom-right, bottom-left'
});

[x, y] = ginput(4);
imagePointsPx = [x, y];
close(gcf);
end

function show_calibration_summary(I, imagePointsPx, rectifiedImage)
figure('Name', 'H\_white calibration result');

subplot(1, 2, 1);
show_image(I);
hold on;
plot(imagePointsPx([1:4, 1], 1), imagePointsPx([1:4, 1], 2), 'g-', 'LineWidth', 2);
plot(imagePointsPx(:, 1), imagePointsPx(:, 2), 'ro', 'MarkerFaceColor', 'r');
title('Selected white-key plane');
hold off;

subplot(1, 2, 2);
show_image(rectifiedImage);
title('Rectified white-key plane');
end

function show_image(I)
if ndims(I) == 2
    imagesc(I);
    colormap gray;
else
    image(I);
end
axis image;
set(gca, 'YDir', 'reverse');
end
