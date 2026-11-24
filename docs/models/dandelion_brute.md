# Dandelion Brute — model build spec

Boss of area 1 (Starter Meadow). Built from parts in `Models.luau` (`BOSS_BUILDERS[1]`).
All sizes are in units of `S` = the boss's `size` in `Config.Areas` (7 studs), so the model
scales with it. The model stands on y = 0 and faces −Z, like every boss.

## Idea

A grumpy, pot-bellied weed: a round leafy body, a huge dandelion flower for a head with an
angry face in its centre, serrated dandelion leaves for a collar and shoulder guards, root
feet, and a dandelion clock (seed puff) carried like a club that sheds glowing seeds.

## Proportions (height ≈ 1.95 S)

| Part | From – to (y, in S) |
|---|---|
| root feet and toes | 0 – 0.12 |
| stem legs | 0.1 – 0.3 |
| leafy body (ball) | 0.21 – 1.03 |
| leaf collar | 0.98 – 1.25 |
| neck stem | 1.0 – 1.12 |
| flower head (disc + petals) | 1.0 – 1.95 |
| seed-puff club (right hand) | 0.45 – 1.5 |

## Exact counts

| Feature | Count |
|---|---|
| outer petals | 16 |
| inner petals | 12 |
| collar leaves | 8 |
| teeth on each leaf | 3 pairs + 1 tip |
| toes per foot | 3 |
| seed spikes on the puff | 14 |
| teeth in the mouth | 4 |
| claw leaves on the left hand | 3 |

## Colours

| Part | Hex |
|---|---|
| stem green (body, legs, neck) | #46A03C |
| dark leaf | #2E7830 |
| leaf rib | #64B450 |
| belly | #82C85A |
| outer petals | #FFE046 |
| inner petals | #FFF078 |
| flower centre | #FFBE28 |
| centre seeds (dots) | #E69620 |
| roots | #78543A |
| seed puff | #F8F8F2 |
| eyes (pupils) | #FF3C28 |
| brows, mouth | #3C1E14 |

## What glows

- the pupils (red light)
- the seed tips and the puff, which drifts white seed particles

## Moving parts

None of its own: the fight code moves the whole model (walking, turning, attacks).

## Preview

Ray-traced from a Python copy of the builder (not a Studio screenshot): front, three-quarter and side.

![Dandelion Brute preview](dandelion_brute.png)
