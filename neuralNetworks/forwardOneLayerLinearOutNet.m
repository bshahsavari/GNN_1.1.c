%function [f,netState]=forwardOneLayerLinearOutNet(x,net)
function netState=forwardOneLayerLinearOutNet(x,net,optimalParam,n)

global dynamicSystem learning

sx=size(x,2);
if ~optimalParam
    netState.outs=dynamicSystem.parameters.(net)(n).weights1*x+repmat(dynamicSystem.parameters.(net)(n).bias1, [1 sx]);
else
    netState.outs=learning.current.optimalParameters.(net)(n).weights1*x+repmat(learning.current.optimalParameters.(net)(n).bias1, [1 sx]);
end

%%%%%%% optimization: %%%%%%%%%%
%   kron(ones(m,n),A) -> repmat(A, [m n])

%f=net.weights1*x+kron(ones(1,sx),net.bias1);
%netState.outs=f;

%netState.outs=net.weights1*x+repmat(net.bias1, [1 sx]);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

netState.inputs=x;

