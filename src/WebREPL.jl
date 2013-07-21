using Morsel
using Meddle
using JSON
using WebSockets
using REPL

app = Morsel.app()

immutable Session
	id::Uint64
	repl_channel::RemoteRef
	response_channel::RemoteRef
end

sessions = Dict{Uint64,Session}()

with(app,FileServer(joinpath(pwd(),"www"))) do app
    # Fallback
    get(app, "/<*>") do req, res
        "Hi, looks like you were trying to find file \"$(req.state[:resource])\". We don't have that file, sorry!"
    end
end

get(app, "/") do req, res
    return readall(joinpath(pwd(),"www/index.htm"))
end

get(app, "/repl") do req, res
	
end

post(app,"/session/new") do req,res
	s = Session(rand(Uint64),RemoteRef(),RemoteRef())
	REPL.start_repl_backend(s.repl_channel,s.response_channel)
	if haskey(sessions,s.id)
		error("Session Collision")
	end
	sessions[s.id] = s
	set_status(res,201)
	!haskey(res.state,:cookies) && (res.state[:cookies] = Dict{String,String}())
	res.state[:cookies]["SessionId"] = string(hex(s.id),"; path=/")
	hex(s.id)
end

# input messages (to julia)
const MSG_INPUT_NULL              = 0
const MSG_INPUT_EVAL              = 1
const MSG_INPUT_REPLAY_HISTORY    = 2
const MSG_INPUT_GET_USER          = 3
const MSG_INPUT_AUTHENTICATE      = 4

# output messages (to the browser)
const MSG_OUTPUT_WELCOME          = 1
const MSG_OUTPUT_READY            = 2
const MSG_OUTPUT_MESSAGE          = 3
const MSG_OUTPUT_OTHER            = 4
const MSG_OUTPUT_EVAL_INPUT       = 5
const MSG_OUTPUT_FATAL_ERROR      = 6
const MSG_OUTPUT_EVAL_INCOMPLETE  = 7
const MSG_OUTPUT_EVAL_RESULT      = 8
const MSG_OUTPUT_EVAL_ERROR       = 9
const MSG_OUTPUT_PLOT             = 10
const MSG_OUTPUT_GET_USER         = 11
const MSG_OUTPUT_HTML             = 12

import Base: repl_show

repl_show(io::WebSocket,result) = write(io,JSON.to_json([MSG_OUTPUT_EVAL_RESULT,"0",sprint(repl_show,result)]))

websocket(app,"/repl/socket") do req,res
	socket = res.res
	session = nothing
	while true
        msg = read(socket)
        julia_msg = JSON.parse(bytestring(msg))
        msg_type = julia_msg[1]
        if msg_type == MSG_INPUT_AUTHENTICATE
        	session = sessions[parseint(Uint64,julia_msg[2],16)]
        	#write(socket, JSON.to_json([MSG_OUTPUT_WELCOME]))
        	reply = [MSG_OUTPUT_READY]
        	write(socket, JSON.to_json(reply))
        elseif msg_type == MSG_INPUT_GET_USER
        	reply = [MSG_OUTPUT_GET_USER,"Keno","0"]
        	write(socket, JSON.to_json(reply))
        elseif msg_type == MSG_INPUT_EVAL
        	username = julia_msg[2]
        	user_id = julia_msg[3]
        	ast = Base.parse_input_line(julia_msg[4])
        	write(socket, JSON.to_json([MSG_OUTPUT_EVAL_INPUT,"0","Keno",julia_msg[4]]))
        	put(session.repl_channel, (ast,1))
        	(val, bt) = take(session.response_channel)
        	repl_show(socket,val)
        end
    end
end

start(app, 8000)
