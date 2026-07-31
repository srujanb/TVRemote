import Foundation

struct BonjourServiceResult: Hashable, Sendable {
    let name: String
    let host: String
    let port: UInt16
}

@MainActor
final class BonjourServiceScanner: NSObject {
    private let browser = NetServiceBrowser()
    private var resolving: [NetService] = []
    private var results = Set<BonjourServiceResult>()
    private var continuation: CheckedContinuation<[BonjourServiceResult], Never>?
    private var timeoutTask: Task<Void, Never>?

    static func scan(serviceType: String, timeout: TimeInterval) async -> [BonjourServiceResult] {
        let scanner = BonjourServiceScanner()
        return await scanner.start(serviceType: serviceType, timeout: timeout)
    }

    private override init() {
        super.init()
        browser.delegate = self
    }

    private func start(serviceType: String, timeout: TimeInterval) async -> [BonjourServiceResult] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            browser.searchForServices(ofType: serviceType, inDomain: "local.")
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish()
            }
        }
    }

    private func finish() {
        guard let continuation else { return }
        browser.stop()
        timeoutTask?.cancel()
        resolving.forEach { $0.stop() }
        self.continuation = nil
        continuation.resume(returning: results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    nonisolated private static func numericHost(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let address = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return nil
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(data.count),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { return nil }
            return String(cString: host)
        }
    }
}

extension BonjourServiceScanner: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            resolving.append(service)
            service.delegate = self
            service.resolve(withTimeout: 4)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        let resolvedHost = addresses.lazy.compactMap(Self.numericHost).first
        guard let resolvedHost, let port = UInt16(exactly: sender.port) else { return }
        Task { @MainActor [weak self] in
            self?.results.insert(BonjourServiceResult(name: sender.name, host: resolvedHost, port: port))
        }
    }
}
