import Std

namespace OptimalComputation.Certification

/-- Successful abstract computations are related to successful concrete ones.
Abstract failures carry no claim that the concrete computation must fail. -/
def Refines (R : α → β → Prop) (a : Except ε α) (b : Except δ β) : Prop :=
  ∀ a', a = .ok a' → ∃ b', b = .ok b' ∧ R a' b'

def foldM (f : ι → α → Except ε α) : List ι → α → Except ε α
  | [], a => .ok a
  | i :: rest, a => do foldM f rest (← f i a)

/-- Relate a simple abstract fold to the imperative loops in Hardware.step. -/
theorem foldM_forIn (R : α → β → Prop) (f : ι → α → Except ε α)
    (g : ι → β → Except δ (ForInStep β)) (items : List ι)
    (step : ∀ i ∈ items, ∀ a b, R a b → ∀ a', f i a = .ok a' →
      ∃ b', g i b = .ok (.yield b') ∧ R a' b')
    (a : α) (b : β) (h : R a b) : Refines R (foldM f items a) (forIn items b g) := by
  induction items generalizing a b with
  | nil =>
      intro a' ha
      cases ha
      exact ⟨b, rfl, h⟩
  | cons i rest ih =>
      intro a' ha
      cases hf : f i a with
      | error e => simp [foldM, hf, bind, Except.bind] at ha
      | ok middle =>
          have ha' : foldM f rest middle = .ok a' := by simpa [foldM, hf, bind, Except.bind] using ha
          obtain ⟨next, hg, hn⟩ := step i (by simp) a b h middle hf
          obtain ⟨b', hb, hr⟩ := ih (fun i hi => step i (by simp [hi])) middle next hn a' ha'
          refine ⟨b', ?_, hr⟩
          simpa [List.forIn_cons, hg, bind, Except.bind] using hb

theorem foldM_pure (f : ι → α → α) (items : List ι) (a : α) :
    foldM (fun i a => .ok (f i a) : ι → α → Except ε α) items a =
      .ok (items.foldl (fun a i => f i a) a) := by
  induction items generalizing a with
  | nil => rfl
  | cons i rest ih => simpa [foldM, bind, Except.bind] using ih (f i a)

theorem pure_forIn (R : α → β → Prop) (f : ι → α → α)
    (g : ι → β → Except δ (ForInStep β)) (items : List ι)
    (step : ∀ i ∈ items, ∀ a b, R a b → ∃ b', g i b = .ok (.yield b') ∧ R (f i a) b')
    (a : α) (b : β) (h : R a b) :
    ∃ b', forIn items b g = .ok b' ∧ R (items.foldl (fun a i => f i a) a) b' := by
  apply foldM_forIn R (ε := Unit) (fun i a => .ok (f i a)) g items ?_ a b h _ (foldM_pure f items a)
  intro i hi a b hr a' ha
  cases ha
  exact step i hi a b hr

theorem mapM_refines (f : α → Except ε β) (g : α → Except δ γ) (translate : β → γ)
    (items : List α) (h : ∀ a ∈ items, ∀ b, f a = .ok b → g a = .ok (translate b))
    (result : List β) (hr : items.mapM f = .ok result) :
    items.mapM g = .ok (result.map translate) := by
  induction items generalizing result with
  | nil =>
      have he : result = [] := by simpa [pure, Except.pure] using hr.symm
      subst result; rfl
  | cons a rest ih =>
      cases hf : f a with
      | error e => simp [List.mapM_cons, hf, bind, Except.bind] at hr
      | ok b =>
        cases ht : rest.mapM f with
        | error e => simp [List.mapM_cons, hf, ht, bind, Except.bind] at hr
        | ok bs =>
          have he : result = b :: bs := by simpa [List.mapM_cons, hf, ht, bind, Except.bind, pure, Except.pure] using hr.symm
          subst result
          simp [List.mapM_cons, h a (by simp) b hf, ih (fun a ha => h a (by simp [ha])) bs ht,
            bind, Except.bind, pure, Except.pure]

end OptimalComputation.Certification
