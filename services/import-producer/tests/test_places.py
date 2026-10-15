from producer.places import lookup

PLACES = [
    {"code": "US", "name": "United States", "type": "country"},
    {"code": "US-VA", "name": "Virginia", "type": "state"},
    {"code": "US-WV", "name": "West Virginia", "type": "state"},
    {"code": "US-OR", "name": "Oregon", "type": "state"},
    {"code": "MX", "name": "Mexico", "type": "country"},
    {"code": "MX-QUE", "name": "Querétaro", "type": "state"},
    {"code": "US-NM", "name": "New Mexico", "type": "state"},
]


def codes(results):
    return [r["code"] for r in results]


def test_exact_name_ranks_first():
    assert codes(lookup("Virginia", PLACES)) == ["US-VA", "US-WV"]


def test_case_and_accent_insensitive():
    assert codes(lookup("queretaro", PLACES)) == ["MX-QUE"]


def test_code_lookup():
    assert codes(lookup("us-or", PLACES)) == ["US-OR"]


def test_results_name_their_country():
    [virginia, *_] = lookup("Virginia", PLACES)
    assert virginia["country"] == "United States"
    [mexico] = [r for r in lookup("Mexico", PLACES) if r["code"] == "MX"]
    assert mexico["country"] == "Mexico"


def test_no_match_returns_empty():
    assert lookup("Atlantis", PLACES) == []
