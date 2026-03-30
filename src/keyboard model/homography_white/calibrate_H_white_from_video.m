function calibration = calibrate_H_white_from_video(videoPath, numWhiteKeys, varargin)
%CALIBRATE_H_WHITE_FROM_VIDEO Extract a frame from a video and calibrate H_white.
%
%   calibration = calibrate_H_white_from_video(videoPath, numWhiteKeys)
%   calibration = calibrate_H_white_from_video(..., 'FrameIndex', 1)
%   calibration = calibrate_H_white_from_video(..., 'TimeSeconds', t)
%
%   Video-specific parameters
%   'FrameIndex'          default 1
%   'TimeSeconds'         default []
%   'SaveFramePath'       default ''
%   'AutoSkipDarkFrames'  default true
%   'DarkFrameThreshold'  default 5
%   'MaxAutoSkipFrames'   default 300
%
%   All the remaining name-value parameters are forwarded to
%   calibrate_H_white, e.g. 'WhiteKeyWidthMm', 'VisibleWhiteKeyHeightMm',
%   'PixelsPerMm', 'OutputMatFile'.

parser = inputParser;
parser.KeepUnmatched = true;
parser.addParameter('FrameIndex', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
parser.addParameter('TimeSeconds', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
parser.addParameter('SaveFramePath', '', @(x) ischar(x) || isstring(x));
parser.addParameter('AutoSkipDarkFrames', true, @(x) islogical(x) || isnumeric(x));
parser.addParameter('DarkFrameThreshold', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parser.addParameter('MaxAutoSkipFrames', 300, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parser.parse(varargin{:});

videoParams = parser.Results;
calibrationParams = unmatched_to_name_value(parser.Unmatched);
outputMatFile = '';

if isfield(parser.Unmatched, 'OutputMatFile')
    outputMatFile = parser.Unmatched.OutputMatFile;
    calibrationParams = remove_name_value_pair(calibrationParams, 'OutputMatFile');
end

[frame, frameInfo] = extract_video_frame( ...
    videoPath, ...
    'FrameIndex', videoParams.FrameIndex, ...
    'TimeSeconds', videoParams.TimeSeconds, ...
    'SaveImagePath', videoParams.SaveFramePath, ...
    'AutoSkipDarkFrames', logical(videoParams.AutoSkipDarkFrames), ...
    'DarkFrameThreshold', videoParams.DarkFrameThreshold, ...
    'MaxAutoSkipFrames', videoParams.MaxAutoSkipFrames);

fprintf('Loaded frame %d at %.3f s from:\n%s\n', ...
    frameInfo.FrameIndex, frameInfo.TimeSeconds, frameInfo.VideoPath);

calibration = calibrate_H_white(frame, numWhiteKeys, calibrationParams{:});
calibration.video = frameInfo;
calibration.videoPath = char(videoPath);
calibration.source = struct( ...
    'type', 'video', ...
    'videoPath', char(videoPath), ...
    'frameIndex', frameInfo.FrameIndex, ...
    'timeSeconds', frameInfo.TimeSeconds);

if ~isempty(outputMatFile)
    save(outputMatFile, 'calibration');
end
end

function nameValue = unmatched_to_name_value(unmatched)
fields = fieldnames(unmatched);
nameValue = cell(1, 2 * numel(fields));

for k = 1:numel(fields)
    nameValue{2 * k - 1} = fields{k};
    nameValue{2 * k} = unmatched.(fields{k});
end
end

function nameValue = remove_name_value_pair(nameValue, targetName)
if isempty(nameValue)
    return;
end

matchMask = false(1, numel(nameValue) / 2);

for k = 1:numel(matchMask)
    matchMask(k) = strcmpi(nameValue{2 * k - 1}, targetName);
end

if any(matchMask)
    keepMask = ~repelem(matchMask, 2);
    nameValue = nameValue(keepMask);
end
end
