function pressedKeys = confirmPressedKeys(currFrame, refFrame, candidateKeys, handMask, threshold)
    % CONFIRMPRESSEDKEYS Implementazione della verifica temporale pesata.
    
    % 1. Pre-processing: Differenza in scala di grigi [cite: 79]
    currGray = double(rgb2gray(currFrame));
    refGray = double(refFrame); % Assumiamo sia già grigio e double
    diffMap = abs(currGray - refGray); % D(i,j) della formula 

    pressedKeys = []; 

    for k = 1:length(candidateKeys)
        % Estrazione della ROI del tasto corrente
        roi = candidateKeys(k).roi; % [x y width height]
        D_sub = imcrop(diffMap, roi);
        H_sub = imcrop(handMask, roi);
        
        D_sub = D_sub .* double(candidateKeys(k).mask);
        [rows, cols] = size(D_sub);
        W = ones(rows, cols); % Peso unitario di base (Peso 1) [cite: 98]

        % 2. Identificazione dei bordi per i pesi extra
        % Peso 15: Confine orizzontale a 90mm [cite: 94, 95]
        horizLine = candidateKeys(k).horizBoundaryPixel; 
        lineRange = max(1, horizLine-2):min(rows, horizLine+2);
        W(lineRange, :) = 15; 

        % Peso 5: Bordi laterali tramite Canny [cite: 96]
        % Questo cattura le ombre tra i tasti adiacenti
        edgeMask = edge(D_sub, 'Canny');
        W(edgeMask) = 5;

        % 3. Esclusione dei pixel della mano [cite: 98]
        % Azzeriamo il peso dove Filippo rileva la mano (evita falsi positivi)
        W(H_sub > 0) = 0;

        % 4. Calcolo della Media Pesata (Formula 3.2.2) 
        % Mu_w = sum(D * W) / sum(W)
        weightedSignal = sum(D_sub(:) .* W(:));
        totalWeight = sum(W(:));

        if totalWeight > 0
            mu_w = weightedSignal / totalWeight;
        else
            mu_w = 0;
        end

        % 5. Decisione finale 
        if mu_w > threshold
            pressedKeys = [pressedKeys; candidateKeys(k).id];
        end
    end
end