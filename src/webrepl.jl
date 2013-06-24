using Morsel
using Meddle
using JSON
using WebSockets
using REPL
using Docker

f = open("settings.yml")
settings = YAML.load(f)
close(f)
docker_host = settings["docker_host"]
worker_port = settings["worker_port"]

app = Morsel.app()

type BackendSession
    id::Uint64
    name::String
    worker_id::String
    worker_port::Uint16
    isready::Bool
    frontends::Array
end

const backend_sessions = Dict{String,BackendSession}()

immutable FrontendSession
    id::Uint64
    userid::Uint64 # Web facing user id
    username::String
    backend::BackendSession
end

const frontend_sessions = Dict{Uint64,FrontendSession}()

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

function destroy_backend(b::BackendSession)
    Docker.kill_container(docker_host,b.worker_id)
    Docker.remove_container(docker_host,b.worker_id)
    if haskey(backend_sessions,b.id)
        delete!(backend_sessions,b.id)
    end
end

function destroy_frontend(s::FrontendSession)
    idx = findfirst(s.backend.frontends)
    if idx != 0
        splice!(s.backend.frontends,idx)
        if isempty(s.backend.frontends)
            destroy_backend(s.backend)
        end
    end
    delete!(frontend_sessions,s.id)
end

post(app,"/session/new") do req,res
    data = JSON.parse(req.req.data)
    parameters = {"username" => "julia", "sessionname" => ""}
    println(data)
    for field in data
        if field["name"] == "user_name" && !isempty(field["value"])
            parameters["username"] = field["value"]
        elseif field["name"] == "session_name"
            parameters["sessionname"] = field["value"]
        end
    end
    if haskey(req.state[:cookies],"SessionId")
        id = parseint(Uint64,req.state[:cookies]["SessionId"],16)
        if haskey(frontend_sessions,id)
            destroy_frontend(frontend_sessions[id])
        end
    end
    username = parameters["username"]
    session_name = parameters["sessionname"]
    if !isempty(session_name) && haskey(backend_sessions,session_name)
        backend = backend_sessions[session_name]
    else
        worker_id = Docker.create_container(docker_host,"51d4c6302994",
                `julia -e 'cd(Pkg2.Dir.path("WebREPL","src")); include("worker.jl")'`;
                 attachStdin =  true, 
                 openStdin   =  true,
                 ports       =  [worker_port])["Id"] 
        Docker.start_container(docker_host,worker_id;binds = ["/home/ubuntu/.julia-container"=>"/.julia"])
        port = uint16(Docker.getNattedPort(docker_host,worker_id,worker_port))
        backend = BackendSession(rand(Uint64),session_name,worker_id,port,false,Array(FrontendSession,0))       
        !isempty(session_name) && (backend_sessions[session_name] = backend)
    end
    frontend = FrontendSession(rand(Uint64),rand(Uint64),username,backend)
    push!(backend.frontends,frontend)
    frontend_sessions[frontend.id] = frontend
	set_status(res,201)
	if !haskey(res.state,:cookies) 
        res.state[:cookies] = Dict{String,String}()
    end
	res.state[:cookies]["SessionId"] = string(hex(frontend.id),"; path=/")
	hex(frontend.id)
end

include("msg_types.jl")

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
        	session = frontend_sessions[parseint(Uint64,julia_msg[2],16)]
            c = Condition()
            @async begin
                stream = Docker.open_logs_stream(docker_host,session.backend.worker_id)
                while isopen(socket) && isopen(stream)
                    if !session.backend.isready && search(readline(stream),"Morsel is listening on $(dec(worker_port))...") != 0:-1
                        notify(c)
                        session.backend.isready = true
                    elseif session.backend.isready
                        data = readavailable(stream)
                        write(socket,JSON.to_json([MSG_OUTPUT_OTHER,data]))
                    end
                end
                close(stream)
            end
            !session.backend.isready && wait(c)
        	#write(socket, JSON.to_json([MSG_OUTPUT_WELCOME]))
        	reply = [MSG_OUTPUT_READY,"ws://128.52.160.116:$(dec(session.backend.worker_port))/"]
        	write(socket, JSON.to_json(reply))
        elseif msg_type == MSG_INPUT_GET_USER
        	reply = [MSG_OUTPUT_GET_USER,session.username,dec(session.userid)]
        	write(socket, JSON.to_json(reply))
        end
    end
end

start(app, parseint(settings["server_port"]))
