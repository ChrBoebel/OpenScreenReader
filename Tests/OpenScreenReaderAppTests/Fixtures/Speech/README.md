# Speech fixtures for the room-echo tests

`RoomEchoTests` in `MeetingTests.swift` feeds these recordings of real German
read speech through a simulated room. They replace speech that was synthesized
with `/usr/bin/say` at test time: the installed voices differ between macOS
images, so the same code measured different values on different machines (the
double-talk coverage was 0.786 locally and 0.529 on CI). Committed recordings make
every run measure the same samples.

The files are bundled only into the `OpenScreenReaderAppTests` test bundle, never
into the app.

## Files

| File | Role in the tests | Duration | Bytes | SHA-256 |
| --- | --- | --- | --- | --- |
| `others-elli.wav` | the others (system audio), female voice, median F0 about 270 Hz | 19.40 s | 310444 | `ef28c083b252d7bb932eab1772753756f330a79826e329eacdd348e0962cfd32` |
| `mine-karlsson-1.wav` | me talking over the echo, male voice, median F0 about 110 Hz | 5.10 s | 81644 | `a43a97048e01398e80e436457c9074e38386ca57c8369117e4909441b3975540` |
| `mine-karlsson-2.wav` | me speaking after the echo, same male voice, another sentence | 4.40 s | 70444 | `e32320c44b715521c856daddb7aee33e614062f50393ffbdd8577662b35cb1cb` |

All three: WAV, 16-bit signed little-endian PCM, mono, 8000 Hz.

## Source

- Work: Jacob und Wilhelm Grimm, *Kinder- und Hausmärchen* (first edition,
  1812/15). The text is in the public domain.
- Recording: LibriVox, *Kinder- und Hausmärchen (1812/15) Teil 1*, catalogued
  2012-06-27. Project page:
  <https://librivox.org/kinder-und-hausmarchen-181215-teil-1-by-jacob-wilhelm-grimm/>.
  Internet Archive item: <https://archive.org/details/kinder_hausmaerchen_1206_librivox>.
- Public-domain statement: LibriVox volunteers dedicate their recordings to the
  public domain; the project page states "LibriVox recordings are Public Domain
  in the USA." The Internet Archive item carries the license URL
  <http://creativecommons.org/publicdomain/zero/1.0/> (CC0 1.0).

| File | Section | Reader | Source file | Range used |
| --- | --- | --- | --- | --- |
| `others-elli.wav` | 02, *Jorinde und Joringel* | Elli | <https://archive.org/download/kinder_hausmaerchen_1206_librivox/kinderundhausmaerchen1_02_jorindejoringel_grimm_64kb.mp3> | 186.95 s to 206.35 s |
| `mine-karlsson-1.wav` | 49, *Der alte Großvater und der Enkel* | Karlsson | <https://archive.org/download/kinder_hausmaerchen_1206_librivox/kinderundhausmaerchen1_49_grossvaterundenkel_grimm_64kb.mp3> | 105.50 s to 110.60 s |
| `mine-karlsson-2.wav` | 49, *Der alte Großvater und der Enkel* | Karlsson | same file as above | 30.90 s to 35.30 s |

Source MP3s as downloaded on 2026-10-25 (64 kbit/s, mono, 22050 Hz):

| Source file | Bytes | SHA-256 | SHA-1 (as listed by the Internet Archive) |
| --- | --- | --- | --- |
| `kinderundhausmaerchen1_02_jorindejoringel_grimm_64kb.mp3` | 2382217 | `4e6eb46c31cf5abb9ce2826a1f6fe90eb886eb150d8b03fb3480b785d3cd7219` | `6e22411a0ece36bb8193dfda4c6192e76119bb1f` |
| `kinderundhausmaerchen1_49_grossvaterundenkel_grimm_64kb.mp3` | 1121038 | `e43eca076b33e2b1e6e7aa9f929b629d06b5ea38c1e67cd41b4fde15f5266de0` | `159fe54ce2ca1e40c7bb02874c2c156d81da03e4` |

## Processing

Every cut starts and ends inside a pause between sentences, within the read
fairy tale (after the spoken LibriVox introduction, before the closing note). `make-fixtures.py` checks the source hashes, then for each
file:

1. `afconvert -f WAVE -d LEI32@8000 -c 1 <source>.mp3 <decoded>.wav`
   (decode, mix to mono, resample to 8 kHz);
2. cuts the listed range (sample `round(start * 8000)` up to `round(end * 8000)`);
3. scales the cut to an RMS of 0.1 (-20 dBFS), between the levels of the former
   `say` voices (0.08 and 0.12); peaks stay between 0.42 and 0.67, so nothing
   clips;
4. writes 16-bit PCM WAV with rounding and no dither.

To rebuild:

```sh
mkdir -p /tmp/librivox && cd /tmp/librivox
curl -LO https://archive.org/download/kinder_hausmaerchen_1206_librivox/kinderundhausmaerchen1_02_jorindejoringel_grimm_64kb.mp3
curl -LO https://archive.org/download/kinder_hausmaerchen_1206_librivox/kinderundhausmaerchen1_49_grossvaterundenkel_grimm_64kb.mp3
python3 <repository>/Tests/OpenScreenReaderAppTests/Fixtures/Speech/make-fixtures.py /tmp/librivox
```

On macOS 26.6.2 (25G83) this reproduces the committed files byte for byte. The
committed files are authoritative; another macOS release may decode the MP3s
slightly differently.

## How the passages were chosen

Real read speech is harder for the echo gate than `say` output, and the result
depends on the passage. Before choosing, every 18-second window (1-second steps)
of seven sections of this project, read by six different readers, was measured as
the others against the final `mine` clips at the final level: 373 of 1264
windows met every threshold of `RoomEchoTests`. Most failures were in the
double-talk test (480 windows passed); the unrelated-speech score stayed below
the floor in 1052 windows and the room grid passed in 1064. The chosen passage
lies in a stretch where the echo tests also pass for neighbouring windows, so it
is not a single lucky cut; some neighbouring windows do exceed the unrelated
floor (up to 0.160). The thresholds themselves were not changed.
