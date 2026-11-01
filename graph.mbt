///|
pub(all) struct Tensor {
  id : String
  bytes : Int64
  alignment : Int64
  banks : Array[String]
  fixed_bank : String?
  fixed_offset : Int64?
  source : Bool
  retain : Bool
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Step {
  id : String
  inputs : Array[String]
  outputs : Array[String]
  scratch : Array[String]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub(all) struct Graph {
  schema : Int32
  banks : Array[Bank]
  tensors : Array[Tensor]
  steps : Array[Step]
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
/// Translate an explicit serial schedule; no shape or operator semantics inferred.
pub fn lifetimes(graph : Graph) -> Problem raise PlanError {
  if graph.schema != 1 ||
    graph.tensors.length() > 2048 ||
    graph.steps.length() > 4096 {
    reject("GraphLimit", "schema 1, at most 2048 tensors and 4096 steps")
  }
  let specs : Map[String, Tensor] = Map([])
  let first : Map[String, Int32] = Map([])
  let last : Map[String, Int32] = Map([])
  let ready : Map[String, Bool] = Map([])
  let step_ids : Map[String, Bool] = Map([])
  for tensor in graph.tensors {
    if !valid_id(tensor.id) || specs.contains(tensor.id) {
      reject("TensorId", "invalid or duplicate tensor ID")
    }
    specs[tensor.id] = tensor
    if tensor.source {
      first[tensor.id] = 0
      last[tensor.id] = 0
      ready[tensor.id] = true
    }
  }
  let mut edges = 0
  for i, step in graph.steps {
    if !valid_id(step.id) || step_ids.contains(step.id) {
      reject("StepId", "invalid or duplicate step ID")
    }
    step_ids[step.id] = true
    edges += step.inputs.length() +
      step.outputs.length() +
      step.scratch.length()
    if edges > 65536 {
      reject("GraphLimit", "maximum 65536 schedule references")
    }
    for input in step.inputs {
      if !ready.contains(input) {
        reject(
          "UnavailableInput",
          "unknown, scratch or forward input: " + input,
        )
      }
      last[input] = i
    }
    for output in step.outputs {
      if !specs.contains(output) || first.contains(output) {
        reject(
          "OutputProducer",
          "unknown output or multiple producers: " + output,
        )
      }
      first[output] = i
      last[output] = i
      ready[output] = true
    }
    for scratch in step.scratch {
      let spec = match specs.get(scratch) {
        Some(t) => t
        None => {
          reject("Scratch", "unknown scratch tensor")
          continue
        }
      }
      if first.contains(scratch) || spec.source || spec.retain {
        reject(
          "Scratch", "scratch cannot be shared, produced, source or retained",
        )
      }
      first[scratch] = i
      last[scratch] = i
    }
  }
  let buffers : Array[Buffer] = []
  for tensor in graph.tensors {
    let start = match first.get(tensor.id) {
      Some(i) => i
      None => {
        reject(
          "UnscheduledTensor",
          "tensor has no source, producer or scratch use: " + tensor.id,
        )
        0
      }
    }
    buffers.push({
      id: tensor.id,
      bytes: tensor.bytes,
      first: start,
      last: if tensor.retain {
        graph.steps.length()
      } else {
        last[tensor.id]
      },
      alignment: tensor.alignment,
      banks: tensor.banks,
      fixed_bank: tensor.fixed_bank,
      fixed_offset: tensor.fixed_offset,
    })
  }
  let result : Problem = { schema: 1, banks: graph.banks, buffers, }
  validate(result)
  result
}

///|
pub extend Tensor with Eq::{equal, not_equal}

///|
pub extend Tensor with @debug.Debug::{to_repr}

///|
pub extend Tensor with ToJson::{to_json}

///|
pub extend Tensor with @json.FromJson::{from_json}

///|
pub extend Step with Eq::{equal, not_equal}

///|
pub extend Step with @debug.Debug::{to_repr}

///|
pub extend Step with ToJson::{to_json}

///|
pub extend Step with @json.FromJson::{from_json}

///|
pub extend Graph with Eq::{equal, not_equal}

///|
pub extend Graph with @debug.Debug::{to_repr}

///|
pub extend Graph with ToJson::{to_json}

///|
pub extend Graph with @json.FromJson::{from_json}
