import OptimalComputation.Hardware.Resources

namespace OptimalComputation.Tests

open Hardware

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw <| IO.userError s!"Hardware check failed: {label}"

private def validated (c : Config) : IO ValidConfig :=
  match validateConfig c with
  | .ok valid => pure valid
  | .error error => throw <| IO.userError error.message

private def expectRejection (c : Config) (expected : ConfigError) : IO Unit := do
  check s!"inadmissible {repr c}" (!decide (Admissible c))
  match validateConfig c with
  | .ok _ => throw <| IO.userError s!"Unexpectedly accepted {repr c}"
  | .error actual =>
    check s!"rejection reason for {repr c}" (actual == expected)

/-- Independent hand calculations for each permitted lane and bank count. -/
private def checkFamily : IO Unit := do
  let laneExpectations : List (Nat × Nat) :=
    [(1, 720), (2, 1440), (4, 2880), (8, 5760)]
  let bankExpectations : List (Nat × Nat × Nat) :=
    [(1, 4096, 8), (2, 2048, 8), (4, 1024, 8), (8, 512, 16)]
  check "exactly 16 distinct enumerated configurations"
    (allConfigs.length == 16 && allConfigs.eraseDups.length == 16)
  for (lanes, registerStorage) in laneExpectations do
    for (banks, slots, blocks) in bankExpectations do
      let raw : Config := ⟨lanes, banks⟩
      check s!"admissibility of ({lanes}, {banks})" (decide (Admissible raw))
      check s!"enumeration of ({lanes}, {banks})" (allConfigs.contains raw)
      let c ← validated raw
      let r := resourceReport c
      check "configuration preserved by validation" (c.val == raw)
      check "resource report identity"
        (r.modelVersion == "arty-model-v1" && r.configuration == raw)
      check "DSP allocation" (r.dspSlices == lanes)
      check "BRAM allocation" (r.bram36Blocks == blocks)
      check "architectural register bits" (r.writableArchitecturalRegisterBits == registerStorage)
      check "32 KiB memory with exactly two ports per bank"
        (r.logicalMemoryBits == 262144 && r.slotsPerBank == slots &&
          r.generalPurposePortsPerBank == 2)
      check "separate bounded pending slots" (r.pendingInstructionSlots == lanes * 3)
      check "physical logic costs remain uncalibrated"
        (r.controlArea.isNone && r.connectionArea.isNone && r.pipelineArea.isNone &&
          r.totalLogicArea.isNone)
      check "bank capacity partitions all slots" (r.slotsPerBank * banks == 4096)
      -- Exhaust every address for every configuration, in addition to the proofs.
      for a in List.finRange localMemorySlots do
        let location := mapAddress c a
        check "bounded bank and row"
          (location.bank.val < banks && location.row.val < slots)
        check "bank mapping reconstructs its address"
          (location.row.val * banks + location.bank.val == a.val)

private def checkRejections : IO Unit := do
  for n in [0, 3, 5, 6, 7, 9, 16, 1024] do
    expectRejection ⟨n, 8⟩ (.unsupportedLanes n)
    expectRejection ⟨8, n⟩ (.unsupportedBanks n)
  expectRejection ⟨0, 0⟩ (.unsupportedLanes 0)
  check "lane diagnostic includes allowed family"
    ((ConfigError.unsupportedLanes 3).message ==
      "Unsupported lane count 3; expected 1, 2, 4, or 8.")
  check "bank diagnostic includes allowed family"
    ((ConfigError.unsupportedBanks 0).message ==
      "Unsupported bank count 0; expected 1, 2, 4, or 8.")

private def checkRounding : IO Unit := do
  let expectations : List (Nat × Nat) :=
    [(0, 0), (1, 1), (512, 1), (1023, 1), (1024, 1), (1025, 2),
     (2047, 2), (2048, 2), (2049, 3), (4096, 4), (4097, 5)]
  for (depth, pairs) in expectations do
    check s!"whole-block rounding at depth {depth}" (bramPairsForDepth depth == pairs)

private def checkBankPorts : IO Unit := do
  let a0 : Address := ⟨0, by decide⟩
  let a1 : Address := ⟨1, by decide⟩
  let a8 : Address := ⟨8, by decide⟩
  let a16 : Address := ⟨16, by decide⟩
  let last : Address := ⟨4095, by decide⟩
  check "default is (8, 8)" (defaultConfig.val == ⟨8, 8⟩)
  check "last default bank/row"
    ((mapAddress defaultConfig last).bank.val == 7 &&
      (mapAddress defaultConfig last).row.val == 511)
  check "striped default bank/row"
    ((mapAddress defaultConfig a8).bank.val == 0 &&
      (mapAddress defaultConfig a8).row.val == 1)
  check "no requests" (bankAccessesFit defaultConfig [])
  check "two requests in one bank" (bankAccessesFit defaultConfig [a0, a8])
  check "third request rejected despite other idle banks"
    (!bankAccessesFit defaultConfig [a0, a8, a16])
  check "three requests distributed across banks" (bankAccessesFit defaultConfig [a0, a1, a8])
  check "two repeated requests each consume a port" (bankAccessesFit defaultConfig [a0, a0])
  check "third repeated request consumes a third port"
    (!bankAccessesFit defaultConfig [a0, a0, a0])
  let singleBank ← validated ⟨8, 1⟩
  check "one bank allows two requests" (bankAccessesFit singleBank [a0, a1])
  check "one bank rejects a third distinct address" (!bankAccessesFit singleBank [a0, a1, a8])

def hardware : IO Unit := do
  check "reference board physical capacities"
    (artyA7_100T.name == "Digilent Arty A7-100T" &&
      artyA7_100T.chip == "AMD/Xilinx Artix-7 XC7A100TCSG324-1" &&
      artyA7_100T.dspSlices == 240 && artyA7_100T.blockRamKibits == 4860 &&
      artyA7_100T.bram36Blocks == 135 && artyA7_100T.lookupTables == 63400 &&
      artyA7_100T.flipFlops == 126800 && artyA7_100T.externalDdr3MB == 256)
  check "fixed per-lane capacities"
    (registersPerLane == 16 && writableRegistersPerLane == 15 && registerBits == 48 &&
      operandReadsPerLanePerCycle == 3 && resultWritesPerLanePerCycle == 1 &&
      instructionsPerLanePerCycle == 1 && pendingInstructionsPerLane == 3 &&
      completionsPerPendingInstruction == 1)
  checkFamily
  checkRejections
  checkRounding
  checkBankPorts
  IO.println "PASS: hardware checks (16 configurations, 65536 address mappings, 17 rejections, 11 rounding cases, bank ports)"

end OptimalComputation.Tests
