import OptimalComputation.Certification.Scoring
import OptimalComputation.Certification.Transport

/-- Internal transport for scripts/certify.py. It never reports acceptance. -/
def main (args : List String) : IO UInt32 := do
  let result ← match args with
    | [file, boundaries, terms] =>
      match boundaries.toNat?, terms.toNat? with
      | some b, some t =>
        try pure (OptimalComputation.Certification.prepareFile (← IO.FS.readFile file) b t)
        catch _ => pure (OptimalComputation.Certification.failureJson "candidate-io" "Cannot read candidate file.")
      | _, _ => pure (OptimalComputation.Certification.failureJson "invalid-arguments" "Expected numeric budgets.")
    | _ => pure (OptimalComputation.Certification.failureJson "invalid-arguments" "Expected FILE BOUNDARIES TERMS.")
  IO.println result.compress
  return 0
