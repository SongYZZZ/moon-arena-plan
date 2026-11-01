///|
fn trace_buffer(id : String, bytes~ : Int64 = 16L) -> @arena.TrackedBuffer {
  {
    id,
    bytes,
    alignment: 16L,
    banks: ["ram"],
    fixed_bank: None,
    fixed_offset: None,
  }
}

///|
fn event(
  step : Int32,
  op : String,
  buffer~ : String = "a",
) -> @arena.TraceEvent {
  { step, op, buffer, }
}

///|
fn trace(events : Array[@arena.TraceEvent]) -> @arena.ExecutionTrace {
  {
    schema: 1,
    banks: [{ id: "ram", capacity: 48L, }],
    buffers: [trace_buffer("a")],
    events,
  }
}

///|
fn trace_reject(t : @arena.ExecutionTrace, code : String) -> Bool {
  try @arena.trace_lifetimes(t) catch {
    @arena.PlanError(c, _) => c == code
  } noraise {
    _ => false
  }
}

///|
test "trace imports reads writes and logical last-use boundaries" {
  let t : @arena.ExecutionTrace = {
    schema: 1,
    banks: [{ id: "ram", capacity: 48L, }],
    buffers: [
      trace_buffer("a", bytes=24L),
      trace_buffer("b"),
      trace_buffer("c", bytes=24L),
    ],
    events: [
      event(0, "begin"),
      event(0, "write"),
      event(1, "begin", buffer="b"),
      event(1, "read"),
      event(1, "write", buffer="b"),
      event(1, "end"),
      event(2, "begin", buffer="c"),
      event(2, "read", buffer="b"),
      event(2, "write", buffer="c"),
      event(2, "end", buffer="b"),
      event(3, "read", buffer="c"),
      event(3, "end", buffer="c"),
    ],
  }
  let p = @arena.trace_lifetimes(t)
  assert_eq(p.buffers.map(b => (b.first, b.last)), [(0, 1), (1, 2), (2, 3)])
  assert_eq(@arena.summarize(p, @arena.plan(p))[0].highwater, 48L)
}

///|
test "trace rejects accesses outside a recorded lifetime" {
  assert_true(trace_reject(trace([event(0, "read")]), "TraceLifecycle"))
  assert_true(
    trace_reject(
      trace([event(0, "begin"), event(1, "end"), event(2, "write")]),
      "TraceLifecycle",
    ),
  )
  assert_true(
    trace_reject(
      trace([event(0, "begin"), event(1, "end"), event(1, "end")]),
      "TraceLifecycle",
    ),
  )
}

///|
test "each trace ID identifies one logical lifetime" {
  assert_true(
    trace_reject(
      trace([event(0, "begin"), event(0, "begin")]),
      "TraceLifecycle",
    ),
  )
  assert_true(
    trace_reject(
      trace([event(0, "begin"), event(1, "end"), event(2, "begin")]),
      "TraceLifecycle",
    ),
  )
}

///|
test "trace times ordering operations and identities are checked" {
  assert_true(
    trace_reject(trace([event(2, "begin"), event(1, "end")]), "TraceOrder"),
  )
  assert_true(trace_reject(trace([event(-1, "begin")]), "TraceTime"))
  assert_true(trace_reject(trace([event(1000001, "begin")]), "TraceTime"))
  assert_true(
    trace_reject(trace([event(0, "begin", buffer="unknown")]), "TraceBuffer"),
  )
  assert_true(trace_reject(trace([event(0, "alloc")]), "TraceOperation"))
}

///|
test "unclosed and unobserved lifetimes cannot be inferred silently" {
  assert_true(trace_reject(trace([event(0, "begin")]), "TraceIncomplete"))
  assert_true(trace_reject(trace([]), "TraceCoverage"))
  assert_true(trace_reject({ ..trace([]), schema: 2, }, "TraceLimit"))
}

///|
test "end and begin on the same step remain simultaneously live" {
  let t : @arena.ExecutionTrace = {
    ..trace([]),
    buffers: [trace_buffer("a"), trace_buffer("b")],
    events: [
      event(0, "begin"),
      event(1, "end"),
      event(1, "begin", buffer="b"),
      event(2, "end", buffer="b"),
    ],
  }
  let p = @arena.trace_lifetimes(t)
  assert_eq(@arena.summarize(p, @arena.plan(p))[0].highwater, 32L)
}

///|
test "trace JSON roundtrip includes pinned and optional metadata" {
  let t = trace([event(0, "begin"), event(1, "end")])
  assert_eq(@arena.decode_trace(Json(t).stringify()), t)
  let pinned = {
    ..t,
    buffers: [
      { ..t.buffers[0], fixed_bank: Some("ram"), fixed_offset: Some(16L), },
    ],
  }
  assert_eq(@arena.decode_trace(Json(pinned).stringify()), pinned)
}

///|
test "trace decoding rejects misspelled metadata and fractional steps" {
  let t = trace([event(0, "begin"), event(1, "end")])
  let text = Json(t).stringify()
  try @arena.decode_trace(text.replace_all(old="events", new="eventz")) catch {
    @arena.PlanError(code, _) => assert_eq(code, "UnknownField")
  } noraise {
    _ => fail("unknown trace field must reject")
  }
  try
    @arena.decode_trace(text.replace_all(old="\"step\":0", new="\"step\":0.5"))
  catch {
    @arena.PlanError(code, _) => assert_eq(code, "IntegerToken")
  } noraise {
    _ => fail("fractional trace step must reject")
  }
}
