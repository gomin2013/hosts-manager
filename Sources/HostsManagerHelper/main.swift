import Foundation
import Shared

// Root LaunchDaemon registered by the app with SMAppService.daemon; launchd starts it on demand when the app
// connects to the Mach service.
let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
