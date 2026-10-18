#!/usr/bin/env python3
"""Validate staged Android Maven artifacts; --push publishes an immutable version."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import io
import zipfile
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GROUP = "io.github.felikslv01.viewin"
MODULES = ("viewin-protocol", "viewin-sdk", "viewin-compose")
REPO = "https://github.com/FeliksLv01/ViewinSDK"
NS = {"m": "http://maven.apache.org/POM/4.0.0"}


def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()


def version():
    values = dict(line.split("=", 1) for line in (ROOT / "android/gradle.properties").read_text().splitlines()
                  if "=" in line and not line.startswith("#"))
    value = values["viewinVersion"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError("viewinVersion must be a stable x.y.z version")
    return value


def checksums(path):
    for algorithm in ("md5", "sha1", "sha256", "sha512"):
        path.with_name(path.name + "." + algorithm).write_text(
            hashlib.new(algorithm, path.read_bytes()).hexdigest())


def validate(staging, release, require_signatures=False):
    group_path = staging / GROUP.replace(".", "/")
    for module in MODULES:
        directory = group_path / module / release
        stem = f"{module}-{release}"
        extension = "jar" if module == "viewin-protocol" else "aar"
        for suffix in (f".{extension}", "-sources.jar", "-javadoc.jar", ".pom", ".module"):
            path = directory / (stem + suffix)
            if not path.is_file() or not path.stat().st_size:
                raise ValueError(f"Missing artifact: {path}")
            if require_signatures:
                signature = path.with_name(path.name + ".asc")
                if not signature.is_file() or "-----BEGIN PGP SIGNATURE-----" not in signature.read_text():
                    raise ValueError(f"Missing PGP signature: {path}")
            for algorithm in ("md5", "sha1", "sha256", "sha512"):
                expected = hashlib.new(algorithm, path.read_bytes()).hexdigest()
                if path.with_name(path.name + "." + algorithm).read_text().strip() != expected:
                    raise ValueError(f"Checksum mismatch: {path}")
        with zipfile.ZipFile(directory / (stem + "." + extension)) as archive:
            if extension == "aar":
                with zipfile.ZipFile(io.BytesIO(archive.read("classes.jar"))) as classes:
                    notice = classes.read("META-INF/LICENSE-" + module)
            else:
                notice = archive.read("META-INF/LICENSE-" + module)
            if notice != (ROOT / "LICENSE").read_bytes():
                raise ValueError(f"Missing or incorrect license notice for {module}")
        with zipfile.ZipFile(directory / (stem + "-javadoc.jar")) as documentation:
            if "index.html" not in documentation.namelist():
                raise ValueError(f"Missing generated API documentation for {module}")
        pom = ET.parse(directory / (stem + ".pom")).getroot()
        for key, expected in (("groupId", GROUP), ("artifactId", module), ("version", release)):
            if pom.findtext("m:" + key, namespaces=NS) != expected:
                raise ValueError(f"Incorrect {key} for {module}")
        dependency = {"viewin-sdk": "viewin-protocol", "viewin-compose": "viewin-sdk"}.get(module)
        if dependency and not any(
            node.findtext("m:groupId", namespaces=NS) == GROUP
            and node.findtext("m:artifactId", namespaces=NS) == dependency
            and node.findtext("m:version", namespaces=NS) == release
            for node in pom.findall("m:dependencies/m:dependency", NS)
        ):
            raise ValueError(f"Missing transitive dependency for {module}")
    return group_path


def publish(staging, release):
    if git("status", "--porcelain"):
        raise ValueError("Commit source changes before publishing")
    remote = git("remote", "get-url", "origin")
    if not re.fullmatch(r"(?:https://github.com/|git@github.com:|ssh://git@ssh.github.com:443/)FeliksLv01/ViewinSDK(?:\.git)?", remote):
        raise ValueError("origin must point to FeliksLv01/ViewinSDK")
    source_commit = git("rev-parse", "HEAD")
    exists = bool(git("ls-remote", "origin", "refs/heads/maven"))
    with tempfile.TemporaryDirectory(prefix="viewin-maven-") as temporary:
        checkout = Path(temporary) / "repository"
        if exists:
            # Published artifacts are public and never require a consumer token.
            git("clone", "--quiet", "--single-branch", "--branch", "maven", REPO + ".git", str(checkout))
        else:
            checkout.mkdir()
            git("init", "--quiet", "--initial-branch=maven", cwd=checkout)
        for key in ("user.name", "user.email"):
            git("config", key, git("config", key), cwd=checkout)
        hashes = {}
        for module in MODULES:
            relative = Path(GROUP.replace(".", "/")) / module
            source = staging / relative / release
            destination = checkout / relative / release
            if destination.exists():
                raise ValueError(f"Version already published: {module}:{release}; bump viewinVersion")
            shutil.copytree(source, destination)
            for path in sorted(destination.iterdir()):
                hashes[str(path.relative_to(checkout))] = hashlib.sha256(path.read_bytes()).hexdigest()
            versions = sorted((p.name for p in destination.parent.iterdir() if p.is_dir()
                               and re.fullmatch(r"\d+\.\d+\.\d+", p.name)),
                              key=lambda value: tuple(map(int, value.split("."))))
            metadata = ET.Element("metadata")
            ET.SubElement(metadata, "groupId").text = GROUP
            ET.SubElement(metadata, "artifactId").text = module
            info = ET.SubElement(metadata, "versioning")
            ET.SubElement(info, "latest").text = versions[-1]
            ET.SubElement(info, "release").text = versions[-1]
            items = ET.SubElement(info, "versions")
            for item in versions:
                ET.SubElement(items, "version").text = item
            ET.SubElement(info, "lastUpdated").text = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
            metadata_path = destination.parent / "maven-metadata.xml"
            ET.indent(metadata)
            ET.ElementTree(metadata).write(metadata_path, encoding="utf-8", xml_declaration=True)
            checksums(metadata_path)
        shutil.copy2(ROOT / "LICENSE", checkout / "LICENSE")
        (checkout / "README.md").write_text(
            "# Viewin Android Maven repository\n\n"
            "Generated artifacts only. [Source and integration guide](" + REPO + ").\n\n"
            "Repository URL: `https://raw.githubusercontent.com/FeliksLv01/ViewinSDK/maven`\n")
        manifest = checkout / "versions" / (release + ".json")
        manifest.parent.mkdir(exist_ok=True)
        manifest.write_text(json.dumps({"version": release, "sourceCommit": source_commit,
                                       "sha256": hashes}, indent=2) + "\n")
        git("add", ".", cwd=checkout)
        git("commit", "--quiet", "-m", f"Publish Android SDK {release} from {source_commit[:12]}", cwd=checkout)
        commit = git("rev-parse", "HEAD", cwd=checkout)
        # Push through the source repository to reuse its configured authentication.
        # No source checkout, branch switch, force push, or credential export is needed.
        git("fetch", "--quiet", str(checkout), "HEAD")
        git("push", "origin", f"{commit}:refs/heads/maven")
        print(f"Published {release}: https://raw.githubusercontent.com/FeliksLv01/ViewinSDK/maven")



def archive(staging, release, output, require_signatures=False):
    validate(staging, release, require_signatures)
    output.parent.mkdir(parents=True, exist_ok=True)
    paths = []
    for module in MODULES:
        folder = staging / GROUP.replace(".", "/") / module
        paths.extend(p for p in (folder / release).iterdir() if p.is_file())
        paths.extend(p for p in folder.glob("maven-metadata.xml*") if p.is_file())
    hashes = {str(p.relative_to(staging)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
    manifest = {"version": release, "sourceCommit": git("rev-parse", "HEAD"), "sha256": hashes}
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(paths):
            bundle.write(path, str(path.relative_to(staging)))
        bundle.write(ROOT / "LICENSE", "LICENSE")
        bundle.writestr("release.json", json.dumps(manifest, indent=2) + "\n")
    output.with_suffix(output.suffix + ".sha256").write_text(
        hashlib.sha256(output.read_bytes()).hexdigest() + "  " + output.name + "\n")
    print(f"Created {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--push", action="store_true", help="Push validated artifacts to the public maven branch")
    parser.add_argument("--archive", type=Path, help="Create a Maven repository ZIP for GitHub Releases")
    parser.add_argument("--require-signatures", action="store_true", help="Require PGP signature files for Central release artifacts")
    args = parser.parse_args()
    release = version()
    staging = ROOT / "android/build/maven"
    validate(staging, release, args.require_signatures)
    print(f"Validated all three modules for {release}")
    if args.archive:
        archive(staging, release, args.archive, args.require_signatures)
    if args.push:
        publish(staging, release)


if __name__ == "__main__":
    main()
