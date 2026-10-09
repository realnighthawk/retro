import Network
import Observation

/// Whether the phone can reach the network at all. Used to decide when to send what is waiting, never to predict
/// whether a request will succeed — `Api.retry` is the real answer to that.
@MainActor
@Observable
final class Reachability {
    private(set) var online = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "org.nighthawklabs.retro.reachability"))
    }
}
