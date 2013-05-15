%%% @author Isak Karlsson <isak-kar@dsv.su.se>
%%% @copyright (C) 2013, Isak Karlsson
%%% @doc
%%%
%%% @end
%%% Created : 12 Feb 2013 by Isak Karlsson <isak-kar@dsv.su.se>

-module(rr_eval).

-export([
	 cross_validation/3,
	 split_validation/3,

	 accuracy/1,
	 auc/2,
	 brier/2,
	 precision/1]).

%% @headerfile "rr_tree.hrl"
-include("rr.hrl"). %% note: for specs


-type result_list() :: {atom(), any()} | {atom(), any(), any()}.
-type result() :: {{atom(), atom(), Model::any()}, [result_list(),...]}.
-type result_set() :: {cv, Folds::integer(), [result(),...]} | {split, result()}.

%% @doc
%% Do cross-validation on Examples
%% @end
-spec cross_validation(features(), examples(), any()) -> result_set().
cross_validation(Features, Examples, Props) ->
    Build = case proplists:get_value(build, Props) of
		undefined -> throw({badarg, build});
		Build0 -> Build0
	    end,
    Evaluate = case proplists:get_value(evaluate, Props) of
		   undefined -> throw({badarg, evaluate});
		   Evaluate0 -> Evaluate0
	       end,
    NoFolds = proplists:get_value(folds, Props, 10),
    ToAverage = proplists:get_value(average, Props, [accuracy, auc, oob_accuracy, brier]),
    Progress = proplists:get_value(progress, Props, fun (_) -> ok end),

    Total = rr_example:cross_validation(
	      fun (Train, Test, Fold) ->
		      Progress(Fold),
		      Model = Build(Features, Train),
		      Result = Evaluate(Model, Test),
		      {{fold, Fold, Model}, Result}
	      end, NoFolds, Examples),
    Avg = average_cross_validation(Total, NoFolds, ToAverage, []),
    {cv, NoFolds, Total ++ [Avg]}.

%% @private average cross-validation
average_cross_validation(_, _, [], Acc) ->
    {{fold, average, undefined}, lists:reverse(Acc)};
average_cross_validation(Avg, Folds, [H|Rest], Acc) ->
    A = lists:foldl(fun ({_, Measures}, Sum) ->
			    case lists:keyfind(H, 1, Measures) of
				{H, _, Auc} ->
				    Sum + Auc;
				{H, O} ->
				    Sum + O
			    end
		    end, 0, Avg) / Folds,
    average_cross_validation(Avg, Folds, Rest, [{H, A}|Acc]).

%% @doc split examples and train and evaluate
-spec split_validation(features(), examples(), any()) -> result_set().
split_validation(Features, Examples, Props) ->
    Build = case proplists:get_value(build, Props) of
		undefined -> throw({badarg, build});
		Build0 -> Build0
	    end,
    Evaluate = case proplists:get_value(evaluate, Props) of
		   undefined -> throw({badarg, evaluate});
		   Evaluate0 -> Evaluate0
	       end,

    Ratio = proplists:get_value(ratio, Props, 0.66),
    {Train, Test} = rr_example:split_dataset(Examples, Ratio),
    Model = Build(Features, Train),
    Result = Evaluate(Model, Test),
    {split, {{split, Ratio, Model}, Result}}.
	
%% @doc 
%% Calculate the accuracy (i.e. the percentage of correctly
%% classified examples) 
%% @end
-spec accuracy(dict()) -> Accuracy::float().
accuracy(Predictions) ->
    {Correct, Incorrect} = correct(Predictions),
    Correct / (Correct + Incorrect).

%% @private containing number of {Correct, Incorrect} predictions
correct(Predictions) ->
    dict:fold(fun (Actual, Values, Acc) ->
		      lists:foldl(fun({{Predict, _}, _Probs},  {C, I}) ->
					  case Actual == Predict of
					      true -> {C+1, I};
					      false -> {C, I+1}
					  end
				  end, Acc, Values)
	      end, {0, 0}, Predictions).

%% @doc
%% Calculate the area under ROC for predictions (i.e. the ability of
%% the model to rank true positives ahead of false positives)
%% @end
-spec auc(dict(), integer()) -> [{Class::atom(), NoExamples::integer(), Auc::float()}].
auc(Predictions, NoExamples) ->
    calculate_auc_for_classes(dict:fetch_keys(Predictions), Predictions, NoExamples, []).

calculate_auc_for_classes([], _, _, Acc) ->
    Acc;
calculate_auc_for_classes([Pos|Rest], Predictions, NoExamples, Auc) ->
    PosEx = dict:fetch(Pos, Predictions),
    Sorted = sorted_predictions(
	       lists:map(fun ({_, P}) -> {pos, find_prob(Pos, P)} end, PosEx), 
	       dict:fold(fun(Class, Values, Acc) ->
				 if Class /= Pos ->
					 lists:foldl(fun({_, P}, Acc0) ->
							     [{neg, find_prob(Pos, P)}|Acc0] 
						     end, Acc, Values);
				    true ->
					 Acc
				 end
			 end, [], Predictions)),
    NoPosEx = length(PosEx),
    if NoPosEx > 0 ->
	    calculate_auc_for_classes(Rest, Predictions, NoExamples, 
				      [{Pos, NoPosEx, calculate_auc(Sorted, 0, 0, 0, 0, -1, 
								    NoPosEx, NoExamples - NoPosEx, 0)}|Auc]);
       true ->
	    calculate_auc_for_classes(Rest, Predictions, NoExamples,
				      [{Pos, NoPosEx, 'n/a'}|Auc])
    end.

%% @private calculate auc
calculate_auc([], _Tp, _Fp, Tp_prev, Fp_prev, _Prob_prev, NoPos, NoNeg, Auc) ->
    (Auc + abs(NoNeg - Fp_prev) * (NoPos + Tp_prev)/2)/(NoPos * NoNeg);
calculate_auc([{Class, Prob}|Rest], Tp, Fp, Tp_prev, Fp_prev, OldProb, NoPos, NoNeg, Auc) ->
    {NewAuc, NewProb, NewFp_p, NewTp_p} = if Prob /= OldProb ->
					      {Auc + abs(Fp - Fp_prev) * (Tp + Tp_prev) / 2, Prob, Fp, Tp};
					 true ->
					      {Auc, OldProb, Fp_prev, Tp_prev}
				      end,
    {NewTp, NewFp} = if Class == pos ->
			     {Tp + 1, Fp};
			true ->
			     {Tp, Fp + 1}
		     end,
    calculate_auc(Rest, NewTp, NewFp, NewTp_p, NewFp_p, NewProb, NoPos, NoNeg, NewAuc).
					      
sorted_predictions(Pos, Neg) ->
    lists:sort(fun({_, A}, {_, B}) -> A > B end, Pos ++ Neg).

%% @private Find probability for predicting "Class" in range [0, 1]
find_prob(Class, Probs) ->
    case lists:keyfind(Class, 1, Probs) of
	{Class, Prob} ->
	    Prob;
	false ->
	    0
    end.

%% @doc
%% Calculate the brier score for predictions (i.e. the mean square
%% difference between the predicted probability assigned to the
%% possible outcomes and the actual outcome)
%% @end
-spec brier(dict(), integer()) -> Brier::float().
brier(Predictions, NoExamples) ->
   calculate_brier_score_for_classes(dict:fetch_keys(Predictions), Predictions, 0) / NoExamples.

calculate_brier_score_for_classes([], _, Score) ->
    Score;
calculate_brier_score_for_classes([Actual|Rest], Predictions, Score) ->
    calculate_brier_score_for_classes(Rest, Predictions, 
				      calculate_brier_score(dict:fetch(Actual, Predictions), Actual, Score)).

%% @private
calculate_brier_score([], _, Score) ->
    Score;
calculate_brier_score([{_, Probs}|Rest], Actual, Score) ->
    calculate_brier_score(Rest, Actual, lists:foldl(fun ({Class, Prob}, Acc) ->
							    if Class == Actual ->
								    Acc + math:pow(1 - Prob, 2);
							       true ->
								    Acc + math:pow(Prob, 2)
							    end
						    end, Score, Probs)).

%% @doc Calculate the precision when predicting each class
-spec precision(dict()) -> [{Class::atom(), Precision::float()}].
precision(Predictions) ->
    precision_for_classes(dict:fetch_keys(Predictions), Predictions, []).

precision_for_classes([], _, Acc) ->
    Acc;
precision_for_classes([Actual|Rest], Predictions, Acc) ->
    {Tp, Fp} = lists:foldl(fun ({{Pred, _}, _}, {Tp, Fp}) ->
				   if Pred == Actual ->
					   {Tp + 1, Fp};
				      true -> 
					   {Tp, Fp + 1}
				   end
			   end, {0, 0}, dict:fetch(Actual, Predictions)),
    precision_for_classes(Rest, Predictions, [{Actual, Tp / (Tp + Fp)}|Acc]).

