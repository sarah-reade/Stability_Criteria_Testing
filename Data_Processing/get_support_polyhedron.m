function support_polyhedron = get_support_polyhedron(params, visualise)

    if nargin < 2
        visualise = false;
    end

    thickness = 0.1; % artificial thickness (m)

    points = generateContactPatchPoints(params,64);

    support_polyhedron.points = points;

    % Centre points
    centre = mean(points,1);
    centred = points - centre;

    rankP = rank(centred);


    switch rankP

        case 0
            % Point -> small cube
            eps = thickness;

            points3D = [
                -1 -1 -1;
                 1 -1 -1;
                 1  1 -1;
                -1  1 -1;
                -1 -1  1;
                 1 -1  1;
                 1  1  1;
                -1  1  1
            ]*eps + centre;


        case 1
            % Line -> thin cylinder-like prism
            [~,~,V] = svd(centred,'econ');

            d = V(:,1);

            t = centred*d;

            p1 = centre + min(t)*d';
            p2 = centre + max(t)*d';

            % Construct small square cross-section
            n1 = V(:,2);
            n2 = V(:,3);

            points3D = [
                p1 + thickness*( n1+n2)';
                p1 + thickness*(-n1+n2)';
                p1 + thickness*(-n1-n2)';
                p1 + thickness*( n1-n2)';
                p2 + thickness*( n1+n2)';
                p2 + thickness*(-n1+n2)';
                p2 + thickness*(-n1-n2)';
                p2 + thickness*( n1-n2)'
            ];


        case 2
            % Plane -> thin prism

            [~,~,V] = svd(centred,'econ');

            normal = V(:,3);

            offset = thickness * normal';

            upper = points + offset;
            lower = points - offset;

            points3D = [
                upper;
                lower
            ];


        case 3
            % Already 3D
            [~,S,V] = svd(centred,'econ');
            s = diag(S);

            if s(3) < 1e-3*s(1)

                % Planar contact patch
                normal = V(:,3)';

                offset = 0.5*thickness*normal;

                points3D = [
                    points + offset;
                    points - offset
                ];

            else

                % Genuine 3D support region
                points3D = points;

            end

    end


    % Compute final 3D hull

    [faces, volume] = convhulln(points3D);

    hullVertexIDs = unique(faces(:));

    vertices = points3D(hullVertexIDs,:);

    % Remap face indices
    [~,newIndex] = ismember(faces,hullVertexIDs);
    
    support_polyhedron.faces = newIndex;
    support_polyhedron.vertices = vertices;
    support_polyhedron.volume = volume;
    support_polyhedron.points = points3D;
    support_polyhedron.type = rankP;

    if visualise
        visualize_support_polyhedron(params,support_polyhedron)
    end
    
end


function contactPoints = generateContactPatchPoints(parameters,N)

    if nargin < 2
        N = 32; % number of points around each contact
    end

    contactPoints = [];

    theta = linspace(0,2*pi,N);

    for i = 1:length(parameters.trans)

        p = parameters.trans{i};

        G = parameters.G{i};
        R = G(1:3,1:3);

        r = parameters.r;

        for k = 1:length(theta)

            localPoint = [
                r*cos(theta(k));
                r*sin(theta(k));
                0
            ];

            worldPoint = p + R*localPoint;

            contactPoints(end+1,:) = worldPoint';

        end

    end
end


function visualize_support_polyhedron(params, support_polyhedron)

    figure;
    hold on;
    grid on;
    axis equal;
    view(3);

    xlabel('X (m)')
    ylabel('Y (m)')
    zlabel('Z (m)')
    title('Support Polyhedron Debug Visualisation')


    %% Plot convex hull

    if ~isempty(support_polyhedron.faces)
        trisurf(...
            support_polyhedron.faces,...
            support_polyhedron.vertices(:,1),...
            support_polyhedron.vertices(:,2),...
            support_polyhedron.vertices(:,3),...
            'FaceAlpha',0.3,...
            'EdgeColor','k');

    end


    %% Plot sampled contact patch points

    if isfield(support_polyhedron,'points')

        scatter3(...
            support_polyhedron.points(:,1),...
            support_polyhedron.points(:,2),...
            support_polyhedron.points(:,3),...
            15,...
            'filled');

    end


    %% Plot contact centres and frames

    for i = 1:length(params.trans)

        p = params.trans{i};

        % Contact centre
        scatter3(...
            p(1),p(2),p(3),...
            100,...
            'filled',...
            'MarkerEdgeColor','k');


        % Contact frame
        R = params.G{i}(1:3,1:3);

        frameScale = params.r*0.75;

        quiver3(...
            p(1),p(2),p(3),...
            R(1,1)*frameScale,...
            R(2,1)*frameScale,...
            R(3,1)*frameScale,...
            0,...
            'LineWidth',2);

        quiver3(...
            p(1),p(2),p(3),...
            R(1,2)*frameScale,...
            R(2,2)*frameScale,...
            R(3,2)*frameScale,...
            0,...
            'LineWidth',2);

        quiver3(...
            p(1),p(2),p(3),...
            R(1,3)*frameScale,...
            R(2,3)*frameScale,...
            R(3,3)*frameScale,...
            0,...
            'LineWidth',2);


        % Contact normal
        normal = R(:,3);

        quiver3(...
            p(1),p(2),p(3),...
            normal(1)*params.r,...
            normal(2)*params.r,...
            normal(3)*params.r,...
            0,...
            'LineWidth',3);

        text(...
            p(1),p(2),p(3),...
            sprintf(' C%d',i));

    end


    %% Sensor frame

    plot3(0,0,0,...
        'ko',...
        'MarkerSize',10,...
        'MarkerFaceColor','k');

    text(0,0,0,' Sensor');


    %% Nice limits

    allPoints = support_polyhedron.points;

    maxRange = max(max(allPoints)-min(allPoints));

    center = mean(allPoints);

    xlim(center(1)+[-1 1]*maxRange);
    ylim(center(2)+[-1 1]*maxRange);
    zlim(center(3)+[-1 1]*maxRange);


    legend('Support hull',...
           'Contact samples',...
           'Contact centre');

end