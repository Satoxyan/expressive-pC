"""What the widget receives for a background vocal: words, no brackets.

Run: python3 -m unittest discover -s tests/lyrics -p 'test_*.py'
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lyrics"))

import lyrics  # noqa: E402


def line_with_echo(text, words=()):
    return {"time": 1.0, "text": "can I get a kiss?",
            "bg": {"text": text,
                   "words": [{"t": float(i), "w": w} for i, w in enumerate(words)]}}


class PayloadEchoTest(unittest.TestCase):
    def test_brackets_dropped_from_text(self):
        self.assertEqual(lyrics._payload_line(line_with_echo("(can I?)"))["b"], "can I?")

    def test_full_width_brackets_dropped(self):
        self.assertEqual(lyrics._payload_line(line_with_echo("（Padamu）"))["b"], "Padamu")

    def test_each_folded_echo_unwrapped(self):
        payload = lyrics._payload_line(line_with_echo("(ooh) (ahh)"))
        self.assertEqual(payload["b"], "ooh ahh")

    def test_words_lose_their_edge_brackets(self):
        payload = lyrics._payload_line(
            line_with_echo("(Back to let you know)", ["(Back", "to", "let", "you", "know)"]))
        self.assertEqual([w for _, w in payload["bw"]], ["Back", "to", "let", "you", "know"])

    def test_unwrapped_echo_is_left_alone(self):
        self.assertEqual(lyrics._payload_line(line_with_echo("ooh ooh"))["b"], "ooh ooh")

    def test_line_without_echo_has_no_b(self):
        payload = lyrics._payload_line({"time": 1.0, "text": "hello"})
        self.assertNotIn("b", payload)


if __name__ == "__main__":
    unittest.main()
