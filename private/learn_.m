%  Two functions ("runForward" and "runBackward") are iteratively  called:
%       - runForward computes the new state of the system after a number of steps large enough such
%           that the system reaches the stable point. More precisely,
%           the system is iterated until |x(t)-x(t-1)| is smaller then learning.forwardStopCoefficient
%           or the maximal number of steps (learning.maxForwardSteps) is reached
%       - runBackward backpropagates the delta error for a number of steps
%           so that the computed gradient is close to the actual gradient.
%           More precisely, the backpropagation is iterated until |deltaNet(t)-deltaNe(t-1)|
%           is smaller then learning.backwardStopCoefficient
%           or the maximal number of steps (learning.maxBackwardSteps) is reached
%
% The learning function is based on Resilient Propagation (RProp)
% Moreover, it uses a validation set to select the best parameters
%
% The learning function can be summarized as follows
%   1. Compute a new stable point by runForward
%   2. Compute the error
%   3. Every learning.stepsForValidation epoches compute error on validation
%       and if ity is minimal stores the current parameters in learning.optimalParameters
%   4. Compute the gradient by runBackwark
%   5. Update the the parameters using gradient
%   6. Repeat 1-2-3-4 until a desidered precision or a given number of steps are reached.
%

% Main variables:
% learning.current.nSteps                           the number of epoches
% learning.current.trainError                       the current training error
% learning.history.trainErrorHistory                a vector containing all the training errors
% dynamicSystem.state                               the current state X of the system
% dynamicSystem.parameters                          structure containing the current parameters
% learning.current.{forwardGradient, outGradient}   data structures containing the current gradient
% learning.optimalParameters                        the best set of parameters according to the validation strategy



function learn_
% Main learning function (private)

warning off MATLAB:divideByZero         % no divideByZero warning
%FIXME
% global transitionNetTrain outNetTrain
global dataSet dynamicSystem learning VisualMode stopLearn toolHandles GUI
if isempty(VisualMode)
    VisualMode = 0;
end
if ~isempty(dynamicSystem) && isfield(dynamicSystem,'config') && isfield(dynamicSystem.config,'logFile')
    if dynamicSystem.config.useLogFile
        h = fopen(dynamicSystem.config.logFile,'a');
        if h==-1
            dynamicSystem.config.useLogFile=0;
            warn(0, ['I can''t open log file <' dynamicSystem.config.logFile '>. Logging was disabled.']);
        else
            disp(['Logging enabled. File: ' dynamicSystem.config.logFile]);
        end
    end
end


iStart=learning.current.nSteps;

if dynamicSystem.config.useValidation
    % if last epoch is not a validation one, we make the system learns a little longer until a validation epoch is reached
    tmpint=mod(iStart+learning.config.learningSteps, learning.config.stepsForValidation);
    if tmpint~=1
        learning.config.learningSteps=learning.config.learningSteps+learning.config.stepsForValidation-tmpint+1;
    end
    validationIndex=find(diag(dataSet.validationSet.maskMatrix));
end

terminateOnValidation = dynamicSystem.config.terminateOnValidation;
max_fail = dynamicSystem.config.max_fail;
% learning.current.validationFail = 0;
% MAIN LEARNING CYCLE
while ( (learning.current.nSteps<iStart+learning.config.learningSteps && isempty(stopLearn)) &&...
        ( ( terminateOnValidation == true) && (learning.current.validationFail < max_fail)))

    % COMPUTING THE NEW STABLE STATE x=dynamicSystem.state;
    for i = 1:dynamicSystem.ntrans
        [dynamicSystem.state{i},learning.current.forwardState(i),learning.current.forwardIt(1,i)]=feval(dynamicSystem.config.forwardFunction,...
            learning.config.maxForwardSteps,dynamicSystem.state{i},'trainSet',0,i);
    end
    
    
    % -- Data Logging --
    if dynamicSystem.config.saveIterationHistory
        learning.history.forwardItHistory(learning.current.nSteps,:)=uint8(learning.current.forwardIt);
    end
    if dynamicSystem.config.saveStateHistory
        learning.history.stateHistory(:,learning.current.nSteps)=single(dynamicSystem.state(:));
    end
    % ------------------

    % Computes the error
    [learning.current.trainError,learning.current.outState]=feval(dynamicSystem.config.computeErrorFunction,'trainSet',[],0);
    
    % -- Data Logging --
    for nt = 1:dynamicSystem.ntrans
        if dynamicSystem.config.saveErrorHistory
            learning.history.trainErrorHistory(learning.current.nSteps)=single(learning.current.trainError);
        end
        if dynamicSystem.config.saveStabilityCoefficientHistory
            learning.current.stabilityCoefficient{nt}=sum(sum(abs(learning.history.oldX{nt}-dynamicSystem.state{nt})))/sum(sum(abs(learning.history.oldX{nt})));
            learning.history.stabilityCoefficientHistory{nt}(learning.current.nSteps)=single(learning.current.stabilityCoefficient{nt});
        end
    end
    % ------------------
    
    % Saturation is measured
    if dynamicSystem.config.saveSaturationHistory
        if dynamicSystem.config.outNet.nLayers == 2
            learning.current.saturationCoefficient.outNet=norm(learning.current.outState.outNetState.hiddens)^2/size(learning.current.outState.outNetState.hiddens,1)/...
                size(learning.current.outState.outNetState.hiddens,2);
            learning.history.saturationCoefficient.outNet(learning.current.nSteps)=single(learning.current.saturationCoefficient.outNet);
        end
        if dynamicSystem.config.transitionNet.nLayers == 2
            for nt = 1:dynamicSystem.ntrans
                learning.current.saturationCoefficient.transitionNet{nt}=norm(learning.current.forwardState(nt).transitionNetState.hiddens)^2/...
                    size(learning.current.forwardState(nt).transitionNetState.hiddens,1)/size(learning.current.forwardState(nt).transitionNetState.hiddens,2);
                learning.history.saturationCoefficient.transitionNet{nt}(learning.current.nSteps)=single(learning.current.saturationCoefficient.transitionNet{nt});
            end
        end
        if strcmp(dynamicSystem.config.type,'linear') && (dynamicSystem.config.forcingNet.nLayers == 2)
            learning.current.saturationCoefficient.forcingNet=norm(learning.current.forwardState.forcingNet.hiddens)^2/...
                size(learning.current.forwardState.forcingNet.hiddens,1)/size(learning.current.forwardState.forcingNet.hiddens,2);
            learning.history.saturationCoefficient.forcingNet(learning.current.nSteps)=single(learning.current.saturationCoefficient.forcingNet);
        end
    end
    % Old state and parameters are saved
    learning.history.oldX=dynamicSystem.state;
    learning.history.oldP=dynamicSystem.parameters;

    %% Computing the gradient
    % Backpropagate through G
    % 1st output gives the gradient of cost w.r.t the parameters of G. 2nd
    % output gives the grad of cost w.r.t the states injected to G
    % (nStates*ntrans) x nTotalNodes
    % In other words, 1st output is de/dw for w's in G. The 2nd input is
    % variable b in TABLE I (de/do * dG/dx)
    [learning.current.outGradient,b]=feval(dynamicSystem.config.computeDeltaErrorFunction,[]);
    
    % Backpropagation through F
    % 1st output contains the gradient of cost w.r.t the parameters of F
    % block(s)
    [learning.current.forwardGradient,~,learning.current.backwardIt]=feval(dynamicSystem.config.backwardFunction,b,[],[]);
    
    % -- Data Logging --
    if dynamicSystem.config.saveIterationHistory
        learning.history.backwardItHistory(learning.current.nSteps,:)=uint8(learning.current.backwardIt);
    end
    % ------------------
    
    %% computing Jacobian of transition function and eventually adapting the gradient
    for nt = 1:dynamicSystem.ntrans
        if dynamicSystem.config.useJacobianControl,
          %  [learning.current.jacobian,learning.current.jacobianErrors]=feval(dynamicSystem.config.forwardJacobianFunction,'trainSet',[]);
            learning.current.maxJac{nt}=max(learning.current.jacobianErrors{nt});
            learning.current.maxJacComplete{nt}=max(sum(abs(learning.current.jacobian{nt})));

            % -- Data Logging --
            if dynamicSystem.config.saveJacobianHistory
                learning.history.jacobianHistory{nt}(learning.current.nSteps)=single(full(learning.current.maxJac{nt}));
                learning.history.jacobianHistoryComplete{nt}(learning.current.nSteps)=single(full(learning.current.maxJacComplete{nt}));
            end
            % ------------------
            overIndexes=find(learning.current.jacobianErrors{nt});
            if (~isempty(overIndexes))
                learning.current.jacobianGradient{nt}=feval(dynamicSystem.config.backwardJacobianFunction,'trainSet',learning.current.jacobian{nt},learning.current.jacobianErrors{nt},[],nt);
                for it=fieldnames(learning.current.jacobianGradient{nt})'
                    learning.current.forwardGradient.transitionNet(nt).(char(it))=...
                        learning.current.forwardGradient.transitionNet(nt).(char(it))+...
                        dynamicSystem.config.jacobianFactorCoeff*learning.current.jacobianGradient{nt}.(char(it));
                end
            end
        end
    end

    global gain;
    % Every learning.config.stepsForValidation, we evaluate the error on validation set.
    if dynamicSystem.config.useValidation && mod(learning.current.nSteps, learning.config.stepsForValidation)==0
        for i = 1:dynamicSystem.ntrans
            learning.current.validationState{i}=feval(dynamicSystem.config.forwardFunction,learning.config.maxStepsForValidation,learning.current.validationState{i},...
            'validationSet',0,i);
        end

        
        [learning.current.validationError learning.current.validationOut]=feval(dynamicSystem.config.computeErrorFunction,'validationSet',[],0);
        if dynamicSystem.config.saveErrorHistory
            learning.history.validationErrorHistory=[learning.history.validationErrorHistory,single(learning.current.validationError)];
        end

        if dynamicSystem.config.useValidationMistakenPatterns
            % optimal parameters update is done using also the number of classification errors on the validationSet
            if dynamicSystem.config.useBalancedDataset
                % the number of errors is obtained weighting the errors on positive and negative examples
                if ~isempty(strfind(dynamicSystem.config.validationBalancedClass,'positive'))
                    learning.current.validationMistakenPatterns=dynamicSystem.config.validationBalancingFact*...
                        size(find(dataSet.validationSet.targets>0 & learning.current.validationOut.outNetState.outs<dataSet.config.rejectUpperThreshold),2)+...
                        size(find(dataSet.validationSet.targets<0 & learning.current.validationOut.outNetState.outs>dataSet.config.rejectLowerThreshold),2);
                else
                    learning.current.validationMistakenPatterns=...
                        size(find(dataSet.validationSet.targets>0 & learning.current.validationOut.outNetState.outs<dataSet.config.rejectUpperThreshold),2)+...
                        dynamicSystem.config.validationBalancingFact*...
                        size(find(dataSet.validationSet.targets<0 & learning.current.validationOut.outNetState.outs>dataSet.config.rejectLowerThreshold),2);
                end
            else
                % we've to consider the possibility of a pure multiclass problem. In that case a pattern is correct if it has the maximum
                % value in the correct class
                if size(dataSet.validationSet.targets,1)==1
                    [r,c]=find((dataSet.validationSet.targets>0 &...
                        learning.current.validationOut.outNetState.outs<dataSet.config.rejectUpperThreshold) | ...
                        (dataSet.validationSet.targets<0 & learning.current.validationOut.outNetState.outs>dataSet.config.rejectLowerThreshold));
                    learning.current.validationMistakenPatterns=size(unique(c(:)),1);
                else
                    % multiclass
                    [vv,ii]=max(dataSet.validationSet.targets(:,validationIndex),[],1);
                    [v2,i2]=max(learning.current.validationOut.outNetState.outs(:,validationIndex),[],1);
                    learning.current.validationMistakenPatterns=size(find(ii-i2),2);
                end
            end

            if dynamicSystem.config.saveIterationHistory
                learning.history.validationMistakenPatterns=[learning.history.validationMistakenPatterns,uint32(learning.current.validationMistakenPatterns)];
            end

            if (learning.current.validationMistakenPatterns < learning.current.bestValMistakenPatterns) || ...
                    ((learning.current.validationMistakenPatterns == learning.current.bestValMistakenPatterns) && (learning.current.validationError < learning.current.bestErrorOnValidation))
                learning.current.bestValMistakenPatterns=learning.current.validationMistakenPatterns;
                learning.current.bestErrorOnValidation=learning.current.validationError;
                learning.current.optimalParameters=dynamicSystem.parameters;
                learning.current.optimalStep=learning.current.nSteps;
                learning.current.optimalValidationOut=learning.current.validationOut.outNetState.outs;
            end

        else
            % optimal parameters update is done using only the error on the validationSet
            if (learning.current.validationError < learning.current.bestErrorOnValidation)
                learning.current.bestErrorOnValidation=learning.current.validationError;
                learning.current.optimalParameters=dynamicSystem.parameters;
                learning.current.optimalStep=learning.current.nSteps;
                learning.current.optimalValidationOut=learning.current.validationOut.outNetState.outs;
                learning.current.validationFail = 0;
            else
                learning.current.validationFail = learning.current.validationFail + 1;
            end
            
        end

        if VisualMode == 1,
            if ~isempty(toolHandles) && ishandle(toolHandles.ConfigToolFig) && strcmp(get(toolHandles.ConfigToolFig,'Visible'),'on')
                set(toolHandles.ConfigToolFig,'Visible','off');
            end
            DisplayResults('learn');
            drawnow;
            fig_h = guihandles(GUI.DisplayResultsH);
            percent=(round((learning.current.nSteps-iStart+1)/learning.config.learningSteps*100));
            DisplayResults('updatePlot',GUI.DisplayResultsH,[],fig_h,percent);
            drawnow;
        elseif VisualMode == 2
            validation_str='current';
            marker='';
            mssg(['step: ' num2str(learning.current.nSteps) sprintf('\ttraining error: ') num2str(learning.current.trainError)])
            if (learning.current.validationError == learning.current.bestErrorOnValidation)
                if dynamicSystem.config.useAutoSave
                    autoSave;
                end
                validation_str='best';
                marker=sprintf('\t***');
            end
            
            if dynamicSystem.config.useValidationMistakenPatterns
                if dynamicSystem.config.useBalancedDataset
                    mssg([sprintf('\t\t\t') validation_str ' validation error: ' num2str(learning.current.validationError) ' (' num2str(learning.current.validationMistakenPatterns) ' errors [balanced])' marker]);
                else
                    mssg([sprintf('\t\t\t') validation_str ' validation error: ' num2str(learning.current.validationError) ' (' num2str(learning.current.validationMistakenPatterns) ' errors)' marker]);
                end
            else
                mssg([sprintf('\t\t\t') validation_str ' validation error: ' num2str(learning.current.validationError) marker]);
            end

            if (dynamicSystem.config.useJacobianControl) && (~isempty(overIndexes))
                mssg([sprintf('\t\t\t') 'Max jacobian: ' num2str(full(learning.current.maxJac{1}))]);%fixme
            end
        end
    else    % if useValidation=0 optimalParameters are currentParameters
        if mod(learning.current.nSteps, learning.config.stepsForValidation)==0
            mssg(['step: ' num2str(learning.current.nSteps) sprintf('\ttraining error: ') num2str(learning.current.trainError)])
            learning.current.optimalParameters=dynamicSystem.parameters;
            learning.current.optimalStep=learning.current.nSteps;
            if (dynamicSystem.config.useJacobianControl) && (~isempty(overIndexes))
                mssg([sprintf('\t\t\t') 'Max jacobian: ' num2str(full(learning.current.maxJac{1}))]);
            end
            if dynamicSystem.config.useAutoSave
                autoSave;
            end
        end
    end

    %% Updating outNet weights.
    for it1=fieldnames(learning.current.outGradient)'
        IT = fieldnames(learning.current.outGradient.(char(it1)))';
%         IT = IT(outNetTrain);
        for it2=IT
            old4new=learning.current.outGradient.(char(it1)).(char(it2)) .* learning.current.rProp.oldGradient.(char(it1)).(char(it2));
            learning.current.rProp.delta.(char(it1)).(char(it2)) =...
                (old4new>0) .* min(learning.config.rProp.deltaMax,learning.config.rProp.etaP * ...
                learning.current.rProp.delta.(char(it1)).(char(it2))) ...
                +(old4new<0) .* max(learning.config.rProp.deltaMin,learning.config.rProp.etaM * ...
                learning.current.rProp.delta.(char(it1)).(char(it2))) ...
                +(old4new==0) .* learning.current.rProp.delta.(char(it1)).(char(it2));

            learning.current.rProp.deltaW.(char(it1)).(char(it2)) =...
                (old4new>0) .*(-sign(learning.current.outGradient.(char(it1)).(char(it2))) .* ...
                learning.current.rProp.delta.(char(it1)).(char(it2)))...
                +(old4new<0) .* learning.current.rProp.deltaW.(char(it1)).(char(it2)) ...
                +(old4new==0) .* (-sign(learning.current.outGradient.(char(it1)).(char(it2))) .* ...
                learning.current.rProp.delta.(char(it1)).(char(it2)));

            dynamicSystem.parameters.(char(it1)).(char(it2))=learning.history.oldP.(char(it1)).(char(it2)) ...
                +(old4new>0) .* learning.current.rProp.deltaW.(char(it1)).(char(it2)) ...
                -(old4new<0) .* learning.current.rProp.deltaW.(char(it1)).(char(it2)) ...
                +(old4new==0) .* learning.current.rProp.deltaW.(char(it1)).(char(it2));

            learning.current.rProp.oldGradient.(char(it1)).(char(it2))=...
                (old4new>=0) .* learning.current.outGradient.(char(it1)).(char(it2))...
                +(old4new<0) .* zeros(size(learning.current.outGradient.(char(it1)).(char(it2))));

%             dynamicSystem.parameters.(char(it1)).(char(it2))=learning.history.oldP.(char(it1)).(char(it2)) ...
%                 - gain * learning.current.outGradient.(char(it1)).(char(it2));
       
        end
    end
    %% Updating transitionNet weights.
    for it3 = 1:dynamicSystem.ntrans;
        IT = fieldnames(learning.current.forwardGradient.transitionNet(it3))';
%         IT = IT(transitionNetTrain);
        for it2=IT
            old4new=learning.current.forwardGradient.transitionNet(it3).(char(it2)) .* ...
                learning.current.rProp.oldGradient.transitionNet(it3).(char(it2));
            learning.current.rProp.delta.transitionNet(it3).(char(it2)) =...
                (old4new>0) .* min(learning.config.rProp.deltaMax,learning.config.rProp.etaP * ...
                learning.current.rProp.delta.transitionNet(it3).(char(it2))) ...
                +(old4new<0) .* max(learning.config.rProp.deltaMin,learning.config.rProp.etaM * ...
                learning.current.rProp.delta.transitionNet(it3).(char(it2))) ...
                +(old4new==0) .* learning.current.rProp.delta.transitionNet(it3).(char(it2));

            learning.current.rProp.deltaW.transitionNet(it3).(char(it2)) =...
                (old4new>0) .*(-sign(learning.current.forwardGradient.transitionNet(it3).(char(it2))) .* ...
                learning.current.rProp.delta.transitionNet(it3).(char(it2)))...
                +(old4new<0) .* learning.current.rProp.deltaW.transitionNet(it3).(char(it2)) ...
                +(old4new==0) .* (-sign(learning.current.forwardGradient.transitionNet(it3).(char(it2))) .* ...
                learning.current.rProp.delta.transitionNet(it3).(char(it2)));

            % Update parameters
            dynamicSystem.parameters.transitionNet(it3).(char(it2))=learning.history.oldP.transitionNet(it3).(char(it2)) ...
                +(old4new>0) .* learning.current.rProp.deltaW.transitionNet(it3).(char(it2)) ...
                -(old4new<0) .* learning.current.rProp.deltaW.transitionNet(it3).(char(it2)) ...
                +(old4new==0) .* learning.current.rProp.deltaW.transitionNet(it3).(char(it2));

                        % make transition networks fixed for some epochs
    %                         if learning.current.nSteps<=200
    %                            dynamicSystem.parameters.transitionNet(it3).(char(it2))=learning.history.oldP.transitionNet(it3).(char(it2));
    %                         end
    %                         if learning.current.nSteps==200
    %                             learning.current.rProp.delta.transitionNet(it3).(char(it2)) = 0.001 * ones(size(learning.current.rProp.delta.transitionNet(it3).(char(it2))));
    %                         end

            learning.current.rProp.oldGradient.transitionNet(it3).(char(it2))=...
                (old4new>=0) .* learning.current.forwardGradient.transitionNet(it3).(char(it2))...
                +(old4new<0) .* zeros(size(learning.current.forwardGradient.transitionNet(it3).(char(it2))));
        end
    end
    
    learning.current.nSteps=learning.current.nSteps+1;
end

if VisualMode == 1
    DisplayResults('EnableUI',GUI.DisplayResultsH,[],guihandles(GUI.DisplayResultsH));
end

