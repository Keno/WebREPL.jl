using Morsel
using Meddle
using JSON
using WebSockets
using REPL
using Gadfly
using Compose
using Color
import YAML

f = open("settings.yml")
settings = YAML.load(f)
close(f)

const dark_theme =
    Gadfly.Theme(color("steel blue"),      # default_color
          0.6mm,                    # default_point_size
          0.2mm,                    # line_width
          color("#000000"),         # panel_fill
          color("#4d87c7"),         # panel_stroke
          color("#333333"),         # grid_color
          color("#f0f0f0"),         # grid_color_focused
          0.2mm,                    # grid line width
          Gadfly.default_font_desc,        # minor_label_font
          9pt,                      # minor_label_font_size
          color("#dddddd"),         # minor_label_color
          Gadfly.default_font_desc,        # major_label_font
          11pt,                     # major_label_font_size
          color("#dddddd"),         # major_label_color
          Gadfly.default_font_desc,        # point_label_font
          8pt,                      # point_label_font_size
          color("#dddddd"),         # point_label_color
          0.0mm,                    # bar_spacing
          1mm,                      # boxplot_spacing
          0.3mm,                    # highlight_width
          Gadfly.default_highlight_color,  # highlight_color
          Gadfly.default_middle_color,     # middle_color
          1000,                     # label_placement_iterations
          10.0,                     # label_out_of_bounds_penalty
          0.5,                      # label_hidden_penalty
          0.2)                      # label_visibility_flip_pr


include("msg_types.jl")

app = Morsel.app()

import Base: repl_show

function repl_show(io::WebSocket,result,user_id) 
	message = JSON.to_json([MSG_OUTPUT_EVAL_RESULT,user_id,sprint(repl_show,result)])
	for sock in clients
		write(sock,message)
	end
end
function repl_show(io::WebSocket,p::Union(Plot,Canvas),user_id)
	p.theme = dark_theme
	div_id = "plot_$(dec(uint16(rand(Uint64))))"
	out = IOBuffer()
	draw(D3(out,6inch,6inch; emit_on_finish=false),p)
	message = JSON.to_json([MSG_OUTPUT_HTML,user_id,"""
	<div id="$(div_id)"></div>
	<script>
	(function() {
		$(takebuf_string(out))
		draw("#$(div_id)")
	})()
	</script>
	"""]) #"
	for sock in clients
		isopen(sock) && write(sock,message)
	end
end

repl_channel, response_channel = RemoteRef(),RemoteRef()
REPL.start_repl_backend(repl_channel,response_channel)

clients = Array(WebSocket,0)

websocket(app,"/") do req, res
	socket = res.res
	push!(clients,socket)
	while true
        msg = read(socket)
        julia_msg = JSON.parse(bytestring(msg))
        msg_type = julia_msg[1]
        if msg_type == MSG_INPUT_EVAL
        	username = julia_msg[2]
        	user_id = julia_msg[3]
        	ast = Base.parse_input_line(julia_msg[4])
        	put(repl_channel, (ast,1))
        	@async begin
        		message = JSON.to_json([MSG_OUTPUT_EVAL_INPUT,user_id,username,julia_msg[4]])
        		for sock in clients
        			isopen(sock) && write(sock, message)
        		end
        		(val, bt) = take(response_channel)
        		repl_show(socket,val,user_id)
        	end       	
        end
    end
    splice!(clients,findfirst(clients,socket))
end

start(app, parseint(setting["worker_port"]))