import Foundation
import ChupCore

struct DeliveryDiagnostic: Identifiable {
  let id = UUID()
  let date: Date
  let trigger: String
  let result: TextDeliveryResult
  let route: String
  let detail: String
}

extension WorkspaceState {
  @MainActor func recordDelivery(_ result: TextDeliveryResult, trigger: String) {
    deliveryDiagnostics.insert(DeliveryDiagnostic(date: Date(), trigger: trigger,
      result: result, route: insertion.lastDeliveryRoute, detail: insertion.lastDiagnostic), at: 0)
    deliveryDiagnostics = Array(deliveryDiagnostics.prefix(20))
  }
}
