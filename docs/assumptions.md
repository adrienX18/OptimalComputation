# Hardware facts and assumptions

All first-release rules come from [PLAN.md](../PLAN.md). The
[machine contract](machine-contract.md) summarizes their semantics. This table
labels each group as **manufacturer fact**, **project modeling choice**, or
**deferred physical detail**; choices are not claims measured from the board.

## Manufacturer facts

| Item | Classification | Fact and source |
| --- | --- | --- |
| Reference board/chip | Manufacturer fact | Digilent Arty A7-100T, Artix-7 XC7A100TCSG324-1 (vendor ordering form XC7A100T-1CSG324C); [Digilent specifications](https://digilent.com/shop/system-boards/). |
| Physical resources | Manufacturer fact | 240 DSP slices, 4,860 Kibits nominal block RAM, 256 MB external DDR3; [Digilent specifications](https://digilent.com/shop/system-boards/). The RAM total is 607.5 KiB by unit conversion; usable allocation depends on port/width/depth mode. |
| Logic resources | Manufacturer fact | XC7A100T has 63,400 LUTs and 126,800 flip-flops; [UG474, Artix-7 resource table](https://docs.amd.com/r/en-US/ug474_7Series_CLB/7-Series-FPGA-CLB-Resources), v1.9. These build circuitry, not a fixed processor instruction set. |
| DSP primitive | Manufacturer fact | DSP48E1 supports 25-by-18-bit signed multiplication and 48-bit arithmetic, with configurable pipeline registers; [UG479](https://docs.amd.com/api/khub/documents/gu4oRPFEh_Pm2uaAlfY6Kg/content), v1.10, Chapters 1–2. |
| BRAM primitive | Manufacturer fact | A 36-Kibit block supports up to 1,024 words at 36 bits in true dual-port mode; 512-by-72 mode is simple dual-port (one read and one write port). A 64-bit memory with two general-purpose ports needs multiple blocks; [UG473](https://docs.amd.com/api/khub/documents/9gZGbqBxtlKXxBfkBt~lAg/content), v1.14, Chapter 1. |

## Project modeling choices

| Rule group | Classification | Fixed first-release choice |
| --- | --- | --- |
| Family and default | Project modeling choice | Independent `L, B ∈ {1, 2, 4, 8}`; default `(8, 8)`; fixed during execution. Model admissibility only. |
| Local memory | Project modeling choice | 4,096 64-bit slots; bank `a mod B`, row `a / B`; `4096 / B` slots and two general-purpose ports per bank. |
| Resources | Project modeling choice | One DSP/lane; BRAM36 allocation `B * 2 * ceil((4096 / B) / 1024)` using paired blocks. Counts are 8, 8, 8, 16 for 1, 2, 4, 8 banks. |
| Registers | Project modeling choice | Per lane: zero `r0`, 15 writable signed 48-bit registers, three operand reads and one result write per cycle. Architectural bits: `L * 15 * 48`. |
| Connections | Project modeling choice | Any lane can request any bank subject to ports; lane-to-lane transfers require stores/loads. |
| Issue and capacity | Project modeling choice | One instruction/lane/cycle; at most three pending instructions/lane with payload/metadata and one completion each. |
| Numbers | Project modeling choice | Exact integer references; signed 16-bit inputs/multiplicands; signed 48-bit addition/accumulation/results; overflow invalid. No wrap, saturation, rounding, or floating point. |
| Memory representation | Project modeling choice | Canonical sign-extended 64-bit slots holding signed 48-bit values; full-slot transfers; no packing. |
| Layout and initialization | Project modeling choice | Bounded, injective, disjoint input/output/scratch mappings; read-only inputs; initially only inputs and `r0` readable. |
| Candidate instructions | Project modeling choice | Finite schedule of explicit load/store/add/multiply/multiply-add; explicit time/lane/operands/addresses/waits. No branches, implicit loops, allocation, hidden state/work, or data-dependent scheduling. |
| Timing | Project modeling choice | Commit before issue at each boundary; memory latency 1, arithmetic latency 3; sample operands at issue, including ready old destination values. |
| Register hazards | Project modeling choice | Pending destinations cannot be read or written; reserve one result arrival/lane/boundary. |
| Memory contention | Project modeling choice | Every load/store is one bank access; at most two per bank/cycle; same-address simultaneous accesses only if both read. |
| Conflict behavior | Project modeling choice | Reject violations and uninitialized reads; no implicit stalls or schedule repair; simultaneous representation order cannot affect execution. |
| Completion | Project modeling choice | Process all instructions, commit all effects, write every output; include final store completion in elapsed cycles. |
| Proof obligations | Project modeling choice | Structural checks, all-input execution safety/termination/widths, and all-input reference equivalence; shared executable transitions; exact proof bindings; audit axioms, no unfinished or candidate-specific assumed proofs. |
| Failure reporting | Project modeling choice | Structured categories and relevant execution location; resource exhaustion is inconclusive; unverified/invalid results get no accepted score. |
| Execution record | Project modeling choice | Objective-free outputs, timing, event-derived activity/counters, resources, declared storage, schedule size. |
| Objectives | Project modeling choice | Separate minimization of cycles and abstract energy; pure rescoring; no weighted combination. |
| Energy coefficients | Project modeling choice | Base/lane/BRAM per cycle and register read/write/add cost 1; load/store 4; multiply 8; multiply-add 9 as a single event. Charge `r0` reads; fixed `energy-coefficients-v1`. |
| Workloads | Project modeling choice | Runtime dense signed 16-bit 16-by-16 matvec and matmul; exact 16-term dot products with proved 48-bit bounds; no fixed weights or reuse between invocations. |
| Baselines | Project modeling choice | Required verified executable naive row-major, lane-zero baseline per workload; matvec rows/columns, matmul `i,j,k`; explicit transfers/waits; no tiling/packing/parallel scheduling/cross-dot-product reuse. |
| Versions and extension | Project modeling choice | Stable model/candidate/workload/objective/coefficient versions and baseline results; incompatible semantics get a new version and reruns. Workloads/objectives never redefine machine legality; search remains future work. |

## Deferred physical details

| Item | Classification | Boundary |
| --- | --- | --- |
| External movement | Deferred physical detail | Inputs already reside locally; host, initialization, and DDR3 traffic excluded. |
| Controller | Deferred physical detail | Abstract schedule issue; instruction storage/fetch and physical controller excluded; record schedule size. |
| Physical area | Deferred physical detail | Full LUT/flip-flop, routing, control, interconnect, and pipeline implementation costs uncalibrated; distinguish architectural register bits and pending state; never substitute zero. |
| Physical performance | Deferred physical detail | Routing delay, placement/routing, timing closure, frequency, and power calibration deferred. Three arithmetic cycles is a model rule, not a universal DSP timing claim. |
| Energy meaning | Deferred physical detail | Hypothetical coefficients, abstract units; no claim of measured or calibrated joules/watt-hours. |
