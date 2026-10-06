import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// One measurement step in the "Ich" room.
struct StepRow: View {
    var index: Int
    var step: LabStep
    var isNext: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(step.done ? Theme.good.opacity(0.18) : isNext ? Theme.lab.opacity(0.18) : Theme.surface2)
                if step.done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.good)
                } else {
                    Text("\(index)").font(.caption.weight(.bold)).foregroundStyle(isNext ? Theme.lab : Theme.text2)
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                Text(step.sub).font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                if let meta = step.meta { Chip(meta, tone: step.done ? .good : .tint(Theme.lab)).padding(.top, 2) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.text3).padding(.top, 8)
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}

struct HeadphonesCheckView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 1
    var body: some View {
        ZStack {
            AuroraBackground()
            if step == 1 {
                HeadphonesStep(returning: true, next: { step = 2 }, back: { model.pop() })
            } else {
                VolumeStep(next: { model.pop() }, back: { step = 1 })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shown instead of a measurement when the output is the built-in speaker.
struct MeasurementBlocked: View {
    var body: some View {
        Callout("Messungen brauchen Kopfhörer. Über den Lautsprecher stimmen weder Pegel noch Links/Rechts.", tone: .warn)
    }
}
