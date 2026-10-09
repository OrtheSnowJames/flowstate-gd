# Flowstate

After going to the pool, have you ever wanted to do your crazy water fights online?
Well now you can! Introducing Flowstate! (I hastily made this name up)

## Movement

Getting around the pool isn't just holding W. Here's the rundown.

1. Walking - On dry land or in the shallow end, forward/back gets you moving up to a capped walking speed. Let go and it fades right back out.
2. Swimming - Hold the swim key and forward/back to actually get going. There's a short wind-up before you hit full speed, and backstrokes wind up faster than forward strokes.
3. Gliding - Let go of the swim key without stopping and you'll coast on your last heading, bleeding momentum the whole way, until you run dry or hit a movement key.
4. Turning - A/D turn you (and the camera with you) instead of strafing. There's an option to make holding a turn key ramp up instead of turning at full speed right away.
5. Backstroke flip - Tap forward right after letting go of back and you'll spin 180° on the spot without losing momentum, instead of coasting to a stop first.
6. Dodge - Double-tap A or D to dodge sideways. Only works in the shallow end or on dry land, since there's nothing to push off of in open water. Costs stamina and has its own cooldown.
7. Jump - Same shallow-end-or-dry-land rule as the dodge. A jump spends your ENTIRE momentum bar on the way up - the more you had, the higher you go, but you land with none of it left.
8. Scoreboard - Press F to pan the camera to the scoreboard. The scoreboard measures how many times your team has fainted an enemy. First to the goal wins!

## Combat

There are a few combat features we made. First, there are 2 roles.
1. Normal - Just a normal dude.
2. Lifeguard - Chosen randomly. Expends less stamina, goes faster, and can revive fainted teammates.

Next, we need to cover stamina. You can't just swim forever!
You only have 100 points of stamina.
1. When you get hit, you lose a TON of stamina.
2. When you use an attack, you lose a little bit of stamina.
3. When you swim or tread, you lose stamina.
4. Standing in the shallow end is the only way to recover stamina.

If you lose all your stamina, you faint. Here's what that actually means.
1. You go limp and just drift with the water - no more input until someone brings you back.
2. Your screen fades to black and your ears start ringing. It's unsettling on purpose.
3. Any lifeguard on your team can swim up next to you and revive you, handing back half your stamina and snapping your screen right back open.
4. If the lifeguard faints, the whole team can't revive anymore - not even to save the lifeguard themself.
5. If your whole team faints, the round's over and the other team wins. Everyone gets revived automatically so nobody's left staring at black, then it's back to the lobby for a rematch.

Don't worry! That's why we made the lifeguard an absolute unit.
1. The lifeguard can block most of an attack's damage, since it's holding a kickboard.
2. The lifeguard can hit for 80 points of stamina damage if performed correctly.
3. The lifeguard expends virtually no stamina swimming or treading.

Now let's talk Momentum. It decides how hard your attacks hit and how high you can jump.
1. The more momentum you have, the higher you can jump.
2. You build momentum by swimming, and backstrokes build it 2x as fast as swimming forward.
3. Attack while swimming and you'll dump your entire momentum bar into the hit. This can more than double your attack power.

What you've all been waiting for, finally, the moves.
1. Water Power - Launches a long range wave that hits harder the farther away the enemy is.
2. Water Attack - Shoots a burst of short range water that hits harder the closer the enemy is.
3. Water Wall - Halves incoming damage while it's up, no matter which direction it comes from.

## Death and Spectating

When your stamina reaches zero, you unfortunately drown/faint. Don't worry!
You can still look at your team! There's a gray guy on the sidelines who flies a drone.
This drone allows you to spectate the lifeguard while you're fainted, until the lifeguard revives you.
If the lifeguard dies, you can only see an overhead view of the pool. All hope is lost.

If a game just started, you can still spectate! When you join, press the spectate button.

## TODO:
- Add matchmaking/lobbies
