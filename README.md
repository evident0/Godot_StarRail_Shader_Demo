# Godot Toon Shader With Contact Shadows
![](./preview.gif)

## NOTES
* This project demonstrates the use of screen-space shadows in Godot to add clean shadows to a toon shader.
* Why do this? You can't easily modify the shadow map of the directional light. The shadows the directional light casts are not very accurate at small distances.
* Unity already implements screen space shadows in the engine.
* The main shader is implemented in the next-pass of the material.
* Some inputs of the shader are globals and you can change them in the project settings.
* The toon shader is not made to accurately copy the game's shader but to help enhance the demo a bit.
* The sdf texture is roughly mapped to the face, for a better example see [face_shader](https://github.com/evident0/Face_Toon_Shader).
