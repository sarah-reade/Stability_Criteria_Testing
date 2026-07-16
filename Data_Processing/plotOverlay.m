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


function plotMotionPoints(ax,motionTimepoints)
    if ~isempty(motionTimepoints)
        xl = xline(ax, motionTimepoints.Time, '--r', 'LineWidth', 1);
        xe = xline(ax, motionTimepoints.EndTime, '--b', 'LineWidth', 1);
        set(xl, 'HandleVisibility', 'off');
        set(xe, 'HandleVisibility', 'off');
    end
end