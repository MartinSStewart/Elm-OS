"""The test facts Elm OS writes to the serial log with ELMOS_TEST=1 on the kernel's
command line, for the QEMU tests to check instead of reading the screen.

Main.testFacts (elm/src/Main.elm) says which there are. Each is a line

    [elm] test <name> <JSON>

written whenever it changes, and all of them again each time the Elm program starts.
So the newest line for a name says how things are now. Buttons are clicked by their
text, at the place the "buttons" fact gives (text boxes by what is typed in them), so a test doesn't change when the UI's
look or layout does.
"""

import json
import re
import time

LINE = re.compile(r"^\[elm\] test (\w+) (.*)$", re.M)


class Facts:
    """`serial` gives the serial log so far, `fail` stops the test with a message, and
    `running` says whether QEMU is still running."""

    def __init__(self, serial, fail, running):
        self.serial, self.fail, self.running = serial, fail, running

    def mark(self):
        """Where the log is now: pass it as `since` to look only at what comes after."""
        return len(self.serial())

    def get(self, name, since=0):
        """The newest value of a fact (in the log after `since`), or None."""
        value = None
        for m in LINE.finditer(self.serial()[since:]):
            if m.group(1) == name:
                try:
                    value = json.loads(m.group(2))
                except ValueError:
                    pass  # another line landed in the middle of this one
        return value

    def wait(self, name, check, what, timeout=60, since=0):
        """Waits until the newest value of a fact passes `check`, and returns it. `what`
        says what the test is waiting for, for the message if it doesn't come."""
        end = time.time() + timeout
        while True:
            value = self.get(name, since)
            if value is not None and check(value):
                return value
            if not self.running():
                self.fail(f"QEMU exited while waiting for {what} (last {name}: {value!r})")
            if time.time() > end:
                self.fail(f"timed out waiting for {what} (last {name}: {value!r})")
            time.sleep(0.2)

    def button(self, label, timeout=30, text_box=False):
        """The middle of the button whose text is `label` (or has it in it, if `label`
        ends with "..."), in device pixels, once there is one. With text_box=True, the
        text box with that text typed in it instead."""
        def match(b):
            return b["textBox"] == text_box and (label[:-3] in b["label"] if label.endswith("...") else b["label"] == label)

        buttons = self.wait("buttons", lambda bs: any(match(b) for b in bs), f"a button {label!r}", timeout)
        found = next(b for b in buttons if match(b))
        return found["x"], found["y"]
