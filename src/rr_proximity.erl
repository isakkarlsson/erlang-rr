%%% @author Isak Karlsson <isak@dhcp-159-52.dsv.su.se>
%%% @copyright (C) 2013, Isak Karlsson
%%% @doc
%%% Module for generating a proximity matrix from an induced model
%%% @end
%%% Created : 21 Mar 2013 by Isak Karlsson <isak@dhcp-159-52.dsv.su.se>
-module(rr_proximity).
-export([generate_proximity/3,
	 examples/1,
	 init/0]).

-include("rr.hrl").

init() ->
    catch ets:delete(proximity),
    ets:new(proximity, [named_table, public, {read_concurrency, true}]).


examples(ExId0) ->
    ExId = rr_example:exid(ExId0),
    ets:lookup_element(proximity, ExId, 2).
    

generate_proximity(Model, Examples, #rr_ensemble{no_classifiers=Trees} = Conf) ->
    Dict = generate_proximity(Model, Examples, Conf, dict:new()),
    Prox = generate_promixity(Dict, Trees),
    dict:fold(fun (I, V, _) ->
		      List0 = dict:fold(fun (J, Count, Acc) ->
						[{J, Count}|Acc]
					end, [], V),
		      List = lists:reverse(lists:keysort(2, List0)),
		      ets:insert(proximity, {I, List}) %% NOTE: only store a subset?
	      end, [], Prox),
    Model ! {exit, self()}.

generate_promixity(Dict, Trees) ->
    dict:fold(fun (_, Value, Acc) ->
		      lists:foldl(fun (I, Dict0) ->
					  lists:foldl(fun (J, Dict1) ->
							      if I =/= J ->
								      dict:update(I, fun (Dict2) ->
											  dict:update_counter(J, 1*(1/Trees), Dict2)
										  end, dict:store(J, 1, dict:new()), Dict1);
								 true ->
								      Dict1
							      end
						      end, Dict0, Value)
				  end, Acc, Value)
	      end, dict:new(), Dict).
					  
		  

generate_proximity(_, [], _, Acc) ->
    Acc;
generate_proximity(Model, [{_, _, ExIds}|Rest], Conf, Dict) ->
    NewDict = generate_proximity_for_class(Model, ExIds, Conf, Dict),
    generate_proximity(Model, Rest, Conf, NewDict).

generate_proximity_for_class(_, [], _Conf, Dict) ->
    Dict;
generate_proximity_for_class(Model, [ExId|Rest], Conf, Dict) ->
    Model ! {evaluate, self(), ExId},
    receive
	{prediction, Model, Predictions} ->
	    NewDict = lists:foldl(fun ({_P, NodeNr}, Acc) ->
					  dict:update(NodeNr,
						      fun (ExIds) ->
							      [ExId|ExIds]
						      end, [ExId], Acc)
				  end, Dict, Predictions),
	    generate_proximity_for_class(Model, Rest, Conf, NewDict)
    end.




%% %%
%% %% Distribute missing values by sampling from the proximate examples
%% %%
%% proximity(_, {{Type, Feature}, Value} = F, ExId, NoLeft, NoRight) ->
%%     Prox = rr_proximity:examples(ExId),
%%     Avg = average_proximity(Type, Feature, Prox, 5),
%%     case Avg of
%% 	 '?' ->
%% 	    weighted(build, F, ExId, NoLeft, NoRight);
%% 	 Avg ->
%% 	    {direction(Type, Value, Avg), exid(ExId)}
%%     end.    

%% %%
%% %% NOTE: this is really bad..
%% %%
%% average_proximity(numeric, FeatureId, Prox, N) ->
%%     mean_proximity(Prox, FeatureId, N, []);
%% average_proximity(categoric, FeatureId, Prox, N) ->
%%     mode_proximity(Prox, FeatureId, N, dict:new()).

%% mode_proximity(Prox, FeatureId, N, Dict) -> 
%%     case Prox of
%% 	[] ->
%% 	    [{F, _}|_] = lists:reverse(lists:keysort(2, dict:to_list(Dict))),
%% 	    F;
%% 	_ when N == 0 ->
%% 	    [{F, _}|_] = lists:reverse(lists:keysort(2, dict:to_list(Dict))),
%% 	    F;
%% 	['?'|Rest] ->
%% 	    io:format(standard_error, "Missing value... ~n", []),
%% 	    mode_proximity(Rest, FeatureId, N, Dict);
%% 	[{P, _Score}|Rest] ->
%% 	    mode_proximity(Rest, FeatureId, N, dict:update_counter(P, 1, Dict))
%%     end.
	    
%% mean_proximity([], _, _, List) ->
%%     case List of
%% 	[] ->
%% 	    '?';
%% 	_ ->
%% 	    lists:sum(List) / length(List)
%%     end;
%% mean_proximity(_, _, 0, List) ->
%%     case List of
%% 	[] ->
%% 	    '?';
%% 	_ ->
%% 	    lists:sum(List) / length(List)
%%     end;
%% mean_proximity([{Proximity, _Score}|Rest], FeatureId, N, Acc) ->
%%     Value = rr_example:feature(Proximity, FeatureId),
%%     case Value of
%% 	'?' ->
%% 	    mean_proximity(Rest, FeatureId, N - 1, Acc);
%% 	_ ->
%% 	    mean_proximity(Rest, FeatureId, N - 1, [Value|Acc])
%%     end.
