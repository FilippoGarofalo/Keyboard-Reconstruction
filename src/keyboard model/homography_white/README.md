# H_white module

Questo modulo implementa la stima dell'omografia `H_white` per il piano dei tasti bianchi.

Idea geometrica:
- il piano superiore dei tasti bianchi viene modellato come una scena planare `\pi`
- l'immagine del piano e il piano stesso sono legati da un'omografia `u ~ H_white x_\pi`
- `H_white` viene stimata con `DLT + SVD`

File principali:
- `calibrate_H_white.m`: entry point della calibrazione
- `calibrate_H_white_from_video.m`: estrae un frame dal video e calibra `H_white`
- `extract_video_frame.m`: lettura di un frame con `VideoReader`
- `estimate_homography_dlt.m`: stima esplicita della matrice `H`
- `warp_image_inverse.m`: rettifica del frame sul piano della tastiera
- `synthetic_test_H_white.m`: test sintetico senza dati reali

Uso minimo:

```matlab
addpath('matlab/homography_white');
calibration = calibrate_H_white('frame0.png', 14, ...
    'WhiteKeyWidthMm', 23.5, ...
    'VisibleWhiteKeyHeightMm', 150, ...
    'PixelsPerMm', 4, ...
    'OutputMatFile', 'H_white_calibration.mat');
```

Note:
- il numero `14` nell'esempio e` il numero di tasti bianchi visibili nel frame
- i quattro punti cliccati devono appartenere tutti al piano dei tasti bianchi
- il modulo salva la struttura `calibration` con `H_white`, `H_image_to_plane`, ROI della tastiera, punti selezionati, errore di riproiezione e immagine rettificata

Uso diretto da video:

```matlab
addpath('matlab/homography_white');
videoPath = 'data/videos/Bitesize Piano - TWINKLE TWINKLE LITTLE STAR - Easy Piano Tutorial.mp4';

calibration = calibrate_H_white_from_video(videoPath, 14, ...
    'FrameIndex', 1, ...
    'SaveFramePath', 'data/videos/frame0.png', ...
    'WhiteKeyWidthMm', 23.5, ...
    'VisibleWhiteKeyHeightMm', 150, ...
    'PixelsPerMm', 4, ...
    'OutputMatFile', 'H_white_calibration.mat');
```
