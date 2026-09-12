#!/usr/bin/env python3
"""Selbsttest fuer homeassistant/ledfx_package.yaml.

Prueft, dass die YAML gueltig ist, jedes Jinja-Template syntaktisch stimmt und
die Templates der Lampe gegen eine echte LedFx-Antwort die richtigen Werte
liefern. Aufruf:  python test_ha_package.py

Die Beispielantwort entspricht dem Aufbau von make_virtual_response() aus
ledfx/api/virtual.py (v2.1.9).
"""

import sys

import jinja2
import yaml

PACKAGE = "homeassistant/ledfx_package.yaml"

VIRTUALS = {
    "wled-gledopto": {
        "id": "wled-gledopto",
        "active": True,
        "streaming": True,
        "pixel_count": 806,
        "effect": {
            "type": "melt",
            "name": "Melt",
            "config": {"brightness": 0.5, "blur": 3.0},
        },
    },
    "andere-lampe": {"id": "andere-lampe", "active": False, "effect": {}},
}

failures = []


def check(label, condition, detail=""):
    if condition:
        print(f"  OK   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


def main() -> int:
    with open(PACKAGE, encoding="utf-8") as handle:
        package = yaml.safe_load(handle)

    env = jinja2.Environment()
    env.globals.update(
        state_attr=lambda entity, attr: {"virtuals": VIRTUALS}.get(attr),
        states=lambda entity: "50",
    )

    # 1. Jedes Template im Paket muss syntaktisch gueltig sein.
    parsed = 0

    def walk(node, path="root"):
        nonlocal parsed
        if isinstance(node, str):
            if "{{" in node or "{%" in node:
                try:
                    env.parse(node)
                    parsed += 1
                except jinja2.TemplateSyntaxError as exc:
                    failures.append(f"{path}: {exc}")
        elif isinstance(node, dict):
            for key, value in node.items():
                walk(value, f"{path}.{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]")

    walk(package)
    check(f"{parsed} Jinja-Templates syntaktisch gueltig", not failures)

    # 2. Die Lampe muss aus der LedFx-Antwort die richtigen Werte ableiten.
    light = package["template"][0]["light"][0]
    render = lambda key: env.from_string(light[key]).render().strip()

    check("Lampe meldet 'an', wenn das Virtual aktiv ist", render("state") == "True",
          f"-> {render('state')}")
    check("Helligkeit 0.5 wird zu 128 von 255", render("level") == "128.0",
          f"-> {render('level')}")
    check("aktiver Effekt wird uebernommen", render("effect") == "melt",
          f"-> {render('effect')}")

    effects = env.from_string(light["effect_list"]).render()
    check("Effektliste enthaelt melt und bar",
          "'melt'" in effects and "'bar'" in effects)
    check("Effektliste enthaelt keine 2D-Effekte",
          "soap2d" not in effects and "keybeat2d" not in effects)

    # 3. Pflichtschluessel der Template-Lampe (HA: turn_on/turn_off sind
    #    Required, effect/effect_list/set_effect nur gemeinsam erlaubt).
    for key in ("turn_on", "turn_off", "state", "level", "set_level"):
        check(f"Lampe definiert '{key}'", key in light)
    effect_keys = {"effect", "effect_list", "set_effect"}
    check("Effekt-Schluessel vollstaendig oder gar nicht",
          effect_keys <= set(light) or not (effect_keys & set(light)))

    # 4. Jeder rest_command braucht Methode, Typ und Payload.
    for name, command in package["rest_command"].items():
        check(f"rest_command.{name} vollstaendig",
              {"url", "method"} <= set(command)
              and (command["method"] == "get" or "payload" in command))

    print()
    if failures:
        print(f"FEHLGESCHLAGEN: {len(failures)}")
        return 1
    print("ALLE TESTS OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
