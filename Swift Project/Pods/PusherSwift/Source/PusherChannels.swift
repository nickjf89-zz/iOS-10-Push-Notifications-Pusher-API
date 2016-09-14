//
//  PusherGlobalChannel.swift
//  PusherSwift
//
//  Created by Hamilton Chapman on 01/04/2016.
//
//

open class PusherChannels: NSObject {
    open var channels = [String: PusherChannel]()

    /**
        Create a new PusherChannel, which is returned, and add it to the PusherChannels list
        of channels

        - parameter name:            The name of the channel to create
        - parameter connection:      The connection associated with the channel being created
        - parameter onMemberAdded:   A function that will be called with information about the
                                     member who has just joined the presence channel
        - parameter onMemberRemoved: A function that will be called with information about the
                                     member who has just left the presence channel

        - returns: A new PusherChannel instance
    */
    internal func add(
        name: String,
        connection: PusherConnection,
        onMemberAdded: ((PresenceChannelMember) -> ())? = nil,
        onMemberRemoved: ((PresenceChannelMember) -> ())? = nil) -> PusherChannel {
            if let channel = self.channels[name] {
                return channel
            } else {
                var newChannel: PusherChannel
                if PusherChannelType.isPresenceChannel(name: name) {
                    newChannel = PusherPresenceChannel(
                        name: name,
                        connection: connection,
                        onMemberAdded: onMemberAdded,
                        onMemberRemoved: onMemberRemoved
                    )
                } else {
                    newChannel = PusherChannel(name: name, connection: connection)
                }
                self.channels[name] = newChannel
                return newChannel
            }
    }

    /**
        Create a new PresencPusherChannel, which is returned, and add it to the PusherChannels
        list of channels

        - parameter channelName:     The name of the channel to create
        - parameter connection:      The connection associated with the channel being created
        - parameter onMemberAdded:   A function that will be called with information about the
                                     member who has just joined the presence channel
        - parameter onMemberRemoved: A function that will be called with information about the
                                     member who has just left the presence channel

        - returns: A new PusherPresenceChannel instance
    */
    internal func addPresence(
        channelName: String,
        connection: PusherConnection,
        onMemberAdded: ((PresenceChannelMember) -> ())? = nil,
        onMemberRemoved: ((PresenceChannelMember) -> ())? = nil) -> PusherPresenceChannel {
        if let channel = self.channels[channelName] as? PusherPresenceChannel {
            return channel
        } else {
            let newChannel = PusherPresenceChannel(
                name: channelName,
                connection: connection,
                onMemberAdded: onMemberAdded,
                onMemberRemoved: onMemberRemoved
            )
            self.channels[channelName] = newChannel
            return newChannel
        }
    }

    /**
        Remove the PusherChannel with the given channelName from the channels list

        - parameter name: The name of the channel to remove
    */
    internal func remove(name: String) {
        self.channels.removeValue(forKey: name)
    }

    /**
        Return the PusherChannel with the given channelName from the channels list, if it exists

        - parameter name: The name of the channel to return

        - returns: A PusherChannel instance, if a channel with the given name existed, otherwise nil
    */
    public func find(name: String) -> PusherChannel? {
        return self.channels[name]
    }
}
