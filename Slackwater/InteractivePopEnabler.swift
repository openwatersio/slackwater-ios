// Slackwater — GPL v3. The edge-swipe-back the custom detail chrome costs us.
import SwiftUI
import UIKit

/// Restores the edge-swipe-back that the custom chrome costs us.
///
/// Root cause (M52): the app hides the nav bar everywhere —
/// `.toolbar(.hidden, for: .navigationBar)` on the stack and on every detail —
/// because the detail header carries its own back button. UIKit's
/// `setNavigationBarHidden:` disables `interactivePopGestureRecognizer` as a
/// side effect, so on iPhone the only way out of a detail was the button.
/// Re-enabling the recognizer needs a delegate (its own is nil'd with the bar),
/// and the delegate must refuse to begin on the root — otherwise a swipe on the
/// list wedges the navigation controller.
///
/// It stays an edge gesture, so it never competes with the timeline strip's
/// horizontal scrub: the strip's UIScrollView owns every pan that doesn't start
/// within the screen-edge margin.
struct InteractivePopEnabler: UIViewControllerRepresentable {
    final class PopDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }
    }

    final class Host: UIViewController {
        private let popDelegate = PopDelegate()
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false  // pure plumbing, never a hit target
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController,
                  let pop = nav.interactivePopGestureRecognizer else { return }
            popDelegate.nav = nav
            pop.delegate = popDelegate
            pop.isEnabled = true
        }
    }

    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ vc: Host, context: Context) {}
}
