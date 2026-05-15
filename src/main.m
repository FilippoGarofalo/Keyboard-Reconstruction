% =========================================================================
% MAIN INTEGRATO: Flavio (Rettificazione) + Filippo (Spazio) + Emanuele (Tempo)
% =========================================================================

close all; clear; clc;

%% 1. Setup dei Path (Infallibile)
script_dir = fileparts(mfilename('fullpath')); 
addpath(genpath(script_dir)); 

%% 2. Inizializzazione Video e Calibrazione (Flavio)
video_path = fullfile(script_dir, '..', 'assets', 'Video.mp4'); 
if ~isfile(video_path)
    error('File video non trovato! Controlla il percorso.');
end
video_obj = VideoReader(video_path);

disp('Caricamento modello della tastiera...');
calib_file_path = fullfile(script_dir, 'keyboard model', 'H_white_calibration.mat');
calib_data = load(calib_file_path);
calib = calib_data.calibration; 
H = calib.H_white; % Matrice di omografia di Flavio

%% 3. Setup Immagine Rettificata e KeyMap (Flavio + Emanuele)
first_frame = readFrame(video_obj);
video_obj.CurrentTime = 0; % Reset

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
    if isfield(vk, 'blackKeys') && ~isempty(vk.blackKeys)
        blackKeys = vk.blackKeys;
        for i = 1:numel(blackKeys), blackKeys(i).type = 'black'; end
        % Allinea i campi per consentire la concatenazione
        commonFields = intersect(fieldnames(whiteKeys), fieldnames(blackKeys));
        extraW = setdiff(fieldnames(whiteKeys), commonFields);
        extraB = setdiff(fieldnames(blackKeys), commonFields);
        for f = 1:numel(extraW), [blackKeys.(extraW{f})] = deal([]); end
        for f = 1:numel(extraB), [whiteKeys.(extraB{f})] = deal([]); end
        allKeys = [whiteKeys(:); blackKeys(:)];
    else
        allKeys = whiteKeys(:);
    end
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

%% 4. Loop di Analisi Video
fig = figure('Name', 'Keyboard Reconstruction - Analisi Integrata', 'WindowStyle', 'normal');
ax = axes('Parent', fig);
disp('Inizio processamento video...');

while hasFrame(video_obj)
    frame = readFrame(video_obj);
    
    % --- A. RETTIFICAZIONE (Flavio) ---
    % Immagine perfetta vista dall'alto su cui lavorerà la tua funzione
    curr_rect = warp_image_inverse(frame, H, planeSizeMm, pixelsPerMm);
    
    % --- B. COMPONENTE SPAZIALE: Candidati (Filippo) ---
    fingertips_img = getFingers(frame .* mask_3D); 
    
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
        
        % Troviamo quali tasti contengono questi polpastrelli.
        % Policy: i neri vengono testati solo sulla colonna X (la punta del
        % dito spesso cade in basso fuori dalla "lamella" del nero, ma il
        % dito intende suonare il nero). Se nessun nero matcha, si cerca
        % tra i bianchi col poligono completo.
        for f = 1:size(fingertips_rect_px, 1)
            fx = fingertips_rect_px(f, 1);
            fy = fingertips_rect_px(f, 2);
            matchedBlack = false;
            for k = 1:length(keyMap)
                if strcmp(keyMap(k).type, 'black')
                    r = keyMap(k).BoundingBox; % [x y w h]
                    if fx >= r(1) && fx <= r(1) + r(3)
                        spatial_candidates = [spatial_candidates, keyMap(k).id];
                        matchedBlack = true;
                        break;
                    end
                end
            end
            if matchedBlack, continue; end
            for k = 1:length(keyMap)
                if strcmp(keyMap(k).type, 'white') && ...
                        inpolygon(fx, fy, keyMap(k).vertices(:,1), keyMap(k).vertices(:,2))
                    spatial_candidates = [spatial_candidates, keyMap(k).id];
                end
            end
        end
    end
    spatial_candidates = unique(spatial_candidates);

    % --- C. COMPONENTE TEMPORALE: Conferma (Emanuele) ---
    % La tua funzione calcola la differenza sull'immagine di Flavio
    temporal_candidates = detectPressedKeys(curr_rect, ref_rect, keyMap);
    
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
    
    % 2. Disegniamo i CANDIDATI SPAZIALI (Solo tocco, no pressione) in BLU TRATTEGGIATO
    for id = 1:length(spatial_candidates)
        r = keyMap(spatial_candidates(id)).roi;
        rectangle('Position', r, 'EdgeColor', 'b', 'LineWidth', 2, 'LineStyle', '--');
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
    drawnow limitrate;
end
disp('Elaborazione completata!');