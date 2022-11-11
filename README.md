# FTX
FTX API connector in Julia

Send an receive are run as asynchronous tasks.
Data is received through a Channel subscription:

```julia
using FTX

ftxWebSocket = open()
subscribe(ftxWebSocket, "trades", "ETH-PERP")

for data in ftxWebSocket.receiveChannel
    println(data)
end

close()
```
