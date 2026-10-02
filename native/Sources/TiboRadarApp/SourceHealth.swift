import Foundation

struct SourceHealth: Sendable {
  enum State: String, Sendable {
    case fresh, missing, cached, stale, unknown
  }

  let source: RadarSource
  let state: State
  let checkedAt: Date?

  var warning: String? {
    let label: String
    switch source {
    case .feed: label = "Tibo 动态"
    case .forecast: label = "历史预测基准"
    case .timeline: label = "重置时间线"
    case .status: label = "聚合故障记录"
    case .openAIStatus: label = "OpenAI 状态"
    }
    switch state {
    case .fresh: return nil
    case .missing: return "\(label)：来源缺失"
    case .cached: return "\(label)：正在使用缓存"
    case .stale: return "\(label)：来源已过期"
    case .unknown: return "\(label)：无法确认更新时间"
    }
  }

  static func assess(bundle: SourceBundle, now: Date = Date()) -> [SourceHealth] {
    RadarSource.allCases.map { source in
      guard let payload = bundle.payloads[source]?.objectValue else {
        return SourceHealth(source: source, state: .missing, checkedAt: nil)
      }
      // An old post or incident is not evidence that polling has stopped.
      // Prefer the upstream collection time over unrelated content updates.
      let upstreamDate = ["fetched_at", "checked_at", "updated_at"]
        .compactMap { SourceMetadata.parseDate(payload.string($0)) }.first
      let checkedAt = upstreamDate ?? bundle.receivedAt[source]
      let state: State
      if bundle.cacheFallbacks.contains(source) {
        state = .cached
      } else if payload.bool("stale") == true {
        state = .stale
      } else if let checkedAt {
        let age = now.timeIntervalSince(checkedAt)
        state = age < -300 ? .unknown : (age > 4 * 60 * 60 ? .stale : .fresh)
      } else {
        state = .unknown
      }
      return SourceHealth(source: source, state: state, checkedAt: checkedAt)
    }
  }
}
