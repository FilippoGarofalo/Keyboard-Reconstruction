function [keyMap] = keysDetection(background_rect)
    rect_gray = im2gray(background_rect);
    [h, w] = size(rect_gray);
    
    % --- 1. DETECTION TASTI NERI (Ancore) ---
    y_sep = round(h * 0.65); % Punto dove finiscono i tasti neri
    upper_roi = imadjust(rect_gray(1:y_sep, :));
    bw = ~imbinarize(upper_roi, graythresh(upper_roi));
    bw = imopen(bw, strel('line', 20, 90));
    stats_black = regionprops(bw, 'BoundingBox', 'Area');
    stats_black = stats_black([stats_black.Area] > 200);
    
    % --- 2. COSTRUZIONE GRIGLIA CROMATICA ---
    % Ipotizziamo 21 tasti bianchi (3 ottave)
    num_white = 21;
    white_w = w / num_white;
    keyMap = struct('id', {}, 'roi', {}, 'type', {}, 'noteName', {}, 'mask', {}, 'vertices', {});
    
    % Generiamo i tasti bianchi come poligoni (incastro)
    for j = 1:num_white
        x_L = (j-1) * white_w;
        x_R = j * white_w;
        
        % Definiamo il poligono del tasto bianco (forma a "L" o "T")
        % Un tasto bianco è un rettangolo [x_L, 0, white_w, h] 
        % MENO le aree occupate dai tasti neri adiacenti.
        
        % Vertici semplificati per visualizzazione (poligono chiuso)
        v_x = [x_L, x_R, x_R, x_L];
        v_y = [0, 0, h, h];
        
        keyMap(j).id = j;
        keyMap(j).type = 'white';
        keyMap(j).roi = [x_L, 1, white_w, h-1]; % Rettangolo contenitore
        keyMap(j).vertices = [v_x' v_y'];
        
        % Creiamo una maschera binaria per il tasto (solo la parte "bianca")
        m = zeros(h, w);
        m = poly2mask(v_x, v_y, h, w);
        
        % SOTTRAZIONE: Rimuoviamo i tasti neri dalla maschera del bianco
        for k = 1:length(stats_black)
            bb = stats_black(k).BoundingBox;
            % Se il tasto nero cade dentro il range X del bianco, lo cancelliamo
            if bb(1) >= x_L - 5 && (bb(1) + bb(3)) <= x_R + 5
                m(round(bb(2)):round(bb(2)+bb(4)), round(bb(1)):round(bb(1)+bb(3))) = 0;
            end
        end
        keyMap(j).mask = imcrop(m, keyMap(j).roi);
        keyMap(j).noteName = 'White';
    end
    
    % Aggiungiamo i Tasti Neri (figure chiuse semplici)
    start_black = num_white + 1;
    for k = 1:length(stats_black)
        idx = start_black + k - 1;
        bb = stats_black(k).BoundingBox;
        keyMap(idx).id = idx;
        keyMap(idx).type = 'black';
        keyMap(idx).roi = bb;
        keyMap(idx).mask = ones(round(bb(4)+1), round(bb(3)+1));
        keyMap(idx).noteName = 'Black';
        % Vertici per il disegno
        keyMap(idx).vertices = [bb(1), bb(2); bb(1)+bb(3), bb(2); ...
                                bb(1)+bb(3), bb(2)+bb(4); bb(1), bb(2)+bb(4)];
    end
end