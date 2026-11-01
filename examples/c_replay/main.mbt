///|
extern "C" fn replay() -> Int32 = "mp_replay"

///|
fn main {
  if replay() != 0 {
    panic()
  }
  println("C replay verified: inclusive lifetimes and generated offsets")
}
