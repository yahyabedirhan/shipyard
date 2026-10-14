import Foundation
import os

/// Watches the configuration file's directory and calls `onChange` (on the
/// main actor) once changes have settled for 200 ms. The ping store is
/// watched as a folder instead (`init(folder:)`): only the folder itself,
/// so a save beside it (`state.json`) doesn't fire.
///
/// Editors and agents usually save by writing a new file and renaming it
/// over the old one, which leaves a watch on the old file's descriptor
/// looking at a file that's gone. So the watch is on the directory, which
/// sees every create, rename and delete in it. An in-place write (`>>`)
/// doesn't touch the directory, so the file itself is watched too, and both
/// watches are opened again after every change: the file may be a new one
/// now. When the directory doesn't exist (yet), its nearest existing
/// ancestor is watched instead, so creating it is noticed.
@MainActor
final class ConfigurationWatcher {
    private enum Target {
        case file(URL)
        case folder(@MainActor () -> URL)
    }

    private struct Handles: @unchecked Sendable {
        var directory: (any DispatchSourceFileSystemObject)?
        var file: (any DispatchSourceFileSystemObject)?

        mutating func cancel() {
            directory?.cancel()
            file?.cancel()
            directory = nil
            file = nil
        }
    }

    private let target: Target
    private let debounce: TimeInterval
    private let onChange: @MainActor () -> Void
    nonisolated private let handles = OSAllocatedUnfairLock(initialState: Handles())
    private var pending: DispatchWorkItem?

    init(file: URL, debounce: TimeInterval = 0.2, onChange: @escaping @MainActor () -> Void) {
        target = .file(file)
        self.debounce = debounce
        self.onChange = onChange
    }

    init(folder: @escaping @MainActor () -> URL, debounce: TimeInterval = 0.2, onChange: @escaping @MainActor () -> Void) {
        target = .folder(folder)
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        handles.withLock { $0.cancel() }
    }

    func start() {
        watch()
    }

    private func watch() {
        let directory: (any DispatchSourceFileSystemObject)?
        let file: (any DispatchSourceFileSystemObject)?
        switch target {
        case .file(let fileURL):
            directory = source(at: Self.nearestExisting(fileURL.deletingLastPathComponent()), events: [.write, .delete, .rename])
            file = source(at: fileURL, events: [.write, .extend, .delete, .rename, .attrib])
        case .folder(let folder):
            directory = source(at: folder(), events: [.write, .delete, .rename])
            file = nil
        }
        handles.withLock { state in
            state.cancel()
            state.directory = directory
            state.file = file
        }
    }

    private func source(at url: URL, events: DispatchSource.FileSystemEvent) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.settled() }
        }
        pending = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: settle)
    }

    private func settled() {
        pending = nil
        watch()
        onChange()
    }

    private static func nearestExisting(_ url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}
