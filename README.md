# Breakout game
This is an implementation of a breakout game using the Mach Engine.
The game is designed around the Mach ECS library and reuses code 
provided by the Mach examples. The primary I goal is to explore the
different features available.

Running the game
```
zig build run
```

## Controls
* Space to launch ball
* Left and right to control paddle
* p to pause the game
* q or esc to exit

Each time the bricks are cleared the ball and paddle will speed up. 

The direction of the ball can be manipulated by keeping the paddle in motion as the ball lands. The ball horizontal speed will increase in 
the direction that the paddle is moving. Making the ball trajectory 
shallower or steeper.

## Implementation
The paddle, ball, bricks, and walls are the main game entities in the game. In addition background, text, and sound use the gfx.Sprite, gfx.Text, and 
sysgpu modules respectively. Most of the vector computation is done using
mach.math.

