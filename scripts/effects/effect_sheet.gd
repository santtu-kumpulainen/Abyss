class_name EffectSheet
extends Resource
## One-shot sprite-sheet effect (Free Pixel Effects Pack, 100x100 frames in a
## grid). Play it with PixelEffect.spawn(). `first_frame`/`frame_count` select the
## filled cells of the sheet (some sheets start with an empty cell).

@export var texture: Texture2D
## Frames per row (sheet width / 100).
@export var columns: int = 1
## Index of the first filled cell and the number of frames to play.
@export var first_frame: int = 0
@export var frame_count: int = 1
@export var fps: float = 60.0
## Sprite scale (the source cell is 100x100 px).
@export var scale: float = 0.5
@export var tint: Color = Color.WHITE
