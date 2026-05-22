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
    whiteDiffThresh    = 50/255;
    blackDiffThresh    = 35/255;   % alzato da 25/255 per ridurre falsi positivi
    whitePixelPercent  = 0.15;
    blackPixelPercent  = 0.10;     % alzato da 0.07 per ridurre falsi positivi

    bwDiffWhite = imbinarize(diffImg / 255, whiteDiffThresh);
    bwDiffBlack = imbinarize(diffImg / 255, blackDiffThresh);

    se = strel('disk', 2);
    bwDiffWhite = imopen(bwDiffWhite, se);
    bwDiffBlack = imopen(bwDiffBlack, se);

    pressedNotes = [];
    perKeyRatio = zeros(1, length(keyMap));

    % 3. Controllo ROI per ogni tasto nella keyMap
    for i = 1:length(keyMap)
        bb = keyMap(i).BoundingBox;

        if strcmp(keyMap(i).type, 'black')
            keyROI = imcrop(bwDiffBlack, bb);
            pixelPercent = blackPixelPercent;
        else
            keyROI = imcrop(bwDiffWhite, bb);
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
            'whiteDiffThresh', whiteDiffThresh, ...
            'blackDiffThresh', blackDiffThresh, ...
            'whitePixelPercent', whitePixelPercent, ...
            'blackPixelPercent', blackPixelPercent);
    end
end