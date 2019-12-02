import NIO
import NIOWebSocket
import NIOHTTP1
import NIOSSL
import Foundation
import NIOFoundationCompat

public final class WebSocket {
    enum PeerType {
        case server
        case client
    }

    public var eventLoop: EventLoop {
        return channel.eventLoop
    }

    public private(set) var isClosed: Bool

    public var onClose: EventLoopFuture<Void> {
        return self.channel.closeFuture
    }

    private let channel: Channel
    private var onTextCallback: (WebSocket, String) -> ()
    private var onBinaryCallback: (WebSocket, ByteBuffer) -> ()
    private var frameSequence: WebSocketFrameSequence?
    private let type: PeerType

    init(channel: Channel, type: PeerType) {
        self.channel = channel
        self.type = type
        self.onTextCallback = { _, _ in }
        self.onBinaryCallback = { _, _ in }
        self.isClosed = false
    }

    public func onText(_ callback: @escaping (WebSocket, String) -> ()) {
        self.onTextCallback = callback
    }

    public func onBinary(_ callback: @escaping (WebSocket, ByteBuffer) -> ()) {
        self.onBinaryCallback = callback
    }

    public func send<S>(_ text: S, promise: EventLoopPromise<Void>? = nil)
        where S: Collection, S.Element == Character
    {
        let string = String(text)
        var buffer = channel.allocator.buffer(capacity: text.count)
        buffer.writeString(string)
        self.send(raw: buffer.readableBytesView, opcode: .text, fin: true, promise: promise)

    }

    public func send(_ binary: [UInt8], promise: EventLoopPromise<Void>? = nil) {
        self.send(raw: binary, opcode: .binary, fin: true, promise: promise)
    }

    public func send<Data>(
        raw data: Data,
        opcode: WebSocketOpcode,
        fin: Bool = true,
        promise: EventLoopPromise<Void>? = nil
    )
        where Data: DataProtocol
    {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let frame = WebSocketFrame(
            fin: fin,
            opcode: opcode,
            maskKey: self.makeMaskKey(),
            data: buffer
        )
        self.channel.writeAndFlush(frame, promise: promise)
    }

    public func close(code: WebSocketErrorCode = .goingAway) -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.close(code: code, promise: promise)
        return promise.futureResult
    }

    public func close(
        code: WebSocketErrorCode = .goingAway,
        promise: EventLoopPromise<Void>?
    ) {
        guard !self.isClosed else {
            promise?.succeed(())
            return
        }
        self.isClosed = true

        var buffer = channel.allocator.buffer(capacity: 2)
        buffer.write(webSocketErrorCode: code)

        self.send(raw: buffer.readableBytesView, opcode: .connectionClose, fin: true, promise: promise)
    }

    func makeMaskKey() -> WebSocketMaskingKey? {
        switch type {
        case .client:
            var bytes: [UInt8] = []
            for _ in 0..<4 {
                bytes.append(.random(in: .min ..< .max))
            }
            return WebSocketMaskingKey(bytes)
        case .server:
            return nil
        }
    }

    func handle(incoming frame: WebSocketFrame) {
        switch frame.opcode {
        case .connectionClose:
            if self.isClosed {
                // peer confirmed close, time to close channel
                self.channel.close(mode: .all, promise: nil)
            } else {
                // peer asking for close, confirm and close channel
                var data = frame.data
                self.close(code: data.readWebSocketErrorCode() ?? .goingAway).whenComplete { _ in
                    self.channel.close(mode: .all, promise: nil)
                }
            }
        case .ping:
            if frame.fin {
                self.send(
                    raw: frame.data.readableBytesView,
                    opcode: .pong,
                    fin: true,
                    promise: nil
                )
            } else {
                self.close(code: .protocolError, promise: nil)
            }
        case .text, .binary:
            // create a new frame sequence or use existing
            var frameSequence: WebSocketFrameSequence
            if let existing = self.frameSequence {
                frameSequence = existing
            } else {
                frameSequence = WebSocketFrameSequence(type: frame.opcode)
            }
            // append this frame and update the sequence
            frameSequence.append(frame)
            self.frameSequence = frameSequence
        case .continuation:
            // we must have an existing sequence
            if var frameSequence = self.frameSequence {
                // append this frame and update
                frameSequence.append(frame)
                self.frameSequence = frameSequence
            } else {
                self.close(code: .protocolError, promise: nil)
            }
        default:
            // We ignore all other frames.
            break
        }

        // if this frame was final and we have a non-nil frame sequence,
        // output it to the websocket and clear storage
        if let frameSequence = self.frameSequence, frame.fin {
            switch frameSequence.type {
            case .binary:
                self.onBinaryCallback(self, frameSequence.binaryBuffer)
            case .text:
                self.onTextCallback(self, frameSequence.textBuffer)
            default: break
            }
            self.frameSequence = nil
        }
    }

    deinit {
        assert(self.isClosed, "WebSocket was not closed before deinit.")
    }
}

extension WebSocket {
    public static func connect(
        to url: String,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: EventLoopGroup,
        onUpgrade: @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        guard let url = URL(string: url) else {
            return eventLoopGroup.next().makeFailedFuture(WebSocketClient.Error.invalidURL)
        }
        return self.connect(
            to: url,
            headers: headers,
            configuration: configuration,
            on: eventLoopGroup,
            onUpgrade: onUpgrade
        )
    }

    public static func connect(
        to url: URL,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: EventLoopGroup,
        onUpgrade: @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        let scheme = url.scheme ?? "ws"
        return self.connect(
            scheme: scheme,
            host: url.host ?? "localhost",
            port: url.port ?? (scheme == "wss" ? 443 : 80),
            path: url.path,
            headers: headers,
            configuration: configuration,
            on: eventLoopGroup,
            onUpgrade: onUpgrade
        )
    }

    public static func connect(
        scheme: String = "ws",
        host: String,
        port: Int = 80,
        path: String = "/",
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: EventLoopGroup,
        onUpgrade: @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        return WebSocketClient(
            eventLoopGroupProvider: .shared(eventLoopGroup),
            configuration: configuration
        ).connect(
            scheme: scheme,
            host: host,
            port: port,
            path: path,
            headers: headers,
            onUpgrade: onUpgrade
        )
    }
}

private struct WebSocketFrameSequence {
    var binaryBuffer: ByteBuffer
    var textBuffer: String
    var type: WebSocketOpcode

    init(type: WebSocketOpcode) {
        self.binaryBuffer = ByteBufferAllocator().buffer(capacity: 0)
        self.textBuffer = .init()
        self.type = type
    }

    mutating func append(_ frame: WebSocketFrame) {
        var data = frame.unmaskedData
        switch type {
        case .binary:
            self.binaryBuffer.writeBuffer(&data)
        case .text:
            if let string = data.readString(length: data.readableBytes) {
                self.textBuffer += string
            }
        default: break
        }
    }
}
