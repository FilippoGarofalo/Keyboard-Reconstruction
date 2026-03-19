% =========================================================================
% PHASE 1: SKIN SEGMENTATION & CLEANUP
% =========================================================================

% 1. Load the Image
img_RGB = imread('assets/piano_player.jpg'); 

% 2. Convert to YCbCr Color Space
img_YCbCr = rgb2ycbcr(img_RGB);

% 3. Isolate the Chrominance Channels
Cb = img_YCbCr(:, :, 2); 
Cr = img_YCbCr(:, :, 3); 

% 4. Apply the Logical Thresholds (GIVEN)
skin_mask = (Cb >= 100 & Cb <= 150) & (Cr >= 150 & Cr <= 200);

% 5. Morphological Cleanup (The Filtered Map)
se = strel('disk', 5); 
solid_mask = imclose(skin_mask, se);
solid_mask = imfill(solid_mask, 'holes');
solid_mask = bwareaopen(solid_mask, 50); 

% =========================================================================
% PHASE 2: PREPARE THE PLOTS
% =========================================================================
close all; % This forcefully closes any lingering subplot windows

% --- WINDOW 1: The Filtered Map ---
fig1 = figure('Name', 'Window 1: Filtered Map', 'WindowStyle', 'normal');
imshow(solid_mask);
title('Filtered Map (Solid Mask)');

% --- WINDOW 2: The Convex Hulls ---
fig2 = figure('Name', 'Window 2: Dual Convex Hulls', 'WindowStyle', 'normal');
imshow(img_RGB);
hold on;
title('Dual Convex Hulls');

% --- WINDOW 3: The Fingertips ---
fig3 = figure('Name', 'Window 3: Detected Fingertips', 'WindowStyle', 'normal');
imshow(img_RGB);
hold on;
title('Detected Fingertips');

% =========================================================================
% PHASE 3: CONVEX HULL & FINGERTIP EXTRACTION
% =========================================================================

% 7. Extract the Point Cloud
[y_img, x_img] = find(solid_mask);

if isempty(x_img)
    disp('No skin detected in the frame.');
    return;
end

% 8. Mathematically Separate the Hands (Largest Gap Method)
unique_x = unique(x_img);
x_gaps = diff(unique_x);
[~, max_gap_idx] = max(x_gaps);

if ~isempty(max_gap_idx)
    split_threshold = unique_x(max_gap_idx);
else
    split_threshold = max(x_img); 
end

left_hand_idx = x_img <= split_threshold;
right_hand_idx = x_img > split_threshold;

hand_points = { ...
    [x_img(left_hand_idx), -y_img(left_hand_idx)], ... 
    [x_img(right_hand_idx), -y_img(right_hand_idx)]  ... 
};

% 9. Compute the Graham Scan and Fingertips for Each Hand
for h = 1:2
    points = hand_points{h};
    if isempty(points)
        continue;
    end
    
    x = points(:, 1);
    y = points(:, 2);
    
    % Find Anchor Point
    [~, min_y_idx] = min(y);
    bottom_points = find(y == y(min_y_idx));
    [~, min_x_idx] = min(x(bottom_points));
    anchor_idx = bottom_points(min_x_idx);
    
    anchor_x = x(anchor_idx);
    anchor_y = y(anchor_idx);
    
    % Calculate Polar Angles and Sort
    angles = atan2(y - anchor_y, x - anchor_x);
    distances = (x - anchor_x).^2 + (y - anchor_y).^2;
    [~, sort_idx] = sortrows([angles, distances]);
    sorted_x = x(sort_idx);
    sorted_y = y(sort_idx);
    
    % The Stack (Graham Scan)
    hull_x = zeros(length(sorted_x), 1);
    hull_y = zeros(length(sorted_y), 1);
    
    hull_x(1) = sorted_x(1);
    hull_y(1) = sorted_y(1);
    
    if length(sorted_x) > 1
        hull_x(2) = sorted_x(2);
        hull_y(2) = sorted_y(2);
        stack_size = 2;
    else
        stack_size = 1;
    end
    
    % Build the Hull using Cross Products
    for i = 3:length(sorted_x)
        while stack_size >= 2
            p1_x = hull_x(stack_size-1); p1_y = hull_y(stack_size-1);
            p2_x = hull_x(stack_size);   p2_y = hull_y(stack_size);
            p3_x = sorted_x(i);          p3_y = sorted_y(i);
            
            cross_product = (p2_x - p1_x) * (p3_y - p1_y) - (p2_y - p1_y) * (p3_x - p1_x);
            
            if cross_product > 0
                break;
            else
                stack_size = stack_size - 1; 
            end
        end
        stack_size = stack_size + 1;
        hull_x(stack_size) = sorted_x(i);
        hull_y(stack_size) = sorted_y(i);
    end
    
    % Finalize the Hull array size
    hull_x = hull_x(1:stack_size);
    hull_y = hull_y(1:stack_size);
    
    % Close the loop for drawing the hull outline
    hull_x(end+1) = hull_x(1); 
    hull_y(end+1) = hull_y(1);
    hull_y_img = -hull_y; % Convert full hull back to image space
    
    % --- RENDER ON WINDOW 2 (HULLS) ---
    % Bring Window 2 to the front and draw the hull
    figure(fig2); 
    plot(hull_x, hull_y_img, 'g-', 'LineWidth', 2);
    
    % 10. Extract Exactly 5 Fingertips (Spatial Clustering / Non-Maximum Suppression)
    num_hull_points = length(hull_y) - 1; 
    
    % Step A: Gather all candidates in the top half of the hand
    center_y = mean(y); 
    cand_x = [];
    cand_y_cart = [];
    cand_y_img = [];
    
    for j = 1:num_hull_points
        if hull_y(j) > center_y
            cand_x(end+1) = hull_x(j);
            cand_y_cart(end+1) = hull_y(j);
            cand_y_img(end+1) = -hull_y(j); 
        end
    end
    
    % Step B: Sort candidates by height (highest physical points first)
    [~, sort_idx] = sort(cand_y_cart, 'descend');
    sorted_cand_x = cand_x(sort_idx);
    sorted_cand_y_img = cand_y_img(sort_idx);
    
    % Step C: Filter out clusters to leave a maximum of 5 distinct fingertips
    fingertip_x = [];
    fingertip_y_img = [];
    min_finger_dist = 40; % Minimum pixel distance between fingers (adjust if needed)
    
    for k = 1:length(sorted_cand_x)
        % Assume this candidate is a valid new finger
        is_new_finger = true; 
        
        % Check its distance against all previously saved fingertips
        for m = 1:length(fingertip_x)
            dist = sqrt((sorted_cand_x(k) - fingertip_x(m))^2 + ...
                        (sorted_cand_y_img(k) - fingertip_y_img(m))^2);
            
            % If it's too close to an existing tip, it's just part of the same cluster
            if dist < min_finger_dist
                is_new_finger = false;
                break;
            end
        end
        
        % If it passed the distance check, save it!
        if is_new_finger
            fingertip_x(end+1) = sorted_cand_x(k);
            fingertip_y_img(end+1) = sorted_cand_y_img(k);
        end
        
        % Stop immediately once we have successfully isolated 5 fingers
        if length(fingertip_x) == 5
            break;
        end
    end
    
    % --- RENDER ON WINDOW 3 (FINGERTIPS) ---
    % Bring Window 3 to the front
    figure(fig3); 
    
    % ONLY plot the red stars for the detected fingertips (no green hull lines)
    plot(fingertip_x, fingertip_y_img, 'r*', 'MarkerSize', 12, 'LineWidth', 2);
end

% Release the holds
figure(fig2); hold off;
figure(fig3); hold off;