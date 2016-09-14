//
//  PusherWebsocketDelegate.swift
//  PusherSwift
//
//  Created by Hamilton Chapman on 01/04/2016.
//
//

extension PusherConnection: WebSocketDelegate {

    /**
        Delegate method called when a message is received over a websocket

        - parameter ws:   The websocket that has received the message
        - parameter text: The message received over the websocket
    */
    public func websocketDidReceiveMessage(_ ws: WebSocket, text: String) {
        self.debugLogger?("[PUSHER DEBUG] websocketDidReceiveMessage \(text)")
        if let pusherPayloadObject = getPusherEventJSON(from: text), let eventName = pusherPayloadObject["event"] as? String {
            self.handleEvent(eventName: eventName, jsonObject: pusherPayloadObject)
        } else {
            print("Unable to handle incoming Websocket message \(text)")
        }
    }

    /**
        Delegate method called when a websocket disconnected

        - parameter ws:    The websocket that disconnected
        - parameter error: The error, if one exists, when disconnected
    */
    public func websocketDidDisconnect(_ ws: WebSocket, error: NSError?) {
        // Handles setting channel subscriptions to unsubscribed wheter disconnection
        // is intentional or not
        if connectionState == .disconnecting || connectionState == .connected {
            for (_, channel) in self.channels.channels {
                channel.subscribed = false
            }
        }

        // Handle error (if any)
        guard let error = error, error.code != Int(WebSocket.CloseCode.normal.rawValue) else {
            self.debugLogger?("[PUSHER DEBUG] Deliberate disconnection - skipping reconnect attempts")
            return updateConnectionState(to: .disconnected)
        }

        print("Websocket is disconnected. Error: \(error.localizedDescription)")
        // Attempt reconnect if possible

        guard self.options.autoReconnect else {
            return updateConnectionState(to: .disconnected)
        }

        guard reconnectAttemptsMax == nil || reconnectAttempts < reconnectAttemptsMax! else {
            self.debugLogger?("[PUSHER DEBUG] Max reconnect attempts reached")
            return updateConnectionState(to: .disconnected)
        }

        guard let reachability = self.reachability, reachability.isReachable else {
            self.debugLogger?("[PUSHER DEBUG] Network unreachable so waiting to attempt reconnect")
            return updateConnectionState(to: .reconnectingWhenNetworkBecomesReachable)
        }

        if connectionState != .reconnecting {
            updateConnectionState(to: .reconnecting)
        }
        self.debugLogger?("[PUSHER DEBUG] Network reachable so will setup reconnect attempt")

        attemptReconnect()
    }

    /**
        Attempt to reconnect triggered by a disconnection
    */
    internal func attemptReconnect() {
        guard connectionState != .connected else {
            return
        }

        guard reconnectAttemptsMax == nil || reconnectAttempts < reconnectAttemptsMax! else {
            return
        }

        let reconnectInterval = Double(reconnectAttempts * reconnectAttempts)

        let timeInterval = maxReconnectGapInSeconds != nil ? min(reconnectInterval, maxReconnectGapInSeconds!)
                                                           : reconnectInterval

        if reconnectAttemptsMax != nil {
            self.debugLogger?("[PUSHER DEBUG] Waiting \(timeInterval) seconds before attempting to reconnect (attempt \(reconnectAttempts + 1) of \(reconnectAttemptsMax!))")
        } else {
            self.debugLogger?("[PUSHER DEBUG] Waiting \(timeInterval) seconds before attempting to reconnect (attempt \(reconnectAttempts + 1))")
        }

        reconnectTimer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: #selector(connect),
            userInfo: nil,
            repeats: false
        )
        reconnectAttempts += 1
    }


    public func websocketDidConnect(_ ws: WebSocket) {}
    public func websocketDidReceiveData(_ ws: WebSocket, data: Data) {}
}
