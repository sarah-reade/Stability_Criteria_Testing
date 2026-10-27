function [variables,gamma_cnstr,beta,all_beta,loopTime] = SOCP_Fast(parameters,wrench)

    tStart = tic;
    [variables,gamma_cnstr] = obtain_gamma_cnstr(parameters,wrench);
    loopTime = toc(tStart);
    [beta,all_beta] = get_beta(variables,parameters);
end


function [x,beta] = obtain_gamma_cnstr(parameters,wrench)

    %% Solve optimisation problem
    [x,beta] = solveSOCP_mosek(parameters,wrench);


end


function [x,beta] = solveSOCP_mosek(parameters,wrench)
    % SOLVESOCP_MOSEK
    %
    % Direct MOSEK 11.2 implementation of the existing SOCP.
    %
    % Variables:
    %
    %   y = [w_1; ...; w_nc; gamma]
    %
    % Length:
    %
    %   6*nc + 1
    %
    % Objective:
    %
    %   maximize gamma
    %
    % This is equivalent to minimizing
    %
    %   1/(gamma + epsilon)
    %
    % provided gamma + epsilon > 0.
    %
    % Returned:
    %
    %   x    = [w_1; ...; w_nc; gamma]
    %          length = 6*nc + 1
    %
    %   beta = -gamma
    %
    % Requires MOSEK 11.2 MATLAB API.
    %
    % -----------------------------------------------------------------

    % -----------------------------
    % Extract parameters
    % -----------------------------
    nc   = numel(parameters.c);
    mu   = parameters.mu;
    r_x  = parameters.r_x;
    r_y  = parameters.r_y;
    reff = parameters.reff;
    c    = parameters.c;
    G    = parameters.G;
    Fa   = parameters.s .* parameters.Fd;

    % -----------------------------
    % Dimensions
    % -----------------------------
    nvar = 6*nc + 1;

    gamma_col = 6*nc + 1;

    % -----------------------------
    % Objective
    % -----------------------------
    %
    % MOSEK minimizes by default.
    %
    % maximize gamma
    %
    % becomes
    %
    % minimize -gamma
    %

    cobj = zeros(nvar,1);
    cobj(gamma_col) = -1;

    % -----------------------------
    % Variable bounds
    % -----------------------------
    %
    % Same bounds as your coneprog
    % formulation.
    %

    lb = -10000*ones(nvar,1);
    ub =  10000*ones(nvar,1);

    % -----------------------------
    % Linear equality constraints
    % -----------------------------
    %
    % Aeq*y = wrench
    %

    Aeq = zeros(6,nvar);

    for i = 1:nc

        cols = (6*(i-1)+1):(6*i);

        Aeq(:,cols) = c(i)*G{i};

    end

    beq = wrench(:);

    % -----------------------------
    % Linear inequality constraints
    % -----------------------------
    %
    % Existing constraint:
    %
    %   -Fz_i + gamma <= Fa_i
    %

    A = zeros(nc,nvar);
    b = zeros(nc,1);

    for i = 1:nc

        z_col = 6*(i-1) + 3;

        A(i,z_col)     = -1;
        A(i,gamma_col) =  1;

        b(i) = Fa(i);

    end

    % -----------------------------
    % Create MOSEK environment
    % -----------------------------

    [r,res] = mosekopt('echo(0)');

    if r ~= 0
        error('Could not initialise MOSEK. Return code: %d',r);
    end

    % -----------------------------
    % Create task
    % -----------------------------

    [r,task] = mosekopt('task', ...
                        res.env);

    if r ~= 0
        error('Could not create MOSEK task. Return code: %d',r);
    end

    % Make sure task is cleaned up if an error occurs
    cleanupObj = onCleanup(@() cleanupMosek(task));

    % -----------------------------
    % Add variables
    % -----------------------------

    [r,~] = mosekopt( ...
        'appendvars', ...
        task, ...
        nvar);

    if r ~= 0
        error('MOSEK appendvars failed. Return code: %d',r);
    end

    % -----------------------------
    % Variable objective coefficients
    % -----------------------------

    for j = 1:nvar

        [r,~] = mosekopt( ...
            'putcj', ...
            task, ...
            j-1, ...
            cobj(j));

        if r ~= 0
            error('MOSEK putcj failed at variable %d. Return code: %d', ...
                  j,r);
        end

    end

    % -----------------------------
    % Variable bounds
    % -----------------------------

    for j = 1:nvar

        [r,~] = mosekopt( ...
            'putvarbound', ...
            task, ...
            j-1, ...
            'ra', ...
            lb(j), ...
            ub(j));

        if r ~= 0
            error('MOSEK putvarbound failed at variable %d. Return code: %d', ...
                  j,r);
        end

    end

    % -----------------------------
    % Add linear constraints
    % -----------------------------

    mlinear = 6 + nc;

    [r,~] = mosekopt( ...
        'appendcons', ...
        task, ...
        mlinear);

    if r ~= 0
        error('MOSEK appendcons failed. Return code: %d',r);
    end

    % -----------------------------
    % Equality constraints
    % -----------------------------

    for i = 1:6

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            i-1, ...
            'fx', ...
            beq(i), ...
            beq(i));

        if r ~= 0
            error('MOSEK equality bound failed. Return code: %d',r);
        end

    end

    % -----------------------------
    % Existing linear inequalities
    % -----------------------------

    for i = 1:nc

        row = 6 + i;

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row-1, ...
            'up', ...
            -inf, ...
            b(i));

        if r ~= 0
            error('MOSEK inequality bound failed. Return code: %d',r);
        end

    end

    % -----------------------------
    % Add coefficients to Aeq
    % -----------------------------

    for i = 1:6

        for j = 1:nvar

            if Aeq(i,j) ~= 0

                [r,~] = mosekopt( ...
                    'putaij', ...
                    task, ...
                    i-1, ...
                    j-1, ...
                    Aeq(i,j));

                if r ~= 0
                    error('MOSEK putaij failed.');
                end

            end

        end

    end

    % -----------------------------
    % Add coefficients to A
    % -----------------------------

    for i = 1:nc

        row = 6 + i;

        for j = 1:nvar

            if A(i,j) ~= 0

                [r,~] = mosekopt( ...
                    'putaij', ...
                    task, ...
                    row-1, ...
                    j-1, ...
                    A(i,j));

                if r ~= 0
                    error('MOSEK putaij failed.');
                end

            end

        end

    end

    % =============================================================
    % SECOND-ORDER CONES
    % =============================================================
    %
    % We introduce auxiliary rows for each SOC.
    %
    % Friction:
    %
    % || [Fx/mu;
    %      Fy/mu;
    %      Mz/(reff*mu)] ||
    %
    % <= Fz - gamma - Fa(i)
    %
    % represented as:
    %
    % [Fz-gamma-Fa(i);
    %  Fx/mu;
    %  Fy/mu;
    %  Mz/(reff*mu)]
    %
    % in Q^4.
    %
    %
    % Tipping:
    %
    % || [2Mx/r_x;
    %      2My/r_y] ||
    %
    % <= Fz - gamma - Fa(i)
    %
    % represented as:
    %
    % [Fz-gamma-Fa(i);
    %  2Mx/r_x;
    %  2My/r_y]
    %
    % in Q^3.
    %
    % -------------------------------------------------------------

    % Number of additional rows
    nsocrows = 7*nc;

    [r,~] = mosekopt( ...
        'appendcons', ...
        task, ...
        nsocrows);

    if r ~= 0
        error('MOSEK appendcons for SOC rows failed. Return code: %d',r);
    end

    socRow = mlinear;

    for i = 1:nc

        % =========================================================
        % FRICTION CONE
        % =========================================================

        startCol = 6*(i-1) + 1;

        row_t = socRow + 1;
        row_x = socRow + 2;
        row_y = socRow + 3;
        row_z = socRow + 4;

        % ---------------------------------------------------------
        % t = Fz - gamma - Fa(i)
        %
        % We put:
        %
        % t = Fz - gamma
        %
        % and use the lower bound -Fa(i):
        %
        % t >= -Fa(i)
        %
        % This produces:
        %
        % t + Fa(i) >= 0
        %
        % together with the cone condition.
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_t-1, ...
            startCol+2-1, ...
            1);

        if r ~= 0
            error('MOSEK friction t coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_t-1, ...
            gamma_col-1, ...
            -1);

        if r ~= 0
            error('MOSEK friction gamma coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_t-1, ...
            'lo', ...
            -Fa(i), ...
            inf);

        if r ~= 0
            error('MOSEK friction t bound failed.');
        end

        % ---------------------------------------------------------
        % Fx/mu
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_x-1, ...
            startCol-1, ...
            1/mu);

        if r ~= 0
            error('MOSEK friction Fx coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_x-1, ...
            'fr', ...
            -inf, ...
            inf);

        if r ~= 0
            error('MOSEK friction Fx bound failed.');
        end

        % ---------------------------------------------------------
        % Fy/mu
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_y-1, ...
            startCol+1-1, ...
            1/mu);

        if r ~= 0
            error('MOSEK friction Fy coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_y-1, ...
            'fr', ...
            -inf, ...
            inf);

        if r ~= 0
            error('MOSEK friction Fy bound failed.');
        end

        % ---------------------------------------------------------
        % Mz/(reff*mu)
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_z-1, ...
            startCol+5-1, ...
            1/(reff*mu));

        if r ~= 0
            error('MOSEK friction Mz coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_z-1, ...
            'fr', ...
            -inf, ...
            inf);

        if r ~= 0
            error('MOSEK friction Mz bound failed.');
        end

        % ---------------------------------------------------------
        % Add friction quadratic cone
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'appendcone', ...
            task, ...
            'quad', ...
            0, ...
            [row_t-1,row_x-1,row_y-1,row_z-1]);

        if r ~= 0
            error('MOSEK friction cone failed. Return code: %d',r);
        end

        socRow = socRow + 4;


        % =========================================================
        % TIPPING CONE
        % =========================================================

        startCol = 6*(i-1) + 4;

        row_t = socRow + 1;
        row_x = socRow + 2;
        row_y = socRow + 3;

        % ---------------------------------------------------------
        % t = Fz - gamma
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_t-1, ...
            startCol+2-1, ...
            1);

        if r ~= 0
            error('MOSEK tipping t coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_t-1, ...
            gamma_col-1, ...
            -1);

        if r ~= 0
            error('MOSEK tipping gamma coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_t-1, ...
            'lo', ...
            -Fa(i), ...
            inf);

        if r ~= 0
            error('MOSEK tipping t bound failed.');
        end

        % ---------------------------------------------------------
        % 2Mx/r_x
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_x-1, ...
            startCol-1, ...
            2/r_x);

        if r ~= 0
            error('MOSEK tipping Mx coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_x-1, ...
            'fr', ...
            -inf, ...
            inf);

        if r ~= 0
            error('MOSEK tipping Mx bound failed.');
        end

        % ---------------------------------------------------------
        % 2My/r_y
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'putaij', ...
            task, ...
            row_y-1, ...
            startCol+1-1, ...
            2/r_y);

        if r ~= 0
            error('MOSEK tipping My coefficient failed.');
        end

        [r,~] = mosekopt( ...
            'putconbound', ...
            task, ...
            row_y-1, ...
            'fr', ...
            -inf, ...
            inf);

        if r ~= 0
            error('MOSEK tipping My bound failed.');
        end

        % ---------------------------------------------------------
        % Add tipping quadratic cone
        % ---------------------------------------------------------

        [r,~] = mosekopt( ...
            'appendcone', ...
            task, ...
            'quad', ...
            0, ...
            [row_t-1,row_x-1,row_y-1]);

        if r ~= 0
            error('MOSEK tipping cone failed. Return code: %d',r);
        end

        socRow = socRow + 3;

    end

    % =============================================================
    % SOLVE
    % =============================================================

    % Turn on logging
    [r,~] = mosekopt( ...
        'putintparam', ...
        task, ...
        'MSK_IPAR_LOG', ...
        3);

    if r ~= 0
        error('Could not set MOSEK log parameter.');
    end

    % Solve
    [r,res] = mosekopt( ...
        'optimize', ...
        task);

    if r ~= 0

        warning('MOSEK returned error code %d.',r);

        x = NaN(6*nc+1,1);
        beta = NaN;

        return

    end

    % =============================================================
    % GET SOLUTION
    % =============================================================

    % Request interior-point solution
    [r,solsta,prosta,xx] = mosekopt( ...
        'getsolution', ...
        task, ...
        'itr');

    if r ~= 0

        warning('Could not retrieve MOSEK solution. Code: %d',r);

        x = NaN(6*nc+1,1);
        beta = NaN;

        return

    end

    % Check solution status
    if ~strcmp(solsta,'optimal') && ...
       ~strcmp(solsta,'near_optimal')

        warning('MOSEK solution status: %s',solsta);

    end

    % -----------------------------
    % Return solution
    % -----------------------------
    %
    % IMPORTANT:
    %
    % Return length is exactly:
    %
    %       6*nc + 1
    %
    % [wrenches; gamma]
    %

    x = xx(:);

    % Safety check
    if length(x) ~= 6*nc+1
        error('Unexpected MOSEK solution length: %d. Expected %d.', ...
              length(x),6*nc+1);
    end

    % Gamma
    gamma = x(gamma_col);

    % Preserve your existing convention
    beta = -gamma;

end


function cleanupMosek(task)
    % Cleanup helper for MOSEK task.
    %
    % The MATLAB MOSEK API manages the task through the returned
    % handle. This function intentionally does not call a potentially
    % version-specific delete/free routine.

    %#ok<INUSD>
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