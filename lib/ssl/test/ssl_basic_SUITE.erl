%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2019. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%

-module(ssl_basic_SUITE).

-behaviour(ct_suite).

-include_lib("common_test/include/ct.hrl").
-include_lib("ssl/src/ssl_api.hrl").

%% Callback functions
-export([all/0,
         groups/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2]).

%% Testcases
-export([app/0,
         app/1,
         appup/0,
         appup/1,
         version_option/0,
         version_option/1,
         connect_twice/0,
         connect_twice/1,
         connect_dist/0,
         connect_dist/1,
         defaults/1,
         fallback/0,
         fallback/1,
         cipher_format/0,
         cipher_format/1,
         tls_versions_option/0,
         tls_versions_option/1,
         eccs/0,
         eccs/1,
         cipher_suites/0,
         cipher_suites/1,
         cipher_suites_mix/0,
         cipher_suites_mix/1,
         unordered_protocol_versions_server/0,
         unordered_protocol_versions_server/1,
         unordered_protocol_versions_client/0,
         unordered_protocol_versions_client/1
        ]).

%% Apply export
-export([send_recv_result/1,
         tcp_send_recv_result/1,
         result_ok/1,
         protocol_info_result/1,
         version_info_result/1,
         connect_dist_s/1,
         connect_dist_c/1,
         dummy/1
        ]).

-define(TIMEOUT, 20000).
-define(EXPIRE, 10).
-define(SLEEP, 500).
-define(RENEGOTIATION_DISABLE_TIME, 12000).
-define(CLEAN_SESSION_DB, 60000).
-define(SEC_RENEGOTIATION_TIMEOUT, 30).

%%--------------------------------------------------------------------
%% Common Test interface functions -----------------------------------
%%--------------------------------------------------------------------
all() -> 
    [
     {group, basic},
     {group, options}
    ].

groups() ->
    [{basic, [], basic_tests()},
     {options, [], options_tests()}
    ].

basic_tests() ->
    [app,
     appup,    
     version_option,
     connect_twice,
     connect_dist,
     defaults,
     fallback,
     cipher_format,
     tls_versions_option,
     eccs,
     cipher_suites,
     cipher_suites_mix     
    ].

options_tests() ->
    [
     unordered_protocol_versions_server,
     unordered_protocol_versions_client].

init_per_suite(Config0) ->
    catch crypto:stop(),
    try crypto:start() of
	ok ->
	    ssl_test_lib:clean_start(),
	    %% make rsa certs using openssl
	    {ok, _} = make_certs:all(proplists:get_value(data_dir, Config0),
				     proplists:get_value(priv_dir, Config0)),
	    Config1 = ssl_test_lib:make_dsa_cert(Config0),
	    Config2 = ssl_test_lib:make_ecdsa_cert(Config1),
            Config3 = ssl_test_lib:make_rsa_cert(Config2),
	    Config = ssl_test_lib:make_ecdh_rsa_cert(Config3),
	    ssl_test_lib:cert_options(Config)
    catch _:_ ->
	    {skip, "Crypto did not start"}
    end.

end_per_suite(_Config) ->
    ssl:stop(),
    application:stop(crypto).

%%--------------------------------------------------------------------
init_per_testcase(eccs, Config) ->
    case ssl:eccs() of
        [] ->
            {skip, "named curves not supported"};
        [_|_] ->
            ssl_test_lib:ct_log_supported_protocol_versions(Config),
            ct:timetrap({seconds, 5}),
            Config
    end;
init_per_testcase(_TestCase, Config) ->
    ssl_test_lib:ct_log_supported_protocol_versions(Config),
    ct:timetrap({seconds, 5}),
    Config.

end_per_testcase(_TestCase, Config) ->
    Config.
%%--------------------------------------------------------------------
%% Test Cases --------------------------------------------------------
%%--------------------------------------------------------------------
app() ->
    [{doc, "Test that the ssl app file is ok"}].
app(Config) when is_list(Config) ->
    ok = ?t:app_test(ssl).
%%--------------------------------------------------------------------
appup() ->
    [{doc, "Test that the ssl appup file is ok"}].
appup(Config) when is_list(Config) ->
    ok = ?t:appup_test(ssl).
%%--------------------------------------------------------------------
version_option() ->
    [{doc, "Use version option and do no specify ciphers list. Bug specified incorrect ciphers"}].
version_option(Config) when is_list(Config) ->
    Versions = proplists:get_value(supported, ssl:versions()),
    [version_option_test(Config, Version) || Version <- Versions].
   
%%--------------------------------------------------------------------
connect_twice() ->
    [{doc,""}].
connect_twice(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server =
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{keepalive, true},{active, false}
					       | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client =
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{keepalive, true},{active, false}
					      | ClientOpts]}]),
    Server ! listen,

    {Client1, #sslsocket{}} =
	ssl_test_lib:start_client([return_socket,
				   {node, ClientNode}, {port, Port},
				   {host, Hostname},
				   {from, self()},
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{keepalive, true},{active, false}
					      | ClientOpts]}]),

    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
			 [self(), Client, Server]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:check_result(Server, ok, Client1, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client),
    ssl_test_lib:close(Client1).
defaults(Config) when is_list(Config)->
    Versions = ssl:versions(),
    false = lists:member(sslv3, proplists:get_value(available, Versions)),
    false = lists:member(sslv3,  proplists:get_value(supported, Versions)),
    true = lists:member('tlsv1', proplists:get_value(available, Versions)),
    false = lists:member('tlsv1',  proplists:get_value(supported, Versions)),
    true = lists:member('tlsv1.1', proplists:get_value(available, Versions)),
    false = lists:member('tlsv1.1',  proplists:get_value(supported, Versions)),
    true = lists:member('tlsv1.2', proplists:get_value(available, Versions)),
    true = lists:member('tlsv1.2',  proplists:get_value(supported, Versions)),    
    true = lists:member('dtlsv1.2', proplists:get_value(available_dtls, Versions)),
    true = lists:member('dtlsv1', proplists:get_value(available_dtls, Versions)),
    true = lists:member('dtlsv1.2', proplists:get_value(supported_dtls, Versions)),
    false = lists:member('dtlsv1', proplists:get_value(supported_dtls, Versions)).


fallback() ->
    [{doc, "Test TLS_FALLBACK_SCSV downgrade prevention"}].

fallback(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    
    Server = 
	ssl_test_lib:start_server_error([{node, ServerNode}, {port, 0}, 
					 {from, self()},
					 {options, ServerOpts}]),
    
    Port = ssl_test_lib:inet_port(Server),
    
    Client = 
        ssl_test_lib:start_client_error([{node, ClientNode},
                                         {port, Port}, {host, Hostname},
                                         {from, self()},  {options,
                                                           [{fallback, true},
                                                            {versions, ['tlsv1']}
                                                            | ClientOpts]}]),
    ssl_test_lib:check_server_alert(Server, Client, inappropriate_fallback).
   
%%--------------------------------------------------------------------
cipher_format() ->
    [{doc, "Test that cipher conversion from maps | tuples | stings to binarys works"}].
cipher_format(Config) when is_list(Config) ->
    {ok, Socket0} = ssl:listen(0, [{ciphers, ssl:cipher_suites(default, 'tlsv1.2')}]),
    ssl:close(Socket0).

%%--------------------------------------------------------------------

cipher_suites() ->
    [{doc,"Test API function cipher_suites/2, filter_cipher_suites/2"
      " and prepend|append_cipher_suites/2"}].

cipher_suites(Config) when is_list(Config) -> 
    MandatoryCipherSuiteTLS1_0TLS1_1 = #{key_exchange => rsa,
                                         cipher => '3des_ede_cbc',
                                         mac => sha,
                                         prf => default_prf},
    MandatoryCipherSuiteTLS1_0TLS1_2 = #{key_exchange =>rsa,
                                         cipher => 'aes_128_cbc',
                                         mac => sha,
                                         prf => default_prf}, 
    Version = ssl_test_lib:protocol_version(Config),
    All = [_|_] = ssl:cipher_suites(all, Version),
    Default = [_|_] = ssl:cipher_suites(default, Version),
    Anonymous = [_|_] = ssl:cipher_suites(anonymous, Version),
    true = length(Default) < length(All),
    Filters = [{key_exchange, 
                fun(dhe_rsa) -> 
                        true;
                   (_) -> 
                        false
                end
               }, 
               {cipher, 
                fun(aes_256_cbc) ->
                        true;
                   (_) -> 
                        false
                end
               },
               {mac, 
                fun(sha) ->
                        true;
                   (_) -> 
                        false
                end
               }
              ],
    Cipher = #{cipher => aes_256_cbc,
               key_exchange => dhe_rsa,
               mac => sha,
               prf => default_prf},
    [Cipher] = ssl:filter_cipher_suites(All, Filters),    
    [Cipher | Rest0] = ssl:prepend_cipher_suites([Cipher], Default),
    [Cipher | Rest0] = ssl:prepend_cipher_suites(Filters, Default),
    true = lists:member(Cipher, Default), 
    false = lists:member(Cipher, Rest0), 
    [Cipher | Rest1] = lists:reverse(ssl:append_cipher_suites([Cipher], Default)),
    [Cipher | Rest1] = lists:reverse(ssl:append_cipher_suites(Filters, Default)),
    true = lists:member(Cipher, Default),
    false = lists:member(Cipher, Rest1),
    [] = lists:dropwhile(fun(X) -> not lists:member(X, Default) end, Anonymous),
    [] = lists:dropwhile(fun(X) -> not lists:member(X, All) end, Anonymous),        
    true = lists:member(MandatoryCipherSuiteTLS1_0TLS1_1, All),
    true = lists:member(MandatoryCipherSuiteTLS1_0TLS1_2, All).

%%--------------------------------------------------------------------
cipher_suites_mix() ->
    [{doc,"Test to have old and new cipher suites at the same time"}].

cipher_suites_mix(Config) when is_list(Config) -> 
    CipherSuites = [{dhe_rsa,aes_128_cbc,sha256,sha256}, {dhe_rsa,aes_128_cbc,sha}],
    ClientOpts = ssl_test_lib:ssl_options(client_rsa_verify_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_rsa_verify_opts, Config),

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
					{host, Hostname},
					{from, self()},
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, [{versions, ['tlsv1.2']},{ciphers, CipherSuites} | ClientOpts]}]),

    ssl_test_lib:check_result(Server, ok, Client, ok),
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).
unordered_protocol_versions_server() ->
    [{doc,"Test that the highest protocol is selected even" 
      " when it is not first in the versions list."}].

unordered_protocol_versions_server(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),  

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options, [{versions, ['tlsv1.1', 'tlsv1.2']} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options, ClientOpts}]),

    ServerMsg = ClientMsg = {ok,'tlsv1.2'},    
    ssl_test_lib:check_result(Server, ServerMsg, Client, ClientMsg).

%%--------------------------------------------------------------------
unordered_protocol_versions_client() ->
    [{doc,"Test that the highest protocol is selected even" 
      " when it is not first in the versions list."}].

unordered_protocol_versions_client(Config) when is_list(Config) -> 
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),  

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options, ServerOpts }]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, protocol_info_result, []}},
					{options,  [{versions, ['tlsv1.1', 'tlsv1.2']} | ClientOpts]}]),

    ServerMsg = ClientMsg = {ok, 'tlsv1.2'},    
    ssl_test_lib:check_result(Server, ServerMsg, Client, ClientMsg).
  
connect_dist() ->
    [{doc,"Test a simple connect as is used by distribution"}].

connect_dist(Config) when is_list(Config) -> 
    ClientOpts0 = ssl_test_lib:ssl_options(client_kc_opts, Config),
    ClientOpts = [{ssl_imp, new},{active, false}, {packet,4}|ClientOpts0],
    ServerOpts0 = ssl_test_lib:ssl_options(server_kc_opts, Config),
    ServerOpts = [{ssl_imp, new},{active, false}, {packet,4}|ServerOpts0],

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),

    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {?MODULE, connect_dist_s, []}},
					{options, ServerOpts}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {?MODULE, connect_dist_c, []}},
					{options, ClientOpts}]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),

    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).
eccs() ->
    [{doc, "Test API functions eccs/0 and eccs/1"}].

eccs(Config) when is_list(Config) ->
    [_|_] = All = ssl:eccs(),
    [_|_] = Tls = ssl:eccs(tlsv1),
    [_|_] = Tls1 = ssl:eccs('tlsv1.1'),
    [_|_] = Tls2 = ssl:eccs('tlsv1.2'),
    [_|_] = Tls1 = ssl:eccs('dtlsv1'),
    [_|_] = Tls2 = ssl:eccs('dtlsv1.2'),
    %% ordering is currently not verified by the test
    true = lists:sort(All) =:= lists:usort(Tls ++ Tls1 ++ Tls2),
    ok.

tls_versions_option() ->
    [{doc,"Test API versions option to connect/listen."}].
tls_versions_option(Config) when is_list(Config) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),

    Supported = proplists:get_value(supported, ssl:versions()),
    Available = proplists:get_value(available, ssl:versions()),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
					{from, self()}, 
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, [{versions, Supported} | ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
					{host, Hostname},
					{from, self()}, 
					{mfa, {ssl_test_lib, send_recv_result_active, []}},
					{options, ClientOpts}]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    Server ! listen,				       
    Versions = remove_supported_versions(Available, Supported),
    ErrClient = ssl_test_lib:start_client_error([{node, ClientNode}, {port, Port}, 
						 {host, Hostname},
						 {from, self()},
						 {options, [{versions , Versions} | ClientOpts]}]),
    receive
	{Server, _} ->
	    ok
    end,	    
    ssl_test_lib:check_client_alert(ErrClient, protocol_version).


%%--------------------------------------------------------------------
%% callback functions ------------------------------------------------
%%--------------------------------------------------------------------
send_recv_result(Socket) ->
    ssl:send(Socket, "Hello world"),
    {ok,"Hello world"} = ssl:recv(Socket, 11),
    ok.
tcp_send_recv_result(Socket) ->
    gen_tcp:send(Socket, "Hello world"),
    {ok,"Hello world"} = gen_tcp:recv(Socket, 11),
    ok.

result_ok(_Socket) ->
    ok.


protocol_info_result(Socket) ->
    {ok, [{protocol, PVersion}]} = ssl:connection_information(Socket, [protocol]),
    {ok, PVersion}.

version_info_result(Socket) ->
    {ok, [{version, Version}]} = ssl:connection_information(Socket, [version]),
    {ok, Version}.

  
connect_dist_s(S) ->
    Msg = term_to_binary({erlang,term}),
    ok = ssl:send(S, Msg).

connect_dist_c(S) ->
    Test = binary_to_list(term_to_binary({erlang,term})),
    {ok, Test} = ssl:recv(S, 0, 10000),
    ok.

dummy(_Socket) ->
    %% Should not happen as the ssl connection will not be established
    %% due to fatal handshake failiure
    exit(kill).
%%--------------------------------------------------------------------
%% Internal functions ------------------------------------------------
%%--------------------------------------------------------------------
version_option_test(Config, Version) ->
    ClientOpts = ssl_test_lib:ssl_options(client_opts, Config),
    ServerOpts = ssl_test_lib:ssl_options(server_opts, Config),
    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = 
	ssl_test_lib:start_server([{node, ServerNode}, {port, 0}, 
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options,  [{active, false}, {versions, [Version]}| ServerOpts]}]),
    Port = ssl_test_lib:inet_port(Server),
    Client = 
	ssl_test_lib:start_client([{node, ClientNode}, {port, Port}, 
				   {host, Hostname},
				   {from, self()}, 
				   {mfa, {ssl_test_lib, send_recv_result, []}},
				   {options, [{active, false}, {versions, [Version]}| ClientOpts]}]),
    
    ct:log("Testcase ~p, Client ~p  Server ~p ~n",
	   [self(), Client, Server]),
    
    ssl_test_lib:check_result(Server, ok, Client, ok),
    
    ssl_test_lib:close(Server),
    ssl_test_lib:close(Client).

remove_supported_versions(Available, Supported) ->
    Versions0 = Available -- Supported,
    case lists:member('tlsv1.3', Versions0) andalso
        not lists:member('tlsv1.2', Versions0) of
        true ->
            %% If 'tlsv1.2' is removed, remove also 'tlsv1.3'
            Versions0 -- ['tlsv1.3'];
        _ ->
            Versions0
    end.

