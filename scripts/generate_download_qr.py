from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_M

APK_URL = (
    "https://github.com/hesaaam/hesam-void/releases/download/"
    "v4.0.0/hesam-void-v4.0.0-universal.apk"
)
OUTPUT_PATH = Path("assets/images/hesam-void-v4.0.0-download-qr.png")


def main() -> None:
    qr = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECT_M,
        box_size=14,
        border=4,
    )
    qr.add_data(APK_URL)
    qr.make(fit=True)
    image = qr.make_image(fill_color="#000000", back_color="#FFFFFF")
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT_PATH)
    print(f"Generated {OUTPUT_PATH} for {APK_URL}")


if __name__ == "__main__":
    main()
