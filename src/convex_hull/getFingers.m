function [fingertips, skin_mask] = getFingers(img_RGB, motion_mask, tipMaxAngleDeg)
    % GETFINGERS Detects convex fingertip coordinates from a single frame.
    %
    % Inputs:
    %   img_RGB        - Frame to process (H x W x 3).
    %   motion_mask    - (Optional) Logical H x W mask of moving pixels. 
    %                    Enforces the constraint: hands move, keys do not.
    %   tipMaxAngleDeg - (Optional, default 65) k-curvature threshold. 
    %                    Discards straight finger edges (~180 deg) to isolate 
    %                    sharp protruding fingertips (~30-60 deg).
    %
    % Outputs:
    %   fingertips - N x 2 matrix of [x, y] coordinates (physical apex of tips).
    %   skin_mask  - Logical H x W mask of skin pixels (post morphology).

    if nargin < 3 || isempty(tipMaxAngleDeg)
        tipMaxAngleDeg = 65;
    end

    fingertips = [];
    skin_mask = false(size(img_RGB, 1), size(img_RGB, 2));
    
    % =====================================================================
    % PHASE 1: SKIN SEGMENTATION & MASKING
    % =====================================================================
    img_YCbCr = rgb2ycbcr(img_RGB);
    Y  = img_YCbCr(:, :, 1);
    Cb = img_YCbCr(:, :, 2); 
    Cr = img_YCbCr(:, :, 3); 
    
    raw_skin = (Y >= 100 & Y <= 235) & (Cb >= 85 & Cb <= 135) & (Cr >= 135 & Cr <= 180);

    % Intersect skin with motion mask to reject static ivory keys.
    if nargin >= 2 && ~isempty(motion_mask)
        raw_skin = raw_skin & logical(motion_mask);
    end

    % Morphological operations: close gaps, fill holes, drop noise < 50px.
    se = strel('disk', 5);
    solid_mask = imclose(raw_skin, se);
    solid_mask = imfill(solid_mask, 'holes');
    solid_mask = bwareaopen(solid_mask, 50);

    skin_mask = solid_mask;

    if ~any(solid_mask(:))
        return;
    end

    % =====================================================================
    % PHASE 2: HAND SEPARATION VIA CONNECTED COMPONENTS
    % =====================================================================
    % Apply Connected Component Labeling (CCL) to isolate blobs.
    CC    = bwconncomp(solid_mask);
    stats = regionprops(CC, 'Area', 'PixelIdxList');
    if isempty(stats)
        return;
    end
    areas = [stats.Area];
    [~, order] = sort(areas, 'descend');

    MIN_HAND_AREA = 1000; 
    MAX_HANDS     = 2;    
    REL_HAND_FRAC = 0.4;  

    % Adaptive area floor: keeps a true second hand, rejects distant reflections.
    area_floor = max(MIN_HAND_AREA, REL_HAND_FRAC * areas(order(1)));

    hand_points = {};
    for h = 1:numel(order)
        if numel(hand_points) >= MAX_HANDS || areas(order(h)) < area_floor
            break; 
        end
        [hy, hx] = ind2sub(size(solid_mask), stats(order(h)).PixelIdxList);
        hand_points{end+1} = [hx(:), -hy(:)];
    end
    
    % =====================================================================
    % PHASE 3: CONVEX HULL & FINGERTIP EXTRACTION
    % =====================================================================
    for h = 1:numel(hand_points)
        points = hand_points{h};
        if isempty(points) || size(points, 1) < 3; continue; end
        
        x = points(:, 1);
        y = points(:, 2);
        
        % 1. Anchor Point & Radar Sweep (Graham Scan)
        % Find lowest geometric pixel (min y). Break ties with min x.
        [~, min_y_idx] = min(y);
        bottom_points = find(y == y(min_y_idx));
        [~, min_x_idx] = min(x(bottom_points));
        anchor_idx = bottom_points(min_x_idx);
        
        anchor_x = x(anchor_idx);
        anchor_y = y(anchor_idx);
        
        % Sort remaining pixels by polar angle for a counter-clockwise sweep.
        angles = atan2(y - anchor_y, x - anchor_x);
        distances = (x - anchor_x).^2 + (y - anchor_y).^2;
        [~, sort_idx] = sortrows([angles, distances]);
        sorted_x = x(sort_idx);
        sorted_y = y(sort_idx);
        
        % 2. The Stack & Orientation Test
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
                
                % 2D cross product. CP > 0 is a convex left turn. 
                % CP <= 0 is a concavity (right turn) and gets popped off.
                cross_product = (p2_x - p1_x) * (p3_y - p1_y) - (p2_y - p1_y) * (p3_x - p1_x);
                if cross_product > 0; break; else; stack_size = stack_size - 1; end
            end
            stack_size = stack_size + 1;
            hull_x(stack_size) = sorted_x(i);
            hull_y(stack_size) = sorted_y(i);
        end
        
        hull_x = hull_x(1:stack_size);
        hull_y = hull_y(1:stack_size);
        
        % 3. Anatomical Filtering (Horizontal Bisector & k-curvature)
        raw_tip_x = [];
        raw_tip_y_img = [];
        robust_mid_y = median(y);

        for j = 1:length(hull_y)
            % Discard wrist/palm (below median y-coordinate)
            if hull_y(j) <= robust_mid_y
                continue;
            end
            
            % Discard straight finger edges
            if hull_vertex_angle(hull_x, hull_y, j) > tipMaxAngleDeg
                continue;
            end
            raw_tip_x(end+1) = hull_x(j);
            raw_tip_y_img(end+1) = -hull_y(j);
        end
        
        % 4. Anatomical Filtering (Density Clustering)
        min_dist        = 35; 
        boundary_margin = 20; 
        img_w = size(img_RGB, 2);
        img_h = size(img_RGB, 1);

        for k = 1:length(raw_tip_x)
            tx = raw_tip_x(k);
            ty = raw_tip_y_img(k);
            
            % Discard artificial hull corners caused by frame borders
            if tx < boundary_margin || tx > img_w - boundary_margin || ...
               ty < boundary_margin || ty > img_h - boundary_margin
                continue;
            end

            is_new = true;
            for m = 1:size(fingertips, 1)
                dist = sqrt((tx - fingertips(m, 1))^2 + (ty - fingertips(m, 2))^2);
                
                % Merge clustered vertices on the same tip (< 35px)
                if dist < min_dist
                    is_new = false;
                    
                    % Retain the candidate with minimum y-value to log the true physical apex
                    if ty < fingertips(m, 2)
                        fingertips(m, :) = [tx, ty];
                    end
                    break;
                end
            end

            if is_new
                fingertips = [fingertips; tx, ty];
            end
        end
    end
end

function ang = hull_vertex_angle(hx, hy, j)
    % Calculates angle (degrees) at vertex j to filter ~180 deg straight edges.
    NEIGH_DIST = 15; 
    n = numel(hx);
    px = hx(j); py = hy(j);

    prev = j;
    for s = 1:n-1
        cand = mod(j - 1 - s, n) + 1;
        if hypot(hx(cand) - px, hy(cand) - py) >= NEIGH_DIST
            prev = cand;
            break;
        end
    end
    nxt = j;
    for s = 1:n-1
        cand = mod(j - 1 + s, n) + 1;
        if hypot(hx(cand) - px, hy(cand) - py) >= NEIGH_DIST
            nxt = cand;
            break;
        end
    end

    if prev == j || nxt == j
        ang = 180;
        return;
    end

    v1 = [hx(prev) - px, hy(prev) - py];
    v2 = [hx(nxt) - px, hy(nxt) - py];
    c  = dot(v1, v2) / (norm(v1) * norm(v2));
    ang = acosd(max(-1, min(1, c)));
end