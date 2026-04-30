function fingertips = getFingers(img_RGB)
    % GETFINGERS Detects convex fingertip coordinates from a single frame.
    %
    % Inputs:
    %   img_RGB    - A single image frame (Height x Width x 3 matrix)
    %
    % Outputs:
    %   fingertips - An N x 2 matrix of [x, y] coordinates representing 
    %                the detected fingertips (the "red points").

    % Initialize the output matrix
    fingertips = []; 
    
    % =====================================================================
    % PHASE 1: SKIN SEGMENTATION & MASKING
    % =====================================================================
    img_YCbCr = rgb2ycbcr(img_RGB);
    Cb = img_YCbCr(:, :, 2); 
    Cr = img_YCbCr(:, :, 3); 
    
    skin_mask = (Cb >= 100 & Cb <= 150) & (Cr >= 150 & Cr <= 200);
    se = strel('disk', 5); 
    solid_mask = imclose(skin_mask, se);
    solid_mask = imfill(solid_mask, 'holes');
    solid_mask = bwareaopen(solid_mask, 50); 
    
    [y_img, x_img] = find(solid_mask);
    
    if isempty(x_img)
        return; % Exit early and return empty array if no skin is found
    end
    
    % =====================================================================
    % PHASE 2: 1D CLUSTERING (HAND SEPARATION)
    % =====================================================================
    split_threshold = mean(x_img); 
    for iter = 1:10
        left_pts = x_img(x_img <= split_threshold);
        right_pts = x_img(x_img > split_threshold);
        if isempty(left_pts) || isempty(right_pts); break; end
        
        center_left = mean(left_pts);
        center_right = mean(right_pts);
        new_threshold = (center_left + center_right) / 2;
        if abs(split_threshold - new_threshold) < 0.5; break; end
        split_threshold = new_threshold;
    end
    
    % Determine if we are tracking one or two hands
    if exist('center_left', 'var') && exist('center_right', 'var') && (center_right - center_left > 100)
        left_hand_idx = x_img <= split_threshold;
        right_hand_idx = x_img > split_threshold;
        hand_points = { ...
            [x_img(left_hand_idx), -y_img(left_hand_idx)], ... 
            [x_img(right_hand_idx), -y_img(right_hand_idx)] ... 
        };
    else
        hand_points = {[x_img, -y_img], []};
    end
    
    % =====================================================================
    % PHASE 3: CONVEX HULL & FINGERTIP EXTRACTION
    % =====================================================================
    for h = 1:2
        points = hand_points{h};
        if isempty(points) || size(points, 1) < 3; continue; end
        
        x = points(:, 1);
        y = points(:, 2);
        
        % 1. Setup the Anchor Point for Graham Scan
        [~, min_y_idx] = min(y);
        bottom_points = find(y == y(min_y_idx));
        [~, min_x_idx] = min(x(bottom_points));
        anchor_idx = bottom_points(min_x_idx);
        
        anchor_x = x(anchor_idx);
        anchor_y = y(anchor_idx);
        
        angles = atan2(y - anchor_y, x - anchor_x);
        distances = (x - anchor_x).^2 + (y - anchor_y).^2;
        [~, sort_idx] = sortrows([angles, distances]);
        sorted_x = x(sort_idx);
        sorted_y = y(sort_idx);
        
        % 2. Build the Convex Hull 
        hull_x = zeros(length(sorted_x), 1);
        hull_y = zeros(length(sorted_y), 1);
        hull_x(1) = sorted_x(1);
        hull_y(1) = sorted_y(1);
        stack_size = 2;
        
        for i = 3:length(sorted_x)
            while stack_size >= 2
                p1_x = hull_x(stack_size-1); p1_y = hull_y(stack_size-1);
                p2_x = hull_x(stack_size);   p2_y = hull_y(stack_size);
                p3_x = sorted_x(i);          p3_y = sorted_y(i);
                
                cross_product = (p2_x - p1_x) * (p3_y - p1_y) - (p2_y - p1_y) * (p3_x - p1_x);
                if cross_product > 0; break; else; stack_size = stack_size - 1; end
            end
            stack_size = stack_size + 1;
            hull_x(stack_size) = sorted_x(i);
            hull_y(stack_size) = sorted_y(i);
        end
        
        hull_x = hull_x(1:stack_size);
        hull_y = hull_y(1:stack_size);
        
        % 3. Extract Convex Fingertips (Top Half of Hand)
        raw_tip_x = [];
        raw_tip_y_img = [];
        robust_mid_y = median(y); 
        
        for j = 1:length(hull_y)
            if hull_y(j) > robust_mid_y
                raw_tip_x(end+1) = hull_x(j);
                raw_tip_y_img(end+1) = -hull_y(j); 
            end
        end
        
        % 4. Density Clustering (Merge points closer than 20px)
        min_dist = 20; 
        
        for k = 1:length(raw_tip_x)
            is_new = true;
            for m = 1:size(fingertips, 1) % Compare against already saved tips
                dist = sqrt((raw_tip_x(k) - fingertips(m, 1))^2 + (raw_tip_y_img(k) - fingertips(m, 2))^2);
                
                if dist < min_dist
                    is_new = false; 
                    break; 
                end
            end
            
            % If it passed the distance check, save it to the output array
            if is_new
                fingertips = [fingertips; raw_tip_x(k), raw_tip_y_img(k)];
            end
        end
    end
end