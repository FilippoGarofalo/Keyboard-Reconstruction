function [roiMask, roiBoundingBoxPx] = build_keyboard_roi_mask(imageSizePx, roiPolygonPx)
%BUILD_KEYBOARD_ROI_MASK Rasterize the white-key quadrilateral on the image.
%   imageSizePx is [height, width]. roiPolygonPx must be a 4x2 polygon in
%   image pixel coordinates.

validateattributes(imageSizePx, {'numeric'}, {'numel', 2, 'integer', 'positive'});
validateattributes(roiPolygonPx, {'numeric'}, {'size', [4, 2], 'real', 'finite'});

imageHeight = imageSizePx(1);
imageWidth = imageSizePx(2);

[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
roiMask = inpolygon(xGrid, yGrid, roiPolygonPx(:, 1), roiPolygonPx(:, 2));

xMin = max(1, floor(min(roiPolygonPx(:, 1))));
xMax = min(imageWidth, ceil(max(roiPolygonPx(:, 1))));
yMin = max(1, floor(min(roiPolygonPx(:, 2))));
yMax = min(imageHeight, ceil(max(roiPolygonPx(:, 2))));

roiBoundingBoxPx = [xMin, yMin, xMax - xMin + 1, yMax - yMin + 1];
end
