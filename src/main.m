% =========================================================================
% MAIN SCRIPT - Debug Integrazione: Keyboard Model (Flavio) & Hand Pose (Filippo)
% =========================================================================

close all; 
clear; 
clc;

%% 1. Setup dei Path e delle Directory
% 'script_dir' calcola automaticamente la cartella 'src' in cui ti trovi
script_dir = fileparts(mfilename('fullpath')); 
addpath(genpath(script_dir)); 

%% 2. Inizializzazione Video e Calibrazione
% Costruiamo il percorso del video in modo assoluto (uscendo da src e andando in assets)
video_path = fullfile(script_dir, '..', 'assets', 'Video.mp4'); 

if ~isfile(video_path)
    error('File video non trovato! Controlla di avere la cartella "assets" e "Video.mp4" al livello superiore di "src".');
end
video_obj = VideoReader(video_path);

disp('Caricamento modello della tastiera e calibrazione...');

% CORRETTO: Il file si trova direttamente dentro 'keyboard model'
calib_file_path = fullfile(script_dir, 'keyboard model', 'H_white_calibration.mat');
if ~isfile(calib_file_path)
    error('File di calibrazione non trovato! Controlla il percorso: %s', calib_file_path);
end

calib_data = load(calib_file_path);
calib = calib_data.calibration; 

%% 3. Setup della Maschera ROI (Region of Interest)
disp('Generazione della maschera per isolare la tastiera...');

first_frame = readFrame(video_obj);
video_obj.CurrentTime = 0; % Reset del video

% Estraiamo le dimensioni dell'immagine per la funzione di Flavio (array di 2 elementi)
img_size = [size(first_frame, 1), size(first_frame, 2)];

% Troviamo il nome della variabile dei 4 punti che Flavio ha salvato nella struct.
% Proviamo i nomi più comuni usati in computer vision per le omografie.
if isfield(calib, 'imagePoints')
    roi_polygon = calib.imagePoints;
elseif isfield(calib, 'roiPolygonPx')
    roi_polygon = calib.roiPolygonPx;
elseif isfield(calib, 'cornersPx')
    roi_polygon = calib.cornersPx;
else
    error('Non riesco a trovare i 4 punti della tastiera in "calib". Clicca due volte su "calib_data" nel workspace e sostituisci il nome del campo corretto qui sotto!');
    % roi_polygon = calib.NOME_DEL_TUO_CAMPO; 
end

% Generiamo la maschera passando dimensioni e poligono
keyboard_roi_mask = build_keyboard_roi_mask(img_size, roi_polygon); 

% Creiamo una maschera a 3 canali per l'immagine a colori
keyboard_roi_mask_uint8 = uint8(keyboard_roi_mask);
mask_3D = repmat(keyboard_roi_mask_uint8, 1, 1, 3);

%% 4. Setup della Finestra di Debug
fig = figure('Name', 'Debug: Hand Pose + Keyboard Mapping', 'WindowStyle', 'normal');
ax = axes('Parent', fig);
img_handle = imshow(first_frame, 'Parent', ax);
hold(ax, 'on');

disp('Inizio processamento video. Premi CTRL+C nella Command Window per interrompere.');

%% 5. Loop di Analisi Video (Integrazione)
while hasFrame(video_obj)
    img_RGB = readFrame(video_obj);
    
    % --- APPLICAZIONE DELLA MASCHERA ---
    % Eliminiamo il feltro rosso e il resto della stanza!
    img_RGB_masked = img_RGB .* mask_3D;
    
    % --- A. MODULO DI FILIPPO: Hand Pose Estimation ---
    fingertips_img = getFingers(img_RGB_masked); 
    
    % --- C. VISUALIZZAZIONE DI DEBUG ---
    % 1. Mostriamo l'immagine MASCHERATA invece di quella originale
    set(img_handle, 'CData', img_RGB_masked);
    
    % Puliamo i disegni vecchi
    delete(findobj(ax, 'Type', 'Line')); 
    
    % 2. Disegniamo i confini della maschera di Flavio (linea gialla)
    % Questo ci farà vedere ESATTAMENTE l'area considerata "tastiera"
    plot(ax, roi_polygon([1:end, 1], 1), roi_polygon([1:end, 1], 2), 'y-', 'LineWidth', 2);
    
    % 3. Disegniamo i polpastrelli (Punti Rossi)
    if ~isempty(fingertips_img)
        plot(ax, fingertips_img(:, 1), fingertips_img(:, 2), 'r*', 'MarkerSize', 10, 'LineWidth', 2);
    end
    % Puliamo i disegni vecchi
    delete(findobj(ax, 'Type', 'Line')); 
    
    % Disegniamo i polpastrelli (Punti Rossi)
    if ~isempty(fingertips_img)
        plot(ax, fingertips_img(:, 1), fingertips_img(:, 2), 'r*', 'MarkerSize', 10, 'LineWidth', 2);
    end
    
    drawnow limitrate; 
end

disp('Debug completato con successo!');