function paraStr = CfgParaStr_SH()
% INTRO
%   configure hyper-parameters for SH (Spectral Hashing)
% INPUT
%   none
% OUTPUT
%   paraStr: struct (hyper-parameters)

% initialize <paraStr> with shared hyper-parameters
paraStr = InitParaStr();

% configure basic parameters
paraStr.mthdName = 'SH'; % method name
paraStr.trnFuncHndl = @TrnHashMdl_SH; % training function
paraStr.logFilePath = sprintf('%s/%s.%s.log', ...
    paraStr.logDirPath, paraStr.mthdName, paraStr.dataSetName);
paraStr.rltFilePath = sprintf('%s/%s.%s.mat', ...
    paraStr.rltDirPath, paraStr.mthdName, paraStr.dataSetName);

% configure hyper-parameters for the training process

end