///|
fn finding(
  out : Array[Finding],
  code : String,
  id : String,
  message : String,
  other~ : String = "",
) -> Unit {
  out.push({ code, buffer: id, other, message, })
}

///|
/// Does not invoke the planner or trust a layout's size/lifetime metadata.
pub fn verify(
  problem : Problem,
  layout : Layout,
) -> Array[Finding] raise PlanError {
  validate(problem)
  if layout.placements.length() > 4096 {
    reject("LayoutLimit", "maximum 4096 placement records")
  }
  let out : Array[Finding] = []
  if layout.schema != 1 {
    finding(out, "Schema", "", "layout schema must be 1")
  }
  let buffers : Map[String, Buffer] = Map([])
  let capacities : Map[String, Int64] = Map([])
  for buffer in problem.buffers {
    buffers[buffer.id] = buffer
  }
  for bank in problem.banks {
    capacities[bank.id] = bank.capacity
  }
  let seen : Map[String, Bool] = Map([])
  let safe : Array[(Buffer, Placement)] = []
  for p in layout.placements {
    if seen.contains(p.id) {
      finding(out, "DuplicatePlacement", p.id, "buffer placed more than once")
      continue
    }
    seen[p.id] = true
    let buffer = match buffers.get(p.id) {
      Some(b) => b
      None => {
        finding(out, "UnknownBuffer", p.id, "placement has no source buffer")
        continue
      }
    }
    if !buffer.banks.contains(p.bank) || !capacities.contains(p.bank) {
      finding(out, "BankNotAllowed", p.id, "placement bank is not permitted")
      continue
    }
    if p.offset < 0L || p.offset > max_bytes - buffer.bytes {
      finding(out, "AddressRange", p.id, "offset outside address bounds")
      continue
    }
    if p.offset % buffer.alignment != 0L {
      finding(out, "Misaligned", p.id, "offset violates alignment")
    }
    if buffer.fixed_bank is Some(bank) &&
      (bank != p.bank || buffer.fixed_offset != Some(p.offset)) {
      finding(out, "FixedOffsetChanged", p.id, "fixed placement changed")
    }
    if p.offset + buffer.bytes > capacities[p.bank] {
      finding(out, "CapacityExceeded", p.id, "placement exceeds bank capacity")
    }
    safe.push((buffer, p))
  }
  for buffer in problem.buffers {
    if !seen.contains(buffer.id) {
      finding(out, "MissingPlacement", buffer.id, "source buffer not placed")
    }
  }
  for i in 0..<safe.length() {
    let (a, pa) = safe[i]
    for j in (i + 1)..<safe.length() {
      let (b, pb) = safe[j]
      // Written from the source intervals, independently of the greedy planner.
      let simultaneous = !(a.last < b.first || b.last < a.first)
      let overlap = pa.offset < pb.offset + b.bytes &&
        pb.offset < pa.offset + a.bytes
      if pa.bank == pb.bank && simultaneous && overlap {
        finding(
          out,
          "LiveOverlap",
          a.id,
          "simultaneously live buffers overlap",
          other=b.id,
        )
      }
    }
  }
  out
}

///|
/// Summary is defined for structurally valid layouts, including over-budget plans.
pub fn summarize(
  problem : Problem,
  layout : Layout,
) -> Array[BankUsage] raise PlanError {
  let findings = verify(problem, layout)
  if findings.any(f => f.code != "CapacityExceeded") {
    reject("InvalidLayout", "summary requires a structurally valid layout")
  }
  let by_id : Map[String, Buffer] = Map([])
  for buffer in problem.buffers {
    by_id[buffer.id] = buffer
  }
  let result : Array[BankUsage] = []
  for bank in problem.banks {
    let events : Array[(Int32, Int64)] = []
    let mut highwater = 0L
    for p in layout.placements {
      if p.bank != bank.id {
        continue
      }
      let b = by_id[p.id]
      let end = p.offset + b.bytes
      if end > highwater {
        highwater = end
      }
      events.push((b.first, b.bytes))
      events.push((b.last + 1, -b.bytes))
    }
    events.sort()
    let mut current = 0L
    let mut peak = 0L
    let mut step = 0
    let mut i = 0
    while i < events.length() {
      let time = events[i].0
      while i < events.length() && events[i].0 == time {
        current += events[i].1
        i += 1
      }
      if current > peak {
        peak = current
        step = time
      }
    }
    result.push({
      bank: bank.id,
      capacity: bank.capacity,
      highwater,
      peak_live_bytes: peak,
      peak_step: step,
      fits: highwater <= bank.capacity,
    })
  }
  result.sort_by((a, b) => a.bank.compare(b.bank))
  result
}

///|
/// C11 offset macros only. The caller owns correctly aligned bank storage.
pub fn c_header(problem : Problem, layout : Layout) -> String raise PlanError {
  if !verify(problem, layout).is_empty() {
    reject("InvalidLayout", "C export requires a verified in-budget layout")
  }
  let out = StringBuilder()
  out.write_string(
    "#ifndef MOON_ARENA_PLAN_H\n#define MOON_ARENA_PLAN_H\n#include <stdint.h>\n",
  )
  let by_id : Map[String, Buffer] = Map([])
  for b in problem.buffers {
    by_id[b.id] = b
  }
  let ordered = layout.placements.copy()
  ordered.sort_by((a, b) => a.id.compare(b.id))
  for i, p in ordered {
    let b = by_id[p.id]
    out.write_string("/* " + p.id + " in " + p.bank + " */\n")
    out.write_string(
      "#define MP_BUFFER_" +
      i.to_string() +
      "_OFFSET UINT64_C(" +
      p.offset.to_string() +
      ")\n",
    )
    out.write_string(
      "#define MP_BUFFER_" +
      i.to_string() +
      "_BYTES UINT64_C(" +
      b.bytes.to_string() +
      ")\n",
    )
    out.write_string(
      "#define MP_BUFFER_" +
      i.to_string() +
      "_ALIGNMENT UINT64_C(" +
      b.alignment.to_string() +
      ")\n",
    )
  }
  out.write_string("#endif\n")
  out.to_string()
}
