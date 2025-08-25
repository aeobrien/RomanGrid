import SwiftUI

struct TapTempoView: View {
    @Binding var bpm: Double
    @State private var taps: [Date] = []
    @State private var averageCount: Int = 4
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Tap Tempo").font(.title2)
            Text("\(String(format: "%.1f", bpm)) BPM").font(.largeTitle)
            Button {
                registerTap()
            } label: {
                Text("TAP").font(.title).padding().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            HStack {
                Stepper("Average last \(averageCount) taps", value: $averageCount, in: 2...8)
                Button("Reset") { taps.removeAll() }
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
    private func registerTap() {
        taps.append(Date())
        if taps.count > 1 {
            let last = taps.suffix(averageCount)
            let intervals = zip(last.dropFirst(), last).map { $0.timeIntervalSince($1) }
            guard !intervals.isEmpty else { return }
            let avg = intervals.reduce(0,+) / Double(intervals.count)
            let newBPM = 60.0 / avg
            bpm = (newBPM * 10).rounded() / 10.0 // round to 0.1 BPM
        }
    }
}
