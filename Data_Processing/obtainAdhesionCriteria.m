function [variables,gamma_cnstr,beta,all_beta,loopTime] = obtainAdhesionCriteria(parameters,wrench,method)
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
            [variables,gamma_cnstr,beta,all_beta,loopTime] = SOCP(parameters,wrench);
        case 'ZML'
            [gamma_cnstr,all_beta,loopTime] = ZML(parameters,wrench);
            beta = gamma_cnstr;
        case 'QP4'
            [variables,gamma_cnstr,beta,all_beta,loopTime] = QP(parameters,wrench,4);
        case 'QP8'
            [variables,gamma_cnstr,beta,all_beta,loopTime] = QP(parameters,wrench,8);
        case 'QP16'
            [variables,gamma_cnstr,beta,all_beta,loopTime] = QP(parameters,wrench,16);
        case 'QP32'
            [variables,gamma_cnstr,beta,all_beta,loopTime] = QP(parameters,wrench,32);
        case 'SOCPZML'
            [variables,gamma_cnstr,beta,all_beta,loopTime] = SOCPZML(parameters,wrench);
        case 'QP8ZML'
            [variables,gamma_cnstr,beta,all_beta,loopTime] = QPZML(parameters,wrench,8);    
        otherwise
            loopTime = NaN;
            error('Invalid method: %s. Valid methods are SOCP, ZML, QP4, QP8, QP16, QP32, SOCPZML, QPZML.', method);
    end
end

