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
    for msg in webSocket[]
        #println(response)
        put!(channel, JSON3.read(msg, Response))
    end
end

function send(channel::Channel)
    for msg in channel
        WebSockets.Sockets.send(webSocket[], msg)
        @info "Sent $(msg) to FTX's websocket"
    end
end

function connection(receiveChannel::Channel, sendChannel::Channel)
    WebSockets.open(WEBSOCKETS_URL) do ws
        while true
            if !isempty(sendChannel)
                for msg in sendChannel
                    Sockets.send(ws, msg)
                end
            end
            if !isempty(ws)
                for msg in ws
                    put!(receiveChannel, JSON3.read(msg, Response))
                end
            end
        end
    end
end

struct WebSocket
    receiveChannel::Channel #Task
    sendChannel::Channel # Task
    function WebSocket(initialSubscriptions::AbstractDict{String,String})
        if isempty(initialSubscriptions)
            throw(ArgumentError("argument must not be an empty dictionnary"))
        end
        # Create a connection task and bind it to both send and receive channels
        @task connection()
        # Create send channel before receive and send first subscriptions
        sendChan = Channel(send)
        for (key, value) in initialSubscriptions
            message = subscribeMessage(key, value)
            put!(sendChan, message)
        end
        new(Channel(receive), sendChan)
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

function open(initialSubscriptions::AbstractDict{String,String})::WebSocket
    return WebSocket(initialSubscriptions)
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

socket = open(Dict("trades" => "ETH-PERP"))
subscribe(socket, "trades", "BTC-PERP")
for data in socket.receiveChannel
    println(data)
end
close()

end # module FTX
