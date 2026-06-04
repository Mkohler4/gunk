import SwiftUI

@MainActor
struct CostMeterView: View {
  private let store: Store
  private let now: () -> Date
  private let calendar: Calendar

  @State private var snapshot = CostMeterSnapshot.empty
  @State private var errorMessage: String?

  init(
    store: Store,
    now: @escaping () -> Date = Date.init,
    calendar: Calendar = .current
  ) {
    self.store = store
    self.now = now
    self.calendar = calendar
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Cost meter")
        .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
        GridRow {
          Text("")
          Text("Tokens")
          Text("USD")
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        meterRow("Today", totals: snapshot.today)
        meterRow("All time", totals: snapshot.allTime)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear(perform: refresh)
  }

  private func meterRow(_ label: String, totals: CostMeterTotals) -> some View {
    GridRow {
      Text(label)
      Text(totals.totalTokens.formatted())
        .monospacedDigit()
      Text(totals.costUsd, format: .currency(code: "USD"))
        .monospacedDigit()
    }
    .font(.caption)
  }

  private func refresh() {
    do {
      snapshot = CostMeterAggregator.snapshot(
        runs: try store.listLLMRuns(),
        now: now(),
        calendar: calendar
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
