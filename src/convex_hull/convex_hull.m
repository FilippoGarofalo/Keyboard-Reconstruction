% =========================================================================
% PHASE 1: VIDEO SETUP & WINDOW INITIALIZATION
% =========================================================================
video_obj = VideoReader('assets/test_piano.mp4'); 
first_frame = readFrame(video_obj);
height = size(first_frame, 1);
width = size(first_frame, 2);
close all; 

% --- WINDOW 1: The Filtered Map ---
fig1 = figure('Name', 'Window 1: Filtered Map', 'WindowStyle', 'normal');
% Create explicit Axes handles to prevent focus-stealing in the loop
ax1 = axes('Parent', fig1);
img_handle1 = imshow(zeros(height, width, 'logical'), 'Parent', ax1); 
title(ax1, 'Filtered Map (Solid Mask)');

% --- WINDOW 2: The Convex Hulls ---
fig2 = figure('Name', 'Window 2: Dual Convex Hulls', 'WindowStyle', 'normal');
ax2 = axes('Parent', fig2);
img_handle2 = imshow(first_frame, 'Parent', ax2);
hold(ax2, 'on');
title(ax2, 'Dual Convex Hulls');

% --- WINDOW 3: The Fingertips & Fallback ---
fig3 = figure('Name', 'Window 3: Detected Fingertips', 'WindowStyle', 'normal');
ax3 = axes('Parent', fig3);
img_handle3 = imshow(first_frame, 'Parent', ax3);
hold(ax3, 'on');
title(ax3, 'Detected Fingertips (Red) & Fallback Keys (Blue)');

video_obj.CurrentTime = 0; 

% =========================================================================
% PHASE 2: THE VIDEO PROCESSING LOOP
% =========================================================================
disp('Processing Video... Press CTRL+C to stop early.');
while hasFrame(video_obj)
    
    img_RGB = readFrame(video_obj);
    img_YCbCr = rgb2ycbcr(img_RGB);
    Cb = img_YCbCr(:, :, 2); 
    Cr = img_YCbCr(:, :, 3); 
    
    skin_mask = (Cb >= 100 & Cb <= 150) & (Cr >= 150 & Cr <= 200);
    se = strel('disk', 5); 
    solid_mask = imclose(skin_mask, se);
    solid_mask = imfill(solid_mask, 'holes');
    solid_mask = bwareaopen(solid_mask, 50); 
    
    % --- UPDATE WINDOW VISUALS ---
    set(img_handle1, 'CData', solid_mask);
    set(img_handle2, 'CData', img_RGB);
    set(img_handle3, 'CData', img_RGB);
    
    % Clear drawings from the PREVIOUS frame using the specific axes
    delete(findobj(ax2, 'Type', 'Line'));
    delete(findobj(ax3, 'Type', 'Line'));
    
    % =====================================================================
    % PHASE 3: CONVEX HULL & FINGERTIP EXTRACTION 
    % =====================================================================
    [y_img, x_img] = find(solid_mask);
    
    if isempty(x_img)
        drawnow limitrate;
        continue;
    end
    
    % --- THE MEMORY FIX ---
    % Forcefully wipe the variables from the previous frame to prevent 
    % ghost tracking and alternating frames.
    clear center_left center_right left_pts right_pts; 
    
    % 8. 1D Clustering (Perfectly Separates Hands)
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
    
    % 9. Compute the Graham Scan
    for h = 1:2
        points = hand_points{h};
        if isempty(points) || size(points, 1) < 3; continue; end
        
        x = points(:, 1);
        y = points(:, 2);
        
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
        hull_x(end+1) = hull_x(1); 
        hull_y(end+1) = hull_y(1);
        hull_y_img = -hull_y; 
        
        % --- DRAW TO WINDOW 2 (HULLS) ---
        % Target ax2 directly to prevent window flickering
        plot(ax2, hull_x, hull_y_img, 'g-', 'LineWidth', 2);
        
        % 10. Extract Convex Fingertips (Robust Median + Clustering)
        raw_tip_x = [];
        raw_tip_y_img = [];
        robust_mid_y = median(y); 
        
        % First, gather ALL the corners in the top half of the hand
        for j = 1:(length(hull_y) - 1)
            if hull_y(j) > robust_mid_y
                raw_tip_x(end+1) = hull_x(j);
                raw_tip_y_img(end+1) = -hull_y(j); 
            end
        end
        
        % Next, filter out the micro-clusters so we only get 1 star per finger
        final_tip_x = [];
        final_tip_y_img = [];
        min_dist = 20; % 20 pixels is small enough to keep curled fingers separate, 
                       % but large enough to merge multiple stars on the same tip.
        
        for k = 1:length(raw_tip_x)
            is_new = true;
            for m = 1:length(final_tip_x)
                % Measure the distance between the current corner and our saved stars
                dist = sqrt((raw_tip_x(k) - final_tip_x(m))^2 + (raw_tip_y_img(k) - final_tip_y_img(m))^2);
                
                % If it is too close to a star we already placed, ignore it
                if dist < min_dist
                    is_new = false; 
                    break; 
                end
            end
            
            % If it passed the distance check, save it as an official fingertip
            if is_new
                final_tip_x(end+1) = raw_tip_x(k);
                final_tip_y_img(end+1) = raw_tip_y_img(k);
            end
        end
        
        % --- DRAW TO WINDOW 3 (FINGERTIPS) ---
        plot(ax3, final_tip_x, final_tip_y_img, 'r*', 'MarkerSize', 12, 'LineWidth', 2);
    end
    
    % =====================================================================
    % PHASE 4: THE PIXEL-DENSITY FALLBACK (For the hidden fingers)
    % =====================================================================
    key_poly_x = [100, 150, 150, 100]; 
    key_poly_y = [200, 200, 400, 400]; 
    pixel_count_threshold = 400; 
    
    key_mask = poly2mask(key_poly_x, key_poly_y, height, width);
    skin_on_key = solid_mask & key_mask;
    total_skin_pixels = sum(skin_on_key, 'all');
    
    if total_skin_pixels > pixel_count_threshold
        plot(ax3, 125, 300, 'bo', 'MarkerSize', 15, 'LineWidth', 2); 
    end
    
    % Flush all the background drawings to the screen at once
    drawnow limitrate;
end
disp('Video processing complete.');

