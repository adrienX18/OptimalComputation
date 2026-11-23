import OptimalComputation

/-! Milestone 6 proof trust audit. Only propext, Quot.sound and Classical.choice
may occur. This file has no proof declarations or candidate assumptions. -/

#print axioms OptimalComputation.Hardware.forIn_preserves
#print axioms OptimalComputation.Hardware.empty_pending_bounded
#print axioms OptimalComputation.Hardware.writeMemory_pending_bounded
#print axioms OptimalComputation.Hardware.applyEffect_pending
#print axioms OptimalComputation.Hardware.setPending_bounded
#print axioms OptimalComputation.Hardware.commit_pending_bounded
#print axioms OptimalComputation.Hardware.forIn_yield_all
#print axioms OptimalComputation.Hardware.checkBatch_sound
#print axioms OptimalComputation.Hardware.checkReservation_capacity
#print axioms OptimalComputation.Hardware.prepare_reservation
#print axioms OptimalComputation.Hardware.mapM_pairs_ok
#print axioms OptimalComputation.Hardware.enqueue_length
#print axioms OptimalComputation.Hardware.enqueue_bounded
#print axioms OptimalComputation.Hardware.step_pending_bounded
#print axioms OptimalComputation.Hardware.commit_writeback_limit
#print axioms OptimalComputation.Hardware.reachable_pending_bounded
#print axioms OptimalComputation.Hardware.step_limits
#print axioms OptimalComputation.Hardware.Reachable.trans
#print axioms OptimalComputation.Workloads.ScalarAdapter.input_injective
#print axioms OptimalComputation.Workloads.ScalarAdapter.output_injective
#print axioms OptimalComputation.Workloads.ScalarAdapter.readOutput_roundtrip
#print axioms OptimalComputation.Workloads.decodeVector_vectorScalars
#print axioms OptimalComputation.Workloads.matrixScalars_at
#print axioms OptimalComputation.Workloads.decodeMatrix_matrixScalars
#print axioms OptimalComputation.Workloads.append_fits
#print axioms OptimalComputation.Workloads.matrixScalars_fits
#print axioms OptimalComputation.Workloads.vectorScalars_fits
#print axioms OptimalComputation.Workloads.MatVec.input_ext
#print axioms OptimalComputation.Workloads.MatVec.scalarInput_roundtrip
#print axioms OptimalComputation.Workloads.MatMul.input_ext
#print axioms OptimalComputation.Workloads.MatMul.scalarInput_roundtrip
#print axioms OptimalComputation.Evaluation.initialState_pending_bounded
#print axioms OptimalComputation.Evaluation.execution_reachable_pending_bounded
#print axioms OptimalComputation.Evaluation.run_finished_reachable
#print axioms OptimalComputation.Evaluation.run_monotone
#print axioms OptimalComputation.Evaluation.executeValues_monotone
#print axioms OptimalComputation.Evaluation.VerifiedCandidate.success_correct
#print axioms OptimalComputation.Evaluation.VerifiedCandidate.decoded_correct
#print axioms OptimalComputation.Evaluation.inspect_roundtrip
#print axioms OptimalComputation.Evaluation.inspect_sound
#print axioms OptimalComputation.Evaluation.checkStatic_sound
#print axioms OptimalComputation.Evaluation.parseInput_values
#print axioms OptimalComputation.Evaluation.evaluate_sound
#print axioms OptimalComputation.Evaluation.lookupTiny_exact
#print axioms OptimalComputation.Evaluation.registered_sound
#print axioms OptimalComputation.Examples.TinyMultiply.execution_correct
#print axioms OptimalComputation.Examples.TinyMultiply.adapter_encode
#print axioms OptimalComputation.Examples.TinyMultiply.verified
#print axioms OptimalComputation.Hardware.step
#print axioms OptimalComputation.Evaluation.run
#print axioms OptimalComputation.Evaluation.executeValues
#print axioms OptimalComputation.Evaluation.evaluate
#print axioms OptimalComputation.Evaluation.evaluateRegistered
