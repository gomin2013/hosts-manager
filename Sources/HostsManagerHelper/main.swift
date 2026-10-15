import Foundation
import os
import Shared

// Phase 1 placeholder. Phase 2: NSXPCListener(machServiceName: HelperConstants.machServiceName) with a
// code-signing requirement, plus the write pipeline (validate → SHA check → backup → atomic write → DNS flush).
let logger = Logger(subsystem: "com.hostsmanager", category: "helper")
logger.info("HostsManagerHelper placeholder for \(HelperConstants.machServiceName, privacy: .public)")
