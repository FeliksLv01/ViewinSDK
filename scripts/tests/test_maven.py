import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("publish_maven", Path(__file__).parents[1] / "publish-maven.py")
maven = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(maven)


class MavenArtifactsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.staging = Path(self.temporary.name) / "maven"
        shutil.copytree(maven.ROOT / "android/build/maven", self.staging)
        self.release = maven.version()

    def artifact(self, module, suffix):
        return self.staging / maven.GROUP.replace(".", "/") / module / self.release / f"{module}-{self.release}{suffix}"

    def test_complete_artifacts_and_transitive_dependencies(self):
        maven.validate(self.staging, self.release)

    def test_corrupted_binary_is_rejected(self):
        self.artifact("viewin-sdk", ".aar").write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            maven.validate(self.staging, self.release)

    def test_missing_transitive_dependency_is_rejected(self):
        path = self.artifact("viewin-compose", ".pom")
        path.write_text(path.read_text().replace("<artifactId>viewin-sdk</artifactId>", "<artifactId>missing-sdk</artifactId>"))
        maven.checksums(path)
        with self.assertRaisesRegex(ValueError, "Missing transitive dependency"):
            maven.validate(self.staging, self.release)

    def test_missing_sources_is_rejected(self):
        self.artifact("viewin-sdk", "-sources.jar").unlink()
        with self.assertRaisesRegex(ValueError, "Missing artifact"):
            maven.validate(self.staging, self.release)

    def test_unsigned_release_cannot_pass_signature_gate(self):
        with self.assertRaisesRegex(ValueError, "Missing PGP signature"):
            maven.validate(self.staging, self.release, require_signatures=True)

    def test_release_archive_has_dependency_metadata_and_provenance(self):
        import zipfile
        import json
        output = Path(self.temporary.name) / "release.zip"
        maven.archive(self.staging, self.release, output)
        with zipfile.ZipFile(output) as bundle:
            manifest = json.loads(bundle.read("release.json"))
            self.assertEqual(manifest["version"], self.release)
            self.assertIn("LICENSE", bundle.namelist())
            for module in maven.MODULES:
                self.assertIn(f"{maven.GROUP.replace('.', '/')}/{module}/{self.release}/{module}-{self.release}.pom", bundle.namelist())
        self.assertTrue(output.with_suffix(".zip.sha256").is_file())
        with self.assertRaises(FileExistsError):
            maven.archive(self.staging, self.release, output)
