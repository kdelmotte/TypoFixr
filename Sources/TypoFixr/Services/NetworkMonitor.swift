import Foundation
import Network

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = true
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue.global(qos: .background)

    private init() {}

    func start() {
        monitor?.cancel()
        let newMonitor = NWPathMonitor()
        newMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        newMonitor.start(queue: queue)
        monitor = newMonitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
