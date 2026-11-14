import Foundation
import Combine

@MainActor final class PlaybackController: ObservableObject {
 @Published var albumID: UUID? { didSet { defaults.set(albumID?.uuidString, forKey: "currentAlbum") } }
 @Published private(set) var ids: [String] = []
 @Published var currentID: String?
 @Published var isPlaying = false
 @Published var shuffle: Bool { didSet { defaults.set(shuffle, forKey: "shuffle"); remaining = []; history = [] } }
 @Published var interval: Double { didSet { if !interval.isFinite || interval < 1 { interval = 60 }; defaults.set(interval, forKey: "interval"); resetTimer() } }
 private let defaults: UserDefaults
 private var timer: Task<Void, Never>?
 private var remaining: [String] = []
 private var history: [String] = []
 init(defaults: UserDefaults = .standard) { self.defaults = defaults; shuffle = defaults.bool(forKey: "shuffle"); let saved = defaults.double(forKey: "interval"); interval = saved >= 1 ? saved : 60; albumID = defaults.string(forKey: "currentAlbum").flatMap(UUID.init(uuidString:)) }
 deinit { timer?.cancel() }
 func select(album: ContactAlbum, ids: [String], autoplay: Bool = true) { albumID = album.id; self.ids = ids; currentID = ids.first; remaining = []; history = []; isPlaying = autoplay && !ids.isEmpty; resetTimer() }
 func update(ids: [String]) { self.ids = ids; remaining.removeAll { !ids.contains($0) }; history.removeAll { !ids.contains($0) }; if currentID == nil || !ids.contains(currentID!) { currentID = ids.first }; if ids.isEmpty { pause() } }
 func next() { guard !ids.isEmpty else { currentID = nil; pause(); return }; if let currentID { history.append(currentID); if history.count > 1000 { history.removeFirst() } }; if shuffle { if remaining.isEmpty { remaining = ids.filter { $0 != currentID }.shuffled() }; currentID = remaining.popLast() ?? ids.first } else { let index = currentID.flatMap { ids.firstIndex(of: $0) } ?? -1; currentID = ids[(index + 1) % ids.count] }; resetTimer() }
 func previous() { guard !ids.isEmpty else { return }; if shuffle, let previous = history.popLast() { if let currentID, currentID != previous { remaining.removeAll { $0 == currentID }; remaining.append(currentID) }; currentID = previous } else { let index = currentID.flatMap { ids.firstIndex(of: $0) } ?? 0; currentID = ids[(index - 1 + ids.count) % ids.count] }; resetTimer() }
 func toggle() { isPlaying ? pause() : resume() }
 func pause() { isPlaying = false; timer?.cancel(); timer = nil }
 func resume() { guard !ids.isEmpty else { return }; isPlaying = true; resetTimer() }
 func resetTimer() { timer?.cancel(); guard isPlaying, ids.count > 1 else { timer = nil; return }; let delay = min(max(interval, 1), 86400); timer = Task { [weak self] in do { try await Task.sleep(for: .seconds(delay)) } catch { return }; guard !Task.isCancelled else { return }; self?.next() } }
}
