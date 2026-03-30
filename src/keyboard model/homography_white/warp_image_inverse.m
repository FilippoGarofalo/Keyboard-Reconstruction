function rectifiedImage = warp_image_inverse(I, H, planeSizeMm, pixelsPerMm)
%WARP_IMAGE_INVERSE Rectify an image by inverse warping with a homography.
%   H must map plane coordinates in mm to image coordinates in pixels.

validateattributes(H, {'numeric'}, {'size', [3, 3], 'real', 'finite'});
validateattributes(planeSizeMm, {'numeric'}, {'numel', 2, 'real', 'finite', 'positive'});
validateattributes(pixelsPerMm, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});

heightMm = planeSizeMm(1);
widthMm = planeSizeMm(2);

outHeight = max(1, round(heightMm * pixelsPerMm));
outWidth = max(1, round(widthMm * pixelsPerMm));

[xGridPx, yGridPx] = meshgrid(0:(outWidth - 1), 0:(outHeight - 1));
planePoints = [xGridPx(:) / pixelsPerMm, yGridPx(:) / pixelsPerMm];
imagePoints = apply_homography(H, planePoints);

u = reshape(imagePoints(:, 1), outHeight, outWidth);
v = reshape(imagePoints(:, 2), outHeight, outWidth);

numChannels = size(I, 3);
sourceImage = double(I);
rectifiedImage = zeros(outHeight, outWidth, numChannels);

for channel = 1:numChannels
    rectifiedImage(:, :, channel) = interp2( ...
        sourceImage(:, :, channel), ...
        u, ...
        v, ...
        'linear', ...
        0);
end

if isinteger(I)
    rectifiedImage = cast(rectifiedImage, class(I));
end
end
