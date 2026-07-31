#!/usr/bin/env python3
"""Local, credential-free Plex and Youtarr fixture service for screenshots."""

from __future__ import annotations

import argparse
import functools
import hashlib
import json
import struct
import urllib.parse
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


MOVIES = [
    ("moonbound", "Moonbound", "PG", 2026, "A family science adventure."),
    ("cloud-chasers", "Cloud Chasers", "PG", 2025, "Young weather watchers follow a summer storm."),
    ("big-build", "The Big Build", "PG", 2024, "Friends transform an empty lot into a community workshop."),
    ("hidden-gardens", "Hidden Gardens", "G", 2023, "A gentle tour of surprising gardens around the world."),
    ("robot-club", "Robot Club", "PG", 2026, "A school robotics team learns to build together."),
    ("lighthouse-map", "The Lighthouse Map", "PG", 2025, "Siblings follow clues along a quiet coast."),
    ("paper-airship", "The Paper Airship", "G", 2024, "A classroom invention takes an unexpected journey."),
    ("river-trail", "The River Trail", "PG", 2026, "Friends learn to read a landscape together."),
]

SHOWS = [
    ("space-camp", "Space Camp", "TV-PG", 2026, "Young explorers train for a mission beyond Earth."),
    ("kitchen-lab", "Kitchen Lab", "TV-G", 2025, "Every recipe becomes a friendly science experiment."),
    ("wild-neighbors", "Wild Neighbors", "TV-PG", 2024, "Families discover the animals living close to home."),
    ("makers-next-door", "Makers Next Door", "TV-G", 2025, "Creative neighbors share practical projects."),
    ("junior-rangers", "Junior Rangers", "TV-G", 2026, "Young naturalists care for a neighborhood park."),
    ("story-station", "Story Station", "TV-PG", 2025, "A book club turns stories into weekend adventures."),
    ("music-room", "The Music Room", "TV-G", 2024, "Friends explore instruments and sounds."),
    ("market-day", "Market Day", "TV-PG", 2026, "A community market becomes a lesson in teamwork."),
]

OTHER_VIDEOS = [
    ("bridge-basics", "How Bridges Work", "PG", 2026, "A friendly look at bridge design."),
    ("backyard-sky", "Backyard Astronomy", "PG", 2026, "A beginner guide to the night sky."),
    ("tiny-garden", "Make a Tiny Garden", "G", 2026, "A small growing project for families."),
    ("science-sound", "The Science of Sound", "PG", 2026, "Experiments with rhythm and vibration."),
    ("friendly-dragons", "Drawing Friendly Dragons", "G", 2026, "A playful step-by-step drawing lesson."),
    ("bird-feeder", "Build a Bird Feeder", "G", 2026, "A simple project for welcoming backyard birds."),
    ("cloud-journal", "Start a Cloud Journal", "PG", 2026, "Learn to notice and record changing skies."),
    ("paper-circuits", "Make a Paper Circuit", "PG", 2026, "Light up a drawing with a beginner circuit."),
    ("bread-science", "The Science of Bread", "G", 2026, "See how simple ingredients change as dough rises."),
    ("map-compass", "Maps and Compasses", "PG", 2026, "Practice basic navigation on a family walk."),
]

YOUTARR_VIDEOS = [
    ("bridge-basics", "How Bridges Work", "Curious Workshop", "TV-G", 402),
    ("backyard-sky", "Backyard Astronomy", "Sky Club", "TV-PG", 615),
    ("tiny-garden", "Make a Tiny Garden", "Green Things", "TV-G", 488),
    ("science-sound", "The Science of Sound", "Everyday Lab", "TV-PG", 532),
    ("friendly-dragons", "Drawing Friendly Dragons", "Art Table", "TV-Y7", 721),
    ("bird-feeder", "Build a Bird Feeder", "Curious Workshop", "TV-G", 574),
    ("cloud-journal", "Start a Cloud Journal", "Weather Watch", "TV-G", 446),
    ("paper-circuits", "Make a Paper Circuit", "Circuit Corner", "TV-PG", 638),
    ("bread-science", "The Science of Bread", "Kitchen Lab", "TV-G", 509),
    ("map-compass", "Maps and Compasses", "Trail Guides", "TV-PG", 682),
    ("shadow-theater", "Build a Shadow Theater", "Art Table", "TV-Y7", 592),
    ("pond-watch", "Life in a Small Pond", "Green Things", "TV-G", 557),
]

YOUTARR_CHANNELS = [
    ("Curious Workshop", "Hands-on engineering for families"),
    ("Sky Club", "Friendly guides to the night sky"),
    ("Green Things", "Small projects for growing minds"),
    ("Everyday Lab", "Science hiding in ordinary places"),
    ("Art Table", "Drawing and making for every skill level"),
    ("Weather Watch", "Simple ways to observe weather"),
    ("Circuit Corner", "Friendly introductions to electronics"),
    ("Kitchen Lab", "Food experiments for curious families"),
    ("Trail Guides", "Outdoor skills for neighborhood explorers"),
]


def plex_item(
    slug: str,
    title: str,
    rating: str,
    year: int,
    summary: str,
    item_type: str = "movie",
    view_offset: int | None = None,
    library_section_id: int | None = None,
) -> dict:
    duration = 6_120_000 if item_type == "movie" else 1_560_000
    item = {
        "ratingKey": slug,
        "key": f"/library/metadata/{slug}",
        "guid": f"plex://fixture/{slug}",
        "librarySectionID": library_section_id or (1 if item_type == "movie" else 2),
        "type": item_type,
        "title": title,
        "summary": summary,
        "thumb": f"/artwork/poster/{slug}.png",
        "art": f"/artwork/backdrop/{slug}.png",
        "year": year,
        "duration": duration,
        "contentRating": rating,
        "studio": "Plinx Fixture Studio",
        "tagline": "Curiosity starts close to home.",
        "audienceRating": 8.4,
        "rating": 8.1,
        "Genre": [{"tag": "Family"}, {"tag": "Adventure"}],
        "Role": [
            {"id": 1, "tag": "Avery North"},
            {"id": 2, "tag": "Jordan Vale"},
        ],
        "Media": [{"id": 1, "videoResolution": "1080", "Part": []}],
    }
    if view_offset is not None:
        item["viewOffset"] = view_offset
    if item_type == "show":
        item["childCount"] = 2
        item["leafCount"] = 12
        item["viewedLeafCount"] = 2
    return item


def plex_items(
    records: list[tuple],
    item_type: str,
    library_section_id: int | None = None,
) -> list[dict]:
    return [
        plex_item(
            *record,
            item_type=item_type,
            library_section_id=library_section_id,
        )
        for record in records
    ]


MOVIE_ITEMS = plex_items(MOVIES, "movie")
SHOW_ITEMS = plex_items(SHOWS, "show")
OTHER_VIDEO_ITEMS = plex_items(OTHER_VIDEOS, "movie", library_section_id=3)
for item in OTHER_VIDEO_ITEMS:
    item["thumb"] = f"/artwork/video/{item['ratingKey']}.png"
    item["art"] = item["thumb"]
ALL_ITEMS = {
    item["ratingKey"]: item
    for item in MOVIE_ITEMS + SHOW_ITEMS + OTHER_VIDEO_ITEMS
}
CONTINUE_ITEMS = [
    plex_item(*SHOWS[0], item_type="show", view_offset=630_000),
    plex_item(*SHOWS[1], item_type="show", view_offset=420_000),
    plex_item(*MOVIES[0], item_type="movie", view_offset=1_920_000),
    plex_item(*SHOWS[2], item_type="show", view_offset=510_000),
    plex_item(*MOVIES[1], item_type="movie", view_offset=1_380_000),
    plex_item(*SHOWS[4], item_type="show", view_offset=360_000),
    plex_item(*MOVIES[5], item_type="movie", view_offset=2_040_000),
]


@functools.lru_cache(maxsize=256)
def png_bytes(slug: str, width: int, height: int) -> bytes:
    width = max(1, min(width, 800))
    height = max(1, min(height, 600))
    digest = hashlib.sha256(slug.encode("utf-8")).digest()
    base = (40 + digest[0] % 150, 45 + digest[1] % 150, 70 + digest[2] % 150)
    accent = (70 + digest[3] % 170, 70 + digest[4] % 170, 70 + digest[5] % 170)
    rows = []
    for y in range(height):
        mix = y / max(height - 1, 1)
        row = bytearray([0])
        for x in range(width):
            wave = ((x + y + digest[6]) // max(width // 8, 1)) % 2
            local_mix = min(1.0, max(0.0, mix * 0.8 + wave * 0.12))
            row.extend(
                int(base[index] * (1 - local_mix) + accent[index] * local_mix)
                for index in range(3)
            )
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def youtarr_capabilities() -> dict:
    return {
        "apiVersion": "1",
        "serverVersion": "fixture",
        "role": "request",
        "scopes": ["catalog:read", "requests:read", "video:request"],
        "policy": {
            "autoApproveVideoRequests": False,
            "autoApproveChannelRequests": False,
            "autoApproveDeleteRequests": False,
            "maxRatingLevel": 3,
            "allowUnrated": False,
            "allowedMediaTypes": ["video"],
        },
        "features": {
            "catalog": True,
            "requests": True,
            "channelRequests": False,
            "deleteRequests": False,
            "recommendations": False,
            "authenticatedAssets": True,
        },
    }


def youtarr_channels() -> dict:
    data = []
    for index, (title, summary) in enumerate(YOUTARR_CHANNELS, start=1):
        slug = title.lower().replace(" ", "-")
        data.append(
            {
                "id": index,
                "channelId": f"fixture-channel-{index}",
                "title": title,
                "descriptionSummary": summary,
                "thumbnailUrl": f"/external-api/v1/assets/channel-{slug}.png",
                "subfolder": None,
                "videoCount": 8 + index,
                "downloadedCount": index - 1,
                "lastFetchedAt": "2026-07-30T12:00:00.000Z",
            }
        )
    return {
        "data": data,
        "pagination": {
            "page": 1,
            "pageSize": 100,
            "total": len(data),
            "totalPages": 1,
            "nextCursor": None,
        },
        "dataSource": "fixture",
    }


def youtarr_videos() -> dict:
    channel_ids = {
        title: index
        for index, (title, _) in enumerate(YOUTARR_CHANNELS, start=1)
    }
    data = []
    for index, (slug, title, channel, rating, duration) in enumerate(
        YOUTARR_VIDEOS, start=1
    ):
        data.append(
            {
                "youtubeId": slug,
                "title": title,
                "thumbnailUrl": f"/external-api/v1/assets/video-{slug}.png",
                "publishedAt": f"2026-07-{31-index:02d}T12:00:00.000Z",
                "duration": duration,
                "description": f"{title} is a fictional, family-friendly fixture.",
                "isDownloaded": False,
                "isRequested": False,
                "requestStatus": None,
                "rating": rating,
                "channelDatabaseId": channel_ids[channel],
                "channelId": f"fixture-channel-{channel_ids[channel]}",
                "channelTitle": channel,
                "mediaType": "video",
            }
        )
    return {
        "data": data,
        "pagination": {
            "page": 1,
            "pageSize": 40,
            "total": len(data),
            "totalPages": 1,
            "nextCursor": None,
        },
        "dataSource": "fixture",
        "isFullyIndexed": True,
        "lastIndexedAt": "2026-07-30T12:00:00.000Z",
        "indexingHint": None,
    }


def asset_dimensions(path: str) -> tuple[int, int]:
    if "/channel-" in path:
        return (512, 512)
    return (640, 360)


def validate_fixtures() -> None:
    minimum_counts = {
        "movies": (MOVIES, 8),
        "shows": (SHOWS, 8),
        "other videos": (OTHER_VIDEOS, 10),
        "continue watching": (CONTINUE_ITEMS, 6),
        "Youtarr videos": (YOUTARR_VIDEOS, 12),
        "Youtarr channels": (YOUTARR_CHANNELS, 8),
    }
    for label, (records, minimum) in minimum_counts.items():
        if len(records) < minimum:
            raise ValueError(
                f"{label} has {len(records)} fixtures; expected at least {minimum}"
            )

    content_slugs = [record[0] for record in MOVIES + SHOWS + OTHER_VIDEOS]
    if len(content_slugs) != len(set(content_slugs)):
        raise ValueError("Plex fixture slugs must be unique")

    youtarr_slugs = [record[0] for record in YOUTARR_VIDEOS]
    if len(youtarr_slugs) != len(set(youtarr_slugs)):
        raise ValueError("Youtarr fixture slugs must be unique")

    channel_titles = {record[0] for record in YOUTARR_CHANNELS}
    missing_channels = {
        record[2]
        for record in YOUTARR_VIDEOS
        if record[2] not in channel_titles
    }
    if missing_channels:
        raise ValueError(
            f"Youtarr videos reference missing channels: {sorted(missing_channels)}"
        )

    plex_ratings = {record[2] for record in MOVIES + OTHER_VIDEOS}
    show_ratings = {record[2] for record in SHOWS}
    youtarr_ratings = {record[3] for record in YOUTARR_VIDEOS}
    if not plex_ratings <= {"G", "PG"}:
        raise ValueError(f"movie fixtures exceed PG: {sorted(plex_ratings)}")
    if not show_ratings <= {"TV-Y", "TV-Y7", "TV-G", "TV-PG"}:
        raise ValueError(f"show fixtures exceed TV-PG: {sorted(show_ratings)}")
    if not youtarr_ratings <= {"TV-Y", "TV-Y7", "TV-G", "TV-PG"}:
        raise ValueError(f"Youtarr fixtures exceed TV-PG: {sorted(youtarr_ratings)}")

    for channel in youtarr_channels()["data"]:
        width, height = asset_dimensions(channel["thumbnailUrl"])
        if width != height:
            raise ValueError(
                f"channel artwork must be square: {channel['thumbnailUrl']}"
            )

    for video in youtarr_videos()["data"]:
        width, height = asset_dimensions(video["thumbnailUrl"])
        if width * 9 != height * 16:
            raise ValueError(
                f"video artwork must be 16:9: {video['thumbnailUrl']}"
            )


class FixtureHandler(BaseHTTPRequestHandler):
    server_version = "PlinxFixture/1.0"

    def log_message(self, message: str, *args: object) -> None:
        if getattr(self.server, "verbose", False):
            super().log_message(message, *args)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == "/healthz":
            self.send_json({"status": "ok"})
        elif path == "/library/sections/all":
            self.send_json(
                {
                    "MediaContainer": {
                        "size": 3,
                        "Directory": [
                            {
                                "agent": "tv.plex.agents.movie",
                                "key": "1",
                                "type": "movie",
                                "title": "Family Movies",
                            },
                            {
                                "agent": "tv.plex.agents.series",
                                "key": "2",
                                "type": "show",
                                "title": "Family TV",
                            },
                            {
                                "agent": "tv.plex.agents.none",
                                "key": "3",
                                "type": "movie",
                                "title": "Other Videos",
                            },
                        ],
                    }
                }
            )
        elif path == "/hubs/continueWatching":
            self.send_json(
                {
                    "MediaContainer": {
                        "size": 1,
                        "Hub": [
                            {
                                "hubKey": "/hubs/continueWatching",
                                "key": "/hubs/continueWatching",
                                "title": "Continue Watching",
                                "hubIdentifier": "continueWatching",
                                "size": len(CONTINUE_ITEMS),
                                "more": False,
                                "Metadata": CONTINUE_ITEMS,
                            }
                        ],
                    }
                }
            )
        elif path == "/library/sections/1/all":
            self.send_items(MOVIE_ITEMS)
        elif path == "/library/sections/2/all":
            self.send_items(SHOW_ITEMS)
        elif path == "/library/sections/3/all":
            self.send_items(OTHER_VIDEO_ITEMS)
        elif path.startswith("/library/metadata/") and path.endswith("/related"):
            self.send_json({"MediaContainer": {"size": 0, "Hub": []}})
        elif path.startswith("/library/metadata/") and path.endswith("/children"):
            self.send_items([])
        elif path.startswith("/library/metadata/"):
            slug = path.split("/")[3]
            item = ALL_ITEMS.get(slug, MOVIE_ITEMS[0])
            self.send_items([item])
        elif path == "/photo/:/transcode":
            raw = query.get("url", ["/artwork/fixture.png"])[0]
            width = int(query.get("width", ["480"])[0])
            height = int(query.get("height", ["720"])[0])
            self.send_png(raw, width, height)
        elif path.startswith("/artwork/"):
            self.send_png(path, 480, 720 if "/poster/" in path else 270)
        elif path == "/external-api/v1/capabilities":
            self.send_json(youtarr_capabilities())
        elif path == "/external-api/v1/channels":
            self.send_json(youtarr_channels())
        elif path in {
            "/external-api/v1/catalog/videos",
            "/external-api/v1/videos",
        }:
            self.send_json(youtarr_videos())
        elif path.startswith("/external-api/v1/channels/") and path.endswith("/videos"):
            self.send_json(youtarr_videos())
        elif path.startswith("/external-api/v1/videos/"):
            slug = path.rsplit("/", 1)[-1]
            videos = youtarr_videos()["data"]
            video = next((entry for entry in videos if entry["youtubeId"] == slug), videos[0])
            self.send_json(
                {
                    **video,
                    "channelDescription": "A fictional channel used for Plinx review captures.",
                    "tags": ["family", "learning"],
                }
            )
        elif path.startswith("/external-api/v1/assets/"):
            width, height = asset_dimensions(path)
            self.send_png(path, width, height)
        else:
            self.send_json({"error": "fixture endpoint not found", "path": path}, 404)

    def send_items(self, items: list[dict]) -> None:
        self.send_json(
            {
                "MediaContainer": {
                    "size": len(items),
                    "totalSize": len(items),
                    "Metadata": items,
                }
            }
        )

    def send_json(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_png(self, slug: str, width: int, height: int) -> None:
        data = png_bytes(slug, width, height)
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Cache-Control", "public, max-age=3600")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--validate",
        action="store_true",
        help="validate fixture density, ratings, identifiers, and artwork shapes",
    )
    args = parser.parse_args()

    validate_fixtures()
    if args.validate:
        print("App Store fixtures are valid")
        return

    server = ThreadingHTTPServer((args.host, args.port), FixtureHandler)
    server.verbose = args.verbose
    print(f"Plinx fixture server listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
