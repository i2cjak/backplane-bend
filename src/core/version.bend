import Base

# The running build's version. Release builds rewrite this file from the
# git tag (scripts/build.sh).

def Version.current() -> String:
  "0.1.0-dev"
