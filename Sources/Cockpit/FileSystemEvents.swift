import CoreServices
import Foundation

enum FileSystemEvent: Equatable, Sendable {
    case changed(URL)
    case historyDropped
    case rootUnavailable(URL)
}

protocol FileSystemEventSource: AnyObject {
    func startWatching(paths: [URL], handler: @escaping @Sendable ([FileSystemEvent]) -> Void)
    func stopWatching()
}

final class ControllableFileSystemEvents: FileSystemEventSource, @unchecked Sendable {
    private var handler: (@Sendable ([FileSystemEvent]) -> Void)?

    func startWatching(paths: [URL], handler: @escaping @Sendable ([FileSystemEvent]) -> Void) {
        self.handler = handler
    }

    func stopWatching() { handler = nil }

    func send(_ event: FileSystemEvent) { handler?([event]) }
}

final class MacOSFileSystemEvents: FileSystemEventSource, @unchecked Sendable {
    private var stream: FSEventStreamRef?

    deinit { stopWatching() }

    func startWatching(paths: [URL], handler: @escaping @Sendable ([FileSystemEvent]) -> Void) {
        stopWatching()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passRetained(EventHandler(handler)).toOpaque(), retain: nil, release: { pointer in
            guard let pointer else { return }
            Unmanaged<EventHandler>.fromOpaque(pointer).release()
        }, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, filesystemEventsCallback, &context, paths.map(\.path) as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
                                                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    func stopWatching() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamRelease(stream)
    }
}

private final class EventHandler: @unchecked Sendable {
    let receive: @Sendable ([FileSystemEvent]) -> Void
    init(_ receive: @escaping @Sendable ([FileSystemEvent]) -> Void) { self.receive = receive }
}

private func filesystemEventsCallback(_ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ eventCount: Int, _ eventPaths: UnsafeMutableRawPointer, _ eventFlags: UnsafePointer<FSEventStreamEventFlags>, _ eventIds: UnsafePointer<FSEventStreamEventId>) {
    guard let info else { return }
    let handler = Unmanaged<EventHandler>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
    let events = zip(paths, 0 ..< Int(eventCount)).map { path, offset -> FileSystemEvent in
        let flags = eventFlags[offset]
        if flags & (FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)) != 0 {
            return .historyDropped
        }
        let url = URL(fileURLWithPath: path)
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 { return .rootUnavailable(url) }
        return .changed(url)
    }
    handler.receive(events)
}
