"""The reading borrowed from another provider is matched on the text, so the
matching itself is what is worth pinning: no network, no providers involved.

Run: python3 -m unittest discover -s tests/lyrics -p 'test_*.py'
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lyrics"))

import lyrics  # noqa: E402


def line(text, reading=None, words=None, time=0.0):
    return {"time": time, "text": text, "words": words or [], "reading": reading}


class NormTests(unittest.TestCase):
    def test_spacing_and_width_do_not_matter(self):
        # Unison puts a space around every word it times; NetEase writes the
        # line as one run. Both are the same lyric.
        self.assertEqual(lyrics._norm_lyric_text("光 まとって"),
                         lyrics._norm_lyric_text("光まとって"))
        self.assertEqual(lyrics._norm_lyric_text("ＡＢＣ １２３"), "abc123")

    def test_parenthetical_marks_go_away(self):
        self.assertEqual(lyrics._norm_lyric_text("ラララ (コーラス)"), "ラララ")
        self.assertEqual(lyrics._norm_lyric_text("C'est fini!"), "cestfini")

    def test_punctuation_and_spaces_are_not_letters(self):
        self.assertEqual(lyrics._norm_lyric_text("  -- ?? "), "")


class GapTests(unittest.TestCase):
    def test_only_lines_that_are_not_their_own_reading_want_one(self):
        lines = [line("光 まとって"), line("Mon amie"), line("사랑해"),
                 line("今 開いて", "i ma hi ra i te")]
        self.assertEqual([l["text"] for l in lyrics._reading_gaps(lines)],
                         ["光 まとって"])


class MergeTests(unittest.TestCase):
    def test_reading_crosses_a_different_split_of_the_line(self):
        ours = [line("私 夜 を 越えてゆく よ", words=[{"time": 3.3, "text": "私"}])]
        theirs = [line("私夜を越えてゆくよ", "wa ta shi yo ru wo ko e te yu ku yo", time=9.1)]
        self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 1)
        self.assertEqual(ours[0]["reading"], "wa ta shi yo ru wo ko e te yu ku yo")

    def test_timestamps_are_ignored_entirely(self):
        # Two masters a minute apart still hold the same words.
        ours = [line("光 まとって", time=0.2)]
        theirs = [line("光まとって", "hi ka ri ma to tte", time=61.7)]
        self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 1)

    def test_one_of_ours_may_be_several_of_theirs(self):
        ours = [line("あいう えお")]
        theirs = [line("あいう", "a i u"), line("えお", "e o")]
        self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 1)
        self.assertEqual(ours[0]["reading"], "a i u e o")

    def test_a_run_longer_than_the_limit_is_not_guessed(self):
        ours = [line("あいう えお かきく")]
        theirs = [line("あいう", "a i u"), line("えお", "e o"), line("かきく", "ka ki ku")]
        lyrics.MAX_JOIN = 2
        try:
            self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 0)
        finally:
            lyrics.MAX_JOIN = 4

    def test_a_line_that_already_has_one_keeps_it(self):
        ours = [line("光 まとって", "ひかりまとって")]
        theirs = [line("光まとって", "hi ka ri ma to tte")]
        self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 0)
        self.assertEqual(ours[0]["reading"], "ひかりまとって")

    def test_latin_lines_are_left_alone(self):
        ours = [line("Mon amie")]
        theirs = [line("Mon amie", "mo namie")]
        self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 0)

    def test_a_source_with_no_readings_adds_nothing(self):
        ours = [line("光 まとって")]
        self.assertEqual(lyrics._merge_readings_by_text(ours, [line("光まとって")]), 0)

    def test_the_first_of_two_agreeing_sources_wins(self):
        ours = [line("ボンボン")]
        theirs = [line("ボンボン", "bo n bo n"), line("ボンボン", "bon bon")]
        self.assertEqual(lyrics._merge_readings_by_text(ours, theirs), 1)
        self.assertEqual(ours[0]["reading"], "bo n bo n")


if __name__ == "__main__":
    unittest.main()
