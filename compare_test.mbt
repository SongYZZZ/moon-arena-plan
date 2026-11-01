///|
fn comparison_problem(bytes : Int64, capacity~ : Int64 = 64L) -> @arena.Problem {
  {
    schema: 1,
    banks: [{ id: "ram", capacity, }],
    buffers: [
      {
        id: "a",
        bytes,
        first: 0,
        last: 0,
        alignment: 1L,
        banks: ["ram"],
        fixed_bank: None,
        fixed_offset: None,
      },
    ],
  }
}

///|
fn comparison(
  before : @arena.Problem,
  after : @arena.Problem,
  limit~ : Int64 = 0L,
) -> @arena.Comparison raise @arena.PlanError {
  @arena.compare_layouts(
    before,
    @arena.plan(before),
    after,
    @arena.plan(after),
    max_growth_bytes=limit,
  )
}

///|
test "comparison identity improvement and growth thresholds" {
  let a = comparison_problem(16L)
  let b = comparison_problem(32L)
  assert_true(comparison(a, a).gate_passed)
  assert_false(comparison(a, b).gate_passed)
  assert_eq(comparison(a, b).banks[0].highwater_delta, 16L)
  assert_eq(comparison(a, b).banks[0].peak_live_delta, 16L)
  assert_true(comparison(a, b, limit=16L).gate_passed)
  assert_true(comparison(b, a).gate_passed)
  assert_eq(comparison(b, a).banks[0].highwater_delta, -16L)
}

///|
test "capacity reduction fails even when footprint is unchanged" {
  let before = comparison_problem(16L)
  let after = comparison_problem(16L, capacity=8L)
  let report = comparison(before, after, limit=64L)
  assert_false(report.gate_passed)
  assert_false(report.candidate_valid)
  assert_true(report.banks[0].candidate_over_budget)
  assert_eq(report.banks[0].highwater_delta, 0L)
}

///|
test "bank addition and removal are explicit and stably ordered" {
  let before = comparison_problem(16L)
  let b = before.buffers[0]
  let after : @arena.Problem = {
    schema: 1,
    banks: [{ id: "other", capacity: 64L, }],
    buffers: [{ ..b, banks: ["other"], }],
  }
  let report = comparison(before, after, limit=16L)
  assert_true(report.gate_passed)
  assert_eq(report.banks.map(b => b.bank), ["other", "ram"])
  assert_eq(report.banks[0].change, "added")
  assert_eq(report.banks[0].before_capacity, None)
  assert_eq(report.banks[1].change, "removed")
  assert_eq(report.banks[1].after_capacity, None)
}

///|
test "live peak growth is visible even inside fixed highwater" {
  let a = {
    ..comparison_problem(16L).buffers[0],
    fixed_bank: Some("ram"),
    fixed_offset: Some(128L),
  }
  let before : @arena.Problem = {
    schema: 1,
    banks: [{ id: "ram", capacity: 256L, }],
    buffers: [a],
  }
  let after = {
    ..before,
    buffers: [
      a,
      { ..a, id: "b", bytes: 32L, fixed_bank: None, fixed_offset: None, },
    ],
  }
  let report = comparison(before, after)
  assert_eq(report.banks[0].highwater_delta, 0L)
  assert_eq(report.banks[0].peak_live_delta, 32L)
  assert_false(report.gate_passed)
}

///|
test "comparison accepts external exact witnesses" {
  let a : @arena.Buffer = {
    id: "a",
    bytes: 5L,
    first: 0,
    last: 0,
    alignment: 1L,
    banks: ["ram"],
    fixed_bank: None,
    fixed_offset: None,
  }
  let p : @arena.Problem = {
    schema: 1,
    banks: [{ id: "ram", capacity: 9L, }],
    buffers: [a, { ..a, id: "b", bytes: 4L, alignment: 4L, }],
  }
  let greedy = @arena.plan(p)
  let exact = @arena.solve_exact(p).layout.unwrap()
  let report = @arena.compare_layouts(p, greedy, p, exact)
  assert_false(report.baseline_valid)
  assert_true(report.candidate_valid)
  assert_true(report.gate_passed)
}

///|
test "comparison refuses malformed layouts and growth limits" {
  let p = comparison_problem(16L)
  try
    @arena.compare_layouts(p, { schema: 1, placements: [], }, p, @arena.plan(p))
  catch {
    @arena.PlanError(c, _) => assert_eq(c, "InvalidLayout")
  } noraise {
    _ => fail("invalid baseline must reject")
  }
  for limit in [-1L, 1125899906842625L] {
    try comparison(p, p, limit~) catch {
      @arena.PlanError(c, _) => assert_eq(c, "GrowthLimit")
    } noraise {
      _ => fail("growth limit must reject")
    }
  }
}
