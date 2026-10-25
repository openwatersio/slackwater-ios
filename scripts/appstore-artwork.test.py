import pathlib
import subprocess
import tempfile
import unittest
import struct
import zlib


class ArtworkChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.binary = str(pathlib.Path(cls.build.name) / "artwork")
        subprocess.run(["swiftc", "-module-cache-path", "/tmp/slackwater-artwork-modulecache",
                        "scripts/appstore-artwork.swift", "-o", cls.binary], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def fixture(self, path, width, height):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        data = b"\x00" + bytes([40, 90, 130]) * width
        path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(data * height)) + chunk(b"IEND", b""))

    def test_missing_captures_do_not_create_upload_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "upload"
            result = subprocess.run(
                [self.binary, directory, directory, str(output)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing capture", result.stderr)
            self.assertFalse(output.exists())

    def test_exports_six_opaque_frames_and_rejects_overwrite_and_mixed_sizes(self):
        with tempfile.TemporaryDirectory() as directory:
            raw = pathlib.Path(directory)
            names = ["01-currents-slack.png", "02-tide-rising.png", "03-scrubber.png",
                     "04-nearby.png", "05-map.png"]
            for name in names:
                self.fixture(raw / name, 1206, 2622)
            self.fixture(raw / "widgets.png", 1000, 1020)
            self.fixture(raw / "02-tide.png", 422, 514)
            output = raw / "upload"
            command = [self.binary, str(raw), str(raw), str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            files = sorted(output.glob("*.png"))
            self.assertEqual(len(files), 6)
            self.assertEqual(files[2].name, "03-widgets-watch.png")
            for path in files:
                data = path.read_bytes()
                self.assertEqual(struct.unpack(">II", data[16:24]), (1206, 2622))
                self.assertEqual(data[25], 2, "PNG must be opaque RGB")
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertIn("already exists", result.stderr)
            self.fixture(raw / names[1], 1179, 2556)
            result = subprocess.run(command[:-1] + [str(raw / "mixed")], capture_output=True, text=True)
            self.assertIn("mixed dimensions", result.stderr)
            self.assertFalse((raw / "mixed").exists())


if __name__ == "__main__":
    unittest.main()
