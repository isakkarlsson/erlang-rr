function visualizeBoundaryRf(X, y, predict)
%
% -- Function File: visualizeBoundaryRf(X, y, model)
%    
%    visualizes the decision boundry, given a prediction function
%       
%    Example: visualizeBoundaryRf(X, y, @(x) rfpredict(x, model))
%
	x1plot = linspace(min(X(:,1)), max(X(:,1)), 100)';
	x2plot = linspace(min(X(:,2)), max(X(:,2)), 100)';
	[X1, X2] = meshgrid(x1plot, x2plot);
	vals = zeros(size(X1));
	
	for i = 1:size(X1, 2)
	   this_X = [X1(:, i), X2(:, i)];
	   p = predict(this_X); %rfpredict(this_X, model);
	   p(p == -1) = 0;
	   vals(:, i) = p;
	end
	% Plot the SVM boundary
	hold on
	contour(X1, X2, vals, [0 0], 'Color', 'b');
	hold off;

end