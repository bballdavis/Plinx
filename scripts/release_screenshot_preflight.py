#!/usr/bin/env python3
"""Fail-closed validation for a local, curated Plex screenshot session.

This tool deliberately accepts a small YAML subset so release tooling does not
need a third-party YAML dependency. It never prints credential values or server
addresses. Network verification is opt-in and is only reached by the capture
script after static validation succeeds.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


REQUIRED_TOP_LEVEL = {
    "schema_version",
    "locale",
    "maximum_movie_rating",
    "maximum_tv_rating",
    "exclude_unrated",
    "detail_rating_key",
    "playback_rating_key",
    "search_query",
    "approved_libraries",
    "approved_items",
    "forbidden_strings",
}
PLACEHOLDER_RE = re.compile(r"(?:placeholder|changeme|example|replace|your[-_ ]|<[^>]+>)", re.I)
ALLOWED_ARTWORK = {"portrait", "landscape"}
ALLOWED_MOVIE_RATINGS = {"G", "PG"}
ALLOWED_TV_RATINGS = {"TV-Y", "TV-Y7", "TV-G", "TV-PG"}


class PreflightError(ValueError):
    pass


def scalar(value: str) -> object:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    if value == "true":
        return True
    if value == "false":
        return False
    if value.isdigit():
        return int(value)
    return value


def parse_selection(path: Path) -> dict[str, object]:
    """Parse the documented, indentation-only selection format."""
    if not path.is_file():
        raise PreflightError("selection file is missing")

    result: dict[str, object] = {}
    active_list: str | None = None
    active_item: dict[str, object] | None = None
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if "\t" in line:
            raise PreflightError(f"selection line {line_number} uses a tab")
        indent = len(line) - len(line.lstrip(" "))
        text = line.strip()
        if indent == 0:
            if ":" not in text:
                raise PreflightError(f"selection line {line_number} is malformed")
            key, value = (part.strip() for part in text.split(":", 1))
            if key in result:
                raise PreflightError(f"selection repeats {key}")
            if value:
                result[key] = scalar(value)
                active_list = None
                active_item = None
            else:
                result[key] = []
                active_list = key
                active_item = None
            continue
        if active_list is None or not isinstance(result.get(active_list), list):
            raise PreflightError(f"selection line {line_number} is outside a list")
        if text.startswith("- "):
            entry = text[2:].strip()
            if active_list == "forbidden_strings":
                if not entry:
                    raise PreflightError(f"selection line {line_number} has an empty forbidden string")
                result[active_list].append(scalar(entry))
                active_item = None
                continue
            if ":" not in entry:
                raise PreflightError(f"selection line {line_number} needs a key/value")
            key, value = (part.strip() for part in entry.split(":", 1))
            active_item = {key: scalar(value)}
            result[active_list].append(active_item)
            continue
        if active_item is None or ":" not in text:
            raise PreflightError(f"selection line {line_number} is malformed")
        key, value = (part.strip() for part in text.split(":", 1))
        if key in active_item:
            raise PreflightError(f"selection line {line_number} repeats {key}")
        active_item[key] = scalar(value)
    return result


def require_nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or PLACEHOLDER_RE.search(value):
        raise PreflightError(f"{label} must be a non-placeholder string")
    return value.strip()


def validate_selection(selection: dict[str, object]) -> None:
    missing = REQUIRED_TOP_LEVEL - set(selection)
    unknown = set(selection) - REQUIRED_TOP_LEVEL
    if missing:
        raise PreflightError(f"selection is missing required fields: {', '.join(sorted(missing))}")
    if unknown:
        raise PreflightError(f"selection has unknown fields: {', '.join(sorted(unknown))}")
    if selection["schema_version"] != 1:
        raise PreflightError("selection schema_version must be 1")
    locale = require_nonempty_string(selection["locale"], "locale")
    if not re.fullmatch(r"[A-Za-z]{2,3}_[A-Za-z]{2}", locale):
        raise PreflightError("locale must be language_COUNTRY, for example en_US")
    if selection["maximum_movie_rating"] not in ALLOWED_MOVIE_RATINGS:
        raise PreflightError("maximum_movie_rating must be G or PG")
    if selection["maximum_tv_rating"] not in ALLOWED_TV_RATINGS:
        raise PreflightError("maximum_tv_rating exceeds the release capture ceiling")
    if selection["exclude_unrated"] is not True:
        raise PreflightError("exclude_unrated must be true")

    libraries = selection["approved_libraries"]
    items = selection["approved_items"]
    forbidden = selection["forbidden_strings"]
    if not isinstance(libraries, list) or not libraries:
        raise PreflightError("approved_libraries must be a non-empty list")
    if not isinstance(items, list) or not items:
        raise PreflightError("approved_items must be a non-empty list")
    if not isinstance(forbidden, list) or not forbidden:
        raise PreflightError("forbidden_strings must be a non-empty list")

    library_ids: set[str] = set()
    for library in libraries:
        if not isinstance(library, dict) or set(library) != {"id", "title"}:
            raise PreflightError("each approved library must contain exactly id and title")
        library_id = require_nonempty_string(library["id"], "approved library id")
        require_nonempty_string(library["title"], "approved library title")
        if library_id in library_ids:
            raise PreflightError("approved library ids must be unique")
        library_ids.add(library_id)

    rating_keys: set[str] = set()
    for item in items:
        if not isinstance(item, dict) or set(item) != {
            "rating_key", "library_id", "content_rating", "artwork_kind"
        }:
            raise PreflightError("each approved item must contain rating_key, library_id, content_rating, artwork_kind")
        rating_key = require_nonempty_string(item["rating_key"], "approved item rating_key")
        if rating_key in rating_keys:
            raise PreflightError("approved item rating_keys must be unique")
        rating_keys.add(rating_key)
        if item["library_id"] not in library_ids:
            raise PreflightError("approved item references an unknown library")
        rating = item["content_rating"]
        if rating not in ALLOWED_MOVIE_RATINGS | ALLOWED_TV_RATINGS:
            raise PreflightError("approved item content_rating exceeds the release capture ceiling")
        if item["artwork_kind"] not in ALLOWED_ARTWORK:
            raise PreflightError("approved item artwork_kind must be portrait or landscape")

    detail_key = require_nonempty_string(selection["detail_rating_key"], "detail_rating_key")
    playback_key = require_nonempty_string(selection["playback_rating_key"], "playback_rating_key")
    require_nonempty_string(selection["search_query"], "search_query")
    if detail_key not in rating_keys or playback_key not in rating_keys:
        raise PreflightError("detail and playback selectors must reference approved item rating_keys")

    for value in forbidden:
        require_nonempty_string(value, "forbidden string")


def load_credentials(path: Path) -> tuple[str, str]:
    if not path.is_file():
        raise PreflightError("credentials file is missing")
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if key not in {"PLINX_PLEX_SERVER_URL", "PLINX_PLEX_TOKEN"}:
            continue
        values[key] = str(scalar(value))
    server = require_nonempty_string(values.get("PLINX_PLEX_SERVER_URL"), "PLINX_PLEX_SERVER_URL")
    token = require_nonempty_string(values.get("PLINX_PLEX_TOKEN"), "PLINX_PLEX_TOKEN")
    parsed = urllib.parse.urlparse(server)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise PreflightError("PLINX_PLEX_SERVER_URL must be an absolute HTTP(S) URL")
    return server.rstrip("/"), token


def request_json(url: str, token: str) -> dict:
    request = urllib.request.Request(url, headers={"X-Plex-Token": token, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=20) as response:  # noqa: S310 - dedicated local endpoint supplied by parent
        payload = json.loads(response.read())
    if not isinstance(payload, dict):
        raise PreflightError("Plex preflight received an invalid response")
    return payload


def verify_artwork(server: str, token: str, artwork: str, kind: object) -> None:
    if kind == "portrait":
        width, height = 480, 720
    else:
        width, height = 640, 360
    query = urllib.parse.urlencode({"url": artwork, "width": width, "height": height})
    request = urllib.request.Request(
        f"{server}/photo/:/transcode?{query}",
        headers={"X-Plex-Token": token, "Accept": "image/*"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:  # noqa: S310 - dedicated endpoint supplied by parent
        header = response.read(16)
        content_type = response.headers.get_content_type()
    is_image = content_type.startswith("image/") and (
        header.startswith(b"\x89PNG\r\n\x1a\n")
        or header.startswith(b"\xff\xd8\xff")
        or header[:4] == b"RIFF" and header[8:12] == b"WEBP"
    )
    if not is_image:
        raise PreflightError("approved capture item artwork did not return a supported image")


def visible_text(item: dict) -> str:
    parts: list[str] = []
    for key in ("title", "summary", "tagline", "studio", "grandparentTitle", "parentTitle"):
        value = item.get(key)
        if isinstance(value, str):
            parts.append(value)
    return "\n".join(parts).casefold()


def library_inventory(server: str, token: str, library_id: str) -> dict[str, dict]:
    """Return the complete top-level inventory for one capture library."""
    start = 0
    page_size = 200
    inventory: dict[str, dict] = {}
    while True:
        query = urllib.parse.urlencode(
            {
                "X-Plex-Container-Start": start,
                "X-Plex-Container-Size": page_size,
            }
        )
        response = request_json(
            f"{server}/library/sections/{urllib.parse.quote(library_id, safe='')}/all?{query}",
            token,
        )
        container = response.get("MediaContainer", {})
        metadata = container.get("Metadata", [])
        if not isinstance(metadata, list):
            raise PreflightError("approved capture library returned an invalid inventory")
        for item in metadata:
            if not isinstance(item, dict) or not item.get("ratingKey"):
                raise PreflightError("approved capture library contains an unidentified item")
            rating_key = str(item["ratingKey"])
            if rating_key in inventory:
                raise PreflightError("approved capture library inventory contains duplicate items")
            inventory[rating_key] = item
        start += len(metadata)
        total = container.get("totalSize", container.get("size", start))
        if not isinstance(total, int):
            raise PreflightError("approved capture library returned an invalid item count")
        if not metadata or start >= total:
            return inventory


def verify_live(selection: dict[str, object], server: str, token: str) -> None:
    libraries_response = request_json(f"{server}/library/sections/all", token)
    directories = libraries_response.get("MediaContainer", {}).get("Directory", [])
    if not isinstance(directories, list):
        raise PreflightError("Plex library response has no directory list")
    expected_libraries = {str(entry["id"]): str(entry["title"]) for entry in selection["approved_libraries"]}  # type: ignore[index]
    actual_libraries = {str(entry.get("key")): str(entry.get("title")) for entry in directories if isinstance(entry, dict)}
    if actual_libraries != expected_libraries:
        raise PreflightError("live server libraries do not exactly match the approved capture selection")

    forbidden = [str(value).casefold() for value in selection["forbidden_strings"]]  # type: ignore[index]
    if any(value in title.casefold() for title in actual_libraries.values() for value in forbidden):
        raise PreflightError("approved capture library metadata contains a forbidden string")

    approved_by_library: dict[str, set[str]] = {
        library_id: set() for library_id in expected_libraries
    }
    for approved in selection["approved_items"]:  # type: ignore[index]
        assert isinstance(approved, dict)
        approved_by_library[str(approved["library_id"])].add(str(approved["rating_key"]))

    for library_id, approved_keys in approved_by_library.items():
        inventory = library_inventory(server, token, library_id)
        if set(inventory) != approved_keys:
            raise PreflightError(
                "live capture library inventory does not exactly match approved item identities"
            )
        for item in inventory.values():
            text = visible_text(item)
            if any(value in text for value in forbidden):
                raise PreflightError("approved capture library item contains a forbidden string")

    for approved in selection["approved_items"]:  # type: ignore[index]
        item_selection = approved
        assert isinstance(item_selection, dict)
        rating_key = str(item_selection["rating_key"])
        response = request_json(f"{server}/library/metadata/{urllib.parse.quote(rating_key, safe='')}", token)
        metadata = response.get("MediaContainer", {}).get("Metadata", [])
        if not isinstance(metadata, list) or len(metadata) != 1 or not isinstance(metadata[0], dict):
            raise PreflightError("an approved capture item was missing or ambiguous")
        item = metadata[0]
        if str(item.get("ratingKey")) != rating_key:
            raise PreflightError("live server returned an unexpected capture item")
        if str(item.get("librarySectionID")) != str(item_selection["library_id"]):
            raise PreflightError("approved capture item is in an unexpected library")
        if item.get("contentRating") != item_selection["content_rating"]:
            raise PreflightError("approved capture item rating does not match the selection")
        artwork = item.get("thumb") if item_selection["artwork_kind"] == "portrait" else item.get("art") or item.get("thumb")
        if not isinstance(artwork, str) or not artwork.startswith("/"):
            raise PreflightError("approved capture item has no usable Plex artwork path")
        verify_artwork(server, token, artwork, item_selection["artwork_kind"])
        text = visible_text(item)
        if any(value in text for value in forbidden):
            raise PreflightError("approved capture metadata contains a forbidden string")

    approved_keys = {
        str(item["rating_key"])
        for item in selection["approved_items"]  # type: ignore[index]
        if isinstance(item, dict)
    }
    search_query = urllib.parse.urlencode({"query": selection["search_query"]})
    search_response = request_json(f"{server}/search?{search_query}", token)
    search_items = search_response.get("MediaContainer", {}).get("Metadata", [])
    if not isinstance(search_items, list) or not search_items:
        raise PreflightError("approved release search query returned no media")
    search_keys = {
        str(item.get("ratingKey"))
        for item in search_items
        if isinstance(item, dict) and item.get("ratingKey")
    }
    if not search_keys or not search_keys.issubset(approved_keys):
        raise PreflightError("approved release search query returned unapproved media")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selection", required=True, type=Path)
    parser.add_argument("--credentials", type=Path)
    parser.add_argument("--verify-live", action="store_true")
    parser.add_argument(
        "--print-value",
        choices=(
            "locale",
            "maximum_movie_rating",
            "maximum_tv_rating",
            "detail_rating_key",
            "playback_rating_key",
            "search_query",
        ),
        help="print one validated, non-secret launch setting",
    )
    args = parser.parse_args()
    try:
        selection = parse_selection(args.selection)
        validate_selection(selection)
        if args.verify_live:
            if args.credentials is None:
                raise PreflightError("--verify-live requires --credentials")
            server, token = load_credentials(args.credentials)
            verify_live(selection, server, token)
    except (OSError, PreflightError, ValueError, json.JSONDecodeError, urllib.error.URLError) as error:
        print(f"release screenshot preflight failed: {error}", file=sys.stderr)
        return 1
    if args.print_value:
        print(selection[args.print_value])
    else:
        print("release screenshot preflight passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
