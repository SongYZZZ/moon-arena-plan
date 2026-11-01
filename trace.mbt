///|
pub(all) struct TrackedBuffer {
  id : String
  bytes : Int64
  alignment : Int64
  banks : Array[String]
  fixed_bank : String?
  fixed_offset : Int64?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct TraceEvent {
  step : Int32
  op : String
  buffer : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct ExecutionTrace {
  schema : Int32
  banks : Array[Bank]
  buffers : Array[TrackedBuffer]
  events : Array[TraceEvent]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Import a complete logical last-use trace. Only recorded accesses are checked.
/// Every ID describes one begin/end lifetime; steps are nondecreasing and inclusive.
pub fn trace_lifetimes(trace : ExecutionTrace) -> Problem raise PlanError {
  if trace.schema != 1 ||
    trace.buffers.length() > 2048 ||
    trace.events.length() > 65536 {
    reject(
      "TraceLimit", "trace schema 1 supports at most 2048 buffers and 65536 events",
    )
  }
  let templates = trace.buffers.map(b => {
    (
      {
        id: b.id,
        bytes: b.bytes,
        alignment: b.alignment,
        banks: b.banks,
        fixed_bank: b.fixed_bank,
        fixed_offset: b.fixed_offset,
        first: 0,
        last: 0,
      } : Buffer)
  })
  let model : Problem = { schema: 1, banks: trace.banks, buffers: templates, }
  validate(model)
  let known : Map[String, Bool] = Map([])
  let first : Map[String, Int32] = Map([])
  let last : Map[String, Int32] = Map([])
  let active : Map[String, Bool] = Map([])
  for b in templates {
    known[b.id] = true
  }
  let mut prior_step = -1
  for event in trace.events {
    if event.step < 0 || event.step > 1000000 {
      reject("TraceTime", "trace step outside 0..1000000")
    }
    if event.step < prior_step {
      reject("TraceOrder", "trace steps must be nondecreasing")
    }
    prior_step = event.step
    if !known.contains(event.buffer) {
      reject(
        "TraceBuffer",
        "event references undeclared buffer: " + event.buffer,
      )
    }
    match event.op {
      "begin" => {
        if first.contains(event.buffer) {
          reject(
            "TraceLifecycle",
            "ID must describe a single lifetime: " + event.buffer,
          )
        }
        first[event.buffer] = event.step
        active[event.buffer] = true
      }
      "read" | "write" =>
        if !active.contains(event.buffer) {
          reject(
            "TraceLifecycle",
            "access outside active lifetime: " + event.buffer,
          )
        }
      "end" => {
        if !active.contains(event.buffer) {
          reject(
            "TraceLifecycle",
            "end without active lifetime: " + event.buffer,
          )
        }
        last[event.buffer] = event.step
        ignore(active.remove(event.buffer))
      }
      _ =>
        reject(
          "TraceOperation", "supported operations are begin/read/write/end",
        )
    }
  }
  let buffers : Array[Buffer] = []
  for b in templates {
    let start = match first.get(b.id) {
      Some(step) => step
      None => {
        reject("TraceCoverage", "declared buffer never began: " + b.id)
        0
      }
    }
    let end = match last.get(b.id) {
      Some(step) => step
      None => {
        reject("TraceIncomplete", "lifetime has no closing end: " + b.id)
        0
      }
    }
    buffers.push({ ..b, first: start, last: end, })
  }
  { ..model, buffers, }
}

///|
pub extend TrackedBuffer with Eq::{equal, not_equal}

///|
pub extend TrackedBuffer with @debug.Debug::{to_repr}

///|
pub extend TrackedBuffer with ToJson::{to_json}

///|
pub extend TrackedBuffer with @json.FromJson::{from_json}

///|
pub extend TraceEvent with Eq::{equal, not_equal}

///|
pub extend TraceEvent with @debug.Debug::{to_repr}

///|
pub extend TraceEvent with ToJson::{to_json}

///|
pub extend TraceEvent with @json.FromJson::{from_json}

///|
pub extend ExecutionTrace with Eq::{equal, not_equal}

///|
pub extend ExecutionTrace with @debug.Debug::{to_repr}

///|
pub extend ExecutionTrace with ToJson::{to_json}

///|
pub extend ExecutionTrace with @json.FromJson::{from_json}
