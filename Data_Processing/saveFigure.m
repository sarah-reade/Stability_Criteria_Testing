function saveFigure(fig, outDir, filename, fscsvFilename, imucsvFilename)
%SAVEFIGURE Add title and save figure as .fig and .svg.
    if nargin > 3
        sgtitle(fig, sprintf('Sensor data: %s | %s', ...
            fscsvFilename, imucsvFilename), ...
            'Interpreter', 'none');
    end

    % Maximise the figure so the exported image matches the on-screen view.
    set(fig, 'Units', 'normalized', 'OuterPosition', [0 0 0.9 1]);

    savefig(fig, fullfile(outDir, filename + ".fig"));
    print(fig, fullfile(outDir, filename + ".svg"), "-dsvg");
end