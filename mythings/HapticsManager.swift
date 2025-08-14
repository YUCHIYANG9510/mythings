//
//  HapticsManager.swift
//  mythings
//
//  Created by Designer on 2025/8/14.
//

import CoreHaptics
import UIKit

final class HapticsManager {
    static let shared = HapticsManager()
    private var engine: CHHapticEngine?
    private var supportsHaptics = false

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
            // iPad 模擬器或某些機型不支援
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            supportsHaptics = false
        }
    }

    /// 供拖曳開始時預熱（降低延遲）
    func prepare() {
        guard supportsHaptics else { return }
        do { try engine?.start() } catch { }
    }

    /// 分頁「停靠」瞬間的沉一點的觸感
    /// strength 建議 0.5 ~ 1.0
    func pageSnap(strength: Double = 0.75) {
        guard supportsHaptics else {
            // 後備方案：重一點的 Impact
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.impactOccurred()
            return
        }

        let clamped = max(0.0, min(strength, 1.0))

        // 主要「咚」一下（低銳利度 = 更沈）
        let main = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.35 + 0.25*clamped)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15) // 低一點比較「厚」
            ],
            relativeTime: 0.0
        )

        // 很短的餘震（更厚實的感覺）
        let after = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.12 + 0.15*clamped)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05)
            ],
            relativeTime: 0.016 // 16ms 後輕觸一下
        )

        // 也可加一個極短的連續震，填滿手感（可選，這裡時間很短）
        let bed = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.10 + 0.15*clamped)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ],
            relativeTime: 0.0,
            duration: 0.035
        )

        do {
            let pattern = try CHHapticPattern(events: [bed, main, after], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            // 萬一出錯就回退
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.impactOccurred()
        }
    }
}
