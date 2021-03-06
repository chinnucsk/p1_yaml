%%%-------------------------------------------------------------------
%%% @author Evgeniy Khramtsov <>
%%% @copyright (C) 2013, Evgeniy Khramtsov
%%% @doc
%%%
%%% @end
%%% Created :  7 Aug 2013 by Evgeniy Khramtsov <>
%%%-------------------------------------------------------------------
-module(p1_yaml).

%% API
-export([load_nif/0, load_nif/1, decode/1, decode/2, start/0, stop/0,
         decode_from_file/1, decode_from_file/2, encode/1, format_error/1]).

-type option() :: {plain_as_atom, boolean()}.
-type options() :: [option()].

-define(PLAIN_AS_ATOM, 1).

%%%===================================================================
%%% API
%%%===================================================================
start() ->
    application:start(p1_yaml).

stop() ->
    application:stop(p1_yaml).

load_nif() ->
    load_nif(get_so_path()).

load_nif(LibDir) ->
    SOPath = filename:join(LibDir, "p1_yaml"),
    case catch erlang:load_nif(SOPath, 0) of
        ok ->
            ok;
        Err ->
            error_logger:warning_msg("unable to load p1_yaml NIF: ~p~n", [Err]),
            Err
    end.

-spec format_error(atom() |
                   {parser_error | scanner_error,
                    binary(),
                    non_neg_integer(), non_neg_integer()}) -> string().

format_error({Tag, Reason, Line, Column}) when Tag == parser_error;
                                               Tag == scanner_error ->
    lists:flatten(
      io_lib:format(
        "Syntax error on line ~p at position ~p: ~s",
        [Line+1, Column+1, Reason]));
format_error(memory_error) ->
    "Memory error";
format_error(unexpected_error) ->
    "Unexpected error";
format_error(Reason) ->
    file:format_error(Reason).

-spec decode(iodata()) -> {ok, term()} | {error, binary()}.

decode(Data) ->
    decode(Data, []).

-spec decode_from_file(string()) -> {ok, term()} | {error, binary()}.

decode_from_file(File) ->
    decode_from_file(File, []).

-spec decode_from_file(string(), options()) -> {ok, term()} | {error, binary()}.

decode_from_file(File, Opts) ->
    case file:read_file(File) of
        {ok, Data} ->
            decode(Data, Opts);
        Err ->
            Err
    end.

-spec decode(iodata(), options()) -> {ok, term()} | {error, binary()}.

decode(Data, Opts) ->
    nif_decode(Data, make_flags(Opts)).

-spec encode(term()) -> iolist().

encode(Term) ->
    NL = io_lib:nl(),
    case encode(Term, 0) of
        [[NL|T1]|T2] ->
            [T1|T2];
        T ->
            T
    end.

encode([{_, _}|_] = Terms, N) ->
    [[io_lib:nl(), indent(N), encode_pair(T, N)] || T <- Terms];
encode([_|_] = Terms, N) ->
    [[io_lib:nl(), indent(N), "- ", encode(T, N+2)] || T <- Terms];
encode([], _) ->
    "[]";
encode(I, _) when is_integer(I) ->
    integer_to_list(I);
encode(F, _) when is_float(F) ->
    io_lib:format("~f", [F]);
encode(A, _) when is_atom(A) ->
    atom_to_list(A);
encode(B, _) when is_binary(B) ->
    [$",
     lists:map(
       fun($") -> [$\\, $"];
          (C) -> C
       end, binary_to_list(B)),
     $"].

encode_pair({K, V}, N) ->
    [encode(K), ": ", encode(V, N+2)].

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_so_path() ->
    case os:getenv("EJABBERD_SO_PATH") of
        false ->
            case code:priv_dir(p1_yaml) of
                {error, _} ->
                    filename:join(["priv", "lib"]);
                Path ->
                    filename:join([Path, "lib"])
            end;
        Path ->
            Path
    end.

make_flags([{plain_as_atom, true}|Opts]) ->
    ?PLAIN_AS_ATOM bor make_flags(Opts);
make_flags([{plain_as_atom, false}|Opts]) ->
    make_flags(Opts);
make_flags([plain_as_atom|Opts]) ->
    ?PLAIN_AS_ATOM bor make_flags(Opts);
make_flags([Opt|Opts]) ->
    error_logger:warning_msg("p1_yaml: unknown option ~p", [Opt]),
    make_flags(Opts);
make_flags([]) ->
    0.

nif_decode(_Data, _Flags) ->
    error_logger:error_msg("p1_yaml NIF not loaded", []),
    erlang:nif_error(nif_not_loaded).

indent(N) ->
    lists:duplicate(N, $ ).

%%%===================================================================
%%% Unit tests
%%%===================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

load_nif_test() ->
    ?assertEqual(ok, load_nif(filename:join(["..", "priv", "lib"]))).

decode_test1_test() ->
    FileName = filename:join(["..", "test", "test1.yml"]),
    ?assertEqual(
       {ok,[[{<<"Time">>,<<"2001-11-23 15:01:42 -5">>},
             {<<"User">>,<<"ed">>},
             {<<"Warning">>,
              <<"This is an error message for the log file">>}],
            [{<<"Time">>,<<"2001-11-23 15:02:31 -5">>},
             {<<"User">>,<<"ed">>},
             {<<"Warning">>,<<"A slightly different error message.">>}],
            [{<<"Date">>,<<"2001-11-23 15:03:17 -5">>},
             {<<"User">>,<<"ed">>},
             {<<"Fatal">>,<<"Unknown variable \"bar\"">>},
             {<<"Stack">>,
              [[{<<"file">>,<<"TopClass.py">>},
                {<<"line">>,23},
                {<<"code">>,<<"x = MoreObject(\"345\\n\")\n">>}],
               [{<<"file">>,<<"MoreClass.py">>},
                {<<"line">>,58},
                {<<"code">>,<<"foo = bar">>}]]}]]},
       decode_from_file(FileName)).

decode_test2_test() ->
    FileName = filename:join(["..", "test", "test2.yml"]),
    ?assertEqual(
       {ok,[[[{step,[{instrument,<<"Lasik 2000">>},
                     {pulseEnergy,5.4},
                     {pulseDuration,12},
                     {repetition,1000},
                     {spotSize,<<"1mm">>}]}],
             [{step,[{instrument,<<"Lasik 2000">>},
                     {pulseEnergy,5.0},
                     {pulseDuration,10},
                     {repetition,500},
                     {spotSize,<<"2mm">>}]}],
             [{step,<<"id001">>}],
             [{step,<<"id002">>}],
             [{step,<<"id001">>}],
             [{step,<<"id002">>}]]]},
       decode_from_file(FileName, [plain_as_atom])).

decode_test3_test() ->
    FileName = filename:join(["..", "test", "test3.yml"]),
    ?assertEqual(
       {ok,[[{<<"a">>,123},
             {<<"b">>,<<"123">>},
             {<<"c">>,123.0},
             {<<"d">>,123},
             {<<"e">>,123},
             {<<"f">>,<<"Yes">>},
             {<<"g">>,<<"Yes">>},
             {<<"h">>,<<"Yes we have No bananas">>}]]},
       decode_from_file(FileName)).

decode_test4_test() ->
    FileName = filename:join(["..", "test", "test4.yml"]),
    ?assertEqual(
       {ok,[[{<<"picture">>,
              <<"R0lGODlhDAAMAIQAAP//9/X\n17unp5WZmZgAAAOfn515eXv\n"
                "Pz7Y6OjuDg4J+fn5OTk6enp\n56enmleECcgggoBADs=mZmE\n">>}]]},
       decode_from_file(FileName)).

-endif.
