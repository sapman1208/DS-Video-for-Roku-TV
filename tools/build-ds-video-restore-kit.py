#!/usr/bin/env python3
"""Build a downloadable DS Video restore kit from Synology's package archive."""

from __future__ import annotations

import argparse
import hashlib
import html.parser
import json
import os
import platform
import shutil
import ssl
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path


ARCHIVE_ROOT = "https://archive.synology.com/download/Package"
SCRIPT_DIR = Path(__file__).resolve().parent
README_SOURCE = SCRIPT_DIR / "README.md"
if not README_SOURCE.exists():
    README_SOURCE = SCRIPT_DIR / "DS_VIDEO_RESTORE_KIT_README.md"
URL_CONTEXT: ssl.SSLContext | None = None


@dataclass(frozen=True)
class PackageSpec:
    package: str
    version: str
    note: str


TESTED_PACKAGES = [
    PackageSpec("VideoStation", "3.1.0-3153", "tested Video Station build used by the DSM 7.2.2 restore path"),
    PackageSpec("CodecPack", "3.1.0-3005", "tested Advanced Media Extensions / CodecPack build"),
    PackageSpec("MediaServer", "2.0.5-3152", "tested Media Server build used by the DSM 7.2.2 restore path"),
]

OPTIONAL_PACKAGES = [
    PackageSpec("CodecPack", "4.0.0-4025", "non-BSM CodecPack reference build"),
    PackageSpec("Node.js_v22", "22.19.0-1006", "Node.js v22 reference package"),
]

REFERENCE_PACKAGES = [
    PackageSpec("VideoStation", "3.1.1-3168", "newer Video Station reference build; not the tested DSM 7.3.2 VM restore"),
    PackageSpec("MediaServer", "2.2.1-3406", "newer Media Server reference build"),
]


class LinkParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        for name, value in attrs:
            if name.lower() == "href" and value:
                self.links.append(value)


def fetch_text(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "ds-video-restore-kit/1.0"})
    with urllib.request.urlopen(request, timeout=45, context=URL_CONTEXT) as response:
        return response.read().decode("utf-8", "replace")


def archive_links(url: str) -> list[str]:
    parser = LinkParser()
    parser.feed(fetch_text(url))
    return parser.links


def files_for_package(spec: PackageSpec) -> list[tuple[str, str]]:
    index_url = f"{ARCHIVE_ROOT}/{urllib.parse.quote(spec.package)}/{urllib.parse.quote(spec.version)}"
    files: list[tuple[str, str]] = []
    for href in archive_links(index_url):
        parsed = urllib.parse.urlparse(href)
        filename = Path(urllib.parse.unquote(parsed.path)).name
        if filename.endswith(".spk"):
            files.append((filename, urllib.parse.urljoin(index_url + "/", href)))
    if not files:
        raise RuntimeError(f"No SPKs found at {index_url}")
    return sorted(files)


def spk_arch(package: str, version: str, filename: str) -> str | None:
    prefix = f"{package}-"
    suffix = f"-{version}.spk"
    if not filename.startswith(prefix) or not filename.endswith(suffix):
        return None
    return filename[len(prefix) : -len(suffix)]


def detect_synology_arch() -> str:
    env_arch = os.environ.get("SPK_ARCH")
    if env_arch:
        return env_arch

    commands = [
        ["/usr/syno/bin/synogetkeyvalue", "/etc.defaults/synoinfo.conf", "platform_name"],
        ["uname", "-m"],
    ]
    for command in commands:
        try:
            value = subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()
        except (OSError, subprocess.CalledProcessError):
            continue
        if value:
            if value in {"amd64", "x86_64"}:
                return "x86_64"
            if value in {"aarch64", "arm64"}:
                return "armv8"
            return value

    machine = platform.machine().lower()
    if machine in {"amd64", "x86_64"}:
        return "x86_64"
    if machine in {"aarch64", "arm64"}:
        return "armv8"
    return machine


def parse_architectures(value: str) -> list[str]:
    if value == "auto":
        return [detect_synology_arch()]
    return sorted({item.strip() for item in value.split(",") if item.strip()})


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_file(url: str, path: Path, force: bool) -> None:
    if path.exists() and not force:
        print(f"SKIP {path.name}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".part")
    print(f"GET  {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "ds-video-restore-kit/1.0"})
    with urllib.request.urlopen(request, timeout=120, context=URL_CONTEXT) as response, tmp.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    tmp.replace(path)


def copy_restore_files(output: Path) -> None:
    restore = output / "restore-kit"
    rokuvte = restore / "rokuvte"
    revad = restore / "Video_Station_for_DSM_722-1.4.22"
    restore.mkdir(parents=True, exist_ok=True)
    rokuvte.mkdir(parents=True, exist_ok=True)

    copies = [
        (SCRIPT_DIR / "ds-video-restore-kit.sh", restore / "ds-video-restore-kit.sh"),
        (SCRIPT_DIR / "build-ds-video-restore-kit.py", restore / "build-ds-video-restore-kit.py"),
        (README_SOURCE, restore / "README.md"),
        (README_SOURCE, restore / "DS_VIDEO_RESTORE_KIT_README.md"),
        (SCRIPT_DIR / "rokuvte" / "videostation-rokuvte.cgi", rokuvte / "videostation-rokuvte.cgi"),
        (SCRIPT_DIR / "rokuvte" / "install-videostation-rokuvte-wrapper.sh", rokuvte / "install-videostation-rokuvte-wrapper.sh"),
        (SCRIPT_DIR / "rokuvte" / "rokuvte-launcher.c", rokuvte / "rokuvte-launcher.c"),
        (SCRIPT_DIR / "rokuvte" / "videostation-rokuvte-go.go", rokuvte / "videostation-rokuvte-go.go"),
    ]
    for src, dst in copies:
        if src.exists():
            shutil.copy2(src, dst)
    source_revad = SCRIPT_DIR / "Video_Station_for_DSM_722-1.4.22"
    if source_revad.exists():
        if revad.exists():
            shutil.rmtree(revad)
        shutil.copytree(source_revad, revad, ignore=shutil.ignore_patterns("@eaDir", ".DS_Store", "__pycache__"))
    for script in [restore / "ds-video-restore-kit.sh", rokuvte / "videostation-rokuvte.cgi"]:
        if script.exists():
            script.chmod(script.stat().st_mode | 0o755)


def write_checksums(package_dir: Path) -> None:
    lines = []
    for path in sorted(package_dir.rglob("*.spk")):
        rel = path.relative_to(package_dir).as_posix()
        lines.append(f"{sha256_file(path)}  {rel}")
    (package_dir / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_manifest(output: Path, manifest: list[dict[str, str]]) -> None:
    (output / "restore-kit" / "packages" / "download-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


def make_archives(output: Path) -> None:
    zip_path = output.with_suffix(".zip")
    tar_path = output.with_suffix(".tar.gz")
    if zip_path.exists():
        zip_path.unlink()
    if tar_path.exists():
        tar_path.unlink()

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(output.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(output.parent))

    with tarfile.open(tar_path, "w:gz") as archive:
        archive.add(output, arcname=output.name)

    print(f"Wrote {zip_path}")
    print(f"Wrote {tar_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="ds-video-restore-kit-download", help="Output folder to build.")
    parser.add_argument(
        "--arch",
        default="x86_64",
        help="Architecture to download, comma-separated list, 'auto', or use --all-architectures. Default: x86_64.",
    )
    parser.add_argument("--all-architectures", action="store_true", help="Download every architecture found for each package.")
    parser.add_argument("--include-optional", action="store_true", help="Include optional reference packages such as Node.js_v22.")
    parser.add_argument("--include-reference", action="store_true", help="Include newer reference builds that were not the tested VM path.")
    parser.add_argument("--force", action="store_true", help="Redownload files that already exist.")
    parser.add_argument("--no-archive", action="store_true", help="Do not create .zip and .tar.gz archives.")
    parser.add_argument("--insecure", action="store_true", help="Disable HTTPS certificate verification if local Python CA certificates are broken.")
    args = parser.parse_args()

    global URL_CONTEXT
    if args.insecure:
        URL_CONTEXT = ssl._create_unverified_context()

    output = Path(args.output).resolve()
    packages = list(TESTED_PACKAGES)
    if args.include_optional:
        packages.extend(OPTIONAL_PACKAGES)
    if args.include_reference:
        packages.extend(REFERENCE_PACKAGES)

    wanted_arches = set(parse_architectures(args.arch))
    if args.all_architectures:
        wanted_arches = set()

    copy_restore_files(output)
    package_dir = output / "restore-kit" / "packages"
    manifest: list[dict[str, str]] = []

    for spec in packages:
        available = files_for_package(spec)
        selected = []
        for filename, url in available:
            arch = spk_arch(spec.package, spec.version, filename)
            if arch is None:
                continue
            if args.all_architectures or arch in wanted_arches:
                selected.append((arch, filename, url))

        if not selected:
            available_arches = ", ".join(
                sorted(filter(None, (spk_arch(spec.package, spec.version, filename) for filename, _ in available)))
            )
            raise RuntimeError(
                f"No {spec.package} {spec.version} SPK for {sorted(wanted_arches)}. Available: {available_arches}"
            )

        for arch, filename, url in selected:
            target = package_dir / arch / filename
            download_file(url, target, args.force)
            manifest.append(
                {
                    "package": spec.package,
                    "version": spec.version,
                    "arch": arch,
                    "filename": filename,
                    "url": url,
                    "note": spec.note,
                }
            )

    write_manifest(output, manifest)
    write_checksums(package_dir)
    if not args.no_archive:
        make_archives(output)

    print(f"Done: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
