function [variables,gamma_cnstr,beta,all_beta] = obtainAdhesionCriteria(parameters,wrench)
    [variables,gamma_cnstr] = obtain_gamma_cnstr(parameters,wrench);
    [beta,all_beta] = get_beta(variables,parameters);
end


function [x,beta] = obtain_gamma_cnstr(parameters,wrench)
    
    %% Add Gravity 
    sensor_wrench = wrench + parameters.gravity*parameters.m;
    %%sensor_wrench = wrench;

    %% Solve optimisation problem
    [x,beta] = solveSOCP(parameters,sensor_wrench);


end


function [x,beta] = solveSOCP(parameters, wrench)
    % SOLVESOCP
    % Robust contact-wrench SOCP using coneprog
    
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
    % f = ones(6*nc+1,1);
    % f(end) = -1;
    % 
    % for i = 1:nc
    %     f((i-1)*6+3) = -1; % maximise normal forces
    % end
    f = zeros(6*nc+1,1);
    f(end) = -1;
    % f = ones(6*nc+1,1);
    for i = 1:nc
        f((i-1)*6+3) = -1;
    end
    % f(end) = -1;
    
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
    % Linear inequality
    % -----------------------------

    nrow = nc;
    ncol = 6 * nc + 1;
    
    A = zeros(nrow, ncol);
    
    b = [];

    for i = 1:nc
        z_col = 6*(i-1) + 3;
    
        % z component (always 1)
        A(i, z_col) = -1;

        % last column = 1
        A(i, end) = 1;

        b = [b; Fa(i)];
    end
    
    % -----------------------------
    % SOC inequalities
    % -----------------------------
    for i = 1:nc
        % -------- friction ---------%
        Asoc = zeros(3, ncol);

        startCol = 6*(i-1) + 1;

        Asoc(1, startCol)     = 1;
        Asoc(2, startCol + 1) = 1;
        Asoc(3, startCol + 5) = 1/reff;

        bsoc = zeros(3,1);

        dsoc = zeros(ncol, 1);
        dsoc(startCol + 2,1) = mu;
        dsoc(end,1) = -1;

        gamma = -mu*Fa(i);
        
        socConstraints(nc+1-i) = secondordercone(Asoc,bsoc,dsoc,gamma);


        % -------- tipping ---------%
        nrows = 2;
        Asoc = zeros(nrows, ncol);

        startCol = 6*(i-1) + 4;

        Asoc(1, startCol)     = 2/r_x;
        Asoc(2, startCol + 1) = 2/r_y;

        bsoc = zeros(nrows,1);

        dsoc = zeros(ncol, 1);
        dsoc(startCol + 2,1) = 1;
        dsoc(end,1) = -1;

        gamma = -Fa(i);
        
        socConstraints(2*nc+1-i) = secondordercone(Asoc,bsoc,dsoc,gamma);
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

    %% Display coneprog inputs
    % disp('========== coneprog INPUTS ==========');

    % disp('f =');
    % disp(f);

    % disp('socConstraints =');
    % disp(socConstraints);

    % disp('A =');
    % disp(A);

    % disp('b =');
    % disp(b);

    % disp('Aeq =');
    % disp(Aeq);

    % disp('beq =');
    % disp(beq);

    % disp('lb =');
    % disp(lb);

    % disp('ub =');
    % disp(ub);

    % disp('opts =');
    % disp(opts);

    % disp('=====================================');

    [x,beta] = coneprog(f,socConstraints,A,b,Aeq,beq,lb,ub,opts);

    % f = ones(6*nc+1,1);
    % for i = 1:nc
    %     f((i-1)*6+3) = -1;
    % end
    % f(end) = -1;
    % [x,beta] = coneprog(f,socConstraints,A,b,Aeq,beq,lb,ub,opts);
    % disp(x);
    % disp();
    % keyboard
    beta = -x(length(x));

    %displaySOCPConstraints(x, parameters, wrench);
end

function [beta, all_beta] = get_beta(x, parameters)

    nc   = numel(parameters.c);
    mu   = parameters.mu;
    r_x    = parameters.r_x;
    r_y    = parameters.r_y;
    reff = parameters.reff;
    Fa   = parameters.s .* parameters.Fd;

    beta_vals = [];
    all_beta = [];

    for i = 1:nc

        cols = (6*(i-1)+1):(6*i);

        fx = x(cols(1));
        fy = x(cols(2));
        fz = x(cols(3));
        mx = x(cols(4));
        my = x(cols(5));
        mz = x(cols(6));

        % -------------------------
        % Linear inequality bounds
        % -------------------------
        b1 = Fa(i) + fz;
        b2 = Fa(i) + fz - sqrt(((2/r_x)*abs(mx))^2 + ((2/r_y)*abs(my))^2);


        % -------------------------
        % SOC bound
        % -------------------------
        b3 = mu*(fz + Fa(i)) - sqrt(fx^2 + fy^2 + (mz/reff)^2);

        % -------------------------
        % Contact beta
        % -------------------------
        beta_i = min([b1 b2 b3]);

        beta_vals = [beta_vals; beta_i];
        all_beta(:,i) = [b1 b2 b3];

    end

    % global beta is most restrictive contact
    beta = min(beta_vals);
end