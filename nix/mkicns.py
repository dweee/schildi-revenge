"""Build a macOS .icns (PNG payloads) from one square PNG, scaling with ImageMagick."""
import struct
import subprocess
import sys
import tempfile

src, dst = sys.argv[1], sys.argv[2]
# icns type -> pixel size (PNG-compressed variants understood by macOS 10.7+)
sizes = {b"ic07": 128, b"ic08": 256, b"ic09": 512, b"ic10": 1024}

chunks = b""
with tempfile.TemporaryDirectory() as tmp:
    for kind, px in sizes.items():
        out = f"{tmp}/{px}.png"
        subprocess.run(
            ["magick", src, "-resize", f"{px}x{px}", "-background", "none", "-gravity", "center",
             "-extent", f"{px}x{px}", f"PNG32:{out}"],
            check=True,
        )
        data = open(out, "rb").read()
        chunks += kind + struct.pack(">I", len(data) + 8) + data

with open(dst, "wb") as f:
    f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
