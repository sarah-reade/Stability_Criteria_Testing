function [gamma,all_beta,loopTime] = ZML(parameters,wrench)
    
    visualise = false;

    tStart = tic;
    persistent cachedParameters cachedSupportPolyhedron callCount

    % Recompute only if parameters have changed
    if isempty(cachedParameters) || ~isequal(parameters, cachedParameters)
        cachedSupportPolyhedron = get_support_polyhedron(parameters,visualise);
        cachedParameters = parameters;
    end

    % Get support polyhedron relative to force sensor
    support_polyhedron = cachedSupportPolyhedron;
    
    % if 2D 
    if support_polyhedron.planar
        % Calculate ZMP
        zmp = calculate_ZMP(wrench,support_polyhedron.support_polygon.plane,visualise);
        % calculate distance from zmp to polygon
        [gamma,~] = distance_ZMP_to_polygon(...
            support_polyhedron,...
            zmp,visualise);
    % if 3D 
    else
        % Calculate the zero moment line
        zml = calculate_ZML(wrench,visualise);
    
        % Calculate the minimum distance between the edge of the polyhedron and the zml
        [gamma,~] = distance_ZML_to_polyhedron(...
            support_polyhedron,...
            zml,visualise);
    end

    loopTime = toc(tStart);
    

    if visualise
        if isempty(callCount)
            callCount = 0;
        end

        callCount = callCount + 1;

        visualiseEvery = 10;   % trigger every 10 calls

        if mod(callCount, visualiseEvery) == 0
            keyboard
        end
    end

    all_beta = get_beta(gamma,parameters);
end

function zml = calculate_ZML(wrench,visualise)

    % Calculate zero moment line relative to wrench reference point
    %
    % Input:
    %   wrench = [Fx Fy Fz Tx Ty Tz]'
    %
    % Output:
    %   zml.origin    - closest point on ZML to reference point
    %   zml.direction - ZML direction
    %   zml.point()   - function returning points on the line

    if nargin < 2
        visualise = false;
    end

    F = wrench(1:3);
    tau = wrench(4:6);


    if norm(F) < eps
        error('ZML undefined: resultant force is zero');
    end


    % Point on ZML closest to wrench reference point
    p0 = cross(F,tau)/(dot(F,F));


    % Line direction
    direction = F/norm(F);


    zml.origin = p0;
    zml.direction = direction;


    % Parametric line
    zml.point = @(lambda) p0 + lambda*direction;

    if visualise
        visualize_ZML(zml);
    end

end

function visualize_ZML(zml, varargin)

    % visualize_ZML
    %
    % Plot the Zero Moment Line on the current figure.
    %
    % Input:
    %   zml.origin    - point on ZML closest to wrench reference point
    %   zml.direction - unit direction vector of ZML
    %
    % Optional:
    %   lineLength - total length of line to display (m)

    if nargin < 2
        lineLength = 1.0;
    else
        lineLength = varargin{1};
    end


    % Extract ZML parameters
    p0 = zml.origin(:);
    d  = zml.direction(:);


    % Generate points along the line
    s = linspace(-lineLength/2, lineLength/2, 100);

    points = p0 + d*s;


    % Plot ZML
    plot3(...
        points(1,:),...
        points(2,:),...
        points(3,:),...
        'r-',...
        'LineWidth',3,...
        'DisplayName','Zero Moment Line');


    % Plot closest point to reference origin
    scatter3(...
        p0(1),...
        p0(2),...
        p0(3),...
        100,...
        'r',...
        'filled',...
        'DisplayName','ZML reference point');


    % Plot direction arrow
    quiver3(...
        p0(1),...
        p0(2),...
        p0(3),...
        d(1)*0.1,...
        d(2)*0.1,...
        d(3)*0.1,...
        0,...
        'r',...
        'LineWidth',2,...
        'DisplayName','ZML direction');

end

function [distance, closestPoints] = distance_ZML_to_polyhedron(poly, zml, visualise)

    % distance_ZML_to_polyhedron
    %
    % If ZML intersects the polyhedron:
    %   distance = positive penetration depth along ZML
    %
    % If ZML is outside:
    %   distance = negative shortest distance to polyhedron edges
    %
    % Outputs:
    %   distance
    %       >0 : ZML penetration depth
    %       <0 : distance outside polyhedron
    %
    %   closestPoints
    %       [point_on_ZML; point_on_surface]
    if nargin < 3
        visualise = false;
    end

    V = poly.vertices;
    F = poly.faces;


    p = zml.origin(:);
    d = zml.direction(:);
    d = d/norm(d);


    % --------------------------------------------------
    % Check intersections with faces
    % --------------------------------------------------

    intersectionPoints = [];


    for i = 1:size(F,1)

        tri = V(F(i,:),:);

        [hit,~,x] = lineTriangleIntersection(p,d,tri);

        if hit
            intersectionPoints(end+1,:) = x';
        end

    end


    % Remove duplicate intersections from shared edges

    if ~isempty(intersectionPoints)

        intersectionPoints = unique( ...
            round(intersectionPoints,10), ...
            'rows');

    end


    % --------------------------------------------------
    % ZML passes through polyhedron
    % --------------------------------------------------

    if size(intersectionPoints,1) >= 2


        % Project intersections onto ZML axis

        t = (intersectionPoints-p')*d;


        [tmin,idx1] = min(t);
        [tmax,idx2] = max(t);


        % Positive penetration depth

        distance = tmax-tmin;


        closestPoints = [
            intersectionPoints(idx1,:);
            intersectionPoints(idx2,:)
        ];


    else


        % --------------------------------------------------
        % Outside case: distance to edges
        % --------------------------------------------------

        edges = [
            F(:,[1 2]);
            F(:,[2 3]);
            F(:,[3 1])
        ];


        edges = sort(edges,2);
        edges = unique(edges,'rows');


        distance = inf;
        closestPoints = [];


        for i = 1:size(edges,1)

            a = V(edges(i,1),:)';
            b = V(edges(i,2),:)';


            [dist,pLine,pEdge] = distanceLineSegment( ...
                p,d,a,b);


            if dist < distance

                distance = dist;

                closestPoints = [
                    pLine';
                    pEdge'
                ];

            end

        end


        % Negative sign indicates outside

        distance = -distance;

    end

    if visualise
        visualize_ZML_distance(closestPoints, abs(distance))
    end

end

function [hit,t,x] = lineTriangleIntersection(p,d,tri)

    % Line-triangle intersection using Moller-Trumbore algorithm

    v0 = tri(1,:)';
    v1 = tri(2,:)';
    v2 = tri(3,:)';


    % Default outputs
    hit = false;
    t = NaN;
    x = [NaN; NaN; NaN];


    e1 = v1-v0;
    e2 = v2-v0;


    h = cross(d,e2);
    a = dot(e1,h);


    % Parallel to triangle
    if abs(a) < 1e-10
        return
    end


    f = 1/a;

    s = p-v0;

    u = f*dot(s,h);


    % Outside triangle
    if u < 0 || u > 1
        return
    end


    q = cross(s,e1);

    v = f*dot(d,q);


    % Outside triangle
    if v < 0 || (u+v) > 1
        return
    end


    % Intersection distance along line
    t = f*dot(e2,q);


    % Behind line origin (if you want a ray instead of a line)
    % if t < 0
    %     t = NaN;
    %     return
    % end


    x = p + t*d;

    hit = true;

end

function [distance, pointLine, pointSegment] = ...
    distanceLineSegment(p,d,a,b)

    % Infinite line:
    %
    % x = p + s*d
    %
    % Segment:
    %
    % y = a + t(b-a)


    u = d;
    v = b-a;

    w0 = p-a;


    A = dot(u,u);
    B = dot(u,v);
    C = dot(v,v);
    D = dot(u,w0);
    E = dot(v,w0);


    denom = A*C-B^2;


    if abs(denom)<1e-12

        % Parallel case

        s = 0;
        t = dot(w0,v)/C;

    else

        s = (B*E-C*D)/denom;
        t = (A*E-B*D)/denom;

    end


    % Clamp segment parameter

    t = max(0,min(1,t));


    % Recalculate line point

    pointSegment = a+t*v;

    s = dot(pointSegment-p,u);

    pointLine = p+s*u;


    distance = norm(pointLine-pointSegment);

end

function visualize_ZML_distance(closestPoints, dmin)

    % visualize_ZML_distance
    %
    % Plots the closest points between the ZML and support polyhedron edge.
    %
    % Inputs:
    %   closestPoints - 2x3 matrix:
    %                   row 1 = closest point on ZML
    %                   row 2 = closest point on polyhedron edge
    %
    %   dmin          - minimum distance


    pZML  = closestPoints(1,:);
    pEdge = closestPoints(2,:);


    hold on;


    % Closest point on ZML
    scatter3(...
        pZML(1),...
        pZML(2),...
        pZML(3),...
        120,...
        'filled',...
        'DisplayName','Closest point on ZML');


    % Closest point on support boundary
    scatter3(...
        pEdge(1),...
        pEdge(2),...
        pEdge(3),...
        120,...
        'filled',...
        'DisplayName','Closest point on boundary');


    % Connecting distance line
    plot3(...
        [pZML(1) pEdge(1)],...
        [pZML(2) pEdge(2)],...
        [pZML(3) pEdge(3)],...
        'LineWidth',3,...
        'DisplayName',sprintf('ZML distance = %.4f m',dmin));


    % Label distance midpoint
    mid = (pZML+pEdge)/2;

    text(...
        mid(1),...
        mid(2),...
        mid(3),...
        sprintf(' %.3f m',dmin),...
        'FontSize',12);


end

function zmp = calculate_ZMP(wrench, plane, visualise)

    if nargin < 3
        visualise = false;
    end

    % Calculate Zero Moment Line
    zml = calculate_ZML(wrench, false);

    % Plane definition
    plane_point = plane.point(:);
    plane_normal = plane.normal(:);

    % ZML:
    % r = zml.origin + lambda*zml.direction
    %
    % Intersection with plane:
    % n.(r - plane.point) = 0

    denominator = dot(plane_normal, zml.direction);

    if abs(denominator) < 1e-9
        error('Cannot calculate ZMP: ZML is parallel to support plane');
    end

    lambda = dot(plane_normal, plane_point - zml.origin) / denominator;


    % Intersection point
    zmp.point = zml.origin + lambda*zml.direction;


    zmp.x = zmp.point(1);
    zmp.y = zmp.point(2);
    zmp.z = zmp.point(3);


    % Store ZML too (useful for visualisation)
    zmp.zml = zml;


    if visualise
        visualise_ZMP(zmp, plane)
    end

end

function visualise_ZMP(zmp, plane)

    % Assume figure already exists
    hold on;
    axis equal;

    %% Plot ZMP
    scatter3(...
        zmp.point(1),...
        zmp.point(2),...
        zmp.point(3),...
        100,...
        'r',...
        'filled',...
        'MarkerEdgeColor','k');

    text(...
        zmp.point(1),...
        zmp.point(2),...
        zmp.point(3),...
        ' ZMP');

    %% Draw plane
    p = plane.point(:);

    % Two basis vectors spanning the plane
    e1 = plane.basis(:,1);
    e2 = plane.basis(:,2);

    % Size of displayed plane
    L = 0.3;    % Adjust as required

    % Four corners of a square on the plane
    corners = [...
        p + L*( e1 + e2), ...
        p + L*( e1 - e2), ...
        p + L*(-e1 - e2), ...
        p + L*(-e1 + e2)];

    patch(...
        corners(1,:),...
        corners(2,:),...
        corners(3,:),...
        'b',...
        'FaceAlpha',0.2,...
        'EdgeColor','b',...
        'LineWidth',1.5);

    %% Plot plane normal
    quiver3(...
        p(1), p(2), p(3), ...
        plane.normal(1), plane.normal(2), plane.normal(3), ...
        0.15,...
        'k',...
        'LineWidth',2,...
        'MaxHeadSize',0.5);

    xlabel('X');
    ylabel('Y');
    zlabel('Z');
    grid on;
end

function [distance,closest_points] = distance_ZMP_to_polygon(...
            support_polyhedron,...
            zmp,...
            visualise)

    if nargin < 3
        visualise = false;
    end


    %% Extract support polygon

    polygon = support_polyhedron.support_polygon;


    %% Transform ZMP into polygon plane coordinates

    zmp3D = zmp.point(:);

    plane_point = polygon.plane.point(:);

    basis = polygon.plane.basis;


    relative = zmp3D - plane_point;

    zmp2D = relative' * basis;


    %% Find closest point on polygon boundary

    vertices = polygon.vertices2D;

    n = size(vertices,1);

    minDistance = inf;

    closest2D = zeros(1,2);


    for i = 1:n

        p1 = vertices(i,:);

        if i == n
            p2 = vertices(1,:);
        else
            p2 = vertices(i+1,:);
        end


        edge = p2 - p1;

        edgeLengthSquared = dot(edge,edge);


        % Projection onto edge

        if edgeLengthSquared > eps

            t = dot(zmp2D-p1,edge) / edgeLengthSquared;

            t = max(0,min(1,t));

        else

            t = 0;

        end


        closest = p1 + t*edge;


        d = norm(zmp2D-closest);


        if d < minDistance

            minDistance = d;
            closest2D = closest;

        end

    end


    %% Determine inside/outside

    inside = inpolygon(...
        zmp2D(1),...
        zmp2D(2),...
        vertices(:,1),...
        vertices(:,2));


    if inside
        distance = minDistance;
    else
        distance = -minDistance;
    end


    %% Transform closest point back to 3D

    closest3D = plane_point + basis*closest2D';


    closest_points.zmp = zmp3D';

    closest_points.closest = closest3D';


    if visualise
        visualize_ZMP_distance(distance,closest_points);
    end

end

function visualize_ZMP_distance(distance,closest_points)
    % Assume figure already exists

    hold on;


    plot3(...
        [closest_points.zmp(1) closest_points.closest(1)],...
        [closest_points.zmp(2) closest_points.closest(2)],...
        [closest_points.zmp(3) closest_points.closest(3)],...
        'r',...
        'LineWidth',2);


    scatter3(...
        closest_points.closest(1),...
        closest_points.closest(2),...
        closest_points.closest(3),...
        80,...
        'g',...
        'filled');


    text(...
        closest_points.closest(1),...
        closest_points.closest(2),...
        closest_points.closest(3),...
        sprintf(' %.3f m',distance));
end


function all_beta = get_beta(d,parameters)

    nc    = numel(parameters.c);
    all_beta = nan(3,nc);
    all_beta(2,:) = d;

end