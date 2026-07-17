function plotOverlay(axs,motionTimepoints,negTimeSegments)

    %axs = findall(fig, 'Type', 'axes');
    
    for axisIdx = 1:numel(axs)
        % if axs(axisIdx) == infoAx
        %     continue
        % end
        
        plotMotionPoints(axs(axisIdx),motionTimepoints);
        plot_background(axs(axisIdx),negTimeSegments);
    end
end

function plot_background(ax,negTimeSegments)
    yl = ylim(ax);
    
    hold(ax, 'on');
    
    for i = 1:size(negTimeSegments,1)
        x1 = negTimeSegments(i,1);
        x2 = negTimeSegments(i,2);
    
        patch(ax, ...
            [x1 x2 x2 x1], ...
            [yl(1) yl(1) yl(2) yl(2)], ...
            'r', ...
            'FaceAlpha', 0.15, ...
            'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    
    uistack(ax.Children, 'bottom'); % keep shading behind lines
end


function plotMotionPoints(ax, timestamps)

    % Plot movement timestamps (lighter)
    if ~isempty(timestamps.movementTimestamps)
        xl = xline(ax, timestamps.movementTimestamps.Time, '--', ...
            'Color', [1.0, 0.6, 0.6], 'LineWidth', 1);
        xe = xline(ax, timestamps.movementTimestamps.EndTime, '--', ...
            'Color', [0.6, 0.8, 1.0], 'LineWidth', 1);

        set(xl, 'HandleVisibility', 'off');
        set(xe, 'HandleVisibility', 'off');
    end

    % Plot detachment timestamps (stronger)
    if ~isempty(timestamps.detachTimestamps)
        xl = xline(ax, timestamps.detachTimestamps.Time, '--r', ...
            'LineWidth', 1.5);
        xe = xline(ax, timestamps.detachTimestamps.EndTime, '--b', ...
            'LineWidth', 1.5);

        set(xl, 'HandleVisibility', 'off');
        set(xe, 'HandleVisibility', 'off');
    end

end