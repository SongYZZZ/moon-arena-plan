///|
fn buf(
  id : String,
  bytes : Int64,
  first : Int32,
  last : Int32,
  banks~ : Array[String] = ["ram"],
  alignment~ : Int64 = 1L,
  fixed_bank? : String,
  fixed_offset? : Int64,
) -> @arena.Buffer {
  { id, bytes, first, last, banks, alignment, fixed_bank, fixed_offset, }
}

///|
fn problem(
  buffers : Array[@arena.Buffer],
  capacity~ : Int64 = 1024L,
) -> @arena.Problem {
  { schema: 1, banks: [{ id: "ram", capacity, }], buffers, }
}

///|
fn rejects(p : @arena.Problem, code : String) -> Bool {
  try @arena.plan(p) catch {
    @arena.PlanError(c, _) => c == code
  } noraise {
    _ => false
  }
}

///|
test "disjoint lifetimes reuse storage" {
  let p = problem([
    buf("a", 64L, 0, 1),
    buf("b", 64L, 2, 3),
    buf("c", 64L, 4, 5),
  ])
  let layout = @arena.plan(p)
  assert_eq(layout.placements.map(p => p.offset), [0L, 0L, 0L])
  assert_eq(@arena.verify(p, layout), [])
  assert_eq(@arena.summarize(p, layout)[0].highwater, 64L)
}

///|
test "inclusive endpoints prohibit input-output alias" {
  let p = problem([buf("a", 16L, 0, 1), buf("b", 16L, 1, 2)])
  let layout = @arena.plan(p)
  assert_eq(@arena.summarize(p, layout)[0].highwater, 32L)
  assert_eq(@arena.summarize(p, layout)[0].peak_live_bytes, 32L)
  assert_eq(@arena.summarize(p, layout)[0].peak_step, 1)
}

///|
test "alignment padding and touching byte boundaries" {
  let p = problem([buf("a", 17L, 0, 1), buf("b", 8L, 0, 1, alignment=16L)])
  let l = @arena.plan(p)
  assert_eq(l.placements[1].offset, 32L)
  assert_eq(@arena.summarize(p, l)[0].highwater, 40L)
  assert_eq(@arena.summarize(p, l)[0].peak_live_bytes, 25L)
}

///|
test "fixed holes remain usable" {
  let p = problem([
    buf("sensor", 16L, 0, 9, fixed_bank="ram", fixed_offset=32L),
    buf("a", 32L, 0, 1),
  ])
  let l = @arena.plan(p)
  assert_eq(l.placements[0].offset, 0L)
  assert_eq(@arena.summarize(p, l)[0].highwater, 48L)
}

///|
test "fixed conflicts reject while disjoint fixed reuse is legal" {
  assert_true(
    rejects(
      problem([
        buf("a", 16L, 0, 1, fixed_bank="ram", fixed_offset=0L),
        buf("b", 16L, 1, 2, fixed_bank="ram", fixed_offset=0L),
      ]),
      "FixedConflict",
    ),
  )
  let p = problem([
    buf("a", 16L, 0, 1, fixed_bank="ram", fixed_offset=0L),
    buf("b", 16L, 2, 3, fixed_bank="ram", fixed_offset=0L),
  ])
  assert_eq(@arena.verify(p, @arena.plan(p)), [])
}

///|
test "bank access constraints and capacity guide placement" {
  let p : @arena.Problem = {
    schema: 1,
    banks: [{ id: "fast", capacity: 64L, }, { id: "dma", capacity: 64L, }],
    buffers: [
      buf("sensor", 64L, 0, 2, banks=["dma"], fixed_bank="dma", fixed_offset=0L),
      buf("feature", 64L, 0, 2, banks=["dma", "fast"]),
    ],
  }
  let l = @arena.plan(p)
  assert_eq(l.placements.filter(p => p.id == "feature")[0].bank, "fast")
  assert_eq(l.placements.filter(p => p.id == "sensor")[0].bank, "dma")
  assert_eq(@arena.verify(p, l), [])
}

///|
test "over budget returns explicit invalid report" {
  let p = problem([buf("a", 32L, 0, 0)], capacity=16L)
  let l = @arena.plan(p)
  assert_true(@arena.verify(p, l).any(f => f.code == "CapacityExceeded"))
  assert_false(@arena.summarize(p, l)[0].fits)
  try @arena.c_header(p, l) catch {
    @arena.PlanError(c, _) => assert_eq(c, "InvalidLayout")
  } noraise {
    _ => fail("over-budget header must be refused")
  }
}

///|
test "schema bank and identifier input validation" {
  let p = problem([])
  assert_true(rejects({ ..p, schema: 2, }, "Schema"))
  assert_true(rejects({ ..p, banks: [], }, "BankCount"))
  assert_true(
    rejects({ ..p, banks: [{ id: "ram", capacity: -1L, }], }, "Capacity"),
  )
  assert_true(rejects({ ..p, banks: p.banks + p.banks, }, "BankId"))
  assert_true(rejects(problem([buf("bad-id", 1L, 0, 0)]), "BufferId"))
  assert_true(rejects(problem([buf("1bad", 1L, 0, 0)]), "BufferId"))
  assert_true(
    rejects(problem([buf("a", 1L, 0, 0), buf("a", 1L, 0, 0)]), "BufferId"),
  )
}

///|
test "size lifetime and alignment bounds" {
  assert_true(rejects(problem([buf("a", 0L, 0, 0)]), "BufferSize"))
  assert_true(rejects(problem([buf("a", 1L, -1, 0)]), "Lifetime"))
  assert_true(rejects(problem([buf("a", 1L, 2, 1)]), "Lifetime"))
  assert_true(rejects(problem([buf("a", 1L, 0, 1000001)]), "Lifetime"))
  for a in [0L, 3L, -1L, 2147483648L] {
    assert_true(
      rejects(problem([buf("a", 1L, 0, 0, alignment=a)]), "Alignment"),
    )
  }
}

///|
test "allowed banks and paired fixed fields" {
  assert_true(rejects(problem([buf("a", 1L, 0, 0, banks=[])]), "AllowedBanks"))
  assert_true(
    rejects(problem([buf("a", 1L, 0, 0, banks=["x"])]), "AllowedBanks"),
  )
  assert_true(
    rejects(problem([buf("a", 1L, 0, 0, banks=["ram", "ram"])]), "AllowedBanks"),
  )
  assert_true(
    rejects(problem([buf("a", 1L, 0, 0, fixed_bank="ram")]), "FixedOffset"),
  )
  assert_true(
    rejects(problem([buf("a", 1L, 0, 0, fixed_offset=0L)]), "FixedOffset"),
  )
  assert_true(
    rejects(
      problem([
        buf("a", 1L, 0, 0, alignment=16L, fixed_bank="ram", fixed_offset=1L),
      ]),
      "FixedOffset",
    ),
  )
}

///|
test "empty plan and determinism under reordered input" {
  let p = problem([])
  assert_eq(@arena.plan(p).placements, [])
  assert_eq(@arena.summarize(p, @arena.plan(p))[0].highwater, 0L)
  let a = buf("a", 20L, 0, 1)
  let b = buf("b", 13L, 1, 2)
  assert_eq(@arena.plan(problem([a, b])), @arena.plan(problem([b, a])))
}

///|
test "independent verifier rejects omission duplicate and unknown buffer" {
  let p = problem([buf("a", 8L, 0, 1)])
  assert_true(
    @arena.verify(p, { schema: 1, placements: [], }).any(f => {
      f.code == "MissingPlacement"
    }),
  )
  let slot : @arena.Placement = { id: "a", bank: "ram", offset: 0L, }
  assert_true(
    @arena.verify(p, { schema: 1, placements: [slot, slot], }).any(f => {
      f.code == "DuplicatePlacement"
    }),
  )
  assert_true(
    @arena.verify(p, { schema: 1, placements: [{ ..slot, id: "x", }], }).any(f => {
      f.code == "UnknownBuffer"
    }),
  )
}

///|
test "verifier rejects altered bank address alignment fixed and schema" {
  let p = problem([
    buf("a", 8L, 0, 1, alignment=8L, fixed_bank="ram", fixed_offset=0L),
  ])
  let l = @arena.plan(p)
  assert_true(
    @arena.verify(p, { ..l, schema: 9, }).any(f => f.code == "Schema"),
  )
  for offset in [-1L, 1125899906842624L] {
    assert_true(
      @arena.verify(p, {
        schema: 1,
        placements: [{ id: "a", bank: "ram", offset, }],
      }).any(f => f.code == "AddressRange"),
    )
  }
  assert_true(
    @arena.verify(p, {
      schema: 1,
      placements: [{ id: "a", bank: "ram", offset: 1L, }],
    }).any(f => f.code == "Misaligned"),
  )
  assert_true(
    @arena.verify(p, {
      schema: 1,
      placements: [{ id: "a", bank: "ram", offset: 8L, }],
    }).any(f => f.code == "FixedOffsetChanged"),
  )
  assert_true(
    @arena.verify(p, {
      schema: 1,
      placements: [{ id: "a", bank: "other", offset: 0L, }],
    }).any(f => f.code == "BankNotAllowed"),
  )
}

///|
test "verifier does not trust a forged nonoverlap claim" {
  let p = problem([buf("a", 8L, 0, 1), buf("b", 8L, 1, 2)])
  let l : @arena.Layout = {
    schema: 1,
    placements: [
      { id: "a", bank: "ram", offset: 0L, },
      { id: "b", bank: "ram", offset: 0L, },
    ],
  }
  assert_true(@arena.verify(p, l).any(f => f.code == "LiveOverlap"))
}

///|
test "large exact integer sizes do not truncate to 32 bits" {
  let p = problem([buf("a", 4294967296L, 0, 1)], capacity=8589934592L)
  let l = @arena.plan(p)
  assert_eq(@arena.summarize(p, l)[0].highwater, 4294967296L)
  assert_eq(@arena.verify(p, l), [])
}

///|
test "generated schedules always satisfy independent constraints" {
  for seed in 0..<100 {
    let buffers : Array[@arena.Buffer] = []
    for i in 0..<12 {
      let first = (seed * 7 + i * 11) % 13
      buffers.push(
        buf(
          "b" + i.to_string(),
          ((seed + i * 3) % 23 + 1).to_int64(),
          first,
          first + i % 4,
          alignment=1L << (i % 5),
        ),
      )
    }
    let p = problem(buffers, capacity=10000L)
    let l = @arena.plan(p)
    assert_eq(@arena.verify(p, l), [])
    let usage = @arena.summarize(p, l)[0]
    assert_true(usage.highwater >= usage.peak_live_bytes)
  }
}

///|
test "stable ASCII ID ordering includes unequal lengths" {
  let p = problem([buf("z", 1L, 0, 0), buf("aa", 1L, 0, 0), buf("a", 1L, 0, 0)])
  assert_eq(@arena.plan(p).placements.map(p => p.id), ["a", "aa", "z"])
}
