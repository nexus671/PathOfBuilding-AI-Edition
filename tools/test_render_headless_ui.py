"""Guard clipping and alpha composition in the headless visual renderer."""
# cspell:ignore tobytes
import hashlib
import unittest

from render_headless_ui import render


def rectangle(x, y, width, height, clip, color, order):
    return {"kind": "rect", "x": x, "y": y, "width": width, "height": height,
            "clip": clip, "color": color, "layer": 0, "sublayer": 0,
            "order": order, "asset": False}


class RectangleRenderingTests(unittest.TestCase):
    def test_fractional_clipped_and_translucent_rectangles(self):
        frame = {"width": 80, "height": 80, "commands": [
            rectangle(3.25, 4.75, 24.5, 21.25, [0, 0, 80, 80], [.2, .7, .4, 1], 1),
            rectangle(12.6, 15.4, 31.7, 18.2, [0, 0, 80, 80], [.8, .2, .1, .45], 2),
            rectangle(-8.39050059899784, -17.358892572280045, 50.55026484564442,
                      59.3007822171817, [42.46027743752519, 19.32071971781366,
                                         33.38361074541758, 40.52016750861736], [.7, .4, .8, .4], 3),
            rectangle(65.75, 62.25, 30.5, 26.5, [0, 0, 80, 80], [.1, .5, .9, 1], 4),
        ]}
        image, audit = render(frame)
        # Reference pixels were produced by the original full-window layers.
        self.assertEqual("928a3ff2b23423b647d8aadfad381cd1fe8133882ed5b226576a9df0175b002f",
                         hashlib.sha256(image.tobytes()).hexdigest())
        self.assertFalse(any(audit[key] for key in ("lowContrast", "horizontalClipping", "controlClipping", "controlOverlaps")))


if __name__ == "__main__":
    unittest.main()
