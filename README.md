This project allows you to convert Adobe Flash/Animate swf animations to Godot's native format.

If you have Adobe/Animate, open GodotExport.fla and compile.
GodotExport.exe and GodotExport.air are compiled versions to be used with Adobe Air already installed on your system.
Install the runtime before launching them: https://airsdk.harman.com/runtime

In the ‘examples’ folder, you will find an animation formatted correctly for optimized export and the result in Godot format.

The export supports sequences.

EXPORTING AN ANIMATION.
- I recommend having MovieClips with unique names at the root of the scene, otherwise there will be duplicate clips on all scenes. This is because an unnamed clip becomes a new instance from one scene to another.
- Avoid using animated Shapes at the root, use MovieClips instead.
- Filter effects are not supported in the export.

TODO:
- Bug to be fixed regarding the sorting of clips in the scene.
- Export for sprite3D.
- Unique texture for images.

Translated with DeepL.com (free version)
-------------------------------------------------------------------------------------
Ce projet permet la conversion d'animations Adobe Flash/Animate swf au format natif de Godot.

Si vous avez Adobe/Animate, ouvrez le GodotExport.fla et compilez.
GodotExport.exe et GodotExport.air sont des versions compilées pour être utilisées avec une instalation préalable de Adobe Air sur votre système.
Installez le runtime avant de les lancer : https://airsdk.harman.com/runtime

Dans le dossier 'examples', vous trouverez une animation formatée correctement pour un export optimisé et le résultat au format Godot.

L'export supporte les séquences.

EXPORTER UNE ANIMATION.
- Je conseille d'avoir à la racine de la scène des MovieClip dont le nom est unique car sinon il y aura des duplications de clips sur toutes les scènes. Cela est du au fait qu'un clip non nommé devient une instance nouvelle d'une scène à l'autre.
- Evitez d'utiliser des Shapes animées à la racine, privilégiez les MovieClip.
- Les effets de filtres ne sont pas gérés dans l'export.

TODO :
- Bug à régler sur le tri des clips dans la scène
- Export pour les sprite3D
- Texture unique pour les images.
  
