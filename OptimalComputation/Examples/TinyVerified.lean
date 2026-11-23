import OptimalComputation.Examples.TinyMultiply
import OptimalComputation.Evaluation.Execution

namespace OptimalComputation.Examples.TinyMultiply
open Hardware Workloads Candidates Evaluation

def inputs (a b : Int) (ha : InSigned16 a) (hb : InSigned16 b) : Vector Signed48 2 :=
  #v[⟨a, signed16_fits_signed48 ha⟩, ⟨b, signed16_fits_signed48 hb⟩]

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
theorem execution_correct (a b : Int) (ha : InSigned16 a) (hb : InSigned16 b) :
    ∃ record, executeValues candidate (inputs a b ha hb) 7 false = .success record ∧
      record.outputs = [a * b] ∧ record.cycles = 6 := by
  simp +instances [a0, a1, a2, lane0, r1, r2, r3,
    Vector.toList, List.map, List.zip, List.foldl,
    List.forIn_cons, List.forIn_nil, List.mapM, List.mapM.loop,
    executeValues, run, program, candidate, inputs, initialState, layout,
    step, commit, canonicalActions, checkBatch, prepare, checkReservation,
    readReady, registerPending, enqueue, applyEffect, latency,
    State.empty, State.writeMemory, State.writeRegister, State.setPending,
    State.readMemory, State.readRegister, State.drained, Effect.destination,
    Instruction.destination, Instruction.memoryAccess,
    configuration, List.finRange, List.mergeSort, List.span, List.span.loop,
    bankOf, instructionsPerLanePerCycle, bankPorts, pendingInstructionsPerLane,
    resultWritesPerLanePerCycle, checkedMul_accepts ha hb,
    finish, collectOutputs, Except.mapError, bind, pure, Except.bind, Except.pure]
  all_goals simp +instances [List.forIn_cons, bind, pure, Except.bind, Except.pure]
end OptimalComputation.Examples.TinyMultiply
