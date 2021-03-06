function model = TrnHashMdl_MCSDH(featMat, paraStr, extrInfo)
% INTRO
%   train a hashing model of MCSDH
% INPUT
%   featMat: D x N (feature matrix)
%   paraStr: struct (hyper-parameters)
%   extrInfo: 1 x 2 (cell array of label vector and affinity matrix)
% OUTPUT
%   model: struct (hashing model)

% display the greeting message
fprintf('[INFO] entering TrnHashMdl_MCSDH()\n');

% add path for LBFGS-based optimization
addpath(genpath('./extern/LBFGS'));

% perform feature normalization and kernelization
if paraStr.useKernFeat
  normFunc = @(x)(bsxfun(@times, x, 1 ./ sqrt(sum(x .^ 2, 1))));
  featMat = normFunc(featMat);
  opts.ctrdCnt = paraStr.kernAnchCnt;
  opts.iterCnt = 50;
  opts.ctrdLst = [];
  opts.initMthd = 'rnd';
  opts.enblVrbs = true;
  [anchMat, ~] = KMeansClst(featMat, opts);
  kernFunc = @(x)(...
    exp(-CalcDistMat(anchMat, x, 'ecld') .^ 2 / (2 * paraStr.kernBandWid ^ 2)));
  featMat = kernFunc(featMat);
  preProcFunc = @(x)(kernFunc(normFunc(x)));
else
  normFunc = GnrtNormFunc(featMat);
  featMat = normFunc(featMat);
  preProcFunc = normFunc;
end

% randomly select a subset of instances for training
smplCnt = size(featMat, 2);
smplCntTrn = min(smplCnt, paraStr.smplCntTrn);
smplIdxLstTrn = sort(randperm(smplCnt, smplCntTrn));
featMatTrn = featMat(:, smplIdxLstTrn);
lablVecTrn = extrInfo{1}(smplIdxLstTrn);
lablMatTrn = CvtLablVecToMat(lablVecTrn);

% remove the mean vector from the mapping feature matrix
meanVec = mean(featMat, 2);
featMatCen = bsxfun(@minus, featMatTrn, meanVec);

% randomly initialize binary codes for all training instances
if strcmp(paraStr.codeInitMthd, 'rand')
  codeMat = (randn(paraStr.hashBitCnt, instCntTrn) > 0) * 2 - 1;
else
  projMat = randn(size(featMatCen, 1), paraStr.hashBitCnt);
  featMatPrj = projMat' * featMatCen;
  featMatSrt = sort(featMatPrj, 2);
  thrsMat = featMatSrt(:, round(smplCntTrn * [0.33, 0.67]));
  codeMat = ones(paraStr.hashBitCnt, smplCntTrn);
  codeMat(bsxfun(@le, featMatPrj, thrsMat(:, 1))) = -1;
  codeMat(bsxfun(@ge, featMatPrj, thrsMat(:, 2))) = -1;
end

% compute the initial classification weighting matrix
clssReguMat = paraStr.reguCoeffClss * eye(paraStr.hashBitCnt);
clssMat = (codeMat * codeMat' + clssReguMat) \ (codeMat * lablMatTrn');

% compute the initial projection and thresholding vectors
[projMat, thrsMat] = UpdtProjPara(featMatCen, codeMat, [], [], paraStr);

% compute activation matrices
actvMatStr = CalcActvMat(featMatCen, projMat, thrsMat, paraStr);

% update the MCSDH model through iterations
for iterIdx = 1 : paraStr.iterCnt
  % display heart-beat message
  fprintf('[INFO] iterIdx = %3d / %3d\n', iterIdx, paraStr.iterCnt);
  
  % update binary codes in a bit-wise style
  codeMat = zeros(paraStr.hashBitCnt, smplCntTrn);
  pMat = codeMat' * clssMat;
  qMat = clssMat * lablMatTrn + paraStr.pnltCoeffQuan * actvMatStr.cmb;
  for iterIdxCode = 1 : paraStr.iterCntCode
    hashBitIdxLst = randperm(paraStr.hashBitCnt); % allow more explorations
    for hashBitIdx = hashBitIdxLst
      zVec = codeMat(hashBitIdx, :)';
      vVec = clssMat(hashBitIdx, :)';
      pMat = pMat - zVec * vVec';
      zVec = (qMat(hashBitIdx, :)' - pMat * vVec > 0) * 2 - 1;
      pMat = pMat + zVec * vVec';
      codeMat(hashBitIdx, :) = zVec';
    end
  end
  
  % update the classification weighting matrix and hashing function
  clssMat = (codeMat * codeMat' + clssReguMat) \ (codeMat * lablMatTrn');
  [projMat, thrsMat] = ...
      UpdtProjPara(featMatCen, codeMat, projMat, thrsMat, paraStr);
  
  % compute activation matrices
  actvMatStr = CalcActvMat(featMatCen, projMat, thrsMat, paraStr);
  
  % evaluate the objective function's value
  clssLssVal = norm(lablMatTrn - clssMat' * codeMat, 'fro');
  reguLssVal = paraStr.reguCoeffClss * norm(clssMat, 'fro');
  quanLssVal = ...
      paraStr.pnltCoeffQuan * norm(codeMat - actvMatStr.cmb, 'fro');
  objFuncVal = clssLssVal + reguLssVal + quanLssVal;
  fprintf('[INFO] clssLssVal = %.4e\n', clssLssVal);
  fprintf('[INFO] reguLssVal = %.4e\n', reguLssVal);
  fprintf('[INFO] quanLssVal = %.4e\n', quanLssVal);
  fprintf('[INFO] objFuncVal = %.4e\n', objFuncVal);
  
  % check for the early-break condition
  if iterIdx ~= 1
    projMatDiff = projMat - projMatPrev;
    updtRat = norm(projMatDiff, 'fro') / norm(projMat, 'fro');
    if updtRat < paraStr.optTlrtLmt
      fprintf('[INFO] early break at %d-th iteration\n', iterIdx);
      break;
    else
      fprintf('[INFO] update ratio: %.4f%%\n', updtRat * 100);
    end
  end
  projMatPrev = projMat;
end

% create the hashing function handler
model.hashFunc = @(featMat)(HashFuncImpl(...
  preProcFunc(featMat), meanVec, projMat, thrsMat, paraStr));

end

function [projMat, thrsMat] = ...
    UpdtProjPara(featMat, codeMat, projMat, thrsMat, paraStr)
% INTRO
%   update projection parameters
% INPUT
%   featMat: D x N (feature matrix)
%   codeMat: R x N (binary code matrix)
%   projMat: D x R (projection matrix)
%   thrsMat: R x 2 (thresholding matrx of left & right components)
%   paraStr: structure (parameters for training the retrieval model)
% OUTPUT
%   projMat: D x R (projection matrix)
%   thrsMat: R x 2 (thresholding matrix of left & right components)

% obtain basic variables
featCnt = size(featMat, 1);
instCnt = size(featMat, 2);
hashBitCnt = size(codeMat, 1);

% randomly initialize projection matrix and thresholding vectors when needed
if isempty(projMat) || isempty(thrsMat)
  projMat = randn(featCnt, hashBitCnt) * paraStr.projInitScal;
  featMatPrj = projMat' * featMat;
  featMatSrt = sort(featMatPrj, 2);
  thrsMat = featMatSrt(:, round(instCnt * [0.33, 0.67]));
end

% compute activation matrices and quantization error
actvMatStr = CalcActvMat(featMat, projMat, thrsMat, paraStr);
quanErrPrev = norm(codeMat - actvMatStr.cmb, 'fro');

% update each hashing bit's projection and thresholding vectors
warning('off', 'all');
quanErrIter = quanErrPrev;
prThVec = zeros(featCnt + 2, 1);
for hashBitIdx = 1 : hashBitCnt
  % display heart-beat message
  fprintf('[INFO] hashBitIdx = %3d / %3d: ', hashBitIdx, hashBitCnt);
  
  % obtain the corresponding binary code vector
  codeVec = codeMat(hashBitIdx, :);
  
  % pack projection and thresholding vectors
  prThVec(1 : featCnt) = projMat(:, hashBitIdx);
  prThVec(featCnt + 1 : end) = thrsMat(hashBitIdx, :)';
  [objFuncValPrev, ~] = CalcCostGrad(prThVec, featMat, codeVec, paraStr);
  fprintf('%.4e -> ', quanErrIter);

  % update projection and thresholding vectors with the L-BFGS solver
  opts.Method = 'lbfgs';
  opts.MaxIter = paraStr.lbfgsIterCnt;
  opts.Display = 'off';
  [prThVec, objFuncValCurr] = minFunc(...
      @CalcCostGrad, prThVec, opts, featMat, codeVec, paraStr);
  quanErrIter = sqrt(quanErrIter ^ 2 - objFuncValPrev ^ 2 + objFuncValCurr ^ 2);
  fprintf('%.4e\n', quanErrIter);

  % extract projection and thresholding vectors
  projMat(:, hashBitIdx) = reshape(prThVec(1 : featCnt), [featCnt, 1]);
  thrsMat(hashBitIdx, :) = reshape(prThVec(featCnt + 1 : end), [2, 1])';
end
warning('on', 'all');

% compute activation matrices and quantization error
actvMatStr = CalcActvMat(featMat, projMat, thrsMat, paraStr);
quanErrCurr = norm(codeMat - actvMatStr.cmb, 'fro');
fprintf('[INFO] quanErr: %.4e -> %.4e\n', quanErrPrev, quanErrCurr);

end

function [costVal, gradVec] = CalcCostGrad(prThVec, featMat, codeVec, paraStr)
% INTRO
%   compute the cost function's value and gradient vector
% INPUT
%   prThVec: (D + 2) x 1 (projection and thresholding vectors)
%   featMat: D x N (feature matrix)
%   codeVec: 1 x N (binary code vector)
%   paraStr: structure (parameters for training the retrieval model)
% OUTPUT
%   costVal: scalar (cost function's value)
%   gradVec: (D x R + R x 2) x 1 (gradient vector)

% obtain basic variables
featCnt = size(featMat, 1);
instCnt = size(featMat, 2);

% extract projection and thresholding matrices from the vector
projVec = reshape(prThVec(1 : featCnt), [featCnt, 1]);
thrsVec = reshape(prThVec(featCnt + 1 : end), [2, 1])';

% compute activation matrices and quantization error
featVecPrj = projVec' * featMat;
if strcmp(paraStr.actvFuncType, 'sigm')
  actvVecLft = 1 ./ (1 + exp(bsxfun(@minus, thrsVec(1), featVecPrj)));
  actvVecRht = 1 ./ (1 + exp(bsxfun(@minus, thrsVec(2), featVecPrj)));
  actvVecCmb = 2 * (actvVecLft - actvVecRht - 0.5);
else
  actvVecLft = max(0, bsxfun(@minus, featVecPrj, thrsVec(1)));
  actvVecRht = max(0, bsxfun(@minus, thrsVec(2), featVecPrj));
  actvVecCmb = -actvVecLft - actvVecRht + 1;
end
costVal = norm(codeVec - actvVecCmb, 'fro');

% compute the gradient of each variable to be optimized
if strcmp(paraStr.actvFuncType, 'sigm')
  % compute shared variables in advance
  bVecCmb = 2 * (codeVec - actvVecCmb);
  hVecCmb = 2 * actvVecLft .* (1 - actvVecLft);
  gVecCmb = 2 * actvVecRht .* (1 - actvVecRht);

  % compute the gradient of each variable
  gradVecProj = featMat * (bVecCmb .* (-hVecCmb + gVecCmb))' / instCnt;
  gradVecThrs = [mean(bVecCmb .* hVecCmb, 2), mean(-bVecCmb .* gVecCmb, 2)];
else
  % compute shared variables in advance
  bVecCmb = 2 * (codeVec - actvVecCmb);
  hVecCmb = (actvVecLft > 0);
  gVecCmb = (actvVecRht > 0);

  % compute the gradient of each variable
  gradVecProj = featMat * (bVecCmb .* (hVecCmb - gVecCmb))' / instCnt;
  gradVecThrs = [mean(-bVecCmb .* hVecCmb, 2), mean(bVecCmb .* gVecCmb, 2)];
end

% pack gradient matrices into a single vector
gradVec = zeros(featCnt + 2, 1);
gradVec(1 : featCnt) = gradVecProj;
gradVec(featCnt + 1 : end) = gradVecThrs';

end

function actvMatStr = CalcActvMat(featMat, projMat, thrsMat, paraStr)
% INTRO
%   compute left/right/combined activation matrices
% INPUT
%   featMat: D x N (feature matrix)
%   projMat: R x K (projection matrix)
%   thrsMat: R x 2 (thresholding matrx of left & right components)
%   paraStr: structure (parameters for training the retrieval model)
% OUTPUT
%   actvMatStr: structure (left/right/combined activation matrices)

% compute left/right/combined activation matrices
featMatPrj = projMat' * featMat;
if strcmp(paraStr.actvFuncType, 'sigm')
  actvMatStr.lft = 1 ./ (1 + exp(bsxfun(@minus, thrsMat(:, 1), featMatPrj)));
  actvMatStr.rht = 1 ./ (1 + exp(bsxfun(@minus, thrsMat(:, 2), featMatPrj)));
  actvMatStr.cmb = 2 * (actvMatStr.lft - actvMatStr.rht - 0.5);
else
  actvMatStr.lft = max(0, bsxfun(@minus, featMatPrj, thrsMat(:, 1)));
  actvMatStr.rht = max(0, bsxfun(@minus, thrsMat(:, 2), featMatPrj));
  actvMatStr.cmb = -actvMatStr.lft - actvMatStr.rht + 1;
end

end

function codeMat = HashFuncImpl(featMat, meanVec, projMat, thrsMat, paraStr)
% INTRO
%   hashing function
% INPUT
%   dataMat: K x N (feature matrix)
%   meanVec: K x 1 (mean vector)
%   projMat: R x K (projection matrix)
%   thrsMat: R x 2 (thresholding matrx of left & right components)
%   paraStr: struct (hyper-parameters)
% OUTPUT
%   codeMat: R x N (binary code matrix)

% compute the binary code matrix
featMatCen = bsxfun(@minus, featMat, meanVec);
actvMatStr = CalcActvMat(featMatCen, projMat, thrsMat, paraStr);
codeMat = uint8(actvMatStr.cmb > 0);

end
