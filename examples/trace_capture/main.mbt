///|
extern "C" fn capture_trace() -> Int32 = "mp_capture_trace"

///|
fn main {
  if capture_trace() != 0 {
    panic()
  }
}
