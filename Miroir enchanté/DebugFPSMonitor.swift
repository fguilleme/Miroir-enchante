//
//  DebugFPSMonitor.swift
//  Miroir enchanté
//

#if DEBUG
import QuartzCore

final class DebugFPSMonitor {
    private var frameCount = 0
    private var windowStart = CACurrentMediaTime()

    func frameRendered() {
        frameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - windowStart
        guard elapsed >= 1 else { return }

        let fps = Double(frameCount) / elapsed
        print(String(format: "AR FPS %.1f", fps))
        frameCount = 0
        windowStart = now
    }
}
#endif
