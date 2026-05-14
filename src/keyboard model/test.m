repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'homography_white'));
addpath(fullfile(repoRoot, 'virtual_keyboard'));

videoPath = fullfile(repoRoot, '..', '..', 'assets', 'Video.mp4');
framePath = fullfile(repoRoot, '..', '..', 'assets', 'frame0.png');
outputMatFile = fullfile(repoRoot, '..', 'H_white_calibration.mat');
numWhiteKeys = 21;

calibration = calibrate_H_white_from_video(videoPath, numWhiteKeys, ...
    'TimeSeconds', 2.0, ...
    'AutoSkipDarkFrames', true, ...
    'DarkFrameThreshold', 5, ...
    'MaxAutoSkipFrames', 300, ...
    'SaveFramePath', framePath, ...
    'WhiteKeyWidthMm', 23.5, ...
    'VisibleWhiteKeyHeightMm', 150, ...
    'PixelsPerMm', 4, ...
    'OutputMatFile', outputMatFile);

virtualKeyboard = build_virtual_white_keyboard(calibration);
calibration.virtualKeyboard = virtualKeyboard;

if ~isempty(outputMatFile)
    save(outputMatFile, 'calibration');
end

frame = imread(framePath);

figure('Name', 'Keyboard ROI Mask');
imshow(calibration.roiMask);
title('Keyboard ROI Mask');

figure('Name', 'Keyboard ROI Overlay');
imshow(frame);
hold on;
contour(calibration.roiMask, [0.5, 0.5], 'g', 'LineWidth', 2);
plot(calibration.imagePointsPx([1:4, 1], 1), calibration.imagePointsPx([1:4, 1], 2), ...
    'y-', 'LineWidth', 2);
title('Keyboard ROI Overlay');
hold off;

figure('Name', 'Rectified White-Key Plane');
imshow(calibration.rectifiedImage);
title('Rectified White-Key Plane');

figure('Name', 'Virtual White Keyboard');
imshow(calibration.rectifiedImage);
hold on;

for keyIdx = 1:virtualKeyboard.numKeys
    keyPolygon = virtualKeyboard.keys(keyIdx).polygonPx;
    plot(keyPolygon([1:4, 1], 1), keyPolygon([1:4, 1], 2), 'g-', 'LineWidth', 1);
    text(virtualKeyboard.keys(keyIdx).centerPx(1), 20, sprintf('%d', keyIdx), ...
        'Color', 'y', 'FontSize', 10, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

title(sprintf('Virtual White Keyboard (%d keys)', numWhiteKeys));
hold off;
