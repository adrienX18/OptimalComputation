import OptimalComputation

-- naive-v2 tight-timing proofs and the exact v2 candidate/certificate/registration roots.
#print axioms OptimalComputation.Hardware.latency_le_three
#print axioms OptimalComputation.Evaluation.Serial.latency_pos
#print axioms OptimalComputation.Evaluation.Serial.tightSchedule_timed
#print axioms OptimalComputation.Evaluation.Serial.tightTimed_after
#print axioms OptimalComputation.Evaluation.Serial.tightTimed_sorted
#print axioms OptimalComputation.Evaluation.Serial.tightDuration_append
#print axioms OptimalComputation.Evaluation.Serial.enqueue_quiet
#print axioms OptimalComputation.Evaluation.Serial.step_commit_issue
#print axioms OptimalComputation.Evaluation.Serial.run_wait
#print axioms OptimalComputation.Evaluation.Serial.run_tight_pending
#print axioms OptimalComputation.Evaluation.Serial.run_tight
#print axioms OptimalComputation.Evaluation.Serial.run_tight_complete
#print axioms OptimalComputation.Examples.SerialDot.code_tightDuration
#print axioms OptimalComputation.Examples.MatVecNaive.candidateV2For
#print axioms OptimalComputation.Examples.MatVecNaive.candidateV2
#print axioms OptimalComputation.Examples.MatVecNaive.candidateV2_program
#print axioms OptimalComputation.Examples.MatVecNaive.structural_validity_v2
#print axioms OptimalComputation.Examples.MatVecNaive.finish_correct_v2
#print axioms OptimalComputation.Examples.MatVecNaive.execution_correct_v2
#print axioms OptimalComputation.Examples.MatVecNaive.verifiedV2
#print axioms OptimalComputation.Examples.MatMulNaive.candidateV2For
#print axioms OptimalComputation.Examples.MatMulNaive.candidateV2
#print axioms OptimalComputation.Examples.MatMulNaive.candidateV2_program
#print axioms OptimalComputation.Examples.MatMulNaive.structural_validity_v2
#print axioms OptimalComputation.Examples.MatMulNaive.finish_correct_v2
#print axioms OptimalComputation.Examples.MatMulNaive.execution_correct_v2
#print axioms OptimalComputation.Examples.MatMulNaive.verifiedV2
#print axioms OptimalComputation.Examples.MatVecNaive.row_tightDuration
#print axioms OptimalComputation.Examples.MatVecNaive.rows_tightDuration
#print axioms OptimalComputation.Examples.MatMulNaive.entry_tightDuration
#print axioms OptimalComputation.Examples.MatMulNaive.entries_tightDuration
#print axioms OptimalComputation.Evaluation.objectiveCatalog
