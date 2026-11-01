///|
/// A bounded feasibility search, not a minimum-footprint optimizer.
pub(all) struct ExactResult {
  status : String
  layout : Layout?
  nodes : Int32
  budget : Int32
} derive(Eq, Debug, ToJson)

///|
priv struct ExactSearch {
  ordered : Array[Buffer]
  capacities : Map[String, Int64]
  placed : Array[(Buffer, Placement)]
  budget : Int32
  mut nodes : Int32
  mut limited : Bool
}

///|
fn ExactSearch::visit(self : ExactSearch, depth : Int32) -> Bool {
  if depth == self.ordered.length() {
    return true
  }
  let buffer = self.ordered[depth]
  let banks = match buffer.fixed_bank {
    Some(bank) => [bank]
    None => buffer.banks
  }
  for bank in banks {
    let last_offset = self.capacities[bank] - buffer.bytes
    let mut offset = buffer.fixed_offset.unwrap_or(0L)
    while offset <= last_offset {
      if self.nodes >= self.budget {
        self.limited = true
        return false
      }
      self.nodes += 1
      let mut fits = true
      for (prior, slot) in self.placed {
        if bank == slot.bank &&
          live(buffer, prior) &&
          offset < slot.offset + prior.bytes &&
          slot.offset < offset + buffer.bytes {
          fits = false
          break
        }
      }
      if fits {
        self.placed.push((buffer, { id: buffer.id, bank, offset, }))
        if self.visit(depth + 1) {
          return true
        }
        ignore(self.placed.pop())
        if self.limited {
          return false
        }
      }
      if buffer.fixed_offset is Some(_) {
        break
      }
      offset += buffer.alignment
    }
  }
  false
}

///|
/// Enumerates every aligned offset for <=12 buffers and <=4 banks.
/// "infeasible" is returned only after exhaustive search; budget exhaustion is "limit".
pub fn solve_exact(
  problem : Problem,
  max_nodes~ : Int32 = 100000,
) -> ExactResult raise PlanError {
  validate(problem)
  if problem.buffers.length() > 12 || problem.banks.length() > 4 {
    reject("ExactLimit", "exact mode supports at most 12 buffers and 4 banks")
  }
  if max_nodes < 1 || max_nodes > 1000000 {
    reject("SearchBudget", "max_nodes must be 1..1000000")
  }
  let capacities : Map[String, Int64] = Map([])
  for bank in problem.banks {
    capacities[bank.id] = bank.capacity
  }
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
  let search : ExactSearch = {
    ordered,
    capacities,
    placed: [],
    budget: max_nodes,
    nodes: 0,
    limited: false,
  }
  let solved = search.visit(0)
  let layout = if solved {
    let placements = search.placed.map(pair => pair.1)
    placements.sort_by((a, b) => id_compare(a.id, b.id))
    let candidate : Layout = { schema: 1, placements, }
    if !verify(problem, candidate).is_empty() {
      reject("InternalLayout", "exact search produced an invalid witness")
    }
    Some(candidate)
  } else {
    None
  }
  {
    status: if solved {
      "solved"
    } else if search.limited {
      "limit"
    } else {
      "infeasible"
    },
    layout,
    nodes: search.nodes,
    budget: max_nodes,
  }
}

///|
pub extend ExactResult with Eq::{equal, not_equal}

///|
pub extend ExactResult with @debug.Debug::{to_repr}

///|
pub extend ExactResult with ToJson::{to_json}
