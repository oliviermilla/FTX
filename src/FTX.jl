module FTX

export WebSocket, open, close, ping, subscribe, unsubscribe

using HTTP.WebSockets
using JSON3
using Dates
using Logging

const WEBSOCKETS_URL = "wss://ftx.com/ws/"
const DATE_FORMAT = dateformat"Y-m-dTH:M:S.s" # UTC Time

struct Data
    id::UInt64
    size::Float32
    price::Float32
    side::String
    liquidation::Bool
    time::String # TODO change to some datetime structure
end

struct Response
    channel::String
    market::String
    type::String
    code::Union{UInt8,Nothing}
    msg::Union{String,Nothing}
    data::Union{Vector{Data},Nothing}
end

JSON3.StructTypes.StructType(::Type{Response}) = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{Data}) = JSON3.StructTypes.Struct()

const webSocket = Ref{WebSockets.WebSocket}()

function receive(channel::Channel)
    WebSockets.open(WEBSOCKETS_URL) do ws
        webSocket[] = ws
        #try
            for msg in ws
                #println(response)
                put!(channel, JSON3.read(msg, Response))
            end
        # catch error
        #     if isa(error, EOFError)
        #         println(error)
        #     else
        #         rethrow(error)
        #     end
        # end
    end
end

function send(channel::Channel)
    for msg in channel
        HTTP.WebSockets.send(webSocket[], msg)
        @info "Sent $(msg) to FTX's websocket"
    end
end

mutable struct WebSocket
    const receiveChannel::Channel #Task
    const sendChannel::Channel # Task
    function WebSocket()
        new(Channel(receive), Channel(send))
    end
end

function string_to_json(string::AbstractString)
    return JSON3.write(JSON3.read(string))
end

const pingMessage() = string_to_json("""{"op":"ping"}""")
const subscribeMessage(channel, market) = string_to_json("""{"op":"subscribe", "channel":"$(channel)", "market":"$(market)"}""")
const unsubscribeMessage(channel, market) = string_to_json("""{"op":"unsubscribe", "channel":"$(channel)", "market":"$(market)"}""")

function subscribe(socket::WebSocket, channel::String, market::String)
    message = subscribeMessage(channel, market)
    put!(socket.sendChannel, message)    
end

function unsubscribe(socket::WebSocket, channel::String, market::String)
    message = unsubscribeMessage(channel, market)
    put!(socket.sendChannel, message)
end

function ping(socket::WebSocket)
    message = pingMessage()
    put!(socket.sendChannel, message)
end

function open()::WebSocket
    return WebSocket()
end

function close()
    if isassigned(webSocket)
        WebSockets.close(webSocket[])
    end
end

function __init__()
    atexit(close)
end

# Example use

socket = open()
subscribe(socket, "trades", "ETH-PERP")
for data in socket.receiveChannel
    println(data)
end
close()

end # module FTX
