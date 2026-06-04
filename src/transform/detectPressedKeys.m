function [pressedNotes, debugInfo] = detectPressedKeys(current_rect, background_rect, keyMap, skinMaskRect, analysisRowsOverride)
    % detectPressedKeys: Rileva i tasti premuti tramite differenza di frame.
    %
    % Differenza con SEGNO (non assoluta):
    %   - tasti BIANCHI: si cercano pixel che si sono SCURITI
    %     (il dito, piu' scuro del tasto bianco, lo copre → current < background
    %      → segnale = background - current > 0)
    %   - tasti NERI: si cercano pixel che si sono SCHIARITI
    %     (il dito/pelle, piu' chiaro del tasto nero, lo copre → current > background
    %      → segnale = current - background > 0)
    %
    % Questo elimina il cross-talk ai bordi: quando un bianco viene premuto,
    % i pixel dell'area adiacente si scuriscono (direzione "bianco") e NON
    % contribuiscono al canale "nero", eliminando i falsi positivi sui neri.
    %
    % La skin mask viene applicata SOLO a diffForWhite: per i neri il segnale
    % di pressione E' la pelle che schiarisce il tasto, azzerarla toglierebbe
    % il segnale utile. Per i bianchi serve invece a evitare che il movimento
    % della mano generi falsi scurimenti su bianchi adiacenti.
    %
    % Ogni ROI viene ristretta di ROI_MARGIN px verso l'interno (opzione A)
    % per ridurre il bleed dai bordi dei tasti adiacenti.
    %
    % analysisRowsOverride (opzionale): se fornito, sostituisce il calcolo
    % interno TOP_FRACTION=1/3 con il valore adattivo calcolato in main.m.
    %
    % Output:
    %   pressedNotes - indici dei tasti premuti
    %   debugInfo    - struct con .diff (|grayDiff| 0..255), .bwWhite, .bwBlack
    %                  e .perKeyRatio (vettore con la % di pixel "on" per tasto)

    ROI_MARGIN = 2;   % pixel di margine interno per ogni lato della ROI (opzione A)

    % 1. Differenza con segno (NON abs)
    grayDiff = double(im2gray(current_rect)) - double(im2gray(background_rect));

    % 2. Canale NERO: pelle su tasto nero → area si SCHIARISCE (current > background)
    %    La skin mask NON viene applicata: il segnale utile E' la pelle stessa.
    diffForBlack = max(0,  grayDiff) / 255;   % [0..1]

    % 3. Canale BIANCO: pelle su tasto bianco → area si SCURISCE (current < background)
    %    La skin mask viene applicata per evitare falsi positivi da movimento mano.
    if nargin >= 4 && ~isempty(skinMaskRect)
        grayDiff(logical(skinMaskRect)) = 0;
    end
    diffForWhite = max(0, -grayDiff) / 255;   % [0..1]

    whiteDiffThresh   = 20/255;
    blackDiffThresh   = 25/255;
    whitePixelPercent = 0.10;
    blackPixelPercent = 0.15;

    bwDiffWhite = imbinarize(diffForWhite, whiteDiffThresh);
    bwDiffBlack = imbinarize(diffForBlack, blackDiffThresh);

    se = strel('disk', 2);
    bwDiffWhite = imopen(bwDiffWhite, se);
    bwDiffBlack = imopen(bwDiffBlack, se);

    % 4. Limite verticale di analisi
    TOP_FRACTION  = 1/3;
    if nargin >= 5 && ~isempty(analysisRowsOverride) && analysisRowsOverride > 0
        analysis_rows = analysisRowsOverride;
    else
        analysis_rows = floor(size(grayDiff, 1) * TOP_FRACTION);
    end

    pressedNotes = [];
    perKeyRatio = zeros(1, length(keyMap));

    % 5. Controllo ROI per ogni tasto nella keyMap
    for i = 1:length(keyMap)
        bb = keyMap(i).BoundingBox; % [x y w h]

        % Clip verticale
        y0     = bb(2);
        h_clip = min(bb(4), max(0, analysis_rows - y0));
        if h_clip <= 0
            perKeyRatio(i) = 0;
            continue;
        end
        bb_clipped = [bb(1), y0, bb(3), h_clip];

        % Margine interno (opzione A)
        x_in   = bb_clipped(1) + ROI_MARGIN;
        y_in   = bb_clipped(2) + ROI_MARGIN;
        w_in   = max(1, bb_clipped(3) - 2*ROI_MARGIN);
        h_in   = max(1, bb_clipped(4) - 2*ROI_MARGIN);
        bb_inner = [x_in, y_in, w_in, h_in];

        if strcmp(keyMap(i).type, 'black')
            keyROI = imcrop(bwDiffBlack, bb_inner);
            pixelPercent = blackPixelPercent;
        else
            keyROI = imcrop(bwDiffWhite, bb_inner);
            pixelPercent = whitePixelPercent;
        end

        ratio = mean(keyROI(:));
        perKeyRatio(i) = ratio;
        if ratio > pixelPercent
            pressedNotes = [pressedNotes, i];
        end
    end

    if nargout >= 2
        debugInfo = struct( ...
            'diff',             abs(grayDiff), ...
            'bwWhite',          bwDiffWhite, ...
            'bwBlack',          bwDiffBlack, ...
            'perKeyRatio',      perKeyRatio, ...
            'analysisRows',     analysis_rows, ...
            'whiteDiffThresh',  whiteDiffThresh, ...
            'blackDiffThresh',  blackDiffThresh, ...
            'whitePixelPercent', whitePixelPercent, ...
            'blackPixelPercent', blackPixelPercent);
    end
end
