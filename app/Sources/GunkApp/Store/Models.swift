struct Gunk: Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
  let path: String
  let droppedAt: Int64
  let removedAt: Int64?
}
