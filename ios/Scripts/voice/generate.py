#!/usr/bin/env python3
"""Records every phrase the app reads aloud with a local neural voice and writes AAC files
named by VoicePrompts.key(text) into ios/TinnitusLab/Resources/Voice/.

Everything runs offline on the Mac; no text leaves the machine.

  python ios/Scripts/voice/generate.py                      # Chatterbox, German reference voice
  python ios/Scripts/voice/generate.py --engine piper       # Piper only (fast, more synthetic)
  python ios/Scripts/voice/generate.py --only 47073fa7a6d1c6d8 --force
  python ios/Scripts/voice/generate.py --samples out/       # a few phrases per engine to compare

Engines
  chatterbox  Resemble AI Chatterbox Multilingual (MIT). Natural prosody; the timbre comes from a short
              German reference clip (by default rendered with Piper's Thorsten voice, CC0).
  piper       Piper TTS with de_DE-thorsten-high (voice CC0, Thorsten dataset).

Setup (see README.md next to this file): Python 3.12 venv with `pip install chatterbox-tts piper-tts`.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]          # ios/
OUT = ROOT / "TinnitusLab" / "Resources" / "Voice"
CACHE = Path(os.environ.get("VOICE_CACHE", Path.home() / ".cache" / "tinnitus-voice"))
PIPER_VOICE = "de_DE-thorsten-high"
PIPER_URL = f"https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/high/{PIPER_VOICE}"
REFERENCE_TEXT = ("Setz dich bequem hin und atme ruhig. Lass die Schultern sinken und spür, "
                  "wie dein Atem ganz von selbst kommt und geht. Es gibt nichts zu tun.")


def prompts():
    """Exports the phrases from the Swift content package (single source of truth)."""
    out = subprocess.run(["swift", "run", "-q", "--package-path", str(ROOT / "Packages" / "TinnitusCore"), "voice-prompts"],
                         check=True, capture_output=True, text=True).stdout
    items = json.loads(out)
    for it in items:  # must match VoicePrompts.key
        assert it["key"] == hashlib.sha256(it["text"].encode()).hexdigest()[:16], it
    return items


# ---------- engines ----------

def piper_voice():
    CACHE.mkdir(parents=True, exist_ok=True)
    onnx = CACHE / f"{PIPER_VOICE}.onnx"
    for suffix in (".onnx", ".onnx.json"):
        f = CACHE / f"{PIPER_VOICE}{suffix}"
        if not f.exists():
            print(f"downloading {f.name} …", file=sys.stderr)
            subprocess.run(["curl", "-sSfL", "-o", str(f), PIPER_URL + suffix], check=True)
    import piper
    from piper import PiperVoice
    # espeak-ng only accepts data paths up to ~160 characters; deep venvs exceed that → copy to the cache
    data = CACHE / "espeak-ng-data"
    if not data.exists():
        shutil.copytree(Path(piper.__file__).parent / "espeak-ng-data", data)
    return PiperVoice.load(str(onnx), espeak_data_dir=str(data))


def piper_say(voice, text, path, length_scale=1.12):
    from piper import SynthesisConfig
    with wave.open(str(path), "wb") as w:
        voice.synthesize_wav(text, w, syn_config=SynthesisConfig(length_scale=length_scale, noise_scale=0.6, noise_w_scale=0.7))


class Chatterbox:
    def __init__(self, reference):
        import torch
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        self.torch = torch
        self.model = ChatterboxMultilingualTTS.from_pretrained(device=device)
        self.reference = str(reference)

    def say(self, text, path, seed=7):
        import torchaudio
        self.torch.manual_seed(seed)
        # low exaggeration and cfg weight = calm, unhurried delivery for relaxation exercises
        wav = self.model.generate(text, language_id="de", audio_prompt_path=self.reference,
                                  exaggeration=0.35, cfg_weight=0.35, temperature=0.7)
        torchaudio.save(str(path), wav.cpu(), self.model.sr)


def reference_clip(piper):
    ref = CACHE / "reference-de.wav"
    if not ref.exists() or ref.stat().st_size < 10_000:   # also replaces a clip left over from a failed run
        piper_say(piper, REFERENCE_TEXT, ref, length_scale=1.18)
    return ref


# ---------- post-processing ----------

def read_wav(path):
    import soundfile as sf
    x, sr = sf.read(str(path), dtype="float32", always_2d=True)
    return x.mean(axis=1), sr


def polish(x, sr):
    """Trim silence, normalise to a consistent level, short fades, small lead-in."""
    env = np.abs(x)
    thr = max(1e-4, env.max() * 0.02)
    idx = np.where(env > thr)[0]
    if len(idx):
        a = max(0, idx[0] - int(0.03 * sr))
        b = min(len(x), idx[-1] + int(0.12 * sr))
        x = x[a:b]
    rms = np.sqrt(np.mean(x ** 2) + 1e-12)
    x = x * min(0.1 / rms, 0.89 / (np.abs(x).max() + 1e-9))   # ≈ −20 dBFS RMS, peak ≤ −1 dBFS
    f = int(0.01 * sr)
    x[:f] *= np.linspace(0, 1, f)
    x[-f * 4:] *= np.linspace(1, 0, f * 4)
    return np.concatenate([np.zeros(int(0.05 * sr), dtype=np.float32), x.astype(np.float32)])


def encode(x, sr, dest):
    import soundfile as sf
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d) / "x.wav"
        sf.write(str(tmp), x, sr, subtype="PCM_16")
        # AAC-LC mono 64 kbit/s via macOS afconvert
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", "-c", "1", str(tmp), str(dest)], check=True)


def duration(path):
    out = subprocess.run(["afinfo", str(path)], capture_output=True, text=True).stdout
    return next((float(l.split()[2]) for l in out.splitlines() if "estimated duration" in l), 0.0)


def bounds(text):
    n = len(text)
    return 0.25 + n / 22, 1.2 + n / 7      # calm German speech ≈ 10–16 characters per second


def suspicious(items):
    """Clips far outside the length expected from the text (hallucinated tails, swallowed words)."""
    bad = []
    for it in items:
        f = OUT / f"{it['key']}.m4a"
        if not f.exists():
            continue
        n = len(it["spoken"])
        lo, hi = bounds(it["spoken"])
        d = duration(f)
        if not lo <= d <= hi:
            bad.append((it["key"], it["spoken"], d, lo, hi))
    return bad


# ---------- main ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", choices=["chatterbox", "piper"], default="chatterbox")
    ap.add_argument("--reference", help="German reference clip (wav, 5–15 s) for Chatterbox")
    ap.add_argument("--force", action="store_true", help="re-record existing files")
    ap.add_argument("--only", nargs="*", help="keys to (re-)record")
    ap.add_argument("--samples", help="write comparison samples into this folder and exit")
    ap.add_argument("--seed", type=int, default=7, help="Chatterbox seed (change it to re-roll a bad take)")
    ap.add_argument("--check", action="store_true", help="only list recordings whose length looks implausible")
    args = ap.parse_args()

    items = prompts()
    if args.check:
        bad = suspicious(items)
        for k, t, d, lo, hi in bad:
            print(f"{k}  {d:5.1f}s (expected {lo:.1f}–{hi:.1f}s)  {t}")
        print(f"{len(bad)} suspicious of {len(items)}" + (f" → re-record: --force --seed 11 --only {' '.join(b[0] for b in bad)}" if bad else ""))
        return
    piper = piper_voice()

    if args.samples:
        d = Path(args.samples); d.mkdir(parents=True, exist_ok=True)
        texts = ["Setz dich bequem hin. Atme ganz normal, ohne etwas zu verändern.",
                 "Ohr sanft Richtung Schulter, links", "Einatmen durch die Nase"]
        cb = Chatterbox(Path(args.reference) if args.reference else reference_clip(piper))
        for i, t in enumerate(texts):
            for name, fn in [("piper", lambda p: piper_say(piper, t, p)), ("chatterbox", lambda p: cb.say(t, p))]:
                raw = d / f"_{name}-{i}.wav"; fn(raw)
                x, sr = read_wav(raw); encode(polish(x, sr), sr, d / f"{i + 1}-{name}.m4a"); raw.unlink()
        print(f"samples in {d}")
        return

    OUT.mkdir(parents=True, exist_ok=True)
    keys = {it["key"] for it in items}
    for stale in OUT.glob("*.m4a"):          # content changed → drop recordings nobody uses anymore
        if stale.stem not in keys:
            stale.unlink(); print(f"removed stale {stale.name}")

    todo = [it for it in items if (args.force or not (OUT / f"{it['key']}.m4a").exists())
            and (not args.only or it["key"] in args.only)]
    engine = None
    if todo and args.engine == "chatterbox":
        engine = Chatterbox(Path(args.reference) if args.reference else reference_clip(piper))
    with tempfile.TemporaryDirectory() as d:
        for n, it in enumerate(todo, 1):
            raw = Path(d) / f"{it['key']}.wav"
            lo, hi = bounds(it["spoken"])
            for attempt in range(8):            # re-roll takes whose length is implausible (mumbled tails)
                if engine: engine.say(it["spoken"], raw, seed=args.seed + attempt * 101)
                else: piper_say(piper, it["spoken"], raw)
                x, sr = read_wav(raw)
                y = polish(x, sr)
                if not engine or lo <= len(y) / sr <= hi:
                    break
                print(f"    retake {attempt + 1}: {len(y) / sr:.1f}s outside {lo:.1f}–{hi:.1f}s", flush=True)
            encode(y, sr, OUT / f"{it['key']}.m4a")
            print(f"[{n}/{len(todo)}] {it['key']}  {len(y) / sr:4.1f}s  {it['spoken'][:60]}", flush=True)

    manifest = {"engine": args.engine, "piperVoice": PIPER_VOICE,
                "prompts": {it["key"]: it["text"] for it in items}}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    total = sum(f.stat().st_size for f in OUT.glob("*.m4a"))
    print(f"{len(items)} prompts, {len(todo)} recorded, {total / 1e6:.1f} MB in {OUT.relative_to(ROOT.parent)}")


if __name__ == "__main__":
    main()
