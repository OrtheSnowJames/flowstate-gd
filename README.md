# Flowstate

After going to the pool, have you ever wanted to do your crazy water fights online?
Well now you can! Introducing Flowstate! (I hastily made this name up)

Download here: [goto](https://github.com/OrtheSnowJames/orthesnowjames.github.io/releases/tag/flowstate-latest)

An example of King of the Cube:
![strategy?](product_images/king_of_the_cube.png)

## Movement

Getting around the pool isn't just holding W. 

1. Walking - On dry land or in the shallow end, forward/back gets you moving up to a capped walking speed. Let go and it fades right back out.
2. Swimming - Hold the swim key and forward/back to actually get going. There's a short wind-up before you hit full speed, and backstrokes wind up faster than forward strokes.
3. Gliding - Let go of the swim key without stopping and you'll coast on your last heading, bleeding momentum the whole way, until you run dry or hit a movement key.
4. Turning - A/D turn you (and the camera with you) instead of strafing. There's an option to make holding a turn key ramp up instead of turning at full speed right away.
5. Backstroke flip - Tap forward right after letting go of back and you'll spin 180° on the spot without losing momentum, instead of coasting to a stop first.
6. Dodge - Double-tap A or D to dodge sideways. Only works in the shallow end or on dry land, since there's nothing to push off of in open water. Costs stamina and has its own cooldown.
7. Jump - Same shallow-end-or-dry-land rule as the dodge. A jump spends your ENTIRE momentum bar on the way up - the more you had, the higher you go, but you land with none of it left.
8. Scoreboard - Press F to pan the camera to the scoreboard. The scoreboard measures how many times your team has drowned an enemy. First to the goal wins!

## Combat

There are a few combat features we made. First, there are 2 roles.
1. Normal - Just a normal dude.
2. Lifeguard - Chosen randomly. Expends less stamina, goes faster, and can revive drowned teammates.

Next, we need to cover stamina. You can't just swim forever!
You only have 100 points of stamina.
1. When you get hit, you lose a TON of stamina.
2. When you use an attack, you lose a little bit of stamina.
3. When you swim or tread, you lose stamina.
4. Standing in the shallow end is the only way to recover stamina.

If you lose all your stamina, you drown/faint. Here's what that actually means.
1. You go limp and just drift with the water - no more input until someone brings you back.
2. Your screen fades to black and your ears start ringing. It's unsettling on purpose.
3. Any lifeguard on your team can swim up next to you and revive you, handing back half your stamina and snapping your screen right back open.
4. If the lifeguard drowns, the whole team can't revive anymore - not even to save the lifeguard themself.
5. If your whole team drowns, the round's over and the other team wins. Everyone gets revived automatically so nobody's left staring at black, then it's back to the lobby for a rematch.

Don't worry! That's why we made the lifeguard an absolute unit.
1. The lifeguard can block most of an attack's damage, since it's holding a kickboard.
2. The lifeguard can hit for 80 points of stamina damage if performed correctly.
3. The lifeguard expends virtually no stamina swimming or treading.

Now let's talk Momentum. It decides how hard your attacks hit and how high you can jump.
1. The more momentum you have, the higher you can jump.
2. You build momentum by swimming, and backstrokes build it 2x as fast as swimming forward.
3. Attack while swimming and you'll dump your entire momentum bar into the hit. This can more than double your attack power.

What you've all been waiting for, finally, the moves.
Press the key with the number to fire it.
1. Water Power - Launches a long range wave that hits harder the farther away the enemy is.
2. Water Attack - Shoots a burst of short range water that hits harder the closer the enemy is.
3. Water Wall - Halves incoming damage while it's up.
4. Water Counter - Water Walls and Water Powers, but takes 50 stamina.
5. Water Pelt - Shoots some bubbles of water that do little damage unless the opponent is on a cube.

Controller tables use button positions so they work across different gamepads. **Select** means Xbox View, PlayStation Share/Create, or Nintendo `−`. **Start** means Xbox Menu, PlayStation Options, or Nintendo `+`.

# Normal

In **Normal**, work with your team to drain your opponents' stamina while keeping your own team afloat. Protect your lifeguard, pick your fights, and send the whole enemy team under to win the round.

## How to Play

- **Knock out the other team.** Water attacks drain stamina, and running out means you faint.
- **Protect your lifeguard.** They can revive teammates, so losing them makes every other knockout much harder to recover from.
- **Build momentum before attacking** to make your hits stronger. Backstrokes build it faster.
- **Retreat when you need a break.** Recover stamina in the shallow end or on dry land before going back into the fight.

## A Few Things to Know

- You have 100 stamina. Swimming, treading, dodging, and attacking all spend it.
- One player on each team is randomly chosen as the lifeguard. They swim more efficiently and carry a kickboard that helps block damage.
- A lifeguard can revive a nearby fainted teammate with half their stamina.
- If your whole team faints, the round ends. Everyone gets revived before returning to the lobby.

## Controls

| Keyboard / Mouse | Controller | Action |
|---|---|---|
| `W` / `S` | Left stick | Move |
| `A` / `D` | Right stick | Turn / look |
| `Shift` + `W` / `S` | Hold left stick click while moving the stick | Swim |
| Double-tap `A` / `D` | Double-tap D-pad left / right | Dodge in the shallow end or on land |
| `Space` | Bottom face button | Jump |
| `1` | Right face button | Water Power |
| `2` | Left face button | Water Attack |
| `3` | Top face button | Water Wall |
| `4` | Not bound | Water Counter |
| `5` | Right trigger | Water Pelt |
| `R` | D-pad right | Revive a nearby teammate as a lifeguard |
| `F` | D-pad up | Look at the scoreboard |
| `C` | Select | Toggle voice chat |
| `Escape` | Start | Leave solo play or open the online disconnect menu |

# King of the Cube

King of the Hill with a movable cube in the pool.

In **King of the Cube**, fight for a place on top of the push cube and keep the other team off it. Your team earns one point per second while holding it uncontested. First to 100 points wins.

## How to Play

- **Get someone on the cube** to start scoring. A lifeguard is a good choice if your team can protect them.
- **Defend from the water below.** Surround your teammate with players using Water Walls, Water Attacks, and Water Powers.
- **Use Water Pelts against opponents on the cube.** They take extra stamina damage up there.
- **Move the cube into a corner** to make it easier to defend, or bring it toward your team's side so returning enemies have farther to travel.
- **Contest the cube** by getting on it alongside an enemy. Neither team scores until only one team remains on top.

## A Few Things to Know

- The cube turns gold when empty, red or blue when one team holds it, and purple when contested.
- Having more teammates on the cube helps defend it, but you still earn one point per second.
- Players automatically respawn on their team's side after five seconds.
- Knockouts help clear the cube. Holding the cube is what earns points.

## Controls

| Keyboard / Mouse | Controller | Action |
|---|---|---|
| `W` / `S` | Left stick | Move |
| `A` / `D` | Right stick | Turn / look |
| `Shift` + `W` / `S` | Hold left stick click while moving the stick | Swim |
| `Space` | Bottom face button | Jump onto the cube |
| `1` | Right face button | Water Power |
| `2` | Left face button | Water Attack |
| `3` | Top face button | Water Wall |
| `4` | Not bound | Water Counter |
| `5` | Right trigger | Water Pelt |
| `R` | D-pad right | Revive a nearby teammate as a lifeguard |
| `F` | D-pad up | Look at the scoreboard |
| `C` | Select | Toggle voice chat |
| `Escape` | Start | Leave solo play or open the online disconnect menu |

# Arcade Mode

In **Arcade Mode**, take the fight into the air with jumps, targeted dashes, and midair clashes. You have 200 stamina, no lifeguards, and plenty of opportunities to send someone straight back into the pool.

## How to Play

- **Jump and lock onto an opponent**, then press Q to dash at them.
- **Win the midair clash.** If you dash into each other, alternate Q, E, Q, E as quickly as you can. A wrong key or falling behind sends you downward.
- **Choose your next move after an evenly matched clash.** Press Q to retreat to your previous position, or E to hurdle over your opponent and gain height.
- **Follow up with a ground pound.** Get above an opponent and press Shift + Space to slam down for 75 stamina damage.
- **Earn three eliminations to charge your ultimate.** Hold Q and E to raise a cube overhead, aim with the mouse, and click to throw it.

## A Few Things to Know

- The normal water attacks are still available.
- Watch the crosshair. If it says you're not locked on, you don't have a dash target yet.
- There are no lifeguards in this mode, so nobody is coming over to revive you.
- The ultimate cube knocks out anyone it hits and passes through the pool before despawning.
- Eliminate the other team to win the round.

## Controls

| Keyboard / Mouse | Controller | Action |
|---|---|---|
| `W` / `S` | Left stick | Move |
| `A` / `D` | Right stick | Turn / look |
| `Shift` + `W` / `S` | Hold left stick click while moving the stick | Swim |
| `Space` | Bottom face button | Jump |
| `Q` | Left trigger | Dash at a locked-on opponent, or retreat after a tied clash |
| `Q`, `E`, `Q`, `E` | Alternate left trigger, right trigger, left trigger, right trigger | Fight during a midair clash |
| `E` | Right trigger | Hurdle over your opponent after a tied clash |
| `Shift` + `Space` | Left stick click + bottom face button | Ground pound |
| Hold `Q` + `E` | Hold both triggers | Activate your ultimate after three eliminations |
| Mouse + left click | Aim with the right stick, release and press the left trigger | Aim and throw the ultimate cube |
| `1` / `2` / `3` | Right / left / top face button | Water Power / Water Attack / Water Wall |
| `4` | Not bound | Water Counter |
| `5` | Right trigger, also used for E | Water Pelt |
| `F` | D-pad up | Look at the scoreboard |
| `C` | Select | Toggle voice chat |
| `Escape` | Start | Leave solo play or open the online disconnect menu |

# "Friendly" Pool Party

A water balloon fight with friends.

In **Friendly Pool Party**, fight for control of the hot tub and the inflatables surrounding it. Capture these strategic positions, launch water balloons at your opponents, and establish dominance over the pool.

## How to Play

- **Capture the hot tub** and inflatables to gain control of the pool.
- **Fire water balloons from inflatables** to earn points for your team.
- **Gang up on inflatable occupants** to knock them out, steal their balloons, and gain a tactical advantage.
- **Manage your ammunition.** You can only carry a limited number of balloons, so make every throw count.

## A Few Things to Know

- You have infinite stamina.
- Water balloons are a one-hit KO.
- Balloons can be recovered and reused.

## Controls

| Keyboard / Mouse | Controller | Action |
|---|---|---|
| `W` / `S` | Left stick | Move |
| `A` / `D` | Right stick | Turn / look |
| `Shift` + `W` / `S` | Hold left stick click while moving the stick | Swim |
| `Space` | Bottom face button | Jump onto an inflatable |
| `5` | Right trigger | Fire a water balloon |
| `R` | D-pad right | Pick up a nearby balloon or take one from the bucket |
| `F` | D-pad up | Look at the scoreboard |
| `C` | Select | Toggle voice chat |
| `Escape` | Start | Leave solo play or open the online disconnect menu |

## Voice Chat

Use voice chat to call out enemies and coordinate with your team.

- **Set up your mic when you first join.** The name prompt also lets you enable voice chat and choose which microphone to use.
- **Talk to your teammates.** Match voice chat only goes to players on your team. A mic icon shows who's speaking.
- **Press C or Select to toggle voice chat.** On Nintendo controllers, that's the `−` button. This is a toggle, so you don't need to hold it while talking.
- **In VR, use the disconnect menu's Voice Chat toggle.** Hold both thumbsticks to open it. Couch rooms also have a Microphone toggle in the Rooms panel.
- **Couch rooms have their own voice chat.** Everyone in the room can hear each other, with voices coming from their seats. The Microphone toggle mutes your mic there.

## Death and Spectating

When your stamina reaches zero, you unfortunately drown. Don't worry!
You can still look at your team! There's a gray guy on the sidelines who flies a drone.
This drone allows you to spectate the lifeguard while you're drowned, until the lifeguard revives you.
If the lifeguard dies, you can only see an overhead view of the pool. All hope is lost.

If a game just started, you can still spectate! When you join, press the spectate button.

## VR Controls (very weird at first)

In a real pool, you swim very realistically. In VR, you flap your hands and go zoom.

To swim, put your hands in the water and imitate a very bad swimming stroke.
It doesn't really matter how bad, as long as the hands touch the water.

To attack, put one hand in the water and swing it forward. The harder, the stronger the attack.

Normal Controls (sorta):
- To jump, press A (as usual.)
- To dodge, use the grip buttons.
- To water pelt, press either of the triggers.
- To water wall, hold both triggers and flail your hands back and forth.
- Water counter got removed for balancing purposes.
- Jump Cancelling got removed also for balancing purposes. Now you can swim really fast in VR.

Hold both joysticks to exit a game.
What I think is really cool is people can see your hand positions. Yeah.

In arcade mode, Left and Right trigger replace Q and E.

## Controller settings

Use the controller column in each mode's controls table. The left stick moves your player and the right stick controls the camera and aiming.

| Button position | Xbox | PlayStation | Nintendo |
|---|---|---|---|
| Bottom face button | A | Cross | B |
| Right face button | B | Circle | A |
| Left face button | X | Square | Y |
| Top face button | Y | Triangle | X |
| Left / right trigger | LT / RT | L2 / R2 | ZL / ZR |
| Select | View | Share / Create | `−` |
| Start | Menu | Options | `+` |

- Move the stick or D-pad to navigate menus, then press the bottom face button to select.
- Double-tap D-pad left or right to dodge in the shallow end or on land.
- The bottom face button also hurdles when you're near a ledge, or starts a cannon ball after jumping off the diving board.
- In solo play, D-pad down toggles lifeguard and D-pad left cycles through Normal, King of the Cube, Arcade, and Friendly Pool Party.
- Water Counter was removed to balance controller mode. 

## Matchmaking

### Quick Play/Join Code

To hop in a match and play fast, press the quick play button, connecting you to an open room or making a new one. Make sure you have internet at all times! (You will need to communicate to the matchmaker)
If you want to join a friend without their IP, you can join with a code if they used quick play.

### Custom Servers

If you don't want to connect to matchmaking and have randoms join your room, you can make your own server.
You just share the IP and port with your friends and they can connect.

### Solo Play

If you just want to play alone, there's always solo play. It doesn't require internet.

#### Fake Friends

Not the real name for the feature, but good enough.

This feature lets you place fake players in the water to practice with.

Step by step:
- Ctrl+C to spawn a player at your location
- Ctrl+E while hovering over a player to edit its settings
- You can edit the move the player spams, infinite stamina, lifeguard and team
- Ctrl+D while hovering over a player to delete it

## VR Builds

Forgive me. I used powershell. I know. But I had to because of windows.

### How to Build
On Windows, `.\start_vr.ps1` starts PCVR without generating Quest texture formats.
Use `pwsh -File ./build_quest.ps1` on Windows (just use `.\build_quest.ps1`), macOS or Linux to export a standalone Quest debug APK at `build/flowstate-quest.apk`.
Both scripts accept `-Godot "C:\path\to\Godot.exe"`; the build script also accepts `-Output` and/or `-Release`.

### Prerequisites
- Godot 4.6+ export templates
- Android SDK, JDK 17 and debug keystore configured in Godot
- Internet access for Gradle dependencies (first build only)

### Other Notes
AS (ante-script): This setup takes a while as android is pretty annoying. I could probably just make a [release](https://github.com/OrtheSnowJames/orthesnowjames.github.io/releases/tag/flowstate-latest) of the .apk...
Release exports additionally need release signing configured in the Meta Quest export preset.
Quest imports live in `.godot/quest-build/project`, separate from the PCVR cache; the first Quest export imports assets once.

## TODO:
- Done: Diving board
- Done: Voice chat
- Done: Solo Play Sandbox
- Done: "Fun" mode - water balloons, higher ground, otter pops and more fun I guess (I realize I made this game too competitive)
- Allow quick time event to flip the inflatable and get people off the high ground.
- Done? Untested, also only in alpha on my meta dashboard: VR couch parties with quest friends
- Done: Fix bug where you can clip out of map
- Done: Make stamina only start running out when you start moving
