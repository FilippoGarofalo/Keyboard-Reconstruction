function [frame, info] = extract_video_frame(videoPath, varargin)
%EXTRACT_VIDEO_FRAME Read a frame from a video using VideoReader.
%
%   [frame, info] = extract_video_frame(videoPath)
%   [frame, info] = extract_video_frame(..., 'FrameIndex', k)
%   [frame, info] = extract_video_frame(..., 'TimeSeconds', t)
%   [frame, info] = extract_video_frame(..., 'SaveImagePath', path)
%   [frame, info] = extract_video_frame(..., 'AutoSkipDarkFrames', true)

parser = inputParser;
parser.addParameter('FrameIndex', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
parser.addParameter('TimeSeconds', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
parser.addParameter('SaveImagePath', '', @(x) ischar(x) || isstring(x));
parser.addParameter('AutoSkipDarkFrames', true, @(x) islogical(x) || isnumeric(x));
parser.addParameter('DarkFrameThreshold', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parser.addParameter('MaxAutoSkipFrames', 300, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parser.parse(varargin{:});
params = parser.Results;

videoObj = VideoReader(videoPath);
info = struct();
info.VideoPath = char(videoPath);
info.Width = videoObj.Width;
info.Height = videoObj.Height;
info.FrameRate = videoObj.FrameRate;
info.Duration = videoObj.Duration;

if ~isempty(params.TimeSeconds)
    targetTime = min(params.TimeSeconds, max(0, videoObj.Duration - eps));
    videoObj.CurrentTime = targetTime;
    if ~hasFrame(videoObj)
        error('No frame is available at the requested time %.3f s.', params.TimeSeconds);
    end
    frame = readFrame(videoObj);
    info.TimeSeconds = targetTime;
    info.FrameIndex = max(1, round(targetTime * videoObj.FrameRate) + 1);
else
    targetIndex = round(params.FrameIndex);
    if targetIndex < 1
        error('FrameIndex must be at least 1.');
    end

    frame = [];
    for k = 1:targetIndex
        if ~hasFrame(videoObj)
            error('Requested frame %d exceeds the video length.', targetIndex);
        end
        frame = readFrame(videoObj);
    end

    info.FrameIndex = targetIndex;
    info.TimeSeconds = (targetIndex - 1) / videoObj.FrameRate;
end

framesSkipped = 0;
if params.AutoSkipDarkFrames
    while is_dark_frame(frame, params.DarkFrameThreshold) && hasFrame(videoObj) ...
            && framesSkipped < params.MaxAutoSkipFrames
        frame = readFrame(videoObj);
        framesSkipped = framesSkipped + 1;
        info.FrameIndex = info.FrameIndex + 1;
        info.TimeSeconds = (info.FrameIndex - 1) / videoObj.FrameRate;
    end

    if framesSkipped > 0
        fprintf('Auto-skipped %d dark frame(s). Using frame %d at %.3f s.\n', ...
            framesSkipped, info.FrameIndex, info.TimeSeconds);
    end
end

if ~isempty(params.SaveImagePath)
    imwrite(frame, params.SaveImagePath);
    info.SaveImagePath = char(params.SaveImagePath);
else
    info.SaveImagePath = '';
end

info.AutoSkippedFrames = framesSkipped;
end

function tf = is_dark_frame(frame, threshold)
tf = mean(double(frame(:))) <= threshold;
end
