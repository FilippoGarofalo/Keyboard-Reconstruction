% =========================================================================
% MAIN INTEGRATO: Flavio (Rettificazione) + Filippo (Spazio) + Emanuele (Tempo)
% =========================================================================

close all; clear; clc;

%% 1. Setup dei Path (Infallibile)
script_dir = fileparts(mfilename('fullpath')); 
addpath(genpath(script_dir)); 

%% 2. Parametri
% Modifica questi valori per adattarli al tuo setup.
% Imposta FORCE_RECALIBRATE = true per ricalibr forzando la sovrascrittura del .mat.
FORCE_RECALIBRATE        = true;
NUM_WHITE_KEYS           = 21;
FIRST_VISIBLE_NOTE       = 'F';
WHITE_KEY_WIDTH_MM       = 23.5;
VISIBLE_WHITE_HEIGHT_MM  = 150;
PIXELS_PER_MM            = 4;
CALIB_TIME_SECONDS       = 2.0;
MOTION_DIFF_THRESH       = 40;   % luminanza (0..255): soglia movimento mano vs sfondo statico (alza per meno falsi)
MOTION_DILATE_PX         = 5;     % raggio dilatazione maschera movimento (riduci per meno sbordo sui tasti vicini)
ANALYSIS_MARGIN_PX       = 10;   % margine di sicurezza (px) sopra il bordo superiore della mano
MIN_ANALYSIS_FRAC        = 0.15; % floor adattivo: mai meno del 15% della tastiera (evita zone troppo piccole)
GRID_SHIFT_X_PX          = -35;  % shift orizz. ROI temporale (px, neg=sinistra per inseguire ombra a sx del tasto nero)
GRID_SHIFT_Y_PX          = 0;   % shift vert. ROI temporale (px, neg=alto)

video_path      = fullfile(script_dir, '..', 'assets', 'Video5.mp4');
calib_file_path = fullfile(script_dir, 'keyboard model', 'H_white_calibration2.mat');

if ~isfile(video_path)
    error('File video non trovato: %s', video_path);
end

%% 3. Calibrazione
if ~isfile(calib_file_path) || FORCE_RECALIBRATE
    fprintf('Calibrazione: %d tasti bianchi, nota iniziale ''%s''...\n', ...
        NUM_WHITE_KEYS, FIRST_VISIBLE_NOTE);
    frame_path = fullfile(script_dir, '..', 'assets', 'frame0.png');
    calib = calibrate_H_white_from_video(video_path, NUM_WHITE_KEYS, ...
        'TimeSeconds',             CALIB_TIME_SECONDS, ...
        'AutoSkipDarkFrames',      true, ...
        'DarkFrameThreshold',      5, ...
        'MaxAutoSkipFrames',       300, ...
        'SaveFramePath',           frame_path, ...
        'WhiteKeyWidthMm',         WHITE_KEY_WIDTH_MM, ...
        'VisibleWhiteKeyHeightMm', VISIBLE_WHITE_HEIGHT_MM, ...
        'PixelsPerMm',             PIXELS_PER_MM, ...
        'FirstVisibleNote',        FIRST_VISIBLE_NOTE, ...
        'OutputMatFile',           '');
    calib.virtualKeyboard = build_virtual_keyboard(calib, 'StartNote', FIRST_VISIBLE_NOTE);
    calibration = calib;
    save(calib_file_path, 'calibration');
    fprintf('Calibrazione completata e salvata: %s\n', calib_file_path);
else
    disp('Calibrazione esistente trovata, caricamento...');
    tmp = load(calib_file_path);
    calib = tmp.calibration;
end

H = calib.H_white;
video_obj = VideoReader(video_path);

%% 4. Setup Immagine Rettificata e KeyMap (Flavio + Emanuele)
first_frame = readFrame(video_obj);
video_obj.CurrentTime = 0; % Reset

% Background statico in coordinate raw (video) per la maschera di movimento.
% I tasti sono fermi qui dentro; solo la mano cambia rispetto a questo frame.
background_gray = im2gray(first_frame);

% Generiamo l'immagine rettificata di Flavio (vista dall'alto)
% Usiamo i parametri della calibrazione invece di assumere 52 tasti
vk = calib.virtualKeyboard;
pixelsPerMm = calib.pixelsPerMm;
planeSizeMm = [vk.keyboardHeightMm, vk.keyboardWidthMm];
ref_rect = warp_image_inverse(first_frame, H, planeSizeMm, pixelsPerMm);

% Costruiamo keyMap direttamente da virtualKeyboard (bianchi + neri, gia'
% modellati in coordinate rettificate dalla calibrazione).
% Compat: i .mat vecchi non hanno il campo unificato allKeys.
if isfield(vk, 'allKeys') && ~isempty(vk.allKeys)
    allKeys = vk.allKeys;
else
    whiteKeys = vk.keys;
    for i = 1:numel(whiteKeys), whiteKeys(i).type = 'white'; end

    % Se vk.blackKeys non c'e' (calibrazioni vecchie con solo bianchi),
    % costruiamo i neri al volo dal modello dei bianchi e dal startNote
    % salvato in calibration. Cosi' main.m funziona senza rigenerare il .mat.
    if isfield(vk, 'blackKeys') && ~isempty(vk.blackKeys)
        blackKeys = vk.blackKeys;
    else
        if isfield(calib, 'firstVisibleNote') && ~isempty(calib.firstVisibleNote)
            startNote = calib.firstVisibleNote;
        else
            startNote = 'A0';  % default 88-tasti
        end
        blackKeys = build_virtual_black_keys(vk, startNote);
    end
    for i = 1:numel(blackKeys), blackKeys(i).type = 'black'; end

    % Allinea i campi per consentire la concatenazione
    commonFields = intersect(fieldnames(whiteKeys), fieldnames(blackKeys));
    extraW = setdiff(fieldnames(whiteKeys), commonFields);
    extraB = setdiff(fieldnames(blackKeys), commonFields);
    for f = 1:numel(extraW), [blackKeys.(extraW{f})] = deal([]); end
    for f = 1:numel(extraB), [whiteKeys.(extraB{f})] = deal([]); end
    allKeys = [whiteKeys(:); blackKeys(:)];
end
keyMap = struct('id', {}, 'roi', {}, 'type', {}, 'vertices', {}, 'BoundingBox', {});
for k = 1:numel(allKeys)
    keyMap(k).id          = k;
    keyMap(k).type        = allKeys(k).type;
    keyMap(k).roi         = allKeys(k).boundingBoxPx;
    keyMap(k).BoundingBox = allKeys(k).boundingBoxPx;
    keyMap(k).vertices    = allKeys(k).polygonPx;
end

% Pre-calcoliamo la maschera ROI di Flavio per pulire l'input di Filippo
img_size = [size(first_frame, 1), size(first_frame, 2)];
if isfield(calib, 'roiPolygonPx'), roi_poly = calib.roiPolygonPx;
elseif isfield(calib, 'imagePoints'), roi_poly = calib.imagePoints;
else, roi_poly = calib.cornersPx; end
roi_mask = build_keyboard_roi_mask(img_size, roi_poly);
mask_3D = repmat(uint8(roi_mask), 1, 1, 3);

%% 5. Loop di Analisi Video
fig = figure('Name', 'Keyboard Reconstruction - Analisi Integrata', 'WindowStyle', 'normal');
ax = axes('Parent', fig);

% Finestra di debug: diff grayscale + maschere binarie per-tipo
DEBUG_DIFF = true;
if DEBUG_DIFF
    % Calcoliamo la dimensione del frame rettificato per inizializzare gli
    % assi con la dimensione corretta (altrimenti rimangono 1x1 e si vede
    % solo un quadratino nero).
    recH = max(1, round(planeSizeMm(1) * pixelsPerMm));
    recW = max(1, round(planeSizeMm(2) * pixelsPerMm));

    figDebug   = figure('Name', 'Debug: Frame Difference', 'WindowStyle', 'normal');
    scr = get(0, 'ScreenSize');   % [1 1 screenW screenH]
    figDebug.Position = [10, 80, scr(3) - 20, min(650, scr(4) - 150)];
    axSkin     = subplot(1, 4, 1, 'Parent', figDebug);
    axDiff     = subplot(1, 4, 2, 'Parent', figDebug);
    axBwWhite  = subplot(1, 4, 3, 'Parent', figDebug);
    axBwBlack  = subplot(1, 4, 4, 'Parent', figDebug);

    % Pannello 1: frame rettificato con skin mask in rosso semi-trasparente
    hSkinImg = imshow(zeros(recH, recW, 3, 'uint8'), 'Parent', axSkin);
    title(axSkin, 'Skin mask rettificata (rosso) su frame');

    % Diff grayscale: imagesc auto-scala il range, cosi' anche valori bassi
    % (post skin-mask la diff e' tipicamente 10-40 su 255) si vedono.
    hDiff = imagesc(zeros(recH, recW), 'Parent', axDiff);
    axis(axDiff, 'image'); axis(axDiff, 'off');
    colormap(axDiff, 'hot');
    colorbar(axDiff);
    title(axDiff, 'Diff grayscale (post skin-mask)');

    hBwWhite = imshow(false(recH, recW), 'Parent', axBwWhite);
    title(axBwWhite, 'BW Diff - soglia bianchi');

    hBwBlack = imshow(false(recH, recW), 'Parent', axBwBlack);
    title(axBwBlack, 'BW Diff - soglia neri');

    % Creiamo UNA SOLA linea ciano per pannello, aggiornata frame per frame.
    % Usando l'handle e impostando .Value evitiamo l'accumulo di linee.
    hold(axDiff,    'on'); hLineAnalysisDiff  = yline(axDiff,    1, 'c-', 'LineWidth', 1.5); hold(axDiff,    'off');
    hold(axBwWhite, 'on'); hLineAnalysisWhite = yline(axBwWhite, 1, 'c-', 'LineWidth', 1.5); hold(axBwWhite, 'off');
    hold(axBwBlack, 'on'); hLineAnalysisBlack = yline(axBwBlack, 1, 'c-', 'LineWidth', 1.5); hold(axBwBlack, 'off');

    % Disegna i bounding box dei tasti UNA SOLA VOLTA su tutti i pannelli diff.
    % Le posizioni sono fisse nel piano rettificato, quindi non serve ridisegnarle
    % ad ogni frame: restano sopra all'immagine aggiornata via set(...,'CData',...).
    % Bianchi in ciano, neri in giallo (stesso schema della finestra principale).
    hold(axDiff,    'on');
    hold(axBwWhite, 'on');
    hold(axBwBlack, 'on');
    for k = 1:length(keyMap)
        bb  = keyMap(k).BoundingBox;
        col = 'c'; lw = 0.8;
        if strcmp(keyMap(k).type, 'black'), col = 'y'; lw = 1.0; end
        xv = [bb(1), bb(1)+bb(3), bb(1)+bb(3), bb(1)];
        yv = [bb(2), bb(2),       bb(2)+bb(4), bb(2)+bb(4)];
        patch('Parent', axDiff,    'XData', xv, 'YData', yv, 'FaceColor', 'none', 'EdgeColor', col, 'LineWidth', lw, 'EdgeAlpha', 0.35);
        patch('Parent', axBwWhite, 'XData', xv, 'YData', yv, 'FaceColor', 'none', 'EdgeColor', col, 'LineWidth', lw, 'EdgeAlpha', 0.35);
        patch('Parent', axBwBlack, 'XData', xv, 'YData', yv, 'FaceColor', 'none', 'EdgeColor', col, 'LineWidth', lw, 'EdgeAlpha', 0.35);
    end
    hold(axDiff,    'off');
    hold(axBwWhite, 'off');
    hold(axBwBlack, 'off');
end
disp('Inizio processamento video...');

while hasFrame(video_obj)
    frame = readFrame(video_obj);
    
    % --- A. RETTIFICAZIONE (Flavio) ---
    % Immagine perfetta vista dall'alto su cui lavorerà la tua funzione
    curr_rect = warp_image_inverse(frame, H, planeSizeMm, pixelsPerMm);
    
    % --- B. COMPONENTE SPAZIALE: Candidati (Filippo) ---
    % Maschera di movimento: la mano si muove, i tasti no. Intersecando la
    % pelle con questa maschera dentro getFingers, i tasti color avorio fermi
    % non possono piu' essere scambiati per dita (falsi candidati a sinistra).
    motion_mask = imabsdiff(im2gray(frame), background_gray) > MOTION_DIFF_THRESH;
    motion_mask = imclose(motion_mask, strel('disk', 5));
    motion_mask = imdilate(motion_mask, strel('disk', MOTION_DILATE_PX));

    [fingertips_img, skin_mask_img] = getFingers(frame .* mask_3D, motion_mask);
    
    spatial_candidates = [];
    fingertips_rect_px = [];
    if ~isempty(fingertips_img)
        % Mappiamo i punti di Filippo dal video all'immagine rettificata!
        % 1. Aggiungiamo la coordinata omogenea
        pts_homog = [fingertips_img, ones(size(fingertips_img,1), 1)]';
        % 2. Moltiplichiamo per l'inversa di H (per trovare i millimetri)
        pts_mm_homog = H \ pts_homog;
        pts_mm = (pts_mm_homog(1:2, :) ./ pts_mm_homog(3, :))';
        % 3. Convertiamo i millimetri nei pixel dell'immagine rettificata
        fingertips_rect_px = pts_mm * pixelsPerMm;
        
        % Policy: si testa prima il nero (bounding box X e Y, con tolleranza
        % in Y per assorbire la PARALLASSE (i tasti neri sono ~10 mm piu'
        % alti del piano dei bianchi su cui e' calibrata H, quindi il
        % fingertip su un nero si proietta piu' in avanti del previsto).
        % Solo se nessun nero matcha si passa ai bianchi col poligono.
        % 80 px ~ 20 mm: la zona fy > 460 px (>~115 mm dal back) resta
        % comunque territorio bianco puro.
        % Tolleranza Y per i neri: le nocche rilevate dall'hull si proiettano
        % piu' in avanti del polpastrello reale (parallasse + hull = nocche).
        % Tolleranza Y per i bianchi: stessa causa, le nocche cadono appena
        % fuori dal poligono verso il bordo anteriore della tastiera.
        blackYTolerancePx = 80;
        whiteYTolerancePx = 60;
        for f = 1:size(fingertips_rect_px, 1)
            fx = fingertips_rect_px(f, 1);
            fy = fingertips_rect_px(f, 2);
            matchedBlack = false;
            for k = 1:length(keyMap)
                if strcmp(keyMap(k).type, 'black')
                    r = keyMap(k).BoundingBox; % [x y w h]
                    if fx >= r(1) && fx <= r(1) + r(3) && ...
                            fy >= r(2) && fy <= r(2) + r(4) + blackYTolerancePx
                        spatial_candidates = [spatial_candidates, keyMap(k).id];
                        matchedBlack = true;
                        break;
                    end
                end
            end
            if matchedBlack
                if DEBUG_DIFF
                    fprintf('  finger #%d -> BLACK fy=%.0f fx=%.0f\n', f, fy, fx);
                end
                continue;
            end
            % Per i bianchi usiamo fy spostato indietro di whiteYTolerancePx
            % cosi' le nocche (proiettate troppo in avanti) rientrano nel
            % poligono del tasto corretto.
            fy_white = max(0, fy - whiteYTolerancePx);
            matchedWhite = false;
            for k = 1:length(keyMap)
                if strcmp(keyMap(k).type, 'white') && ...
                        inpolygon(fx, fy_white, keyMap(k).vertices(:,1), keyMap(k).vertices(:,2))
                    spatial_candidates = [spatial_candidates, keyMap(k).id];
                    matchedWhite = true;
                    break;
                end
            end
            if DEBUG_DIFF && ~matchedWhite
                fprintf('  finger #%d -> NO MATCH  fy=%.0f fx=%.0f\n', f, fy, fx);
            end
        end
    end
    spatial_candidates = unique(spatial_candidates);

    % Espansione dei candidati spaziali per mano separata.
    % I candidati vengono ordinati per X e divisi in gruppi: un gap
    % orizzontale > HAND_GAP_THRESH indica il vuoto tra le due mani.
    % Ogni gruppo viene espanso separatamente, cosi' non si includono i
    % tasti nel mezzo tra mano sinistra e mano destra.
    if length(spatial_candidates) >= 2
        key_width_px   = WHITE_KEY_WIDTH_MM * PIXELS_PER_MM;
        HAND_GAP_THRESH = 3 * key_width_px;   % >3 tasti bianchi = cambio di mano

        x_centers  = arrayfun(@(k) keyMap(k).BoundingBox(1) + keyMap(k).BoundingBox(3)/2, spatial_candidates);
        [~, sidx]  = sort(x_centers);
        cands_sort = spatial_candidates(sidx);
        x_sort     = x_centers(sidx);

        % Trova i punti di separazione tra i gruppi (mani)
        breaks = [0, find(diff(x_sort) > HAND_GAP_THRESH), length(cands_sort)];

        expanded = [];
        for g = 1:length(breaks)-1
            grp     = cands_sort(breaks(g)+1 : breaks(g+1));
            x_left  = min(arrayfun(@(k) keyMap(k).BoundingBox(1), grp));
            x_right = max(arrayfun(@(k) keyMap(k).BoundingBox(1) + keyMap(k).BoundingBox(3), grp));
            for k = 1:length(keyMap)
                bb = keyMap(k).BoundingBox;
                if bb(1) < x_right && (bb(1) + bb(3)) > x_left
                    expanded = [expanded, k];
                end
            end
        end
        spatial_candidates = unique(expanded);
    end

    % --- C. COMPONENTE TEMPORALE: Conferma (Emanuele) ---
    % Rettifichiamo la skin mask con la stessa omografia del frame in modo
    % da poter sottrarre i pixel di pelle dalla frame-difference (altrimenti
    % il dito stesso viene contato come "tasto premuto").
    skin_mask_rect = false(size(curr_rect, 1), size(curr_rect, 2));
    if ~isempty(skin_mask_img) && any(skin_mask_img(:))
        warped = warp_image_inverse(uint8(skin_mask_img) * 255, ...
                                    H, planeSizeMm, pixelsPerMm);
        skin_mask_rect = warped > 127;
    end
    % Calcolo adattivo del limite verticale di analisi.
    % Usa la Y minima dei polpastrelli proiettati (fingertips_rect_px) come
    % stima del bordo superiore della mano nel frame rettificato.
    % La skin mask warped NON e' adatta a questo scopo: l'omografia H e'
    % calibrata sul piano dei tasti, ma la mano e' fisicamente sopra quel
    % piano (parallasse) → la proiezione sposta i pixel di pelle verso l'alto
    % (piccola Y), rendendo top_skin_row troppo piccolo e la linea sempre in cima.
    % fingertips_rect_px invece riflette la posizione visiva della mano.
    % Fallback al fisso 1/3 se nessun polpastrello e' rilevato.
    if ~isempty(fingertips_rect_px)
        top_finger_y  = min(fingertips_rect_px(:, 2));
        adaptive_rows = max(top_finger_y - ANALYSIS_MARGIN_PX, ...
                            floor(size(curr_rect, 1) * MIN_ANALYSIS_FRAC));
    else
        adaptive_rows = floor(size(curr_rect, 1) / 3);
    end

    % Grid shift per la componente temporale: trasla le ROI nella direzione
    % dell'ombra cosi' ogni tasto cattura la propria variazione di luminanza.
    % La componente spaziale continua a usare keyMap originale (non shiftata).
    keyMapTemporal = keyMap;
    if GRID_SHIFT_X_PX ~= 0 || GRID_SHIFT_Y_PX ~= 0
        for k = 1:length(keyMapTemporal)
            keyMapTemporal(k).BoundingBox(1) = keyMapTemporal(k).BoundingBox(1) + GRID_SHIFT_X_PX;
            keyMapTemporal(k).BoundingBox(2) = keyMapTemporal(k).BoundingBox(2) + GRID_SHIFT_Y_PX;
        end
    end

    if DEBUG_DIFF
        [temporal_candidates, diffDebug] = detectPressedKeys(curr_rect, ref_rect, keyMapTemporal, skin_mask_rect, adaptive_rows);
    else
        temporal_candidates = detectPressedKeys(curr_rect, ref_rect, keyMapTemporal, skin_mask_rect, adaptive_rows);
    end
    
    % --- D. INTERSEZIONE (La vera magia) ---
    % Il tasto è premuto SOLO SE Filippo vede il dito E tu vedi il movimento
    pressed_keys = intersect(temporal_candidates, spatial_candidates);

    % --- E. VISUALIZZAZIONE ---
    % Mostriamo il risultato finale sull'immagine rettificata
    imshow(curr_rect, 'Parent', ax); hold(ax, 'on');
    
    % 1. Disegniamo i polpastrelli di Filippo proiettati
    if ~isempty(fingertips_rect_px)
        plot(ax, fingertips_rect_px(:,1), fingertips_rect_px(:,2), 'r*', 'MarkerSize', 8, 'LineWidth', 2);
    end
    
    % 2. Disegniamo i CANDIDATI SPAZIALI (Solo tocco, no pressione) tratteggiati.
    %    Bianchi in BLU, neri in GIALLO: sui tasti neri il blu si confondeva,
    %    il giallo risalta e distingue subito quando un nero e' candidato.
    for id = 1:length(spatial_candidates)
        r = keyMap(spatial_candidates(id)).roi;
        candCol = 'b';
        if strcmp(keyMap(spatial_candidates(id)).type, 'black'), candCol = 'y'; end
        rectangle('Parent', ax, 'Position', r, 'EdgeColor', candCol, 'LineWidth', 2, 'LineStyle', '--');
    end

    % 3. Disegniamo I TASTI PREMUTI CONFERMATI (Intersezione Spazio + Tempo) CON RIEMPIMENTO
    for id = 1:length(pressed_keys)
        r = keyMap(pressed_keys(id)).roi;
        col = 'g'; if strcmp(keyMap(pressed_keys(id)).type, 'black'), col = 'r'; end
        % Usiamo 'patch' per colorare l'interno del tasto in semitrasparenza
        patch(ax, 'XData', [r(1) r(1)+r(3) r(1)+r(3) r(1)], ...
                  'YData', [r(2) r(2) r(2)+r(4) r(2)+r(4)], ...
                  'FaceColor', col, 'FaceAlpha', 0.4, 'EdgeColor', col, 'LineWidth', 2);
    end
    hold(ax, 'off');

    % --- F. DEBUG: visualizzazione frame difference ---
    if DEBUG_DIFF
        % Pannello 1: frame rettificato con la skin mask tinta in rosso.
        % Cosi' vediamo se la mask copre davvero la mano dopo la rettifica.
        overlay = curr_rect;
        if ~isa(overlay, 'uint8'); overlay = im2uint8(overlay); end
        if size(overlay, 3) == 1; overlay = repmat(overlay, 1, 1, 3); end
        m = logical(skin_mask_rect);
        if any(m(:))
            R = overlay(:,:,1); G = overlay(:,:,2); B = overlay(:,:,3);
            % Alpha-blend con rosso pieno (255, 0, 0) al 50%
            R(m) = uint8(0.5 * 255 + 0.5 * double(R(m)));
            G(m) = uint8(0.5 * 0   + 0.5 * double(G(m)));
            B(m) = uint8(0.5 * 0   + 0.5 * double(B(m)));
            overlay(:,:,1) = R; overlay(:,:,2) = G; overlay(:,:,3) = B;
        end
        set(hSkinImg, 'CData', overlay);

        % diff: passiamo double cosi' imagesc auto-scala il range visibile
        % (i valori della diff post skin-mask sono tipicamente molto bassi).
        set(hDiff,    'CData', diffDebug.diff);
        set(hBwWhite, 'CData', diffDebug.bwWhite);
        set(hBwBlack, 'CData', diffDebug.bwBlack);
        % Aggiorna la linea ciano adattiva (una sola per pannello, creata
        % prima del loop): mostra il bordo superiore della zona di analisi,
        % che ora segue il punto piu' alto della mano frame per frame.
        ar = diffDebug.analysisRows;
        hLineAnalysisDiff.Value  = ar;
        hLineAnalysisWhite.Value = ar;
        hLineAnalysisBlack.Value = ar;
        % Stampa a console la % per i candidati spaziali (vediamo se i neri
        % sono vicini a passare la soglia o lontanissimi).
        if ~isempty(spatial_candidates)
            for sc = spatial_candidates(:)'
                fprintf('  key %2d (%s): ratio=%.3f  thresh=%.3f\n', ...
                    sc, keyMap(sc).type, diffDebug.perKeyRatio(sc), ...
                    (strcmp(keyMap(sc).type,'black')) * diffDebug.blackPixelPercent + ...
                    (~strcmp(keyMap(sc).type,'black')) * diffDebug.whitePixelPercent);
            end
        end
    end

    drawnow limitrate;
end
disp('Elaborazione completata!');