# Lantern Spirit

A glowing companion character that lives in the header of an ordinary
park-app screen, rendered with Flutter Scene. Everything under the header is
plain Flutter UI, and the character reacts to it.

Lumi is five spheres and a face drawn on a thin shell in front of the head,
with procedural materials and one animation clip per state. Interactive
motion is layered on at runtime.

## What to try

- **Tap the header** to wake Lumi from sleep.
- **Poke, press, and pull the head.** It is a soft body: a quick tap
  jiggles it, a press squashes it under your finger, and a drag away from the
  head pulls it like taffy before it snaps back.
- **Drag in the header** (or hover with a mouse) and Lumi looks at you. When
  you are still, it looks around at whatever is moving or new: the coin, the
  list, a firework.
- **Scroll the list.** Lumi's glow spills onto the cards under it, and the
  character bobs with the scroll speed. Fling hard and Lumi gets dizzy.
- **Collect** the reward card. A coin flies from the card into the scene and
  Lumi catches it and celebrates.
- **Watch with Lumi** on the Tonight card dives into the fireworks show over
  the lagoon: a one-minute show scored to a beat, with Lumi reacting to every
  break from the end of the pier. Lumi's light, the water, and the town all
  pick up the colors of each burst.
- **The hanger button** opens the wardrobe: hats, a scarf, color themes, a
  hue slider, and glow. Choices are saved. Some hats unlock with keys, and
  the party hat unlocks after watching the show.
- **Friends** (the smiley button, or the Friends tab in the wardrobe): choose
  who lives in the app. Lumi the Lantern Spirit, Juju the Gummy Toy, Mochi the
  Soft Pebble, or Nova the Orbit Guide. The current friend pops out and the
  new one springs into the header; hats, colors, the show, and the games
  all follow. Every friend runs on Lumi's rig and clips, so one animation
  set drives the whole family.
- **Send Lumi** (on the reward card): your friend hops out of the header
  into a full-screen 3D layer over the app, dives behind the reward card,
  peeks over its edge, hops on top, presses Collect itself, and carries the
  key home. The list can scroll mid-errand; it stays with the card.
- **The room** (the little house in the header): the header grows into a
  full-screen room around your friend, who never moves. Tap a hat on the
  shelf to wear it, the cushion for a nap, and the board, which is a live
  Flutter widget inside the 3D room, to throw a party.
- **The park map**: a 3D diorama of the park on a mirror lagoon with live
  Flutter cards over every ride (wait times tick, buttons press). Your
  friend suggests the shortest wait and hops along the paths to whatever
  you pick.
- **Idle with a mouse over the app**, your friend follows it with its head
  and eyes. Hats ride every squish and stretch of the soft head.
- **Play with your friend**:
  - **Star Catch**: slide along a mirror-still lake and catch falling stars.
    Each catch flies up into a constellation; finish one (The Lantern, The
    Coaster, The Castle) and a meteor shower pays double. Storm clouds throw
    lightning.
  - **Sky Lift**: hold to glow and float up, slide to steer, let go to drift
    and recharge. Bounce off clouds, grab sky lanterns, dodge storm clouds,
    burst through the cloud sea into the night and the aurora, and reach the
    moon.
  Both pay stars into the profile.
- **The tune button** opens the creative panel: jump to any state with the
  real crossfade, watch the clip weights blend, turn on the mood blend and
  drag the emotion pad between grumpy, happy, glum, and content, tune fade,
  glow, softness, and squash, and explode the parts.

## Living in the app

- **Dark mode**: a quiet navy-black shell so your friend's glow is the
  brightest thing on screen; the glow pools over the cards as it moves.
- **Shy**: rest the mouse on its face and it covers it with both hands,
  peeking out now and then.
- **Sneeze**: a butterfly lands on its head, it goes cross-eyed and sneezes,
  and the hat flies off, spins, and lands back on crooked.
- **Tricks** (the sparkle button): Lumi blows a glowing bubble lantern, Juju
  splits into two mini Jujus and back, Mochi's sprout blooms, Nova projects a
  hologram of the shortest waits.
- **Idle surprises**: a butterfly, a spark it chases and misses, a peek from
  behind a card in the list, and after a long while a little glow snowman.
- **Reacting to the app**: pull the list down and your friend stretches after
  it (let go to refresh the wait times); drag through the list and it rides
  the scrollbar, dizzy at the bottom; notifications get caught in both hands,
  read, and thrown onto the card they are about, which lights up and changes
  (a new key, rain on the way, a shorter wait); news about treats gets
  eaten instead: three big bites cut out of a real 3D slab, crumbs flying,
  the rest gulped, and a belly rub; search and it throws a sparkle at the match; the weather card
  brings out an umbrella or sunglasses; resize the window and it tumbles;
  the header and the room's window follow the time of day.
- **Talk to the friend**: tap the mic in the header and ask out loud ("what
  has the shortest line?", "when are the fireworks?", "take me to Moon
  Drop"). It cups an ear while it listens, thinks, then answers in its own
  chirpy voice while the words type out in a speech bubble, and shows you:
  lights up the row, points out the card, walks you there on the map, or
  opens what you asked for. Answers come from Gemini when a key is set (see
  Running), from a built-in matcher otherwise; with no speech recognition
  the bubble becomes a text field.
- **Petting**: press near the top of the friend's head and stroke back and
  forth. It leans into your hand, the head dents right where the hand is,
  and hearts float up; keep going and it melts into a drowsy, swaying trance
  that lingers after you stop, until it blinks back with a happy sigh.
- **Full-screen moments**, where the friend affects everything on screen
  (each one also in the creative panel's Moments):
  - *Lantern pulse*: a ring of light rolls out from the friend, a heat haze
    bends the screen as it passes, and every card's outline lights up with
    glints running round it (after a key, a snack, or a refresh).
  - *Sneeze ripple*: every sneeze sends water ripples across the whole app,
    through a fragment shader over everything.
  - *Pratfall*: the friend trips out of the header and lands face-first on
    a card; the shockwave shakes every card, row, and the header on its own
    spring, later and gentler with distance.
  - *Lights out*: the app goes dark and the friend is the only light; cards
    cast soft shadows away from it and catch a warm rim (tap to end).
  - *Card Jenga*: the friend yanks a card out of the list and the rest
    tumble into a pile with real rigid-body physics, then fly home.
  - *Peel into 3D*: the whole app tilts back into thick slabs on a floor,
    the friend hops across them, and it folds flat again, pixel for pixel.
- **Photo booth**: four backdrops (fireworks, the moon, the aurora, the room),
  poses and hats, a countdown and flash, and a polaroid card to save.
- **The room and the map** were rebuilt after concept art: a floating wooden
  nook under string lights with a lamp that pools warm light, and a
  handmade island park with cobbled paths, lamp posts, a fountain plaza, and
  a bespoke model for every ride, lit like a storybook model at dusk
  (a two-tone key light, bright rims, a color grade, and shadows baked under
  every tree, ride, and lamp post); stones laid along each path and in rings
  round the plaza, trees that never repeat, and a lagoon of lily pads,
  islets, and floating paper lanterns.

## Clips to record

The creative panel's **Clips to record** section plays eight short scripted
performances made for social video, each with an on-screen finger so a
recording shows exactly what was touched. Turn on **Show touches** to draw
your own touches too.

| Clip | What happens |
| --- | --- |
| Fetch run | Out of the header, behind the reward card, a peek, Collect, and home with the key |
| Taffy pull | The head stretched like taffy and let go with a snap, then a cheek pulled sideways |
| Room reveal | The header grows into the room; two hats from the shelf, then a party from the board |
| Friend swap | The Friends sheet open while all four friends pop in and out of the header |
| Climb to the moon | Sky Lift on autopilot through every zone to the fireworks at the moon |
| Constellation | Star Catch on autopilot: constellations drawing in, meteor showers, golden stars |
| Fireworks dive | The Tonight card grows into the lagoon just before the first break |
| Map hop | Rides tapped on the 3D map; the friend hops over and the card flips |
| Shy | A pointer rests on the face and the hands come up |
| Sneeze | A butterfly lands, a sneeze, the hat in the air |
| Pull to refresh | The list pulled down with the friend stretching after it |
| Tricks | Every friend's signature trick in a row |
| Photo booth | Moon, Cheer, Fireworks, and the shot, into a polaroid |

Every interaction has its own sound: soft, toy-like, and all in one
pentatonic key so overlapping sounds harmonize. They are synthesized from
code by `tool/make_ui_sounds.py` (the show's by `tool/make_sounds.py`); see
`assets/sfx/README.md` for the full list. The creative panel's **Sound**
switch mutes them for recording. Haptics fire on devices that have them.

## Running

Needs Flutter 3.47 (stable) or newer. It runs on iOS, Android, macOS, and the
web.

```sh
flutter run -d macos
```

Other platforms work the same way (`-d <device>`). The macOS window opens
phone-sized. Flutter GPU is turned on in the iOS and macOS `Info.plist`
(`FLTEnableFlutterGPU`) and the Android manifest, so no flag is needed. On the
web, Flutter Scene renders through its own WebGL2 backend.

The demo depends on a Flutter Scene commit from `master` until 0.24.4 is on
pub.dev, since it uses `BloomSettings.referenceSize` to keep the glow the same
in the header and in the full-screen layer the friend moves into.

To let Gemini answer when you talk to the friend, pass a key (and optionally
a model; the default is `gemini-2.5-flash`):

```sh
flutter run -d macos --dart-define=GEMINI_API_KEY=your-key
```

Without a key, or whenever Gemini fails or takes longer than six seconds, a
built-in matcher answers the common questions, so a demo never stalls.

## How it is put together

| Piece | File |
| --- | --- |
| Rig and state clips (GLB) | `assets/lantern.glb`, written by `tool/make_lantern_glb.py` |
| Expression sheet | `assets/face_atlas.png`, written by `tool/make_face_atlas.py` |
| Skin, face, and embers | `assets/skin.fmat`, `assets/face.fmat`, `assets/ember.fmat` |
| Moods, crossfades, look-at, springs, mood pad, wardrobe sockets | `lib/lantern/character.dart` |
| Soft body (CPU, 12 control points, volume preserving) | `lib/lantern/soft_body.dart` |
| Where Lumi looks | `lib/lantern/attention.dart` |
| Accessories | `assets/accessories/*.glb`, from `tool/accessories/` |
| Friends: shapes, palettes, extras on Lumi's rig | `lib/lantern/friends.dart` |
| Friends' material (candy, felt, pearl, glass) | `assets/toy.fmat` |
| Friends' expression sheets | `assets/faces/*.png`, from `tool/make_friend_faces.py` |
| Fireworks (closed form from show time, so scrubbing is free) | `lib/show/fireworks.dart` |
| Lagoon set, show script, director, screen | `lib/show/` |
| Mini-games and their host (popups, banners, flashes, hitstop) | `lib/games/` |
| Tricks, surprises, reactions to the app, time of day | `lib/ui/park_life.dart` |
| Scenery material (planks, cobbles, grass, rug, plaster, stripes, rock) | `assets/scenery.fmat`, `lib/scenery/scenery.dart` |
| The map diorama | `lib/map/park_diorama.dart` |
| The photo booth | `lib/booth/photo_booth_screen.dart` |
| Concept art prompts | `tool/concepts/gen_concepts.py` |
| Game effects: sparks, flares, shockwaves, puffs, trails, lightning | `lib/vfx/vfx.dart`, `assets/vfx.fmat` |
| The fetch errand (leaving the header) | `lib/ui/errand.dart`, `lib/ui/park_screen.dart` |
| The room | `lib/room/room.dart` |
| The park map | `lib/map/park_map_screen.dart` |
| Saved profile (keys, stars, look, best scores) | `lib/app/profile.dart` |
| The app screen, wardrobe, creative panel, inner light | `lib/ui/` |

Every part of the rig hangs off two nodes. `<Part>Ctrl` is keyed by the clips,
the timeline layer. `<Part>Fx` sits under it and is driven from Dart for the
interactive layer. The two never write the same transform, so a clip and a
look-at or spring compose cleanly.

The clips cover the app states (Awake, Sleepy, Curious, Dizzy, Poked,
Delighted), the show reactions (Watch, Flinch, Cheer, Lean), and the four
corners of the mood pad (Happy, Content, Glum, Grumpy). A state change
crossfades the clip weights, cross-dissolves the face, and eases the glow.

To regenerate the assets after editing the tools:

```sh
python3 tool/make_lantern_glb.py
python3 tool/make_face_atlas.py
```

## Render captures

The integration tests drive the app with scripted input and write PNGs to
`build/captures/`:

| Test | Covers |
| --- | --- |
| `capture_test.dart` | States, poke, press, pull, mood pad, themes, the dive into the show, the panel |
| `show_capture_test.dart` | Each beat of the fireworks show |
| `wardrobe_capture_test.dart` | Every hat and the wardrobe screen |
| `games_capture_test.dart` | Both games, played as different friends, through every zone of Sky Lift |
| `friends_capture_test.dart` | Every friend awake, celebrating, and dressed, plus the swap and the Friends tab |
| `hats_capture_test.dart` | Every friend in a hat, pressed, pulled, and released |
| `header_capture_test.dart` | The fetch errand beat by beat, the room, and the park map |
| `sweep_capture_test.dart` | Another friend through the errand, room, and show, and a bot that plays Sky Lift to the moon |
| `clips_capture_test.dart` | Every scripted clip, frame by frame, for seams and pops |
| `life_capture_test.dart` | Every moment above: shy, sneeze, tricks, surprises, reactions, weather, time of day, the booth |
| `polish_capture_test.dart` | Frame by frame: a notification caught and delivered, the spark chase (prints the hand's largest jump between frames), the status line changing, the peek's climb back over its card, the walk around the carousel |
| `snack_capture_test.dart` | A notification eaten bite by bite, the chase's escape, the snowman appearing, a clean second peek, and the map and a game dissolving back onto their cards |
| `voice_capture_test.dart` | Questions answered in the speech bubble and shown: a row lit up, cards pointed out, the map walked |
| `pet_capture_test.dart` | Petting into a trance and out of it, Juju's split, and the friend facing where it walks on the map (prints the worst and average angle) |
| `spectacle_capture_test.dart` | The full-screen moments: pulse, ripple, pratfall, lights out, card Jenga, and the peel into 3D |
| `card_art_capture_test.dart` | Renders the stills for the fireworks and map cards (crop into `assets/ui/`) |
| `fixes_capture_test.dart` | The wardrobe sheet over the header, and leaving a game mid-round |

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/capture_test.dart \
  -d macos
```
