# Sound effects

Every sound in this folder is synthesized from code (oscillators, additive voices, and filtered noise). There are no recordings or third-party samples. All files are 44.1 kHz, 16-bit, mono WAV.

## Regenerating

Run from the package root (`content/lantern_spirit`). Both scripts need Python 3 with numpy; `make_ui_sounds.py` also uses scipy.

```sh
python3 tool/make_sounds.py                 # fireworks show sounds (first table)
python3 tool/make_ui_sounds.py              # everything else
python3 tool/make_ui_sounds.py tap poke     # re-render only some sounds
python3 tool/make_ui_sounds.py --list       # names, lengths, descriptions
python3 tool/make_ui_sounds.py --verify     # check format, peak, length, DC, end clicks, loop seams
```

`make_ui_sounds.py` seeds its random generator per sound name, so output is byte-identical from run to run and re-rendering one sound never changes another. It refuses to write any of the fireworks file names.

## Palette

- Soft, warm, toy-like: music-box bells, kalimba and marimba plucks, felt thumps, rubbery boings, airy whooshes, gentle sparkles.
- Pitched material sits in C major pentatonic (C D E G A), so sounds that overlap harmonize.
- Character voices are wordless coos: additive harmonics shaped by vowel formants, with pitch glides.
- A small shared room reverb glues everything into one space.
- Peaks: about -3 to -6 dBFS for most sounds, -8 to -12 dBFS for small UI ticks, -6 to -10 dBFS for loops. Every file starts and ends at zero, except the loops, which are crossfaded end-to-start so they repeat seamlessly.

## Fireworks show (tool/make_sounds.py)

| File | Length | Description |
| --- | --- | --- |
| `coin.wav` | 0.9 s | Two-note coin chime (B5, E6). |
| `crackle.wav` | 1.8 s | Sparse firework crackle thinning out. |
| `pop.wav` | 0.22 s | Soft rounded boop for pokes and UI. |
| `sparkle.wav` | 1.0 s | Three-note glittering chime (E6, A6, E7). |
| `squish.wav` | 0.45 s | Low wobble for the soft body. |
| `burst_big_1.wav` to `burst_big_3.wav` | 3.3 to 3.6 s | A big shell bursting across the lagoon: a muffled crack and low thump, slapback echoes off the far shore, a rolling rumble, sometimes faint crackle. |
| `burst_small_1.wav`, `burst_small_2.wav` | 1.8 to 2.1 s | A smaller shell bursting, shorter tail. |
| `mortar.wav` | 0.5 s | A launch heard from far off: a soft hollow thump, played on its own at launch time (main shells only). |

## App sounds (tool/make_ui_sounds.py)

### UI

| File | Length | Description |
| --- | --- | --- |
| `tap.wav` | 0.08 s | A tiny round blip on C6. |
| `toggle.wav` | 0.15 s | Two-note soft marimba blip (G5 then C6). |
| `open.wav` | 0.4 s | A soft rising bloop that blooms into two quiet bells (E6, G6). |
| `close.wav` | 0.35 s | A soft falling bloop settling on two wooden notes (E5, C5). |
| `card_flip.wav` | 0.2 s | Two quick soft wooden ticks. |
| `dissolve.wav` | 0.6 s | A gentle shimmering pentatonic swell for a cross-dissolve. |

### Character

| File | Length | Description |
| --- | --- | --- |
| `poke.wav` | 0.3 s | Rubbery boing with a little squeak. |
| `stretch.wav` | 0.6 s | Rubbery taffy stretch creak, pitch rising. |
| `snap_back.wav` | 0.5 s | Wobbly 'boing-oing' sproing as the head springs back. |
| `hop.wav` | 0.15 s | Small soft upward jump blip. |
| `land.wav` | 0.25 s | Soft felt thump with a tiny bell jingle. |
| `chirp_happy.wav` | 0.35 s | Happy wordless coo, bouncing upward. |
| `chirp_curious.wav` | 0.4 s | Curious 'hmm?' coo rising at the end. |
| `chirp_sad.wav` | 0.5 s | Sad little descending coo with a wobble. |
| `giggle.wav` | 0.5 s | Three quick rising 'hee' coos. |
| `yawn.wav` | 0.9 s | Slow sleepy descending coo, breathy. |
| `snore.wav` | 1.6 s | One soft breathy snore cycle (seamless loop). |
| `soft_sweep.wav` | 1.2 s | A quiet, soft sweep of air with a faint warm chord, for the app tilting into 3D and folding back. |
| `pet_stroke.wav` | 0.28 s | A very soft low glide, a hand stroking the head. |
| `heart.wav` | 0.35 s | A tiny bright ping as a heart floats up. |
| `sneeze_in.wav` | 0.9 s | Two rising breathy inhales: 'ah... ah...'. |
| `sneeze_out.wav` | 0.35 s | Cute 'choo!' burst with a pop. |
| `hat_pop.wav` | 0.2 s | A round, cork-like pop as the hat flies off. |
| `hat_land.wav` | 0.2 s | Soft cloth plop. |
| `dizzy.wav` | 0.9 s | Wobbly cartoon spin warble with circling star bells. |
| `tumble.wav` | 0.7 s | A round warbling roll, 'whup-whup-whup', all tone. |
| `shy.wav` | 0.25 s | Tiny embarrassed 'eep' squeak. |
| `wake.wav` | 0.4 s | Bright little two-bell wake chime (E6, A6). |
| `swap.wav` | 0.6 s | A round magical 'bwoop' rising into a chime, for switching friends. |

### Life moments

| File | Length | Description |
| --- | --- | --- |
| `notify.wav` | 0.5 s | Soft notification ding (E6 over C6). |
| `catch.wav` | 0.2 s | A quick soft pluck as something lands in hand. |
| `throw.wav` | 0.3 s | A smooth falling glide, a toss. |
| `deliver.wav` | 0.6 s | Warm chime landing on a card (C major pluck chord). |
| `bite_1.wav` | 0.2 s | Crunchy chomp of a crisp wafer (variant 1). |
| `bite_2.wav` | 0.2 s | Crunchy chomp of a crisp wafer (variant 2). |
| `bite_3.wav` | 0.2 s | Crunchy chomp of a crisp wafer (variant 3). |
| `gulp.wav` | 0.3 s | Cartoon 'gl-ulp' gulp. |
| `belly_rub.wav` | 1.2 s | Content humming coo over soft rhythmic pats. |
| `burp.wav` | 0.35 s | Tiny polite cute burp. |
| `butterfly.wav` | 0.8 s | A faint, high, fluttering shimmer of wings. |
| `spark_zip.wav` | 0.35 s | A spark zipping past: a quick bright rising glide. |
| `spark_escape.wav` | 0.4 s | The spark getting away: a quick descending zip. |
| `snow_build.wav` | 0.3 s | Soft snow packing crunch. |
| `snow_melt.wav` | 1 s | Gentle descending drips, melting away. |
| `refresh_pull.wav` | 0.4 s | Elastic creak while pulling to refresh. |
| `refresh.wav` | 0.5 s | Release boing plus a small chime. |
| `scroll_ride.wav` | 0.8 s | 'Wheee' swoop. |
| `rain_loop.wav` | 4 s | Soft rain bed with patters and plips (seamless loop). |
| `umbrella.wav` | 0.3 s | A soft round 'fwump' as the umbrella opens. |
| `shades.wav` | 0.4 s | Sunglasses clink plus a cool little shimmer. |
| `search_found.wav` | 0.6 s | Sparkle arpeggio landing on a C7 bell. |
| `trick_bubble.wav` | 0.6 s | Bubble blow and wobble ending in a soft blub. |
| `trick_split.wav` | 0.6 s | Splitting into minis: three rising pops. |
| `trick_bloom.wav` | 0.7 s | A flower blooming: a soft rising glide opening into a chime. |
| `trick_holo.wav` | 0.7 s | Soft sci-fi hologram flicker-in settling on a chord. |

### Errand, room, map, booth

| File | Length | Description |
| --- | --- | --- |
| `press.wav` | 0.15 s | Big soft button press click (down and release). |
| `key_get.wav` | 0.8 s | Magical key get: rising bell arpeggio and a key jingle. |
| `room_open.wav` | 0.6 s | Two warm wooden notes and a soft glow of chord, into the cozy room. |
| `hat_equip.wav` | 0.35 s | A soft low plop as the hat goes on, and a twinkle. |
| `lamp.wav` | 0.1 s | Small lamp switch click. |
| `party.wav` | 0.9 s | Party popper pop with a confetti tinkle. |
| `map_step.wav` | 0.12 s | Tiny footstep hop on cobbles. |
| `arrive.wav` | 0.7 s | Arrival chime: rolled G5 C6 E6 G6 bells. |
| `countdown.wav` | 0.15 s | One soft countdown beep (C6). |
| `countdown_go.wav` | 0.25 s | Higher 'go' beep (G6 over G5). |
| `shutter.wav` | 0.45 s | Camera shutter double click with a soft rising flash whine. |

### Games

| File | Length | Description |
| --- | --- | --- |
| `star_catch.wav` | 0.35 s | Bright clean C6 twinkle (the game pitches it up per combo). |
| `star_miss.wav` | 0.3 s | Soft low plunk (C4). |
| `combo.wav` | 0.5 s | Rising C6 E6 G6 arpeggio. |
| `banner.wav` | 1 s | Level banner swell: warm chord, a rising glide, sparkle. |
| `thrust_loop.wav` | 2 s | Warm airy jet burner (seamless loop). |
| `zap.wav` | 0.4 s | Soft electric zap from a storm cloud. |
| `boing.wav` | 0.45 s | Big bouncy cloud boing (jaw-harp style 'boyoyoing'). |
| `glow_pickup.wav` | 0.4 s | Warm lantern pickup: G5 to C6 pluck with a glow swell. |
| `moon_fanfare.wav` | 2 s | Short magical fanfare on reaching the moon. |
| `results.wav` | 1.2 s | Gentle results jingle resolving to a C major chord. |
| `game_start.wav` | 0.5 s | '3-2-1 go' start sting: three ticks into a bright chord. |

Loops: `snore`, `rain_loop`, and `thrust_loop` are built with an equal-power crossfade of their tail into their head; play them with looping enabled.

`star_catch` is a clean harmonic C6 bell so the game can pitch it up per combo step by changing playback rate.

## Checking for noise

`python3 tool/audit_sounds.py assets/sfx` scores every sound with an FFT:
how far its noise floor sits below its loudest tone between 1 and 10 kHz,
how much of it is noise rather than tone, its spectral flatness, and its
share of hiss above 4 kHz. Interaction sounds should all come out clean;
only the ones meant to have texture (rain, the bite crunches, snoring,
sneezes, the burner, snow) and the fireworks should be flagged. The
generator gates any faint bed of noise out of every other sound.
