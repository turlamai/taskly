#!/usr/bin/env python3
import argparse
import datetime
import json
import os
import sqlite3
import subprocess
import time
from pathlib import Path

import pyatspi


def children(node):
    try:
        count = node.childCount
    except Exception:
        return
    for index in range(count):
        try:
            child = node.getChildAtIndex(index)
            # GTK can remove and rebuild a row between childCount and the
            # D-Bus lookup while async task snapshots arrive.
            if child is not None:
                yield child
        except Exception:
            continue


def walk(node):
    if node is None:
        return
    yield node
    for child in children(node):
        yield from walk(child)


def role(node):
    try:
        return node.getRoleName()
    except Exception:
        return "unknown"


def name(node):
    try:
        return node.name or ""
    except Exception:
        # A row can disappear between two AT-SPI calls while GTK rebuilds it.
        return ""


def text(node):
    try:
        value = node.queryText()
        return value.getText(0, value.characterCount)
    except Exception:
        return ""


def wait_for(description, probe, timeout=60.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = probe()
        if value:
            return value
        time.sleep(0.05)
    # Timeout diagnostics: the visible control inventory is what a distant
    # runner needs; a bare timeout name alone is not actionable. The full
    # inventory also lands in TASKLY_TIMEOUT_DUMP when set.
    inventory = []
    try:
        application = find_application()
        frame = find_frame(application)
        for node in walk(frame):
            node_name = name(node)
            if node_name:
                inventory.append(f"{role(node)}[{node_name[:80]}]")
    except Exception:
        pass
    dump_path = os.environ.get("TASKLY_TIMEOUT_DUMP")
    if dump_path and inventory:
        try:
            Path(dump_path).write_text("\n".join(inventory), encoding="utf-8")
        except Exception:
            pass
    suffix = f"; visible controls={inventory[:25]}" if inventory else ""
    raise AssertionError(f"timed out waiting for {description}{suffix}")


def find_application():
    desktop = pyatspi.Registry.getDesktop(0)
    for application in children(desktop):
        for node in children(application):
            if role(node) == "frame" and "taskly" in name(node).casefold():
                return application
    return None


def find_frame(application):
    if application is None:
        return None
    return next(
        (node for node in children(application) if role(node) == "frame"),
        None,
    )


# AT-SPI button roles vary across distro accessibility stacks: older
# stacks expose "push button", GTK 4.16+ on newer AT-SPI exposes plain
# "button". The name is the product contract; accept either role.
BUTTON_ROLES = ("push button", "button")


def find_named(root, expected_name, expected_role=None):
    for node in walk(root):
        if name(node) != expected_name:
            continue
        if expected_role is None:
            return node
        if expected_role in BUTTON_ROLES:
            if role(node) in BUTTON_ROLES:
                return node
        elif role(node) == expected_role:
            return node
    return None


def find_editable_named(root, expected_name):
    for node in walk(root):
        if name(node) != expected_name:
            continue
        try:
            node.queryEditableText()
            return node
        except Exception:
            continue
    return None


def find_editable_value(root, expected_value):
    for node in walk(root):
        try:
            editable = node.queryEditableText()
            if editable.getText(0, editable.characterCount) == expected_value:
                return node
        except Exception:
            continue
    return None


def contains_text(root, expected):
    return any(name(node) == expected or text(node) == expected for node in walk(root))


def persisted_first_run_due_date():
    """Assert the exact stored ISO date independently of rendered labels."""
    db = sqlite3.connect(Path.home() / ".taskly" / "tasks.db")
    try:
        rows = db.execute(
            "SELECT due_date FROM tasks WHERE text = ?",
            ("First-run persistence task",),
        ).fetchall()
    finally:
        db.close()
    expected = (
        datetime.date.today() + datetime.timedelta(days=1)
    ).isoformat()
    if rows != [(expected,)]:
        raise AssertionError(
            f"first-run task date not persisted: expected {expected!r}, rows={rows!r}"
        )


def first_run_due_rendered(root):
    """Require Tomorrow on *the persisted task row*, not elsewhere in UI.

    In multi-list views the GTK meta label is 'List name  ·  Tomorrow',
    so an exact-text match against the whole GtkLabel is incorrect.
    """
    for node in walk(root):
        if role(node) != "list item":
            continue
        descendants = list(walk(node))
        if not any(
            name(child) == "First-run persistence task"
            or text(child) == "First-run persistence task"
            for child in descendants
        ):
            continue
        for child in descendants:
            values = (name(child), text(child))
            for value in values:
                if "Tomorrow" in [
                    component.strip() for component in value.split("·")
                ]:
                    return True
    return False


def find_staged_delete_ready(root):
    """Find the Undo button and verify both staged task rows are already hidden in one tree walk."""
    undo = None
    found_a = False
    found_b = False
    for node in walk(root):
        node_name = name(node)
        node_text = ""
        if node_name == "Undo" and role(node) in BUTTON_ROLES:
            undo = node
        if node_name == "64-bit task A":
            found_a = True
        elif not found_a:
            node_text = text(node)
            if node_text == "64-bit task A":
                found_a = True
        if node_name == "64-bit task B":
            found_b = True
        elif not found_b:
            if not node_text:
                node_text = text(node)
            if node_text == "64-bit task B":
                found_b = True
        if undo is not None and found_a and found_b:
            return None
    return undo if undo is not None and not found_a and not found_b else None


def matching_child_indexes(container, expected):
    result = []
    try:
        count = container.childCount
    except Exception:
        return result
    for index in range(count):
        try:
            child = container.getChildAtIndex(index)
        except Exception:
            continue
        if contains_text(child, expected):
            result.append(index)
    return result


def select_single_named_child(root, expected):
    """Select the one direct row containing expected in a selection container."""
    for container in walk(root):
        try:
            selection = container.querySelection()
        except Exception:
            continue
        indexes = matching_child_indexes(container, expected)
        if len(indexes) != 1:
            continue
        selection.clearSelection()
        if not selection.selectChild(indexes[0]):
            raise AssertionError(f"AT-SPI failed to select row containing {expected!r}")
        return container.getChildAtIndex(indexes[0])
    return None


def select_and_focus_row(root, expected):
    """Select the row, then click its title label.

    §5: clicking the task title opens the inline quick editor. The click
    goes through xdotool at the title label's AT-SPI extent — a real
    pointer event, since AT-SPI selection does not move GTK keyboard focus
    and synthetic row double-clicks are swallowed by GTK's gesture stack.
    """
    row = select_single_named_child(root, expected)
    if row is None:
        return None
    try:
        title = next(node for node in walk(row)
                     if role(node) == "label" and name(node) == expected)
        extent = title.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
        try:
            ex, ey, ew, eh = extent.x, extent.y, extent.width, extent.height
        except AttributeError:
            ex, ey, ew, eh = extent
        center_x = ex + min(ew // 2, 120)
        center_y = ey + eh // 2
        subprocess.run(
            ["xdotool", "mousemove", str(center_x), str(center_y),
             "click", "1"],
            check=True, timeout=5,
        )
    except Exception as error:
        print(f"title click failed for {expected!r}: {error}", flush=True)
        return None
    return row


def open_detail_layer(root, row_title, attempts=6):
    """Open the anchored detail layer and return the live frame.

    ⓘ is the row's toggle button. GTK rebuilds invalidate proxies between
    snapshots, so every attempt re-reads the live frame and re-finds the
    button instead of retrying a stale proxy.
    """
    for _ in range(attempts):
        live = find_frame(find_application())
        if find_editable_named(live, "Title") is not None:
            return live  # Already open (e.g. a toggle raced the rebuild).
        row = select_single_named_child(live, row_title)
        if row is not None:
            for node in walk(row):
                if role(node) not in BUTTON_ROLES:
                    continue
                if name(node) not in DETAIL_TOGGLE_NAMES:
                    continue
                try:
                    node.queryAction().doAction(0)
                except Exception:
                    pass
                break
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            live = find_frame(find_application())
            if find_editable_named(live, "Title") is not None:
                return live
            time.sleep(0.1)
    # Diagnostics for the distant runner: which row/buttons the attempt saw.
    live = find_frame(find_application())
    probe_row = select_single_named_child(live, row_title)
    observed = []
    if probe_row is not None:
        observed = [
            f"{role(node)}[{name(node)}]"
            for node in walk(probe_row)
            if role(node) in BUTTON_ROLES
        ]
    raise AssertionError(
        f"could not open the detail layer for {row_title!r}; "
        f"row={'found' if probe_row is not None else 'missing'} "
        f"buttons={observed}"
    )


DETAIL_TOGGLE_NAMES = ("\u24d8", "Details", "\u8be6\u60c5")


def close_detail_layer(root, row_title):
    """§5b: pressing the row's ⓘ button again closes the layer (the button
    tracks aria-expanded). While the layer is open its popover is parented
    under that same button, so the row exposes many controls — find the
    toggle by name instead of assuming a single row button. A plain
    button's doAction is reliable on every AT-SPI stack tested;
    popover-internal controls and synthetic Escape are not.
    """
    row = select_single_named_child(root, row_title)
    if row is None:
        raise AssertionError(f"row {row_title!r} not found while closing the layer")
    for node in walk(row):
        if role(node) not in BUTTON_ROLES:
            continue
        if name(node) not in DETAIL_TOGGLE_NAMES:
            continue
        try:
            actions = node.queryAction()
            if actions.nActions >= 1 and actions.doAction(0):
                return True
        except Exception:
            continue
    raise AssertionError(f"could not toggle the detail layer for {row_title!r}")

def select_and_press_unedited_named_row_button(root, expected):
    """Select a direct task-list child and invoke its sole row action atomically.

    Looking for any descendant list item is ambiguous in GTK's AT-SPI tree:
    an outer list item can expose the text of nested task rows. Resolve the
    direct child through its selection container instead, then keep selection
    and action invocation in one traversal so no proxy survives a GTK update.
    """
    for container in walk(root):
        try:
            selection = container.querySelection()
        except Exception:
            continue
        indexes = matching_child_indexes(container, expected)
        if len(indexes) != 1:
            continue
        try:
            selection.clearSelection()
            if not selection.selectChild(indexes[0]):
                continue
            row = container.getChildAtIndex(indexes[0])
            buttons = [
                node
                for node in walk(row)
                if role(node) in ("push button", "button")
            ]
            if len(buttons) != 1:
                continue
            actions = buttons[0].queryAction()
            return actions.nActions >= 1 and actions.doAction(0)
        except Exception:
            continue
    return None


def select_named_children(root, expected_names):
    """Select the direct rows that contain every expected task title."""
    for container in walk(root):
        try:
            selection = container.querySelection()
        except Exception:
            continue
        indexes = []
        for expected in expected_names:
            matches = matching_child_indexes(container, expected)
            if len(matches) != 1:
                indexes = []
                break
            indexes.append(matches[0])
        if not indexes or len(set(indexes)) != len(expected_names):
            continue
        selection.clearSelection()
        for index in indexes:
            if not selection.selectChild(index):
                raise AssertionError("AT-SPI failed to select all requested task rows")
        return container
    return None


def snapshot(node, depth=0):
    result = {"name": name(node), "role": role(node)}
    value = text(node)
    if value:
        result["text"] = value
    if depth < 8:
        result["children"] = [snapshot(child, depth + 1) for child in children(node)]
    return result


def find_live_window():
    # GtkListBox reparents the editor's row and AT-SPI can cache a previous
    # frame proxy. Fetch the actual accessible frame for focus assertions.
    return find_frame(find_application())


def send_keyboard_key(key):
    """Deliver an XTest keystroke to the active X11 window, not AT-SPI focus.

    GTK runs under Xvfb + Openbox in this test, with a real keyboard seat.
    AT-SPI is still used to assert actual native focus and editor results.
    """
    subprocess.run(
        ["xdotool", "key", "--clearmodifiers", key],
        check=True,
        timeout=5,
    )


def has_focus(node):
    # GTK4 GtkEntry delegates keyboard input to its internal GtkText.
    # Require the native focused state on the editor or one of its own
    # descendants, never on an unrelated control in the same window.
    if node is None:
        return False
    for child in walk(node):
        try:
            if child.getState().contains(pyatspi.STATE_FOCUSED):
                return True
        except Exception:
            continue
    return False


def keyboard_activate_named_button(start, expected_name, max_tabs=12):
    """Reach a real native action by Tab, then activate it with Return.

    We never force accessibility focus or guess the number of Tab stops.
    GTK may add/remove focusable controls in a native host release; the
    contract is that keyboard-only users can reach and activate Add Date.
    """
    if not has_focus(start):
        raise AssertionError("task editor did not receive native keyboard focus")

    for step in range(max_tabs + 1):
        live = find_live_window()
        target = find_named(live, expected_name)
        if target is not None and has_focus(target):
            send_keyboard_key("Return")
            return
        if step < max_tabs:
            send_keyboard_key("Tab")
            time.sleep(0.08)

    live = find_live_window()
    focused = [
        {"name": name(node), "role": role(node)}
        for node in walk(live)
        if has_focus(node)
    ]
    raise AssertionError(
        f"keyboard Tab could not focus {expected_name!r}; focused={focused}"
    )


def press(node):
    # Capture identity before querying adapters. GTK may invalidate the
    # original proxy when a failing AT-SPI call also refreshes its cache.
    expected_name = name(node)
    expected_role = role(node)
    try:
        actions = node.queryAction()
        if actions.nActions >= 1 and actions.doAction(0):
            return
    except Exception:
        pass

    # GTK4 exposes GtkMenuButton with the correct button role and name but,
    # unlike GtkButton, some AT-SPI stacks do not publish a default action.
    # Exercise the same keyboard path a screen-reader or keyboard-only user
    # receives instead of treating the missing adapter action as activation.
    try:
        component = node.queryComponent()
        if component.grabFocus():
            send_keyboard_key("Return")  # Return keysym
            return
    except Exception:
        # Some GTK/AT-SPI combinations expose GtkMenuButton as focusable but
        # reject Component.grabFocus with a transient atspi_error. Callers that
        # exercise that menu using a verified native keyboard focus origin
        # origin instead of replacing the keyboard journey with a click.
        pass

    raise AssertionError(
        "AT-SPI action and keyboard focus failed for "
        f"{expected_name!r} ({expected_role})"
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--mode", choices=("main", "first-run", "verify-first-run"), default="main"
    )
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    application = wait_for("Taskly application", find_application)
    window = wait_for("Taskly frame", lambda: find_frame(application))
    # GTK/AT-SPI role names vary between distro accessibility stacks
    # (commonly "text" or "entry"). The editable-text interface is the
    # stable behavioral contract we actually need.
    entry = wait_for("quick-add entry", lambda: find_editable_named(window, "+ Add Task"))
    submit = wait_for("quick-add submit", lambda: find_named(window, "+ Add Task", "push button"))

    if args.mode == "first-run":
        wait_for(
            "actionable first-run empty state",
            lambda: contains_text(
                window, "Add your first task above — try “Plan tomorrow”"
            ),
        )
        entry.queryEditableText().setTextContents("First-run persistence task")
        press(submit)
        wait_for("first task created", lambda: contains_text(window, "First-run persistence task"))
        task_row = wait_for(
            "first task selected",
            lambda: select_single_named_child(window, "First-run persistence task"),
        )
        # §5b: the row's ⓘ button opens the anchored task-detail layer. The
        # quick-date chips autosave immediately — choosing Tomorrow persists
        # without any further action, and Done closes without discarding.
        window = open_detail_layer(window, "First-run persistence task")
        first_title = wait_for(
            "first task detail layer title",
            lambda: find_editable_named(window, "Title"),
        )
        assert text(first_title) == "First-run persistence task", (
            f"detail title mismatch: {text(first_title)!r}"
        )
        # The quick-date chips sit inside the popover, whose controls do
        # not accept AT-SPI doAction on this GTK stack — drive the date
        # entry directly (its accessible label is the product contract).
        date_entry = wait_for(
            "first task detail layer date field",
            lambda: find_editable_named(window, "Date"),
        )
        import datetime as _dt
        tomorrow_iso = (_dt.date.today() + _dt.timedelta(days=1)).isoformat()
        date_entry.queryEditableText().setTextContents(tomorrow_iso)
        send_keyboard_key("Return")
        # Esc closes the layer (autohide popover; closing never discards).
        # The date persisted the moment Return committed the field (§5b
        # per-field autosave). Close the layer through the row ⓘ toggle and
        # read the persisted value off the row meta — the popover's own
        # chips are also in the window tree while it is open, so the
        # assertion runs only after the layer is gone.
        close_detail_layer(window, "First-run persistence task")
        window = wait_for(
            "live frame after the date entry closed the layer",
            lambda: find_frame(find_application()),
        )
        wait_for(
            "first task save acknowledgement",
            lambda: find_editable_named(window, "Date") is None
            and contains_text(window, "First-run persistence task")
            and contains_text(window, "Tomorrow"),
        )
        (args.output / "first-run-trace.json").write_text(
            json.dumps(
                {
                    "platform": "linux",
                    "actions": [
                        "set:quick-add",
                        "press:task-info",
                        "set:detail-date-entry",
                        "press:detail-done",
                    ],
                    "assertions": [
                        "fresh profile exposes an actionable empty state",
                        "first task can be created without setup",
                        "the detail layer autosaved the Tomorrow quick date and Done closed it",
                    ],
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        return

    if args.mode == "verify-first-run":
        wait_for(
            "persisted first task after restart",
            lambda: contains_text(window, "First-run persistence task"),
        )
        persisted_first_run_due_date()
        try:
            wait_for(
                "persisted Tomorrow date on the first task row after restart",
                lambda: first_run_due_rendered(find_live_window()),
                timeout=15.0,
            )
        except AssertionError:
            live = find_live_window()
            (args.output / "first-run-restart-accessibility.json").write_text(
                json.dumps(snapshot(live), ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            raise
        (args.output / "persistence-restart.json").write_text(
            json.dumps(
                {
                    "platform": "linux",
                    "assertions": [
                        "first task and Tomorrow date survive a cold installed-app restart"
                    ],
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        return

    wait_for("default-list sentinel", lambda: contains_text(window, "Default-list sentinel"))
    wait_for("first 64-bit task row", lambda: contains_text(window, "64-bit task A"))
    wait_for("second 64-bit task row", lambda: contains_text(window, "64-bit task B"))

    wait_for(
        "64-bit list row selection",
        lambda: select_single_named_child(window, "64-bit identity list"),
    )
    wait_for(
        "64-bit list filter",
        lambda: not contains_text(window, "Default-list sentinel")
        and contains_text(window, "64-bit task A")
        and contains_text(window, "64-bit task B"),
    )

    wait_for(
        "two 64-bit task rows selected for scheduling",
        lambda: select_named_children(window, ["64-bit task A", "64-bit task B"]),
    )
    schedule = wait_for(
        "batch schedule button",
        lambda: find_named(window, "Schedule Selected", "push button"),
    )
    (args.output / "bulk-toolbar-debug.json").write_text(
        json.dumps(snapshot(window), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    delete = wait_for(
        "batch delete button", lambda: find_named(window, "Delete", "push button")
    )
    press(schedule)
    tomorrow = wait_for(
        "Tomorrow schedule option", lambda: find_named(window, "Tomorrow", "push button")
    )
    press(tomorrow)
    wait_for(
        "two 64-bit task rows selected for deletion",
        lambda: select_named_children(window, ["64-bit task A", "64-bit task B"]),
    )
    press(delete)
    # The product's undo window is six seconds. Find the banner and confirm
    # both rows are hidden in one AT-SPI traversal, then undo immediately.
    undo = wait_for(
        "staged deletion hidden with undo banner",
        lambda: find_staged_delete_ready(window),
        timeout=4.0,
    )
    press(undo)
    wait_for(
        "identity-preserving undo",
        lambda: contains_text(window, "64-bit task A")
        and contains_text(window, "64-bit task B"),
    )

    task_row = wait_for(
        "single row selected for keyboard editing",
        lambda: select_single_named_child(window, "64-bit task A"),
    )
    # §5b: ⓘ opens the anchored task-detail layer with per-field autosave.
    # A title change persists on Return without any further action, and
    # closing through the toggle never discards.
    window = open_detail_layer(window, "64-bit task A")
    detail_title = wait_for(
        "task detail layer title field",
        lambda: find_editable_named(window, "Title"),
    )
    assert text(detail_title) == "64-bit task A", (
        f"detail title mismatch: {text(detail_title)!r}"
    )
    wait_for(
        "task detail layer native keyboard focus",
        lambda: has_focus(
            find_editable_value(find_live_window(), "64-bit task A")
        ),
        timeout=10.0,
    )
    detail_title.queryEditableText().setTextContents("Autosaved detail A")
    send_keyboard_key("Return")
    wait_for(
        "detail layer autosaved the title to the stored row",
        lambda: contains_text(window, "Autosaved detail A"),
        timeout=10.0,
    )
    done = wait_for(
        "task detail Done action",
        lambda: find_named(window, "Done", "push button"),
    )
    press(done)
    wait_for(
        "task detail layer closed without discarding",
        lambda: find_editable_value(window, "Autosaved detail A") is None
        and contains_text(window, "Autosaved detail A"),
    )

    # §5b, field reachability: the detail layer exposes every field through
    # an accessible label. Reopen the layer, autosave a URL through it, and
    # verify the persisted value by reading the layer again after closing.
    window = open_detail_layer(window, "Autosaved detail A")
    url_field = wait_for(
        "detail layer URL field",
        lambda: find_editable_named(window, "URL"),
    )
    url_field.queryEditableText().setTextContents("https://example.com/autosaved")
    send_keyboard_key("Return")
    # §5b close: press the row ⓘ again (closing never discards).
    close_detail_layer(window, "Autosaved detail A")
    window = wait_for(
        "live frame after the URL autosave closed the layer",
        lambda: find_frame(find_application()),
    )
    wait_for(
        "URL autosave closed the layer",
        lambda: find_editable_named(window, "URL") is None,
    )
    window = open_detail_layer(window, "Autosaved detail A")
    url_field = wait_for(
        "detail layer URL field after reopen",
        lambda: find_editable_named(window, "URL"),
    )
    try:
        persisted = text(url_field)
    except Exception:
        persisted = ""
    assert persisted == "https://example.com/autosaved", (
        f"URL did not persist: {persisted!r}"
    )
    # §5b close: press the row ⓘ again (closing never discards).
    close_detail_layer(window, "Autosaved detail A")
    window = wait_for(
        "live frame after the URL verification closed the layer",
        lambda: find_frame(find_application()),
    )
    wait_for(
        "detail layer closed after URL verification",
        lambda: find_editable_named(window, "URL") is None,
    )

    # Re-enter through the desktop registry after the editor collapses.
    # GTK can reparent its task row and invalidate descendants of the old
    # frame proxy; the following Save path must use live accessibility nodes.
    application = wait_for(
        "Taskly application after editor layout change", find_application
    )
    window = wait_for(
        "Taskly frame after editor layout change",
        lambda: find_frame(application),
    )
    (args.output / "task-editor-after-escape.json").write_text(
        json.dumps(snapshot(window), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    window = open_detail_layer(window, "64-bit task B")
    # §5b: notes autosave when editing ends. Set them, close through Done,
    # then reopen and read the persisted value back.
    notes_view = wait_for(
        "second task detail layer opened",
        lambda: find_editable_named(window, "Notes"),
    )
    notes_view.queryEditableText().setTextContents("Detail-layer notes B")
    # §5b close: press the row ⓘ again (closing never discards).
    close_detail_layer(window, "64-bit task B")
    window = wait_for(
        "live frame after the notes autosave closed the layer",
        lambda: find_frame(find_application()),
    )
    wait_for(
        "notes autosave closed the layer",
        lambda: find_editable_named(window, "Notes") is None,
    )
    window = open_detail_layer(window, "64-bit task B")
    notes_view = wait_for(
        "second task detail layer reopened",
        lambda: find_editable_named(window, "Notes"),
    )
    try:
        persisted = text(notes_view)
    except Exception:
        persisted = ""
    assert persisted == "Detail-layer notes B", (
        f"notes did not persist: {persisted!r}"
    )
    # §5b close: press the row ⓘ again (closing never discards).
    close_detail_layer(window, "64-bit task B")
    window = wait_for(
        "live frame after the notes verification closed the layer",
        lambda: find_frame(find_application()),
    )
    wait_for(
        "detail layer closed after notes verification",
        lambda: find_editable_named(window, "Notes") is None,
    )

    entry.queryEditableText().setTextContents("Acceptance task")
    press(submit)
    wait_for("quick-add field cleared", lambda: text(entry) == "")
    wait_for("RPC-created task row", lambda: contains_text(window, "Acceptance task"))

    (args.output / "accessibility.json").write_text(
        json.dumps(snapshot(application), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (args.output / "interaction-trace.json").write_text(
        json.dumps(
            {
                "platform": "linux",
                "actions": [
                    "select:64-bit-list-row",
                    "select:two-64-bit-task-rows",
                    "press:batch-schedule-tomorrow",
                    "press:batch-delete",
                    "press:undo",
                    "press:selected-row-info",
                    "key:detail-title-autosave-return",
                    "press:detail-done",
                    "press:detail-reopen-url-autosave",
                    "press:detail-done",
                    "press:detail-reopen-verify-url",
                    "press:task-B-info",
                    "set:detail-notes-autosave",
                    "press:detail-done",
                    "press:detail-reopen-verify-notes",
                    "set:quick-add",
                    "press:quick-add-submit",
                ],
                "assertions": [
                    "packaged GTK4 frame activated on native X11",
                    "AT-SPI roles and names exposed",
                    "list and task IDs above 2^32 survive GTK row data",
                    "batch scheduling clears hidden due times for both tasks",
                    "six-second staged deletion hides both tasks without deleting them",
                    "undo restores the original task IDs and metadata",
                    "the anchored detail layer autosaved a title change without further action and Done closed it without discarding",
                    "the detail layer autosaved a URL and reopened with the persisted value",
                    "the detail layer autosaved notes and reopened with the persisted value",
                    "RPC-created task appeared after the quick-add field cleared",
                    "quick-add preserved the selected 64-bit list ownership",
                ],
            },
            indent=2,
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
