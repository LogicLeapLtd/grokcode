import Foundation

/// Back-pressure between the background stream reader and the `@MainActor` UI.
///
/// The provider stream (`GrokAgentSession` / `GrokCLIService`) delivers events
/// from a pipe-reader thread, one `onEvent` call per chunk. Hopping each of
/// those straight onto the main actor with its own `Task { @MainActor }` has **no
/// backpressure**: when the agent streams fast — or a looping tool re-emits its
/// (cumulative) output thousands of times — the reader enqueues main-actor tasks
/// far faster than SwiftUI can drain them. The backlog of tasks (each retaining
/// an event `String`) plus the ever-growing transcript pins the main thread
/// ("Not Responding") and grows memory without bound (observed: ~50 GB).
///
/// This coalescer collapses the firehose into at most **one** in-flight
/// main-actor flush. Events accumulate on a lock-guarded buffer; the first event
/// after a flush schedules the next one, and everything that arrives before it
/// runs is merged into that single batch. So the main actor sees O(flushes), not
/// O(events); text deltas are applied in one append per flush (one COW + one
/// re-render instead of thousands); and repeated updates to the same tool row
/// collapse to a single entry. Memory is bounded to the real transcript size
/// regardless of how fast — or how pathologically — the agent streams.
nonisolated final class StreamCoalescer: @unchecked Sendable {
    /// A merged snapshot of everything buffered since the last flush.
    struct Batch: Sendable {
        let text: String
        let reasoning: String
        let tools: [ToolEventPayload]
        let endSessionId: String?
        let ended: Bool
    }

    private let lock = NSLock()
    private var text = ""
    private var reasoning = ""
    /// Tool events in first-appearance order, merged in place by `id` so a tool
    /// that spams updates (e.g. a streaming build log) never buffers more than
    /// one entry between flushes.
    private var tools: [ToolEventPayload] = []
    private var endSessionId: String?
    private var ended = false
    private var flushScheduled = false

    private let apply: @MainActor @Sendable (Batch) -> Void

    /// - Parameter apply: invoked on the main actor once per flush with the merged
    ///   batch. Must perform the actual model mutation.
    init(apply: @escaping @MainActor @Sendable (Batch) -> Void) {
        self.apply = apply
    }

    /// Buffer one stream event (called from the background reader thread) and
    /// ensure exactly one flush is scheduled.
    func enqueue(_ event: GrokStreamEvent) {
        lock.lock()
        switch event.type {
        case "text":
            if let data = event.data { text += data }
        case "thought":
            if let data = event.data { reasoning += data }
        case "tool":
            if let tool = event.tool { mergeTool(tool) }
        case "end":
            ended = true
            if let sid = event.sessionId { endSessionId = sid }
        default:
            break
        }
        let shouldSchedule = !flushScheduled
        if shouldSchedule { flushScheduled = true }
        lock.unlock()

        if shouldSchedule {
            Task { @MainActor [weak self] in self?.flush() }
        }
    }

    /// Merge a tool payload into the pending buffer, keyed by ACP `toolCallId`.
    /// Non-empty fields win over blanks and `done` latches true — the same rules
    /// `AppViewModel.upsertToolCall` applies — so collapsing repeated updates for
    /// one id never drops a refined title/kind/detail. Caller holds `lock`.
    private func mergeTool(_ tool: ToolEventPayload) {
        guard let i = tools.firstIndex(where: { $0.id == tool.id }) else {
            tools.append(tool)
            return
        }
        let current = tools[i]
        tools[i] = ToolEventPayload(
            id: tool.id,
            title: tool.title.isEmpty ? current.title : tool.title,
            kind: tool.kind.isEmpty ? current.kind : tool.kind,
            detail: tool.detail.isEmpty ? current.detail : tool.detail,
            done: current.done || tool.done
        )
    }

    @MainActor private func flush() {
        lock.lock()
        let batch = Batch(
            text: text,
            reasoning: reasoning,
            tools: tools,
            endSessionId: endSessionId,
            ended: ended
        )
        text = ""
        reasoning = ""
        tools = []
        endSessionId = nil
        ended = false
        flushScheduled = false
        lock.unlock()

        apply(batch)
    }
}
