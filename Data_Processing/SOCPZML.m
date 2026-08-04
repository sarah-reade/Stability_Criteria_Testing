function [variables,gamma_cnstr,beta,all_beta,loopTime] = SOCPZML(parameters,wrench)

    tStart = tic;
    [variables,gamma_cnstr] = obtain_gamma_cnstr(parameters,wrench);
    zml_dist = ZML(parameters,wrench);
    gamma_cnstr = min(gamma_cnstr,zml_dist);
    loopTime = tok(tStart);

    [beta,all_beta] = get_beta(variables,zml_dist,parameters);
end


function [x,beta] = obtain_gamma_cnstr(parameters,wrench)

    %% Solve optimisation problem
    [x,beta] = solveSOCP(parameters,wrench);


end


function [x,beta] = solveSOCP(parameters, wrench)
    % SOLVESOCP
    % Robust contact-wrench SOCP using coneprog
    
    % -----------------------------
    % Extract parameters
    % -----------------------------
    nc   = numel(parameters.c);     % number of contacts
    mu   = parameters.mu;
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
    % for i = 1:nc
    %     f((i-1)*6+3) = -1;
    % end
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

    % displaySOCPConstraints(x, parameters, wrench);
    % keyboard
end

function [beta, all_beta] = get_beta(x, zml_dist, parameters)

    nc   = numel(parameters.c);
    mu   = parameters.mu;
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
        b2 = zml_dist;


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

function displaySOCPConstraints(x, parameters, wrench)
%DISPLAYSOCPCONSTRAINTS Display evaluation of all SOCP constraints.
%
% Prints:
%   - Equality constraints
%   - Linear inequalities
%   - Friction cones
%   - Tipping cones
%
% A constraint is satisfied when the reported residual <= 0.

    if isempty(x)
        fprintf('No solution returned.\n');
        return;
    end

    nc   = numel(parameters.c);
    mu   = parameters.mu;
    r_x  = parameters.r_x;
    r_y  = parameters.r_y;
    reff = parameters.reff;

    c  = parameters.c;
    G  = parameters.G;
    Fa = parameters.s .* parameters.Fd;

    beta = -x(end);

    fprintf('\n========================================================\n');
    fprintf('SOCP Constraint Evaluation\n');
    fprintf('beta = %.6f\n', beta);
    fprintf('========================================================\n');

    %% Equality constraints
    fprintf('\n--- Equality Constraints ---\n');

    Aeq = zeros(6,6*nc);

    for i = 1:nc
        cols = (6*(i-1)+1):(6*i);
        Aeq(:,cols) = c(i)*G{i};
    end

    lhs = Aeq*x(1:end-1);

    fprintf('Desired wrench:\n');
    disp(wrench(:).');

    fprintf('Produced wrench:\n');
    disp(lhs(:).');

    fprintf('Residual:\n');
    disp((lhs-wrench(:)).');

    %% Linear inequalities
    fprintf('\n--- Linear Inequalities ---\n');

    for i = 1:nc

        idx = (i-1)*6;

        fz = x(idx+3);

        lhs = beta - fz;
        rhs = Fa(i);

        fprintf(['Contact %d : beta - fz <= Fa\n' ...
                 '    %.6f <= %.6f   (%s)\n'], ...
                 i,lhs,rhs,passfail(lhs<=rhs+1e-8));
    end

    %% Friction cones
    fprintf('\n--- Friction Cones ---\n');

    for i = 1:nc

        idx = (i-1)*6;

        fx = x(idx+1);
        fy = x(idx+2);
        fz = x(idx+3);
        mz = x(idx+6);

        lhs = norm([fx;fy;mz/reff]);

        rhs = mu*(fz+Fa(i)) - beta;

        fprintf(['Contact %d\n' ...
                 '    ||[fx fy mz/re]|| = %.6f\n' ...
                 '    mu(fz+Fa)-beta   = %.6f\n' ...
                 '    residual         = %.6e   (%s)\n'], ...
                 i,lhs,rhs,lhs-rhs,passfail(lhs<=rhs+1e-8));
    end

    %% Tipping cones
    fprintf('\n--- Tipping Cones ---\n');

    for i = 1:nc

        idx = (i-1)*6;

        mx = x(idx+4);
        my = x(idx+5);
        fz = x(idx+3);

        lhs = norm([2*mx/r_x;
                    2*my/r_y]);

        rhs = fz + Fa(i) - beta;

        fprintf(['Contact %d\n' ...
                 '    ||[2mx/rx 2my/ry]|| = %.6f\n' ...
                 '    fz+Fa-beta         = %.6f\n' ...
                 '    residual           = %.6e   (%s)\n'], ...
                 i,lhs,rhs,lhs-rhs,passfail(lhs<=rhs+1e-8));
    end

    fprintf('========================================================\n');

end


function s = passfail(tf)

    if tf
        s = 'PASS';
    else
        s = 'FAIL';
    end

end