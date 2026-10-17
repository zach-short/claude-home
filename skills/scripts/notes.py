#!/usr/bin/env python3
"""Read an Apple Notes folder into numbered text files and decoded screenshots.

Usage (run with -I):
  python3 -I notes.py --folder ezh --list
  python3 -I notes.py --folder ezh --since 2026-10-14 --out DIR

--list prints names and times only and reads no body. With --out it writes
DIR/notes.json and one DIR/note-NN-K.<ext> file per embedded screenshot, and prints
a table. Times are local. Notes are numbered oldest first by creation time.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path

JXA = r"""
function run(argv) {
  const [folderName, sinceMs, wantBody] = argv;
  const Notes = Application('Notes');
  const out = [];
  Notes.folders.whose({ name: folderName })().forEach(folder => {
    folder.notes().forEach(note => {
      const modified = note.modificationDate();
      if (modified.getTime() < Number(sinceMs)) return;
      out.push({
        name: note.name(),
        created: note.creationDate().toISOString(),
        modified: modified.toISOString(),
        body: wantBody === '1' ? note.body() : '',
      });
    });
  });
  return JSON.stringify(out);
}
"""

BLOCK_TAGS = {"div", "p", "br", "li", "h1", "h2", "h3", "tr"}


class BodyParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.lines = [""]
        self.images = []
        self.unresolved = 0

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            src = dict(attrs).get("src") or ""
            match = re.match(r"data:image/([a-zA-Z0-9.+-]+);base64,(.*)", src, re.S)
            if match:
                ext = "jpg" if match.group(1) == "jpeg" else match.group(1).split("+")[0]
                self.images.append((ext, base64.b64decode(match.group(2))))
            else:
                self.unresolved += 1
        elif tag in BLOCK_TAGS and self.lines[-1] != "":
            self.lines.append("")

    def handle_data(self, data):
        self.lines[-1] += data

    def text(self):
        return "\n".join(line.strip() for line in self.lines if line.strip())


def local(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone()


def read_notes(folder, since, want_body):
    since_ms = int(since.timestamp() * 1000) if since else 0
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", JXA, folder, str(since_ms), "1" if want_body else "0"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"osascript failed: {result.stderr.strip()}")
    notes = json.loads(result.stdout)
    notes.sort(key=lambda n: n["created"])
    return notes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder", required=True)
    parser.add_argument("--since", help="local date or datetime, e.g. 2026-10-14 or 2026-10-14T22:00")
    parser.add_argument("--out", help="directory for notes.json and screenshots")
    parser.add_argument("--list", action="store_true", help="names and times only, no bodies")
    args = parser.parse_args()

    if not args.list and not args.out:
        sys.exit("pass --out DIR, or --list")
    since = datetime.fromisoformat(args.since).astimezone() if args.since else None
    notes = read_notes(args.folder, since, want_body=not args.list)
    if not notes:
        sys.exit(f"no notes in folder {args.folder!r}" + (f" since {args.since}" if since else ""))

    if args.list:
        for i, note in enumerate(notes, 1):
            print(f"{i:02d}  created {local(note['created']):%Y-%m-%d %H:%M:%S}  modified {local(note['modified']):%H:%M:%S}  {note['name'][:70]}")
        return

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    records = []
    for i, note in enumerate(notes, 1):
        parser_ = BodyParser()
        parser_.feed(note["body"])
        paths = []
        for k, (ext, data) in enumerate(parser_.images, 1):
            path = out / f"note-{i:02d}-{k}.{ext}"
            path.write_bytes(data)
            paths.append(str(path))
        records.append({
            "n": i,
            "created": f"{local(note['created']):%Y-%m-%d %H:%M:%S}",
            "modified": f"{local(note['modified']):%Y-%m-%d %H:%M:%S}",
            "name": note["name"],
            "text": parser_.text(),
            "images": paths,
            "unresolved_images": parser_.unresolved,
        })
    (out / "notes.json").write_text(json.dumps(records, indent=2) + "\n")
    for r in records:
        flag = f"  [{len(r['images'])} img]" if r["images"] else ""
        flag += f"  [{r['unresolved_images']} image not decoded]" if r["unresolved_images"] else ""
        print(f"{r['n']:02d}  {r['created']}{flag}\n    {r['text'][:300]}")
    print(f"\nwrote {out / 'notes.json'}")


if __name__ == "__main__":
    main()
