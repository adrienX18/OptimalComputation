import OptimalComputation.Examples.ObjectiveResults

/-! M8 proof trust audit. Only the standard propext, Quot.sound and
Classical.choice axioms may occur. Private step witnesses are included
transitively through the public all-input execution and certificate roots. -/
#print axioms OptimalComputation.Evaluation.run_path
#print axioms OptimalComputation.Evaluation.CertifiedExecution.correct
#print axioms OptimalComputation.Evaluation.CertifiedExecution.decoded_correct
#print axioms OptimalComputation.Evaluation.executeCertified
#print axioms OptimalComputation.Evaluation.lookupArtifact
#print axioms OptimalComputation.Evaluation.lookupArtifact_member
#print axioms OptimalComputation.Evaluation.selectArtifact
#print axioms OptimalComputation.Evaluation.energyCoefficients_positive
#print axioms OptimalComputation.Evaluation.latency_formula
#print axioms OptimalComputation.Evaluation.energy_formula
#print axioms OptimalComputation.Evaluation.AcceptedScore.rescore_preserves_record
#print axioms OptimalComputation.Evaluation.AcceptedScore.correct
#print axioms OptimalComputation.Evaluation.evaluateObjective
#print axioms OptimalComputation.Evaluation.evaluateObjective_registered
#print axioms OptimalComputation.Examples.ProductPair.candidate
#print axioms OptimalComputation.Examples.ProductPair.adapter
#print axioms OptimalComputation.Examples.ProductPair.adapter_encode
#print axioms OptimalComputation.Examples.ProductPair.execution_correct
#print axioms OptimalComputation.Examples.ProductPair.verified
#print axioms OptimalComputation.Evaluation.objectiveCatalog
#print axioms OptimalComputation.Evaluation.scoreRecord
#print axioms OptimalComputation.Evaluation.AcceptedScore.result
#print axioms OptimalComputation.Evaluation.AcceptedScore.toJson
#print axioms OptimalComputation.Hardware.step
#print axioms OptimalComputation.Evaluation.run
#print axioms OptimalComputation.Evaluation.executeValues
