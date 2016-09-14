//
//  PusherConnection.swift
//  PusherSwift
//
//  Created by Hamilton Chapman on 01/04/2016.
//
//

public typealias PusherEventJSON = [String : AnyObject]
public typealias PusherUserData = PresenceChannelMember

open class PusherConnection: NSObject {
    open let url: String
    open let key: String
    open var options: PusherClientOptions
    open var globalChannel: GlobalChannel!
    open var socketId: String?
    open var connectionState = ConnectionState.disconnected
    open var channels = PusherChannels()
    open var socket: WebSocket!
    open var URLSession: Foundation.URLSession
    open var userDataFetcher: (() -> PusherUserData)?
    open var debugLogger: ((String) -> ())?
    open weak var stateChangeDelegate: ConnectionStateChangeDelegate?
    open var reconnectAttemptsMax: Int? = 6
    open var reconnectAttempts: Int = 0
    open var maxReconnectGapInSeconds: Double? = nil
    internal var reconnectTimer: Timer? = nil
    open var subscriptionErrorHandler: ((String, URLResponse?, String?, NSError?) -> Void)?
    open var subscriptionSuccessHandler: ((String) -> Void)?

    open lazy var reachability: Reachability? = {
        let reachability = Reachability.init()
        reachability?.whenReachable = { [unowned self] reachability in
            self.debugLogger?("[PUSHER DEBUG] Network reachable")
            if self.connectionState == .disconnected || self.connectionState == .reconnectingWhenNetworkBecomesReachable {
                self.attemptReconnect()
            }
        }
        reachability?.whenUnreachable = { [unowned self] reachability in
            self.debugLogger?("[PUSHER DEBUG] Network unreachable")
        }
        return reachability
    }()

    /**
        Initializes a new PusherConnection with an app key, websocket, URL, options and URLSession

        - parameter key:        The Pusher app key
        - parameter socket:     The websocket object
        - parameter url:        The URL the connection is made to
        - parameter options:    A PusherClientOptions instance containing all of the user-speficied
                                client options
        - parameter URLSession: An NSURLSession instance for the connection to use for making
                                authentication requests

        - returns: A new PusherConnection instance
    */
    public init(
        key: String,
        socket: WebSocket,
        url: String,
        options: PusherClientOptions,
        URLSession: Foundation.URLSession = Foundation.URLSession.shared) {
            self.url = url
            self.key = key
            self.options = options
            self.URLSession = URLSession
            self.socket = socket
            super.init()
            self.socket.delegate = self
    }

    /**
        Initializes a new PusherChannel with a given name

        - parameter channelName:     The name of the channel
        - parameter onMemberAdded:   A function that will be called with information about the
                                     member who has just joined the presence channel
        - parameter onMemberRemoved: A function that will be called with information about the
                                     member who has just left the presence channel

        - returns: A new PusherChannel instance
    */
    internal func subscribe(
        channelName: String,
        onMemberAdded: ((PresenceChannelMember) -> ())? = nil,
        onMemberRemoved: ((PresenceChannelMember) -> ())? = nil) -> PusherChannel {
            let newChannel = channels.add(name: channelName, connection: self, onMemberAdded: onMemberAdded, onMemberRemoved: onMemberRemoved)
            if self.connectionState == .connected {
                if !self.authorize(newChannel) {
                    print("Unable to subscribe to channel: \(newChannel.name)")
                }
            }
            return newChannel
    }

    /**
        Initializes a new PusherChannel with a given name

        - parameter channelName:     The name of the channel
        - parameter onMemberAdded:   A function that will be called with information about the
        member who has just joined the presence channel
        - parameter onMemberRemoved: A function that will be called with information about the
        member who has just left the presence channel

        - returns: A new PusherChannel instance
    */
    internal func subscribeToPresenceChannel(
        channelName: String,
        onMemberAdded: ((PresenceChannelMember) -> ())? = nil,
        onMemberRemoved: ((PresenceChannelMember) -> ())? = nil) -> PusherPresenceChannel {
        let newChannel = channels.addPresence(channelName: channelName, connection: self, onMemberAdded: onMemberAdded, onMemberRemoved: onMemberRemoved)
        if self.connectionState == .connected {
            if !self.authorize(newChannel) {
                print("Unable to subscribe to channel: \(newChannel.name)")
            }
        }
        return newChannel
    }

    /**
        Unsubscribes from a PusherChannel with a given name

        - parameter channelName: The name of the channel
    */
    internal func unsubscribe(channelName: String) {
        if let chan = self.channels.find(name: channelName) , chan.subscribed {
            self.sendEvent(event: "pusher:unsubscribe",
                data: [
                    "channel": channelName
                ] as [String : Any]
            )
            self.channels.remove(name: channelName)
        }
    }

    /**
        Either writes a string directly to the websocket with the given event name
        and data, or calls a client event to be sent if the event is prefixed with
        "client"

        - parameter event:       The name of the event
        - parameter data:        The data to be stringified and sent
        - parameter channelName: The name of the channel
    */
    open func sendEvent(event: String, data: Any, channel: PusherChannel? = nil) {
        if event.components(separatedBy: "-")[0] == "client" {
            sendClientEvent(event: event, data: data, channel: channel)
        } else {
            let dataString = JSONStringify(["event": event, "data": data])
            self.debugLogger?("[PUSHER DEBUG] sendEvent \(dataString)")
            self.socket.write(string: dataString)
        }
    }

    /**
        Sends a client event with the given event, data, and channel name

        - parameter event:       The name of the event
        - parameter data:        The data to be stringified and sent
        - parameter channelName: The name of the channel
    */
    fileprivate func sendClientEvent(event: String, data: Any, channel: PusherChannel?) {
        if let channel = channel {
            if channel.type == .presence || channel.type == .private {
                let dataString = JSONStringify(["event": event, "data": data, "channel": channel.name] as [String : Any])
                self.debugLogger?("[PUSHER DEBUG] sendClientEvent \(dataString)")
                self.socket.write(string: dataString)
            } else {
                print("You must be subscribed to a private or presence channel to send client events")
            }
        }
    }

    /**
        JSON stringifies an object

        - parameter value: The value to be JSON stringified

        - returns: A JSON-stringified version of the value
    */
    fileprivate func JSONStringify(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value) {
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [])
                let string = String(data: data, encoding: .utf8)
                if string != nil {
                    return string!
                }
            } catch _ {
            }
        }
        return ""
    }

    /**
        Disconnects the websocket
    */
    open func disconnect() {
        if self.connectionState == .connected {
            self.reachability?.stopNotifier()
            updateConnectionState(to: .disconnecting)
            self.socket.disconnect()
        }
    }

    /**
        Establish a websocket connection
    */
    @objc open func connect() {
        if self.connectionState == .connected {
            return
        } else {
            updateConnectionState(to: .connecting)
            self.socket.connect()
            if self.options.autoReconnect {
                // can call this multiple times and only one notifier will be started
                _ = try? reachability?.startNotifier()
            }
        }
    }

    /**
        Instantiate a new GloblalChannel instance for the connection
    */
    internal func createGlobalChannel() {
        self.globalChannel = GlobalChannel(connection: self)
    }

    /**
        Add callback to the connection's global channel

        - parameter callback: The callback to be stored

        - returns: A callbackId that can be used to remove the callback from the connection
    */
    internal func addCallbackToGlobalChannel(_ callback: @escaping (Any?) -> Void) -> String {
        return globalChannel.bind(callback)
    }

    /**
        Remove the callback with id of callbackId from the connection's global channel

        - parameter callbackId: The unique string representing the callback to be removed
    */
    internal func removeCallbackFromGlobalChannel(callbackId: String) {
        globalChannel.unbind(callbackId: callbackId)
    }

    /**
        Remove all callbacks from the connection's global channel
    */
    internal func removeAllCallbacksFromGlobalChannel() {
        globalChannel.unbindAll()
    }

    /**
        Set the connection state and call the stateChangeDelegate, if set

        - parameter newState: The new ConnectionState value
    */
    internal func updateConnectionState(to newState: ConnectionState) {
        let oldState = self.connectionState
        self.connectionState = newState
        self.stateChangeDelegate?.connectionChange(old: oldState, new: newState)
    }

    /**
        Handle setting channel state and triggering unsent client events, if applicable,
        upon receiving a successful subscription event

        - parameter json: The PusherEventJSON containing successful subscription data
    */
    fileprivate func handleSubscriptionSucceededEvent(json: PusherEventJSON) {
        if let channelName = json["channel"] as? String, let chan = self.channels.find(name: channelName) {
            chan.subscribed = true
            if let eData = json["data"] as? String {
                callGlobalCallbacks(forEvent: "pusher:subscription_succeeded", jsonObject: json)
                chan.handleEvent(name: "pusher:subscription_succeeded", data: eData)
            }

            if PusherChannelType.isPresenceChannel(name: channelName) {
                if let presChan = self.channels.find(name: channelName) as? PusherPresenceChannel {
                    if let data = json["data"] as? String, let dataJSON = getPusherEventJSON(from: data) {
                        if let presenceData = dataJSON["presence"] as? [String : AnyObject],
                               let presenceHash = presenceData["hash"] as? [String : AnyObject] {
                                    presChan.addExistingMembers(memberHash: presenceHash)
                        }
                    }
                }
            }

            subscriptionSuccessHandler?(channelName)

            while chan.unsentEvents.count > 0 {
                if let pusherEvent = chan.unsentEvents.popLast() {
                    chan.trigger(eventName: pusherEvent.name, data: pusherEvent.data)
                }
            }
        }
    }

    /**
        Handle setting connection state and making subscriptions that couldn't be
        attempted while the connection was not in a connected state

        - parameter json: The PusherEventJSON containing connection established data
    */
    fileprivate func handleConnectionEstablishedEvent(json: PusherEventJSON) {
        if let data = json["data"] as? String {
            if let connectionData = getPusherEventJSON(from: data), let socketId = connectionData["socket_id"] as? String {
                self.socketId = socketId
                updateConnectionState(to: .connected)

                self.reconnectAttempts = 0
                self.reconnectTimer?.invalidate()

                for (_, channel) in self.channels.channels {
                    if !channel.subscribed {
                        if !self.authorize(channel) {
                            print("Unable to subscribe to channel: \(channel.name)")
                        }
                    }
                }
            }
        }
    }

    /**
        Handle a new member subscribing to a presence channel

        - parameter json: The PusherEventJSON containing the member data
    */
    fileprivate func handleMemberAddedEvent(json: PusherEventJSON) {
        if let data = json["data"] as? String {
            if let channelName = json["channel"] as? String, let chan = self.channels.find(name: channelName) as? PusherPresenceChannel {
                if let memberJSON = getPusherEventJSON(from: data) {
                    chan.addMember(memberJSON: memberJSON)
                } else {
                    print("Unable to add member")
                }
            }
        }
    }

    /**
        Handle a member unsubscribing from a presence channel

        - parameter json: The PusherEventJSON containing the member data
    */
    fileprivate func handleMemberRemovedEvent(json: PusherEventJSON) {
        if let data = json["data"] as? String {
            if let channelName = json["channel"] as? String, let chan = self.channels.find(name: channelName) as? PusherPresenceChannel {
                if let memberJSON = getPusherEventJSON(from: data) {
                    chan.removeMember(memberJSON: memberJSON)
                } else {
                    print("Unable to remove member")
                }
            }
        }
    }

    /**
        Handle failure of our auth endpoint

        - parameter channelName: The name of channel for which authorization failed
        - parameter data:        The error returned by the auth endpoint
    */
    fileprivate func handleAuthorizationError(forChannel channelName: String, response: URLResponse?, data: String?, error: NSError?) {
        let eventName = "pusher:subscription_error"
        let json = [
            "event": eventName,
            "channel": channelName,
            "data": data ?? ""
        ]
        DispatchQueue.main.async {
            // TODO: Consider removing in favour of exclusively using handlers
            self.handleEvent(eventName: eventName, jsonObject: json as [String : AnyObject])
        }

        subscriptionErrorHandler?(channelName, response, data, error)
    }

    /**
        Parse a string to extract Pusher event information from it

        - parameter string: The string received over the websocket connection containing
                            Pusher event information

        - returns: A dictionary of Pusher-relevant event data
    */
    open func getPusherEventJSON(from string: String) -> [String : AnyObject]? {
        let data = (string as NSString).data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false)

        do {
            if let jsonData = data, let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String : AnyObject] {
                return jsonObject
            } else {
                print("Unable to parse string from WebSocket: \(string)")
            }
        } catch let error as NSError {
            print("Error: \(error.localizedDescription)")
        }
        return nil
    }

    /**
        Parse a string to extract Pusher event data from it

        - parameter string: The data string received as part of a Pusher message

        - returns: The object sent as the payload part of the Pusher message
    */
    open func getEventDataJSON(from string: String) -> Any {
        let data = (string as NSString).data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false)

        do {
            if let jsonData = data, let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) {
                return jsonObject
            } else {
                print("Returning data string instead because unable to parse string as JSON - check that your JSON is valid.")
            }
        }
        return string
    }

    /**
        Handles incoming events and passes them on to be handled by the appropriate function

        - parameter eventName:  The name of the incoming event
        - parameter jsonObject: The event-specific data related to the incoming event
    */
    open func handleEvent(eventName: String, jsonObject: [String : AnyObject]) {
        switch eventName {
        case "pusher_internal:subscription_succeeded":
            handleSubscriptionSucceededEvent(json: jsonObject)
        case "pusher:connection_established":
            handleConnectionEstablishedEvent(json: jsonObject)
        case "pusher_internal:member_added":
            handleMemberAddedEvent(json: jsonObject)
        case "pusher_internal:member_removed":
            handleMemberRemovedEvent(json: jsonObject)
        default:
            callGlobalCallbacks(forEvent: eventName, jsonObject: jsonObject)
            if let channelName = jsonObject["channel"] as? String, let internalChannel = self.channels.find(name: channelName) {
                if let eName = jsonObject["event"] as? String, let eData = jsonObject["data"] as? String {
                    internalChannel.handleEvent(name: eName, data: eData)
                }
            }
        }
    }

    /**
        Call any global callbacks

        - parameter eventName:  The name of the incoming event
        - parameter jsonObject: The event-specific data related to the incoming event
    */
    fileprivate func callGlobalCallbacks(forEvent eventName: String, jsonObject: [String : AnyObject]) {
        if let globalChannel = self.globalChannel {
            if let eData =  jsonObject["data"] as? String {
                let channelName = jsonObject["channel"] as! String?
                globalChannel.handleEvent(name: eventName, data: eData, channelName: channelName)
            } else if let eData =  jsonObject["data"] as? [String: AnyObject] {
                globalChannel.handleErrorEvent(name: eventName, data: eData)
            }
    }
    }

    /**
        Uses the appropriate authentication method to authenticate subscriptions to private and
        presence channels

        - parameter channel:  The PusherChannel to authenticate
        - parameter callback: An optional callback to be passed along to relevant auth handlers

        - returns: A Bool indicating whether or not the authentication request was made
                   successfully
    */
    fileprivate func authorize(_ channel: PusherChannel, callback: ((Dictionary<String, String>?) -> Void)? = nil) -> Bool {
        if channel.type != .presence && channel.type != .private {
            subscribeToNormalChannel(channel)
            return true
        } else {
            if let socketID = self.socketId {
                switch self.options.authMethod {
                    case .noMethod:
                        let errorMessage = "Authentication method required for private / presence channels but none provided."
                        let error = NSError(domain: "com.pusher.PusherSwift", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: errorMessage])

                        print(errorMessage)

                        handleAuthorizationError(forChannel: channel.name, response: nil, data: nil, error: error)

                        return false
                    case .endpoint(authEndpoint: let authEndpoint):
                        let request = requestForAuthValue(from: authEndpoint, socketID: socketID, channel: channel)
                        sendAuthorisationRequest(request: request, channel: channel, callback: callback)
                        return true

                    case .authRequestBuilder(authRequestBuilder: let builder):
                        if let request = builder.requestFor(socketID: socketID, channel: channel) {
                            sendAuthorisationRequest(request: request as URLRequest, channel: channel, callback: callback)

                            return true
                        } else {
                            let errorMessage = "Authentication request could not be built"
                            let error = NSError(domain: "com.pusher.PusherSwift", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: errorMessage])

                            handleAuthorizationError(forChannel: channel.name, response: nil, data: nil, error: error)

                            return false
                        }
                    case .inline(secret: let secret):
                        var msg = ""
                        var channelData = ""
                        if channel.type == .presence {
                            channelData = getUserDataJSON()
                            msg = "\(self.socketId!):\(channel.name):\(channelData)"
                        } else {
                            msg = "\(self.socketId!):\(channel.name)"
                        }

                        let secretBuff: [UInt8] = Array(secret.utf8)
                        let msgBuff: [UInt8] = Array(msg.utf8)

                        if let hmac = try? HMAC(key: secretBuff, variant: .sha256).authenticate(msgBuff) {
                            let signature = Data(bytes: hmac).toHexString()
                            let auth = "\(self.key):\(signature)".lowercased()

                            if channel.type == .private {
                                self.handlePrivateChannelAuth(authValue: auth, channel: channel, callback: callback)
                            } else {
                                self.handlePresenceChannelAuth(authValue: auth, channel: channel, channelData: channelData, callback: callback)
                            }
                        }

                        return true
                }
            } else {
                print("socketId value not found. You may not be connected.")
                return false
            }
        }
    }

    /**
        Calls the provided userDataFetcher function, if provided, otherwise will
        use the socketId as the user_id and return that stringified

        - returns: A JSON stringified user data object
    */
    fileprivate func getUserDataJSON() -> String {
        if let userDataFetcher = self.userDataFetcher {
            let userData = userDataFetcher()
            if let userInfo: Any = userData.userInfo {
                return JSONStringify(["user_id": userData.userId, "user_info": userInfo])
            } else {
                return JSONStringify(["user_id": userData.userId])
            }
        } else {
            if let socketId = self.socketId {
                return JSONStringify(["user_id": socketId])
            } else {
                print("Authentication failed. You may not be connected")
                return ""
            }
        }
    }

    /**
        Send subscription event for subscribing to a public channel

        - parameter channel:  The PusherChannel to subscribe to
    */
    fileprivate func subscribeToNormalChannel(_ channel: PusherChannel) {
        self.sendEvent(
            event: "pusher:subscribe",
            data: [
                "channel": channel.name
            ]
        )
    }

    /**
     Creates an authentication request for the given authEndpoint

        - parameter endpoint: The authEndpoint to which the request will be made
        - parameter socketID: The socketId of the connection's websocket
        - parameter channel:  The PusherChannel to authenticate subsciption for

        - returns: NSURLRequest object to be used by the function making the auth request
    */
    fileprivate func requestForAuthValue(from endpoint: String, socketID: String, channel: PusherChannel) -> URLRequest {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.httpBody = "socket_id=\(socketID)&channel_name=\(channel.name)".data(using: String.Encoding.utf8)

        return request
    }

    /**
        Send authentication request to the authEndpoint specified

        - parameter request:  The request to send
        - parameter channel:  The PusherChannel to authenticate subsciption for
        - parameter callback: An optional callback to be passed along to relevant auth handlers
    */
    fileprivate func sendAuthorisationRequest(request: URLRequest, channel: PusherChannel, callback: (([String : String]?) -> Void)? = nil) {
        let task = URLSession.dataTask(with: request, completionHandler: { data, response, sessionError in
            if let error = sessionError {
                print("Error authorizing channel [\(channel.name)]: \(error)")
                self.handleAuthorizationError(forChannel: channel.name, response: response, data: nil, error: error as NSError?)
                return
            }

            guard let data = data else {
                print("Error authorizing channel [\(channel.name)]")
                self.handleAuthorizationError(forChannel: channel.name, response: response, data: nil, error: nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) else {
                let dataString = String(data: data, encoding: String.Encoding.utf8)
                print ("Error authorizing channel [\(channel.name)]: \(dataString)")
                self.handleAuthorizationError(forChannel: channel.name, response: response, data: dataString, error: nil)
                return
            }

            guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []), let json = jsonObject as? [String: AnyObject] else {
                print("Error authorizing channel [\(channel.name)]")
                self.handleAuthorizationError(forChannel: channel.name, response: httpResponse, data: nil, error: nil)
                return
            }

            self.handleAuthResponse(json: json, channel: channel, callback: callback)
        })

        task.resume()
    }

    /**
        Handle authentication request response and call appropriate handle function

        - parameter json:     The auth response as a dictionary
        - parameter channel:  The PusherChannel to authenticate subsciption for
        - parameter callback: An optional callback to be passed along to relevant auth handlers
    */
    fileprivate func handleAuthResponse(
        json: [String : AnyObject],
        channel: PusherChannel,
        callback: (([String : String]?) -> Void)? = nil) {
            if let auth = json["auth"] as? String {
                if let channelData = json["channel_data"] as? String {
                    handlePresenceChannelAuth(authValue: auth, channel: channel, channelData: channelData, callback: callback)
                } else {
                    handlePrivateChannelAuth(authValue: auth, channel: channel, callback: callback)
                }
            }
    }

    /**
        Handle presence channel auth response and send subscribe message to Pusher API

        - parameter auth:        The auth string
        - parameter channel:     The PusherChannel to authenticate subsciption for
        - parameter channelData: The channelData to send along with the auth request
        - parameter callback:    An optional callback to be called with auth and channelData, if provided
    */
    fileprivate func handlePresenceChannelAuth(
        authValue: String,
        channel: PusherChannel,
        channelData: String,
        callback: (([String : String]?) -> Void)? = nil) {
            (channel as? PusherPresenceChannel)?.setMyUserId(channelData: channelData)

            if let cBack = callback {
                cBack(["auth": authValue, "channel_data": channelData])
            } else {
                self.sendEvent(
                    event: "pusher:subscribe",
                    data: [
                        "channel": channel.name,
                        "auth": authValue,
                        "channel_data": channelData
                    ]
                )
            }
    }

    /**
        Handle private channel auth response and send subscribe message to Pusher API

        - parameter auth:        The auth string
        - parameter channel:     The PusherChannel to authenticate subsciption for
        - parameter callback:    An optional callback to be called with auth and channelData, if provided
    */
    fileprivate func handlePrivateChannelAuth(
        authValue auth: String,
        channel: PusherChannel,
        callback: (([String : String]?) -> Void)? = nil) {
            if let cBack = callback {
                cBack(["auth": auth])
            } else {
                self.sendEvent(
                    event: "pusher:subscribe",
                    data: [
                        "channel": channel.name,
                        "auth": auth
                    ]
                )
            }
    }
}

@objc public enum ConnectionState: Int {
    case connecting
    case connected
    case disconnecting
    case disconnected
    case reconnecting
    case reconnectingWhenNetworkBecomesReachable
}

@objc public protocol ConnectionStateChangeDelegate: class {
    func connectionChange(old: ConnectionState, new: ConnectionState)
}
