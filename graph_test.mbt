///|
fn tensor(
  id : String,
  source~ : Bool = false,
  retain~ : Bool = false,
) -> @arena.Tensor {
  {
    id,
    bytes: 16L,
    alignment: 16L,
    banks: ["ram"],
    fixed_bank: None,
    fixed_offset: None,
    source,
    retain,
  }
}

///|
fn graph() -> @arena.Graph {
  {
    schema: 1,
    banks: [{ id: "ram", capacity: 128L, }],
    tensors: [
      tensor("input", source=true),
      tensor("mid"),
      tensor("result", retain=true),
      tensor("scratch"),
    ],
    steps: [
      {
        id: "encode",
        inputs: ["input"],
        outputs: ["mid"],
        scratch: ["scratch"],
      },
      { id: "classify", inputs: ["mid"], outputs: ["result"], scratch: [], },
    ],
  }
}

///|
fn graph_reject(g : @arena.Graph, code : String) -> Bool {
  try @arena.lifetimes(g) catch {
    @arena.PlanError(c, _) => c == code
  } noraise {
    _ => false
  }
}

///|
test "schedule derives input intermediate retained output and scratch lifetimes" {
  let p = @arena.lifetimes(graph())
  assert_eq(p.buffers[0].first, 0)
  assert_eq(p.buffers[0].last, 0)
  assert_eq(p.buffers[1].first, 0)
  assert_eq(p.buffers[1].last, 1)
  assert_eq(p.buffers[2].last, 2)
  assert_eq(p.buffers[3].first, 0)
  assert_eq(p.buffers[3].last, 0)
  assert_eq(@arena.verify(p, @arena.plan(p)), [])
}

///|
test "schedule rejects forwards duplicate producers and unknown inputs" {
  let g = graph()
  assert_true(
    graph_reject({ ..g, steps: [g.steps[1], g.steps[0]], }, "UnavailableInput"),
  )
  assert_true(
    graph_reject(
      {
        ..g,
        steps: [
          g.steps[0],
          { id: "again", inputs: [], outputs: ["mid"], scratch: [], },
        ],
      },
      "OutputProducer",
    ),
  )
  assert_true(
    graph_reject(
      {
        ..g,
        steps: [{ id: "bad", inputs: ["unknown"], outputs: [], scratch: [], }],
      },
      "UnavailableInput",
    ),
  )
  assert_true(
    graph_reject(
      {
        ..g,
        steps: [{ id: "bad", inputs: [], outputs: ["input"], scratch: [], }],
      },
      "OutputProducer",
    ),
  )
}

///|
test "scratch cannot escape operator lifetime" {
  let g = graph()
  assert_true(
    graph_reject(
      { ..g, steps: [g.steps[0], { ..g.steps[1], inputs: ["scratch"], }], },
      "UnavailableInput",
    ),
  )
  assert_true(
    graph_reject(
      { ..g, steps: [g.steps[0], { ..g.steps[1], scratch: ["scratch"], }], },
      "Scratch",
    ),
  )
  assert_true(
    graph_reject(
      { ..g, steps: [{ ..g.steps[0], scratch: ["input"], }, g.steps[1]], },
      "Scratch",
    ),
  )
}

///|
test "schedule IDs and unused tensors are validated" {
  let g = graph()
  assert_true(
    graph_reject({ ..g, tensors: g.tensors + [g.tensors[0]], }, "TensorId"),
  )
  assert_true(graph_reject({ ..g, steps: [g.steps[0], g.steps[0]], }, "StepId"))
  assert_true(
    graph_reject(
      { ..g, tensors: g.tensors + [tensor("unused")], },
      "UnscheduledTensor",
    ),
  )
}
