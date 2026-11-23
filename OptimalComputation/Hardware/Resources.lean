import OptimalComputation.Hardware.Board
import OptimalComputation.Hardware.Config
import OptimalComputation.Versions

namespace OptimalComputation.Hardware

def wordsPerBramPair : Nat := 1024

/-- Integer ceiling for the fixed 1,024-word depth of a pair of BRAM36 blocks. -/
def bramPairsForDepth (depth : Nat) : Nat :=
  (depth + wordsPerBramPair - 1) / wordsPerBramPair

/-- The rounded depth covers the request with strictly less than one spare pair. -/
theorem bramPairsForDepth_rounding (depth : Nat) :
    depth ≤ bramPairsForDepth depth * wordsPerBramPair ∧
    bramPairsForDepth depth * wordsPerBramPair < depth + wordsPerBramPair := by
  simp only [bramPairsForDepth, wordsPerBramPair]
  omega

def allocatedBram36 (c : ValidConfig) : Nat :=
  c.val.banks * 2 * bramPairsForDepth (bankCapacity c)

theorem allocatedBram36_exact (c : ValidConfig) :
    allocatedBram36 c = if c.val.banks = 8 then 16 else 8 := by
  have h := c.property.2
  simp [AllowedCount, supportedCounts] at h
  rcases h with h | h | h | h <;>
    simp [allocatedBram36, bankCapacity, localMemorySlots, bramPairsForDepth,
      wordsPerBramPair, h]

structure LogicArea where
  lookupTables : Nat
  flipFlops : Nat
  deriving Repr, DecidableEq, BEq

structure ResourceReport where
  modelVersion : String
  configuration : Config
  dspSlices : Nat
  bram36Blocks : Nat
  logicalMemoryBits : Nat
  slotsPerBank : Nat
  generalPurposePortsPerBank : Nat
  writableArchitecturalRegisterBits : Nat
  /-- Capacity for result/store payload and destination metadata, not FF cost. -/
  pendingInstructionSlots : Nat
  /-- `none` means uncalibrated, never zero. Architectural bits are not total FFs. -/
  controlArea : Option LogicArea
  connectionArea : Option LogicArea
  pipelineArea : Option LogicArea
  totalLogicArea : Option LogicArea
  deriving Repr, DecidableEq, BEq

/-- Resource accounting depends only on the fixed model and validated configuration. -/
def resourceReport (c : ValidConfig) : ResourceReport := {
  modelVersion := Versions.model
  configuration := c.val
  dspSlices := c.val.lanes
  bram36Blocks := allocatedBram36 c
  logicalMemoryBits := localMemorySlots * memorySlotBits
  slotsPerBank := bankCapacity c
  generalPurposePortsPerBank := bankPorts
  writableArchitecturalRegisterBits := c.val.lanes * writableRegistersPerLane * registerBits
  pendingInstructionSlots := c.val.lanes * pendingInstructionsPerLane
  controlArea := none
  connectionArea := none
  pipelineArea := none
  totalLogicArea := none
}

/-- This bounds modeled DSP/BRAM allocations only; it is not a physical area proof. -/
theorem resourceReport_fits_board (c : ValidConfig) :
    (resourceReport c).dspSlices ≤ artyA7_100T.dspSlices ∧
    (resourceReport c).bram36Blocks ≤ artyA7_100T.bram36Blocks := by
  have hl := c.property.1
  simp [AllowedCount, supportedCounts] at hl
  have hb := allocatedBram36_exact c
  simp only [resourceReport, artyA7_100T, BoardProfile.bram36Blocks]
  by_cases h : c.val.banks = 8 <;> simp [h] at hb <;> omega

end OptimalComputation.Hardware
