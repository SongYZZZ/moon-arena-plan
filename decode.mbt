///|
fn fields(
  value : Json,
  allowed : Array[String],
  context : String,
) -> Map[String, Json] raise PlanError {
  let obj = match value {
    Object(obj) => obj
    _ => {
      reject("JsonShape", context + " must be an object")
      Map([])
    }
  }
  for key in obj.keys() {
    if !allowed.contains(key) {
      reject("UnknownField", context + ": " + key)
    }
  }
  for key in ["fixed_bank", "fixed_offset"] {
    if obj.get(key) is Some(Null) {
      ignore(obj.remove(key))
    }
  }
  obj
}

///|
fn items(obj : Map[String, Json], key : String) -> Array[Json] raise PlanError {
  match obj.get(key) {
    Some(Array(a)) => a
    _ => {
      reject("JsonShape", key + " must be an array")
      []
    }
  }
}

///|
fn integer_tokens(value : Json) -> Unit raise PlanError {
  match value {
    Number(_, repr=Some(raw)) =>
      if raw.contains_char('.') ||
        raw.contains_char('e') ||
        raw.contains_char('E') {
        reject("IntegerToken", "numeric fields must use integer tokens")
      }
    Array(a) =>
      for item in a {
        integer_tokens(item)
      }
    Object(o) =>
      for value in o.values() {
        integer_tokens(value)
      }
    _ => ()
  }
}

///|
fn json_input(text : String) -> Json raise PlanError {
  if text.length() > 4194304 {
    reject("InputLimit", "input exceeds 4 Mi code units")
  }
  let value = @json.parse(
    text,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    e => {
      reject("JsonSyntax", e.to_string())
      Json::null()
    }
  }
  integer_tokens(value)
  value
}

///|
fn bank_fields(obj : Map[String, Json]) -> Unit raise PlanError {
  for bank in items(obj, "banks") {
    ignore(fields(bank, ["id", "capacity"], "bank"))
  }
}

///|
pub fn decode_problem(text : String) -> Problem raise PlanError {
  let value = json_input(text)
  let obj = fields(value, ["schema", "banks", "buffers"], "problem")
  bank_fields(obj)
  if items(obj, "buffers").length() > 2048 {
    reject("BufferCount", "maximum 2048 buffers")
  }
  for buffer in items(obj, "buffers") {
    ignore(
      fields(
        buffer,
        [
          "id", "bytes", "first", "last", "alignment", "banks", "fixed_bank", "fixed_offset",
        ],
        "buffer",
      ),
    )
  }
  let result : Problem = @json.from_json(value) catch {
    e => {
      reject("JsonShape", e.to_string())
      { schema: 0, banks: [], buffers: [], }
    }
  }
  validate(result)
  result
}

///|
pub fn decode_layout(text : String) -> Layout raise PlanError {
  let value = json_input(text)
  let obj = fields(value, ["schema", "placements"], "layout")
  if items(obj, "placements").length() > 4096 {
    reject("LayoutLimit", "maximum 4096 placements")
  }
  for p in items(obj, "placements") {
    ignore(fields(p, ["id", "bank", "offset"], "placement"))
  }
  @json.from_json(value) catch {
    e => {
      reject("JsonShape", e.to_string())
      { schema: 0, placements: [], }
    }
  }
}

///|
pub fn decode_graph(text : String) -> Graph raise PlanError {
  let value = json_input(text)
  let obj = fields(value, ["schema", "banks", "tensors", "steps"], "graph")
  bank_fields(obj)
  if items(obj, "tensors").length() > 2048 ||
    items(obj, "steps").length() > 4096 {
    reject("GraphLimit", "graph count limit exceeded")
  }
  for tensor in items(obj, "tensors") {
    ignore(
      fields(
        tensor,
        [
          "id", "bytes", "alignment", "banks", "fixed_bank", "fixed_offset", "source",
          "retain",
        ],
        "tensor",
      ),
    )
  }
  for step in items(obj, "steps") {
    ignore(fields(step, ["id", "inputs", "outputs", "scratch"], "step"))
  }
  @json.from_json(value) catch {
    e => {
      reject("JsonShape", e.to_string())
      { schema: 0, banks: [], tensors: [], steps: [], }
    }
  }
}

///|
pub fn decode_trace(text : String) -> ExecutionTrace raise PlanError {
  let value = json_input(text)
  let obj = fields(value, ["schema", "banks", "buffers", "events"], "trace")
  bank_fields(obj)
  if items(obj, "buffers").length() > 2048 ||
    items(obj, "events").length() > 65536 {
    reject("TraceLimit", "maximum 2048 buffers and 65536 events")
  }
  for b in items(obj, "buffers") {
    ignore(
      fields(
        b,
        ["id", "bytes", "alignment", "banks", "fixed_bank", "fixed_offset"],
        "trace buffer",
      ),
    )
  }
  for event in items(obj, "events") {
    ignore(fields(event, ["step", "op", "buffer"], "trace event"))
  }
  @json.from_json(value) catch {
    e => {
      reject("JsonShape", e.to_string())
      { schema: 0, banks: [], buffers: [], events: [], }
    }
  }
}
