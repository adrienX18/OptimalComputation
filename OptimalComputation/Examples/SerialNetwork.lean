import OptimalComputation.Examples.SerialDot
import OptimalComputation.Examples.MatMulProof
import OptimalComputation.Workloads.ExperimentWorkloads

/-! Proof-producing serial composition for explicitly supplied dot-product DAGs.
This does not certify arbitrary schedules. It reuses the existing serial runner,
with all arithmetic equations and range obligations supplied by the workload. -/
namespace OptimalComputation.Examples.SerialNetwork
open Hardware Workloads Candidates Evaluation Evaluation.Serial
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000
set_option linter.unusedSimpArgs false

abbrev Source (inputs nodes : Nat) := Sum (Fin inputs) (Fin nodes)
structure Node (inputs nodes : Nat) where
  seed : Option (Source inputs nodes) := none
  terms : Nat
  short : terms ≤ 16
  left : Fin terms → Source inputs nodes
  right : Fin terms → Source inputs nodes

def sourceValue (x : Vector Int n) (v : Fin m → Int) : Source n m → Int
  | .inl i => x[i.val]
  | .inr i => v i

def earlier (j : Nat) : Source n m → Prop
  | .inl _ => True
  | .inr i => i.val < j

structure Network (w : FlatWorkload) where
  count : Nat
  fits : w.inputs + w.outputs + count ≤ localMemorySlots
  node : Fin count → Node w.inputs count
  output : Fin w.outputs → Fin count
  value : Vector Int w.inputs → Fin count → Int
  seedEarlier : ∀ j s, (node j).seed = some s → earlier j.val s
  leftEarlier : ∀ j k, earlier j.val ((node j).left k)
  rightEarlier : ∀ j k, earlier j.val ((node j).right k)
  seedFits : ∀ x, w.allowed x → ∀ j s, (node j).seed = some s → InSigned16 (sourceValue x (value x) s)
  leftFits : ∀ x, w.allowed x → ∀ j k, InSigned16 (sourceValue x (value x) ((node j).left k))
  rightFits : ∀ x, w.allowed x → ∀ j k, InSigned16 (sourceValue x (value x) ((node j).right k))
  equation : ∀ x, w.allowed x → ∀ j,
    value x j = ((node j).seed.map (sourceValue x (value x))).getD 0 +
      dot (sourceValue x (value x) ∘ (node j).left) (sourceValue x (value x) ∘ (node j).right)
  result : ∀ x, w.allowed x → ∀ i, value x (output i) = (w.reference x)[i.val]

variable {w : FlatWorkload} {c : ValidConfig}

def inputAddress (net : Network w) (i : Fin w.inputs) : Address := ⟨i.val, by have := net.fits; omega⟩
def outputAddress (net : Network w) (i : Fin w.outputs) : Address := ⟨w.inputs + i.val, by have := net.fits; omega⟩
def nodeAddress (net : Network w) (i : Fin net.count) : Address := ⟨w.inputs + w.outputs + i.val, by have := net.fits; omega⟩
def sourceAddress (net : Network w) : Source w.inputs net.count → Address
  | .inl i => inputAddress net i
  | .inr i => nodeAddress net i

private theorem range_nodup (base n : Nat) (h : base + n ≤ localMemorySlots) :
    (List.ofFn (fun i : Fin n => (⟨base + i.val, by omega⟩ : Address))).Nodup := by
  apply List.nodup_iff_eq_of_getElem_eq.mpr
  intro i j hi hj he
  simp only [List.getElem_ofFn] at he
  have he' := congrArg Fin.val he
  simp only at he'
  omega

def layout (net : Network w) : Layout w.adapter.shape where
  inputs := List.ofFn (inputAddress net)
  outputs := List.ofFn (outputAddress net)
  scratch := List.ofFn (nodeAddress net)
  inputCount := List.length_ofFn
  outputCount := List.length_ofFn
  separate := by
    have hf := net.fits
    simp only [List.nodup_append]
    refine ⟨⟨?_, ?_, ?_⟩, ?_, ?_⟩
    · apply List.nodup_iff_eq_of_getElem_eq.mpr
      intro i j hi hj he
      simp only [List.getElem_ofFn] at he
      exact congrArg Fin.val he
    · exact range_nodup w.inputs w.outputs (by omega)
    · intro a ha b hb he
      obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
      obtain ⟨j, rfl⟩ := List.mem_ofFn.mp hb
      have := congrArg Fin.val he
      simp only [inputAddress, outputAddress] at this
      omega
    · exact range_nodup (w.inputs + w.outputs) net.count hf
    · intro a ha b hb he
      obtain ⟨j, rfl⟩ := List.mem_ofFn.mp hb
      rcases List.mem_append.mp ha with ha | ha
      all_goals
        obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
        have := congrArg Fin.val he
        simp only [inputAddress, outputAddress, nodeAddress] at this
        omega

def seedCode (net : Network w) (node : Node w.inputs net.count) : List BoundedInstruction :=
  match node.seed with
  | none => [.add acc r0 r0]
  | some s => [.load acc (sourceAddress net s)]

def nodeCode (net : Network w) (j : Fin net.count) : List BoundedInstruction :=
  seedCode net (net.node j) ++
  SerialDot.code (sourceAddress net ∘ (net.node j).left) (sourceAddress net ∘ (net.node j).right)
    (net.node j).terms (Nat.le_refl _) ++ [.store acc.val (nodeAddress net j)]

def nodesCode (net : Network w) : (n : Nat) → n ≤ net.count → List BoundedInstruction
  | 0, _ => []
  | n+1, h => nodesCode net n (by omega) ++ nodeCode net ⟨n, by omega⟩

def copyCode (net : Network w) (i : Fin w.outputs) : List BoundedInstruction :=
  [.load acc (nodeAddress net (net.output i)), .store acc.val (outputAddress net i)]

def outputsCode (net : Network w) : (n : Nat) → n ≤ w.outputs → List BoundedInstruction
  | 0, _ => []
  | n+1, h => outputsCode net n (by omega) ++ copyCode net ⟨n, by omega⟩

def code (net : Network w) : List BoundedInstruction :=
  nodesCode net net.count (Nat.le_refl _) ++ outputsCode net w.outputs (Nat.le_refl _)

theorem input_declared (net : Network w) (i : Fin w.inputs) : inputAddress net i ∈ (layout net).declared := by
  simp only [Layout.declared, layout, List.mem_append]
  exact Or.inl (Or.inl (List.mem_ofFn.mpr ⟨i, rfl⟩))
theorem node_writable (net : Network w) (i : Fin net.count) : nodeAddress net i ∈ (layout net).writable := by
  exact List.mem_append_right _ (List.mem_ofFn.mpr ⟨i, rfl⟩)
theorem output_writable (net : Network w) (i : Fin w.outputs) : outputAddress net i ∈ (layout net).writable := by
  exact List.mem_append_left _ (List.mem_ofFn.mpr ⟨i, rfl⟩)
theorem source_declared (net : Network w) (s : Source w.inputs net.count) : sourceAddress net s ∈ (layout net).declared := by
  cases s with
  | inl i => exact input_declared net i
  | inr i => exact List.mem_append_right _ (List.mem_ofFn.mpr ⟨i, rfl⟩)

theorem node_allowed (net : Network w) (j : Fin net.count) :
    ∀ i ∈ nodeCode net j, MemoryAllowed (layout net) i := by
  have hd (n : Nat) (hn : n ≤ (net.node j).terms) :
      ∀ i ∈ SerialDot.code (sourceAddress net ∘ (net.node j).left) (sourceAddress net ∘ (net.node j).right) n hn,
        MemoryAllowed (layout net) i := by
    induction n with
    | zero => simp [SerialDot.code]
    | succ n ih =>
      intro i hi
      rcases List.mem_append.mp hi with hi | hi
      · exact ih (by omega) i hi
      · simp only [SerialDot.block, List.mem_cons, List.not_mem_nil, or_false] at hi
        rcases hi with rfl | rfl | rfl
        · exact source_declared net _
        · exact source_declared net _
        · trivial
  intro i hi
  simp only [nodeCode, List.mem_append, List.mem_singleton] at hi
  rcases hi with (hi | hi) | rfl
  · unfold seedCode at hi
    split at hi
    · simp only [List.mem_singleton] at hi; subst i; trivial
    · simp only [List.mem_singleton] at hi; subst i; exact source_declared net _
  · exact hd _ _ i hi
  · exact node_writable net j

theorem code_allowed (net : Network w) : ∀ i ∈ code net, MemoryAllowed (layout net) i := by
  have hn (n : Nat) (h : n ≤ net.count) : ∀ i ∈ nodesCode net n h, MemoryAllowed (layout net) i := by
    induction n with
    | zero => simp [nodesCode]
    | succ n ih =>
      intro i hi
      rcases List.mem_append.mp hi with hi | hi
      · exact ih (by omega) i hi
      · exact node_allowed net _ i hi
  have ho (n : Nat) (h : n ≤ w.outputs) : ∀ i ∈ outputsCode net n h, MemoryAllowed (layout net) i := by
    induction n with
    | zero => simp [outputsCode]
    | succ n ih =>
      intro i hi
      rcases List.mem_append.mp hi with hi | hi
      · exact ih (by omega) i hi
      · simp only [copyCode, List.mem_cons, List.not_mem_nil, or_false] at hi
        rcases hi with rfl | rfl
        · exact source_declared net (.inr _)
        · exact output_writable net _
  intro i hi
  rcases List.mem_append.mp hi with hi | hi
  · exact hn _ _ i hi
  · exact ho _ _ i hi

def candidateFor (net : Network w) (id : String) (hid : id ≠ "") (c : ValidConfig) : Candidate w.adapter.shape where
  identifier := id
  identifier_nonempty := hid
  configuration := c
  layout := layout net
  schedule := tightSchedule c (layout net) 0 (code net) (code_allowed net)

def candidate (net : Network w) (id : String) (hid : id ≠ "") := candidateFor net id hid C

theorem seeded_fits {n : Nat} (seed : Int) (hs : InSigned16 seed) (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i)) (k : Nat) (hk : k ≤ n) (h16 : k ≤ 16) :
    InSigned48 (seed + dotPrefix a b k hk) := by
  have := dotPrefix_bounds a b ha hb k hk
  simp only [InSigned16, signed16Min, signed16Max] at hs
  simp only [InSigned48, signed48Min, signed48Max]
  omega

theorem seeded_executes {n : Nat} (seed : Int) (hsd : InSigned16 seed) (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i)) (aa ba : Fin n → Address)
    (s : State c) (hs : Quiet s)
    (hma : ∀ i, s.readMemory (aa i) = some (encodeSlot ⟨a i, signed16_fits_signed48 (ha i)⟩))
    (hmb : ∀ i, s.readMemory (ba i) = some (encodeSlot ⟨b i, signed16_fits_signed48 (hb i)⟩))
    (hz : s.readRegister lane acc.val = some ⟨seed, signed16_fits_signed48 hsd⟩)
    (k : Nat) (hk : k ≤ n) (h16 : k ≤ 16) :
    ∃ final, Executes (SerialDot.code aa ba k hk) s final ∧ final.memory = s.memory ∧
      final.readRegister lane acc.val = some ⟨seed + dotPrefix a b k hk, seeded_fits seed hsd a b ha hb k hk h16⟩ := by
  induction k with
  | zero => exact ⟨s, .nil s hs, rfl, by simpa [dotPrefix] using hz⟩
  | succ k ih =>
    obtain ⟨middle, hex, hm, hv⟩ := ih (by omega) (by omega)
    let i : Fin n := ⟨k, by omega⟩
    let av : Signed48 := ⟨a i, signed16_fits_signed48 (ha i)⟩
    let bv : Signed48 := ⟨b i, signed16_fits_signed48 (hb i)⟩
    let next : Signed48 := ⟨seed + dotPrefix a b (k+1) hk, seeded_fits seed hsd a b ha hb _ hk h16⟩
    have hc : checkedMac (a i) (b i) (seed + dotPrefix a b k (by omega)) = .ok next := by
      have he : seed + dotPrefix a b (k+1) hk = (seed + dotPrefix a b k (by omega)) + a i * b i := by
        simp only [dotPrefix, Int.add_assoc, i]
      have hn := next.property
      change InSigned48 (seed + dotPrefix a b (k+1) hk) at hn
      rw [he] at hn
      have hh := checkedMac_accepts (ha i) (hb i) (seeded_fits seed hsd a b ha hb k (by omega) (by omega)) hn
      simpa only [next, he] using hh
    have he := SerialDot.block_executes middle (executes_quiet hex) (aa i) (ba i) av bv _ next
      (by simpa [State.readMemory, hm, av] using hma i)
      (by simpa [State.readMemory, hm, bv] using hmb i) hv hc
    exact ⟨_, executes_append hex he, hm, State.readRegister_write_same _ _ _ _⟩

def seedValue (net : Network w) (x : Vector Int w.inputs) (j : Fin net.count) : Int :=
  ((net.node j).seed.map (sourceValue x (net.value x))).getD 0

theorem seed_fits (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) (j : Fin net.count) :
    InSigned16 (seedValue net x j) := by
  unfold seedValue
  cases hs : (net.node j).seed with
  | none => exact (by decide : InSigned16 0)
  | some s => exact net.seedFits x hx j s hs

theorem value_fits (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) (j : Fin net.count) :
    InSigned48 (net.value x j) := by
  rw [net.equation x hx j]
  exact seeded_fits _ (seed_fits net x hx j) _ _ (net.leftFits x hx j) (net.rightFits x hx j)
    _ (Nat.le_refl _) (net.node j).short

def nodeValue (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) (j : Fin net.count) : Signed48 :=
  ⟨net.value x j, value_fits net x hx j⟩

def Matches (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) (n : Nat) (s : State c) : Prop :=
  (∀ i : Fin w.inputs, s.readMemory (inputAddress net i) = some (encodeSlot ⟨x[i.val], w.inputFits x hx i⟩)) ∧
  (∀ i : Fin net.count, i.val < n → s.readMemory (nodeAddress net i) = some (encodeSlot (nodeValue net x hx i)))

theorem source_read (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) (n : Nat)
    (s : State c) (hm : Matches net x hx n s) (r : Source w.inputs net.count) (hr : earlier n r)
    (hfit : InSigned48 (sourceValue x (net.value x) r)) :
    s.readMemory (sourceAddress net r) = some (encodeSlot ⟨sourceValue x (net.value x) r, hfit⟩) := by
  cases r with
  | inl i => exact hm.1 i
  | inr i => exact hm.2 i hr

theorem node_executes (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x)
    (j : Fin net.count) (s : State c) (hs : Quiet s) (hm : Matches net x hx j.val s) :
    ∃ final, Executes (nodeCode net j) s final ∧
      final.memory = (s.writeMemory (nodeAddress net j) (encodeSlot (nodeValue net x hx j))).memory := by
  let seed : Signed48 := ⟨seedValue net x j, signed16_fits_signed48 (seed_fits net x hx j)⟩
  let start := s.writeRegister lane acc seed
  have hstart : Executes (seedCode net (net.node j)) s start := by
    cases he : (net.node j).seed with
    | none =>
      have hv : seed = zero48 := by apply Subtype.ext; simp [seed, seedValue, he, zero48]
      simp only [seedCode, he]
      change Executes [.add acc r0 r0] s (s.writeRegister lane acc seed)
      rw [hv]
      exact .cons _ _ _ _ (.register acc zero48) hs (fun t => prepare_reset t s hs) (.nil _ hs)
    | some r =>
      have hv : seed.val = sourceValue x (net.value x) r := by simp [seed, seedValue, he]
      have hr : s.readMemory (sourceAddress net r) = some (encodeSlot seed) := by
        have hh := source_read net x hx j.val s hm r (net.seedEarlier j r he)
          (signed16_fits_signed48 (net.seedFits x hx j r he))
        have hsval : seed = ⟨sourceValue x (net.value x) r, signed16_fits_signed48 (net.seedFits x hx j r he)⟩ := Subtype.ext hv
        rw [hsval]
        exact hh
      simp only [seedCode, he]
      exact .cons _ _ _ _ (.register acc seed) hs (fun t => prepare_load t s hs acc _ seed hr) (.nil _ hs)
  obtain ⟨middle, hd, hmem, hv⟩ := seeded_executes (seedValue net x j) (seed_fits net x hx j)
    _ _ (net.leftFits x hx j) (net.rightFits x hx j)
    (sourceAddress net ∘ (net.node j).left) (sourceAddress net ∘ (net.node j).right)
    start hs
    (fun k => source_read net x hx j.val start hm _ (net.leftEarlier j k) _)
    (fun k => source_read net x hx j.val start hm _ (net.rightEarlier j k) _)
    (State.readRegister_write_same _ _ _ _) _ (Nat.le_refl _) (net.node j).short
  have heq : (⟨seedValue net x j + dot _ _, seeded_fits _ (seed_fits net x hx j) _ _
      (net.leftFits x hx j) (net.rightFits x hx j) _ (Nat.le_refl _) (net.node j).short⟩ : Signed48) =
      nodeValue net x hx j := by
    apply Subtype.ext
    exact (net.equation x hx j).symm
  simp only [dot] at heq
  rw [heq] at hv
  have hq := executes_quiet hd
  let final := middle.writeMemory (nodeAddress net j) (encodeSlot (nodeValue net x hx j))
  have he : Executes [.store acc.val (nodeAddress net j)] middle final :=
    .cons _ _ _ _ (.memory _ _) hq
      (fun t => prepare_store t middle hq _ _ _ hv) (.nil _ hq)
  refine ⟨final, executes_append (executes_append hstart hd) he, ?_⟩
  simp only [final, State.writeMemory, hmem]
  rfl

theorem node_ne_input (net : Network w) (j : Fin net.count) (i : Fin w.inputs) :
    nodeAddress net j ≠ inputAddress net i := by
  intro h; have he := congrArg Fin.val h
  simp only [nodeAddress, inputAddress] at he
  omega

theorem node_injective (net : Network w) {i j : Fin net.count} : nodeAddress net i = nodeAddress net j → i = j := by
  intro h; apply Fin.ext
  have he := congrArg Fin.val h
  simp only [nodeAddress] at he
  omega

theorem nodes_execute (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x)
    (s : State c) (hs : Quiet s) (hm : Matches net x hx 0 s) (n : Nat) (hn : n ≤ net.count) :
    ∃ final, Executes (nodesCode net n hn) s final ∧ Matches net x hx n final := by
  induction n with
  | zero => exact ⟨s, .nil s hs, hm⟩
  | succ n ih =>
    obtain ⟨middle, he, hm⟩ := ih (by omega)
    let j : Fin net.count := ⟨n, by omega⟩
    obtain ⟨final, hj, hmem⟩ := node_executes net x hx j middle (executes_quiet he) hm
    refine ⟨final, executes_append he hj, ?_, ?_⟩
    · intro i
      change final.memory[_] = _
      rw [hmem]
      change (middle.writeMemory _ _).readMemory _ = _
      rw [State.readMemory_write_other _ _ _ _ (node_ne_input net j i)]
      exact hm.1 i
    · intro i hi
      change final.memory[_] = _
      rw [hmem]
      change (middle.writeMemory _ _).readMemory _ = _
      by_cases hij : j = i
      · subst i; exact State.readMemory_write_same _ _ _
      · rw [State.readMemory_write_other _ _ _ _ (fun h => hij (node_injective net h))]
        exact hm.2 i (by have hh : j.val ≠ i.val := fun h => hij (Fin.ext h); dsimp [j] at hh; omega)

theorem output_ne_node (net : Network w) (i : Fin w.outputs) (j : Fin net.count) :
    outputAddress net i ≠ nodeAddress net j := by
  intro h; have he := congrArg Fin.val h
  simp only [nodeAddress, outputAddress] at he
  omega

theorem outputs_execute (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x)
    (s : State c) (hs : Quiet s)
    (hm : ∀ j, s.readMemory (nodeAddress net j) = some (encodeSlot (nodeValue net x hx j)))
    (n : Nat) (hn : n ≤ w.outputs) :
    ∃ final, Executes (outputsCode net n hn) s final ∧
      (∀ j, final.readMemory (nodeAddress net j) = some (encodeSlot (nodeValue net x hx j))) ∧
      (∀ i : Fin w.outputs, i.val < n → final.readMemory (outputAddress net i) =
        some (encodeSlot (nodeValue net x hx (net.output i)))) := by
  induction n with
  | zero => exact ⟨s, .nil s hs, hm, by intro i hi; omega⟩
  | succ n ih =>
    obtain ⟨middle, he, hm, ho⟩ := ih (by omega)
    let i : Fin w.outputs := ⟨n, by omega⟩
    let v := nodeValue net x hx (net.output i)
    let loaded := middle.writeRegister lane acc v
    let final := loaded.writeMemory (outputAddress net i) (encodeSlot v)
    have hq := executes_quiet he
    have hc : Executes (copyCode net i) middle final := by
      apply Executes.cons _ _ _ _ (.register acc v) hq
      · intro t; exact prepare_load t middle hq acc _ v (hm _)
      apply Executes.cons _ _ loaded _ (.memory _ _) (show Quiet loaded from hq)
      · intro t; exact prepare_store t loaded hq acc.val _ v (State.readRegister_write_same _ _ _ _)
      exact .nil _ hq
    refine ⟨final, executes_append he hc, ?_, ?_⟩
    · intro j
      change (loaded.writeMemory _ _).readMemory _ = _
      rw [State.readMemory_write_other _ _ _ _ (output_ne_node net i j)]
      exact hm j
    · intro j hj
      change (loaded.writeMemory _ _).readMemory _ = _
      by_cases hij : i = j
      · subst j; exact State.readMemory_write_same _ _ _
      · have haddr : outputAddress net i ≠ outputAddress net j := by
          intro h; apply hij; apply Fin.ext
          have he := congrArg Fin.val h
          simp only [outputAddress] at he
          omega
        rw [State.readMemory_write_other _ _ _ _ haddr]
        exact ho j (by have hh : i.val ≠ j.val := fun h => hij (Fin.ext h); dsimp [i] at hh; omega)

theorem initial_matches (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) :
    Matches net x hx 0 (initialState c (layout net) (w.adapter.encode x hx)) := by
  constructor
  · intro i
    have hp : (layout net).inputs.zip (w.adapter.encode x hx).toList =
        List.ofFn (fun k : Fin w.inputs => (inputAddress net k, (w.adapter.encode x hx)[k.val]'(by exact k.isLt))) := by
      apply List.ext_getElem
      · simp [layout, FlatWorkload.adapter]
      · intro k hk hk'
        simp only [List.getElem_zip, List.getElem_ofFn, Vector.getElem_toList, layout]
    change (writeValues (State.empty c) ((layout net).inputs.zip (w.adapter.encode x hx).toList)).readMemory _ = _
    rw [hp]
    apply writeValues_read
    · apply List.mem_ofFn.mpr
      refine ⟨i, ?_⟩
      simp [ScalarAdapter.encode, FlatWorkload.adapter]
    · intro p hp he
      obtain ⟨j, rfl⟩ := List.mem_ofFn.mp hp
      have hij : j = i := Fin.ext (congrArg (fun a : Address => a.val) he)
      subst j
      simp [ScalarAdapter.encode, FlatWorkload.adapter]
  · intro i hi; omega

theorem code_executes (net : Network w) (x : Vector Int w.inputs) (hx : w.allowed x) :
    ∃ final, Executes (code net) (initialState c (layout net) (w.adapter.encode x hx)) final ∧
      ∀ i, final.readMemory (outputAddress net i) = some (encodeSlot (nodeValue net x hx (net.output i))) := by
  have hq : Quiet (initialState c (layout net) (w.adapter.encode x hx)) := by
    change (writeValues (State.empty c) _).pending = _
    rw [writeValues_pending]; rfl
  obtain ⟨middle, he, hm⟩ := nodes_execute net x hx _ hq (initial_matches net x hx) net.count (Nat.le_refl _)
  obtain ⟨final, ho, _, hr⟩ := outputs_execute net x hx middle (executes_quiet he)
    (fun j => hm.2 j j.isLt) w.outputs (Nat.le_refl _)
  exact ⟨final, executes_append he ho, fun i => hr i i.isLt⟩

theorem execution_correct (c : ValidConfig) (net : Network w) (id : String) (hid : id ≠ "")
    (hpos : 0 < tightDuration (code net)) (x : Vector Int w.inputs) (hx : w.allowed x) :
    ∃ record, executeValues (candidateFor net id hid c) (w.adapter.encode x hx) (tightDuration (code net) + 1) false = .success record ∧
      record.outputs = (w.reference x).toList := by
  obtain ⟨final, he, ho⟩ := code_executes (c := c) net x hx
  obtain ⟨counts, hr⟩ := run_tight_complete he _ rfl hpos
  have hp : program (candidateFor net id hid c) = tightTimed 0 (code net) := by
    unfold program candidateFor
    rw [tightSchedule_timed]
    exact List.mergeSort_of_pairwise (tightTimed_sorted _ _)
  have hn : ((layout net).outputs.filter fun a => (final.readMemory a).isNone) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro a ha
    obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
    simp only [ho, Option.isNone_some, Bool.false_eq_true, not_false_eq_true]
  have hout : collectOutputs (layout net).outputs final = (w.reference x).toList := by
    change (List.ofFn (outputAddress net)).filterMap _ = _
    rw [MatMulNaive.filterMap_ofFn (outputAddress net) _ (fun i => (w.reference x)[i.val])]
    · rw [← Vector.toList_ofFn, Vector.ofFn_getElem]
    · intro i
      simp only [ho, Option.map_some, decode_encode_slot, nodeValue, net.result x hx i]
  have hr' : run false (tightDuration (code net) + 1) 0 (program (candidateFor net id hid c))
      (initialState (candidateFor net id hid c).configuration (candidateFor net id hid c).layout (w.adapter.encode x hx))
      (Counters.empty (candidateFor net id hid c).configuration) [] = .finished ⟨tightDuration (code net), final, counts, []⟩ := by
    rw [hp]
    exact hr
  have hf : ∃ record, finish (candidateFor net id hid c) ⟨tightDuration (code net), final, counts, []⟩ = .success record ∧
      record.outputs = (w.reference x).toList := by
    unfold finish
    change ∃ record, (if ((layout net).outputs.filter fun a => (final.readMemory a).isNone).isEmpty then _ else _) = _ ∧ _
    simp only [hn, List.isEmpty_nil, ↓reduceIte]
    exact ⟨_, rfl, hout⟩
  obtain ⟨record, hf, hout⟩ := hf
  exact ⟨record, MatMulNaive.execute_of_finished _ _ _ _ _ hr' hf, hout⟩

theorem outputs_duration (net : Network w) (n : Nat) (hn : n ≤ w.outputs) :
    tightDuration (outputsCode net n hn) = 2 * n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [outputsCode, tightDuration_append, copyCode, tightDuration, latency, ih]; omega

theorem code_positive (net : Network w) (h : 0 < w.outputs) : 0 < tightDuration (code net) := by
  simp only [code, tightDuration_append, outputs_duration]
  omega

def verifiedFor (c : ValidConfig) (net : Network w) (id : String) (hid : id ≠ "") (hpos : 0 < tightDuration (code net)) :
    VerifiedCandidate w.adapter where
  candidate := candidateFor net id hid c
  sufficientBoundaries := tightDuration (code net) + 1
  safety := by
    intro x hx
    obtain ⟨r, he, _⟩ := execution_correct c net id hid hpos x hx
    exact ⟨r, he⟩
  correctness := by
    intro x hx r he
    obtain ⟨r', he', ho⟩ := execution_correct c net id hid hpos x hx
    have hh := ExecutionOutcome.success.inj (he'.symm.trans he)
    subst r; exact ho

def verified (net : Network w) (id : String) (hid : id ≠ "") (hpos : 0 < tightDuration (code net)) :=
  verifiedFor C net id hid hpos

end OptimalComputation.Examples.SerialNetwork
