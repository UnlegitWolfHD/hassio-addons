import json, pathlib, shlex, subprocess, textwrap, sys, os
snippet = pathlib.Path(r"D:/Homeasssistant addons/ledfx/run.sh").read_text(encoding="utf-8")
body = snippet.split("<<'PY'\n",1)[1].split("\nPY\n",1)[0]
for opts in [{}, {"port": 9000, "log_level": "trace", "null_sink": True, "audio_source": "a b'c"}]:
    p = pathlib.Path("options.json"); p.write_text(json.dumps(opts))
    code = body.replace('"/data/options.json"', '"options.json"')
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    check = subprocess.run(["sh", "-c", f'eval "{out.stdout}"' .replace('"','\'') + '; echo "$PORT|$LOG_LEVEL|$NULL_SINK|$AUDIO_SOURCE"'], capture_output=True, text=True)
    print(repr(opts), "->", out.stdout.replace("\n"," "))
