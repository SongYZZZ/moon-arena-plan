///|
pub(all) struct Bank {
  id : String
  capacity : Int64
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Inclusive lifetimes. Access restrictions and byte sizes must be supplied.
pub(all) struct Buffer {
  id : String
  bytes : Int64
  first : Int32
  last : Int32
  alignment : Int64
  banks : Array[String]
  fixed_bank : String?
  fixed_offset : Int64?
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Problem {
  schema : Int32
  banks : Array[Bank]
  buffers : Array[Buffer]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Placement {
  id : String
  bank : String
  offset : Int64
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Layout {
  schema : Int32
  placements : Array[Placement]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Finding {
  code : String
  buffer : String
  other : String
  message : String
} derive(Eq, Debug, ToJson)

///|
pub(all) struct BankUsage {
  bank : String
  capacity : Int64
  highwater : Int64
  peak_live_bytes : Int64
  peak_step : Int32
  fits : Bool
} derive(Eq, Debug, ToJson)

///|
pub suberror PlanError {
  PlanError(String, String)
} derive(Debug)

///|
let max_bytes : Int64 = 1125899906842624L

///|
fn reject(code : String, message : String) -> Unit raise PlanError {
  raise PlanError(code, message)
}

///|
fn valid_id(id : String) -> Bool {
  if id.is_empty() || id.length() > 64 {
    return false
  }
  for i, c in id.to_array() {
    match c {
      'a'..<='z' | 'A'..<='Z' | '_' => ()
      '0'..<='9' if i > 0 => ()
      _ => return false
    }
  }
  true
}

///|
pub fn validate(problem : Problem) -> Unit raise PlanError {
  if problem.schema != 1 {
    reject("Schema", "problem schema must be 1")
  }
  if problem.banks.is_empty() || problem.banks.length() > 32 {
    reject("BankCount", "expected 1..32 banks")
  }
  if problem.buffers.length() > 2048 {
    reject("BufferCount", "maximum 2048 buffers")
  }
  let banks : Map[String, Bool] = Map([])
  for bank in problem.banks {
    if !valid_id(bank.id) || banks.contains(bank.id) {
      reject("BankId", "invalid or duplicate bank ID")
    }
    if bank.capacity < 0L || bank.capacity > max_bytes {
      reject("Capacity", "capacity outside 0..2^50")
    }
    banks[bank.id] = true
  }
  let ids : Map[String, Bool] = Map([])
  for buffer in problem.buffers {
    if !valid_id(buffer.id) || ids.contains(buffer.id) {
      reject("BufferId", "invalid or duplicate buffer ID")
    }
    ids[buffer.id] = true
    if buffer.banks.is_empty() || buffer.banks.length() > 32 {
      reject("AllowedBanks", "expected 1..32 allowed banks")
    }
    let seen : Map[String, Bool] = Map([])
    for bank in buffer.banks {
      if !banks.contains(bank) || seen.contains(bank) {
        reject("AllowedBanks", "unknown or repeated bank for " + buffer.id)
      }
      seen[bank] = true
    }
    if buffer.bytes < 1L || buffer.bytes > max_bytes {
      reject("BufferSize", "size outside 1..2^50: " + buffer.id)
    }
    if buffer.first < 0 || buffer.last < buffer.first || buffer.last > 1000000 {
      reject("Lifetime", "invalid inclusive lifetime: " + buffer.id)
    }
    let a = buffer.alignment
    if a < 1L || a > 1073741824L || (a & (a - 1L)) != 0L {
      reject("Alignment", "expected power of two in 1..2^30")
    }
    match (buffer.fixed_bank, buffer.fixed_offset) {
      (None, None) => ()
      (Some(bank), Some(offset)) =>
        if !buffer.banks.contains(bank) ||
          offset < 0L ||
          offset > max_bytes - buffer.bytes ||
          offset % a != 0L {
          reject("FixedOffset", "invalid fixed placement: " + buffer.id)
        }
      _ =>
        reject(
          "FixedOffset", "fixed_bank and fixed_offset must be supplied together",
        )
    }
  }
}

///|
fn live(a : Buffer, b : Buffer) -> Bool {
  a.first <= b.last && b.first <= a.last
}

///|
fn aligned(value : Int64, alignment : Int64) -> Int64 {
  (value + alignment - 1L) / alignment * alignment
}

///|
pub extend Bank with Eq::{equal, not_equal}

///|
pub extend Bank with @debug.Debug::{to_repr}

///|
pub extend Bank with ToJson::{to_json}

///|
pub extend Buffer with Eq::{equal, not_equal}

///|
pub extend Buffer with @debug.Debug::{to_repr}

///|
pub extend Buffer with ToJson::{to_json}

///|
pub extend Problem with Eq::{equal, not_equal}

///|
pub extend Problem with @debug.Debug::{to_repr}

///|
pub extend Problem with ToJson::{to_json}

///|
pub extend Placement with Eq::{equal, not_equal}

///|
pub extend Placement with @debug.Debug::{to_repr}

///|
pub extend Placement with ToJson::{to_json}

///|
pub extend Layout with Eq::{equal, not_equal}

///|
pub extend Layout with @debug.Debug::{to_repr}

///|
pub extend Layout with ToJson::{to_json}

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Finding with @debug.Debug::{to_repr}

///|
pub extend Finding with ToJson::{to_json}

///|
pub extend BankUsage with Eq::{equal, not_equal}

///|
pub extend BankUsage with @debug.Debug::{to_repr}

///|
pub extend BankUsage with ToJson::{to_json}

///|
pub extend PlanError with @debug.Debug::{to_repr}

///|
pub extend Bank with @json.FromJson::{from_json}

///|
pub extend Buffer with @json.FromJson::{from_json}

///|
pub extend Problem with @json.FromJson::{from_json}

///|
pub extend Placement with @json.FromJson::{from_json}

///|
pub extend Layout with @json.FromJson::{from_json}
