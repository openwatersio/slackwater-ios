// Slackwater — GPL v3. The phone's scrub host: the scroll view, its momentum
// and magnet, the strip that composes it, and the rescale glide's display
// link. The watch drives the same canvas with the Crown instead (#522).
import Almanac
import SwiftUI
import UIKit

// MARK: - The scroll host: native pan + momentum, magnet on settle

/// Land on the target instead of riding an animated `setContentOffset` there.
///
/// Reduce Motion asks for it. `-uiTestQuiet` needs it: with UIKit's animations
/// off the scroll view arrives in the same frame and never calls
/// `scrollViewDidEndScrollingAnimation`, which is the callback that parks
/// `scrubTime` on the stop and clears `magneting`. Left on the animated path,
/// the first magnet after a scrub wedges the coordinator for the life of the
/// detail — `magnet` returns early ever after, and every later scrub leaves
/// the readout exactly where it was.
private var landsInstantly: Bool {
    UIAccessibility.isReduceMotionEnabled || uiTestQuiet
}

struct TimelineScrubber: UIViewRepresentable {
    let data: TimelineData
    let geo: TimelineGeo
    let imperial: Bool
    let speedUnit: String
    let now: Date
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date
    /// The lead in words — "Rising 2.3 feet" — for the strip's spoken value.
    var spokenLead = ""
    /// Bumped by a pill tap or a reopen on now. A tap must win over whatever
    /// the strip is doing, so this bypasses the settle guard below.
    var jumpToken = 0
    /// The store's is-it-safe-to-move-the-left-edge signal (`ScrollGate`).
    /// Nil on a fixed window (the online gate), where nothing slides.
    var scrollGate: ScrollGate? = nil
    /// A tap on the day row's DATE — the one label on the strip that names a
    /// day rather than a moment on it — opens the week picker.
    var onPickDate: () -> Void = {}
    /// The strip was pressed and held; its moment is already on the centerline. Nil where the
    /// host has nothing to open — a list card's strip — and then the strip carries neither the
    /// press recognizer nor the matching VoiceOver action.
    var onLongPress: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The tiles worth having mounted for this offset: the visible ones plus
    /// one each side, so a pan never reaches an unmounted tile before the
    /// next remount lands.
    static func mountedTiles(offset: CGFloat, viewport: CGFloat, total: CGFloat) -> Range<Int> {
        let count = max(Int((total / TimelineCanvas.tileWidth).rounded(.up)), 1)
        guard viewport > 0 else { return 0..<0 }
        let lo = max(Int(((offset - TimelineCanvas.tileWidth) / TimelineCanvas.tileWidth).rounded(.down)), 0)
        let hi = min(Int(((offset + viewport + TimelineCanvas.tileWidth) / TimelineCanvas.tileWidth).rounded(.up)), count)
        return lo..<max(hi, lo)
    }

    /// The scroll view's bounds are zero in makeUIView and updateUIView is
    /// not re-invoked by layout, so "center now under the centerline" can't
    /// live there: it would wait for the next state change (the first magnet
    /// settle), leaving the first view uncentered and the first scrub's
    /// readout frozen (build-7 riding-dot bug). Centering runs at layout
    /// time instead — the first moment the real width exists.
    final class ScrubScrollView: UIScrollView {
        var onLayout: (() -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityTraits = .adjustable
        }
        required init?(coder: NSCoder) { fatalError("not from a nib") }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            if event?.type == .touches {
                ScrubTrace.record("hit point=\(point) target=\(String(describing: hit))", self)
            }
            return hit
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
        /// The strip is one adjustable VoiceOver control (spec § 15): the
        /// canvas's labels are decoration, not focus stops.
        private var scrubber: Coordinator? { delegate as? Coordinator }
        override func accessibilityIncrement() { scrubber?.step(self, by: Timeline.accessibilityStep) }
        override func accessibilityDecrement() { scrubber?.step(self, by: -Timeline.accessibilityStep) }
    }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = ScrubScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceVertical = false
        sv.contentInsetAdjustmentBehavior = .never
        // The strip's SwiftUI mask clips instead, so it can reach into a trailing bleed.
        sv.clipsToBounds = false
        sv.delegate = context.coordinator
        // Nothing mounted until the first update with a real width — the
        // opening data can already span two chunks, and mounting every tile
        // of it would allocate their textures for one throwaway frame.
        let host = UIHostingController(rootView: canvas(tiles: 0..<0))
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: data.totalWidth, height: geo.height)
        sv.addSubview(host.view)
        sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        context.coordinator.host = host
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        if onLongPress != nil {
            let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handlePress(_:)))
            // A press held and then lifted must not also scrub. The press fails the instant the
            // finger leaves before its half second, so an ordinary tap is not delayed.
            tap.require(toFail: press)
            sv.addGestureRecognizer(press)
        }
        sv.addGestureRecognizer(tap)
        sv.onLayout = { [weak sv, coordinator = context.coordinator] in
            guard let sv else { return }
            coordinator.layoutDidRun(sv)
        }
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        updateUIView(sv, coordinator: context.coordinator)
    }

    func updateUIView(_ sv: UIScrollView, coordinator co: Coordinator) {
        co.updatingView = true
        defer { co.updatingView = false }
        ScrubTrace.record("update requested=\(scrubTime.timeIntervalSince1970) jump=\(jumpToken)", sv)
        co.parent = self
        // Rendered from the CURRENT offset; when a branch below moves the
        // offset, the scroll callback it fires refreshes again from the
        // final position.
        co.refreshCanvas(sv)
        guard sv.bounds.width > 0 else { return }
        co.publishCenter(sv)
        // The window's width is a constant 228h for every anchor (the 48h
        // back-pad is unconditional, #67 item 1) — an anchor pick alone can no
        // longer change `totalWidth`. The guard below still earns its keep for
        // whatever DOES change it: the host frame and `contentSize` were set
        // once in `makeUIView` and never again, so a canvas that grew or
        // shrank without a resize here lays itself out CENTRED inside the
        // stale host view — off from where the offset arithmetic below assumes
        // the window starts — and the viewport can land on empty space. A
        // blank strip under a perfectly correct readout, which is exactly what
        // shipping this fix's first attempt produced (back when an anchor pick
        // was still the trigger).
        //
        // Resize BEFORE the offset: the offset is set against these bounds, and
        // shrinking `contentSize` afterwards lets UIKit clamp it out from under
        // us.
        if abs(sv.contentSize.width - data.totalWidth) > 0.5 {
            co.host?.view.frame = CGRect(x: 0, y: 0, width: data.totalWidth, height: geo.height)
            sv.contentSize = CGSize(width: data.totalWidth, height: geo.height)
        }
        if !co.didInitialCenter {
            co.centerIfNeeded(sv)
            return
        }
        // External scrub (event tap, return-to-now): jump the strip so the
        // requested time sits under the centerline (prototype scrubTo/centerNow
        // are instant). User-driven scrolling round-trips within a point.
        // `!co.nudging` for the opening slide: scroll callbacks move
        // `scrubTime` with the animation, and this guard stops those updates
        // from making the representable snap its own offset mid-flight.
        //
        // NOT gated on `isDecelerating` or `magneting` (#237): while the strip
        // coasts, every frame writes `scrubTime` back from the offset, so a
        // request skipped here is overwritten before the glide ends — the Now
        // tap was simply swallowed. A finger still down (`isDragging`) keeps
        // its say; momentum does not. Setting the offset unanimated is how
        // UIKit stops a deceleration, and it cancels a magnet in flight too.
        let desired = data.x(scrubTime) - sv.bounds.width / 2
        if co.seenJump != jumpToken {
            ScrubTrace.record("jump desired=\(desired)", sv)
            // A tapped pill mid-fling: the guard below would drop the jump and
            // the next scroll callback would write the fling's time back over
            // the tap. Stop the fling and the magnet, then ride the magnet's
            // own animated path to the stop — the curve eases under the
            // centerline and the reading follows it, and
            // `didEndScrollingAnimation` parks exactly on the tapped time.
            // Reduce Motion, or nothing to travel, lands directly: a
            // zero-length animated scroll may never call back.
            // Past `snapJumpHours` of travel the ride is skipped too: a far
            // Now tap (or a picked week) lands instantly, because a multi-week
            // glide in 0.3s reads as a smear and the far content may not even
            // be mounted to ride through.
            co.seenJump = jumpToken
            co.stopIntro()
            sv.setContentOffset(sv.contentOffset, animated: false)
            let travel = abs(desired - sv.contentOffset.x)
            if landsInstantly || travel < 0.5
                || travel > CGFloat(Timeline.snapJumpHours) * Timeline.pph {
                co.magneting = false
                sv.contentOffset = CGPoint(x: desired, y: 0)
            } else {
                co.magneting = true
                // Scroll feedback must not cancel the external jump before its destination lands.
                co.nudging = true
                co.magnetTarget = scrubTime
                sv.setContentOffset(CGPoint(x: desired, y: 0), animated: true)
            }
            co.syncGate(sv)
            return
        }
        if abs(desired - sv.contentOffset.x) > 1, !sv.isDragging, !co.nudging {
            ScrubTrace.record("external desired=\(desired)", sv)
            if sv.isDecelerating || co.magneting {
                sv.setContentOffset(sv.contentOffset, animated: false)
                co.cancelMagnet()
            }
            sv.contentOffset = CGPoint(x: desired, y: 0)
            co.syncGate(sv)
        }
    }

    private func canvas(tiles: Range<Int>?) -> TimelineCanvas {
        TimelineCanvas(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                       now: now,
                       floodDeg: floodDeg, ebbDeg: ebbDeg, tileRange: tiles)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: TimelineScrubber
        var host: UIHostingController<TimelineCanvas>?
        var didInitialCenter = false
        var seenJump = 0
        var magneting = false
        /// The opening slide is animating. It keeps `updateUIView`'s external-
        /// scrub branch from snapping the offset back while scroll callbacks
        /// deliberately drive the reading and sky toward now.
        var nudging = false
        var introDisplayLink: CADisplayLink?
        var introStartedAt: CFTimeInterval?
        var introRange: (start: Date, destination: Date)?
        weak var introScrollView: UIScrollView?
        /// Where the animated scroll — the magnet's snap or a pill's jump — is
        /// headed; parked on exactly when the animation ends.
        var magnetTarget: Date?
        /// The viewport width the offset was last computed against (#280).
        var laidOutWidth: CGFloat = 0
        /// A width change is re-anchoring the offset to `scrubTime`; the
        /// scroll callback it fires must not write `scrubTime` back from
        /// layout.
        var reanchoring = false
        /// Applying SwiftUI's state can synchronously fire the scroll delegate,
        /// including when loaded chunks move the timeline's left edge.
        var updatingView = false
        /// Everything the drawn strip depends on — and notably NOT
        /// `scrubTime`. The canvas is the same picture at every offset: a pan
        /// moves it, it does not change it. Assigning `rootView` per scroll
        /// frame (which SwiftUI invites, since the scroll callback writes
        /// `scrubTime` and re-runs the body) re-renders every mounted tile
        /// sixty times a second for an identical result — affordable against
        /// a fixed 228h window, and the reason a multi-week one felt heavy.
        ///
        /// Keyed on the timeline's IDENTITY, never on its shape: a rebuild
        /// with a new slack threshold or a refined CHS model lands the same
        /// span and the same sample count, and only `revision` tells those
        /// apart. The geometry fields are still listed because the scale is
        /// the store's, not the data's, and can move under unchanged data.
        struct CanvasKey: Equatable {
            let revision: UInt64
            let height: CGFloat
            let tideMid: Double, tideSpan: Double, maxAbsCur: Double
            let now: Date
            let imperial: Bool, speedUnit: String
            let floodDeg: Double?, ebbDeg: Double?
            let tiles: Range<Int>
        }
        var canvasKey: CanvasKey?

        init(_ parent: TimelineScrubber) { self.parent = parent }

        /// Re-host the canvas only when what it draws has actually changed:
        /// new data, a new scale, or a pan that reached different tiles.
        func refreshCanvas(_ sv: UIScrollView) {
            let data = parent.data, geo = parent.geo
            let tiles = TimelineScrubber.mountedTiles(offset: sv.contentOffset.x,
                                                      viewport: sv.bounds.width,
                                                      total: data.totalWidth)
            let key = CanvasKey(revision: data.revision,
                                height: geo.height, tideMid: geo.tideMid,
                                tideSpan: geo.tideSpan, maxAbsCur: geo.maxAbsCur,
                                now: parent.now, imperial: parent.imperial,
                                speedUnit: parent.speedUnit,
                                floodDeg: parent.floodDeg, ebbDeg: parent.ebbDeg,
                                tiles: tiles)
            guard key != canvasKey else { return }
            canvasKey = key
            host?.rootView = TimelineCanvas(data: data, geo: geo,
                                            imperial: parent.imperial, speedUnit: parent.speedUnit,
                                            now: parent.now,
                                            floodDeg: parent.floodDeg, ebbDeg: parent.ebbDeg,
                                            tileRange: tiles)
        }

        /// Tell the store whether the offset may be rewritten right now.
        /// An offset write is how UIKit cancels a deceleration, so the store
        /// holds any left-edge chunk swap until this reads quiet.
        func syncGate(_ sv: UIScrollView) {
            parent.scrollGate?.isQuiet = !sv.isDragging && !sv.isDecelerating && !magneting && !nudging
        }

        /// Every `layoutSubviews`: the one-shot opening centre, then the
        /// width check that keeps the same time under the centerline.
        func layoutDidRun(_ sv: UIScrollView) {
            centerIfNeeded(sv)
            reanchorIfResized(sv)
            publishCenter(sv)
            // The viewport's width arrives HERE and nowhere else. `updateUIView`
            // runs first with zero bounds, where `mountedTiles` can only answer
            // "none", and a strip that then never scrolls — a picked week that
            // lands on the offset it already had — would keep that empty canvas:
            // a scroll view of the right size hosting nothing, which is a blank
            // chart under a correct readout. Cheap to repeat, since it returns
            // on an unchanged key.
            refreshCanvas(sv)
        }

        /// Rotation (iPad portrait ↔ landscape, Stage Manager) keeps
        /// `contentOffset.x` while `bounds.width` changes, so the time under
        /// the centerline — `contentOffset.x + width / 2` — drifts by half
        /// the width change and the curve disagrees with the readout until
        /// the next state change (#280). No scroll callback fires for a pure
        /// bounds change and SwiftUI does not re-run `updateUIView` for
        /// layout, so this is the only place that can notice. Re-anchor the
        /// offset to `scrubTime` unanimated, cancelling a magnet or fling in
        /// flight. The opening slide is left alone: it recomputes its offset
        /// from the live width every frame.
        func reanchorIfResized(_ sv: UIScrollView) {
            let width = sv.bounds.width
            defer { laidOutWidth = width }
            guard didInitialCenter, width > 0, abs(width - laidOutWidth) > 0.5, !nudging else { return }
            ScrubTrace.record("reanchor", sv)
            if sv.isDecelerating || magneting {
                sv.setContentOffset(sv.contentOffset, animated: false)
                cancelMagnet()
            }
            reanchoring = true
            sv.contentOffset = CGPoint(x: parent.data.x(parent.scrubTime) - width / 2, y: 0)
            reanchoring = false
        }

        /// The time actually under the centerline, as the strip's
        /// accessibility value. The lead readout carries `scrubTime`; this is
        /// the only signal a UI test has for whether the curve agrees with it.
        func publishCenter(_ sv: UIScrollView) {
            guard sv.bounds.width > 0 else { return }
            let t = parent.data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
            sv.accessibilityLabel = parent.geo.hasTide
                ? String(localized: "Tide timeline", comment: "VoiceOver label for the interactive tide chart.")
                : String(localized: "Current timeline", comment: "VoiceOver label for the interactive current chart.")
            sv.accessibilityValue = [parent.spokenLead, spokenWhen(t, parent.data.tz)]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            sv.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: String(localized: "Next event", comment: "VoiceOver chart action.")) { [weak self, weak sv] _ in
                    guard let self, let sv else { return false }
                    let after = self.parent.scrubTime.addingTimeInterval(1)
                    return self.jump(sv, to: self.parent.data.snapTimes.first { $0 > after })
                },
                UIAccessibilityCustomAction(name: String(localized: "Previous event", comment: "VoiceOver chart action.")) { [weak self, weak sv] _ in
                    guard let self, let sv else { return false }
                    let before = self.parent.scrubTime.addingTimeInterval(-1)
                    return self.jump(sv, to: self.parent.data.snapTimes.last { $0 < before })
                },
            ]
            // The press and hold, as an action: the moment is already on the centerline, so
            // the host opens the popup for it exactly as it would after a press.
            if let onLongPress = parent.onLongPress {
                sv.accessibilityCustomActions?.append(
                    UIAccessibilityCustomAction(name: String(localized: "Set an alert", comment: "VoiceOver chart action.")) { _ in
                        onLongPress(); return true
                    })
            }
        }

        /// A VoiceOver increment: five minutes, landed directly.
        func step(_ sv: UIScrollView, by seconds: TimeInterval) {
            stopIntro()
            park(sv, at: parent.scrubTime.addingTimeInterval(seconds))
        }
        private func jump(_ sv: UIScrollView, to target: Date?) -> Bool {
            guard let target else { return false }
            stopIntro()
            park(sv, at: target)
            return true
        }

        /// Land on a moment with no travel: the Reduce Motion path, and the
        /// accessibility one. Clamped, then read back, so a moment past the
        /// window's edge parks where the offset can actually reach (see
        /// `handleTap`).
        func park(_ sv: UIScrollView, at target: Date) {
            let maxOffset = max(parent.data.totalWidth - sv.bounds.width, 0)
            let desired = min(max(parent.data.x(target) - sv.bounds.width / 2, 0), maxOffset)
            let reachable = abs(parent.data.x(target) - sv.bounds.width / 2 - desired) < 0.5
            sv.setContentOffset(sv.contentOffset, animated: false)
            cancelMagnet()
            sv.contentOffset = CGPoint(x: desired, y: 0)
            parent.scrubTime = reachable ? target : parent.data.time(atX: desired + sv.bounds.width / 2)
        }

        /// One-shot initial centering, at the first layout with a real width
        /// (also reachable from updateUIView, whichever lands first). After
        /// this, scrollViewDidScroll drives scrubTime — including the very
        /// first drag.
        ///
        /// The four detail views initialize at `Timeline.introStart`; that
        /// exact opening state slides to now. Any other state (for example a
        /// picked week after an online timeline reload) centres without an
        /// intro. Reduce Motion likewise lands directly on now.
        func centerIfNeeded(_ sv: UIScrollView, animated: Bool = !landsInstantly) {
            guard !didInitialCenter, sv.bounds.width > 0 else { return }
            defer { didInitialCenter = true }
            ScrubTrace.record("center", sv)
            let start = parent.scrubTime
            let isIntro = abs(start.timeIntervalSince(Timeline.introStart(for: parent.now))) < 2
            let destination = isIntro ? parent.now : start
            let startX = parent.data.x(start) - sv.bounds.width / 2
            let destinationX = parent.data.x(destination) - sv.bounds.width / 2

            // Offset assignment can call the delegate synchronously. Keep
            // `didInitialCenter` false through both opening offsets, including
            // the instant landing, so layout never mutates SwiftUI state.
            sv.contentOffset = CGPoint(x: isIntro ? startX : destinationX, y: 0)
            laidOutWidth = sv.bounds.width
            guard isIntro else { return }
            guard animated else {
                sv.contentOffset = CGPoint(x: destinationX, y: 0)
                Task { @MainActor [weak self] in self?.parent.scrubTime = destination }
                return
            }

            nudging = true
            parent.scrollGate?.isQuiet = false
            introScrollView = sv
            introRange = (start, destination)
            let link = CADisplayLink(target: self, selector: #selector(advanceIntro))
            introDisplayLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func advanceIntro(_ link: CADisplayLink) {
            guard let sv = introScrollView, let range = introRange else {
                stopIntro()
                return
            }
            if introStartedAt == nil { introStartedAt = link.timestamp }
            let elapsed = link.timestamp - (introStartedAt ?? link.timestamp)
            let time = Timeline.introTime(from: range.start, to: range.destination,
                                          elapsed: elapsed)
            sv.contentOffset = CGPoint(x: parent.data.x(time) - sv.bounds.width / 2, y: 0)
            if elapsed >= Timeline.introDuration {
                parent.scrubTime = range.destination
                stopIntro()
                parent.scrollGate?.isQuiet = true
            }
        }

        func stopIntro() {
            introDisplayLink?.invalidate()
            introDisplayLink = nil
            introStartedAt = nil
            introRange = nil
            introScrollView = nil
            nudging = false
        }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            ScrubTrace.record("scroll", sv)
            publishCenter(sv)
            refreshCanvas(sv)
            guard sv.bounds.width > 0, didInitialCenter, !reanchoring, !updatingView else { return }
            parent.scrubTime = parent.data.time(atX: sv.contentOffset.x + sv.bounds.width / 2)
        }
        /// A touch during the opening slide leaves the scrubber exactly where
        /// the user grabbed it.
        func scrollViewWillBeginDragging(_ sv: UIScrollView) {
            ScrubTrace.record("pan-began", sv)
            stopIntro()
            parent.scrollGate?.isQuiet = false
        }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) {
            ScrubTrace.record("pan-ended", sv)
            if !willDecelerate { magnet(sv) }
            syncGate(sv)
        }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
            ScrubTrace.record("deceleration-ended", sv)
            magnet(sv)
            syncGate(sv)
        }
        /// An external scrub interrupted the animated settle; drop its
        /// target so a late `didEndScrollingAnimation` cannot park on it.
        func cancelMagnet() {
            magneting = false
            magnetTarget = nil
        }
        func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
            magneting = false
            nudging = false
            // Park exactly on the stop, so readouts show the event's own time.
            if let t = magnetTarget {
                magnetTarget = nil
                if !updatingView { parent.scrubTime = t }
            }
            syncGate(sv)
        }

        /// A tap: the date opens the picker, everything else on the strip
        /// brings its own moment to the centerline. Dragging is still how you
        /// read the curve; this is how you get across a day of it.
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? UIScrollView, sv.bounds.width > 0 else { return }
            // The scroll view's own coordinate space IS the content's, so this
            // x is a strip x and this y a canvas y.
            let p = g.location(in: sv)
            // Whatever the strip is doing, a tap wins — including the tap that
            // only opens the picker. Left running, the opening slide or a
            // magnet in flight keeps writing `scrubTime` behind the sheet.
            stopIntro()
            guard let target = tapTarget(x: p.x, y: p.y) else {
                sv.setContentOffset(sv.contentOffset, animated: false)
                cancelMagnet()
                parent.onPickDate()
                return
            }
            // Clamped, then read back: at either end of the window the offset
            // that would centre the tap does not exist, and parking scrubTime
            // on an unreachable time leaves the readout disagreeing with the
            // curve under the line. x and time are exact inverses, so a
            // reachable tap round-trips to itself.
            let maxOffset = max(parent.data.totalWidth - sv.bounds.width, 0)
            let desired = min(max(parent.data.x(target) - sv.bounds.width / 2, 0), maxOffset)
            let landing = parent.data.time(atX: desired + sv.bounds.width / 2)
            // Stop a fling first, then ride the magnet's animated path — the
            // same landing a tapped pill gets (updateUIView's jump branch).
            sv.setContentOffset(sv.contentOffset, animated: false)
            if landsInstantly || abs(desired - sv.contentOffset.x) < 0.5 {
                park(sv, at: landing)
            } else {
                magneting = true
                // `nudging` for the same reason the opening slide sets it: the
                // scroll callbacks drive `scrubTime` from the offset the
                // animation is passing through, and SwiftUI renders from that
                // value a frame later — updateUIView's external-scrub branch
                // reads the gap as a stale offset and pins the strip a few
                // points into a travel that can be a screen wide.
                nudging = true
                magnetTarget = landing
                sv.setContentOffset(CGPoint(x: desired, y: 0), animated: true)
            }
        }

        /// A press and hold: park its moment on the centerline and let the scaffold open the
        /// popup there. Instant, not the tap's animated magnet ride — a press names one moment,
        /// and a popup opening over a sliding strip could not say what it was about until the
        /// slide landed. The day row belongs to the picker's tap and answers a press with
        /// nothing.
        @objc func handlePress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let sv = g.view as? UIScrollView, sv.bounds.width > 0 else { return }
            let p = g.location(in: sv)
            // The plot region only, so `tapTarget` always takes its plot branch here — the same
            // magnet the strip settles into: a press near a turn means that turn.
            guard p.y <= rowSplit, let target = tapTarget(x: p.x, y: p.y) else { return }
            stopIntro()
            sv.setContentOffset(sv.contentOffset, animated: false)
            cancelMagnet()
            let maxOffset = max(parent.data.totalWidth - sv.bounds.width, 0)
            let desired = min(max(parent.data.x(target) - sv.bounds.width / 2, 0), maxOffset)
            sv.contentOffset = CGPoint(x: desired, y: 0)
            parent.scrubTime = parent.data.time(atX: desired + sv.bounds.width / 2)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress?()
        }

        /// What a tap at this point on the strip means: the moment to bring to
        /// the centerline, or nil for the date — the one label that names a day
        /// rather than a moment, and so opens the picker.
        /// The line between the plot with its axis times (at or above) and the day row (below),
        /// from the two rows' own y's: the strip's geometry is all literal points and moves.
        private var rowSplit: CGFloat { (parent.geo.timeY + parent.geo.dayY) / 2 }

        private func tapTarget(x: CGFloat, y: CGFloat) -> Date? {
            let data = parent.data
            guard y > rowSplit else {
                // The plot and its axis: the tapped moment, pulled onto a stop
                // by the same magnet a drag settles into.
                if let stop = nearest(data.snapTimes, toX: x), stop.dx < Timeline.magnetPts {
                    return stop.time
                }
                return data.time(atX: x)
            }
            // The day row is a row of labels — each day's date at its noon, its
            // sun times where they fall — so a tap goes to the nearest one. A
            // sunrise is a moment on the strip and scrubs there like anything
            // else; only the date is a different question.
            let sun = nearest(data.visibleDays.flatMap { day in
                [day.sunrise, day.sunset].compactMap { $0 }
            }, toX: x)
            let date = nearest(data.visibleDays.map { noonLocal($0.start, data.tz) }, toX: x)
            guard let sun, sun.dx < (date?.dx ?? .greatestFiniteMagnitude) else { return nil }
            return sun.time
        }

        /// The nearest of `times` to a strip x, and how far off it is.
        private func nearest(_ times: [Date], toX x: CGFloat) -> (time: Date, dx: CGFloat)? {
            var best: (time: Date, dx: CGFloat)?
            for t in times {
                let dx = abs(parent.data.x(t) - x)
                if dx < (best?.dx ?? .greatestFiniteMagnitude) { best = (t, dx) }
            }
            return best
        }

        /// Prototype magnet(): after the scroll settles, the nearest stop
        /// within 46pt of the centerline pulls the strip onto itself.
        private func magnet(_ sv: UIScrollView) {
            guard !magneting else { return }
            let center = sv.contentOffset.x + sv.bounds.width / 2
            guard let target = parent.data.magnetTarget(nearX: center) else { return }
            let desired = CGPoint(x: parent.data.x(target) - sv.bounds.width / 2, y: 0)
            // Reduce Motion: park on the stop directly, the same landing a
            // tap or a pill gets.
            if landsInstantly {
                park(sv, at: target)
                return
            }
            magneting = true
            magnetTarget = target
            sv.setContentOffset(desired, animated: true)
        }
    }
}

// MARK: - Strip + fixed overlay (centerline, riding dots, track labels)

struct TimelineScrubStrip: View {
    let data: TimelineData
    let geo: TimelineGeo
    var imperial = true    // only read by the tide track; current-only strips omit it
    var speedUnit = "kn"   // tide-only strips draw no speed labels
    let now: Date
    var chromeInk: Color = SN.foam
    var floodDeg: Double? = nil
    var ebbDeg: Double? = nil
    @Binding var scrubTime: Date
    var onReturn: (() -> Void)? = nil
    /// Reopened while scrubbed away: the caller moves `now`, the scrub stays put.
    var onResumeScrubbedAway: () -> Void = {}
    /// The lead in words, for the strip's spoken value (spec § 15).
    var spokenLead = ""
    /// The next significant event from the scrub, and the scrub to it.
    var commentary: CommentaryContent? = nil
    /// The commentary's ink when it is a warning rather than a next event.
    var commentaryTint: Color? = nil
    var onCommentary: () -> Void = {}
    /// Infinite-strip plumbing, nil on a fixed window: the store's scroll
    /// gate, and the viewport width the scale governor fits against.
    var scrollGate: ScrollGate? = nil
    var onViewportWidth: ((CGFloat) -> Void)? = nil
    @Environment(\.openWeekPicker) private var openWeekPicker
    @Environment(\.stripTrailingBleed) private var trailingBleed
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openAlertPopup) private var openAlertPopup
    @State private var jumpToken = 0
    @State private var settled = false

    var body: some View {
        TimelineScrubber(data: data, geo: geo, imperial: imperial, speedUnit: speedUnit,
                         now: now,
                         floodDeg: floodDeg, ebbDeg: ebbDeg, scrubTime: $scrubTime,
                         spokenLead: spokenLead,
                         jumpToken: jumpToken, scrollGate: scrollGate,
                         onPickDate: openWeekPicker, onLongPress: openAlertPopup)
            .frame(height: geo.height)
            // Stretched, not widened: the scroll view keeps its bounds, so the
            // centerline stays at the visible center while the drawing runs
            // on under the iPhone Duo's status rail.
            .mask { Rectangle().padding(.trailing, -trailingBleed) }
            // `onGeometryChange`, not a GeometryReader's `onChange(initial:)`:
            // the latter reports the first width from inside the update pass,
            // and writing the caller's state there is "Modifying state during
            // view update" — which SwiftUI calls undefined behavior and which
            // showed up in the result bundles as a runtime warning. This API
            // exists to hand geometry back without that.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                onViewportWidth?(width)
            }
            .overlay { overlay }
            .overlay(alignment: .top) { chromeRow }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-strip")
            .tourAnchor(.stars)
            .id(TourCoach.Step.stars)
            // The page outlives a trip to the background, so `now` is stale on reopen.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if scrubbedAway(scrubTime, from: now) {
                    onResumeScrubbedAway()
                } else {
                    jumpToken += 1
                    onReturn?()
                }
            }
            // The first-run tour's swipe demo. The animated magnet ride is
            // reachable only through `jumpToken`, which is this view's own
            // @State — so the tour asks for it through the observable rather
            // than through a parameter, which would fan out to every detail
            // view.
            .onChange(of: TourCoach.shared.glideToken) { _, _ in
                jumpToken += 1
            }
    }

    /// The row of glass pills between the lead and the plot: the commentary
    /// centred on the reading line, return-to-now at the edge on the side now
    /// is (scrubbed into history, now is to the right and the arrow points
    /// there; into the future, the left).
    private var chromeRow: some View {
        let past = scrubTime < now
        let showNow = onReturn != nil && scrubbedAway(scrubTime, from: now)
        return ZStack {
            Commentary(content: commentary, tint: commentaryTint,
                       ink: chromeInk) {
                jumpToken += 1
                onCommentary()
            }
            if showNow {
                HStack {
                    if past { Spacer(minLength: 0) }
                    nowPill(past: past)
                    if !past { Spacer(minLength: 0) }
                }
            }
        }
        // Capped so a long commentary and the Now pill share one row at
        // accessibility sizes; the lead above carries the full-size reading.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .opacity(settled ? 1 : 0)
        .allowsHitTesting(settled)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settled)
        .task(id: scrubTime) {
            // Rest = no scrub change for this long. A cancelled sleep is a
            // scrub still in motion, not a rest.
            settled = false
            guard (try? await Task.sleep(for: Timeline.rest)) != nil else { return }
            settled = true
        }
        // The pills' 44-point semantic rows are centred on the 30-point
        // capsules the geometry places at `chromeY`.
        .padding(.top, geo.chromeY - (Timeline.pillTarget - 30) / 2)
        .padding(.horizontal, 16)
    }

    private func nowPill(past: Bool) -> some View {
        Button(action: { jumpToken += 1; onReturn?() }) {
            HStack(spacing: 4) {
                if !past { Image(systemName: "arrow.left") }
                Text("Now")
                if past { Image(systemName: "arrow.right") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(chromeInk)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .frame(height: Timeline.pillTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Activate") { jumpToken += 1; onReturn?() }
        .accessibilityLabel("Return to now")
        .accessibilityIdentifier("detail-return-now")
    }

    private var overlay: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                // No y-axis column: the lead reading above the strip carries
                // the unit and the turn labels carry the values. A faint
                // reading line runs from the pill row to the plot's foot —
                // the riding dot marks the scrub, the line only ties it to
                // the lead above.
                Rectangle().fill(.white.opacity(0.18))
                    .frame(width: 1, height: geo.bodyBottom - geo.padTop)
                    .position(x: w / 2, y: geo.padTop + (geo.bodyBottom - geo.padTop) / 2)
                    .opacity(settled && commentary != nil ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settled)
                if geo.hasTide {
                    // Neutral white, like the current dot below it — a green
                    // dot coloured the mark by SERIES IDENTITY inside a canvas
                    // where green means slack.
                    Circle().fill(.white)
                        .frame(width: 13, height: 13)
                        .shadow(color: .white.opacity(0.9), radius: 4)
                        .position(x: w / 2, y: geo.tideY(data.heightAt(scrubTime)))
                }
                if geo.hasCurrent {
                    Circle().fill(.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .white.opacity(0.9), radius: 3)
                        .position(x: w / 2, y: geo.curY(data.velocityAt(scrubTime)))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - The rescale glide

/// Walks the drawn scale to the governor's target over a short beat — the
/// same display-link pattern the opening slide uses, for the same reason:
/// the strip's canvas is re-hosted on discrete values behind a
/// UIViewRepresentable, where SwiftUI's own animation cannot reach.
///
/// Retargetable mid-flight: a governor that adopts again while the glide is
/// running restarts it from wherever the scale currently is, so a fling that
/// crosses two spring weeks bends rather than jumps. Self-terminating — the
/// link invalidates itself on arrival, so an animator abandoned mid-glide
/// (its page closed) lives at most one beat longer than its store.
@MainActor final class ScaleAnimator: NSObject {
    static let duration: TimeInterval = 0.3

    private var link: CADisplayLink?
    private var from: TimelineScale?
    private var to: TimelineScale?
    private var startedAt: CFTimeInterval?
    /// Each frame's blended scale, ending exactly on the target.
    var onFrame: (@MainActor (TimelineScale) -> Void)?

    func glide(from current: TimelineScale, to target: TimelineScale) {
        from = current
        to = target
        startedAt = nil
        guard link == nil else { return }   // retarget: the running link continues
        let l = CADisplayLink(target: self, selector: #selector(tick))
        // The redraw this drives re-renders every mounted tile; 60 is smooth
        // and half the cost of letting ProMotion run it at 120.
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let from, let to else { return cancel() }
        if startedAt == nil { startedAt = link.timestamp }
        let t = (link.timestamp - (startedAt ?? link.timestamp)) / Self.duration
        onFrame?(TimelineScale.lerp(from, to, TimelineScale.eased(t)))
        if t >= 1 { cancel() }
    }

    func cancel() {
        link?.invalidate()
        link = nil
        from = nil
        to = nil
        startedAt = nil
    }
}

// Native state travels with CI's screenshot artifacts when the Malibu test opts in (#613).
@MainActor private enum ScrubTrace {
    #if DEBUG && targetEnvironment(simulator)
    static let path: URL? = {
        guard let i = CommandLine.arguments.firstIndex(of: "-scrubTrace"),
              CommandLine.arguments.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[i + 1])
    }()
    static var lines: [String] = []
    static var pending = false
    static let writer = DispatchQueue(label: "scrub-trace", qos: .utility)
    #endif

    static func record(_ event: @autoclosure () -> String, _ sv: UIScrollView) {
        #if DEBUG && targetEnvironment(simulator)
        guard let path, lines.count < 2000 else { return }
        let co = sv.delegate as? TimelineScrubber.Coordinator
        var gestures: [String] = []
        var view: UIView? = sv
        while let current = view {
            gestures += (current.gestureRecognizers ?? []).map {
                "\(ObjectIdentifier(current)):\(type(of: $0))=\($0.state.rawValue)"
            }
            view = current.superview
        }
        lines.append("\(Date().timeIntervalSince1970) \(event()) view=\(ObjectIdentifier(sv)) frame=\(sv.convert(sv.bounds, to: nil)) offset=\(sv.contentOffset) size=\(sv.contentSize) enabled=\(sv.isScrollEnabled) dragging=\(sv.isDragging) decelerating=\(sv.isDecelerating) translation=\(sv.panGestureRecognizer.translation(in: sv)) time=\(co?.parent.scrubTime.timeIntervalSince1970 ?? 0) jump=\(co?.seenJump ?? -1) centered=\(co?.didInitialCenter ?? false) nudging=\(co?.nudging ?? false) magnet=\(co?.magneting ?? false) reanchoring=\(co?.reanchoring ?? false) gestures=\(gestures)")
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            record("snapshot", sv)
            pending = false
            let snapshot = lines
            writer.async {
                do {
                    try snapshot.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
                } catch {
                    print("Could not save scrub trace: \(error)")
                }
            }
        }
        #endif
    }
}
