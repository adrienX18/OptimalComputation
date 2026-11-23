import OptimalComputation.Evaluation.Execution
import OptimalComputation.Examples.TinyMultiply

namespace OptimalComputation.Tests

open Hardware Candidates Workloads Evaluation

private def checkExecution (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw <| IO.userError s!"Execution check failed: {label}"

private def fixture (inputs outputs scratch : List Nat) (lanes banks : Nat)
    (schedule : List RawScheduledInstruction) : RawCandidate := {
  identifier := "execution-test-v1"
  workloadIdentifier := "execution-test-shape-v1"
  configuration := ⟨lanes, banks⟩
  layout := ⟨inputs, outputs, scratch⟩
  schedule := schedule
}

private def simulate (raw : RawCandidate) (values : List Int) (fuel : Nat := 100)
    (trace : Bool := true) : IO ExecutionOutcome := do
  let shape : Shape := ⟨raw.workloadIdentifier, raw.layout.inputs.length, raw.layout.outputs.length⟩
  match validateCandidate shape raw with
  | .error error => throw <| IO.userError s!"Execution fixture malformed: {repr error}"
  | .ok candidate => return execute candidate values fuel trace

private def success (raw : RawCandidate) (values : List Int) (fuel : Nat := 100) : IO ExecutionRecord := do
  match ← simulate raw values fuel with
  | .success record => return record
  | other => throw <| IO.userError s!"Expected completion, got {repr other}"

private def expectFailure (raw : RawCandidate) (values : List Int) (expected : ExecutionError) : IO Unit := do
  let result ← simulate raw values
  checkExecution s!"expected {repr expected}, got {repr result}" (result == .failure expected)

private def expectMachine (raw : RawCandidate) (values : List Int) (cycle : Nat)
    (lane : Option Nat) (rule : MachineRule) : IO Unit :=
  expectFailure raw values (.machine ⟨cycle, lane, rule⟩)

/-- A plain projection exposes hand-worked trace values and timing without
constructing expected values by replaying the implementation. -/
private def traceRows (record : ExecutionRecord) : List (String × Nat × Nat × Nat × Int) :=
  record.trace.flatMap fun boundary => boundary.events.map fun
    | .issued t lane i due => (s!"issue:{repr i}", t, lane, due, 0)
    | .committed t lane (.register r v) => ("register", t, lane, r.val.val, v.val)
    | .committed t lane (.memory a v) => ("memory", t, lane, a.val, (decodeSlot v).val)
    | .active t lane => ("active", t, lane, 0, 0)

private def checkTiny : IO Unit := do
  let raw := Examples.TinyMultiply.raw
  let record ← success raw [-7, 6] 7
  checkExecution "tiny exact boundary/output/storage/resources" <|
    record.cycles == 6 && record.outputs == [-42] && record.scheduleSize == 4 &&
    record.storage == ⟨2, 1, 0, 3, 24⟩ && record.resources == resourceReport Examples.TinyMultiply.configuration
  checkExecution "tiny independent counts" <| record.counters == {
    loads := 2, stores := 1, additions := 0, multiplications := 1, multiplyAdds := 0,
    registerReads := 3, registerWrites := 3, bankAccesses := [3], laneIssues := [4],
    laneCompletions := [4], laneActiveCycles := [6]
  }
  checkExecution "tiny all seven boundaries including explicit waits" <|
    record.trace.map BoundaryTrace.cycle == [0, 1, 2, 3, 4, 5, 6]
  let issue := fun (i : RawInstruction) t due => (s!"issue:{repr i}", t, 0, due, (0 : Int))
  checkExecution "tiny entire hand-worked trace" <| traceRows record == [
    issue (.load 1 0) 0 1, ("active", 0, 0, 0, 0),
    ("register", 1, 0, 1, -7), issue (.load 2 1) 1 2, ("active", 1, 0, 0, 0),
    ("register", 2, 0, 2, 6), issue (.multiply 3 1 2) 2 5, ("active", 2, 0, 0, 0),
    ("active", 3, 0, 0, 0), ("active", 4, 0, 0, 0),
    ("register", 5, 0, 3, -42), issue (.store 3 2) 5 6, ("active", 5, 0, 0, 0),
    ("memory", 6, 0, 2, -42)]
  checkExecution "trace counter reconciliation" <|
    Counters.ofEvents Examples.TinyMultiply.configuration (record.trace.flatMap BoundaryTrace.events) == record.counters
  checkExecution "reversing whole schedule preserves whole record" <|
    (← simulate { raw with schedule := raw.schedule.reverse } [-7, 6] 7) == .success record
  checkExecution "trace suppression does not change results or counters" <|
    (← simulate raw [-7, 6] 7 false) == .success { record with trace := [] }
  for (a, b, answer) in [(0, 99, 0), (-32768, -32768, 1073741824),
      (32767, 32767, 1073676289), (-32768, 32767, -1073709056)] do
    let other ← success raw [a, b]
    checkExecution "tiny signed endpoints" (other.outputs == [answer] && other.cycles == 6)
  checkExecution "exact budget before output-store commit is inconclusive" <|
    (← simulate raw [-7, 6] 6) == .resourceExhausted ⟨6, 4, 0, 1⟩
  checkExecution "zero budget is inconclusive" <|
    (← simulate raw [-7, 6] 0) == .resourceExhausted ⟨0, 0, 4, 0⟩
  expectFailure raw [1] (.invalidInput (.wrongScalarCount 2 1))
  expectFailure raw [1, 2, 3] (.invalidInput (.wrongScalarCount 2 3))
  expectFailure raw [1, 140737488355328] (.invalidInput (.scalarOutOfRange 1 140737488355328))
  expectFailure raw [-140737488355329, 1] (.invalidInput (.scalarOutOfRange 0 (-140737488355329)))

private def checkTiming : IO Unit := do
  let empty ← success (fixture [] [] [] 1 1 []) [] 0
  checkExecution "empty zero-output run completes at zero without fuel" <|
    empty.cycles == 0 && empty.trace == [] && empty.outputs == [] && empty.counters.laneIssues == [0]
  let storeZero := fixture [] [0] [] 1 1 [⟨0, 0, .store 0 0⟩]
  let zero ← success storeZero [] 2
  checkExecution "store r0 commits at boundary one and charges r0 read" <|
    zero.outputs == [0] && zero.cycles == 1 && zero.counters.registerReads == 1 &&
    zero.counters.registerWrites == 0 && zero.counters.laneActiveCycles == [1]
  let delayed := { storeZero with schedule := storeZero.schedule ++ [⟨9, 0, .add 1 0 0⟩] }
  let delay ← success delayed [] 13
  checkExecution "unused arithmetic still drains; explicit idle boundaries count" <|
    delay.cycles == 12 && delay.outputs == [0] && delay.counters.laneActiveCycles == [4] &&
    delay.counters.registerWrites == 1 && delay.trace.length == 13
  checkExecution "pending final unused arithmetic does not finish early" <|
    (← simulate delayed [] 12) == .resourceExhausted ⟨12, 2, 0, 1⟩
  expectFailure (fixture [] [0] [] 1 1 []) [] (.incompleteOutputs 0 [0])
  expectFailure (fixture [] [0, 1] [] 1 1 [⟨0, 0, .store 0 1⟩]) [] (.incompleteOutputs 1 [0])
  let independent := fixture [] [0, 1, 2] [] 1 1 [
    ⟨0, 0, .add 1 0 0⟩, ⟨1, 0, .multiply 2 0 0⟩, ⟨2, 0, .multiplyAdd 3 0 0 0⟩,
    ⟨3, 0, .store 1 0⟩, ⟨4, 0, .store 2 1⟩, ⟨5, 0, .store 3 2⟩]
  let independentResult ← success independent []
  checkExecution "three outstanding; independent arithmetic then stores during drain" <|
    independentResult.cycles == 6 && independentResult.outputs == [0, 0, 0] &&
    independentResult.counters == {
      loads := 0, stores := 3, additions := 1, multiplications := 1, multiplyAdds := 1,
      registerReads := 10, registerWrites := 3, bankAccesses := [3], laneIssues := [6],
      laneCompletions := [6], laneActiveCycles := [6] }
  let aliasing := fixture [0] [1] [] 1 1 [⟨0, 0, .load 1 0⟩,
    ⟨1, 0, .add 1 1 1⟩, ⟨4, 0, .multiplyAdd 1 1 1 1⟩, ⟨7, 0, .store 1 1⟩]
  let aliasResult ← success aliasing [3]
  checkExecution "source/destination alias samples ready old value" <|
    aliasResult.cycles == 8 && aliasResult.outputs == [42] && aliasResult.counters.registerReads == 6
  let collision := fixture [0] [] [] 1 1 [⟨0, 0, .add 1 0 0⟩, ⟨2, 0, .load 2 0⟩]
  expectMachine collision [7] 2 (some 0) (.writebackCollision 3)
  expectMachine (fixture [] [] [] 1 1 [⟨0, 0, .add 1 0 0⟩, ⟨1, 0, .add 2 1 0⟩]) []
    1 (some 0) (.pendingRead 1)
  expectMachine (fixture [] [] [] 1 1 [⟨0, 0, .add 1 0 0⟩, ⟨2, 0, .add 2 0 1⟩]) []
    2 (some 0) (.pendingRead 1)
  expectMachine (fixture [] [] [] 1 1 [⟨0, 0, .add 1 0 0⟩, ⟨1, 0, .add 1 0 0⟩]) []
    1 (some 0) (.pendingWrite 1)
  expectMachine (fixture [] [0] [] 1 1 [⟨0, 0, .add 1 0 0⟩, ⟨2, 0, .store 1 0⟩]) []
    2 (some 0) (.pendingRead 1)
  -- Destination r1 already holds a value but remains unreadable while its new
  -- result is pending. Looking only at initialization would incorrectly pass.
  expectMachine { aliasing with schedule := [⟨0, 0, .load 1 0⟩,
    ⟨1, 0, .add 1 1 1⟩, ⟨2, 0, .store 1 1⟩] } [3] 2 (some 0) (.pendingRead 1)

private def checkMemoryAndOrder : IO Unit := do
  let readRead := fixture [0] [1, 2] [] 2 1 [
    ⟨0, 1, .load 1 0⟩, ⟨0, 0, .load 1 0⟩, ⟨1, 1, .store 1 2⟩, ⟨1, 0, .store 1 1⟩]
  let rr ← success readRead [-19]
  checkExecution "same-address read/read consumes two ports; different writes allowed" <|
    rr.outputs == [-19, -19] && rr.cycles == 2 && rr.counters.bankAccesses == [4] &&
    rr.counters.laneIssues == [2, 2] && rr.counters.laneCompletions == [2, 2] &&
    rr.counters.laneActiveCycles == [2, 2]
  checkExecution "all simultaneous batches reversed preserve full trace" <|
    (← simulate { readRead with schedule := readRead.schedule.reverse } [-19]) == .success rr
  let three := fixture [0, 1, 2] [] [] 4 1 [
    ⟨0, 0, .load 1 0⟩, ⟨0, 1, .load 1 1⟩, ⟨0, 2, .load 1 2⟩]
  expectMachine three [7, 8, 9] 0 none (.bankCapacity 0 3)
  expectMachine { three with schedule := three.schedule.reverse } [7, 8, 9] 0 none (.bankCapacity 0 3)
  expectMachine { three with schedule := [⟨0, 0, .load 1 0⟩, ⟨0, 1, .load 1 0⟩,
    ⟨0, 2, .load 1 0⟩] } [7, 8, 9] 0 none (.bankCapacity 0 3)
  let distributed ← success { three with configuration := ⟨4, 4⟩ } [7, 8, 9]
  checkExecution "same traffic across separate banks passes" <|
    distributed.cycles == 1 && distributed.counters.bankAccesses == [1, 1, 1, 0]
  for schedule in [[⟨0, 0, .load 1 0⟩, ⟨0, 1, .store 0 0⟩],
      [⟨0, 0, .store 0 0⟩, ⟨0, 1, .load 1 0⟩],
      [⟨0, 0, .store 0 0⟩, ⟨0, 1, .store 0 0⟩]] do
    let conflict := fixture [] [0] [] 2 1 schedule
    expectMachine conflict [] 0 none (.addressConflict 0)
    expectMachine { conflict with schedule := schedule.reverse } [] 0 none (.addressConflict 0)
  let issueConflict := fixture [0] [] [] 1 1 [⟨0, 0, .load 1 0⟩, ⟨0, 0, .add 2 0 0⟩]
  expectMachine issueConflict [7] 0 (some 0) .issueCollision
  expectMachine { issueConflict with schedule := issueConflict.schedule.reverse } [7] 0 (some 0) .issueCollision
  -- Lane 0 writes scratch; lane 1 reads precisely at store completion, then
  -- sends it through its own registers. This is the only lane transfer route.
  let transfer := fixture [0] [1] [2] 2 1 [⟨0, 0, .load 1 0⟩,
    ⟨1, 0, .store 1 2⟩, ⟨2, 1, .load 1 2⟩, ⟨3, 1, .store 1 1⟩]
  let tr ← success transfer [-33]
  checkExecution "store completion before cross-lane load issue" <|
    tr.cycles == 4 && tr.outputs == [-33] && tr.counters.bankAccesses == [4] &&
    tr.counters.laneActiveCycles == [2, 2]
  expectMachine (fixture [] [] [] 2 1 [⟨0, 0, .add 1 0 0⟩,
    ⟨3, 1, .add 2 1 0⟩]) [] 3 (some 1) (.uninitializedRegister 1)
  -- A store captures -33 while a new arithmetic result for the same register
  -- is issued at the following boundary. Memory keeps the captured payload.
  let captured := fixture [0] [1] [] 1 1 [⟨0, 0, .load 1 0⟩,
    ⟨1, 0, .store 1 1⟩, ⟨2, 0, .add 1 0 0⟩]
  let cr ← success captured [-33]
  checkExecution "store payload survives later source mutation and full drain" <|
    cr.outputs == [-33] && cr.cycles == 5
  -- A load captures the old value before a following store updates its slot.
  let loadCaptured := fixture [0] [1, 2] [] 2 1 [⟨0, 0, .load 1 0⟩,
    ⟨1, 0, .store 1 1⟩, ⟨2, 1, .load 1 1⟩, ⟨3, 0, .store 0 1⟩, ⟨3, 1, .store 1 2⟩]
  let lc ← success loadCaptured [27]
  checkExecution "load payload captures earlier memory value" (lc.outputs == [0, 27] && lc.cycles == 4)

private def checkInitializationAndArithmetic : IO Unit := do
  for instruction in [(.store 1 0 : RawInstruction), .add 2 1 0, .multiply 2 0 1,
      .multiplyAdd 2 0 0 1] do
    expectMachine (fixture [] [0] [] 1 1 [⟨0, 0, instruction⟩]) []
      0 (some 0) (.uninitializedRegister 1)
  expectMachine (fixture [] [0] [] 1 1 [⟨0, 0, .load 1 0⟩]) []
    0 (some 0) (.uninitializedMemory 0)
  expectMachine (fixture [] [] [0] 1 1 [⟨0, 0, .load 1 0⟩]) []
    0 (some 0) (.uninitializedMemory 0)
  let unary := fun instruction => fixture [0] [1] [] 1 1
    [⟨0, 0, .load 1 0⟩, ⟨1, 0, instruction⟩, ⟨4, 0, .store 2 1⟩]
  expectMachine (unary (.multiply 2 1 0)) [32768] 1 (some 0)
    (.arithmetic (.operandOutOfRange .left 16 32768))
  expectMachine (unary (.multiply 2 0 1)) [-32769] 1 (some 0)
    (.arithmetic (.operandOutOfRange .right 16 (-32769)))
  expectMachine (unary (.multiplyAdd 2 1 0 0)) [32768] 1 (some 0)
    (.arithmetic (.operandOutOfRange .left 16 32768))
  expectMachine (unary (.add 2 1 1)) [140737488355327] 1 (some 0)
    (.arithmetic (.resultOutOfRange 281474976710654))
  expectMachine (unary (.add 2 1 1)) [-140737488355328] 1 (some 0)
    (.arithmetic (.resultOutOfRange (-281474976710656)))
  let mac := fixture [0, 1, 2] [3] [] 1 1 [⟨0, 0, .load 1 0⟩,
    ⟨1, 0, .load 2 1⟩, ⟨2, 0, .load 3 2⟩, ⟨3, 0, .multiplyAdd 3 1 2 3⟩,
    ⟨6, 0, .store 3 3⟩]
  expectMachine mac [1, 1, 140737488355327] 3 (some 0)
    (.arithmetic (.resultOutOfRange 140737488355328))
  expectMachine mac [-1, 1, -140737488355328] 3 (some 0)
    (.arithmetic (.resultOutOfRange (-140737488355329)))
  let mr ← success mac [-7, 6, 5]
  checkExecution "mixed-sign MAC counts only a MAC and its three reads" <|
    mr.outputs == [-37] && mr.cycles == 7 && mr.counters.multiplyAdds == 1 &&
    mr.counters.additions == 0 && mr.counters.multiplications == 0 && mr.counters.registerReads == 4
  for endpoint in [(-140737488355328 : Int), 140737488355327] do
    let r ← success (unary (.add 2 1 0)) [endpoint]
    checkExecution "full-width canonical memory roundtrip through addition" (r.outputs == [endpoint])

/-- Reachable schedules cannot exceed three pending effects: one issue per
cycle and maximum latency three. Direct transition probes still exercise the
reservation guard, including store payloads, without weakening that guard. -/
private def checkCapacity : IO Unit := do
  let c := Examples.TinyMultiply.configuration
  let lane : Lane c := ⟨0, by decide⟩
  let r : WritableRegister := ⟨⟨1, by decide⟩, by decide⟩
  let pending := fun due (address : Address) =>
    PendingEffect.mk due (.memory address (encodeSlot zero48))
  let full := (State.empty c).setPending lane [pending 7 ⟨0, by decide⟩,
    pending 8 ⟨1, by decide⟩, pending 9 ⟨2, by decide⟩]
  match step 0 [⟨lane, .add r ⟨0, by decide⟩ ⟨0, by decide⟩⟩] full with
  | .error error =>
      checkExecution "three store payloads also occupy capacity" (error == ⟨0, some 0, .pendingCapacity 3⟩)
  | .ok _ => throw <| IO.userError "Full pending slots accepted another operation"
  -- At boundary seven the first store retires before the new reservation.
  match step 7 [⟨lane, .add r ⟨0, by decide⟩ ⟨0, by decide⟩⟩] full with
  | .error e => throw <| IO.userError s!"Commit did not release capacity: {repr e}"
  | .ok (s, _) => checkExecution "commit releases capacity before issue" (s.pendingCount == 3)

private def checkConfigurations : IO Unit := do
  for config in allConfigs do
    let raw := { Examples.TinyMultiply.raw with
      configuration := config
      schedule := Examples.TinyMultiply.raw.schedule.map
        (fun i => { i with lane := config.lanes - 1 }) }
    let record ← success raw [-7, 6]
    let expectedBanks := match config.banks with
      | 1 => [3]
      | 2 => [2, 1]
      | 4 => [1, 1, 1, 0]
      | _ => [1, 1, 1, 0, 0, 0, 0, 0]
    checkExecution "tiny executes on last lane of every allowed configuration" <|
      record.outputs == [-42] && record.cycles == 6 && record.counters.bankAccesses == expectedBanks &&
      record.counters.laneIssues == List.replicate (config.lanes - 1) 0 ++ [4] &&
      record.counters.laneActiveCycles == List.replicate (config.lanes - 1) 0 ++ [6]
  let boundary := fixture [4095] [0] [] 8 8 [⟨0, 7, .load 15 4095⟩, ⟨1, 7, .store 15 0⟩]
  let record ← success boundary [-123]
  checkExecution "highest address, register, and lane execute" <|
    record.outputs == [-123] && record.cycles == 2 &&
    record.counters.bankAccesses == [1, 0, 0, 0, 0, 0, 0, 1]

private def checkPermutationsAndScale : IO Unit := do
  let a : RawScheduledInstruction := ⟨0, 0, .load 1 0⟩
  let b : RawScheduledInstruction := ⟨0, 1, .load 1 1⟩
  let c : RawScheduledInstruction := ⟨0, 2, .load 1 2⟩
  let raw := fixture [0, 1, 2] [] [] 4 4 [a, b, c]
  let expected ← simulate raw [4, 5, 6]
  for ordering in [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]] do
    checkExecution "all six simultaneous representation permutations" <|
      (← simulate { raw with schedule := ordering } [4, 5, 6]) == expected
  let twoFailures := fixture [] [] [] 2 1 [⟨0, 1, .add 1 2 0⟩, ⟨0, 0, .add 1 3 0⟩]
  expectMachine twoFailures [] 0 (some 0) (.uninitializedRegister 3)
  expectMachine { twoFailures with schedule := twoFailures.schedule.reverse } []
    0 (some 0) (.uninitializedRegister 3)
  let farFuture := fixture [] [0] [] 1 1 [⟨1000000000, 0, .store 0 0⟩]
  checkExecution "long explicit wait is budget exhaustion, not schedule failure" <|
    (← simulate farFuture [] 3) == .resourceExhausted ⟨3, 0, 1, 0⟩
  -- A scale probe, not a computation baseline or optimization strategy.
  -- 12,500 explicit stores through boundary floor(12499*5/3)+1 = 20,832.
  let large := fixture [] [0] [] 1 1 ((List.range 12500).map
    (fun i => ⟨i * 5 / 3, 0, .store 0 0⟩))
  match ← simulate large [] 20833 false with
  | .success record =>
      checkExecution "large explicit schedule uses incremental queue" <|
        record.cycles == 20832 && record.scheduleSize == 12500 && record.outputs == [0] &&
        record.counters.stores == 12500 && record.counters.registerReads == 12500 &&
        record.counters.registerWrites == 0 && record.counters.bankAccesses == [12500] &&
        record.counters.laneActiveCycles == [12500] && record.trace == []
  | other => throw <| IO.userError s!"Large schedule failed: {repr other}"

def execution : IO Unit := do
  checkTiny
  checkTiming
  checkMemoryAndOrder
  checkInitializationAndArithmetic
  checkCapacity
  checkConfigurations
  checkPermutationsAndScale
  IO.println "PASS: execution (complete tiny trace/counters, timing, pending/writeback/issue hazards, memory ports/order, initialization, arithmetic, completion, budgets)"

end OptimalComputation.Tests
