function [variables,gamma_cnstr] = QP(parameters,wrench)
    [variables,gamma_cnstr] = solveQP(parameters,wrench);
end

function [x,gamma_cnstr] = solveQP(parameters,wrench)
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

    nSides = 8;                     % choose 4,8,16,...
    dirs = polygonDirections(nSides);

    nrow = nc*(1 + nSides + 2 + nSides);    % normal + friction + tipping
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
        %% Friction pyramid
        %%--------------------------

        for k=1:nSides

            c = dirs(k,1);
            s = dirs(k,2);

            A(row,fx) = c;
            A(row,fy) = s;
            A(row,fz) = -mu;
            A(row,end) = mu;

            b(row) = mu*Fa(i);

            row = row+1;

        end

        % +mz
        A(row,mz) = 1/reff;
        A(row,fz) = -mu;
        A(row,end) = mu;
        b(row) = mu*Fa(i);
        row = row+1;

        % -mz
        A(row,mz) = -1/reff;
        A(row,fz) = -mu;
        A(row,end) = mu;
        b(row) = mu*Fa(i);
        row = row+1;

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