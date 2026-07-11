"""A portable hierarchical state-machine DSL for Starlark.

The builders return plain model dictionaries so callers can inspect, serialize, or
lower a model into a host runtime. `define` validates each declared container's
initial transitions, element shapes, callback names, and event declarations.
"""

def _element(kind, **fields):
    result = {"kind": kind}
    result.update(fields)
    return result

def event(name, schema = {}, description = None, examples = ()):
    """Declares an event contract used by `on` and `defer`.

    Args:
        name: Stable event name.
        schema: JSON-schema-shaped payload description.
        description: Optional human-readable event description.
        examples: Optional example payloads.
    """
    _require_nonempty_string(name, "event name")
    if type(schema) != "dict":
        fail("event schema must be a dictionary")
    if description != None and (type(description) != "string" or not description):
        fail("event description must be a non-empty string or None")
    return {
        "name": name,
        "schema": dict(schema),
        "description": description,
        "examples": tuple(examples),
    }

def define(name, *elements):
    """Defines a static HSM model and validates its declared container."""
    model = _element("define", name = name, elements = tuple(elements))
    _validate_model(model)
    return model

def state(name, *elements):
    """Declares a basic or composite state."""
    result = _element("state", name = name, elements = tuple(elements))
    _validate_state(result)
    return result

def final(name):
    """Declares an absorbing final state."""
    _require_name(name, "final state name")
    return _element("final", name = name)

def initial(*targets):
    """Declares the initial route for a model or composite state.

    Strings are converted to `target` elements. A container must have exactly one
    initial declaration and that declaration must select exactly one target.
    """
    return _element(
        "initial",
        elements = tuple([target(item) if type(item) == "string" else item for item in targets]),
    )

def transition(*elements):
    """Declares an event- or time-triggered transition.

    The first argument may be a transition name. Remaining arguments are trigger,
    guard, effect, and target elements.
    """
    name = None
    children = elements
    if children and type(children[0]) == "string":
        name = children[0]
        children = children[1:]
    return _element("transition", name = name, elements = tuple(children))

def on(*events):
    """Declares one or more event triggers."""
    return _element("on", events = tuple(events))

def after(seconds):
    """Declares a positive-duration time trigger in seconds."""
    return _element("after", seconds = seconds)

def target(path):
    """Declares an absolute state target path, such as `/Door/closed`."""
    return _element("target", path = path)

def guard(callback):
    """Declares a named guard callback supplied by the lowering runtime."""
    return _element("guard", callback = callback)

def effect(*callbacks):
    """Declares named transition effect callbacks."""
    return _callbacks("effect", callbacks)

def entry(*callbacks):
    """Declares named state-entry callbacks."""
    return _callbacks("entry", callbacks)

def exit(*callbacks):
    """Declares named state-exit callbacks."""
    return _callbacks("exit", callbacks)

def activity(*callbacks):
    """Declares named state-activity callbacks."""
    return _callbacks("activity", callbacks)

def defer(*events):
    """Declares events deferred while the containing state is active."""
    return _element("defer", events = tuple(events))

def _callbacks(kind, callbacks):
    return _element(kind, callbacks = tuple(callbacks))

def _validate_model(model):
    _require_name(model["name"], "model name")
    _validate_container(model, "/" + model["name"], True)

def _validate_state(element):
    _require_name(element["name"], "state name")
    _validate_container(element, element["name"], False)

def _validate_container(container, label, is_root):
    elements = container.get("elements", ())
    _require_tuple(elements, "elements at " + label)
    nested_states = 0
    initials = []
    seen_state_names = {}
    for element in elements:
        _require_element(element, "element at " + label)
        kind = element["kind"]
        if kind in ["state", "final"]:
            nested_states += 1
            name = element.get("name")
            _require_name(name, kind + " name")
            if name in seen_state_names:
                fail("duplicate state name at " + label + ": " + name)
            seen_state_names[name] = True
        elif kind == "initial":
            initials.append(element)
        else:
            _validate_element(element, label)
    if nested_states or is_root:
        if len(initials) != 1:
            fail("composite state " + label + " must declare exactly one initial")
        _validate_initial(initials[0], label)
    elif initials:
        fail("basic state " + label + " cannot declare an initial")

def _validate_element(element, owner_path):
    kind = element["kind"]
    if kind == "transition":
        _validate_transition(element, owner_path)
    elif kind in ["entry", "exit", "activity", "effect"]:
        _validate_callbacks(element)
    elif kind == "defer":
        _validate_events(element.get("events"), "defer")
    else:
        fail("unsupported " + kind + " element at " + owner_path)

def _validate_initial(element, owner_path):
    _require_element(element, "initial")
    if element["kind"] != "initial":
        fail("expected initial at " + owner_path)
    targets = element.get("elements")
    _require_tuple(targets, "initial targets")
    if len(targets) != 1:
        fail("initial at " + owner_path + " must declare exactly one target")
    _validate_target(targets[0], owner_path)

def _validate_transition(element, owner_path):
    name = element.get("name")
    if name != None:
        _require_name(name, "transition name")
    children = element.get("elements")
    _require_tuple(children, "transition elements")
    target_count = 0
    for child in children:
        _require_element(child, "transition element")
        kind = child["kind"]
        if kind == "on":
            _validate_events(child.get("events"), "on")
        elif kind == "after":
            seconds = child.get("seconds")
            if type(seconds) not in ["int", "float"] or seconds <= 0:
                fail("after seconds must be a positive number")
        elif kind == "guard":
            _require_callback(child.get("callback"), "guard callback")
        elif kind == "effect":
            _validate_callbacks(child)
        elif kind == "target":
            target_count += 1
            _validate_target(child, owner_path)
        else:
            fail("unsupported " + kind + " in transition at " + owner_path)
    if target_count > 1:
        fail("transition at " + owner_path + " has more than one target")

def _validate_target(element, owner_path):
    _require_element(element, "target")
    if element["kind"] != "target":
        fail("expected target at " + owner_path)
    path = element.get("path")
    if type(path) != "string" or not path.startswith("/"):
        fail("target path must be absolute")

def _validate_events(events, label):
    _require_tuple(events, label + " events")
    if not events:
        fail(label + " requires at least one event")
    for item in events:
        if type(item) != "dict" or "name" not in item or "schema" not in item:
            fail(label + " requires event(...) values")
        _require_nonempty_string(item["name"], label + " event name")

def _validate_callbacks(element):
    callbacks = element.get("callbacks")
    _require_tuple(callbacks, element["kind"] + " callbacks")
    if not callbacks:
        fail(element["kind"] + " requires at least one callback")
    for callback in callbacks:
        _require_callback(callback, element["kind"] + " callback")

def _require_callback(value, label):
    _require_name(value, label)

def _require_name(value, label):
    _require_nonempty_string(value, label)
    if "/" in value:
        fail(label + " cannot contain '/'")

def _require_nonempty_string(value, label):
    if type(value) != "string" or not value:
        fail(label + " must be a non-empty string")

def _require_tuple(value, label):
    if type(value) != "tuple":
        fail(label + " must be a tuple")

def _require_element(value, label):
    if type(value) != "dict" or "kind" not in value:
        fail(label + " must be an hsm element")

hsm = struct(
    activity = activity,
    after = after,
    defer = defer,
    define = define,
    effect = effect,
    entry = entry,
    event = event,
    exit = exit,
    final = final,
    guard = guard,
    initial = initial,
    on = on,
    state = state,
    target = target,
    transition = transition,
)
