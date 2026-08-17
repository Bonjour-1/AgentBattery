from pathlib import Path
import unittest

from PIL import Image


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ICON_PATHS = (
    REPOSITORY_ROOT / "windows/runner/resources/app_icon.ico",
    REPOSITORY_ROOT / "windows/runner/resources/app_icon_catgirl_hidden.ico",
)
RUNNER_RESOURCE = REPOSITORY_ROOT / "windows/runner/Runner.rc"
TRAY_SERVICE = REPOSITORY_ROOT / "lib/services/tray_service.dart"
REQUIRED_SIZES = frozenset(
    (size, size) for size in (16, 20, 24, 32, 40, 48, 64, 256)
)


def read_ico_sizes(path: Path) -> frozenset[tuple[int, int]]:
    with Image.open(path) as image:
        if image.format != "ICO":
            raise AssertionError(f"{path} is {image.format}, not ICO")

        sizes = frozenset(image.ico.sizes())
        for size in sizes:
            frame = image.ico.getimage(size)
            frame.load()
            if frame.size != size:
                raise AssertionError(f"ICO entry {size} decoded as {frame.size}")
        return sizes


class WindowsIconAssetsTest(unittest.TestCase):
    def test_icons_have_all_required_sizes(self) -> None:
        for path in ICON_PATHS:
            with self.subTest(icon=path.name):
                self.assertTrue(path.is_file(), f"missing generated icon: {path}")
                actual_sizes = read_ico_sizes(path)
                self.assertEqual(
                    REQUIRED_SIZES,
                    actual_sizes,
                    "incorrect ICO sizes: "
                    f"missing={sorted(REQUIRED_SIZES - actual_sizes)}, "
                    f"unexpected={sorted(actual_sizes - REQUIRED_SIZES)}",
                )

    def test_all_build_modes_use_default_icon(self) -> None:
        resource = RUNNER_RESOURCE.read_text(encoding="utf-8")
        tray = TRAY_SERVICE.read_text(encoding="utf-8")
        self.assertNotIn("app_icon_catgirl_hidden.ico", resource)
        self.assertIn('"resources\\\\app_icon.ico"', resource)
        self.assertNotIn("kDebugMode", tray)
        self.assertNotIn("app_icon_catgirl_hidden.ico", tray)
        self.assertIn("app_icon.ico", tray)


if __name__ == "__main__":
    unittest.main()
