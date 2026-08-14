function [variables,gamma_cnstr,beta,all_beta,loopTime] = QP3D(parameters,wrench,nSides)
    
    tStart = tic;
    [variables,gamma_cnstr] = solveQP(parameters,wrench,nSides);
    loopTime = toc(tStart);
    beta = gamma_cnstr;
    all_beta = get_beta(variables,parameters,nSides);
end

function [x,gamma_cnstr] = solveQP(parameters,wrench,nSides)
    % -----------------------------
    % Extract parameters
    % -----------------------------
    nc   = numel(parameters.c);     % number of contacts
    mu   = parameters.mu;
    r_x    = parameters.r_x;
    r_y    = parameters.r_y;
    reff = parameters.reff;
    c    = parameters.c;
    G    = parameters.G;
    Fa   = parameters.s.*parameters.Fd;

    % -----------------------------
    % Setup x and objective function
    % -----------------------------
    epsilon = 1e-6;

    H = epsilon*eye(6*nc+1);
    H(end,end) = 0;
    f = zeros(6*nc+1,1);
    f(end) = -1;

    % -----------------------------
    % Linear equality
    % -----------------------------
    Aeq = zeros(6, 6*nc + 1);
    
    for i = 1:nc
        cols = (6*(i-1)+1):(6*i);
        Aeq(:, cols) = c(i) * G{i};
    end

    beq = wrench;

    % -----------------------------
    % Linear inequalities
    % -----------------------------

    dirs = polygonDirections(nSides);
    dirs3d = polygonDirections3D(nSides);


    %nrow = nc*(1 + nSides + 2 + nSides);    % normal + friction + tipping
    nrow = nc*(1 + nSides^3 -1 + nSides);
    ncol = 6*nc + 1;

    A = zeros(nrow,ncol);
    b = zeros(nrow,1);

    row = 1;

    for i = 1:nc

        start = 6*(i-1);

        fx = start+1;
        fy = start+2;
        fz = start+3;
        mx = start+4;
        my = start+5;
        mz = start+6;

        %%--------------------------
        %% Normal force
        %%--------------------------

        A(row,fz) = -1;
        A(row,end) = 1;
        b(row) = Fa(i);

        row = row+1;

        %%--------------------------
        %% Friction/moment pyramid
        %%--------------------------

        for k = 1:size(dirs3d,1)

            c = dirs3d(k,1);   % fx
            s = dirs3d(k,2);   % fy
            m = dirs3d(k,3);   % mz

            A(row,fx) = c;
            A(row,fy) = s;
            A(row,mz) = m/reff;
            A(row,fz) = -mu;
            A(row,end) = 1;

            b(row) = mu*Fa(i);

            row = row + 1;
        end
        % %%--------------------------
        % %% Friction pyramid
        % %%--------------------------

        % for k=1:nSides

        %     c = dirs(k,1);
        %     s = dirs(k,2);

        %     A(row,fx) = c;
        %     A(row,fy) = s;
        %     A(row,fz) = -mu;
        %     A(row,end) = 1;

        %     b(row) = mu*Fa(i);

        %     row = row+1;

        % end

        % % +mz
        % A(row,mz) = 1/reff;
        % A(row,fz) = -mu;
        % A(row,end) = 1;
        % b(row) = mu*Fa(i);
        % row = row+1;

        % % -mz
        % A(row,mz) = -1/reff;
        % A(row,fz) = -mu;
        % A(row,end) = 1;
        % b(row) = mu*Fa(i);
        % row = row+1;

        %%--------------------------
        %% Tipping pyramid
        %%--------------------------

        for k=1:nSides

            c = dirs(k,1);
            s = dirs(k,2);

            A(row,mx) = 2*c/r_x;
            A(row,my) = 2*s/r_y;
            A(row,fz) = -1;
            A(row,end) = 1;

            b(row) = Fa(i);

            row = row+1;

        end

    end


    % -----------------------------
    % Solve
    % -----------------------------
    lb = ones(1,6*nc+1)*-10000;
    ub = ones(1,6*nc+1)*10000;
    opts = optimoptions('coneprog', ...
        'ConstraintTolerance', 1e-6, ...
        'Display', 'final', ...
        'LinearSolver', 'auto', ...
        'MaxIterations', 500, ...
        'MaxTime', Inf, ...
        'OptimalityTolerance', 1e-6);

    x = quadprog(H,f,A,b,Aeq,beq,lb,ub);%,opts);
    gamma_cnstr = x(length(x));

end


function D = polygonDirections(nSides)
%POLYGONDIRECTIONS Unit outward normals for an n-sided polygon.

theta = (0:nSides-1)'*2*pi/nSides;

D = [cos(theta) sin(theta)];
end

function D = polygonDirections3D(nSides)
%POLYGONDIRECTIONS3D Unit directions for an nSides^3 3D grid.
%
%   D = polygonDirections3D(nSides)
%
%   Returns nSides^3-by-3 unit vectors spanning the 3D direction space.
%   Columns correspond to [fx, fy, mz].

    % Discrete values in each dimension
    v = linspace(-1, 1, nSides);

    % Create 3D grid
    [x, y, z] = ndgrid(v, v, v);

    % Flatten into vectors
    D = [x(:), y(:), z(:)];

    % Remove zero vector
    D(all(D == 0, 2), :) = [];

    % Normalise each direction
    D = D ./ vecnorm(D, 2, 2);
end


function all_beta = get_beta(x, parameters,nSides)

    nc    = numel(parameters.c);
    mu    = parameters.mu;
    r_x   = parameters.r_x;
    r_y   = parameters.r_y;
    reff  = parameters.reff;
    Fa    = parameters.s .* parameters.Fd;

    gamma = x(end);

    dirs = polygonDirections(nSides);

    all_beta = zeros(3,nc);


    for i = 1:nc

        cols = (6*(i-1)+1):(6*i);

        fx = x(cols(1));
        fy = x(cols(2));
        fz = x(cols(3));
        mx = x(cols(4));
        my = x(cols(5));
        mz = x(cols(6));


        %% -------------------------
        % Normal force
        % Same as SOCP:
        % beta = Fa + fz - gamma
        %% -------------------------

        b_normal = Fa(i) + fz - gamma;


        %% -------------------------
        % Tipping
        % Take minimum polygon face margin
        %% -------------------------

        tipping_beta = [];

        for k = 1:nSides

            dx = dirs(k,1);
            dy = dirs(k,2);

            b_tip = Fa(i) - ...
                    (2*dx*mx/r_x + ...
                     2*dy*my/r_y - ...
                     fz + gamma);

            tipping_beta = [tipping_beta; b_tip];

        end

        b_tipping = min(tipping_beta);



        %% -------------------------
        % Friction
        % Combine tangential friction + mz
        % Take minimum
        %% -------------------------

        friction_beta = [];


        % friction pyramid
        for k = 1:nSides

            dx = dirs(k,1);
            dy = dirs(k,2);

            b_fric = mu*Fa(i) - ...
                     (dx*fx + dy*fy - mu*fz + mu*gamma);

            friction_beta = [friction_beta; b_fric];

        end


        % +mz
        b_mz_pos = mu*Fa(i) - ...
                   (mz/reff - mu*fz + mu*gamma);


        % -mz
        b_mz_neg = mu*Fa(i) - ...
                   (-mz/reff - mu*fz + mu*gamma);


        friction_beta = [friction_beta;
                         b_mz_pos;
                         b_mz_neg];


        b_friction = min(friction_beta);



        %% -------------------------
        % Store same ordering as SOCP
        %% -------------------------

        all_beta(:,i) = [
            b_normal;
            b_tipping;
            b_friction
        ];

    end

end