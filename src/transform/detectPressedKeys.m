function [pressedNotes, debugInfo] = detectPressedKeys(current_rect, background_rect, keyMap, skinMaskRect)
    % detectPressedKeys: Rileva i tasti premuti tramite differenza di frame.
    % Se skinMaskRect (logical, stesse dimensioni del frame rettificato) e'
    % fornita, i pixel di pelle vengono ignorati nella differenza, cosi' che
    % il dito stesso non venga contato come "tasto premuto".
    %
    % Output:
    %   pressedNotes - indici dei tasti premuti
    %   debugInfo    - struct con .diff (grayscale 0..255), .bwWhite, .bwBlack
    %                  e .perKeyRatio (vettore con la % di pixel "on" per tasto)
    %                  Utile per visualizzare lo stato interno del temporale.

    % 1. Calcolo della differenza
    % Convertiamo in grigio per velocizzare
    diffImg = abs(double(im2gray(current_rect)) - double(im2gray(background_rect)));

    % 1b. Azzera la diff sui pixel di pelle (se la maschera e' disponibile)
    if nargin >= 4 && ~isempty(skinMaskRect)
        diffImg(logical(skinMaskRect)) = 0;
    end

    % 2. Binarizzazione della differenza con soglie distinte per tipo
    % I tasti neri partono da luminanza bassa: il movimento del tasto
    % produce variazioni molto piu' piccole, quindi servono soglie piu'
    % permissive sia in luminanza sia in percentuale di pixel cambiati.
    % NB: la premuta finale e' spaziale AND temporale, quindi allentare il
    % temporale e' a basso rischio: un tasto diventa "premuto" solo se ha gia'
    % un dito candidato sopra. I bianchi venivano persi perche' il dito copre
    % la zona di contatto (azzerata dalla skin-mask) e il cambio bianco-su-bianco
    % e' piccolo, quindi soglie piu' permissive.
    whiteDiffThresh    = 30/255;   % abbassato da 50/255: premuta bianca = cambio luminanza piccolo
    blackDiffThresh    = 35/255;   % alzato da 25/255 per ridurre falsi positivi
    whitePixelPercent  = 0.04;     % abbassato da 0.10: il dito copre parte della ROI analizzata
    blackPixelPercent  = 0.15;

    bwDiffWhite = imbinarize(diffImg / 255, whiteDiffThresh);
    bwDiffBlack = imbinarize(diffImg / 255, blackDiffThresh);

    se = strel('disk', 2);
    bwDiffWhite = imopen(bwDiffWhite, se);
    bwDiffBlack = imopen(bwDiffBlack, se);

    % Usa solo il terzo superiore della tastiera per il calcolo del ratio.
    % In questa zona il dito entra a contatto con il tasto; le ombre del
    % palmo e i riflessi della mano si concentrano nella parte inferiore
    % e vengono cosi' esclusi dall'analisi.
    TOP_FRACTION  = 1/3;
    analysis_rows = floor(size(diffImg, 1) * TOP_FRACTION);

    pressedNotes = [];
    perKeyRatio = zeros(1, length(keyMap));

    % 3. Controllo ROI per ogni tasto nella keyMap
    for i = 1:length(keyMap)
        bb = keyMap(i).BoundingBox; % [x y w h]

        % Clip verticale: teniamo solo la parte del tasto che cade
        % nel terzo superiore della tastiera rettificata.
        y0     = bb(2);
        h_clip = min(bb(4), max(0, analysis_rows - y0));
        if h_clip <= 0
            perKeyRatio(i) = 0;
            continue;
        end
        bb_clipped = [bb(1), y0, bb(3), h_clip];

        if strcmp(keyMap(i).type, 'black')
            keyROI = imcrop(bwDiffBlack, bb_clipped);
            pixelPercent = blackPixelPercent;
        else
            keyROI = imcrop(bwDiffWhite, bb_clipped);
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
            'diff', diffImg, ...
            'bwWhite', bwDiffWhite, ...
            'bwBlack', bwDiffBlack, ...
            'perKeyRatio', perKeyRatio, ...
            'analysisRows', analysis_rows, ...
            'whiteDiffThresh', whiteDiffThresh, ...
            'blackDiffThresh', blackDiffThresh, ...
            'whitePixelPercent', whitePixelPercent, ...
            'blackPixelPercent', blackPixelPercent);
    end
end