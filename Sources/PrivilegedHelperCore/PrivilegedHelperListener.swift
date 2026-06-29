import Foundation
import PrivilegedHelperProtocol

public protocol XPCConnectionConfiguring: AnyObject {
    func setCodeSigningRequirement(_ requirement: String)
    func setExportedInterface(_ interface: NSXPCInterface)
    func setExportedObject(_ object: Any)
    func resume()
}

extension NSXPCConnection: XPCConnectionConfiguring {
    public func setExportedInterface(_ interface: NSXPCInterface) {
        exportedInterface = interface
    }

    public func setExportedObject(_ object: Any) {
        exportedObject = object
    }
}

public final class PrivilegedHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    public typealias ServiceFactory = () -> Any

    public let appCodeSigningRequirement: String
    public let serviceFactory: ServiceFactory

    public init(
        appCodeSigningRequirement: String,
        serviceFactory: @escaping ServiceFactory = { PrivilegedHelperService() }
    ) throws {
        try CodeSigningRequirement.validate(appCodeSigningRequirement)

        self.appCodeSigningRequirement = appCodeSigningRequirement
        self.serviceFactory = serviceFactory
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        configure(connection: newConnection)
    }

    public func configure(connection: XPCConnectionConfiguring) -> Bool {
        connection.setCodeSigningRequirement(appCodeSigningRequirement)
        connection.setExportedInterface(NSXPCInterface(with: RoamVibingPrivilegedHelperProtocol.self))
        connection.setExportedObject(serviceFactory())
        connection.resume()

        return true
    }
}

public final class PrivilegedHelperListener {
    private let listener: NSXPCListener
    private let delegate: PrivilegedHelperListenerDelegate

    public init(
        machServiceName: String = PrivilegedHelperConstants.machServiceName,
        appCodeSigningRequirement: String,
        serviceFactory: @escaping PrivilegedHelperListenerDelegate.ServiceFactory = { PrivilegedHelperService() }
    ) throws {
        let delegate = try PrivilegedHelperListenerDelegate(
            appCodeSigningRequirement: appCodeSigningRequirement,
            serviceFactory: serviceFactory
        )

        self.listener = NSXPCListener(machServiceName: machServiceName)
        self.delegate = delegate
        self.listener.delegate = delegate
    }

    public func run() {
        listener.resume()
        RunLoop.main.run()
    }
}
