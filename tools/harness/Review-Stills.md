# Reviewing rig stills (WP-H-10)

A rig run that took stills has `<run>\stills\<seq>-<case>-<label>.png` and `<run>\shots.json` (one row per still: case, label, file, size, mean brightness, capture route, error). This file is the prompt for a vision-capable agent that judges one still against one issue.

Owner decision OD-02 applies: a still may close an issue only on **presence or absence** of something (a model is shown or not, a widget is there or not, an icon is missing). Colour, light, animation feel, "looks right" and anything subtle stay on the human list, whatever the still shows.

## The prompt

Give the agent the PNG and the issue's expected sentence, then this text:

```text
You are checking one still from an automated Vermintide 2 test run against one expected sentence.

Expected: <the issue's expected sentence, for example "the hero holds the staff in the right hand">
Still: <run>/stills/<file>.png (1280x720, taken from the game window; the HUD may be visible)
Context: case <case id>, label "<label>", from shots.json.

Answer on the first line with exactly one word: PASS, FAIL or CANNOT-TELL.
Then give one sentence of reason that names what you see in the image.

Rules:
- PASS only when the still clearly shows what the sentence expects.
- FAIL only when the still clearly shows the opposite: the thing is absent, or something else is in its place.
- CANNOT-TELL when the image is black, blurred, cropped, covered by a menu or loading screen, too small to see,
  or when the sentence is about colour, light, motion or quality rather than presence or absence.
- Do not guess from game knowledge; judge only what is in this image.
```

## Using the answer

- PASS or FAIL counts for the issue only if the sentence is a presence or absence check (OD-02); otherwise treat it as CANNOT-TELL.
- CANNOT-TELL puts the check on the human list with the still attached.
- A still whose `shots.json` row is not `ok`, is not 1280x720, or has a mean brightness under 8 is not reviewed: fix the capture first (`tools/harness/README.md`, "Stills").
- Record the answer next to the still's run folder and case in the issue's evidence, never as a new case verdict: the case's own verdict comes from its assertions in the game.
