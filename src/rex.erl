%%% @author Isak Karlsson <isak@Unkown-MacBook-Pro.local>
%%% @copyright (C) 2013, Isak Karlsson
%%% @doc
%%%
%%% @end
%%% Created : 17 Sep 2013 by Isak Karlsson <isak@Unkown-MacBook-Pro.local>

-module(rex).
-behaviour(rr_command).
-behaviour(rr_module).
-include("rex.hrl").

-export([
	 parse_args/1,
	 main/1,
	 help/0,
	 args/1,
	 new/1,
	 run/2
	]).

-define(CMD_SPEC, 
	[{<<"input">>,          $i,           "input",        string, 
	  "Specifies the input dataset in csv-format with rows of equal length. The first row must describe the type of attributes as 'numeric' or 'categoric' and exactly one 'class'. The second row name each attribute including the class. Finally, every row below the first two describe exactly one example."},
	 {<<"min_confidence">>,  undefined, "min-confidence",  {float, 0.7},
	  "Minimum confidence required for rule"},
	 {<<"min_coverage">>,    undefined, "min-coverage",    {float, 0.3},
	  "Minimum coverage required for a rule"},
	 {<<"classifier">>,      $c,        "classifer",       {string, "rf -n 1"},
	  "Random Forest classifier options"}
	]).
-define(NAME, "rex").

parse_args(Args) ->
    rr:parse(?NAME, Args, ?CMD_SPEC).

main(Args) ->
    Opts = args(Args),
    Rex = new(Opts),
    run(Rex, args(<<"input">>, Args, fun rr:invalid_option/2)).
    

help() ->
    rr:show_help(options, ?CMD_SPEC, "rf").

args(Args) ->
    Error = fun (Value, Reason) -> throw({bad_arg, "rf", Value, Reason}) end,
    [{min_confidence, args(<<"min_confidence">>, Args, Error)},
     {min_coverage, args(<<"min_coverage">>, Args, Error)},
     {classifier, args(<<"classifier">>, Args, Error)}].

args(Key, Args, Error) ->
    Value = proplists:get_value(Key, Args),
    case Key of
	<<"classifier">> ->
	    classifier(Value, Error);
	_ ->
	    Value
    end.

classifier(Value, Error) ->
    case rr:parse_string_args(Value) of
	{Method, Args} ->
	    Opts = Method:args(Args, Error),
	    Rf = Method:new(Opts),
	    fun (ExSet) ->
		    Pid = Method:build(Rf, ExSet),
		    Method:get(Pid)		    
	    end;
	_ ->
	    Error("classifier", Value)
    end.

new(Opts) ->
    #rex {
       classifier = proplists:get_value(classifier, Opts),
       confidence = proplists:get_value(min_confidence, Opts),
       coverage = proplists:get_value(min_coverage, Opts)
      }.

run(Rex, Dataset) ->
    #rex {
       classifier = Classifier,
       confidence = Confidence,
       coverage = Coverage
      } = Rex,
    ExSet = rr_example:load(csv:binary_reader(Dataset), 4),
    Model = Classifier(ExSet),
    Rules = rr_rex:extract(hd(Model), Confidence, Coverage, rr_example:count(ExSet#rr_exset.examples)),
    io:format("~p ~n", [Rules]),
    ok.
