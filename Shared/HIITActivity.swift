import ActivityKit
import Foundation

struct HIITAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var remainingSeconds: Int   // 전체 남은 초
        var nextBeep: Int           // 다음 알림까지 남은 초
        var isRunning: Bool         // 실행 상태
    }
    var totalMinutes: Int           // 총 분
    var intervalMinutes: Int        // 인터벌 분
}

