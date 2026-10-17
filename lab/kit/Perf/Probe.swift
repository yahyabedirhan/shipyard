import Darwin
import Foundation
import Synchronization

/// Counters the copied views and model bump where the work happens (each
/// marked `// lab probe` at its call), so the perf meter can say how often
/// SwiftUI evaluated a body or the model recomputed a tab per second. A
/// `Mutex` keeps a bump cheap enough to leave in a hot path.
public enum Probe {
    public enum Point: String, CaseIterable, Sendable {
        case tabsBody = "TabsLayout.body"
        case tabContent = "tabContent(for:)"
        case tabListBody = "TabList.body"
        case tabRowBody = "TabRow.body"
        case itemRowBody = "ItemRow.body"
        case rowGeometry = "row geometry report"
        case rowHover = "row hover"
    }

    private static let counts = Mutex<[Point: Int]>([:])

    public static func hit(_ point: Point) {
        counts.withLock { $0[point, default: 0] += 1 }
    }

    /// The counts since the last call, which resets them.
    public static func drain() -> [Point: Int] {
        counts.withLock { counts in
            defer { counts = [:] }
            return counts
        }
    }
}

/// Watches the main thread from a background queue: how much of each
/// interval it spent on the CPU (from the kernel's own accounting of the
/// thread, as `sample` shows it) and how late a block posted to it every
/// 8 ms ran (a stall: a frame the panel couldn't draw).
public final class MainThreadMeter: @unchecked Sendable {
    public struct Reading: Sendable {
        /// The main thread's share of wall time on the CPU, 0–100.
        public var busy: Double
        /// The longest a posted block waited, in milliseconds.
        public var worstStall: Double
        /// Blocks that waited longer than a 60 Hz frame (16.7 ms).
        public var droppedFrames: Int
    }

    public static let shared = MainThreadMeter()

    private let queue = DispatchQueue(label: "lab.main-thread-meter", qos: .userInteractive)
    private var mainThread: thread_act_t = 0
    private var lastCPU: Double = 0
    private var lastWall: Double = 0
    private let stalls = Mutex<(worst: Double, dropped: Int)>((0, 0))
    private var pinger: DispatchSourceTimer?

    /// Starts watching; call it on the main thread, which it records.
    @MainActor public func start() {
        guard pinger == nil else { return }
        mainThread = mach_thread_self()
        lastCPU = cpuTime()
        lastWall = Self.now()
        pinger = makePinger()
    }

    private let episode = Mutex<Double>(0)

    /// Made outside the main actor: the handler runs on `queue`.
    private nonisolated func makePinger() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { @Sendable [weak self] in
            let posted = Self.now()
            DispatchQueue.main.async { @Sendable in self?.record(waited: (Self.now() - posted) * 1000) }
        }
        timer.resume()
        return timer
    }

    private func record(waited: Double) {
        stalls.withLock { value in
            value.worst = max(value.worst, waited)
            if waited > 16.7 { value.dropped += 1 }
        }
        episode.withLock { $0 = max($0, waited) }
    }

    /// Starts an episode, such as one tab switch: `endEpisode()` gives the
    /// longest stall since, apart from the readings.
    public func beginEpisode() {
        episode.withLock { $0 = 0 }
    }

    public func endEpisode() -> Double {
        episode.withLock { $0 }
    }

    /// What happened since the last reading.
    public func read() -> Reading {
        let cpu = cpuTime(), wall = Self.now()
        let busy = wall > lastWall ? min(100, max(0, (cpu - lastCPU) / (wall - lastWall) * 100)) : 0
        lastCPU = cpu
        lastWall = wall
        let (worst, dropped) = stalls.withLock { value in
            defer { value = (0, 0) }
            return value
        }
        return Reading(busy: busy, worstStall: worst, droppedFrames: dropped)
    }

    private func cpuTime() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
        return user + system
    }

    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1e9
    }
}
