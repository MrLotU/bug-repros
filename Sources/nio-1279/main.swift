import Foundation
import NIO
import NIOWebSocket

let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let prom = elg.next().makePromise(of: Void.self)

let ws = WebSocket.connect(to: URL(string: "wss://gateway.discord.gg/?v=6&encoding=json")!, on: elg) { (socket) in
    print("Sock connected")
    socket.onText { _, text in
        let prom = elg.next().makePromise(of: Void.self)
        prom.futureResult.whenFailure { err in
            print(err.localizedDescription, err)
        }
        print(text)
        socket.send("text", promise: prom)
    }
}
try! prom.futureResult.wait()
