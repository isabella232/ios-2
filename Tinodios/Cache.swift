//
//  Cache.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB
import Firebase

class Cache {
    private static let `default` = Cache()

    private var tinode: Tinode? = nil
    private var timer = RepeatingTimer(timeInterval: 60 * 60 * 4) // Once every 4 hours.
    private var largeFileHelper: LargeFileHelper? = nil
    private var queue = DispatchQueue(label: "co.tinode.cache")
    internal static let log = TinodeSDK.Log(subsystem: "co.tinode.tinodios")

    public static func getTinode() -> Tinode {
        return Cache.default.getTinode()
    }
    public static func getLargeFileHelper(withIdentifier identifier: String? = nil) -> LargeFileHelper {
        return Cache.default.getLargeFileHelper(withIdentifier: identifier)
    }
    public static func invalidate() {
        if let tinode = Cache.default.tinode {
            Cache.default.timer.suspend()
            tinode.logout()
            InstanceID.instanceID().deleteID { error in
                Cache.log.debug("Failed to delete FCM instance id: %@", error.debugDescription)
            }
            Cache.default.tinode = nil
        }
    }
    public static func isContactSynchronizerActive() -> Bool {
        return Cache.default.timer.state == .resumed
    }
    public static func synchronizeContactsPeriodically() {
        Cache.default.timer.suspend()
        // Try to synchronize contacts immediately
        ContactsSynchronizer.default.run()
        // And repeat once every 4 hours.
        Cache.default.timer.eventHandler = { ContactsSynchronizer.default.run() }
        Cache.default.timer.resume()
    }
    private func getTinode() -> Tinode {
        // TODO: fix tsan false positive.
        // TSAN fires because one thread may read |tinode| variable
        // while another thread may be writing it below in the critical section.
        if tinode == nil {
            queue.sync {
                if tinode == nil {
                    tinode = SharedUtils.createTinode()
                    // Tell contacts synchronizer to attempt to synchronize contacts.
                    ContactsSynchronizer.default.appBecameActive()
                }
            }
        }
        return tinode!
    }
    private func getLargeFileHelper(withIdentifier identifier: String?) -> LargeFileHelper {
        if largeFileHelper == nil {
            let id = identifier ?? "tinode-\(Date().millisecondsSince1970)"
            let config = URLSessionConfiguration.background(withIdentifier: id)
            largeFileHelper = LargeFileHelper(config: config)
        }
        return largeFileHelper!
    }
    public static func totalUnreadCount() -> Int {
        guard let tinode = Cache.default.tinode, let topics = tinode.getTopics() else {
            return 0
        }
        return topics.reduce(into: 0, { result, topic in
            result += topic.isReader && !topic.isMuted ? topic.unread : 0
        })
    }
}
