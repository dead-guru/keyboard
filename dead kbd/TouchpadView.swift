import SwiftUI
import UIKit

struct TouchpadView: View {
    let client: WebSocketClient
    let settings: AppSettings

    var body: some View {
        TouchpadRepresentable(client: client, settings: settings)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(8)
    }
}

struct TouchpadRepresentable: UIViewRepresentable {
    let client: WebSocketClient
    let settings: AppSettings

    func makeUIView(context: Context) -> TouchpadUIView {
        let view = TouchpadUIView()
        view.client = client
        view.settings = settings
        view.isMultipleTouchEnabled = true
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: TouchpadUIView, context: Context) {
        uiView.settings = settings
    }
}

final class TouchpadUIView: UIView {
    var client: WebSocketClient?
    var settings = AppSettings()

    private var primaryTouch: UITouch?
    private var previousLocation: CGPoint = .zero
    private var previousTouchCount = 0
    private var touchStartTime: TimeInterval = 0
    private var touchStartLocation: CGPoint = .zero
    private var isDragging = false
    private var isDragMode = false
    private var lastTapTime: TimeInterval = 0
    private var lastTapWasSingle = false
    private var peakTouchCount = 0
    private var feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var touchDots: [UIView] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let allTouches = event?.touches(for: self) ?? touches
        let count = allTouches.count

        if primaryTouch == nil, let touch = touches.first {
            primaryTouch = touch
            let location = touch.location(in: self)
            touchStartTime = touch.timestamp
            touchStartLocation = location
            previousLocation = location
            isDragging = false
            peakTouchCount = count

            let timeSinceLastTap = touch.timestamp - lastTapTime
            if lastTapWasSingle && timeSinceLastTap < 0.3 {
                isDragMode = true
                client?.sendMouseButton(.left, pressed: true)
                lastTapWasSingle = false
            }
        }

        if count > previousTouchCount {
            // Finger added — reset previousLocation to avoid delta spike
            if let pt = primaryTouch {
                previousLocation = pt.location(in: self)
            }
            peakTouchCount = max(peakTouchCount, count)
        }

        previousTouchCount = count
        updateDots(allTouches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let allTouches = event?.touches(for: self) ?? touches
        let count = allTouches.count

        if count != previousTouchCount {
            // Touch count changed mid-gesture — reset to avoid jump
            if let pt = primaryTouch {
                previousLocation = pt.location(in: self)
            }
            previousTouchCount = count
            updateDots(allTouches)
            return
        }

        guard let pt = primaryTouch, touches.contains(pt) else {
            updateDots(allTouches)
            return
        }

        let location = pt.location(in: self)
        let dx = location.x - previousLocation.x
        let dy = location.y - previousLocation.y
        previousLocation = location

        let moved = abs(location.x - touchStartLocation.x) + abs(location.y - touchStartLocation.y)
        if moved > 10 {
            isDragging = true
        }

        if count >= 2 && !isDragMode {
            let scrollDx = Float(dx * settings.scrollSpeed * 0.5)
            var scrollDy = Float(dy * settings.scrollSpeed * 0.5)
            if settings.naturalScrolling {
                scrollDy = -scrollDy
            }
            client?.sendScroll(dx: scrollDx, dy: scrollDy)
        } else {
            let sens = settings.sensitivity
            let accDx = accelerate(Float(dx), sensitivity: sens)
            let accDy = accelerate(Float(dy), sensitivity: sens)
            client?.sendMouseMove(dx: accDx, dy: accDy)
        }

        updateDots(allTouches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let allTouches = event?.touches(for: self) ?? touches
        let remainingCount = allTouches.count - touches.count

        if let pt = primaryTouch, touches.contains(pt) {
            let elapsed = pt.timestamp - touchStartTime
            let location = pt.location(in: self)
            let moved = abs(location.x - touchStartLocation.x) + abs(location.y - touchStartLocation.y)

            if isDragMode {
                if remainingCount == 0 {
                    client?.sendMouseButton(.left, pressed: false)
                    isDragMode = false
                }
            } else if !isDragging && elapsed < 0.3 && moved < 10 {
                performTap(fingerCount: peakTouchCount)
            }

            if remainingCount == 0 && !isDragMode {
                lastTapTime = pt.timestamp
                lastTapWasSingle = (peakTouchCount == 1 && !isDragging && elapsed < 0.3 && moved < 10)
            }

            // Pick a new primary from remaining touches
            primaryTouch = nil
            for t in allTouches where !touches.contains(t) && t.phase != .ended && t.phase != .cancelled {
                primaryTouch = t
                previousLocation = t.location(in: self)
                break
            }
        }

        if remainingCount == 0 {
            primaryTouch = nil
            peakTouchCount = 0
        }

        previousTouchCount = remainingCount
        updateDots(allTouches.subtracting(touches))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isDragMode {
            client?.sendMouseButton(.left, pressed: false)
            isDragMode = false
        }
        primaryTouch = nil
        previousTouchCount = 0
        peakTouchCount = 0
        clearDots()
    }

    private func performTap(fingerCount: Int) {
        if settings.hapticFeedback {
            feedbackGenerator.impactOccurred()
        }

        switch fingerCount {
        case 1:
            client?.sendMouseButton(.left, pressed: true)
            client?.sendMouseButton(.left, pressed: false)
        case 2:
            client?.sendMouseButton(.right, pressed: true)
            client?.sendMouseButton(.right, pressed: false)
        case 3:
            client?.sendMouseButton(.middle, pressed: true)
            client?.sendMouseButton(.middle, pressed: false)
        default:
            break
        }
    }

    private func accelerate(_ delta: Float, sensitivity: Double) -> Float {
        let sens = Float(sensitivity)
        let absDelta = abs(delta)
        let acc = sens * (absDelta + 0.5 * absDelta * absDelta)
        let capped = min(acc, 50.0)
        return delta >= 0 ? capped : -capped
    }

    private func updateDots(_ touches: Set<UITouch>) {
        clearDots()
        for touch in touches {
            if touch.phase == .ended || touch.phase == .cancelled { continue }
            let loc = touch.location(in: self)
            let dot = UIView(frame: CGRect(x: loc.x - 15, y: loc.y - 15, width: 30, height: 30))
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            dot.layer.cornerRadius = 15
            addSubview(dot)
            touchDots.append(dot)
        }
    }

    private func clearDots() {
        touchDots.forEach { $0.removeFromSuperview() }
        touchDots.removeAll()
    }
}
