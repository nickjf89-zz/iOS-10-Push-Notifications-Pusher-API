//
//  PusherPresenceChannel.swift
//  PusherSwift
//
//  Created by Hamilton Chapman on 01/04/2016.
//
//

public typealias PusherUserInfoObject = [String : AnyObject]

open class PusherPresenceChannel: PusherChannel {
    open var members: [PresenceChannelMember]
    open var onMemberAdded: ((PresenceChannelMember) -> ())?
    open var onMemberRemoved: ((PresenceChannelMember) -> ())?
    open var myId: String? = nil

    /**
        Initializes a new PusherPresenceChannel with a given name, conenction, and optional
        member added and member removed handler functions

        - parameter name:            The name of the channel
        - parameter connection:      The connection that this channel is relevant to
        - parameter onMemberAdded:   A function that will be called with information about the
                                     member who has just joined the presence channel
        - parameter onMemberRemoved: A function that will be called with information about the
                                     member who has just left the presence channel

        - returns: A new PusherPresenceChannel instance
    */
    init(
        name: String,
        connection: PusherConnection,
        onMemberAdded: ((PresenceChannelMember) -> ())? = nil,
        onMemberRemoved: ((PresenceChannelMember) -> ())? = nil) {
            self.members = []
            self.onMemberAdded = onMemberAdded
            self.onMemberRemoved = onMemberRemoved
            super.init(name: name, connection: connection)
    }

    /**
        Add information about the member that has just joined to the members object
        for the presence channel and call onMemberAdded function, if provided

        - parameter memberJSON: A dictionary representing the member that has joined
                                the presence channel
    */
    internal func addMember(memberJSON: [String : AnyObject]) {
        let member: PresenceChannelMember

        if let userId = memberJSON["user_id"] as? String {
            if let userInfo = memberJSON["user_info"] as? PusherUserInfoObject {
                member = PresenceChannelMember(userId: userId, userInfo: userInfo as AnyObject?)

            } else {
                member = PresenceChannelMember(userId: userId)
            }
        } else {
            if let userInfo = memberJSON["user_info"] as? PusherUserInfoObject {
                member = PresenceChannelMember(userId: String.init(describing: memberJSON["user_id"]!), userInfo: userInfo as AnyObject?)
            } else {
                member = PresenceChannelMember(userId: String.init(describing: memberJSON["user_id"]!))
            }
        }
        members.append(member)
        self.onMemberAdded?(member)
    }

    /**
        Add information about the members that are already subscribed to the presence channel to
        the members object of the presence channel

        - parameter memberHash: A dictionary representing the members that were already
                                subscribed to the presence channel
    */
    internal func addExistingMembers(memberHash: [String : AnyObject]) {
        for (userId, userInfo) in memberHash {
            let member: PresenceChannelMember
            if let userInfo = userInfo as? PusherUserInfoObject {
                member = PresenceChannelMember(userId: userId, userInfo: userInfo as AnyObject?)
            } else {
                member = PresenceChannelMember(userId: userId)
            }
            self.members.append(member)
        }
    }

    /**
        Remove information about the member that has just left from the members object
        for the presence channel and call onMemberRemoved function, if provided

        - parameter memberJSON: A dictionary representing the member that has left the
                                presence channel
    */
    internal func removeMember(memberJSON: [String : AnyObject]) {
        let id: String

        if let userId = memberJSON["user_id"] as? String {
            id = userId
        } else {
            id = String.init(describing: memberJSON["user_id"]!)
        }

        if let index = self.members.index(where: { $0.userId == id }) {
            let member = self.members[index]
            self.members.remove(at: index)
            self.onMemberRemoved?(member)
        }
    }

    /**
        Set the value of myId to the value of the user_id returned as part of the authorization
        of the subscription to the channel

        - parameter channelData: The channel data obtained from authorization of the subscription
                                 to the channel
    */
    internal func setMyUserId(channelData: String) {
        if let channelDataObject = parse(channelData: channelData), let userId = channelDataObject["user_id"] {
            self.myId = String.init(describing: userId)
        }
    }

    /**
        Parse a string to extract the channel data object from it

        - parameter channelData: The channel data string received as part of authorization

        - returns: A dictionary of channel data
    */
    fileprivate func parse(channelData: String) -> [String: AnyObject]? {
        let data = (channelData as NSString).data(using: String.Encoding.utf8.rawValue, allowLossyConversion: false)

        do {
            if let jsonData = data, let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: AnyObject] {
                return jsonObject
            } else {
                print("Unable to parse string: \(channelData)")
            }
        } catch let error as NSError {
            print(error.localizedDescription)
        }
        return nil
    }


    /**
        Returns the PresenceChannelMember object for the given user id

        - parameter userId: The user id of the PresenceChannelMember for whom you want
                            the PresenceChannelMember object

        - returns: The PresenceChannelMember object for the given user id
    */
    open func findMember(userId: String) -> PresenceChannelMember? {
        return self.members.filter({ $0.userId == userId }).first
    }

    /**
        Returns the connected user's PresenceChannelMember object

        - returns: The connected user's PresenceChannelMember object
    */
    open func me() -> PresenceChannelMember? {
        if let id = self.myId {
            return findMember(userId: id)
        } else {
            return nil
        }
    }
}

public class PresenceChannelMember: NSObject {
    public let userId: String
    public let userInfo: Any?

    public init(userId: String, userInfo: Any? = nil) {
        self.userId = userId
        self.userInfo = userInfo
    }
}
