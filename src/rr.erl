%%% @author Isak Karlsson <isak-kar@dsv.su.se>
%%% @copyright (C) 2013, Isak Karlsson
%%% @doc
%%%
%%% @end
%%% Created :  4 Feb 2013 by Isak Karlsson <isak-kar@dsv.su.se>
-module(rr).
-author('isak-kar@dsv.su.se').
-define(DATE, "2013-05-16").
-define(MAJOR_VERSION, "1").
-define(MINOR_VERSION, "0").
-define(REVISION, "0.0").

-define(AUTHOR, "Isak Karlsson <isak-kar@dsv.su.se>").

-export([
	 main/1,

	 show_help/3,

	 parse/2,
	 warn/1,
	 warn/2,
	 illegal/1,
	 illegal/2,
	 illegal/3,
	 illegal_option/2,
	 seconds/1,
	 
	 read_config/1,
	 get_opt_name/2,
	 any_opt/2
	]).

main(Args) ->
    Props = read_config("rr.config"),
    initialize(Props),
    case Args of
	["km"|Cmd] ->
	    km:main(Cmd);
	["rf"|Cmd] ->
	    rf:main(Cmd);
	["config"|Cmd] ->
	    case Cmd of
		["get",Var] ->
		    io:format("~s ~n", [proplists:get_value(list_to_atom(Var), Props)]);
		_Other ->
		    io:format("config: invalid argument~n")
	    end;		
	["help"|Methods] ->
	    case Methods of
		[Method] ->
		    Atom = list_to_atom(Method),
		    Atom:help();
		[] ->
		    show_help()
	    end;
	["version"] ->
	    io:format("~s~n", [show_information()]);
	[] ->
	    io:format("no command specified~n"),
	    show_help()
    end.

read_config(File) ->
    case rr_config:read_config_file(File) of
	{ok, Props} ->
	    Props;
	{error, {Line, _, Term}} ->
	    io:format("malformed configuration file: \"~s\" (line: ~p). ~n", [Term, Line]),
	    halt();
	{error, Reason} ->
	    io:format("could not read 'rr.config': '~p'. ~n", [Reason]),
	    halt()
    end.

initialize(Props) ->
    rr_config:init(Props),
    rr_log:new(proplists:get_value('log.target', Props, std_err),
	       proplists:get_value('log.level', Props, info)),
    rr_log:debug("initialized configuration file").

show_help(options, CmdSpec, Application) ->
    io:format("~s~n", [show_information()]),
    getopt:usage(CmdSpec, Application).

show_help() ->
    io:format("~s~n", [show_information()]),
    io:format("Commands:
   rf             generate a random forest
   config         set and get global configuration options
   help           show program options
   version        show program version
").

show_information() -> 
    io_lib:format("rr (Random Rule Learner) ~s.~s.~s (build date: ~s)
Copyright (C) 2013+ ~s~n", [?MAJOR_VERSION, ?MINOR_VERSION, ?REVISION, ?DATE, ?AUTHOR]).


%% configuration helpers
get_opt_name(Name, []) ->
    Name;
get_opt_name(Name, [{RealName, _, Long, _Default, _Descr}|Rest]) ->
    if Name == RealName ->
	    Long;
       true ->
	    get_opt_name(Name, Rest)
    end.
    
any_opt([], _) ->
    false;
any_opt([O|Rest], Options) ->
    case proplists:is_defined(O, Options) of
	true ->
	    O;
	false ->
	    any_opt(Rest, Options)
    end.

warn(String) ->
    io:format(standard_error, ["warn: "|String], []).
warn(String, Args) ->
    io:format(standard_error, ["warn: "|String], Args).

%% error reporting
illegal(Argument, Error) ->
    illegal(Argument, Error, []),
    halt().

illegal(Argument, Error, Args) ->
    io:format(standard_error, "rr: '~s': ~s. ~n", [Argument, io_lib:format(Error, Args)]),
    halt().

illegal_option(Argument, Option) ->
    illegal(io_lib:format("unrecognized option '~s' for '~s'", [Option, Argument])).

illegal(Error) ->
    io:format(standard_error, "rr: ~s. ~nPlease consult the manual.~n", [Error]),
    halt().

%% @doc calculates the number of seconds between now() and Time
seconds(Time) ->
    timer:now_diff(erlang:now(), Time)/1000000.

parse(Args, Options) ->
    case getopt:parse(Options, Args) of
	{ok, {Parsed, _}} -> 
	    Parsed;
	{error, {invalid_option, R}} ->
	    rr:illegal(io_lib:format("unrecognized option '~s'", [R]));
	{error, {missing_option_arg, R}} ->
	    rr:illegal(io_lib:format("missing argument to option '~s'", [rr:get_opt_name(R, Options)]));
	{error, _} ->
	    rr:illegal("unknown error")
    end.
