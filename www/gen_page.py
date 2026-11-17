#!/usr/bin/env python3
"""
gen_page.py - Generate a styled trial content page from a markdown source.

It reads   www/pages_md/<Name>/<Name>.md  (+ its images/ folder)
and writes www/pages/<Name>/<Name>.html  (+ a copy of the images it uses),
reusing the visual identity / layout of www/pages/welcome.html
(left sidebar nav, dark hero, white content panels).

Usage:
    python3 gen_page.py "Deliver Active Context"
    python3 gen_page.py path/to/Something.md          # explicit file
    python3 gen_page.py                                 # all folders in pages_md/

No third-party runtime deps beyond python-markdown (stdlib + markdown).
Missing images referenced by the markdown are rendered as a visible
placeholder instead of a broken <img>, so the page never 404s silently.
"""

import html
import re
import shutil
import sys
from pathlib import Path

import markdown

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
WWW = Path(__file__).resolve().parent
SRC_ROOT = WWW / "pages_md"
OUT_ROOT = WWW / "pages"
# Output pages live in www/pages/<Name>/ , one level below www/pages/ ,
# so shared assets are reached with ../../assets/...
ASSETS = "../../assets"

# ---------------------------------------------------------------------------
# Page shell (mirrors welcome.html)
# ---------------------------------------------------------------------------
NAV_LINKS = [
    ("/denodo-design-studio/",
     '<path d="M12 2l9 5v10l-9 5-9-5V7l9-5zM3 7l9 5 9-5M12 12v10"/>', "Design Studio"),
    ("/denodo-data-catalog/#/",
     '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/>'
     '<rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>', "Data Marketplace"),
    ("/chatbot/",
     '<path d="M12 2l2 6.2L20 10l-6 1.8L12 18l-2-6.2L4 10l6-1.8L12 2z"/>', "Ask a Question"),
    ("../mcp-api.html",
     '<path d="M10 14a4 4 0 0 0 5.6 0l3-3a4 4 0 1 0-5.6-5.6L11.8 6.6M14 10a4 4 0 0 0-5.6 0l-3 3'
     'A4 4 0 0 0 11 18.6l1.2-1.2"/>', "MCP and API"),
    ("../documentation.html",
     '<path d="M4 4h6a3 3 0 0 1 3 3v13a2.5 2.5 0 0 0-2.5-2.5H4V4zM20 4h-6a3 3 0 0 0-3 3v13'
     'a2.5 2.5 0 0 1 2.5-2.5H20V4z"/>', "Documentation"),
]

HEAD_CSS = f"""
@font-face{{font-family:"Proxima Nova";src:url("{ASSETS}/fonts/Proxima%20Nova/proximanova-regular-webfont.woff2") format("woff2");font-weight:400;font-display:swap}}
@font-face{{font-family:"Proxima Nova";src:url("{ASSETS}/fonts/Proxima%20Nova/proximanova-medium-webfont.woff2") format("woff2");font-weight:500;font-display:swap}}
@font-face{{font-family:"Proxima Nova";src:url("{ASSETS}/fonts/Proxima%20Nova/proximanova-semibold-webfont.woff2") format("woff2");font-weight:600;font-display:swap}}

:root{{
  --midnight-blue:#112533; --dark-midnight-blue:#0a3f5b; --light-blue:#84b5ce;
  --peacock-blue:#006699; --peacock-blue-hover:#3276b1;
  --green-success:#42b044; --highlight-orange:#ff9933; --warning-red:#f05149;
  --gunmetal:#4f5e69; --grey:#c7c9ca; --light-grey:#e7e9ea; --light-grey-b:#f3f4f5;
  --line:#dadfe3; --muted:#60707c; --r-sm:4px; --r-md:6px;
}}
*,*::before,*::after{{box-sizing:border-box}}
html,body{{height:100%}}
body{{margin:0;background:var(--light-grey-b);color:var(--midnight-blue);
  font-family:"Proxima Nova","proxima-nova",Roboto,"Segoe UI",system-ui,sans-serif;
  font-size:14px;-webkit-font-smoothing:antialiased}}
h1,h2,h3,h4{{margin:0;font-weight:600;letter-spacing:-.025em;line-height:1.15}}
p{{margin:0}}
a{{color:var(--peacock-blue)}}
:focus-visible{{outline:2px solid var(--peacock-blue);outline-offset:2px}}

.mark{{display:inline-flex;align-items:center;gap:9px;font-size:22px;font-weight:600;letter-spacing:-.03em}}
.mark img{{height:26px;display:block}}

/* ---- shell: sidebar + main (welcome.html) ---- */
.app{{display:flex;min-height:100vh}}
.nav{{width:238px;flex:none;background:#fff;border-right:1px solid var(--line);padding:14px 0;
  display:flex;flex-direction:column}}
.nav .brand{{display:flex;align-items:center;padding:10px 18px 22px}}
.nav .brand img{{height:28px}}
.nav-s{{font-size:11px;font-weight:600;letter-spacing:.07em;text-transform:uppercase;
  color:var(--muted);padding:14px 18px 6px}}
.nav a,.nav button.navi{{display:flex;align-items:center;gap:10px;padding:7px 18px;font-size:14px;
  color:var(--midnight-blue);text-decoration:none;border-left:3px solid transparent;width:100%}}
.nav a:hover,.nav button.navi:hover{{background:var(--light-grey-b)}}
.nav .on{{background:#e1edf4;border-left-color:var(--peacock-blue);color:var(--peacock-blue);font-weight:600}}
.nav svg{{color:var(--gunmetal);flex:none}}
.nav .on svg{{color:var(--peacock-blue)}}
.ico{{width:20px;height:20px;display:block}}

.main{{flex:1 1 auto;min-width:0;background:var(--light-grey-b);padding-bottom:60px}}
.hero{{background:var(--dark-midnight-blue);padding:30px 40px 92px;position:relative;overflow:hidden}}
.hero h1{{color:#fff;font-size:27px;text-align:center;position:relative;z-index:1}}
.hero p{{color:#dbe9f2;text-align:center;font-size:14.5px;line-height:1.5;margin:7px auto 0;max-width:720px;position:relative;z-index:1}}
.hero-logo{{position:absolute;top:20px;right:30px;height:24px;width:auto;z-index:2}}
.hero svg.deco{{position:absolute;inset:0;width:100%;height:100%;opacity:.5}}

.wrap{{max-width:1020px;margin:-68px auto 0;padding:0 40px;position:relative;z-index:2}}
.panel{{background:#fff;border:1px solid var(--line);border-radius:8px;margin-bottom:20px}}
.panel-p{{padding:26px 30px}}
.panel h2{{font-size:21px;margin-bottom:10px}}

/* ---- rendered markdown content ---- */
.content h3{{font-size:16.5px;margin:22px 0 8px}}
.content h4{{font-size:14.5px;color:var(--gunmetal);margin:18px 0 6px}}
.content p{{font-size:14px;line-height:1.6;margin:10px 0;color:var(--midnight-blue)}}
.content ul,.content ol{{margin:10px 0;padding-left:22px}}
.content li{{font-size:14px;line-height:1.6;margin:4px 0}}
.content li>ul,.content li>ol{{margin:4px 0}}
.content a{{font-weight:600}}
.content a:hover{{text-decoration:underline}}
.content strong{{font-weight:600}}
.content hr{{border:0;border-top:1px solid var(--light-grey);margin:22px 0}}
.content code{{font-family:"SFMono-Regular",Consolas,"Liberation Mono",Menlo,monospace;
  font-size:12.5px;background:var(--light-grey-b);border:1px solid var(--line);
  border-radius:4px;padding:1px 5px;overflow-wrap:anywhere}}
.content pre{{background:#0d1b26;color:#e7eef4;border-radius:8px;padding:16px 18px;overflow:auto;margin:14px 0}}
.content pre code{{background:none;border:0;padding:0;color:inherit;font-size:12.5px;line-height:1.55}}
.content table{{border-collapse:collapse;width:100%;margin:14px 0;font-size:13.5px}}
.content th,.content td{{border:1px solid var(--line);padding:8px 12px;text-align:left;vertical-align:top}}
.content th{{background:var(--light-grey-b);font-weight:600}}
.content figure{{margin:18px 0}}
.content figure img{{display:block;max-width:100%;height:auto;border:1px solid var(--line);
  border-radius:8px;box-shadow:0 1px 3px rgba(17,37,51,.08)}}
.content figcaption{{font-size:12.5px;color:var(--muted);margin-top:7px}}
.imgmiss{{display:block;border:1px dashed var(--grey);border-radius:8px;background:var(--light-grey-b);
  color:var(--muted);font-size:12.5px;padding:22px;text-align:center}}
.foot{{font-size:12.5px;color:var(--muted);margin:28px 0 0;text-align:center}}

@media(max-width:900px){{.nav{{display:none}}}}
@media(max-width:760px){{
  .wrap{{padding:0 16px;margin-top:-48px}}
  .hero{{padding:26px 18px 74px}}
  .hero h1{{font-size:22px;line-height:1.25}}
  .panel-p{{padding:20px 18px}}
  .panel h2{{font-size:19px;line-height:1.25}}
}}
"""

HERO_DECO = (
    '<svg class="deco" viewBox="0 0 1200 220" preserveAspectRatio="none" aria-hidden="true">'
    '<circle cx="120" cy="40" r="3" fill="#2f6f93"/><circle cx="170" cy="90" r="3" fill="#2f6f93"/>'
    '<circle cx="70" cy="140" r="3" fill="#2f6f93"/><circle cx="220" cy="30" r="3" fill="#2f6f93"/>'
    '<circle cx="1080" cy="60" r="3" fill="#2f6f93"/><circle cx="1130" cy="120" r="3" fill="#2f6f93"/>'
    '<circle cx="1020" cy="160" r="3" fill="#2f6f93"/><circle cx="980" cy="40" r="3" fill="#2f6f93"/>'
    '<path d="M120 40L170 90M70 140L170 90M220 30L170 90M1080 60L1130 120M1020 160L1130 120M980 40L1080 60" '
    'stroke="#2f6f93" stroke-width="1" fill="none"/></svg>'
)


def build_nav():
    lines = ['<aside class="nav">',
             f'<div class="brand"><img alt="Denodo" src="{ASSETS}/images/denodo_logo_black.png"></div>',
             '<div class="nav-s">Trial</div>',
             '<a href="../welcome.html"><svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
             'stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M15 9l-2 5-5 2 2-5 5-2z"/></svg>Get started</a>',
             '<div class="nav-s">Tools</div>']
    for href, path, label in NAV_LINKS:
        lines.append(
            f'<a href="{href}"><svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="2" stroke-linejoin="round" stroke-linecap="round">{path}</svg>{label}</a>')
    lines.append('</aside>')
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Markdown -> HTML
# ---------------------------------------------------------------------------
IMG_RE = re.compile(r'!\[(?P<alt>[^\]]*)\]\((?P<src>[^)]+)\)')


def split_sections(md_text):
    """First H1 -> page title. Each top-level ## starts a new panel.
    Content before the first ## (but after the H1) becomes an intro panel."""
    lines = md_text.splitlines()
    title = None
    i = 0
    # page title = first H1
    while i < len(lines):
        m = re.match(r'#\s+(.*)', lines[i])
        if m:
            title = m.group(1).strip()
            i += 1
            break
        i += 1
    if title is None:
        title = "Denodo trial"
        i = 0

    sections = []  # list of (heading_or_None, body_md)
    cur_heading = None
    cur_body = []

    def flush():
        if cur_heading is not None or any(l.strip() for l in cur_body):
            sections.append((cur_heading, "\n".join(cur_body).strip()))

    for line in lines[i:]:
        m = re.match(r'##\s+(?!#)(.*)', line)  # exactly H2
        if m:
            flush()
            cur_heading = m.group(1).strip()
            cur_body = []
        else:
            cur_body.append(line)
    flush()
    return title, sections


def resolve_images(body_md, src_dir, used):
    """Rewrite image paths to local images/ copies; flag missing ones.
    Returns rewritten markdown. `used` collects (src_path, exists)."""
    def repl(m):
        alt = m.group('alt')
        src = m.group('src').strip()
        # only handle relative local images
        if re.match(r'^[a-zA-Z]+://', src) or src.startswith('/'):
            return m.group(0)
        name = Path(src).name
        abs_src = (src_dir / src).resolve()
        exists = abs_src.is_file()
        used.append((abs_src, name, exists))
        if exists:
            return f'![{alt}](images/{name})'
        # leave a marker the HTML post-pass turns into a placeholder
        return f'@@MISSING_IMG::{html.escape(alt)}::{html.escape(name)}@@'
    return IMG_RE.sub(repl, body_md)


def md_to_html(body_md):
    out = markdown.markdown(
        body_md,
        extensions=['extra', 'sane_lists'],  # 'extra' => tables, fenced_code, etc.
        output_format='html5',
    )
    # wrap <img> in <figure> with its alt as caption
    def fig(m):
        tag, alt = m.group(0), m.group('alt')
        cap = f'<figcaption>{alt}</figcaption>' if alt else ''
        return f'<figure>{tag}{cap}</figure>'
    out = re.sub(r'<img [^>]*alt="(?P<alt>[^"]*)"[^>]*>', fig, out)
    # turn missing-image markers into placeholders
    out = re.sub(
        r'@@MISSING_IMG::(?P<alt>.*?)::(?P<name>.*?)@@',
        lambda m: f'<span class="imgmiss">Image not available: {m.group("name")}'
                  + (f' &mdash; {m.group("alt")}' if m.group("alt") else '') + '</span>',
        out)
    return out


def generate(md_path):
    md_path = Path(md_path).resolve()
    src_dir = md_path.parent
    name = md_path.stem
    text = md_path.read_text(encoding='utf-8')

    title, sections = split_sections(text)

    out_dir = OUT_ROOT / name
    out_dir.mkdir(parents=True, exist_ok=True)
    img_out = out_dir / "images"

    used = []
    panels = []
    for heading, body in sections:
        body = resolve_images(body, src_dir, used)
        inner = md_to_html(body) if body.strip() else ""
        h2 = f'<h2>{html.escape(heading)}</h2>' if heading else ''
        panels.append(f'<section class="panel"><div class="panel-p">{h2}'
                      f'<div class="content">{inner}</div></div></section>')

    # copy images that exist
    copied, missing = 0, []
    if any(e for *_, e in used):
        img_out.mkdir(parents=True, exist_ok=True)
    for abs_src, fname, exists in used:
        if exists:
            shutil.copy2(abs_src, img_out / fname)
            copied += 1
        elif fname not in missing:
            missing.append(fname)

    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<link rel="shortcut icon" href="{ASSETS}/images/favicon.ico">
<link rel="stylesheet" href="{ASSETS}/css/challenge-context.css">
<!-- Generated by gen_page.py from pages_md/{html.escape(name)}/{html.escape(name)}.md -->
<style>{HEAD_CSS}</style>
</head>
<body>
<div class="app">
{build_nav()}
<div class="main">
 <div class="hero">
  {HERO_DECO}
  <img class="hero-logo" alt="Denodo" src="{ASSETS}/images/denodo_logo_white.svg">
  <h1>{html.escape(title)}</h1>
 </div>
 <div class="wrap">
{chr(10).join(panels)}
  <p class="foot">Property of Denodo. &copy; Copyright Denodo 2026</p>
 </div>
</div>
</div>
</body>
</html>
"""
    out_file = out_dir / f"{name}.html"
    out_file.write_text(page, encoding='utf-8')
    rel = out_file.relative_to(WWW)
    print(f"  wrote {rel}  ({len(panels)} panels, {copied} images copied"
          + (f", {len(missing)} missing: {', '.join(missing)}" if missing else "") + ")")
    return out_file


def main(argv):
    targets = []
    if not argv:
        targets = sorted(p for p in SRC_ROOT.iterdir() if p.is_dir())
        targets = [d / f"{d.name}.md" for d in targets]
    else:
        for a in argv:
            p = Path(a)
            if p.suffix.lower() == ".md":
                targets.append(p if p.is_absolute() else (WWW / p))
            else:
                # treat as folder name under pages_md/
                targets.append(SRC_ROOT / a / f"{a}.md")

    for md in targets:
        if not md.is_file():
            print(f"  SKIP (not found): {md}")
            continue
        print(f"Generating from {md.name} ...")
        generate(md)


if __name__ == "__main__":
    main(sys.argv[1:])
