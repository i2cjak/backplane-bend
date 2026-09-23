import Base
import ../../src/core/json.bend as J
import ../../src/core/cbor.bend as C

# The hub's CBOR codec, for test/smoke.ts: a message's JSON text to the
# bytes of a frame, and back.

def encode(text: String) -> List<&2, U32>:
  C.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

def decode(bs: List<&2, U32>) -> String:
  J.Json.show(Maybe.default(&2, J.Json, C.Cbor.decode(bs), J.Null{}))
