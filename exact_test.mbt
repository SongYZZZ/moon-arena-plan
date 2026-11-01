///|
fn exact_buffer(
  id : String,
  bytes : Int64,
  alignment~ : Int64 = 1L,
  banks~ : Array[String] = ["ram"],
  fixed_bank? : String,
  fixed_offset? : Int64,
) -> @arena.Buffer {
  { id, bytes, alignment, banks, fixed_bank, fixed_offset, first: 0, last: 0, }
}

///|
fn exact_problem(
  buffers : Array[@arena.Buffer],
  capacity~ : Int64 = 9L,
) -> @arena.Problem {
  { schema: 1, banks: [{ id: "ram", capacity, }], buffers, }
}

///|
test "exact finds a feasible packing after greedy alignment failure" {
  let p = exact_problem([
    exact_buffer("a", 5L),
    exact_buffer("b", 4L, alignment=4L),
  ])
  assert_eq(@arena.summarize(p, @arena.plan(p))[0].highwater, 12L)
  let result = @arena.solve_exact(p)
  assert_eq(result.status, "solved")
  let layout = result.layout.unwrap()
  assert_eq(@arena.verify(p, layout), [])
  assert_eq(@arena.summarize(p, layout)[0].highwater, 9L)
}

///|
test "exhaustion and budget limits are different outcomes" {
  let p = exact_problem(
    [exact_buffer("a", 1L), exact_buffer("b", 1L)],
    capacity=1L,
  )
  let complete = @arena.solve_exact(p, max_nodes=2)
  assert_eq(complete.status, "infeasible")
  assert_eq(complete.nodes, 2)
  assert_eq(complete.layout, None)
  let limited = @arena.solve_exact(p, max_nodes=1)
  assert_eq(limited.status, "limit")
  assert_eq(limited.nodes, 1)
  assert_eq(limited.layout, None)
}

///|
test "a solution on the final permitted search node is retained" {
  let p = exact_problem([exact_buffer("a", 1L)], capacity=1L)
  let result = @arena.solve_exact(p, max_nodes=1)
  assert_eq(result.status, "solved")
  assert_eq(result.nodes, 1)
}

///|
test "exact search respects fixed positions and bank reachability" {
  let p : @arena.Problem = {
    schema: 1,
    banks: [{ id: "ram", capacity: 4L, }, { id: "dma", capacity: 4L, }],
    buffers: [
      exact_buffer(
        "sensor",
        4L,
        banks=["dma"],
        fixed_bank="dma",
        fixed_offset=0L,
      ),
      exact_buffer("work", 4L, banks=["dma", "ram"]),
    ],
  }
  let result = @arena.solve_exact(p)
  assert_eq(result.status, "solved")
  assert_eq(@arena.verify(p, result.layout.unwrap()), [])
  assert_eq(
    result.layout.unwrap().placements.filter(p => p.id == "work")[0].bank,
    "ram",
  )
}

///|
test "impossible fixed placement has no alternative candidate" {
  let p = exact_problem(
    [exact_buffer("a", 2L, fixed_bank="ram", fixed_offset=2L)],
    capacity=3L,
  )
  assert_eq(@arena.solve_exact(p).status, "infeasible")
  let conflict = exact_problem(
    [
      exact_buffer("a", 1L, fixed_bank="ram", fixed_offset=0L),
      exact_buffer("b", 1L, fixed_bank="ram", fixed_offset=0L),
    ],
    capacity=1L,
  )
  assert_eq(@arena.solve_exact(conflict).status, "infeasible")
}

///|
test "empty problem and nonoverlapping lifetimes" {
  assert_eq(@arena.solve_exact(exact_problem([])).status, "solved")
  let b = exact_buffer("a", 9L)
  let p = exact_problem([b, { ..b, id: "b", first: 1, last: 1, }])
  let result = @arena.solve_exact(p)
  assert_eq(result.status, "solved")
  assert_eq(@arena.verify(p, result.layout.unwrap()), [])
}

///|
test "exact profile and budget bounds are enforced" {
  let buffers : Array[@arena.Buffer] = []
  for i in 0..<13 {
    buffers.push(exact_buffer("b" + i.to_string(), 1L))
  }
  try @arena.solve_exact(exact_problem(buffers)) catch {
    @arena.PlanError(c, _) => assert_eq(c, "ExactLimit")
  } noraise {
    _ => fail("exact profile limit must reject")
  }
  for budget in [0, -1, 1000001] {
    try @arena.solve_exact(exact_problem([]), max_nodes=budget) catch {
      @arena.PlanError(c, _) => assert_eq(c, "SearchBudget")
    } noraise {
      _ => fail("search budget must reject")
    }
  }
}

///|
test "exact witness is deterministic under reordered buffers" {
  let a = exact_buffer("a", 5L)
  let b = exact_buffer("b", 4L, alignment=4L)
  assert_eq(
    @arena.solve_exact(exact_problem([a, b])),
    @arena.solve_exact(exact_problem([b, a])),
  )
}
