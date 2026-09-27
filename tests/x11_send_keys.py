#!/usr/bin/env python3
"""Send named keys to a DOSBox X11 window for local smoke testing."""

import ctypes
import sys
import time


X11 = ctypes.CDLL("libX11.so.6")
XTST = ctypes.CDLL("libXtst.so.6")

X11.XOpenDisplay.restype = ctypes.c_void_p
X11.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
X11.XGetInputFocus.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_int)]
X11.XStringToKeysym.argtypes = [ctypes.c_char_p]
X11.XStringToKeysym.restype = ctypes.c_ulong
X11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X11.XKeysymToKeycode.restype = ctypes.c_uint
X11.XFlush.argtypes = [ctypes.c_void_p]
XTST.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]


def title(display: int, window: int) -> str:
    value = ctypes.c_char_p()
    if not X11.XFetchName(display, window, ctypes.byref(value)) or not value.value:
        return ""
    result = value.value.decode(errors="replace")
    return result


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: x11_send_keys.py KEY [KEY ...]", file=sys.stderr)
        return 2

    display = X11.XOpenDisplay(None)
    if not display:
        print("could not open X11 display", file=sys.stderr)
        return 1
    window = ctypes.c_ulong()
    revert_to = ctypes.c_int()
    X11.XGetInputFocus(display, ctypes.byref(window), ctypes.byref(revert_to))
    window_title = title(display, window.value)
    if "DIS" not in window_title and "DOSBox Staging" not in window_title:
        print(f"focused X11 window is not DOSBox: {window_title!r}", file=sys.stderr)
        return 1

    print(f"target: {window_title}")

    for key_name in sys.argv[1:]:
        keysym = X11.XStringToKeysym(key_name.encode())
        keycode = X11.XKeysymToKeycode(display, keysym)
        if not keysym or not keycode:
            print(f"unknown key: {key_name}", file=sys.stderr)
            return 2
        XTST.XTestFakeKeyEvent(display, keycode, True, 0)
        XTST.XTestFakeKeyEvent(display, keycode, False, 0)
        X11.XFlush(display)
        time.sleep(0.25)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
