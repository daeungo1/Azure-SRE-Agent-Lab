#!/usr/bin/env python3
"""Build MkDocs sources from the repository's canonical Markdown files.

README.md, SRE_Agent.md and features-sre/README.md stay single files so they keep
rendering on GitHub. This script is the only place that knows how to turn them into a
multi-tab site: it splits README.md on its top-level sections, rewrites every
cross-reference, copies the diagrams, and writes .site/ ready for `mkdocs build`.

Nothing it produces is committed — .site/ is a build artifact.

    python scripts/build-site.py
    mkdocs build -f .site/mkdocs.yml
"""

from __future__ import annotations

import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / ".site"
DOCS = OUT / "docs"
GH = "https://github.com/daeungo1/Azure-SRE-Agent-Lab"

TAB_LAB = "Lab 실습"
TAB_E2E = "E2E 결과"
TAB_PORTAL = "Portal 기능"
TAB_OPS = "Lab 마무리"

# README.md section number -> (tab, output directory, url slug)
SECTION_SLUGS = {
    1: "overview",
    2: "prerequisites",
    3: "quickstart",
    4: "verify",
    5: "scenarios",
    6: "e2e-results",
    7: "wrapup",
    8: "cleanup",
    9: "troubleshooting",
    10: "repo-structure",
}


@dataclass
class Page:
    out: str  # path relative to DOCS, e.g. "lab/03-quickstart.md"
    title: str
    body: str
    tab: str | None = None  # None means top-level entry
    anchors: list[str] = field(default_factory=list)


# ── Markdown helpers ─────────────────────────────────────────────────────────

FENCE = re.compile(r"^\s*(```|~~~)")


def iter_lines_outside_fences(text: str):
    """Yield (line, in_fence) so heading rules never fire inside code blocks."""
    in_fence = False
    for line in text.split("\n"):
        if FENCE.match(line):
            in_fence = not in_fence
            yield line, True
            continue
        yield line, in_fence


def slugify(text: str) -> str:
    """Mirror pymdownx.slugs.uslugify so links written for GitHub keep working."""
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # links -> label
    text = re.sub(r"[*`_]", "", text)
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE).strip().lower()
    return re.sub(r"\s", "-", text)


def shift_headings(text: str) -> str:
    """Promote every heading one level so a split section starts at H1."""
    out = []
    for line, in_fence in iter_lines_outside_fences(text):
        if not in_fence and line.startswith("##"):
            line = line[1:]
        out.append(line)
    return "\n".join(out)


def collect_anchors(text: str) -> list[str]:
    anchors = []
    for line, in_fence in iter_lines_outside_fences(text):
        if in_fence:
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            anchors.append(slugify(m.group(2)))
    return anchors


def split_sections(md: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (preamble, [(heading_text, section_markdown), ...]) split on '## '."""
    preamble: list[str] = []
    sections: list[tuple[str, list[str]]] = []
    current: list[str] | None = None

    for line, in_fence in iter_lines_outside_fences(md):
        if not in_fence and re.match(r"^##\s+\S", line):
            heading = line[2:].strip()
            current = [line]
            sections.append((heading, current))
            continue
        (current if current is not None else preamble).append(line)

    return "\n".join(preamble), [(h, "\n".join(body)) for h, body in sections]


def section_number(heading: str) -> int | None:
    m = re.match(r"^(\d+)\.", heading.strip())
    return int(m.group(1)) if m else None


# ── Page construction ────────────────────────────────────────────────────────


def build_pages() -> list[Page]:
    pages: list[Page] = []

    # Home — the whole product introduction, minus its own table of contents.
    sre_md = (REPO / "SRE_Agent.md").read_text(encoding="utf-8")
    pages.append(Page(out="index.md", title="홈 — SRE Agent 소개", body=drop_toc(sre_md)))

    # Lab guide — README.md split by top-level section.
    readme = (REPO / "README.md").read_text(encoding="utf-8")
    preamble, sections = split_sections(readme)
    pages.append(Page(out="lab/index.md", title="시작하기", body=preamble.rstrip(), tab=TAB_LAB))

    unrouted: list[str] = []
    for heading, body in sections:
        if heading.strip() == "목차":
            continue
        num = section_number(heading)
        body = shift_headings(body)

        if num is None:
            # '참고' and any other unnumbered trailing section.
            pages.append(Page(out="ops/99-references.md", title=heading, body=body, tab=TAB_OPS))
            continue

        slug = SECTION_SLUGS.get(num)
        if slug is None:
            slug = f"section-{num}"
            unrouted.append(heading)

        if 1 <= num <= 5:
            pages.append(Page(out=f"lab/{num:02d}-{slug}.md", title=heading, body=body, tab=TAB_LAB))
        elif num == 6:
            pages.append(Page(out="e2e/index.md", title=heading, body=body, tab=TAB_E2E))
        else:
            pages.append(Page(out=f"ops/{num:02d}-{slug}.md", title=heading, body=body, tab=TAB_OPS))

    if unrouted:
        print(f"  note: sections without a known slug -> {', '.join(unrouted)}")

    # Portal features — kept as one page; it reads as a single document.
    portal_md = (REPO / "features-sre" / "README.md").read_text(encoding="utf-8")
    pages.append(Page(out="portal/index.md", title="포털 기능 구성", body=drop_toc(portal_md), tab=TAB_PORTAL))

    for p in pages:
        p.anchors = collect_anchors(p.body)
    return pages


def drop_toc(md: str) -> str:
    preamble, sections = split_sections(md)
    kept = [body for heading, body in sections if heading.strip() != "목차"]
    return "\n".join([preamble.rstrip(), *kept])


# ── Link rewriting ───────────────────────────────────────────────────────────

LINK_RE = re.compile(r"(?<=\]\()([^)\s]+)(?=[)\s])")
SRC_RE = re.compile(r'(?<=src=")([^"]+)(?=")')

# Source file -> the page that now holds its preamble, used when a link has no anchor.
DEFAULT_TARGET = {
    "SRE_Agent.md": "index.md",
    "README.md": "lab/index.md",
    "features-sre/README.md": "portal/index.md",
}


def resolve(src_page_out: str, url: str, anchor_index: dict[str, str], svgs: set[str]) -> str:
    if url.startswith(("http://", "https://", "mailto:")):
        return url

    page_dir = Path(src_page_out).parent

    def rel(target: str, anchor: str) -> str:
        out = Path(target)
        result = Path(*([".."] * len(page_dir.parts))) / out if page_dir.parts else out
        link = result.as_posix()
        return f"{link}#{anchor}" if anchor else link

    # A bare '#anchor' was same-page in the original file; after splitting it may not be.
    if url.startswith("#"):
        anchor = url[1:]
        target = anchor_index.get(anchor)
        if target is None:
            print(f"  warn: unknown anchor {url} in {src_page_out}")
            return url
        return url if target == src_page_out else rel(target, anchor)

    path, _, anchor = url.partition("#")
    path = path.lstrip("./")
    if not path:
        return url

    # Diagrams are copied next to the docs.
    if path in svgs:
        return rel(f"assets/{Path(path).name}", "")

    if path in DEFAULT_TARGET:
        if anchor and anchor in anchor_index:
            return rel(anchor_index[anchor], anchor)
        if anchor:
            print(f"  warn: unresolved anchor #{anchor} in {src_page_out}")
        return rel(DEFAULT_TARGET[path], "")

    # Everything else is source code — link to it on GitHub.
    kind = "tree" if (REPO / path).is_dir() else "blob"
    return f"{GH}/{kind}/main/{path}"


def rewrite(page: Page, anchor_index: dict[str, str], svgs: set[str]) -> str:
    body = LINK_RE.sub(lambda m: resolve(page.out, m.group(1), anchor_index, svgs), page.body)
    return SRC_RE.sub(lambda m: resolve(page.out, m.group(1), anchor_index, svgs), body)


# ── Output ───────────────────────────────────────────────────────────────────


def write_nav(pages: list[Page]) -> str:
    lines = ["", "nav:"]
    order = [None, TAB_LAB, TAB_E2E, TAB_PORTAL, TAB_OPS]
    for tab in order:
        members = [p for p in pages if p.tab == tab]
        if not members:
            continue
        if tab is None:
            for p in members:
                lines.append(f"  - {yaml_str(p.title)}: {p.out}")
        else:
            lines.append(f"  - {yaml_str(tab)}:")
            for p in members:
                lines.append(f"      - {yaml_str(p.title)}: {p.out}")
    return "\n".join(lines) + "\n"


def yaml_str(text: str) -> str:
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def main() -> int:
    if OUT.exists():
        shutil.rmtree(OUT)
    DOCS.mkdir(parents=True)

    svg_dir = REPO / "docs"
    svgs = {f"docs/{p.name}" for p in svg_dir.glob("*.svg")}
    assets = DOCS / "assets"
    assets.mkdir()
    for p in svg_dir.glob("*.svg"):
        shutil.copy2(p, assets / p.name)

    pages = build_pages()

    anchor_index: dict[str, str] = {}
    for p in pages:
        for a in p.anchors:
            anchor_index.setdefault(a, p.out)

    for p in pages:
        target = DOCS / p.out
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rewrite(p, anchor_index, svgs).rstrip() + "\n", encoding="utf-8")

    base = (REPO / "mkdocs.base.yml").read_text(encoding="utf-8")
    (OUT / "mkdocs.yml").write_text(base.rstrip() + "\n" + write_nav(pages), encoding="utf-8")

    print(f"  built {len(pages)} pages, {len(svgs)} diagrams -> {OUT.relative_to(REPO)}")
    for p in pages:
        print(f"    {p.tab or '(top)':<22} {p.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
