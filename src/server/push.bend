import Base
import ../core/model.bend as M

# Phone notifications (APNs alerts and Live Activity updates). The hub
# calls Push.turn_ended once for every turn that completes or fails, off
# its own thread (the server spawns it), with the state as it was when the
# turn ended. `state` is "completed" or "failed". Owned by the mobile work;
# keep the signature, fill in the body.
def Push.turn_ended(+home: String, st: M.State, +thread: String, +state: String) -> IO(Unit):
  IO.pure(Unit, Unit{})
