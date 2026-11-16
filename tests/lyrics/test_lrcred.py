"""lrc.red's hit matching and TTML reading, against what the host returned on
2026-10-04 (fixtures trimmed to the first few hits). No network.

Run: python3 -m unittest discover -s tests/lyrics -p 'test_*.py'
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "lyrics"))

import lyrics  # noqa: E402


BOHEMIAN_HITS = [
    {"isrc": "GBUM71100986",
     "title": "Bohemian Rhapsody (Operatic Section / 2011 A Cappella Mix)",
     "artist": "Queen", "duration": 64.969},
    {"isrc": "GBUM71029604", "title": "Bohemian Rhapsody (Remastered 2011)",
     "artist": "Queen", "duration": 356.52},
    {"isrc": "GBCEG0100046", "title": "Bohemian Rhapsody (Live)",
     "artist": "Queen", "duration": 352.04},
]

TUM_HI_HO_HITS = [
    {"isrc": "INS181303031", "title": 'Tum Hi Ho (From "Aashiqui 2")',
     "artist": "Arijit Singh", "duration": 261.974},
    {"isrc": "INS181303860", "title": "Tum Hi Ho (Remix)",
     "artist": "Arijit Singh", "duration": 237.338},
    {"isrc": "GB8KE2422340", "title": "Tum Hi Ho",
     "artist": "Imazee", "duration": 163.699},
]

# GET https://lrc.red/s/USUG11904206.ttml, one paragraph with its echo.
BLINDING_LIGHTS = """
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:lrc="http://lrc.red/lyric-ttml-internal"
 xmlns:ttm="http://www.w3.org/ns/ttml#metadata" lrc:timing="Word" xml:lang="en"><head><metadata>
<ttm:agent type="person" xml:id="v1"><ttm:name type="full">Vocal 1</ttm:name></ttm:agent>
</metadata></head><body dur="3:20.046">
<div begin="2:19.610" end="2:23.809" lrc:songPart="Verse"><p begin="2:19.610" end="2:23.809" lrc:key="L27" ttm:agent="v1"><span begin="2:19.610" end="2:19.899">I'm</span> <span begin="2:19.899" end="2:20.059">just</span> <span begin="2:20.059" end="2:20.353">calling</span> <span begin="2:20.353" end="2:20.726">back</span> <span begin="2:20.726" end="2:20.906">to</span> <span begin="2:20.906" end="2:21.228">let</span> <span begin="2:21.228" end="2:21.445">you</span> <span begin="2:21.445" end="2:22.261">know</span> <span ttm:role="x-bg"><span begin="2:21.720" end="2:22.154">(Back</span> <span begin="2:22.154" end="2:22.295">to</span> <span begin="2:22.295" end="2:22.706">let</span> <span begin="2:22.706" end="2:22.889">you</span> <span begin="2:22.889" end="2:23.809">know)</span></span></p></div>
</body></tt>
""".strip()


class BestTests(unittest.TestCase):
    def test_skips_the_a_cappella_mix_the_search_ranks_first(self):
        hit = lyrics._lrcred_best(BOHEMIAN_HITS, "Bohemian Rhapsody", "Queen", 355)
        self.assertEqual("GBUM71029604", hit["isrc"])

    def test_a_live_cut_close_in_length_is_still_not_the_studio_recording(self):
        live = lyrics._lrcred_best(BOHEMIAN_HITS, "Bohemian Rhapsody (Live)", "Queen", 352)
        self.assertEqual("GBCEG0100046", live["isrc"])
        self.assertIsNone(lyrics._lrcred_best(BOHEMIAN_HITS, "Bohemian Rhapsody", "Queen", 352))

    def test_a_soundtrack_credit_and_a_shared_artist_are_enough(self):
        hit = lyrics._lrcred_best(TUM_HI_HO_HITS, "Tum Hi Ho", "Mithoon, Arijit Singh", 262)
        self.assertEqual("INS181303031", hit["isrc"])

    def test_the_same_title_by_somebody_else_is_not_a_match(self):
        self.assertIsNone(lyrics._lrcred_best(TUM_HI_HO_HITS, "Tum Hi Ho", "Imazee Fan", 163))
        self.assertIsNone(lyrics._lrcred_best(TUM_HI_HO_HITS, "Tum Hi Ho", "Arijit Singh", 200))

    def test_only_a_well_formed_isrc_becomes_a_path(self):
        self.assertEqual("https://lrc.red/s/GBUM71029604.ttml",
                         lyrics._lrcred_document_url(" gbum71029604 "))
        self.assertIsNone(lyrics._lrcred_document_url("../search.json?q=x"))
        self.assertIsNone(lyrics._lrcred_document_url(""))


class TtmlTests(unittest.TestCase):
    def test_its_ttml_reads_as_word_timed_with_the_echo_kept_apart(self):
        line = lyrics.ttml_to_lrc(BLINDING_LIGHTS)[0]
        self.assertEqual("I'm just calling back to let you know", line["text"])
        self.assertTrue(line["words"])
        self.assertEqual(139.61, line["time"])
        self.assertEqual("(Back to let you know)", line["bg"]["text"])


if __name__ == "__main__":
    unittest.main()
