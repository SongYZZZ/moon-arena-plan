///|
/// Deterministic greedy planning. An over-budget result is not an infeasibility proof.
pub fn plan(problem : Problem) -> Layout raise PlanError {
  validate(problem)
  let ordered = problem.buffers.copy()
  ordered.sort_by(fn(a, b) {
    let af = if a.fixed_offset is Some(_) { 0 } else { 1 }
    let bf = if b.fixed_offset is Some(_) { 0 } else { 1 }
    if af != bf {
      af.compare(bf)
    } else if a.banks.length() != b.banks.length() {
      a.banks.length().compare(b.banks.length())
    } else if a.bytes != b.bytes {
      b.bytes.compare(a.bytes)
    } else {
      id_compare(a.id, b.id)
    }
  })
  let capacities : Map[String, Int64] = Map([])
  let high : Map[String, Int64] = Map([])
  for bank in problem.banks {
    capacities[bank.id] = bank.capacity
    high[bank.id] = 0L
  }
  let placed : Array[(Buffer, Placement)] = []
  for buffer in ordered {
    let placement = match (buffer.fixed_bank, buffer.fixed_offset) {
      (Some(bank), Some(offset)) => {
        for (prior, slot) in placed {
          if bank == slot.bank &&
            live(buffer, prior) &&
            offset < slot.offset + prior.bytes &&
            slot.offset < offset + buffer.bytes {
            reject(
              "FixedConflict",
              "fixed buffers overlap: " + buffer.id + " / " + prior.id,
            )
          }
        }
        { id: buffer.id, bank, offset, }
      }
      _ => {
        let mut best : (Placement, Int64, Int64)? = None
        for bank in buffer.banks {
          let busy : Array[(Int64, Int64)] = []
          for (prior, slot) in placed {
            if slot.bank == bank && live(buffer, prior) {
              busy.push((slot.offset, slot.offset + prior.bytes))
            }
          }
          busy.sort()
          let mut offset = 0L
          for (start, end) in busy {
            if offset + buffer.bytes <= start {
              break
            }
            if offset < end {
              offset = aligned(end, buffer.alignment)
            }
          }
          if offset > max_bytes - buffer.bytes {
            continue
          }
          let end = offset + buffer.bytes
          let top = if end > high[bank] { end } else { high[bank] }
          let overflow = if top > capacities[bank] {
            top - capacities[bank]
          } else {
            0L
          }
          let growth = top - high[bank]
          if best is None ||
            (
              best is Some((_, prev_overflow, prev_growth)) &&
              (
                overflow < prev_overflow ||
                (overflow == prev_overflow && growth < prev_growth)
              )
            ) {
            best = Some(({ id: buffer.id, bank, offset, }, overflow, growth))
          }
        }
        match best {
          Some((placement, _, _)) => placement
          None => {
            reject(
              "AddressLimit",
              "no representable placement for " + buffer.id,
            )
            { id: buffer.id, bank: "", offset: 0L, }
          }
        }
      }
    }
    let end = placement.offset + buffer.bytes
    if end > high[placement.bank] {
      high[placement.bank] = end
    }
    placed.push((buffer, placement))
  }
  let placements = placed.map(pair => pair.1)
  placements.sort_by((a, b) => id_compare(a.id, b.id))
  { schema: 1, placements, }
}
