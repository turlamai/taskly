#!/usr/bin/env python3
"""Keep Taskly's shared palette aligned and enforce useful contrast floors.

Canonical token values live in design/prototype/shared.css — the prototype
is the single source. This gate parses them from the CSS and enforces the
three host implementations against the parsed values. Do not duplicate
values here: change shared.css and align the hosts in the same slice."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CSS = (ROOT / "design" / "prototype" / "shared.css").read_text(encoding="utf-8")

# CSS custom property -> gate slot pair (light, dark)
CORE_VARS = {
    "--accent": ("accentLight", "accentDark"),
    "--bg": ("lightBackground", "darkBackground"),
    "--sidebar": ("lightSidebar", "darkSidebar"),
    "--surface": ("lightSurface", "darkSurface"),
    "--divider": ("lightDivider", "darkDivider"),
    "--ink": ("lightOnSurface", "darkOnSurface"),
    "--ink2": ("lightSecondaryText", "darkSecondaryText"),
    "--ink3": ("lightTertiaryText", "darkTertiaryText"),
    "--input-border": ("lightInputBorder", "darkInputBorder"),
}


def fail(message: str):
    raise SystemExit(message)


def block(pattern: str) -> str:
    found = re.search(pattern, CSS, re.S)
    if not found:
        fail(f"shared.css: cannot locate canonical block for {pattern!r}")
    return found.group(1)


def parse_vars(body: str) -> dict:
    return {
        name: value.strip()
        for name, value in re.findall(r"(--[a-z0-9-]+)\s*:\s*([^;]+);", body)
    }


light = parse_vars(block(r":root\s*\{([^}]*)\}"))
dark = parse_vars(block(r'html\[data-taskly-theme="dark"\]\s*\.window\s*\{([^}]*)\}'))

TOKENS: dict[str, str] = {}
for var, (light_slot, dark_slot) in CORE_VARS.items():
    for values, slot in ((light, light_slot), (dark, dark_slot)):
        if var not in values:
            fail(f"shared.css: missing canonical var {var} for {slot}")
        TOKENS[slot] = values[var].lstrip("#").upper()


def solid(values: dict, var: str) -> str:
    if var not in values:
        fail(f"shared.css: missing canonical var {var}")
    return values[var].lstrip("#").upper()


def argb(values: dict, var: str) -> str:
    raw = values.get(var)
    if not raw:
        fail(f"shared.css: missing canonical var {var}")
    match = re.match(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*([0-9.]+)\)$", raw)
    if not match:
        fail(f"shared.css: cannot parse rgba var {var}: {raw!r}")
    red, green, blue, alpha = (
        int(match[1]), int(match[2]), int(match[3]), float(match[4]),
    )
    return f"{round(alpha * 255):02X}{red:02X}{green:02X}{blue:02X}"


def channel(value: int) -> float:
    normalized = value / 255
    return normalized / 12.92 if normalized <= 0.04045 else ((normalized + 0.055) / 1.055) ** 2.4


def luminance(hex_value: str) -> float:
    red, green, blue = (int(hex_value[index:index + 2], 16) for index in (0, 2, 4))
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)


def contrast(first: str, second: str) -> float:
    high, low = sorted((luminance(first), luminance(second)), reverse=True)
    return (high + 0.05) / (low + 0.05)


def require(path: str, fragments: list) -> None:
    content = (ROOT / path).read_text(encoding="utf-8")
    missing = [fragment for fragment in fragments if fragment not in content]
    if missing:
        raise SystemExit(f"{path} does not implement canonical tokens: {missing}")


def main() -> None:
    require(
        "macos-host/Sources/RivetHost/Theme.swift",
        [f"0x{value}" for value in TOKENS.values()],
    )
    require(
        "linux/src/main.cpp",
        [f'"#{value}"' for value in TOKENS.values()],
    )
    # Overdue red stays the classic system red until D12 migrates Windows
    # (and Linux) overdue text to the danger pair — see DESIGN-TOKENS ledger.
    windows_values = [
        TOKENS["accentLight"], TOKENS["accentDark"],
        TOKENS["lightSidebar"], TOKENS["darkSidebar"],
        TOKENS["lightSurface"], TOKENS["darkSurface"],
        TOKENS["lightDivider"], TOKENS["darkDivider"],
        TOKENS["lightSecondaryText"], TOKENS["lightTertiaryText"],
        TOKENS["darkSecondaryText"], TOKENS["darkTertiaryText"],
        argb(light, "--sel"), argb(dark, "--sel"),
        argb(light, "--hover"), argb(dark, "--hover"),
        solid(light, "--planned"),
        solid(light, "--today"),
        solid(light, "--gray-tile"),
    ]
    require(
        "windows/MainWindow.xaml",
        [f'Color="#{value}"' for value in windows_values],
    )

    checks = {
        "light primary text": ("lightOnSurface", "lightBackground", 4.5),
        "light secondary text": ("lightSecondaryText", "lightBackground", 4.5),
        "light tertiary text": ("lightTertiaryText", "lightBackground", 4.5),
        "light action accent": ("accentLight", "lightBackground", 4.5),
        "light input boundary": ("lightInputBorder", "lightBackground", 3.0),
        "dark primary text": ("darkOnSurface", "darkBackground", 4.5),
        "dark secondary text": ("darkSecondaryText", "darkBackground", 4.5),
        "dark tertiary text": ("darkTertiaryText", "darkBackground", 4.5),
        "dark action accent": ("accentDark", "darkBackground", 4.5),
        "dark input boundary": ("darkInputBorder", "darkBackground", 3.0),
    }
    for label, (foreground, background, minimum) in checks.items():
        ratio = contrast(TOKENS[foreground], TOKENS[background])
        if ratio < minimum:
            raise SystemExit(f"{label}: {ratio:.2f}:1 is below {minimum:.1f}:1")
        print(f"ok: {label} {ratio:.2f}:1")

    print(f"ok: canonical source design/prototype/shared.css ({len(TOKENS)} core slots)")


if __name__ == "__main__":
    main()
