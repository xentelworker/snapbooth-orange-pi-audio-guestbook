"""
Minimal RPi.GPIO compatibility layer for Orange Pi PC.
Uses libgpiod v2 and /dev/gpiochip0.
Designed for rotary-phone-audio-guestbook.
"""

import gpiod
from gpiod.line import Direction, Bias, Value

# RPi.GPIO-compatible constants
BCM = 11
IN = 1
OUT = 0

LOW = 0
HIGH = 1

PUD_OFF = 20
PUD_DOWN = 21
PUD_UP = 22

_chip_path = "/dev/gpiochip0"
_requests = {}


def setmode(mode):
    if mode != BCM:
        raise ValueError("Orange Pi compatibility layer only supports BCM-style line numbers")


def setwarnings(flag):
    pass


def setup(pin, mode, pull_up_down=PUD_OFF):
    if mode != IN:
        raise NotImplementedError("Only GPIO input mode is currently supported")

    if pin in _requests:
        _requests[pin].release()
        del _requests[pin]

    if pull_up_down == PUD_UP:
        bias = Bias.PULL_UP
    elif pull_up_down == PUD_DOWN:
        bias = Bias.PULL_DOWN
    else:
        bias = Bias.DISABLED

    request = gpiod.request_lines(
        _chip_path,
        consumer="audio-guestbook",
        config={
            pin: gpiod.LineSettings(
                direction=Direction.INPUT,
                bias=bias,
            )
        },
    )

    _requests[pin] = request


def input(pin):
    if pin not in _requests:
        raise RuntimeError(f"GPIO line {pin} has not been configured")

    value = _requests[pin].get_value(pin)

    return HIGH if value == Value.ACTIVE else LOW


def cleanup(pin=None):
    if pin is not None:
        request = _requests.pop(pin, None)
        if request is not None:
            request.release()
        return

    for request in list(_requests.values()):
        try:
            request.release()
        except Exception:
            pass

    _requests.clear()
