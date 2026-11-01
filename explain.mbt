///|
pub(all) struct PeakBuffer {
  id : String
  bytes : Int64
  offset : Int64
} derive(Eq, Debug, ToJson)

///|
pub(all) struct PeakExplanation {
  bank : String
  capacity : Int64
  highwater : Int64
  peak_live_bytes : Int64
  peak_step : Int32
  layout_over_budget_by : Int64
  live_over_budget_by : Int64
  highwater_minus_peak : Int64
  live_buffers : Array[PeakBuffer]
} derive(Eq, Debug, ToJson)

///|
/// Explain the earliest live-byte peak for each assigned bank.
/// Excess live bytes apply to this bank assignment, not every possible assignment.
pub fn explain(
  problem : Problem,
  layout : Layout,
) -> Array[PeakExplanation] raise PlanError {
  let summaries = summarize(problem, layout)
  let by_id : Map[String, Buffer] = Map([])
  for b in problem.buffers {
    by_id[b.id] = b
  }
  summaries.map(fn(usage) {
    let live_buffers : Array[PeakBuffer] = []
    for p in layout.placements {
      let b = by_id[p.id]
      if p.bank == usage.bank &&
        b.first <= usage.peak_step &&
        usage.peak_step <= b.last {
        live_buffers.push({ id: b.id, bytes: b.bytes, offset: p.offset, })
      }
    }
    live_buffers.sort_by(fn(a, b) {
      if a.bytes != b.bytes {
        b.bytes.compare(a.bytes)
      } else {
        id_compare(a.id, b.id)
      }
    })
    {
      bank: usage.bank,
      capacity: usage.capacity,
      highwater: usage.highwater,
      peak_live_bytes: usage.peak_live_bytes,
      peak_step: usage.peak_step,
      layout_over_budget_by: if usage.highwater > usage.capacity {
        usage.highwater - usage.capacity
      } else {
        0L
      },
      live_over_budget_by: if usage.peak_live_bytes > usage.capacity {
        usage.peak_live_bytes - usage.capacity
      } else {
        0L
      },
      highwater_minus_peak: usage.highwater - usage.peak_live_bytes,
      live_buffers,
    }
  })
}

///|
pub extend PeakBuffer with Eq::{equal, not_equal}

///|
pub extend PeakBuffer with @debug.Debug::{to_repr}

///|
pub extend PeakBuffer with ToJson::{to_json}

///|
pub extend PeakExplanation with Eq::{equal, not_equal}

///|
pub extend PeakExplanation with @debug.Debug::{to_repr}

///|
pub extend PeakExplanation with ToJson::{to_json}
