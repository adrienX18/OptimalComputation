import OptimalComputation.Certification.Scoring
import OptimalComputation.Certification.Catalog

namespace Certificate_c70881073b615e01e73756cc4e8b21d4f727634f2f1b90be2b6d0e0771e96c5c
open OptimalComputation OptimalComputation.Hardware OptimalComputation.Candidates OptimalComputation.Certification
set_option maxRecDepth 100000
set_option maxHeartbeats 20000000

def entry := Catalog.polynomial
def raw : RawCandidate := {
  identifier := "polynomial-naive-v1"
  workloadIdentifier := "polynomial-degree7-points16-v1"
  modelVersion := "arty-model-v1"
  formatVersion := "candidate-v1"
  configuration := ⟨8, 8⟩
  layout := ⟨[0, 1, 2, 3, 4, 5, 6, 7, 16, 17, 48, 49, 26, 27, 64, 57, 8, 9, 40, 41, 56, 34, 72, 65], [24, 25, 10, 11, 12, 13, 14, 15, 32, 33, 18, 19, 20, 21, 22, 23], []⟩
  schedule := [
    ⟨0, 0, .load 1 7⟩,
    ⟨0, 1, .load 1 7⟩,
    ⟨0, 2, .load 1 40⟩,
    ⟨0, 3, .load 1 41⟩,
    ⟨0, 4, .load 1 26⟩,
    ⟨0, 5, .load 1 27⟩,
    ⟨0, 6, .load 1 6⟩,
    ⟨0, 7, .load 1 6⟩,
    ⟨1, 0, .load 2 1⟩,
    ⟨1, 1, .load 2 1⟩,
    ⟨1, 2, .load 2 7⟩,
    ⟨1, 3, .load 2 7⟩,
    ⟨1, 4, .load 2 56⟩,
    ⟨1, 5, .load 2 34⟩,
    ⟨1, 6, .load 2 3⟩,
    ⟨1, 7, .load 2 3⟩,
    ⟨2, 0, .load 3 5⟩,
    ⟨2, 1, .load 3 5⟩,
    ⟨2, 2, .load 3 48⟩,
    ⟨2, 3, .load 3 49⟩,
    ⟨2, 4, .load 3 4⟩,
    ⟨2, 5, .load 3 4⟩,
    ⟨2, 6, .load 3 7⟩,
    ⟨2, 7, .load 3 7⟩,
    ⟨3, 0, .load 4 6⟩,
    ⟨3, 1, .load 4 6⟩,
    ⟨3, 2, .load 4 5⟩,
    ⟨3, 3, .load 4 5⟩,
    ⟨3, 4, .load 4 7⟩,
    ⟨3, 5, .load 4 7⟩,
    ⟨3, 6, .load 4 64⟩,
    ⟨3, 7, .load 4 57⟩,
    ⟨4, 0, .load 5 8⟩,
    ⟨4, 1, .load 5 9⟩,
    ⟨4, 2, .load 5 6⟩,
    ⟨4, 3, .load 5 6⟩,
    ⟨4, 4, .load 5 2⟩,
    ⟨4, 5, .load 5 2⟩,
    ⟨4, 6, .multiplyAdd 5 3 4 1⟩,
    ⟨4, 7, .multiplyAdd 5 3 4 1⟩,
    ⟨5, 0, .multiplyAdd 6 1 5 4⟩,
    ⟨5, 1, .multiplyAdd 6 1 5 4⟩,
    ⟨5, 2, .multiplyAdd 6 2 1 5⟩,
    ⟨5, 3, .multiplyAdd 6 2 1 5⟩,
    ⟨5, 4, .load 6 5⟩,
    ⟨5, 5, .load 6 5⟩,
    ⟨5, 6, .load 6 72⟩,
    ⟨5, 7, .load 6 65⟩,
    ⟨6, 0, .load 7 16⟩,
    ⟨6, 1, .load 7 17⟩,
    ⟨6, 2, .load 7 4⟩,
    ⟨6, 3, .load 7 4⟩,
    ⟨6, 4, .load 7 3⟩,
    ⟨6, 5, .load 7 3⟩,
    ⟨6, 6, .multiply 7 4 4⟩,
    ⟨6, 7, .multiply 7 4 4⟩,
    ⟨7, 0, .multiplyAdd 1 1 7 4⟩,
    ⟨7, 1, .multiplyAdd 1 1 7 4⟩,
    ⟨7, 2, .multiplyAdd 2 2 3 5⟩,
    ⟨7, 3, .multiplyAdd 2 2 3 5⟩,
    ⟨7, 4, .load 8 6⟩,
    ⟨7, 5, .load 8 6⟩,
    ⟨7, 6, .load 8 5⟩,
    ⟨7, 7, .load 8 5⟩,
    ⟨8, 0, .load 4 3⟩,
    ⟨8, 1, .load 4 3⟩,
    ⟨8, 2, .load 5 2⟩,
    ⟨8, 3, .load 5 2⟩,
    ⟨8, 4, .multiplyAdd 9 4 1 8⟩,
    ⟨8, 5, .multiplyAdd 9 4 1 8⟩,
    ⟨8, 6, .multiply 9 6 6⟩,
    ⟨8, 7, .multiply 9 6 6⟩,
    ⟨9, 0, .multiplyAdd 6 6 5 3⟩,
    ⟨9, 1, .multiplyAdd 6 6 5 3⟩,
    ⟨9, 2, .multiplyAdd 6 6 1 4⟩,
    ⟨9, 3, .multiplyAdd 6 6 1 4⟩,
    ⟨9, 4, .load 10 1⟩,
    ⟨9, 5, .load 10 1⟩,
    ⟨9, 6, .load 10 2⟩,
    ⟨9, 7, .load 10 2⟩,
    ⟨10, 0, .load 8 4⟩,
    ⟨10, 1, .load 8 4⟩,
    ⟨10, 2, .load 8 3⟩,
    ⟨10, 3, .load 8 3⟩,
    ⟨10, 4, .multiplyAdd 4 4 2 8⟩,
    ⟨10, 5, .multiplyAdd 4 4 2 8⟩,
    ⟨10, 6, .multiplyAdd 1 3 6 1⟩,
    ⟨10, 7, .multiplyAdd 1 3 6 1⟩,
    ⟨11, 0, .multiply 9 7 7⟩,
    ⟨11, 1, .multiply 9 7 7⟩,
    ⟨11, 2, .multiply 9 3 3⟩,
    ⟨11, 3, .multiply 9 3 3⟩,
    ⟨11, 4, .load 8 0⟩,
    ⟨11, 5, .load 8 0⟩,
    ⟨11, 6, .load 3 1⟩,
    ⟨11, 7, .load 3 1⟩,
    ⟨12, 0, .load 10 2⟩,
    ⟨12, 1, .load 10 2⟩,
    ⟨12, 2, .load 10 0⟩,
    ⟨12, 3, .load 10 0⟩,
    ⟨12, 4, .multiplyAdd 9 9 1 6⟩,
    ⟨12, 5, .multiplyAdd 9 9 1 6⟩,
    ⟨12, 6, .multiplyAdd 5 5 4 8⟩,
    ⟨12, 7, .multiplyAdd 5 5 4 8⟩,
    ⟨13, 0, .multiplyAdd 1 1 7 3⟩,
    ⟨13, 1, .multiplyAdd 1 1 7 3⟩,
    ⟨13, 2, .multiplyAdd 2 2 3 4⟩,
    ⟨13, 3, .multiplyAdd 2 2 3 4⟩,
    ⟨13, 4, .multiplyAdd 4 4 2 6⟩,
    ⟨13, 5, .multiplyAdd 4 4 2 6⟩,
    ⟨13, 6, .load 11 4⟩,
    ⟨13, 7, .load 11 4⟩,
    ⟨14, 0, .load 3 0⟩,
    ⟨14, 1, .load 3 0⟩,
    ⟨14, 2, .load 4 1⟩,
    ⟨14, 3, .load 4 1⟩,
    ⟨14, 4, .multiplyAdd 6 10 2 8⟩,
    ⟨14, 5, .multiplyAdd 6 10 2 8⟩,
    ⟨14, 6, .multiplyAdd 1 1 6 8⟩,
    ⟨14, 7, .multiplyAdd 1 1 6 8⟩,
    ⟨15, 0, .multiplyAdd 6 6 5 8⟩,
    ⟨15, 1, .multiplyAdd 6 6 5 8⟩,
    ⟨15, 2, .multiplyAdd 11 4 1 10⟩,
    ⟨15, 3, .multiplyAdd 11 4 1 10⟩,
    ⟨15, 4, .multiplyAdd 9 9 1 3⟩,
    ⟨15, 5, .multiplyAdd 9 9 1 3⟩,
    ⟨15, 6, .load 8 0⟩,
    ⟨15, 7, .load 8 0⟩,
    ⟨16, 0, .multiplyAdd 1 1 7 8⟩,
    ⟨16, 1, .multiplyAdd 1 1 7 8⟩,
    ⟨16, 2, .multiplyAdd 2 2 3 7⟩,
    ⟨16, 3, .multiplyAdd 2 2 3 7⟩,
    ⟨16, 4, .multiplyAdd 3 4 2 3⟩,
    ⟨16, 5, .multiplyAdd 3 4 2 3⟩,
    ⟨16, 6, .multiplyAdd 5 5 4 11⟩,
    ⟨16, 7, .multiplyAdd 5 5 4 11⟩,
    ⟨17, 0, .multiply 8 5 5⟩,
    ⟨17, 1, .multiply 8 5 5⟩,
    ⟨17, 2, .multiplyAdd 6 6 1 7⟩,
    ⟨17, 3, .multiplyAdd 6 6 1 7⟩,
    ⟨17, 4, .multiply 4 1 1⟩,
    ⟨17, 5, .multiply 4 1 1⟩,
    ⟨17, 6, .multiplyAdd 1 1 6 11⟩,
    ⟨17, 7, .multiplyAdd 1 1 6 11⟩,
    ⟨18, 0, .multiplyAdd 6 6 5 4⟩,
    ⟨18, 1, .multiplyAdd 6 6 5 4⟩,
    ⟨18, 2, .multiplyAdd 4 4 3 10⟩,
    ⟨18, 3, .multiplyAdd 4 4 3 10⟩,
    ⟨18, 4, .multiplyAdd 9 9 1 7⟩,
    ⟨18, 5, .multiplyAdd 9 9 1 7⟩,
    ⟨18, 6, .multiplyAdd 11 3 4 8⟩,
    ⟨18, 7, .multiplyAdd 11 3 4 8⟩,
    ⟨19, 0, .multiplyAdd 1 1 7 4⟩,
    ⟨19, 1, .multiplyAdd 1 1 7 4⟩,
    ⟨19, 2, .multiplyAdd 2 2 3 8⟩,
    ⟨19, 3, .multiplyAdd 2 2 3 8⟩,
    ⟨19, 4, .multiplyAdd 3 3 2 7⟩,
    ⟨19, 5, .multiplyAdd 3 3 2 7⟩,
    ⟨19, 6, .multiplyAdd 5 5 4 2⟩,
    ⟨19, 7, .multiplyAdd 5 5 4 2⟩,
    ⟨20, 0, .multiplyAdd 4 2 7 3⟩,
    ⟨20, 1, .multiplyAdd 4 2 7 3⟩,
    ⟨20, 2, .multiplyAdd 6 6 1 8⟩,
    ⟨20, 3, .multiplyAdd 6 6 1 8⟩,
    ⟨20, 4, .multiplyAdd 7 10 1 8⟩,
    ⟨20, 5, .multiplyAdd 7 10 1 8⟩,
    ⟨20, 6, .multiplyAdd 1 1 6 2⟩,
    ⟨20, 7, .multiplyAdd 1 1 6 2⟩,
    ⟨21, 0, .multiplyAdd 6 6 5 10⟩,
    ⟨21, 1, .multiplyAdd 6 6 5 10⟩,
    ⟨21, 2, .multiply 7 1 1⟩,
    ⟨21, 3, .multiply 7 1 1⟩,
    ⟨21, 4, .multiplyAdd 1 9 1 5⟩,
    ⟨21, 5, .multiplyAdd 1 9 1 5⟩,
    ⟨21, 6, .multiplyAdd 2 3 6 8⟩,
    ⟨21, 7, .multiplyAdd 2 3 6 8⟩,
    ⟨22, 0, .multiplyAdd 1 1 7 10⟩,
    ⟨22, 1, .multiplyAdd 1 1 7 10⟩,
    ⟨22, 2, .multiplyAdd 2 2 3 5⟩,
    ⟨22, 3, .multiplyAdd 2 2 3 5⟩,
    ⟨22, 4, .multiplyAdd 3 3 2 5⟩,
    ⟨22, 5, .multiplyAdd 3 3 2 5⟩,
    ⟨22, 6, .multiplyAdd 3 5 4 10⟩,
    ⟨22, 7, .multiplyAdd 3 5 4 10⟩,
    ⟨23, 0, .multiplyAdd 2 2 5 3⟩,
    ⟨23, 1, .multiplyAdd 2 2 5 3⟩,
    ⟨23, 2, .multiplyAdd 1 6 1 5⟩,
    ⟨23, 3, .multiplyAdd 1 6 1 5⟩,
    ⟨23, 4, .multiply 2 2 2⟩,
    ⟨23, 5, .multiply 2 2 2⟩,
    ⟨23, 6, .multiplyAdd 1 1 6 10⟩,
    ⟨23, 7, .multiplyAdd 1 1 6 10⟩,
    ⟨24, 4, .multiplyAdd 1 1 4 7⟩,
    ⟨24, 5, .multiplyAdd 1 1 4 7⟩,
    ⟨25, 0, .multiplyAdd 1 1 9 4⟩,
    ⟨25, 1, .multiplyAdd 1 1 9 4⟩,
    ⟨25, 2, .multiplyAdd 2 2 9 4⟩,
    ⟨25, 3, .multiplyAdd 2 2 9 4⟩,
    ⟨25, 6, .multiplyAdd 3 3 7 11⟩,
    ⟨25, 7, .multiplyAdd 3 3 7 11⟩,
    ⟨26, 0, .multiplyAdd 2 6 8 2⟩,
    ⟨26, 1, .multiplyAdd 2 6 8 2⟩,
    ⟨26, 2, .multiplyAdd 1 1 7 11⟩,
    ⟨26, 3, .multiplyAdd 1 1 7 11⟩,
    ⟨26, 4, .multiplyAdd 2 3 2 6⟩,
    ⟨26, 5, .multiplyAdd 2 3 2 6⟩,
    ⟨26, 6, .multiplyAdd 1 1 9 2⟩,
    ⟨26, 7, .multiplyAdd 1 1 9 2⟩,
    ⟨28, 0, .store 1 24⟩,
    ⟨28, 1, .store 1 25⟩,
    ⟨28, 2, .store 2 10⟩,
    ⟨28, 3, .store 2 11⟩,
    ⟨28, 4, .store 1 12⟩,
    ⟨28, 5, .store 1 13⟩,
    ⟨28, 6, .store 3 14⟩,
    ⟨28, 7, .store 3 15⟩,
    ⟨29, 0, .store 2 32⟩,
    ⟨29, 1, .store 2 33⟩,
    ⟨29, 2, .store 1 18⟩,
    ⟨29, 3, .store 1 19⟩,
    ⟨29, 4, .store 2 20⟩,
    ⟨29, 5, .store 2 21⟩,
    ⟨29, 6, .store 1 22⟩,
    ⟨29, 7, .store 1 23⟩]
}

def cfg : ValidConfig := ⟨raw.configuration, by decide⟩
def r0 : Register := ⟨0, by decide⟩
def r1 : Register := ⟨1, by decide⟩
def d1 : WritableRegister := ⟨r1, by decide⟩
def r2 : Register := ⟨2, by decide⟩
def d2 : WritableRegister := ⟨r2, by decide⟩
def r3 : Register := ⟨3, by decide⟩
def d3 : WritableRegister := ⟨r3, by decide⟩
def r4 : Register := ⟨4, by decide⟩
def d4 : WritableRegister := ⟨r4, by decide⟩
def r5 : Register := ⟨5, by decide⟩
def d5 : WritableRegister := ⟨r5, by decide⟩
def r6 : Register := ⟨6, by decide⟩
def d6 : WritableRegister := ⟨r6, by decide⟩
def r7 : Register := ⟨7, by decide⟩
def d7 : WritableRegister := ⟨r7, by decide⟩
def r8 : Register := ⟨8, by decide⟩
def d8 : WritableRegister := ⟨r8, by decide⟩
def r9 : Register := ⟨9, by decide⟩
def d9 : WritableRegister := ⟨r9, by decide⟩
def r10 : Register := ⟨10, by decide⟩
def d10 : WritableRegister := ⟨r10, by decide⟩
def r11 : Register := ⟨11, by decide⟩
def d11 : WritableRegister := ⟨r11, by decide⟩
def r12 : Register := ⟨12, by decide⟩
def d12 : WritableRegister := ⟨r12, by decide⟩
def r13 : Register := ⟨13, by decide⟩
def d13 : WritableRegister := ⟨r13, by decide⟩
def r14 : Register := ⟨14, by decide⟩
def d14 : WritableRegister := ⟨r14, by decide⟩
def r15 : Register := ⟨15, by decide⟩
def d15 : WritableRegister := ⟨r15, by decide⟩
def l0 : Lane cfg := ⟨0, by decide⟩
def l1 : Lane cfg := ⟨1, by decide⟩
def l2 : Lane cfg := ⟨2, by decide⟩
def l3 : Lane cfg := ⟨3, by decide⟩
def l4 : Lane cfg := ⟨4, by decide⟩
def l5 : Lane cfg := ⟨5, by decide⟩
def l6 : Lane cfg := ⟨6, by decide⟩
def l7 : Lane cfg := ⟨7, by decide⟩
def a0 : Address := ⟨0, by decide⟩
def a1 : Address := ⟨1, by decide⟩
def a2 : Address := ⟨2, by decide⟩
def a3 : Address := ⟨3, by decide⟩
def a4 : Address := ⟨4, by decide⟩
def a5 : Address := ⟨5, by decide⟩
def a6 : Address := ⟨6, by decide⟩
def a7 : Address := ⟨7, by decide⟩
def a16 : Address := ⟨16, by decide⟩
def a17 : Address := ⟨17, by decide⟩
def a48 : Address := ⟨48, by decide⟩
def a49 : Address := ⟨49, by decide⟩
def a26 : Address := ⟨26, by decide⟩
def a27 : Address := ⟨27, by decide⟩
def a64 : Address := ⟨64, by decide⟩
def a57 : Address := ⟨57, by decide⟩
def a8 : Address := ⟨8, by decide⟩
def a9 : Address := ⟨9, by decide⟩
def a40 : Address := ⟨40, by decide⟩
def a41 : Address := ⟨41, by decide⟩
def a56 : Address := ⟨56, by decide⟩
def a34 : Address := ⟨34, by decide⟩
def a72 : Address := ⟨72, by decide⟩
def a65 : Address := ⟨65, by decide⟩
def a24 : Address := ⟨24, by decide⟩
def a25 : Address := ⟨25, by decide⟩
def a10 : Address := ⟨10, by decide⟩
def a11 : Address := ⟨11, by decide⟩
def a12 : Address := ⟨12, by decide⟩
def a13 : Address := ⟨13, by decide⟩
def a14 : Address := ⟨14, by decide⟩
def a15 : Address := ⟨15, by decide⟩
def a32 : Address := ⟨32, by decide⟩
def a33 : Address := ⟨33, by decide⟩
def a18 : Address := ⟨18, by decide⟩
def a19 : Address := ⟨19, by decide⟩
def a20 : Address := ⟨20, by decide⟩
def a21 : Address := ⟨21, by decide⟩
def a22 : Address := ⟨22, by decide⟩
def a23 : Address := ⟨23, by decide⟩
def lay : Layout entry.adapter.shape := {
inputs := [a0, a1, a2, a3, a4, a5, a6, a7, a16, a17, a48, a49, a26, a27, a64, a57, a8, a9, a40, a41, a56, a34, a72, a65]
outputs := [a24, a25, a10, a11, a12, a13, a14, a15, a32, a33, a18, a19, a20, a21, a22, a23]
scratch := []
inputCount := by decide
outputCount := by decide
separate := (distinctAddresses_iff _).mp (by decide +kernel)
}
theorem load0 : a0 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 0) (by decide)
theorem load1 : a1 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 1) (by decide)
theorem load2 : a2 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 2) (by decide)
theorem load3 : a3 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 3) (by decide)
theorem load4 : a4 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 4) (by decide)
theorem load5 : a5 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 5) (by decide)
theorem load6 : a6 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 6) (by decide)
theorem load7 : a7 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 7) (by decide)
theorem load16 : a16 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 8) (by decide)
theorem load17 : a17 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 9) (by decide)
theorem load48 : a48 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 10) (by decide)
theorem load49 : a49 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 11) (by decide)
theorem load26 : a26 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 12) (by decide)
theorem load27 : a27 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 13) (by decide)
theorem load64 : a64 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 14) (by decide)
theorem load57 : a57 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 15) (by decide)
theorem load8 : a8 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 16) (by decide)
theorem load9 : a9 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 17) (by decide)
theorem load40 : a40 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 18) (by decide)
theorem load41 : a41 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 19) (by decide)
theorem load56 : a56 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 20) (by decide)
theorem load34 : a34 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 21) (by decide)
theorem load72 : a72 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 22) (by decide)
theorem load65 : a65 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 23) (by decide)
theorem load24 : a24 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 24) (by decide)
theorem load25 : a25 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 25) (by decide)
theorem load10 : a10 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 26) (by decide)
theorem load11 : a11 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 27) (by decide)
theorem load12 : a12 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 28) (by decide)
theorem load13 : a13 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 29) (by decide)
theorem load14 : a14 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 30) (by decide)
theorem load15 : a15 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 31) (by decide)
theorem load32 : a32 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 32) (by decide)
theorem load33 : a33 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 33) (by decide)
theorem load18 : a18 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 34) (by decide)
theorem load19 : a19 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 35) (by decide)
theorem load20 : a20 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 36) (by decide)
theorem load21 : a21 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 37) (by decide)
theorem load22 : a22 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 38) (by decide)
theorem load23 : a23 ∈ lay.declared := by exact List.getElem_mem (l := lay.declared) (n := 39) (by decide)
theorem store24 : a24 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 0) (by decide)
theorem store25 : a25 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 1) (by decide)
theorem store10 : a10 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 2) (by decide)
theorem store11 : a11 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 3) (by decide)
theorem store12 : a12 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 4) (by decide)
theorem store13 : a13 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 5) (by decide)
theorem store14 : a14 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 6) (by decide)
theorem store15 : a15 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 7) (by decide)
theorem store32 : a32 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 8) (by decide)
theorem store33 : a33 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 9) (by decide)
theorem store18 : a18 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 10) (by decide)
theorem store19 : a19 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 11) (by decide)
theorem store20 : a20 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 12) (by decide)
theorem store21 : a21 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 13) (by decide)
theorem store22 : a22 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 14) (by decide)
theorem store23 : a23 ∈ lay.writable := by exact List.getElem_mem (l := lay.writable) (n := 15) (by decide)
def candidate : Candidate entry.adapter.shape := {
identifier := raw.identifier
identifier_nonempty := by decide
configuration := cfg
layout := lay
schedule := [
⟨0, l0, .load d1 a7, load7⟩,
⟨0, l1, .load d1 a7, load7⟩,
⟨0, l2, .load d1 a40, load40⟩,
⟨0, l3, .load d1 a41, load41⟩,
⟨0, l4, .load d1 a26, load26⟩,
⟨0, l5, .load d1 a27, load27⟩,
⟨0, l6, .load d1 a6, load6⟩,
⟨0, l7, .load d1 a6, load6⟩,
⟨1, l0, .load d2 a1, load1⟩,
⟨1, l1, .load d2 a1, load1⟩,
⟨1, l2, .load d2 a7, load7⟩,
⟨1, l3, .load d2 a7, load7⟩,
⟨1, l4, .load d2 a56, load56⟩,
⟨1, l5, .load d2 a34, load34⟩,
⟨1, l6, .load d2 a3, load3⟩,
⟨1, l7, .load d2 a3, load3⟩,
⟨2, l0, .load d3 a5, load5⟩,
⟨2, l1, .load d3 a5, load5⟩,
⟨2, l2, .load d3 a48, load48⟩,
⟨2, l3, .load d3 a49, load49⟩,
⟨2, l4, .load d3 a4, load4⟩,
⟨2, l5, .load d3 a4, load4⟩,
⟨2, l6, .load d3 a7, load7⟩,
⟨2, l7, .load d3 a7, load7⟩,
⟨3, l0, .load d4 a6, load6⟩,
⟨3, l1, .load d4 a6, load6⟩,
⟨3, l2, .load d4 a5, load5⟩,
⟨3, l3, .load d4 a5, load5⟩,
⟨3, l4, .load d4 a7, load7⟩,
⟨3, l5, .load d4 a7, load7⟩,
⟨3, l6, .load d4 a64, load64⟩,
⟨3, l7, .load d4 a57, load57⟩,
⟨4, l0, .load d5 a8, load8⟩,
⟨4, l1, .load d5 a9, load9⟩,
⟨4, l2, .load d5 a6, load6⟩,
⟨4, l3, .load d5 a6, load6⟩,
⟨4, l4, .load d5 a2, load2⟩,
⟨4, l5, .load d5 a2, load2⟩,
⟨4, l6, .multiplyAdd d5 r3 r4 r1, True.intro⟩,
⟨4, l7, .multiplyAdd d5 r3 r4 r1, True.intro⟩,
⟨5, l0, .multiplyAdd d6 r1 r5 r4, True.intro⟩,
⟨5, l1, .multiplyAdd d6 r1 r5 r4, True.intro⟩,
⟨5, l2, .multiplyAdd d6 r2 r1 r5, True.intro⟩,
⟨5, l3, .multiplyAdd d6 r2 r1 r5, True.intro⟩,
⟨5, l4, .load d6 a5, load5⟩,
⟨5, l5, .load d6 a5, load5⟩,
⟨5, l6, .load d6 a72, load72⟩,
⟨5, l7, .load d6 a65, load65⟩,
⟨6, l0, .load d7 a16, load16⟩,
⟨6, l1, .load d7 a17, load17⟩,
⟨6, l2, .load d7 a4, load4⟩,
⟨6, l3, .load d7 a4, load4⟩,
⟨6, l4, .load d7 a3, load3⟩,
⟨6, l5, .load d7 a3, load3⟩,
⟨6, l6, .multiply d7 r4 r4, True.intro⟩,
⟨6, l7, .multiply d7 r4 r4, True.intro⟩,
⟨7, l0, .multiplyAdd d1 r1 r7 r4, True.intro⟩,
⟨7, l1, .multiplyAdd d1 r1 r7 r4, True.intro⟩,
⟨7, l2, .multiplyAdd d2 r2 r3 r5, True.intro⟩,
⟨7, l3, .multiplyAdd d2 r2 r3 r5, True.intro⟩,
⟨7, l4, .load d8 a6, load6⟩,
⟨7, l5, .load d8 a6, load6⟩,
⟨7, l6, .load d8 a5, load5⟩,
⟨7, l7, .load d8 a5, load5⟩,
⟨8, l0, .load d4 a3, load3⟩,
⟨8, l1, .load d4 a3, load3⟩,
⟨8, l2, .load d5 a2, load2⟩,
⟨8, l3, .load d5 a2, load2⟩,
⟨8, l4, .multiplyAdd d9 r4 r1 r8, True.intro⟩,
⟨8, l5, .multiplyAdd d9 r4 r1 r8, True.intro⟩,
⟨8, l6, .multiply d9 r6 r6, True.intro⟩,
⟨8, l7, .multiply d9 r6 r6, True.intro⟩,
⟨9, l0, .multiplyAdd d6 r6 r5 r3, True.intro⟩,
⟨9, l1, .multiplyAdd d6 r6 r5 r3, True.intro⟩,
⟨9, l2, .multiplyAdd d6 r6 r1 r4, True.intro⟩,
⟨9, l3, .multiplyAdd d6 r6 r1 r4, True.intro⟩,
⟨9, l4, .load d10 a1, load1⟩,
⟨9, l5, .load d10 a1, load1⟩,
⟨9, l6, .load d10 a2, load2⟩,
⟨9, l7, .load d10 a2, load2⟩,
⟨10, l0, .load d8 a4, load4⟩,
⟨10, l1, .load d8 a4, load4⟩,
⟨10, l2, .load d8 a3, load3⟩,
⟨10, l3, .load d8 a3, load3⟩,
⟨10, l4, .multiplyAdd d4 r4 r2 r8, True.intro⟩,
⟨10, l5, .multiplyAdd d4 r4 r2 r8, True.intro⟩,
⟨10, l6, .multiplyAdd d1 r3 r6 r1, True.intro⟩,
⟨10, l7, .multiplyAdd d1 r3 r6 r1, True.intro⟩,
⟨11, l0, .multiply d9 r7 r7, True.intro⟩,
⟨11, l1, .multiply d9 r7 r7, True.intro⟩,
⟨11, l2, .multiply d9 r3 r3, True.intro⟩,
⟨11, l3, .multiply d9 r3 r3, True.intro⟩,
⟨11, l4, .load d8 a0, load0⟩,
⟨11, l5, .load d8 a0, load0⟩,
⟨11, l6, .load d3 a1, load1⟩,
⟨11, l7, .load d3 a1, load1⟩,
⟨12, l0, .load d10 a2, load2⟩,
⟨12, l1, .load d10 a2, load2⟩,
⟨12, l2, .load d10 a0, load0⟩,
⟨12, l3, .load d10 a0, load0⟩,
⟨12, l4, .multiplyAdd d9 r9 r1 r6, True.intro⟩,
⟨12, l5, .multiplyAdd d9 r9 r1 r6, True.intro⟩,
⟨12, l6, .multiplyAdd d5 r5 r4 r8, True.intro⟩,
⟨12, l7, .multiplyAdd d5 r5 r4 r8, True.intro⟩,
⟨13, l0, .multiplyAdd d1 r1 r7 r3, True.intro⟩,
⟨13, l1, .multiplyAdd d1 r1 r7 r3, True.intro⟩,
⟨13, l2, .multiplyAdd d2 r2 r3 r4, True.intro⟩,
⟨13, l3, .multiplyAdd d2 r2 r3 r4, True.intro⟩,
⟨13, l4, .multiplyAdd d4 r4 r2 r6, True.intro⟩,
⟨13, l5, .multiplyAdd d4 r4 r2 r6, True.intro⟩,
⟨13, l6, .load d11 a4, load4⟩,
⟨13, l7, .load d11 a4, load4⟩,
⟨14, l0, .load d3 a0, load0⟩,
⟨14, l1, .load d3 a0, load0⟩,
⟨14, l2, .load d4 a1, load1⟩,
⟨14, l3, .load d4 a1, load1⟩,
⟨14, l4, .multiplyAdd d6 r10 r2 r8, True.intro⟩,
⟨14, l5, .multiplyAdd d6 r10 r2 r8, True.intro⟩,
⟨14, l6, .multiplyAdd d1 r1 r6 r8, True.intro⟩,
⟨14, l7, .multiplyAdd d1 r1 r6 r8, True.intro⟩,
⟨15, l0, .multiplyAdd d6 r6 r5 r8, True.intro⟩,
⟨15, l1, .multiplyAdd d6 r6 r5 r8, True.intro⟩,
⟨15, l2, .multiplyAdd d11 r4 r1 r10, True.intro⟩,
⟨15, l3, .multiplyAdd d11 r4 r1 r10, True.intro⟩,
⟨15, l4, .multiplyAdd d9 r9 r1 r3, True.intro⟩,
⟨15, l5, .multiplyAdd d9 r9 r1 r3, True.intro⟩,
⟨15, l6, .load d8 a0, load0⟩,
⟨15, l7, .load d8 a0, load0⟩,
⟨16, l0, .multiplyAdd d1 r1 r7 r8, True.intro⟩,
⟨16, l1, .multiplyAdd d1 r1 r7 r8, True.intro⟩,
⟨16, l2, .multiplyAdd d2 r2 r3 r7, True.intro⟩,
⟨16, l3, .multiplyAdd d2 r2 r3 r7, True.intro⟩,
⟨16, l4, .multiplyAdd d3 r4 r2 r3, True.intro⟩,
⟨16, l5, .multiplyAdd d3 r4 r2 r3, True.intro⟩,
⟨16, l6, .multiplyAdd d5 r5 r4 r11, True.intro⟩,
⟨16, l7, .multiplyAdd d5 r5 r4 r11, True.intro⟩,
⟨17, l0, .multiply d8 r5 r5, True.intro⟩,
⟨17, l1, .multiply d8 r5 r5, True.intro⟩,
⟨17, l2, .multiplyAdd d6 r6 r1 r7, True.intro⟩,
⟨17, l3, .multiplyAdd d6 r6 r1 r7, True.intro⟩,
⟨17, l4, .multiply d4 r1 r1, True.intro⟩,
⟨17, l5, .multiply d4 r1 r1, True.intro⟩,
⟨17, l6, .multiplyAdd d1 r1 r6 r11, True.intro⟩,
⟨17, l7, .multiplyAdd d1 r1 r6 r11, True.intro⟩,
⟨18, l0, .multiplyAdd d6 r6 r5 r4, True.intro⟩,
⟨18, l1, .multiplyAdd d6 r6 r5 r4, True.intro⟩,
⟨18, l2, .multiplyAdd d4 r4 r3 r10, True.intro⟩,
⟨18, l3, .multiplyAdd d4 r4 r3 r10, True.intro⟩,
⟨18, l4, .multiplyAdd d9 r9 r1 r7, True.intro⟩,
⟨18, l5, .multiplyAdd d9 r9 r1 r7, True.intro⟩,
⟨18, l6, .multiplyAdd d11 r3 r4 r8, True.intro⟩,
⟨18, l7, .multiplyAdd d11 r3 r4 r8, True.intro⟩,
⟨19, l0, .multiplyAdd d1 r1 r7 r4, True.intro⟩,
⟨19, l1, .multiplyAdd d1 r1 r7 r4, True.intro⟩,
⟨19, l2, .multiplyAdd d2 r2 r3 r8, True.intro⟩,
⟨19, l3, .multiplyAdd d2 r2 r3 r8, True.intro⟩,
⟨19, l4, .multiplyAdd d3 r3 r2 r7, True.intro⟩,
⟨19, l5, .multiplyAdd d3 r3 r2 r7, True.intro⟩,
⟨19, l6, .multiplyAdd d5 r5 r4 r2, True.intro⟩,
⟨19, l7, .multiplyAdd d5 r5 r4 r2, True.intro⟩,
⟨20, l0, .multiplyAdd d4 r2 r7 r3, True.intro⟩,
⟨20, l1, .multiplyAdd d4 r2 r7 r3, True.intro⟩,
⟨20, l2, .multiplyAdd d6 r6 r1 r8, True.intro⟩,
⟨20, l3, .multiplyAdd d6 r6 r1 r8, True.intro⟩,
⟨20, l4, .multiplyAdd d7 r10 r1 r8, True.intro⟩,
⟨20, l5, .multiplyAdd d7 r10 r1 r8, True.intro⟩,
⟨20, l6, .multiplyAdd d1 r1 r6 r2, True.intro⟩,
⟨20, l7, .multiplyAdd d1 r1 r6 r2, True.intro⟩,
⟨21, l0, .multiplyAdd d6 r6 r5 r10, True.intro⟩,
⟨21, l1, .multiplyAdd d6 r6 r5 r10, True.intro⟩,
⟨21, l2, .multiply d7 r1 r1, True.intro⟩,
⟨21, l3, .multiply d7 r1 r1, True.intro⟩,
⟨21, l4, .multiplyAdd d1 r9 r1 r5, True.intro⟩,
⟨21, l5, .multiplyAdd d1 r9 r1 r5, True.intro⟩,
⟨21, l6, .multiplyAdd d2 r3 r6 r8, True.intro⟩,
⟨21, l7, .multiplyAdd d2 r3 r6 r8, True.intro⟩,
⟨22, l0, .multiplyAdd d1 r1 r7 r10, True.intro⟩,
⟨22, l1, .multiplyAdd d1 r1 r7 r10, True.intro⟩,
⟨22, l2, .multiplyAdd d2 r2 r3 r5, True.intro⟩,
⟨22, l3, .multiplyAdd d2 r2 r3 r5, True.intro⟩,
⟨22, l4, .multiplyAdd d3 r3 r2 r5, True.intro⟩,
⟨22, l5, .multiplyAdd d3 r3 r2 r5, True.intro⟩,
⟨22, l6, .multiplyAdd d3 r5 r4 r10, True.intro⟩,
⟨22, l7, .multiplyAdd d3 r5 r4 r10, True.intro⟩,
⟨23, l0, .multiplyAdd d2 r2 r5 r3, True.intro⟩,
⟨23, l1, .multiplyAdd d2 r2 r5 r3, True.intro⟩,
⟨23, l2, .multiplyAdd d1 r6 r1 r5, True.intro⟩,
⟨23, l3, .multiplyAdd d1 r6 r1 r5, True.intro⟩,
⟨23, l4, .multiply d2 r2 r2, True.intro⟩,
⟨23, l5, .multiply d2 r2 r2, True.intro⟩,
⟨23, l6, .multiplyAdd d1 r1 r6 r10, True.intro⟩,
⟨23, l7, .multiplyAdd d1 r1 r6 r10, True.intro⟩,
⟨24, l4, .multiplyAdd d1 r1 r4 r7, True.intro⟩,
⟨24, l5, .multiplyAdd d1 r1 r4 r7, True.intro⟩,
⟨25, l0, .multiplyAdd d1 r1 r9 r4, True.intro⟩,
⟨25, l1, .multiplyAdd d1 r1 r9 r4, True.intro⟩,
⟨25, l2, .multiplyAdd d2 r2 r9 r4, True.intro⟩,
⟨25, l3, .multiplyAdd d2 r2 r9 r4, True.intro⟩,
⟨25, l6, .multiplyAdd d3 r3 r7 r11, True.intro⟩,
⟨25, l7, .multiplyAdd d3 r3 r7 r11, True.intro⟩,
⟨26, l0, .multiplyAdd d2 r6 r8 r2, True.intro⟩,
⟨26, l1, .multiplyAdd d2 r6 r8 r2, True.intro⟩,
⟨26, l2, .multiplyAdd d1 r1 r7 r11, True.intro⟩,
⟨26, l3, .multiplyAdd d1 r1 r7 r11, True.intro⟩,
⟨26, l4, .multiplyAdd d2 r3 r2 r6, True.intro⟩,
⟨26, l5, .multiplyAdd d2 r3 r2 r6, True.intro⟩,
⟨26, l6, .multiplyAdd d1 r1 r9 r2, True.intro⟩,
⟨26, l7, .multiplyAdd d1 r1 r9 r2, True.intro⟩,
⟨28, l0, .store r1 a24, store24⟩,
⟨28, l1, .store r1 a25, store25⟩,
⟨28, l2, .store r2 a10, store10⟩,
⟨28, l3, .store r2 a11, store11⟩,
⟨28, l4, .store r1 a12, store12⟩,
⟨28, l5, .store r1 a13, store13⟩,
⟨28, l6, .store r3 a14, store14⟩,
⟨28, l7, .store r3 a15, store15⟩,
⟨29, l0, .store r2 a32, store32⟩,
⟨29, l1, .store r2 a33, store33⟩,
⟨29, l2, .store r1 a18, store18⟩,
⟨29, l3, .store r1 a19, store19⟩,
⟨29, l4, .store r2 a20, store20⟩,
⟨29, l5, .store r2 a21, store21⟩,
⟨29, l6, .store r1 a22, store22⟩,
⟨29, l7, .store r1 a23, store23⟩]
}

theorem checked : (check entry.problem candidate 32 4096).toOption = some 30 := by decide +kernel

def artifact := entry.artifact candidate 32 4096 30 checked

theorem exactBinding : artifact.verified.candidate.toRaw = raw := by decide +kernel

#print axioms checked
#print axioms artifact
#print axioms exactBinding
end Certificate_c70881073b615e01e73756cc4e8b21d4f727634f2f1b90be2b6d0e0771e96c5c

#eval OptimalComputation.Certification.printScore Certificate_c70881073b615e01e73756cc4e8b21d4f727634f2f1b90be2b6d0e0771e96c5c.artifact "latency-v1" "generated-23"
