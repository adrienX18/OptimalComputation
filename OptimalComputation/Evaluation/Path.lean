import OptimalComputation.Evaluation.Execution

namespace OptimalComputation.Evaluation
open Hardware

/-- Compose a finite sequence of actual machine steps. States are proof
witnesses, not an alternative executor; every edge requires Hardware.step. -/
theorem run_path (n : Nat) (states : Nat → State c) (queues : Nat → List (TimedAction c))
    (batches : Nat → List (TimedAction c))
    (hn : ∀ i, i < n → ((queues i).isEmpty && (states i).drained) = false)
    (hq : ∀ i, i < n → (queues i).span (fun a => a.cycle == i) = (batches i, queues (i + 1)))
    (hs : ∀ i, i < n → ∃ events, step i ((batches i).map TimedAction.action) (states i) =
      .ok (states (i + 1), events))
    (hendq : queues n = []) (hends : (states n).drained = true)
    (fuel t : Nat) (ht : t + fuel = n) (counts : Counters) :
    ∃ finalCounts, run false fuel t (queues t) (states t) counts [] =
      .finished ⟨n - 1, states n, finalCounts, []⟩ := by
  induction fuel generalizing t counts with
  | zero =>
    have he : t = n := by omega
    subst t
    exact ⟨counts, by rw [hendq, run_finished false 0 n (states n) counts [] hends]; rfl⟩
  | succ fuel ih =>
    have hlt : t < n := by omega
    obtain ⟨events, hstep⟩ := hs t hlt
    rw [run_step false fuel t _ _ _ _ _ counts [] events (hn t hlt) (hq t hlt) hstep]
    simp only [Bool.false_eq_true, ↓reduceIte]
    exact ih (t + 1) (by omega) _

end OptimalComputation.Evaluation
