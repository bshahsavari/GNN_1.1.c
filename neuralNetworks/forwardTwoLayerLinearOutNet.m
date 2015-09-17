%function [f,netState]=forwardTwoLayerLinearOutNet(x,net)
function netState=forwardTwoLayerLinearOutNet(x,net,optimalParam,n)

global dynamicSystem learning

%%%%%%% optimization: %%%%%%%%%%
%   kron(ones(m,n),A) -> repmat(A, [m n])

%o=tanh(net.weights1*x+kron(ones(1,sx),net.bias1));
%f=net.weights2*o+kron(ones(1,sx),net.bias2);
%netState.hiddens=o;

%% 1st version
%netState.hiddens=tanh(net.weights1*x+repmat(net.bias1,[1 sx]));
%f=net.weights2*netState.hiddens+repmat(net.bias2, [1 sx]);
%netState.outs=f;

%% 2nd version (new parameters)
sx=size(x,2);
if ~optimalParam
    netState.hiddens = tansig(dynamicSystem.parameters.(net)(n).weights1*x+repmat(dynamicSystem.parameters.(net)(n).bias1, [1 sx]));
    netState.outs=dynamicSystem.parameters.(net)(n).weights2*netState.hiddens+repmat(dynamicSystem.parameters.(net)(n).bias2, [1 sx]);
else
    netState.hiddens=tansig(learning.current.optimalParameters.(net)(n).weights1*x+repmat(learning.current.optimalParameters.(net)(n).bias1, [1 sx]));
    netState.outs=learning.current.optimalParameters.(net)(n).weights2*netState.hiddens+repmat(learning.current.optimalParameters.(net)(n).bias2, [1 sx]);
end
netState.inputs=x;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
