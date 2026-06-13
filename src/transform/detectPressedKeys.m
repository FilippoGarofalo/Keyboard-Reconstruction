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
    %     (|current - background|), ma con la PELLE ESCLUSA. Il dito che copre
    %      il tasto non e' di per se' una pressione (potrebbe solo sfiorarlo),
    %      quindi la pelle non deve contare; il segnale che resta e' l'OMBRA di
    %      contatto e i bordi col bianco che si scuriscono (il tasto si abbassa,
    %      il dito proietta ombra), piu' specifici di una pressione reale.
    %
    % Normalizzazione (BIANCHI e NERI): il rapporto non e' calcolato sull'area
    % totale della ROI ma sulla sola area ESPOSTA (non-pelle) dentro la fascia di
    % analisi: ratio = (pixel cambiati non-pelle) / (pixel esposti). Cosi'
    % escludere la pelle non diluisce il rapporto su nessuno dei due tipi.
    % Guardia anti-rumore: se l'area esposta e' sotto MIN_EXPOSED_PX non si decide.
    %
    % Trade-off: l'abs riapre il rischio di cross-talk (lo scurimento di un
    % bianco premuto sui bordi di un nero adiacente). Lo arginiamo su due
    % fronti: (1) l'intersezione spaziale a valle (un nero si conferma solo se
    % una punta di dito gli sta sopra) e (2) blackPixelPercent, cosi'
    % una sottile striscia di bleed sul bordo non basta a far scattare il nero.
    %
    % La skin mask viene applicata a ENTRAMBI i canali: ai bianchi per evitare
    % falsi scurimenti dal movimento della mano, ai neri per misurare solo
    % l'area di tasto visibile (vedi sopra).
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
    MIN_EXPOSED_PX = 30;  % area esposta (non-pelle) minima di un tasto nella fascia
                          % per decidere: sotto questa il rapporto e' troppo
                          % rumoroso (pochi pixel) → ratio 0. Vale per bianchi e neri.

    % 1. Differenza con segno (NON abs)
    grayDiff = double(im2gray(current_rect)) - double(im2gray(background_rect));

    % Maschera di pelle (logica), riusata su entrambi i canali. Se non fornita,
    % maschera vuota (nessun pixel di pelle).
    if nargin >= 4 && ~isempty(skinMaskRect)
        skinMask = logical(skinMaskRect);
    else
        skinMask = false(size(grayDiff));
    end

    % 2. Canale NERO: combinato schiarimento+scurimento = |current - background|.
    %    La PELLE verra' esclusa (sotto, dopo l'imopen): il dito che copre il
    %    tasto non e' di per se' una pressione, conta solo l'ombra di contatto.
    diffForBlack = abs(grayDiff) / 255;   % [0..1]

    % 3. Canale BIANCO: pelle su tasto bianco → area si SCURISCE (current < background)
    %    La skin mask viene applicata per evitare falsi positivi da movimento mano.
    grayDiff(skinMask) = 0;
    diffForWhite = max(0, -grayDiff) / 255;   % [0..1]

    if nargin < 6 || isempty(whiteDiffThresh), whiteDiffThresh = 20/255; end
    if nargin < 7 || isempty(blackDiffThresh), blackDiffThresh = 25/255; end
    whitePixelPercent = 0.10;
    % Guardia anti-cross-talk: col canale nero in abs entra piu' segnale
    % (anche lo scurimento) Una striscia sottile di bleed dal bordo di un bianco premuto
    % non raggiunge il 20% della ROI nera; una pressione vera si'.
    blackPixelPercent = 0.20;

    % Il confronto elementwise vale sia per soglia scalare sia per mappa HxW
    % (equivale a imbinarize nel caso scalare).
    bwDiffWhite = diffForWhite > whiteDiffThresh;
    bwDiffBlack = diffForBlack > blackDiffThresh;

    se = strel('disk', 2);
    bwDiffWhite = imopen(bwDiffWhite, se);
    bwDiffBlack = imopen(bwDiffBlack, se);

    % ENTRAMBI i canali senza pelle: il dito che copre il tasto non deve contare
    % come cambiamento. Resta l'ombra di contatto e i bordi scuriti, piu' specifici
    % di una pressione. La normalizzazione per-tasto (sotto) usa solo l'area esposta,
    % cosi' la pelle non diluisce il rapporto (vale per bianchi e neri).
    bwDiffWhite(skinMask) = false;
    bwDiffBlack(skinMask) = false;

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

        % Margine interno
        x_in   = bb_clipped(1) + ROI_MARGIN;
        y_in   = bb_clipped(2) + ROI_MARGIN;
        w_in   = max(1, bb_clipped(3) - 2*ROI_MARGIN);
        h_in   = max(1, bb_clipped(4) - 2*ROI_MARGIN);
        bb_inner = [x_in, y_in, w_in, h_in];

        % Selezione canale e soglia per tipo di tasto.
        if strcmp(keyMap(i).type, 'black')
            bwMap        = bwDiffBlack;
            pixelPercent = blackPixelPercent;
        else
            bwMap        = bwDiffWhite;
            pixelPercent = whitePixelPercent;
        end

        % Normalizzazione sull'area ESPOSTA (non-pelle) della fascia, per
        % ENTRAMBI i tipi. Numeratore = pixel cambiati (gia' senza pelle),
        % denominatore = pixel esposti. Cosi' la pelle non diluisce il rapporto:
        % misuriamo "di quel tasto visibile nella fascia, quanto e' cambiato".
        changedROI = imcrop(bwMap,     bb_inner);   % gia' senza pelle
        exposed    = ~imcrop(skinMask, bb_inner);   % area visibile del tasto
        nExposed   = nnz(exposed);
        if nExposed >= MIN_EXPOSED_PX
            ratio = nnz(changedROI) / nExposed;
        else
            ratio = 0;   % troppo pochi pixel esposti nella fascia: non decidere
        end

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
