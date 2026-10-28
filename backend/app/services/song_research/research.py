"""Busca por artista/música e leitura limitada de fontes; conteúdo externo é dado."""

import hashlib
import ipaddress
import json
import os
import re
import socket
import time
import unicodedata
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, urljoin
import httpx
from ...core.storage import load_record, save_record

DOMAINS = {
    "producelikeapro.com",
    "premierguitar.com",
    "soundonsound.com",
    "guitarworld.com",
    "guitarplayer.com",
    "guitar.com",
    "fender.com",
    "mesaboogie.com",
    "marshall.com",
}
GEAR = {
    "mesa": r"mesa[ /-]*boogie|dual rectifier|mesa.{0,20}4[ x×]*12",
    "fender": r"fender|tone master",
    "marshall": r"marshall|jcm[ -]?[89]00",
    "vox": r"vox|ac[ -]?30",
    "roland": r"roland|jazz chorus|jc[ -]?120",
}


def normalize(text):
    return " ".join(
        re.sub(
            r"[^a-z0-9 ]",
            " ",
            unicodedata.normalize("NFKD", text)
            .encode("ascii", "ignore")
            .decode()
            .lower(),
        ).split()
    )


def allowed(url, search=False):
    parsed = urlparse(url)
    hosts = (
        {"www.bing.com", "www.googleapis.com"}
        if search
        else DOMAINS | {"www." + d for d in DOMAINS}
    )
    if (
        parsed.scheme != "https"
        or parsed.hostname not in hosts
        or parsed.port not in {None, 443}
        or parsed.username
    ):
        return False
    try:
        return all(
            ipaddress.ip_address(row[4][0]).is_global
            for row in socket.getaddrinfo(parsed.hostname, 443, type=socket.SOCK_STREAM)
        )
    except OSError:
        return False


class TextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hidden = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "nav", "footer"}:
            self.hidden += 1

    def handle_endtag(self, tag):
        if tag in {"script", "style", "nav", "footer"} and self.hidden:
            self.hidden -= 1

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


class PublicSearchProvider:
    """Bing RSS sem credenciais; provedor substituível, falha nunca inventa resultados."""

    def fetch(self, url, *, search=False):
        for _ in range(3):
            if not allowed(url, search):
                raise ValueError("Fonte externa não permitida")
            with httpx.Client(
                timeout=12,
                follow_redirects=False,
                headers={"User-Agent": "AIToneStudio/1.5 documentation research"},
            ) as client:
                with client.stream("GET", url) as response:
                    if response.status_code in {301, 302, 303, 307, 308}:
                        url = urljoin(url, response.headers["location"])
                        continue
                    response.raise_for_status()
                    chunks = []
                    size = 0
                    for chunk in response.iter_bytes():
                        size += len(chunk)
                        if size > 1_500_000:
                            raise ValueError("Fonte excede o limite de leitura")
                        chunks.append(chunk)
                    return b"".join(chunks).decode("utf-8", "replace")
        raise ValueError("Redirecionamento excessivo")

    def search(self, query):
        url = str(
            httpx.URL(
                "https://www.bing.com/search", params={"q": query, "format": "rss"}
            )
        )
        root = ET.fromstring(self.fetch(url, search=True))
        return [
            {"url": item.findtext("link") or "", "title": item.findtext("title") or ""}
            for item in root.findall("./channel/item")
        ]


class SongResearch:
    def __init__(self, provider=None):
        self.provider = provider or PublicSearchProvider()

    def research(self, artist, song, version="unknown", refresh=False):
        artist = (artist or "").strip()[:120]
        song = (song or "").strip()[:180]
        if not artist or not song:
            return {
                "status": "missing_identity",
                "sources": [],
                "hints": [],
                "note": "Informe artista e música para pesquisa documental.",
            }
        identity = {
            "artist": normalize(artist),
            "song": normalize(song),
            "version": version,
            "schema": 1,
        }
        key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
        cached = load_record("song_research", key)
        if cached and not refresh and time.time() - cached["fetched_at"] < 7 * 86400:
            return cached
        seeds = json.loads(Path(__file__).with_name("sources.json").read_text())[
            "sources"
        ]
        candidates = [
            dict(s)
            for s in seeds
            if normalize(s["artist"]) == identity["artist"]
            and (not s["song"] or normalize(s["song"]) == identity["song"])
        ]
        query = f'"{artist}" "{song}" guitar amplifier cabinet recording interview'
        errors = []
        if os.environ.get("TONE_WEB_RESEARCH", "1") == "1":
            try:
                hits = self.provider.search(query)
                for hit in hits:
                    if urlparse(hit["url"]).hostname in DOMAINS | {
                        "www." + d for d in DOMAINS
                    } and all(s["url"] != hit["url"] for s in candidates):
                        candidates.append(
                            {
                                **hit,
                                "context": "unverified",
                                "verification": "automatic_search",
                                "gear_hints": [],
                            }
                        )
            except Exception as exc:
                errors.append(type(exc).__name__)
        else:
            errors.append("online_disabled")
        sources = []
        hints = []
        for item in candidates[:4]:
            source = dict(item)
            source["available"] = False
            if os.environ.get("TONE_WEB_RESEARCH", "1") == "1":
                try:
                    html = self.provider.fetch(item["url"])
                    parser = TextParser()
                    parser.feed(html)
                    text = " ".join(parser.parts)
                    normalized = normalize(text)
                    # Descarta resultados sobre outro artista; menções de equipamento não são fatos da sessão.
                    if identity["artist"] not in normalized:
                        continue
                    source["available"] = True
                    source["song_mentioned"] = identity["song"] in normalize(
                        text[:12000]
                    )
                    source["page_sha256"] = hashlib.sha256(html.encode()).hexdigest()
                    source["mentioned_families"] = [
                        family
                        for family, pattern in GEAR.items()
                        if re.search(pattern, text, re.I)
                    ]
                except Exception as exc:
                    source["fetch_error"] = type(exc).__name__
            source.setdefault(
                "note",
                "Menções automáticas requerem revisão; não confirmam uso nesta música ou versão.",
            )
            sources.append(source)
            # Só dados já revisados em fonte primária entram no mapeamento; descoberta automática é exibida para consulta.
            if source.get("verification") == "primary_interview":
                weight = (
                    0.5
                    if source["context"] == "song_recording"
                    and version in {"studio", "unknown"}
                    else 0.10
                )
                if source["context"] == "artist_live" and version in {
                    "studio",
                    "acoustic",
                }:
                    weight = 0
                for hint in source.get("gear_hints", []):
                    hints.append(
                        {
                            **hint,
                            "url": source["url"],
                            "scope": source["context"],
                            "weight": weight,
                            "exact_recording_confirmed": False,
                        }
                    )
        # Novos artistas podem contribuir com priors nominais muito fracos,
        # somente quando páginas de dois domínios permitidos citam a família e a música.
        for family in GEAR:
            matches = [
                source
                for source in sources
                if source.get("available")
                and source.get("verification") == "automatic_search"
                and family in source.get("mentioned_families", [])
                and source.get("song_mentioned")
            ]
            if len({urlparse(source["url"]).hostname for source in matches}) >= 2:
                for block in ["amp", "cabinet"]:
                    hints.append(
                        {
                            "block": block,
                            "family": family,
                            "model": f"Família {family} (menções não verificadas)",
                            "url": matches[0]["url"],
                            "source_urls": [source["url"] for source in matches],
                            "scope": "unverified_mentions",
                            "weight": 0.03,
                            "exact_recording_confirmed": False,
                        }
                    )
        revision = hashlib.sha256(
            json.dumps(
                {
                    "hints": hints,
                    "sources": [
                        {
                            k: source.get(k)
                            for k in ["url", "context", "verification", "page_sha256"]
                        }
                        for source in sources
                    ],
                },
                sort_keys=True,
            ).encode()
        ).hexdigest()
        result = {
            "id": key,
            "revision": revision,
            **identity,
            "artist_display": artist,
            "song_display": song,
            "fetched_at": time.time(),
            "status": "available" if sources else "no_reliable_sources",
            "sources": sources,
            "hints": hints,
            "query": query,
            "provider": "bing_rss",
            "search_errors": errors,
            "note": "Fontes orientam famílias candidatas; não revelam knobs, equivalência acústica ou a versão do arquivo enviado.",
        }
        save_record("song_research", key, result)
        return result
