# stateforward/hsm.star

`hsm.star` is a dependency-free, portable HSM model DSL for Bazel Starlark.
It constructs validated model dictionaries that can be serialized, inspected in
analysis, or lowered into a host runtime. It deliberately does not pretend to
be an executable state-machine runtime: Bazel evaluates Starlark during build
analysis, not inside a long-lived application process.

## Install

With Bzlmod:

```starlark
bazel_dep(name = "stateforward_hsm", version = "0.1.0")
```

Until a Bazel Central Registry release exists, use a source override:

```starlark
git_override(
    module_name = "stateforward_hsm",
    remote = "https://github.com/stateforward/hsm.star.git",
    commit = "<commit>",
)
```

## Define a model

```starlark
load("@stateforward_hsm//:hsm.bzl", "hsm")

open_event = hsm.event(
    name = "door.open",
    schema = {"type": "object"},
)

door = hsm.define(
    "Door",
    hsm.initial("/Door/closed"),
    hsm.state(
        "closed",
        hsm.transition(
            hsm.on(open_event),
            hsm.guard("is_unlocked"),
            hsm.effect("unlatch"),
            hsm.target("/Door/open"),
        ),
    ),
    hsm.state("open", hsm.entry("announce_open")),
)
```

`define` validates each declared container. Every root or composite state has
one `initial` declaration with one target; target paths must be absolute.
States, transitions, events, and callback declarations are plain dictionaries,
so consumers may safely lower them to their own runtime and resolve targets in
their own model index.

## API

The `hsm` namespace exposes `define`, `state`, `final`, `initial`,
`transition`, `on`, `after`, `target`, `guard`, `effect`, `entry`, `exit`,
`activity`, `defer`, and `event`. The same functions are also exported directly
from `hsm.bzl` for hosts that need flat bindings.

## Verify

```sh
bazel test //...
```
