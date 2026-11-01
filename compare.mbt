///|
pub(all) struct BankDelta {
  bank : String
  change : String
  before_capacity : Int64?
  after_capacity : Int64?
  before_highwater : Int64
  after_highwater : Int64
  highwater_delta : Int64
  before_peak_live_bytes : Int64
  after_peak_live_bytes : Int64
  peak_live_delta : Int64
  growth_exceeded : Bool
  candidate_over_budget : Bool
} derive(Eq, Debug, ToJson)

///|
pub(all) struct Comparison {
  allowed_growth_bytes : Int64
  baseline_valid : Bool
  candidate_valid : Bool
  gate_passed : Bool
  banks : Array[BankDelta]
} derive(Eq, Debug, ToJson)

///|
/// Compare verified source/layout pairs. Growth is evaluated per bank for both
/// highwater and live-byte peak; a candidate capacity violation always fails.
pub fn compare_layouts(
  before : Problem,
  before_layout : Layout,
  after : Problem,
  after_layout : Layout,
  max_growth_bytes~ : Int64 = 0L,
) -> Comparison raise PlanError {
  if max_growth_bytes < 0L || max_growth_bytes > max_bytes {
    reject("GrowthLimit", "allowed growth must be 0..2^50 bytes")
  }
  let baseline = summarize(before, before_layout)
  let candidate = summarize(after, after_layout)
  let old : Map[String, BankUsage] = Map([])
  let next : Map[String, BankUsage] = Map([])
  let ids : Map[String, Bool] = Map([])
  for u in baseline {
    old[u.bank] = u
    ids[u.bank] = true
  }
  for u in candidate {
    next[u.bank] = u
    ids[u.bank] = true
  }
  let names = ids.keys().collect()
  names.sort_by(id_compare)
  let banks : Array[BankDelta] = []
  for bank in names {
    let prev = old.get(bank)
    let now = next.get(bank)
    let before_highwater = prev.map(u => u.highwater).unwrap_or(0L)
    let after_highwater = now.map(u => u.highwater).unwrap_or(0L)
    let before_peak_live_bytes = prev.map(u => u.peak_live_bytes).unwrap_or(0L)
    let after_peak_live_bytes = now.map(u => u.peak_live_bytes).unwrap_or(0L)
    let highwater_delta = after_highwater - before_highwater
    let peak_live_delta = after_peak_live_bytes - before_peak_live_bytes
    banks.push({
      bank,
      change: if prev is None {
        "added"
      } else if now is None {
        "removed"
      } else {
        "retained"
      },
      before_capacity: prev.map(u => u.capacity),
      after_capacity: now.map(u => u.capacity),
      before_highwater,
      after_highwater,
      highwater_delta,
      before_peak_live_bytes,
      after_peak_live_bytes,
      peak_live_delta,
      growth_exceeded: highwater_delta > max_growth_bytes ||
      peak_live_delta > max_growth_bytes,
      candidate_over_budget: now.map(u => !u.fits).unwrap_or(false),
    })
  }
  let baseline_valid = !baseline.any(u => !u.fits)
  let candidate_valid = !candidate.any(u => !u.fits)
  {
    allowed_growth_bytes: max_growth_bytes,
    baseline_valid,
    candidate_valid,
    gate_passed: candidate_valid && !banks.any(b => b.growth_exceeded),
    banks,
  }
}

///|
pub extend BankDelta with Eq::{equal, not_equal}

///|
pub extend BankDelta with @debug.Debug::{to_repr}

///|
pub extend BankDelta with ToJson::{to_json}

///|
pub extend Comparison with Eq::{equal, not_equal}

///|
pub extend Comparison with @debug.Debug::{to_repr}

///|
pub extend Comparison with ToJson::{to_json}
