import OptimalComputation.Candidates.Program
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson.Basic

/-! JSON transport for `RawCandidate`, so a candidate can be written outside
Lean. Decoding is strict: every field is required and unknown fields are
rejected, so no extra field (for example a claimed verification status) is ever
silently accepted. A decoded candidate is still unchecked data; `inspect` binds
it to a trusted workload shape, and nothing here confers verified status. -/

namespace OptimalComputation.Candidates
open Lean Hardware

/-- Operand names shared by candidate files and exported traces. -/
def instructionFields : RawInstruction → String × List (String × Nat)
  | .load destination address => ("load", [("destination", destination), ("address", address)])
  | .store source address => ("store", [("source", source), ("address", address)])
  | .add destination left right =>
      ("add", [("destination", destination), ("left", left), ("right", right)])
  | .multiply destination left right =>
      ("multiply", [("destination", destination), ("left", left), ("right", right)])
  | .multiplyAdd destination left right accumulator =>
      ("multiplyAdd", [("destination", destination), ("left", left), ("right", right),
        ("accumulator", accumulator)])

def instructionToJson (instruction : RawInstruction) : Json :=
  let (kind, operands) := instructionFields instruction
  Json.mkObj (("kind", Lean.toJson kind) :: operands.map fun (name, value) => (name, Lean.toJson value))

def RawCandidate.toJson (candidate : RawCandidate) : Json := Json.mkObj [
  ("identifier", Lean.toJson candidate.identifier),
  ("workloadIdentifier", Lean.toJson candidate.workloadIdentifier),
  ("modelVersion", Lean.toJson candidate.modelVersion),
  ("formatVersion", Lean.toJson candidate.formatVersion),
  ("configuration", Json.mkObj [("lanes", Lean.toJson candidate.configuration.lanes),
    ("banks", Lean.toJson candidate.configuration.banks)]),
  ("layout", Json.mkObj [("inputs", Lean.toJson candidate.layout.inputs),
    ("outputs", Lean.toJson candidate.layout.outputs), ("scratch", Lean.toJson candidate.layout.scratch)]),
  ("schedule", Json.arr (candidate.schedule.map fun entry => Json.mkObj [
    ("cycle", Lean.toJson entry.cycle), ("lane", Lean.toJson entry.lane),
    ("instruction", instructionToJson entry.instruction)]).toArray)]

/-- Quote file-supplied text for a plain-text message. Only printable ASCII is
kept and everything else is escaped, so the text cannot add lines or terminal
control sequences to the output. At most 64 characters are shown. -/
def quoteText (text : String) : String :=
  let escape := fun (c : Char) =>
    if c == '"' || c == '\\' then s!"\\{c}"
    else if 0x20 ≤ c.toNat && c.toNat < 0x7f then c.toString
    else "\\u{" ++ String.ofList (Nat.toDigits 16 c.toNat) ++ "}"
  let shown := text.toList.take 64
  "\"" ++ String.join (shown.map escape) ++ (if text.length > 64 then "..." else "") ++ "\""

namespace UniqueJson
open Std.Internal.Parsec Std.Internal.Parsec.String

-- Reuse Lean's scalar and string parsers. Only aggregate parsing differs:
-- keys are checked after escape decoding, before an object map can erase them.
mutual
  private partial def value : Parser Json := do
    let c ← peek!
    if c == '{' then
      skip; ws
      if (← peek!) == '}' then
        skip; ws
        return Json.obj ∅
      else
        object ∅
    else if c == '[' then
      skip; ws
      if (← peek!) == ']' then
        skip; ws
        return Json.arr #[]
      else
        array #[]
    else
      Json.Parser.anyCore

  private partial def object (fields : Std.TreeMap.Raw String Json) : Parser Json := do
    Json.Parser.lookahead (· == '"') "object key"; skip
    let key ← Json.Parser.str
    if fields.contains key then
      fail s!"duplicate object key {quoteText key}"
    ws
    Json.Parser.lookahead (· == ':') ":"; skip; ws
    let item ← value
    let fields := fields.insert key item
    match ← any with
    | '}' => ws; return Json.obj fields
    | ',' => ws; object fields
    | _ => fail "unexpected character in object"

  private partial def array (items : Array Json) : Parser Json := do
    let item ← value
    let items := items.push item
    match ← any with
    | ']' => ws; return Json.arr items
    | ',' => ws; array items
    | _ => fail "unexpected character in array"
end

/-- Strict JSON text transport: duplicate decoded keys fail at every depth.
Callers must apply their numeric and nesting limits before parsing untrusted text.
This parser supplies data only, never certification evidence. -/
def parse (contents : String) : Except String Json :=
  Parser.run (do ws; let result ← value; eof; return result) contents

end UniqueJson

/-- Require exactly the named keys, so typos and unexpected claims fail loudly. -/
private def exactFields (context : String) (json : Json) (names : List String) : Except String Unit := do
  let fields ← json.getObj?.mapError fun _ => s!"{context}: expected an object"
  for key in fields.keys do
    unless names.contains key do throw s!"{context}: unknown field {quoteText key}"
  for name in names do
    unless fields.contains name do throw s!"{context}: missing field \"{name}\""

private def field (context : String) (json : Json) (name : String) : Except String Json :=
  (json.getObjVal? name).mapError fun _ => s!"{context}: missing field \"{name}\""

private def natField (context : String) (json : Json) (name : String) : Except String Nat := do
  ((← field context json name).getNat?).mapError fun _ =>
    s!"{context}.{name}: expected a nonnegative integer"

private def stringField (context : String) (json : Json) (name : String) : Except String String := do
  ((← field context json name).getStr?).mapError fun _ => s!"{context}.{name}: expected a string"

private def natListField (context : String) (json : Json) (name : String) : Except String (List Nat) := do
  let values ← ((← field context json name).getArr?).mapError fun _ =>
    s!"{context}.{name}: expected an array"
  let values ← values.mapM fun value => value.getNat?.mapError fun _ =>
    s!"{context}.{name}: expected nonnegative integers"
  return values.toList

def instructionFromJson? (context : String) (json : Json) : Except String RawInstruction := do
  let kind ← stringField context json "kind"
  let operands := fun (names : List String) => exactFields context json ("kind" :: names)
  let nat := natField context json
  match kind with
  | "load" =>
      operands ["destination", "address"]
      return .load (← nat "destination") (← nat "address")
  | "store" =>
      operands ["source", "address"]
      return .store (← nat "source") (← nat "address")
  | "add" =>
      operands ["destination", "left", "right"]
      return .add (← nat "destination") (← nat "left") (← nat "right")
  | "multiply" =>
      operands ["destination", "left", "right"]
      return .multiply (← nat "destination") (← nat "left") (← nat "right")
  | "multiplyAdd" =>
      operands ["destination", "left", "right", "accumulator"]
      return .multiplyAdd (← nat "destination") (← nat "left") (← nat "right") (← nat "accumulator")
  | other => throw s!"{context}.kind: unknown instruction kind {quoteText other}"

/-- Decode the exact `RawCandidate` fields. Range, version and layout checks
remain the job of `validateCandidate`, which reports structured failures. -/
def RawCandidate.fromJson? (json : Json) : Except String RawCandidate := do
  exactFields "candidate" json ["identifier", "workloadIdentifier", "modelVersion",
    "formatVersion", "configuration", "layout", "schedule"]
  let configuration ← field "candidate" json "configuration"
  exactFields "configuration" configuration ["lanes", "banks"]
  let layout ← field "candidate" json "layout"
  exactFields "layout" layout ["inputs", "outputs", "scratch"]
  let entries ← ((← field "candidate" json "schedule").getArr?).mapError fun _ =>
    "candidate.schedule: expected an array"
  let mut schedule : Array RawScheduledInstruction := #[]
  for entry in entries do
    let context := s!"schedule[{schedule.size}]"
    exactFields context entry ["cycle", "lane", "instruction"]
    schedule := schedule.push {
      cycle := ← natField context entry "cycle"
      lane := ← natField context entry "lane"
      instruction := ← instructionFromJson? s!"{context}.instruction"
        (← field context entry "instruction")
    }
  return {
    identifier := ← stringField "candidate" json "identifier"
    workloadIdentifier := ← stringField "candidate" json "workloadIdentifier"
    modelVersion := ← stringField "candidate" json "modelVersion"
    formatVersion := ← stringField "candidate" json "formatVersion"
    configuration := ⟨← natField "configuration" configuration "lanes",
      ← natField "configuration" configuration "banks"⟩
    layout := ⟨← natListField "layout" layout "inputs", ← natListField "layout" layout "outputs",
      ← natListField "layout" layout "scratch"⟩
    schedule := schedule.toList
  }

end OptimalComputation.Candidates
