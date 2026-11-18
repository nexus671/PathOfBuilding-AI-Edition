"""Guard clipping and alpha composition in the headless visual renderer."""
# cspell:ignore tobytes
import hashlib
import unittest

from render_headless_ui import hidden_text, render


def rectangle(x, y, width, height, clip, color, order):
    return {"kind": "rect", "x": x, "y": y, "width": width, "height": height,
            "clip": clip, "color": color, "layer": 0, "sublayer": 0,
            "order": order, "asset": False}


def text_command(order=1, sublayer=0):
    return {"kind": "text", "x": 10, "y": 10, "width": 40, "height": 12,
            "clip": [0, 0, 80, 80], "text": "^7Visible label",
            "layer": 0, "sublayer": sublayer, "order": order}


class HiddenTextTests(unittest.TestCase):
    def test_detects_a_card_background_drawn_over_a_label(self):
        background = rectangle(5, 5, 55, 25, [0, 0, 80, 80], [.1, .1, .1, 1], 2)
        self.assertEqual(["^7Visible label"], hidden_text([text_command(), background], 80, 80))
        self.assertEqual([], hidden_text([text_command(sublayer=1), background], 80, 80))

    def test_respects_transparency_clipping_textures_and_tooltips(self):
        background = rectangle(5, 5, 55, 25, [0, 0, 80, 80], [.1, .1, .1, 1], 2)
        self.assertEqual([], hidden_text([text_command(), {**background, "color": [.1, .1, .1, .5]}], 80, 80))
        self.assertEqual([], hidden_text([text_command(), {**background, "clip": [5, 5, 10, 10]}], 80, 80))
        self.assertEqual([], hidden_text([text_command(), {**background, "asset": "background.png"}], 80, 80))
        self.assertEqual([], hidden_text([text_command(), {**background, "sublayer": 100}], 80, 80))
        self.assertEqual([], hidden_text([text_command(), {**background, "width": 42}], 80, 80))


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
        self.assertFalse(any(audit[key] for key in ("lowContrast", "horizontalClipping", "controlClipping", "controlOverlaps", "hiddenText")))


if __name__ == "__main__":
    unittest.main()
