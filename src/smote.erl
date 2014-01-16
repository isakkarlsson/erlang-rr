-module(smote).

-compile(export_all).
-include("rr.hrl").

%% @doc  
fit(Features, Examples, ExConf, Smote, K) ->
    MaxId = rr_example:count(Examples),
    NN = knn:fit(Features, Examples, ExConf, 4),
    io:format("knn~n~p~n", [NN]),
    {_, MaxCount, _} = rr_util:max(fun ({_, M, _}) -> M end, Examples),
    io:format("~p ~n", [MaxCount]),
    {ExIds, NoSmoteEx} = smote(Features, Examples, ExConf, NN, K, Smote, MaxId, MaxCount),
    {ExIds, {MaxId+1, MaxId+NoSmoteEx}}.

%% @doc
unfit(ExConf, {Start, End}) ->
    ExDb = ExConf#rr_example.examples,
    lists:foreach(fun (Id) ->
                          ets:delete(ExDb, Id)
                  end, lists:seq(Start, End)).

smote(Features, Examples, ExDb, NN, K, Smote, MaxId, MaxCount) ->
    smote_for_class(Features, Examples, ExDb, NN, K, Smote, MaxId, MaxCount, [], 0).

smote_for_class(_, [], _, _, _, _, _, _, Acc, SmoteEx) ->
    {Acc, SmoteEx};
smote_for_class(Features, [{Class, NoEx, Ex}|Rest], ExDb, 
                NN, K, Smote, MaxId, MaxCount, Acc, TotSmoteEx) ->
    if NoEx < MaxCount ->
            SmoteEx = trunc(NoEx * Smote),
            NewNoEx = NoEx + SmoteEx,
            PrEx = if NewNoEx < NoEx -> %% Smote < 1
                           rr_util:shuffle(Ex);
                      SmoteEx > NoEx -> %% Smote > 1
                           duplicate_examples(Ex, SmoteEx-1);
                      true -> %% Smote == 1
                           Ex
                   end,                           
            NewEx = smote_examples(Features, PrEx, ExDb, NN, K, MaxId, Ex),
            NewAcc = [{Class, NewNoEx, NewEx}|Acc],
            smote_for_class(Features, Rest, ExDb, NN, K, Smote, MaxId + SmoteEx, MaxCount, NewAcc, SmoteEx + TotSmoteEx);
       true ->
            smote_for_class(Features, Rest, ExDb, NN, K, Smote, MaxId, MaxCount, [{Class, NoEx, Ex}|Acc], TotSmoteEx)
    end.

duplicate_examples(Ex, NoEx) ->
    duplicate_examples(Ex, Ex, NoEx, Ex).

duplicate_examples(_, _, 0, Acc) ->
    Acc;
duplicate_examples([], ExF, NoEx, Acc) ->
    duplicate_examples(ExF, ExF, NoEx, Acc);
duplicate_examples([H|Rest], ExF, NoEx, Acc) ->
    duplicate_examples(Rest, ExF, NoEx - 1, [H|Acc]).

smote_examples(_, [], _ExDb, _NN, _K, _MaxId, Acc) ->
    Acc;
smote_examples(Features, [Ex|Rest], ExDb, NN, K, MaxId, Acc) ->
    NewId = MaxId + 1,
    KNearest = knn:pknearest(NN, Ex, K),
    insert_smote_example(Features, Ex, NewId, ExDb, KNearest),
    smote_examples(Features, Rest, ExDb, NN, K, NewId, [NewId|Acc]).

insert_smote_example(Features, OldEx, NewId, ExDb, KN) ->
    N = rr_util:shuffle(KN),
    FeatureVector = format_smote_example(Features, OldEx, N, ExDb, [NewId]),
    ets:insert(ExDb#rr_example.examples, FeatureVector).

format_smote_example([], _, _, _, Acc) ->
    list_to_tuple(lists:reverse(Acc));
format_smote_example([{Type, Axis}|Rest], OldEx, NEx, ExDb, Acc) ->
    Value = smote_value(Type, Axis, ExDb, OldEx, NEx),
    format_smote_example(Rest, OldEx, NEx, ExDb, [Value|Acc]).

smote_value(numeric, Axis, ExDb, OldEx, KN) ->
    NEx = hd(KN),
    case {rr_example:feature(ExDb, OldEx, Axis), rr_example:feature(ExDb, NEx, Axis)} of
        {'?', _} ->
            '?';
        {_, '?'} ->
            '?';
        {OldValue, NewValue} ->
            Diff = NewValue - OldValue,
            Gap = random:uniform(),
            OldValue + Gap * Diff
    end;
smote_value(categoric, Axis, ExDb, _OldEx, KN) ->
    majority_value(ExDb, Axis, KN).

majority_value(ExDb, Axis, KN) ->
    Values = lists:foldl(fun ({ExId, _Dist}, Acc) ->
                                 dict:update_counter(rr_example:feature(ExDb, ExId, Axis), 1, Acc)
                         end, dict:new(), KN),
    element(1, rr_util:max(fun ({_, V}) -> V end, dict:to_list(Values))).
                         
    
test() ->
    File = csv:binary_reader("data/test-kd.txt"),
    #rr_exset {
      features=Features, 
      examples=Examples, 
      exconf=Dataset
     } = Ds = rr_example:load(File, 4),
    NewExSet = fit(Features, Examples, Dataset, 2, 2), %% extend Dataset wiht SMOTE examples @todo fix bug
    io:format("smoted ~n"),
    print_examples(element(1, NewExSet), Dataset),
    unfit(Dataset, element(2, NewExSet)), %% remove the smoted examples
    io:format("original~n"),
    print_examples(Examples, Dataset),
    Rf = rf:new([]),
    rf:build(Rf, Ds),
    io:format("~p~n", [NewExSet]).

print_examples([], _) ->
    ok;
print_examples([{_, _, Ex}|Rest], ExSet) ->
    lists:foreach(fun (ExId) ->
                          io:format("~w ~n", [rr_example:vector(ExSet, ExId)])
                  end, Ex),
    print_examples(Rest, ExSet).
