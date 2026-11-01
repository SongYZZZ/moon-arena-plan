///|
suberror Usage {
  Usage(String)
}

///|
async fn read_text(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  if file.kind() != Regular || size < 0L || size > 4194304L {
    raise Usage("input must be a regular UTF-8 JSON file at most 4 MiB")
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  if file.size() != size {
    raise Usage("input size changed while reading")
  }
  @utf8.decode(bytes)
}

///|
async fn run(args : Array[String]) -> Int32 {
  if args.is_empty() || args == ["--help"] {
    @stdio.stdout.write(
      "MoonArenaPlan 0.2.0-dev\nexact PROBLEM.json [MAX_NODES]\nexplain PROBLEM.json [LAYOUT.json]\ncompare BEFORE.json AFTER.json [MAX_GROWTH_BYTES]\nlifetimes GRAPH.json\ntrace TRACE.json\nplan PROBLEM.json\nlayout PROBLEM.json\nverify PROBLEM.json LAYOUT.json\nheader PROBLEM.json LAYOUT.json\nExit 0: valid plan; 1: constraint findings; 2: input/usage failure; 3: exact search budget exhausted.\n",
    )
    return 0
  }
  if args.length() < 2 || args.length() > 4 {
    raise Usage("see --help for command arguments")
  }
  if args[0] == "trace" && args.length() == 2 {
    let trace = @arena.decode_trace(read_text(args[1]))
    @stdio.stdout.write(
      Json(@arena.trace_lifetimes(trace)).stringify(indent=2) + "\n",
    )
    return 0
  }
  if args[0] == "lifetimes" && args.length() == 2 {
    let graph : @arena.Graph = @arena.decode_graph(read_text(args[1]))
    @stdio.stdout.write(
      Json(@arena.lifetimes(graph)).stringify(indent=2) + "\n",
    )
    return 0
  }
  let problem : @arena.Problem = @arena.decode_problem(read_text(args[1]))
  let command = args[0]
  if command == "compare" && (args.length() == 3 || args.length() == 4) {
    let candidate = @arena.decode_problem(read_text(args[2]))
    let growth = if args.length() == 4 {
      @string.parse_int64(args[3])
    } else {
      0L
    }
    let report = @arena.compare_layouts(
      problem,
      @arena.plan(problem),
      candidate,
      @arena.plan(candidate),
      max_growth_bytes=growth,
    )
    @stdio.stdout.write(Json(report).stringify(indent=2) + "\n")
    return if report.gate_passed { 0 } else { 1 }
  }
  if command == "exact" && args.length() <= 3 {
    let budget = if args.length() == 3 {
      @string.parse_int(args[2])
    } else {
      100000
    }
    let result = @arena.solve_exact(problem, max_nodes=budget)
    @stdio.stdout.write(Json(result).stringify(indent=2) + "\n")
    return if result.status == "solved" {
      0
    } else if result.status == "infeasible" {
      1
    } else {
      3
    }
  }
  if command == "explain" && args.length() <= 3 {
    let layout = if args.length() == 3 {
      @arena.decode_layout(read_text(args[2]))
    } else {
      @arena.plan(problem)
    }
    let peaks = @arena.explain(problem, layout)
    @stdio.stdout.write(Json(peaks).stringify(indent=2) + "\n")
    return if peaks.any(p => p.layout_over_budget_by > 0L) { 1 } else { 0 }
  }
  if (command == "plan" || command == "layout") && args.length() == 2 {
    let layout = @arena.plan(problem)
    let findings = @arena.verify(problem, layout)
    let report : Json = if command == "layout" {
      Json(layout)
    } else {
      {
        "layout": Json(layout),
        "banks": Json(@arena.summarize(problem, layout)),
        "findings": Json(findings),
        "valid": Json(findings.is_empty()),
        "optimal": false,
      }
    }
    @stdio.stdout.write(report.stringify(indent=2) + "\n")
    return if findings.is_empty() { 0 } else { 1 }
  }
  if (command == "verify" || command == "header") && args.length() == 3 {
    let layout : @arena.Layout = @arena.decode_layout(read_text(args[2]))
    let findings = @arena.verify(problem, layout)
    if command == "header" {
      @stdio.stdout.write(@arena.c_header(problem, layout))
    } else {
      @stdio.stdout.write(
        (
          { "valid": Json(findings.is_empty()), "findings": Json(findings) } :
          Json).stringify(indent=2) +
        "\n",
      )
    }
    return if findings.is_empty() { 0 } else { 1 }
  }
  raise Usage("unknown command or argument count; see --help")
}

///|
async fn main {
  let args = @env.args()
  let code = run(args[1:].to_owned()) catch {
    @arena.PlanError(code, message) => {
      @stdio.stderr.write(
        ({ "code": Json(code), "message": Json(message) } : Json).stringify() +
        "\n",
      ) catch {
        _ => ()
      }
      2
    }
    error => {
      @stdio.stderr.write(
        ({ "code": "InputOrUsage", "message": Json(error.to_string()) } : Json).stringify() +
        "\n",
      ) catch {
        _ => ()
      }
      2
    }
  }
  if code != 0 {
    @sys.exit(code)
  }
}
