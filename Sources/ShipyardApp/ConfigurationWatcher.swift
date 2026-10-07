import Foundation

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
    /// What to watch: a file in its directory, or a folder alone, which
    /// says where it is each time the watch opens (it may have been created).
    private enum Target {
        case file(URL)
        case folder(@MainActor () -> URL)
    }

    private let target: Target
    private let debounce: TimeInterval
    private let onChange: @MainActor () -> Void
    // Written on the main actor only; `deinit` cancels them (closing the descriptors).
    nonisolated(unsafe) private var directorySource: (any DispatchSourceFileSystemObject)?
    nonisolated(unsafe) private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pending: DispatchWorkItem?

    init(file: URL, debounce: TimeInterval = 0.2, onChange: @escaping @MainActor () -> Void) {
        target = .file(file)
        self.debounce = debounce
        self.onChange = onChange
    }

    /// Watches the folder `folder` returns, asked again each time the watch
    /// opens: a create, rename or delete in it, or the folder itself going.
    /// Nothing beside it, such as a save to its parent.
    init(folder: @escaping @MainActor () -> URL, debounce: TimeInterval = 0.2, onChange: @escaping @MainActor () -> Void) {
        target = .folder(folder)
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
    }

    func start() {
        watch()
    }

    /// (Re)opens both watches on whatever is at the paths now.
    private func watch() {
        directorySource?.cancel()
        fileSource?.cancel()
        switch target {
        case .file(let file):
            directorySource = source(at: Self.nearestExisting(file.deletingLastPathComponent()), events: [.write, .delete, .rename])
            fileSource = source(at: file, events: [.write, .extend, .delete, .rename, .attrib])
        case .folder(let folder):
            directorySource = source(at: folder(), events: [.write, .delete, .rename])
            fileSource = nil
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

    /// Something changed: wait for the burst of events a save makes to end.
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

    /// `url`, or its closest ancestor that exists.
    private static func nearestExisting(_ url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}
