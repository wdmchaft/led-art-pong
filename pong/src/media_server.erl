%% @author Huib Verweij <hhv@home.nl
%% @doc Server that receives and interprets commands.
%% This module receives commands and executes media commands,
%% like playing sounds. Any command not executed is assumed to be
%% a LED command and is sent to the local ser2net gateway. 
%% @copyright 2009 Led-Art.nl &amp; Huib Verweij.

-module(media_server).

-behaviour(gen_server).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("protocol.hrl").
-include("media.hrl").


%% --------------------------------------------------------------------
%% External exports
-export([start_link/1, add_socket/1, reconnect_server/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {listen, socket, input, led_server}).

%% ====================================================================
%% External functions
%% ====================================================================
%%
%% Starts the server
%%
start_link(Args) -> 
	gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

add_socket(Socket) ->
	gen_server:call(?MODULE, {add_socket, Socket}),
	ok.
	
%
% (Re)connect the LEDserver.
reconnect_server() ->
	gen_server:call(?MODULE, {reconnect_server}).

%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init([Port, {LS_Host, LS_Port}]) ->
	io:format("~p starting~n", [?MODULE]),
	spawn(fun() ->
				  periodically_reconnect_server(10000) end),
	{ok, Listen} = gen_tcp:listen(Port, [binary,{packet,0},
								  {reuseaddr, true}, {active, true}]),
	Server = self(),
	link(spawn(fun() ->
				  wait_for_connection(Listen, Server) end)),
    {ok, #state{listen = Listen, socket = void, input = <<>>, led_server = {LS_Host, LS_Port, void}}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call({add_socket, Socket}, _From, State) ->
	io:format("~p: handle_call {add_socket,~p}~n", [?MODULE, Socket]),
    {reply, ok, State#state{socket=Socket}};


% Called periodically to try to connect to unconnected server.
handle_call({reconnect_server}, _From, #state{led_server={_, _, void}} = State) ->
	Server = self(),
	spawn(fun() -> connect_to_led_server(State#state.led_server, Server) end),
    {reply, ok, State};
% Server is already connected, so do not try to connect.
handle_call({reconnect_server}, _From, State) ->
    {reply, ok, State};

% Yippie, we have a new connection to the LEDserver!
% Replace {H, P, _, _} with {H, P, Socket, <<>>} in the LEDserver list.
handle_call({add_LEDserver, {Host, Port, Socket}}, _From, State) ->
	{reply, ok, State#state{led_server = {Host, Port, Socket}}};

handle_call(_Request, _From, State) ->
	io:format("~p: handle_call Request=~p~n", [?MODULE, _Request]),
    Reply = ok,
    {reply, Reply, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------

%% @doc Received Bin from Socket, process_input([Input, Bin]).
%% 
%% @spec handle_info({tcp, Socket, Bin}, State) -> NewState. 
handle_info({tcp, Socket, Bin}, #state{led_server = LEDserver, socket = Socket, input = Input} = State) ->
	% error_logger:info_msg("received Bin=~p~n", [Bin]),
	NewBin = process_input(list_to_binary([Input, Bin]), LEDserver),
    {noreply, State#state{input = NewBin}};

handle_info({tcp, LS_Socket, Bin}, #state{led_server = {_, _, LS_Socket}, socket = Socket, input = Input} = State) ->
	io:format("received Bin from LEDserver=~p~n", [Bin]),
	gen_tcp:send(Socket, Bin),
    {noreply, State};
	
% The connection was lost, set Socket to void.
handle_info({tcp_closed, Socket}, #state{socket = Socket} = State) ->
	{noreply, State#state{socket = void, input = <<>>}};

handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% Function: wait_for_connection/1 ->
%% Description: Wait for socket connection
%% --------------------------------------------------------------------
wait_for_connection(Listen, Server) ->
	{ok, Socket} = gen_tcp:accept(Listen),
	gen_tcp:controlling_process(Socket, Server),
	{ok, {Host, _Port}} = inet:peername(Socket),
	io:format("~p: connection from ~p~n", [?MODULE, Host]),
	add_socket(Socket).
	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% @doc Process input from the server.
% @spec Return updated Bin (possible garbage and first n commands removed).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
process_input(Bin, LEDserver) ->
	%% io:format("~p: process_input(~p)~n", [?MODULE, Bin]),
	Cleaned = remove_garbage(Bin),
	if 
		size(Cleaned) >= 7 ->
			{Command, Rest} = split_binary(Cleaned, 7),
			process_command(Command, LEDserver),
			process_input(Rest, LEDserver);
		true ->
			Cleaned
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Remove every byte that is not the ?HEADER from the front of Bin.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
remove_garbage(<<?HEADER:8, _>> = Bin) -> Bin;
remove_garbage(<<_:8, Bin>>) -> remove_garbage(Bin);
remove_garbage(Any) -> Any.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Process command from server.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Check the checksum, ignore any commands that fail the checksum check.
process_command(<<Header:8, D1:8, D2:8, D3:8, D4:8, D5:8, Checksum:8>> = Bin, LEDserver) ->
	<<CalculatedChecksum>> = <<(lists:sum([Header, D1, D2, D3, D4, D5])):8>>,
	if
		(CalculatedChecksum == Checksum) ->
			interpret_command(Bin, LEDserver);
		true ->
			error_logger:info_msg("~p: bad checksum in ~p, Checksum=~p, CalculatedChecksum=~p, D1=~p~n", [?MODULE, Bin, Checksum, CalculatedChecksum, D1]),
			void
	end.



% @doc Interpret the bytes and execute the command.
% @spec interpret_command(Bin, _). 
interpret_command(<<?PLAY_SOUND:8/integer, ?MEDIA_BUTTON_PRESSED_CMD:8/integer, _Dummy:32/integer>> = _Bin, _) ->
	io:format("~p Playing sound! Excellent!~n", [?MODULE]),
	executives:play_sound(?MEDIA_BUTTON_PRESSED);

% @doc Send any other command to the LEDserver.
% @spec interpret_command(Bin, LEDserver)
interpret_command(_Bin, {_, _, void} = _LEDserver) ->
	void;
interpret_command(Bin, {_, _, Socket} = _LEDserver) ->
	gen_tcp:send(Socket, Bin).
	
%% @doc Periodically connect to the LEDserver.
%%

periodically_reconnect_server(T) ->
	media_server:reconnect_server(),
	receive	after T -> true	end,
	periodically_reconnect_server(T).


% Connect to the LEDserver (LS_Host/LS_Port) using gen_tcp module.
connect_to_led_server({LS_Host, LS_Port, _}, Server) ->
	io:format("~p: trying to connect to server ~p:~p~n", [?MODULE, LS_Host, LS_Port]),
	case gen_tcp:connect(LS_Host, LS_Port, [binary, {packet,0}, inet], 3000) of
		{ok, Socket} ->
			gen_tcp:controlling_process(Socket, Server),
			error_logger:info_msg("~p: connected to server ~p:~p~n", [?MODULE, LS_Host, LS_Port]),
			gen_server:call(?MODULE, {add_LEDserver, {LS_Host, LS_Port, Socket}});
		{error, _Errorcode} ->
			error_logger:info_msg("~p: failed to connect to server ~p:~p: ~p~n", [?MODULE, LS_Host, LS_Port, _Errorcode]),
			void
	end.
