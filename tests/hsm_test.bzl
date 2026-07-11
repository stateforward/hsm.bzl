load("//:hsm.bzl", "hsm")

def _assert_equal(actual, expected, label):
    if actual != expected:
        fail("%s: got %r, want %r" % (label, actual, expected))

def _hsm_test_impl(ctx):
    input_event = hsm.event(
        name = "door.open",
        schema = {"type": "object"},
        description = "Open the door.",
        examples = ({},),
    )
    model = hsm.define(
        "Door",
        hsm.initial("/Door/closed"),
        hsm.state(
            "closed",
            hsm.entry("latch"),
            hsm.transition(
                "open",
                hsm.on(input_event),
                hsm.guard("is_unlocked"),
                hsm.effect("unlatch"),
                hsm.target("/Door/open"),
            ),
        ),
        hsm.state(
            "open",
            hsm.activity("watch_open"),
            hsm.transition(hsm.after(5), hsm.target("/Door/closed")),
        ),
    )

    _assert_equal(model["kind"], "define", "model kind")
    _assert_equal(model["name"], "Door", "model name")
    _assert_equal(model["elements"][0]["elements"][0]["path"], "/Door/closed", "initial target")
    _assert_equal(model["elements"][1]["elements"][1]["elements"][0]["events"][0]["name"], "door.open", "event name")
    _assert_equal(hsm.final("done"), {"kind": "final", "name": "done"}, "final declaration")

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(executable, "#!/bin/sh\nexit 0\n", is_executable = True)
    return [DefaultInfo(executable = executable)]

hsm_test = rule(
    implementation = _hsm_test_impl,
    test = True,
)
