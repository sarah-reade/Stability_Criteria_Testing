function [variables,gamma_cnstr,beta,all_beta] = obtainAdhesionCriteria(parameters,wrench,method)
    if nargin < 3
        method = 'SOCP';
    end

    % fill out as nan's
    nc = numel(parameters.c);
    variables = nan(6*nc + 1, 1);
    gamma_cnstr = nan;
    beta = nan;
    all_beta = nan(3, nc);

    % Apply gravity
    wrench = wrench + parameters.gravity*parameters.m;
    
    % Calculate gamma
    switch method
        case 'SOCP'
            [variables,gamma_cnstr,beta,all_beta] = SOCP(parameters,wrench);
        case 'ZML'
            gamma_cnstr = ZML(parameters,wrench);
            beta = gamma_cnstr;
        case 'QP'
            [variables,gamma_cnstr] = QP(parameters,wrench);
            beta = gamma_cnstr;
        case 'SOCPZML'
            [variables,gamma_cnstr,beta,all_beta] = SOCPZML(parameters,wrench);
        case 'QPZML'
            
    end
end

