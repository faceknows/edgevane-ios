import Foundation
import os

enum AppLog {
    static let app = Logger(subsystem: subsystem, category: "app")
    static let http = Logger(subsystem: subsystem, category: "http")
    static let socket = Logger(subsystem: subsystem, category: "socket")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let brokerage = Logger(subsystem: subsystem, category: "brokerage")
    static let market = Logger(subsystem: subsystem, category: "market")
    static let trading = Logger(subsystem: subsystem, category: "trading")
    static let chart = Logger(subsystem: subsystem, category: "chart")
    static let push = Logger(subsystem: subsystem, category: "push")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.byteknows.moneyknows"
}
