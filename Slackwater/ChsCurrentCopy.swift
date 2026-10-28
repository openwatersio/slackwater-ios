// Slackwater — GPL v3. Measured current-fit limits, shared by phone and watch.
import Foundation

extension ChsCurrentGateInfo {
    func boundHeadline(minutes: Int) -> String {
        String(localized: "Slack at \(name) can differ from CHS's prediction by up to \(minutes) min.", comment: "Current-fit timing bound. Values are place name and worst measured difference from CHS predictions, in minutes.")
    }

    var provisionalHeadline: String { boundHeadline(minutes: provisionalSlackMinutes ?? 0) }

    func onlineExplanation(speedUnit: String) -> String {
        var sentences: [String] = []
        switch missContext {
        case "slow_reversal":
            sentences.append(String(localized: "The current here is slow to reverse, which makes slack harder to predict.", comment: "Context for an online current gate's measured fit limitation."))
        case "tidal_falls":
            sentences.append(String(localized: "This place has reversing tidal falls.", comment: "Context for an online current gate's measured fit limitation."))
        case "rapids":
            sentences.append(String(localized: "This place has tidal rapids.", comment: "Context for an online current gate's measured fit limitation."))
        default: break
        }
        guard let miss = onlineMiss else {
            sentences.append(String(localized: "An on-device fit has not been validated here. Slackwater uses CHS predictions.", comment: "Online current gate without fit evidence."))
            return sentences.joined(separator: " ")
        }
        if miss.nearBar == true {
            sentences.append(String(localized: "The on-device fit is close to the validation bar. Slackwater uses CHS predictions until it passes consistently.", comment: "Online current gate awaiting the margin required for promotion."))
        } else if let value = miss.value {
            let number = value.formatted(.number.precision(.fractionLength(1)))
            switch miss.clause {
            case "reversed_axis":
                sentences.append(String(localized: "The on-device fit predicted the wrong flow direction for \(number)% of peak flows in its worst week.", comment: "Current fit limitation. Value is percentage of extrema with wrong sign in the worst held-out week."))
            case "invented_slack":
                sentences.append(String(localized: "The on-device fit’s yearly count of slacks absent from CHS predictions was \(Int(value)).", comment: "Current fit limitation. Value counts invented slacks over a year."))
            case "missed_slack":
                sentences.append(String(localized: "The on-device fit’s yearly count of missed CHS slacks was \(Int(value)).", comment: "Current fit limitation. Value counts missed slacks over a year."))
            case "slack_worst":
                sentences.append(String(localized: "The on-device fit differed from CHS's slack predictions by up to \(number) min over a year.", comment: "Current fit limitation. Value is the worst slack timing difference in minutes over a year."))
            case "slack_median":
                sentences.append(String(localized: "The on-device fit's median slack timing difference from CHS was \(number) min in its worst quarter.", comment: "Current fit limitation. Value is worst-quarter median slack timing difference, minutes."))
            case "extremum_timing":
                sentences.append(String(localized: "The on-device fit's median peak-flow timing difference from CHS was \(number) min in its worst quarter.", comment: "Current fit limitation. Value is worst-quarter median peak-flow timing difference, minutes."))
            case "peak_speed":
                let speed = formatSpeed(value, unit: speedUnit)
                let unit = speedUnitLabel(speedUnit)
                sentences.append(String(localized: "The on-device fit's median peak-speed difference from CHS was \(speed) \(unit) in its worst quarter.", comment: "Current fit limitation. Values are a speed difference and the user's speed unit."))
            default:
                sentences.append(String(localized: "The on-device fit did not pass validation here. Slackwater uses CHS predictions.", comment: "Online current gate with an unrecognized fit limitation."))
            }
        } else {
            sentences.append(String(localized: "There were not enough CHS events to validate the on-device fit in every quarter.", comment: "Current fit limitation when a quarterly median could not be measured."))
        }
        return sentences.joined(separator: " ")
    }
}
