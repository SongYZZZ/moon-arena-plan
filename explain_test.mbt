///|
fn explain_buffer(
  id : String,
  bytes : Int64,
  first : Int32,
  last : Int32,
) -> @arena.Buffer {
  {
    id,
    bytes,
    first,
    last,
    alignment: 1L,
    banks: ["ram"],
    fixed_bank: None,
    fixed_offset: None,
  }
}

///|
fn explain_problem(
  buffers : Array[@arena.Buffer],
  capacity~ : Int64 = 32L,
) -> @arena.Problem {
  { schema: 1, banks: [{ id: "ram", capacity, }], buffers, }
}

///|
test "explanation separates layout overhead from simultaneous demand" {
  let a = explain_buffer("a", 5L, 0, 0)
  let b = { ..explain_buffer("b", 4L, 0, 0), alignment: 4L, }
  let p = explain_problem([a, b], capacity=9L)
  let report = @arena.explain(p, @arena.plan(p))[0]
  assert_eq(report.peak_live_bytes, 9L)
  assert_eq(report.highwater, 12L)
  assert_eq(report.layout_over_budget_by, 3L)
  assert_eq(report.live_over_budget_by, 0L)
  assert_eq(report.highwater_minus_peak, 3L)
  assert_eq(report.live_buffers.map(b => b.id), ["a", "b"])
  let exact = @arena.solve_exact(p).layout.unwrap()
  assert_eq(@arena.explain(p, exact)[0].layout_over_budget_by, 0L)
}

///|
test "peak explanations include both sides of handover" {
  let p = explain_problem(
    [explain_buffer("input", 8L, 0, 1), explain_buffer("output", 8L, 1, 2)],
    capacity=10L,
  )
  let report = @arena.explain(p, @arena.plan(p))[0]
  assert_eq(report.peak_step, 1)
  assert_eq(report.live_buffers.length(), 2)
  assert_eq(report.live_over_budget_by, 6L)
}

///|
test "empty bank and earliest equal peaks have precise identities" {
  let p = explain_problem([
    explain_buffer("early", 8L, 0, 0),
    explain_buffer("late", 8L, 1, 1),
  ])
  let report = @arena.explain(p, @arena.plan(p))[0]
  assert_eq(report.peak_step, 0)
  assert_eq(report.live_buffers.map(b => b.id), ["early"])
  let empty = explain_problem([])
  assert_eq(@arena.explain(empty, @arena.plan(empty))[0].live_buffers, [])
}

///|
test "fixed gaps are not mistaken for live buffer demand" {
  let b = {
    ..explain_buffer("fixed", 16L, 0, 0),
    fixed_bank: Some("ram"),
    fixed_offset: Some(128L),
  }
  let p = explain_problem([b], capacity=256L)
  let report = @arena.explain(p, @arena.plan(p))[0]
  assert_eq(report.highwater, 144L)
  assert_eq(report.peak_live_bytes, 16L)
  assert_eq(report.highwater_minus_peak, 128L)
}

///|
test "explanation refuses forged layouts" {
  let p = explain_problem([explain_buffer("a", 8L, 0, 0)])
  try
    @arena.explain(p, {
      schema: 1,
      placements: [{ id: "a", bank: "ram", offset: -1L, }],
    })
  catch {
    @arena.PlanError(code, _) => assert_eq(code, "InvalidLayout")
  } noraise {
    _ => fail("forged layout must reject")
  }
}
