import Std

/-! Fixed `arty-model-v1` configuration family and banked-memory capacities. -/

namespace OptimalComputation.Hardware

def localMemorySlots : Nat := 4096
def memorySlotBits : Nat := 64
def bankPorts : Nat := 2
def registersPerLane : Nat := 16
def writableRegistersPerLane : Nat := 15
def registerBits : Nat := 48
def operandReadsPerLanePerCycle : Nat := 3
def resultWritesPerLanePerCycle : Nat := 1
def instructionsPerLanePerCycle : Nat := 1
def pendingInstructionsPerLane : Nat := 3
def completionsPerPendingInstruction : Nat := 1

/-- The only candidate-selectable hardware parameters. -/
structure Config where
  lanes : Nat
  banks : Nat
  deriving Repr, DecidableEq, BEq

def supportedCounts : List Nat := [1, 2, 4, 8]

def AllowedCount (n : Nat) : Prop := n ∈ supportedCounts

instance (n : Nat) : Decidable (AllowedCount n) :=
  inferInstanceAs (Decidable (n ∈ supportedCounts))

def Admissible (c : Config) : Prop := AllowedCount c.lanes ∧ AllowedCount c.banks

instance (c : Config) : Decidable (Admissible c) :=
  inferInstanceAs (Decidable (AllowedCount c.lanes ∧ AllowedCount c.banks))

/-- Validation evidence travels with any configuration used by the hardware. -/
abbrev ValidConfig := { c : Config // Admissible c }

inductive ConfigError where
  | unsupportedLanes (actual : Nat)
  | unsupportedBanks (actual : Nat)
  deriving Repr, DecidableEq, BEq

def ConfigError.message : ConfigError → String
  | .unsupportedLanes n => s!"Unsupported lane count {n}; expected 1, 2, 4, or 8."
  | .unsupportedBanks n => s!"Unsupported bank count {n}; expected 1, 2, 4, or 8."

/-- Report the first invalid field, checking lanes before banks. -/
def validateConfig (c : Config) : Except ConfigError ValidConfig :=
  if hl : AllowedCount c.lanes then
    if hb : AllowedCount c.banks then .ok ⟨c, hl, hb⟩
    else .error (.unsupportedBanks c.banks)
  else .error (.unsupportedLanes c.lanes)

theorem validateConfig_accepts (c : Config) (h : Admissible c) :
    validateConfig c = .ok ⟨c, h⟩ := by
  simp [validateConfig, h.1, h.2]

theorem validateConfig_rejects_lanes (c : Config) (h : ¬ AllowedCount c.lanes) :
    validateConfig c = .error (.unsupportedLanes c.lanes) := by
  simp [validateConfig, h]

theorem validateConfig_rejects_banks (c : Config)
    (hl : AllowedCount c.lanes) (hb : ¬ AllowedCount c.banks) :
    validateConfig c = .error (.unsupportedBanks c.banks) := by
  simp [validateConfig, hl, hb]

def defaultConfig : ValidConfig := ⟨⟨8, 8⟩, by decide⟩

/-- Enumeration for checking and reporting, not a search strategy. -/
def allConfigs : List Config :=
  supportedCounts.flatMap fun l => supportedCounts.map fun b => ⟨l, b⟩

theorem allConfigs_length : allConfigs.length = 16 := by decide
theorem allConfigs_nodup : allConfigs.Nodup := by decide

theorem allConfigs_exact (c : Config) : c ∈ allConfigs ↔ Admissible c := by
  rcases c with ⟨l, b⟩
  simp [allConfigs, supportedCounts, Admissible, AllowedCount]
  omega

theorem allowedCount_positive {n : Nat} (h : AllowedCount n) : 0 < n := by
  simp [AllowedCount, supportedCounts] at h
  omega

def bankCapacity (c : ValidConfig) : Nat := localMemorySlots / c.val.banks

theorem bankCapacity_partition (c : ValidConfig) :
    bankCapacity c * c.val.banks = localMemorySlots := by
  have h := c.property.2
  simp [AllowedCount, supportedCounts] at h
  rcases h with h | h | h | h <;> simp [bankCapacity, h, localMemorySlots]

abbrev Address := Fin localMemorySlots

/-- Every physical location is in a specific bounded bank and row. -/
structure BankLocation (c : ValidConfig) where
  bank : Fin c.val.banks
  row : Fin (bankCapacity c)
  deriving Repr, DecidableEq, BEq

def bankOf (c : ValidConfig) (a : Address) : Fin c.val.banks :=
  ⟨a.val % c.val.banks, Nat.mod_lt _ (allowedCount_positive c.property.2)⟩

def rowOf (c : ValidConfig) (a : Address) : Fin (bankCapacity c) :=
  ⟨a.val / c.val.banks, by
    apply (Nat.div_lt_iff_lt_mul (allowedCount_positive c.property.2)).2
    rw [bankCapacity_partition]
    exact a.isLt⟩

def mapAddress (c : ValidConfig) (a : Address) : BankLocation c :=
  ⟨bankOf c a, rowOf c a⟩

theorem mapAddress_reconstruct (c : ValidConfig) (a : Address) :
    (mapAddress c a).row.val * c.val.banks + (mapAddress c a).bank.val = a.val := by
  exact Nat.div_add_mod' a.val c.val.banks

/-- Distinct logical slots never alias one physical bank/row location. -/
theorem mapAddress_injective (c : ValidConfig) {a b : Address}
    (h : mapAddress c a = mapAddress c b) : a = b := by
  apply Fin.ext
  rw [← mapAddress_reconstruct c a, ← mapAddress_reconstruct c b, h]

/--
Capacity-only check for a simultaneous set of memory requests. Each request
consumes one port, even duplicate reads. The later execution semantics must also
check access kinds and same-address conflicts; this is not full schedule legality.
-/
def bankAccessesFit (c : ValidConfig) (requests : List Address) : Bool :=
  (List.finRange c.val.banks).all fun bank =>
    (requests.filter fun a => bankOf c a == bank).length ≤ bankPorts

end OptimalComputation.Hardware
