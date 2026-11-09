"""Reads the Aproid mark out of aproid-logo.svg and normalises it to a unit square."""
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SVG = "{http://www.w3.org/2000/svg}"
XLINK = "{http://www.w3.org/1999/xlink}"


class Affine:
    def __init__(self, a=1.0, b=0.0, c=0.0, d=1.0, e=0.0, f=0.0):
        self.m = (a, b, c, d, e, f)

    @classmethod
    def parse(cls, text):
        values = [float(v) for v in re.findall(r"-?[\d.]+(?:e-?\d+)?", text or "")]
        return cls(*values) if text and text.startswith("matrix") else cls()

    def then(self, other):
        a, b, c, d, e, f = self.m
        A, B, C, D, E, F = other.m
        return Affine(A * a + C * b, B * a + D * b, A * c + C * d, B * c + D * d, A * e + C * f + E, B * e + D * f + F)

    def apply(self, x, y):
        a, b, c, d, e, f = self.m
        return a * x + c * y + e, b * x + d * y + f


class Mark:
    """The logo path as absolute cubic/line segments in unit coordinates, centred in a square."""

    def __init__(self, source: Path):
        root = ET.parse(source).getroot()
        group = root.find(f".//{SVG}g[@id='logo-aproid']")
        path = group.find(f"{SVG}path")
        to_user = Affine.parse(group.get("transform"))

        self.commands = self._absolute(path.get("d"), to_user)
        self.stops, (g0, g1) = self._gradient(root, path, to_user)

        xs = [x for _, pts in self.commands for x, _ in pts]
        ys = [y for _, pts in self.commands for _, y in pts]
        side = max(max(xs) - min(xs), max(ys) - min(ys))
        ox = min(xs) - (side - (max(xs) - min(xs))) / 2
        oy = min(ys) - (side - (max(ys) - min(ys))) / 2
        unit = lambda p: ((p[0] - ox) / side, (p[1] - oy) / side)

        self.commands = [(op, [unit(p) for p in pts]) for op, pts in self.commands]
        self.gradient = (unit(g0), unit(g1))
        self.width = (max(xs) - min(xs)) / side

    @staticmethod
    def _absolute(d, to_user):
        tokens = re.findall(r"[a-zA-Z]|-?[\d.]+(?:e-?\d+)?", d)
        out, i, op = [], 0, None
        x = y = sx = sy = 0.0

        def num():
            nonlocal i
            i += 1
            return float(tokens[i - 1])

        while i < len(tokens):
            if tokens[i].isalpha():
                op = tokens[i]
                i += 1
            rel = op.islower()
            kind = op.lower()

            if kind == "z":
                out.append(("Z", []))
                x, y = sx, sy
                op = None
                continue
            if kind == "m":
                dx, dy = num(), num()
                x, y = (x + dx, y + dy) if rel else (dx, dy)
                sx, sy = x, y
                out.append(("M", [(x, y)]))
                op = "l" if rel else "L"
            elif kind == "l":
                dx, dy = num(), num()
                x, y = (x + dx, y + dy) if rel else (dx, dy)
                out.append(("L", [(x, y)]))
            elif kind == "h":
                v = num()
                x = x + v if rel else v
                out.append(("L", [(x, y)]))
            elif kind == "v":
                v = num()
                y = y + v if rel else v
                out.append(("L", [(x, y)]))
            elif kind == "c":
                pts = []
                for _ in range(3):
                    dx, dy = num(), num()
                    pts.append((x + dx, y + dy) if rel else (dx, dy))
                x, y = pts[-1]
                out.append(("C", pts))
            else:
                raise ValueError(f"Unsupported path command {op}")

        return [(op, [to_user.apply(*p) for p in pts]) for op, pts in out]

    @staticmethod
    def _gradient(root, path, to_user):
        ref = re.search(r"url\(#([^)]+)\)", path.get("style")).group(1)
        grads = {g.get("id"): g for g in root.iter(f"{SVG}linearGradient")}
        grad = grads[ref]
        base = grads[grad.get(XLINK + "href").lstrip("#")]
        stops = [re.search(r"stop-color:(#[0-9a-fA-F]{6})", s.get("style")).group(1) for s in base.iter(f"{SVG}stop")]
        to_grad = Affine.parse(grad.get("gradientTransform")).then(to_user)
        p0 = to_grad.apply(float(grad.get("x1")), float(grad.get("y1")))
        p1 = to_grad.apply(float(grad.get("x2")), float(grad.get("y2")))

        return stops, (p0, p1)

    def path_data(self, scale=1.0, dx=0.0, dy=0.0, digits=2):
        fmt = lambda p: f"{round(p[0] * scale + dx, digits):g},{round(p[1] * scale + dy, digits):g}"

        return " ".join(op + (" ".join(fmt(p) for p in pts)) for op, pts in self.commands)
