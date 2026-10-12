import ActivityKit
import BabyCore
import SwiftUI
import WidgetKit

struct TrackerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackerActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .activitySystemActionForegroundColor(context.attributes.kind.color)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.title).font(.headline)
                    } icon: {
                        Image(systemName: kind.systemImage).foregroundStyle(kind.color)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimerText(context: context)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(kind.color)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.babyName).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityControls(context: context)
                }
            } compactLeading: {
                Image(systemName: kind.systemImage).foregroundStyle(kind.color)
            } compactTrailing: {
                ActivityTimerText(context: context)
                    .frame(maxWidth: 56)
                    .foregroundStyle(kind.color)
            } minimal: {
                Image(systemName: kind.systemImage).foregroundStyle(kind.color)
            }
            .keylineTint(kind.color)
        }
    }
}

/// Count-up timer that keeps ticking without app updates.
struct ActivityTimerText: View {
    let context: ActivityViewContext<TrackerActivityAttributes>

    var body: some View {
        let state = context.state
        Group {
            if context.attributes.kind == .nursing {
                if let start = state.nursingTimerStart {
                    Text(start, style: .timer)
                } else {
                    Text(Fmt.clock(state.leftDuration + state.rightDuration))
                }
            } else {
                Text(state.startDate, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<TrackerActivityAttributes>

    var body: some View {
        let kind = context.attributes.kind
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(kind.color.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(context.attributes.babyName).font(.caption).foregroundStyle(.secondary)
                    Text(kind == .sleep ? String(localized: "Sleeping") : context.attributes.title).font(.headline)
                }
                Spacer()
                ActivityTimerText(context: context)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(kind.color)
            }
            ActivityControls(context: context)
        }
    }
}

struct ActivityControls: View {
    let context: ActivityViewContext<TrackerActivityAttributes>

    var body: some View {
        let state = context.state
        let id = context.attributes.eventID
        let kind = context.attributes.kind
        HStack(spacing: 8) {
            if kind == .nursing {
                sideLabel(.left, state: state)
                sideLabel(.right, state: state)
                Button(intent: SwitchNursingSideIntent(eventID: id)) {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .tint(.pink)
                .accessibilityLabel(Text("Switch Side"))
                Button(intent: ToggleNursingPauseIntent(eventID: id)) {
                    Image(systemName: state.isNursingPaused ? "play.fill" : "pause.fill")
                }
                .tint(.pink)
                .accessibilityLabel(state.isNursingPaused ? String(localized: "Resume") : String(localized: "Pause"))
            } else {
                Text("Started \(Fmt.time(state.startDate))").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Button(intent: StopTimerIntent(eventID: id)) {
                Label(kind == .sleep ? String(localized: "Wake Up") : String(localized: "Stop"), systemImage: "stop.fill")
                    .font(.caption.weight(.semibold))
            }
            .tint(kind.color)
        }
        .buttonStyle(.bordered)
    }

    private func sideLabel(_ side: BreastSide, state: TrackerActivityAttributes.ContentState) -> some View {
        let active = state.activeSide == side
        return VStack(spacing: 0) {
            Text(side.shortTitle).font(.caption2.bold())
            Group {
                if let start = state.sideTimerStart(side) {
                    Text(start, style: .timer)
                } else {
                    Text(Fmt.clock(state.storedDuration(side)))
                }
            }
            .font(.caption.monospacedDigit())
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(active ? Color.pink.opacity(0.25) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
