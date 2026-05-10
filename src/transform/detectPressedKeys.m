function [pressedNotes] = detectPressedKeys(current_rect, background_rect, keyMap)
    % detectPressedKeys: Rileva i tasti premuti tramite differenza di frame
    
    % 1. Calcolo della differenza
    % Convertiamo in grigio per velocizzare
    diffImg = abs(double(im2gray(current_rect)) - double(im2gray(background_rect)));
    
    % 2. Binarizzazione della differenza
    % Usiamo una soglia manuale (es. 50/255) per rilevare solo cambiamenti netti
    bwDiff = imbinarize(diffImg / 255, 50/255);
    
    % Pulizia per eliminare piccoli rumori
    bwDiff = imopen(bwDiff, strel('disk', 2));
    
    pressedNotes = [];
    
    % 3. Controllo ROI per ogni tasto nella keyMap
    % (Assumiamo che keyMap contenga i BoundingBox dei tasti)
    for i = 1:length(keyMap)
        bb = keyMap(i).BoundingBox;
        
        % Estraiamo la porzione di differenza corrispondente al tasto
        keyROI = imcrop(bwDiff, bb);
        
        % Se più del 15% dei pixel nel ROI è cambiato, il tasto è PREMUTO
        if mean(keyROI(:)) > 0.15
            pressedNotes = [pressedNotes, i]; % Salviamo l'indice del tasto
        end
    end
end