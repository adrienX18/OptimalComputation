import OptimalComputation.Hardware.Storage

namespace OptimalComputation.Tests

open Hardware

private def checkArithmetic (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw <| IO.userError s!"Arithmetic check failed: {label}"

private def expectResult (label : String) (actual : Except ArithmeticError Signed48)
    (expected : Except ArithmeticError Int) : IO Unit :=
  checkArithmetic label (match actual, expected with
    | .ok actual, .ok expected => actual.val == expected
    | .error actual, .error expected => actual == expected
    | _, _ => false)

def arithmetic : IO Unit := do
  for (x, expected) in [(-32769, false), (-32768, true), (-32767, true),
      (0, true), (32766, true), (32767, true), (32768, false)] do
    checkArithmetic s!"signed16 boundary {x}" (decide (InSigned16 x) == expected)
  for (x, expected) in [(-140737488355329, false), (-140737488355328, true),
      (-140737488355327, true), (0, true), (140737488355326, true),
      (140737488355327, true), (140737488355328, false)] do
    checkArithmetic s!"signed48 boundary {x}" (decide (InSigned48 x) == expected)
  expectResult "add at negative endpoint" (checkedAdd (-140737488355328) 0)
    (.ok (-140737488355328))
  expectResult "add at positive endpoint" (checkedAdd 140737488355326 1)
    (.ok 140737488355327)
  expectResult "add cancellation" (checkedAdd (-140737488355328) 140737488355327) (.ok (-1))
  expectResult "add positive overflow" (checkedAdd 140737488355327 1)
    (.error (.resultOutOfRange 140737488355328))
  expectResult "add negative overflow" (checkedAdd (-140737488355328) (-1))
    (.error (.resultOutOfRange (-140737488355329)))
  expectResult "add invalid left despite valid sum" (checkedAdd 140737488355328 (-1))
    (.error (.operandOutOfRange .left 48 140737488355328))
  expectResult "add invalid right despite valid sum" (checkedAdd 1 (-140737488355329))
    (.error (.operandOutOfRange .right 48 (-140737488355329)))
  expectResult "multiply two negative endpoints" (checkedMul (-32768) (-32768)) (.ok 1073741824)
  expectResult "multiply two positive endpoints" (checkedMul 32767 32767) (.ok 1073676289)
  expectResult "multiply mixed endpoints" (checkedMul (-32768) 32767) (.ok (-1073709056))
  expectResult "multiply invalid left by zero" (checkedMul 32768 0)
    (.error (.operandOutOfRange .left 16 32768))
  expectResult "multiply zero by invalid right" (checkedMul 0 (-32769))
    (.error (.operandOutOfRange .right 16 (-32769)))
  expectResult "MAC mixed signs" (checkedMac (-7) 9 100) (.ok 37)
  expectResult "MAC at positive endpoint" (checkedMac 1 1 140737488355326) (.ok 140737488355327)
  expectResult "MAC at negative endpoint" (checkedMac (-1) 1 (-140737488355327))
    (.ok (-140737488355328))
  expectResult "MAC positive overflow" (checkedMac 1 1 140737488355327)
    (.error (.resultOutOfRange 140737488355328))
  expectResult "MAC negative overflow" (checkedMac (-1) 1 (-140737488355328))
    (.error (.resultOutOfRange (-140737488355329)))
  expectResult "MAC invalid accumulator despite cancellation" (checkedMac (-1) 1 140737488355328)
    (.error (.operandOutOfRange .accumulator 48 140737488355328))
  expectResult "MAC invalid left by zero" (checkedMac (-32769) 0 0)
    (.error (.operandOutOfRange .left 16 (-32769)))
  expectResult "MAC zero by invalid right" (checkedMac 0 32768 0)
    (.error (.operandOutOfRange .right 16 32768))
  expectResult "left-to-right error precedence" (checkedMac 32768 (-32769) 140737488355328)
    (.error (.operandOutOfRange .left 16 32768))
  IO.println "PASS: arithmetic checks (14 range boundaries, 21 exact results and rejection cases)"

def storage : IO Unit := do
  -- Expected full-slot patterns are independent two's-complement hex values.
  let examples : List (Int × Nat) := [
    (0, 0x0000000000000000), (1, 0x0000000000000001),
    (-1, 0xffffffffffffffff), (-2, 0xfffffffffffffffe),
    (32767, 0x0000000000007fff), (-32768, 0xffffffffffff8000),
    (140737488355327, 0x00007fffffffffff), (-140737488355328, 0xffff800000000000)]
  for (value, expectedBits) in examples do
    if h : InSigned48 value then
      let slot := encodeSlot ⟨value, h⟩
      checkArithmetic s!"full 64-bit representation of {value}" (slot.val.toNat == expectedBits)
      checkArithmetic s!"decode {value}" ((decodeSlot slot).val == value)
      checkArithmetic s!"sign extension of {value}"
        ((slot.val.signExtend 48).signExtend 64 == slot.val)
      match validateSlot (BitVec.ofNat 64 expectedBits) with
      | .ok decoded => checkArithmetic "validate preserves bits" (decoded.val == slot.val)
      | .error _ => throw <| IO.userError s!"Rejected canonical slot for {value}"
    else throw <| IO.userError "Invalid test value"
  for bits in [0x0000800000000000, 0x0000ffffffffffff, 0xffff7fffffffffff,
      0x8000000000000000, 0x0001000000000000] do
    let raw := BitVec.ofNat 64 bits
    match validateSlot raw with
    | .ok _ => throw <| IO.userError s!"Accepted noncanonical bits {bits}"
    | .error error =>
        checkArithmetic "noncanonical rejection retains bits" (error == .noncanonicalSlot raw)
  IO.println "PASS: storage checks (8 canonical full-slot patterns, 5 noncanonical rejections)"

end OptimalComputation.Tests
