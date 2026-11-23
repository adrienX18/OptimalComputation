/-!
Manufacturer resource facts for the fixed reference board. These capacities do
not certify that a model-admissible accelerator can be placed, routed, or timed.
Sources and the abstraction boundary are recorded in `docs/assumptions.md`.
-/

namespace OptimalComputation.Hardware

structure BoardProfile where
  name : String
  chip : String
  dspSlices : Nat
  blockRamKibits : Nat
  lookupTables : Nat
  flipFlops : Nat
  externalDdr3MB : Nat
  deriving Repr, DecidableEq, BEq

def artyA7_100T : BoardProfile := {
  name := "Digilent Arty A7-100T"
  chip := "AMD/Xilinx Artix-7 XC7A100TCSG324-1"
  dspSlices := 240
  blockRamKibits := 4860
  lookupTables := 63400
  flipFlops := 126800
  externalDdr3MB := 256
}

/-- Nominal physical BRAM36 count; usable logical memory depends on its mode. -/
def BoardProfile.bram36Blocks (board : BoardProfile) : Nat :=
  board.blockRamKibits / 36

theorem arty_bram36_count : artyA7_100T.bram36Blocks = 135 := by decide

end OptimalComputation.Hardware
