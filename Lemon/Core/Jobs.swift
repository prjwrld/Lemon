import AppKit
import Observation

/// One piece of work, shown in the progress panel with a Cancel button.
@Observable
final class Job: Identifiable {
    enum State: Equatable {
        case running
        case finished([URL])
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let title: String
    var progress: Double?          // nil = unknown, shows a spinner
    var state = State.running
    /// Short note shown when finished without files (e.g. a QR code's text).
    var message: String?
    fileprivate var task: Task<Void, Never>?

    init(title: String) { self.title = title }

    var isRunning: Bool { state == .running }

    func cancel() { task?.cancel() }
}

/// Passed to the work so it can report progress and notice Cancel.
nonisolated struct JobContext: Sendable {
    let report: @Sendable (Double) -> Void
    let note: @Sendable (String) -> Void

    func checkCancelled() throws { try Task.checkCancellation() }
}

/// Runs jobs in the background and keeps the list the progress panel shows.
@Observable
final class JobCenter {
    static let shared = JobCenter()

    private(set) var jobs: [Job] = []
    /// Called when a job finishes successfully (used for feedback and the trial counter).
    var onFinished: ((Job, [URL]) -> Void)?

    @discardableResult
    func start(_ title: String, work: @escaping @Sendable (JobContext) async throws -> [URL]) -> Job {
        let job = Job(title: title)
        jobs.append(job)

        let context = JobContext(
            report: { value in
                Task { @MainActor in
                    // Skip tiny changes so the screen isn't redrawn hundreds of times a second.
                    if abs((job.progress ?? -1) - value) >= 0.005 { job.progress = min(max(value, 0), 1) }
                }
            },
            note: { text in Task { @MainActor in job.message = text } }
        )

        job.task = Task.detached(priority: .userInitiated) {
            do {
                let urls = try await work(context)
                try Task.checkCancellation()
                await MainActor.run {
                    job.progress = 1
                    job.state = .finished(urls)
                    JobCenter.shared.onFinished?(job, urls)
                }
            } catch is CancellationError {
                await MainActor.run { job.state = .cancelled }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { job.state = .failed(message) }
            }
            await MainActor.run { JobCenter.shared.scheduleCleanup(of: job) }
        }
        return job
    }

    /// Finished jobs leave the panel after a few seconds; failures stay until closed,
    /// so the message can be read (and copied).
    fileprivate func scheduleCleanup(of job: Job) {
        if case .failed = job.state { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.remove(job)
        }
    }

    func remove(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
    }
}

/// A clear error with a message people can understand.
nonisolated struct LemonError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
