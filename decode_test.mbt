///|
fn decode_reject(text : String, code : String) -> Bool {
  try @arena.decode_problem(text) catch {
    @arena.PlanError(c, _) => c == code
  } noraise {
    _ => false
  }
}

///|
test "strict JSON roundtrip uses exact decimal strings for 64 bit fields" {
  let p : @arena.Problem = {
    schema: 1,
    banks: [{ id: "ram", capacity: 4294967296L, }],
    buffers: [],
  }
  assert_eq(@arena.decode_problem(Json(p).stringify()), p)
  assert_eq(
    @arena.decode_layout(Json(@arena.plan(p)).stringify()),
    @arena.plan(p),
  )
}

///|
test "fractional schedule tokens and unknown constraints are rejected" {
  assert_true(
    decode_reject(
      "{\"schema\":1.1,\"banks\":[],\"buffers\":[]}", "IntegerToken",
    ),
  )
  assert_true(
    decode_reject(
      "{\"schema\":1e0,\"banks\":[],\"buffers\":[]}", "IntegerToken",
    ),
  )
  assert_true(
    decode_reject(
      "{\"schema\":1,\"banks\":[],\"buffers\":[],\"typo_constraint\":1}", "UnknownField",
    ),
  )
  assert_true(
    decode_reject(
      "{\"schema\":1,\"schema\":1,\"banks\":[],\"buffers\":[]}", "JsonSyntax",
    ),
  )
  assert_true(
    decode_reject(
      "{\"schema\":1,\"banks\":[{\"id\":\"ram\",\"capacity\":64}],\"buffers\":[]}",
      "JsonShape",
    ),
  )
}

///|
test "nested optional fixed fields roundtrip" {
  let b : @arena.Buffer = {
    id: "a",
    bytes: 16L,
    first: 0,
    last: 1,
    alignment: 16L,
    banks: ["ram"],
    fixed_bank: None,
    fixed_offset: None,
  }
  let p : @arena.Problem = {
    schema: 1,
    banks: [{ id: "ram", capacity: 64L, }],
    buffers: [b],
  }
  assert_eq(@arena.decode_problem(Json(p).stringify()), p)
  let fixed : @arena.Problem = {
    ..p,
    buffers: [{ ..b, fixed_bank: Some("ram"), fixed_offset: Some(0L), }],
  }
  assert_eq(@arena.decode_problem(Json(fixed).stringify()), fixed)
}
