function reprojection = compute_reprojection_error(H, planePoints, imagePoints)
%COMPUTE_REPROJECTION_ERROR Measure point reprojection error in pixels.

projectedPoints = apply_homography(H, planePoints);
errors = sqrt(sum((projectedPoints - imagePoints) .^ 2, 2));

reprojection = struct();
reprojection.projectedPointsPx = projectedPoints;
reprojection.errorsPx = errors;
reprojection.meanPixels = mean(errors);
reprojection.maxPixels = max(errors);
end
