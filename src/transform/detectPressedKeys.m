function [pressedNotes, debugInfo] = detectPressedKeys(current_rect, background_rect, keyMap, skinMaskRect, analysisRowsOverride, whiteDiffThresh, blackDiffThresh)
    % detectPressedKeys: Rileva i tasti premuti tramite differenza di frame.
    %
    % whiteDiffThresh / blackDiffThresh (opzionali): soglia di binarizzazione
    % dei canali diff, scalare [0..1] oppure MAPPA HxW della stessa taglia
    % dell'immagine rettificata. La mappa permette soglie diverse lungo la
    % tastiera (illuminazione/ombre non uniformi) a costo per-frame invariato:
    % il confronto elementwise costa quanto quello con scalare. Default:
    % 20/255 (bianchi) e 25/255 (neri), uniformi come in origine.
    %
    % Differenza per canale:
    %   - tasti BIANCHI: differenza con SEGNO, solo pixel SCURITI
    %     (il dito, piu' scuro del tasto bianco, lo copre → current < background
    %      → segnale = background - current > 0). Il segno evita che lo
    %      scurimento dei bordi di un nero premuto sporchi i bianchi adiacenti.
    %   - tasti NERI: differenza ASSOLUTA, schiarimento OR scurimento
    %     (|current - background|). Premendo un nero il segnale dominante non
    %      e' solo la pelle che lo SCHIARISCE (area piccola e stretta) ma anche
    %      l'OMBRA che lo SCURISCE (il tasto si abbassa, il dito proietta ombra,
    %      i bordi col bianco si scuriscono): col solo schiarimento si perdeva,
    %      ed e' il motivo per cui il canale bianco "vedeva" i neri meglio del
    %      canale nero. Combinando i due versi il nero si traccia molto meglio.
    %
    % Trade-off: l'abs riapre il rischio di cross-talk (lo scurimento di un
    % bianco premuto sui bordi di un nero adiacente). Lo arginiamo su due
    % fronti: (1) l'intersezione spaziale a valle (un nero si conferma solo se
    % una punta di dito gli sta sopra) e (2) blackPixelPercent piu' alto, cosi'
    % una sottile striscia di bleed sul bordo non basta a far scattare il nero.
    %
    % La skin mask viene applicata SOLO a diffForWhite: per i neri il segnale
    % di pressione E' (anche) la pelle che schiarisce il tasto, azzerarla
    % toglierebbe segnale utile. Per i bianchi serve invece a evitare che il
    % movimento della mano generi falsi scurimenti su bianchi adiacenti.
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

    % 2. Canale NERO: combinato schiarimento+scurimento = |current - background|.
    %    Cattura sia la pelle che schiarisce sia l'ombra che scurisce (vedi
    %    header). Calcolato sul grayDiff RAW, PRIMA che la skin mask lo azzeri
    %    sotto (per i neri la pelle e' segnale, non rumore).
    diffForBlack = abs(grayDiff) / 255;   % [0..1]

    % 3. Canale BIANCO: pelle su tasto bianco → area si SCURISCE (current < background)
    %    La skin mask viene applicata per evitare falsi positivi da movimento mano.
    if nargin >= 4 && ~isempty(skinMaskRect)
        grayDiff(logical(skinMaskRect)) = 0;
    end
    diffForWhite = max(0, -grayDiff) / 255;   % [0..1]

    if nargin < 6 || isempty(whiteDiffThresh), whiteDiffThresh = 20/255; end
    if nargin < 7 || isempty(blackDiffThresh), blackDiffThresh = 25/255; end
    whitePixelPercent = 0.10;
    % Guardia anti-cross-talk: col canale nero ora in abs entra piu' segnale
    % (anche lo scurimento), quindi alziamo la frazione d'area richiesta da
    % 0.15 a 0.20. Una striscia sottile di bleed dal bordo di un bianco premuto
    % non raggiunge il 20% della ROI nera; una pressione vera (pelle + ombra) si'.
    blackPixelPercent = 0.20;

    % Il confronto elementwise vale sia per soglia scalare sia per mappa HxW
    % (equivale a imbinarize nel caso scalare).
    bwDiffWhite = diffForWhite > whiteDiffThresh;
    bwDiffBlack = diffForBlack > blackDiffThresh;

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
