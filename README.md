# Visual reconstruction of played notes on a piano keyboard

Given a top-view RGB video of someone playing the piano, the pipeline marks on
every frame which keys are being pressed (green = white keys, red = black keys),
using only classical image processing and projective geometry.

## Requirements

- **MATLAB** (R2021a or newer recommended)
- **Image Processing Toolbox** (uses `im2gray`, `imbinarize`, `regionprops`,
  `imopen`/`imclose`/`imfill`, `bwareaopen`, `imdilate`, `rgb2ycbcr`, `VideoReader`)

## How to run

1. Open MATLAB and open `src/main.m`.
2. At the top of `main.m`, set the parameters for the video you want:
   - `VIDEO_NAME`: one of the videos in `assets/` (`Video1.mp4`, `Video2.mp4`,
     `Video3.mp4`).
   - `NUM_WHITE_KEYS`: how many white keys are visible in that video.
   - `FIRST_VISIBLE_NOTE`: the leftmost visible white note (e.g. `'F'`).
3. Press **Run**.
4. A calibration window opens: **click the four corners of the white-key region**,
   in this order: *top-left, top-right, bottom-right, bottom-left*.
5. The analysis window then plays the video with the detected presses overlaid.

## Useful flags (top of `main.m`)

- `FORCE_RECALIBRATE`: `true` re-runs the corner calibration every time; set it
  to `false` to reuse the saved `.mat` calibration.
- `DEBUG_DIFF`: `true` shows extra debug panels (frame difference and per-type
  masks); set to `false` for the clean output only.


