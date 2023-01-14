-module(shellexec_api_handler).

%% API
-export([init/2]).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% API
%%%===================================================================

init(Req0, Opts) ->
  Method = cowboy_req:method(Req0),
  HasBody = cowboy_req:has_body(Req0),
  Path = cowboy_req:path(Req0),
  Req = handle(Method, HasBody, Path, Req0),

  {ok, Req, Opts}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle(<<"POST">>, true, Path, Req0) when Path =:= <<"/">>; Path =:= <<"/script">> ->
  {ok, Body, Req} = cowboy_req:read_body(Req0),
  try
    DecodedBody = jsx:decode(Body),
    validate_body(DecodedBody),
    Sorted = topsort(maps:get(<<"tasks">>, DecodedBody, [])),
    {Result, ContentType} =
      case Path of
        <<"/">> -> {jsx:encode(handle_sorted(Sorted, [])), <<"application/json">>};
        _       -> {format_script(Sorted, [<<"#!/usr/bin/env bash">>]), <<"text/plain">>}
      end,

    cowboy_req:reply(
      200,
      #{<<"content-type">> => ContentType},
      Result,
      Req
     )
  catch
    E:R:S ->
      logger:error("~p~n~p~n~p", [E, R, S]),

      cowboy_req:reply(
        400,
        #{<<"content-type">> => <<"application/json; charset=utf-8">>},
        jsx:encode(#{<<"error">> => R}),
        Req
       )
  end;
handle(_, _, _, Req) ->
  %% Method not allowed.
  cowboy_req:reply(405, Req).

validate_body(Body) when is_map(Body) ->
  Tasks = maps:get(<<"tasks">>, Body, undefined),
  case is_list(Tasks) of
    true -> ok;
    _    -> throw(<<"Invalid tasks">>)
  end,

  [begin
     case maps:get(<<"name">>, Task, undefined) of
       Name when is_binary(Name) -> ok;
       Name -> throw(<<"Invalid task name ", (format_error(Name))/binary>>)
     end,
     case maps:get(<<"command">>, Task, undefined) of
       Command when is_binary(Command) -> ok;
       Command -> throw(<<"Invalid task command ", (format_error(Command))/binary>>)
     end,
     Requires = maps:get(<<"requires">>, Task, []),
     case Requires of
       Requires when is_list(Requires) -> ok;
       Requires -> throw(<<"Invalid task requires ", (format_error(Requires))/binary>>)
     end,
     [begin
        case is_binary(R) of
          true -> ok;
          _ -> throw(<<"Invalid task requires ", (format_error(R))/binary>>)
        end
      end || R <- Requires]
   end|| Task <- Tasks];
validate_body(_) ->
  throw(<<"Invalid body">>).

topsort(Data) ->
  G = digraph:new(),
  Proplist =
    [begin
       V = maps:get(<<"name">>, Map, undefined),
       digraph:add_vertex(G, V, Map),
       [add_required(G, V, Requires)
        || Requires <- maps:get(<<"requires">>, Map, [])],

       {V, Map}
     end || Map <- Data],

  case digraph_utils:topsort(G) of
    false ->
      [begin
         case digraph:get_short_cycle(G, V) of
           false ->
             ok;
           VS    ->
             throw(<<"Loop detected - ", (format_error(VS))/binary>>)
         end
       end || V <- digraph:vertices(G)];
    T ->
      digraph:delete(G),

      [proplists:get_value(V, Proplist) || V <- lists:reverse(T)]
  end.

add_required(_G, V, V) ->
  ok;
add_required(G, V, Requires) ->
  digraph:add_vertex(G, Requires),
  digraph:add_edge(G, V, Requires).

handle_sorted([], Tasks) ->
  #{<<"tasks">> => lists:reverse(Tasks)};
handle_sorted([H|T], Tasks) ->
  Command = maps:get(<<"command">>, H, <<>>),
  CmdResult = os:cmd(binary_to_list(Command)),
  Result =
    #{<<"name">> => maps:get(<<"name">>, H, undefined),
      <<"command">> => Command,
      <<"result">> => unicode:characters_to_binary(CmdResult)},

  handle_sorted(T, [Result|Tasks]).

format_script([], Tasks) ->
  lists:reverse(Tasks);
format_script([H|T], Tasks) ->
  Command = maps:get(<<"command">>, H, <<>>),

  format_script(T, [Command, <<"\n">>|Tasks]).

format_error(Error) ->
  unicode:characters_to_binary(io_lib:format("~p", [Error])).


topsort_test_() ->
  PosTasks =
    [#{<<"command">> => <<"touch /tmp/file1">>,
       <<"name">> => <<"task-1">>},
     #{<<"command">> => <<"cat /tmp/file1">>,
       <<"name">> => <<"task-2">>,
       <<"requires">> => [<<"task-3">>]},
     #{<<"command">> => <<"echo 'Hello World!' > /tmp/file1">>,
       <<"name">> => <<"task-3">>,
       <<"requires">> => [<<"task-1">>]},
     #{<<"command">> => <<"rm /tmp/file1">>,
       <<"name">> => <<"task-4">>,
       <<"requires">> => [<<"task-2">>,<<"task-3">>]}],
  PosResult =
    [#{<<"command">> => <<"touch /tmp/file1">>,
       <<"name">> => <<"task-1">>},
     #{<<"command">> => <<"echo 'Hello World!' > /tmp/file1">>,
       <<"name">> => <<"task-3">>,
       <<"requires">> => [<<"task-1">>]},
     #{<<"command">> => <<"cat /tmp/file1">>,
       <<"name">> => <<"task-2">>,
       <<"requires">> => [<<"task-3">>]},
     #{<<"command">> => <<"rm /tmp/file1">>,
       <<"name">> => <<"task-4">>,
       <<"requires">> => [<<"task-2">>,<<"task-3">>]}],
  NegTasks =
    [#{<<"command">> => <<"touch /tmp/file1">>,
       <<"name">> => <<"task-1">>,
       <<"requires">> => [<<"task-2">>]},
     #{<<"command">> => <<"touch /tmp/file1">>,
       <<"name">> => <<"task-2">>,
       <<"requires">> => [<<"task-1">>]}],
  NegResult =
    <<"Loop detected - [<<\"task-1\">>,<<\"task-2\">>,<<\"task-1\">>]">>,

  [?_assertEqual(topsort([]), []),
   ?_assertEqual(topsort(PosTasks), PosResult),
   ?_assertThrow(NegResult, topsort(NegTasks))].
