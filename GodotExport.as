package {
	import com.adobe.images.PNGEncoder;
	import flash.display.*;
	import flash.events.*;
	import flash.filesystem.*;
	import flash.geom.*;
	import flash.net.URLRequest;
	import flash.utils.*;
	import flash.desktop.ClipboardFormats;
	import flash.desktop.NativeDragManager;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.setTimeout;
	
	public class GodotExport extends Sprite {
		private var _root:DisplayObjectContainer;
		private var rootMovieClip:MovieClip;
		private var swfLoader:Loader;
		private var outputFolder:File;
		
		private var tscnContent:String = '';
		private var textureID:int = 1;
		private var animationID:int = 1;
		private var textureUIDs:Object = {}; // path -> uid
		
		private var listHeader : String = '';
		private var listTexture : Array = new Array();
		private var listNode : Array = new Array();
		private var listAnimationPlayer : String = '';
		private var listAnimationLibrary : String = '';
		private var listAnimationHeader = '';

		private var listAnimationScene : Array = new Array();
		private var listAnimationName : Array = new Array();
		
		private var listClipName : Array = new Array();
		private var listAnimatedClip : Array = new Array();
		
		private var currentScene : Scene;
		
		private var clipNameToTex : Dictionary = new Dictionary();
		private var pngToName : Dictionary = new Dictionary();
		
		private var outputFolderSt :String = "exportSwf";
		private var outputFolderAnimSt : String;
		
		private var currentFrameRate = 0;
		private var dictTransitionDetectors : Dictionary = new Dictionary();

		private var dropZone:Sprite;
		private var swfMask:Sprite;
		private var titleText:TextField;
		private var openFolderBtn:Sprite;
		private var openFolderLabel:TextField;
		private var conversionMsgContainer:Sprite;
		private var errorMsg = '';
		private const MAX_ATLAS_WIDTH:int = 2048;
		private const MAX_ATLAS_HEIGHT:int = 2048;
		private var marginXInput:TextField;
		private var marginYInput:TextField;
		private var marginContainer:Sprite;
		private var atlasEnabledCheckbox:Sprite;
		private var atlasEnabled:Boolean = false;
		private var bitmapDataCache:Dictionary = new Dictionary();
		private var atlasRects:Dictionary;
		
		public function GodotExport() {
			if (File.desktopDirectory) {
				outputFolder = File.desktopDirectory.resolvePath("SWF_Export");
				if (!outputFolder.exists) outputFolder.createDirectory();

				// === ZONE DE DROP ===
				dropZone = createDropZone();
				createOpenFolderButton();
				createMarginInputs();
				addChild(dropZone);

				dropZone.addEventListener(NativeDragEvent.NATIVE_DRAG_ENTER, onDragEnter);
				dropZone.addEventListener(NativeDragEvent.NATIVE_DRAG_DROP, onDragDrop);

				swfLoader = new Loader();
				swfLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, onSWFLoaded);

				trace("Glissez-déposez un fichier SWF sur la fenêtre pour commencer...");
			} else {
				trace("Erreur : Ce script nécessite Adobe AIR pour accéder au système de fichiers.");
			}
		}

		// === Drag & Drop ===
		private function onDragEnter(e:NativeDragEvent):void {
			if (e.clipboard.hasFormat(ClipboardFormats.FILE_LIST_FORMAT)) {
				NativeDragManager.acceptDragDrop(dropZone);
			}
		}

		private function resetForNewSWF():void {
			// 1. Supprimer le SWF précédent de l'affichage
			if (_root != null) {
				// Retirer tous les enfants du _root
				while (_root.numChildren > 0) {
					var child:DisplayObject = _root.getChildAt(0);
					if (child is MovieClip) MovieClip(child).stop(); // Stoppe les animations
					_root.removeChild(child);
				}
				// Retirer _root du parent
				if (_root.parent) _root.parent.removeChild(_root);
			}
			_root = null;
			rootMovieClip = null;

			// 2. Vider les données statiques/globales
			SceneData.allSceneData = [];
			SceneData.currentSceneData = null;
			SceneData.frameCounter  = 0;
			NodeData.allNodesData = [];



			// 3. Réinitialiser les listes et dictionnaires
			errorMsg = '';
			listHeader = '';
			listTexture = [];
			listNode = [];
			listAnimationPlayer = '';
			listAnimationLibrary = '';
			listAnimationHeader = '';
			listAnimationScene = [];
			listAnimationName = [];
			listClipName = [];
			listAnimatedClip = [];
			tscnContent = '';
			textureID = 1;
			animationID = 1;
			textureUIDs = {};
			clipNameToTex = new Dictionary();
			pngToName = new Dictionary();
			for each (var td:TransitionDetector in dictTransitionDetectors) {
				td.frameData = new Vector.<FrameData>(); // vide les frames
			}
			dictTransitionDetectors = new Dictionary(); // réinitialise le dictionnaire

			trace("✨ Nettoyage terminé — prêt à charger un nouveau SWF");
		}

		private function onDragDrop(e:NativeDragEvent):void {
			var files:Array = e.clipboard.getData(ClipboardFormats.FILE_LIST_FORMAT) as Array;
			if (files.length > 0) {
				var swfFile:File = files[0];
				if (swfFile.extension && swfFile.extension.toLowerCase() == "swf") 
				{
					resetForNewSWF(); // 🔥 Nettoyage avant chargement
					showConvertingMessage();
					trace("Chargement du fichier SWF : " + swfFile.nativePath);
					swfLoader.load(new URLRequest(swfFile.url));
				} else {
					trace("Erreur : Veuillez déposer un fichier SWF valide.");
				}
			}
		}
		
		private function onSWFLoaded(e:Event):void {
			try {
				start(e);
				showConversionMessage();
			} catch (error:Error) {
				var fullError:String = "Error: " + error.message + "\n\nStack Trace:\n" + error.getStackTrace();
				trace(fullError); // Keep tracing just in case
				showErrorMessage(fullError);
			}
		}

		public function start(e:Event)
		{
			var loaderInfo:LoaderInfo = e.target as LoaderInfo;
			var fileURL:String = loaderInfo.url;
			var fileName:String = fileURL.substring(fileURL.lastIndexOf("/") + 1);
			outputFolderAnimSt = fileName.replace(".swf", "");

			// --- Create main export folder if it doesn't exist ---
			var mainExportFolder:File = File.desktopDirectory.resolvePath("SWF_Export");
			if (!mainExportFolder.exists) {
				mainExportFolder.createDirectory();
			}

			// --- Create or reset subfolder for this specific SWF ---
			outputFolder = mainExportFolder.resolvePath(outputFolderAnimSt);

			// If the subfolder already exists, delete it entirely
			if (outputFolder.exists) {
				try 
				{
					outputFolder.deleteDirectory(true);
					trace("Old export folder deleted: " + outputFolder.nativePath);
				} catch (err:Error) 
				{
					trace("⚠ Unable to delete existing animation folder: " + err.message);
				}
			}

			// Create a fresh folder for this animation
			outputFolder.createDirectory();

			// --- Load SWF content ---
			var swf:DisplayObject = e.target.content;
			dropZone.addChild(swf);

			// === AJOUT DU MASQUE ===
			if (!swfMask) {
				swfMask = new Sprite();
				swfMask.graphics.beginFill(0xFFFFFF, 1); // masque opaque
				swfMask.graphics.drawRect(0, 0, 500, 500);
				swfMask.graphics.endFill();
				swfMask.x = 0;
				swfMask.y = 0;
				dropZone.addChild(swfMask);
			}

			swf.mask = swfMask; // Applique le masque
			currentFrameRate = loaderInfo.frameRate;

			_root = DisplayObjectContainer(swf);
			rootMovieClip = MovieClip(_root);

			var _scenes:Array = rootMovieClip.scenes;
			for each (var _scene : Scene in _scenes) {
				var _sceneData : SceneData = new SceneData();
				_sceneData.init(_scene, currentFrameRate);
				SceneData.allSceneData.push(_sceneData);
			}

			SceneData.currentSceneData = SceneData.allSceneData[0];

			//-----------------------------------------------------------
			listHeader = '[gd_scene load_steps=1 format=3 uid=\"uid://' + generateUID() + '\"]\n';
			listNode.push('[node name="root_clip" type="Node2D"]\n\n');
			listAnimationLibrary = 'AnimationLibrary_' + generateUIDTex();
			listAnimationPlayer = '[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {\n&"": SubResource("'+listAnimationLibrary+'")\n}\n';

			var _incFrame = 1;
			for each(var _sd1 : SceneData in SceneData.allSceneData) {
				for (var f:int = _sd1.startFrame; f <= _sd1.endFrame; f++) 
				{
					var _sc : Scene = _sd1.currentScene;
					rootMovieClip.gotoAndStop(_incFrame, _sc.name);

					for (var i:int = 0; i < _root.numChildren; i++) {
						var _clip = _root.getChildAt(i);

						parseDisplayObject(_clip, _root, i.toString());

						if(_clip is MovieClip || _clip is Shape) {
							var _clipName : String = _clip.name;
							var detector : TransitionDetector;

							if(_clipName in dictTransitionDetectors) {
								detector = dictTransitionDetectors[_clipName];
							} else {
								detector  = new TransitionDetector(rootMovieClip, _clipName);
								dictTransitionDetectors[_clipName] = detector;
							}

							detector.addFrame(f-1,_clip,_sc);
						}
					}
					_incFrame++;
					if(f == _sd1.endFrame) 
					{
						_incFrame = 1;
					}
				}
			}

			for(var k:int = 0; k < SceneData.allSceneData.length; k++) {
				SceneData.currentSceneData = SceneData.allSceneData[k];
				insertAnimationDatas();
			}

			//----------------------------------
			tscnContent += listHeader + '\n\n';

			if (atlasEnabled) {
				generateAtlas();
			}
			for each (var _tex:String in listTexture) {
				tscnContent += _tex + '\n';
			}
			tscnContent += '\n\n';

			for(var l:int = 0; l < SceneData.allSceneData.length; l++) {
				SceneData.currentSceneData = SceneData.allSceneData[l];
				tscnContent += getAnimationDatas();
			}

			//---------  ANIMATION LIBRARY AND PLAYER   ------------------------
			tscnContent += '[sub_resource type="AnimationLibrary" id="'+ listAnimationLibrary+'"]\n_data = {\n';

			var _inc = 0;
			for each (var _sd : SceneData in SceneData.allSceneData) {
				tscnContent += '&"'+_sd.currentScene.name+'": SubResource("'+_sd.id+'")';
				if(SceneData.allSceneData.length == 1) {
					tscnContent += '\n';
				}
				if(SceneData.allSceneData.length > 1 && _inc != SceneData.allSceneData.length-1) {
					tscnContent += ',\n';
				}
				_inc++;
			}
			tscnContent += '}\n\n';

			for each (var _node:String in listNode) {
				tscnContent += _node;
			}

			for each(var _nd : NodeData in NodeData.allNodesData) {
				for each(var _nl:String in _nd.nodeList) {
					tscnContent += _nl;
				}
			}

			tscnContent += '\n' + listAnimationPlayer;

			//------------------------------------------------------------
			var tscnFile:File = outputFolder.resolvePath("exported_scene.tscn");
			var fs:FileStream = new FileStream();
			fs.open(tscnFile, FileMode.WRITE);
			fs.writeUTFBytes(tscnContent);
			fs.close();
		}

		private function generateAtlas():void {
			var keyCount:int = 0;
			for (var key:String in bitmapDataCache) {
				keyCount++;
			}
			if (keyCount == 0) {
				return;
			}

			atlasRects = new Dictionary();
			var atlases:Array = [];
			
			var currentAtlasIndex:int = 0;
			var currentX:int = 0;
			var currentY:int = 0;
			var currentRowHeight:int = 0;

			var createNewAtlas = function():void {
				atlases.push(new BitmapData(MAX_ATLAS_WIDTH, MAX_ATLAS_HEIGHT, true, 0x00000000));
				currentX = 0;
				currentY = 0;
				currentRowHeight = 0;
			};

			createNewAtlas();

			for (var id:String in bitmapDataCache) {
				var item:Object = bitmapDataCache[id];
				var bd:BitmapData = item.bd;

				if (currentX + bd.width > MAX_ATLAS_WIDTH) {
					currentX = 0;
					currentY += currentRowHeight;
					currentRowHeight = 0;
				}

				if (currentY + bd.height > MAX_ATLAS_HEIGHT) {
					currentAtlasIndex++;
					createNewAtlas();
				}

				var atlas:BitmapData = atlases[currentAtlasIndex];
				var destPoint:Point = new Point(currentX, currentY);
				try {
					bd.lock();
					atlas.copyPixels(bd, bd.rect, destPoint);
					bd.unlock();
				} catch (e:Error) {
					throw new Error("Failed during copyPixels in generateAtlas for texture ID '" + id + "'. Original error: " + e.message);
				}

				atlasRects[id] = {
					rect: new Rectangle(currentX, currentY, bd.width, bd.height),
					atlasIndex: currentAtlasIndex
				};

				currentX += bd.width;
				if (bd.height > currentRowHeight) {
					currentRowHeight = bd.height;
				}
			}

			// --- Save atlases and create ExtResources ---
			for (var i:int = 0; i < atlases.length; i++) {
				var atlasBitmap:BitmapData = atlases[i];
				var atlasPath:String = "textures/texture_atlas_" + i + ".png";
				var file:File = outputFolder.resolvePath(atlasPath);
				if (!file.parent.exists) file.parent.createDirectory();
				
				var fs:FileStream = new FileStream();
				fs.open(file, FileMode.WRITE);
				try {
					fs.writeBytes(PNGEncoder.encode(atlasBitmap));
				} catch (e:Error) {
					throw new Error("Failed during PNGEncoder.encode in generateAtlas for atlas #" + i + ". Original error: " + e.message);
				}
				fs.close();

				var atlasUUID:String = generateUID();
				var atlasTexPath:String = outputFolderAnimSt + '/' + atlasPath;
				var atlasID:String = "atlas_texture_" + i;
				var atlasTex:String = '[ext_resource type="Texture2D" uid="uid://'+ atlasUUID +'" path="res://' + atlasTexPath + '" id="' + atlasID + '"]\n';
				listTexture.push(atlasTex);
			}

			// --- Replace placeholders in node data ---
			for each (var nodeData:NodeData in NodeData.allNodesData) {
				for (var j:int = 0; j < nodeData.nodeList.length; j++) {
					var nodeString:String = nodeData.nodeList[j];

					// Replace texture placeholder
					var textureRegex:RegExp = /texture = ATLAS_TEXTURE_PLACEHOLDER_FOR_ID_([a-zA-Z0-9_]+)/;
					var textureMatch:Object = textureRegex.exec(nodeString);
					if (textureMatch) {
						var textureId:String = textureMatch[1];
						if (textureId in atlasRects) {
							var atlasInfo:Object = atlasRects[textureId];
							var replacement:String = 'texture = ExtResource("atlas_texture_' + atlasInfo.atlasIndex + '")';
							nodeString = nodeString.replace(textureMatch[0], replacement);
						}
					}

					// Replace rect placeholder
					var rectRegex:RegExp = /region_rect = ATLAS_RECT_PLACEHOLDER_FOR_ID_([a-zA-Z0-9_]+)/;
					var rectMatch:Object = rectRegex.exec(nodeString);
					if (rectMatch) {
						var rectTextureId:String = rectMatch[1];
						if (rectTextureId in atlasRects) {
							var rectAtlasInfo:Object = atlasRects[rectTextureId];
							var rect:Rectangle = rectAtlasInfo.rect;
							var rectReplacement:String = "region_rect = Rect2(" + rect.x + ", " + rect.y + ", " + rect.width + ", " + rect.height + ")";
							nodeString = nodeString.replace(rectMatch[0], rectReplacement);
						}
					}
					
					nodeData.nodeList[j] = nodeString;
				}
			}
		}

		private function showConvertingMessage():void {
			// Supprimer ancien message s'il existe
			if (conversionMsgContainer && contains(conversionMsgContainer)) {
				removeChild(conversionMsgContainer);
			}

			conversionMsgContainer = new Sprite();

			// ==== Texte ====
			var msg:TextField = new TextField();
			msg.text = "⏳ Converting...";
			msg.textColor = 0x00008B; // bleu foncé
			msg.selectable = false;
			msg.autoSize = "center";

			var format:TextFormat = new TextFormat();
			format.font = "Arial";
			format.size = 24;
			format.bold = true;
			format.align = "center";
			msg.setTextFormat(format);
			msg.defaultTextFormat = format;

			// ==== Cadre ====
			var padding:int = 20;
			var boxWidth:Number = msg.width + padding * 2;
			var boxHeight:Number = msg.height + padding * 2;

			conversionMsgContainer.graphics.lineStyle(3, 0x00008B); // contour bleu foncé
			conversionMsgContainer.graphics.beginFill(0xFFFFFF, 1); // fond blanc
			conversionMsgContainer.graphics.drawRoundRect(0, 0, boxWidth, boxHeight, 15, 15);
			conversionMsgContainer.graphics.endFill();

			// Positionnement du texte
			msg.x = padding;
			msg.y = padding;
			conversionMsgContainer.addChild(msg);

			// Centrage
			conversionMsgContainer.x = (stage.stageWidth - boxWidth) / 2;
			conversionMsgContainer.y = (stage.stageHeight - boxHeight) / 2;

			addChild(conversionMsgContainer);
		}


		private function showConversionMessage():void {
			// Supprimer ancien message s'il existe
			if (conversionMsgContainer && contains(conversionMsgContainer)) {
				removeChild(conversionMsgContainer);
			}

			conversionMsgContainer = new Sprite();

			// ==== Texte ====
			var msg:TextField = new TextField();
			msg.text = "✅ Conversion completed!";
			msg.textColor = 0x00008B; // bleu foncé
			msg.selectable = false;
			msg.autoSize = "center";

			var format:TextFormat = new TextFormat();
			format.font = "Arial";
			format.size = 24;
			format.bold = true;
			format.align = "center";
			msg.setTextFormat(format);
			msg.defaultTextFormat = format;

			// ==== Cadre ====
			var padding:int = 20;
			var boxWidth:Number = msg.width + padding * 2;
			var boxHeight:Number = msg.height + padding * 2;

			conversionMsgContainer.graphics.lineStyle(3, 0x00008B); // contour bleu foncé
			conversionMsgContainer.graphics.beginFill(0xFFFFFF, 1); // fond blanc
			conversionMsgContainer.graphics.drawRoundRect(0, 0, boxWidth, boxHeight, 15, 15);
			conversionMsgContainer.graphics.endFill();

			// Positionnement du texte dans le cadre
			msg.x = padding;
			msg.y = padding;
			conversionMsgContainer.addChild(msg);

			// Centrage du container
			conversionMsgContainer.x = (stage.stageWidth - boxWidth) / 2;
			conversionMsgContainer.y = (stage.stageHeight - boxHeight) / 2;

			addChild(conversionMsgContainer);

			// Disparition après 3 secondes
			setTimeout(function():void {
				if (conversionMsgContainer && contains(conversionMsgContainer)) {
					removeChild(conversionMsgContainer);
				}
			}, 3000);
		}

		private function showErrorMessage(msg:String):void {
			// Supprimer ancien message s'il existe
			if (conversionMsgContainer && contains(conversionMsgContainer)) {
				removeChild(conversionMsgContainer);
			}

			conversionMsgContainer = new Sprite();

			// ==== Texte ====
			var textField:TextField = new TextField();
			textField.text = "❌ Error: " + msg;
			textField.textColor = 0x8B0000; // rouge foncé
			textField.selectable = false;
			textField.wordWrap = true;
			textField.width = 460; // texte à l'intérieur de la box de 500 avec padding 20
			textField.autoSize = "left";

			var format:TextFormat = new TextFormat();
			format.font = "Arial";
			format.size = 14; // taille du texte
			format.bold = true;
			format.align = "center";
			textField.setTextFormat(format);
			textField.defaultTextFormat = format;

			// ==== Cadre ====
			var padding:int = 20;
			var boxWidth:Number = 500; // largeur fixe
			var boxHeight:Number = textField.height + padding * 2;

			conversionMsgContainer.graphics.lineStyle(3, 0x8B0000); // contour rouge foncé
			conversionMsgContainer.graphics.beginFill(0xFFFFFF, 1); // fond blanc
			conversionMsgContainer.graphics.drawRoundRect(0, 0, boxWidth, boxHeight, 15, 15);
			conversionMsgContainer.graphics.endFill();

			// Positionnement du texte dans le cadre
			textField.x = padding;
			textField.y = padding;
			conversionMsgContainer.addChild(textField);

			// Centrage du container
			conversionMsgContainer.x = (stage.stageWidth - boxWidth) / 2;
			conversionMsgContainer.y = (stage.stageHeight - boxHeight) / 2;

			addChild(conversionMsgContainer);

			// Disparition après 3 secondes
			setTimeout(function():void {
				if (conversionMsgContainer && contains(conversionMsgContainer)) {
					removeChild(conversionMsgContainer);
				}
			}, 6000);
		}

		
		private function parseDisplayObject(obj:DisplayObject, _parent:*, _index : String ='', _parent_path = '.'):void {
			var nodeName:String = obj.name;
			
			var _st = '';
			var _haveValue = checkValueInArray(listClipName,nodeName);
			if (obj is MovieClip && _haveValue == false) 
			{	

				fillListClipName(nodeName);
				listAnimatedClip.push(nodeName);

				_st += createMovieClipNode(obj,nodeName,_index,_parent_path);
			} else 
			if ((obj is Sprite || obj is Shape || obj is Bitmap) && _haveValue == false) 
			{
				
				fillListClipName(nodeName);
				listAnimatedClip.push(nodeName);

				_st += createShapeNode(obj,nodeName,_index,_parent_path)
			}
			
			if (obj is DisplayObjectContainer && _haveValue == false) {
				var container:DisplayObjectContainer = DisplayObjectContainer(obj);
				for (var i:int = 0; i < container.numChildren; i++) 
				{
					var _new_path =''
					if(_parent_path == '.')
					{
						_new_path = container.name;
					}
					else
					{
						_new_path = _parent_path+'/'+container.name;
					}

					var _newIndex : String = _index + '-' + i;
					parseDisplayObject(container.getChildAt(i), container,_newIndex,_new_path); 
				}
			}
		}

		public function createMovieClipNode(obj : *, nodeName : String,_index : String , _parent_path : String):String
		{
			var _st : String = '';

			
			//trace('index : '+ _index);

			var _scaleX = getSignedScale(obj).x;
			var _scaleY = getSignedScale(obj).y;
			
			_st += '[node name="' + nodeName + '" type="Node2D" parent="' + _parent_path+'"]\n';
			_st += 'position = Vector2('+Math.ceil(obj.x)+','+Math.ceil(obj.y)+')\n'
			_st += 'rotation = '+ GodotExport.getTrueRotationRadians(obj) +'\n'
			_st += 'scale = '+ 'Vector2('+ convertToTwoDecimal(_scaleX) +','+convertToTwoDecimal(_scaleY)+')\n';
			//_st += 'scale = Vector2('+Math.ceil(obj.scaleX)+','+Math.ceil(obj.scaleY)+')\n'

			var _nodeData : NodeData = new NodeData();
			_nodeData.clipName = nodeName;
			_nodeData.nodeList.push(_st);
			NodeData.allNodesData.push(_nodeData);

			return _st;
		}

		public function createShapeNode(obj : *, nodeName : String,_index : String , _parent_path : String):String
		{
			//trace('index : '+ _index);
			var _matrix = getLocalBoundsAndCenter(obj);
			var _scale : Point = getSignedScale(obj);
			var _bounds : Rectangle= obj.getBounds(obj.parent)
			var _st : String = '';

			var _idTex : String = exportSprite(obj, nodeName);
			if (_idTex == null) {
				return ""; // Don't create a node for an empty sprite
			}
			var _offset : String = '';
			var _posX : int = _bounds.x;
			var _posY : int = _bounds.y;
			var _width : int = _bounds.width;
			var _height : int = _bounds.height;
			var _posXFinal : int = _posX + (_width/2);
			var _posYFinal : int = _posY + (_height/2);

			_st += '[node name="'+nodeName+'" type="Sprite2D" parent="' + _parent_path+'"]\n';
			_st += 'position = Vector2('+Math.ceil(_posXFinal)+','+Math.ceil(_posYFinal)+')\n';
			_st += 'rotation = '+ GodotExport.getTrueRotationRadians(obj) +'\n';
			_st += 'scale = Vector2('+Math.abs(_scale.x)+','+Math.abs(_scale.y)+')\n'
			_st += 'flip_h = '+ (_scale.x < 0)+'\n';
			if (atlasEnabled) {
				_st += 'texture = ATLAS_TEXTURE_PLACEHOLDER_FOR_ID_' + _idTex + '\n';
				_st += 'region_enabled = true\n';
				_st += 'region_rect = ATLAS_RECT_PLACEHOLDER_FOR_ID_' + _idTex + '\n';
			} else {
				_st += 'texture = ExtResource("'+ _idTex +'")\n';
			}


			if(_posXFinal != 0 || _posYFinal != 0) {
				//_offset = 'offset = Vector2('+_posXFinal+','+_posYFinal+')\n';
				_offset = 'offset = Vector2(0,0)\n';
				_st += _offset;
			}
			_st += '\n';

			var _nodeData : NodeData = new NodeData();
			_nodeData.clipName = nodeName;
			_nodeData.nodeList.push(_st);
			NodeData.allNodesData.push(_nodeData);

			return _st
		}



		function fillListClipName(_clipName : String)
		{
			if(listClipName.indexOf(_clipName) > -1) return;
			listClipName.push(_clipName);
		}

		function getDisplayType(obj:Object):String {
			return getQualifiedClassName(obj);
		}

		function getLocalBoundsAndCenter(obj:DisplayObject):Object
		{
			// 1) Matrice locale (par rapport au parent)
			var m:Matrix = obj.transform.matrix;

			// 2) Bornes internes de l'objet (dans SON propre espace local)
			var localBounds:Rectangle = obj.getBounds(obj);

			// 3) Coins locaux (avant transformation)
			var p1:Point = new Point(localBounds.x, localBounds.y);           // top-left
			var p2:Point = new Point(localBounds.right, localBounds.y);       // top-right
			var p3:Point = new Point(localBounds.right, localBounds.bottom);  // bottom-right
			var p4:Point = new Point(localBounds.x, localBounds.bottom);      // bottom-left

			// 4) Transformation par la matrice locale => espace du parent
			p1 = m.transformPoint(p1);
			p2 = m.transformPoint(p2);
			p3 = m.transformPoint(p3);
			p4 = m.transformPoint(p4);

			// 5) Calcul du rectangle final dans l'espace parent
			var minX:Number = Math.min(p1.x, p2.x, p3.x, p4.x);
			var maxX:Number = Math.max(p1.x, p2.x, p3.x, p4.x);
			var minY:Number = Math.min(p1.y, p2.y, p3.y, p4.y);
			var maxY:Number = Math.max(p1.y, p2.y, p3.y, p4.y);

			var width:Number = maxX - minX;
			var height:Number = maxY - minY;

			// 6) Centre défini comme : coin haut-gauche + moitié
			var centerX:Number = minX + width / 2;
			var centerY:Number = minY + height / 2;

			return {
				// Coin supérieur gauche
				x: minX,
				y: minY,
				// Dimensions
				width: width,
				height: height,
				// Centre basé sur le coin supérieur gauche
				centerX: centerX,
				centerY: centerY
			};
		}

		
		private function checkValueInArray(_array : Array,_valueToFind : *):Boolean {
			var _bool : Boolean = false;
			for each(var value:* in _array)
			{
				if(value == _valueToFind)
				{
					_bool = true;
					break
				}
			}
			return _bool;
		}
		
		private function exportSprite(obj:DisplayObject,  nodeName:String):String {
			var marginX:int = parseInt(marginXInput.text) || 0;
			var marginY:int = parseInt(marginYInput.text) || 0;

			var bounds:Rectangle = getRealBounds(obj);
			var w:int = Math.max(1, Math.ceil(bounds.width)) + (marginX * 2);
			var h:int = Math.max(1, Math.ceil(bounds.height)) + (marginY * 2);

			if (w > 8191 || h > 8191) {
				throw new Error("Object '" + nodeName + "' is too large to be exported. Its dimensions (" + w + "x" + h + ") exceed the maximum texture size of 8191px.");
			}

			if (atlasEnabled && (w > MAX_ATLAS_WIDTH || h > MAX_ATLAS_HEIGHT)) {
				throw new Error("Object '" + nodeName + "' (" + w + "x" + h + ") is too large to fit in the texture atlas (max " + MAX_ATLAS_WIDTH + "x" + MAX_ATLAS_HEIGHT + "). Please disable the 'Single Texture' option or reduce the object's size.");
			}

			var _id : String = '';
			
			var bd:BitmapData;
			try {
				bd = new BitmapData(w, h, true, 0x00000000);
				var matrix:Matrix = new Matrix();
				matrix.translate(-bounds.x + marginX, -bounds.y + marginY);
				bd.draw(obj, matrix, null, null, null, true);
			} catch (e:Error) {
				throw new Error("Failed during BitmapData creation/draw in exportSprite for node '" + nodeName + "'. Original error: " + e.message);
			}

			// Check for empty bitmap
			var colorBounds:Rectangle = bd.getColorBoundsRect(0xFF000000, 0x000000, false);
			if (colorBounds == null) {
				return null; // Return null for empty sprites
			}
			var _png:ByteArray;
			try {
				_png = PNGEncoder.encode(bd);
			} catch (e:Error) {
				throw new Error("Failed during PNGEncoder.encode in exportSprite for node '" + nodeName + "'. Original error: " + e.message);
			}
			var _pngSt : String = _png.toString();
			
			_id = textureID + '_' + generateUIDTex();
			if(clipNameToTex.hasOwnProperty(_pngSt) == true) {
				_id = clipNameToTex[_pngSt];
			} else {
				clipNameToTex[_pngSt] = _id;
				if (atlasEnabled) {
					bitmapDataCache[_id] = {bd: bd.clone(), nodeName: nodeName};
				} else {
					var _path : String = "textures/" + nodeName + ".png";
					var file:File = outputFolder.resolvePath(_path);
					if (!file.parent.exists) file.parent.createDirectory();
					var fs:FileStream = new FileStream();
					fs.open(file, FileMode.WRITE);
					fs.writeBytes(_png);
					fs.close();	
					var _uuid : String = generateUID();
					_path = outputFolderAnimSt+'/' +_path;
					var _tex : String = '[ext_resource type="Texture2D" uid="uid://'+ _uuid+'" path="res://' + _path + '" id="' + _id + '"]\n';
					listTexture.push(_tex);
				}
				textureID++;
			}
			return _id;
		}
		
		public static function getRealBounds(obj:DisplayObject):Rectangle {
			var bounds:Rectangle = obj.getBounds(obj);
			if (obj is DisplayObjectContainer) {
				var container:DisplayObjectContainer = DisplayObjectContainer(obj);
				for (var i:int = 0; i < container.numChildren; i++) {
					var child:DisplayObject = container.getChildAt(i);
					var childBounds:Rectangle = getRealBounds(child);
					var topLeftGlobal:Point = child.localToGlobal(new Point(childBounds.x, childBounds.y));
					var childGlobal:Rectangle = new Rectangle(topLeftGlobal.x, topLeftGlobal.y, childBounds.width, childBounds.height);
					var topLeftLocal:Point = obj.globalToLocal(new Point(childGlobal.x, childGlobal.y));
					var childLocal:Rectangle = new Rectangle(topLeftLocal.x, topLeftLocal.y, childGlobal.width, childGlobal.height);
					bounds = bounds.union(childLocal);
				}
			}
			return bounds;
		}

		public static function getLocalBoundsAndCenter(obj:DisplayObject):Object
		{
			// 1) Matrice locale (par rapport au parent)
			var m:Matrix = obj.transform.matrix;

			// 2) Bornes internes de l'objet (dans SON propre espace local)
			var localBounds:Rectangle = obj.getBounds(obj);

			// 3) Coins locaux (avant transformation)
			var p1:Point = new Point(localBounds.x, localBounds.y);           // top-left
			var p2:Point = new Point(localBounds.right, localBounds.y);       // top-right
			var p3:Point = new Point(localBounds.right, localBounds.bottom);  // bottom-right
			var p4:Point = new Point(localBounds.x, localBounds.bottom);      // bottom-left

			// 4) Transformation par la matrice locale => espace du parent
			p1 = m.transformPoint(p1);
			p2 = m.transformPoint(p2);
			p3 = m.transformPoint(p3);
			p4 = m.transformPoint(p4);

			// 5) Calcul du rectangle final dans l'espace parent
			var minX:Number = Math.min(p1.x, p2.x, p3.x, p4.x);
			var maxX:Number = Math.max(p1.x, p2.x, p3.x, p4.x);
			var minY:Number = Math.min(p1.y, p2.y, p3.y, p4.y);
			var maxY:Number = Math.max(p1.y, p2.y, p3.y, p4.y);

			var width:Number = maxX - minX;
			var height:Number = maxY - minY;

			// 6) Centre défini comme : coin haut-gauche + moitié
			var centerX:Number = minX + width / 2;
			var centerY:Number = minY + height / 2;

			return {
				// Coin supérieur gauche
				x: minX,
				y: minY,
				// Dimensions
				width: width,
				height: height,
				// Centre basé sur le coin supérieur gauche
				centerX: centerX,
				centerY: centerY
			};
		}
		
		private function generateUID():String {
			var chars:String = "abcdefghijklmnopqrstuvwxyz0123456789";
			var uid:String = "";
			for (var i:int = 0; i < 12; i++) {
				uid += chars.charAt(Math.floor(Math.random() * chars.length));
			}
			return uid;
		}
		
		private function generateUIDTex():String {
			var chars:String = "abcdefghijklmnopqrstuvwxyz0123456789";
			var uid:String = "";
			for (var i:int = 0; i < 5; i++) {
				uid += chars.charAt(Math.floor(Math.random() * chars.length));
			}
			return uid;
		}
		
		private function getAnimationDatas():String 
		{
			var _tscnContent : String ='';

			for each (var _animationData : AnimationData in SceneData.currentSceneData.animationsDataList) 
			{
				for each(var _data : String in _animationData.datas)
				{
					_tscnContent += _data;
				}
			}
			
			_tscnContent += '\n\n';

			return _tscnContent;
		}
		


		private function insertAnimationDatas() 
		{
			var _arrayProps : Array = [
				['x','y'],
				['scaleX','scaleY'],
				['rotation'],
				//['alpha'],
				['visible']
			] ;


			var _dictGodotPropsName : Object = {
				'x,y': 'position',
				'scaleX,scaleY' : 'scale',
				'rotation' : 'rotation',
				'alpha' : 'alpha',
				'visible' : 'visible'
			}

			var _inc : int = 0;

			var _animationData = new AnimationData();
			var _animation_id = 'Animation_' + generateUIDTex();
			SceneData.currentSceneData.id = _animation_id;
			_animationData.id = _animation_id;
			_animationData.name = SceneData.currentSceneData.currentScene.name;

			var listAnimationHeader = '[sub_resource type="Animation" id="'+_animation_id+'"]\n'
				+ 'resource_name = "' + SceneData.currentSceneData.currentScene.name + '"\n'
				+ 'length = ' + SceneData.currentSceneData.duration+'\n';

			_animationData.datas.push(listAnimationHeader);
			
			
			for each (var _clipName:String in listAnimatedClip) 
			{
				
				var detector : TransitionDetector = dictTransitionDetectors[_clipName];


				if(detector != null) 
				{
					var _clip = detector.findClipByName(rootMovieClip,_clipName);
					
					for each(var _propArray : Array in _arrayProps)
					{
						var _propArraySt = _propArray.toString();
						var _dictData = getPositionVectorsFromFrame(_clip,_clipName,_propArray);//!!!
					
						var _data : String ='';
						var _updateValue = 0;

						if(_propArraySt == 'visible') _updateValue = 1;

						var _times =  _dictData['frames'].join(", ");


						for(var i:int = 0; i < _dictData['values'].length; i++)
						{
							var element : * = _dictData['values'][i];
							if(element === 0) _dictData['values'][i] = '0.0';
						}

						_data += 'tracks/'+ _inc +'/type = "value"\n'
							+ 'tracks/'+ _inc +'/imported = false\n'
							+ 'tracks/'+ _inc +'/enabled = true\n'
							+ 'tracks/'+ _inc +'/path = NodePath("'+_clipName+':'+ _dictGodotPropsName[_propArraySt] +'")\n'
							+ 'tracks/'+ _inc +'/interp = 1\n'
							+ 'tracks/'+ _inc +'/loop_wrap = false\n'
							+ 'tracks/'+ _inc +'/keys = {\n'
							+ '"times": PackedFloat32Array('+ _times +'),\n'
							+ '"transitions": PackedFloat32Array('+ _dictData['transitions'].join(", ") +'),\n'
							+ '"update": ' + _updateValue + ',\n'
							+ '"values": ['+_dictData['values'].join(", ")+']\n'
							+ '}\n';
						
						
						_animationData.datas.push(_data);
						
						_inc++;
					}
				}
			}
			SceneData.currentSceneData.animationsDataList.push(_animationData);
		}
		
		
		// Retourn le temps en secondes de la frame en cours
		private function getTimeFromFrame(_frame : int):Number
		{
			_frame -= SceneData.currentSceneData.startFrame
			var totalFrames:int = SceneData.currentSceneData.totalFrames;
			var _part = SceneData.currentSceneData.duration / (SceneData.currentSceneData.totalFrames-1);
			var time :Number = (_frame)*_part

			return time;
		}
		

		public static function convertToTwoDecimal(_num : Number):Number
		{
			return Math.round(_num * 100) / 100;
		}


		public static function getTrueRotationRadians(obj:DisplayObject):Number {
			var m:Matrix = obj.transform.matrix;

			// Extraire la rotation de base
			var radians:Number = Math.atan2(m.b, m.a);

			// Déterminer s'il y a une inversion (flip)
			var determinant:Number = m.a * m.d - m.b * m.c;

			// Si la matrice est inversée (flip), on doit corriger l'angle
			if (determinant < 0) {
				radians += Math.PI;
			}

			// Normaliser entre -π et π
			radians = (radians + Math.PI) % (2 * Math.PI);
			if (radians < 0) radians += 2 * Math.PI;
			radians -= Math.PI;

			return radians;
		}

		
		public static function getSignedScale(obj:DisplayObject):Point {
			var m:Matrix = obj.transform.matrix;

			// Magnitudes des axes X et Y
			var sx:Number = Math.sqrt(m.a * m.a + m.b * m.b);
			var sy:Number = Math.sqrt(m.c * m.c + m.d * m.d);

			// Déterminant pour détecter une inversion
			var determinant:Number = m.a * m.d - m.b * m.c;

			// Si le déterminant est négatif → inversion (flip)
			// On choisit conventionnellement de mettre le flip sur X
			if (determinant < 0) {
				sx = -sx;
			}

			return new Point(sx, sy);
		}


		
		private function getPositionVectorsFromFrame(_clip, _clipName : String, _array: Array) : Dictionary
		{
			var _detector : TransitionDetector = dictTransitionDetectors[_clipName];

			var allFrameData = _detector.frameData;
			var keyframesByProp = _detector.getKeyframes();
			var keyframesVisible : Vector.<int> = keyframesByProp['visible'];

			var framesVector1 : Vector.<int> = keyframesByProp[_array[0]];
			var framesVector2 : Vector.<int> = (_array.length > 1) ? keyframesByProp[_array[1]] : null;
			
			var positions : Array = new Array();
			var frames : Array = new Array();
			var transitions : Array = new Array();
			
			var dictData : Dictionary = new Dictionary();

			var _incFrame : int = 1;

			for (var i:int = SceneData.currentSceneData.startFrame; i <= SceneData.currentSceneData.endFrame; i++) 
			{
				var _frameXExisting =  framesVector1.indexOf(i);
				var _frameYExisting =  (framesVector2 != null) ? framesVector2.indexOf(i) : -1;
				var _currentFrameData = null;
				var _index = i-1;
				var _forceKey = false;

				_currentFrameData = allFrameData[_index];

				var _startFrame : Boolean = (i == SceneData.currentSceneData.startFrame)
				var _endFrame : Boolean = (i == SceneData.currentSceneData.endFrame)

				var _prevIndex = (_index-1);
				var _nextIndex = (_index+1);

				var _prevFrameData : FrameData
				var _nextFrameData : FrameData

				if(_prevIndex in allFrameData)
				{
					_prevFrameData  =  allFrameData[_index-1];

					if(_prevFrameData.visible == false && _currentFrameData.visible==true)
					{
						_frameXExisting = 1;
					}
					if(_startFrame == false && _endFrame == false && _prevFrameData.visible == true && _currentFrameData.visible == false)
					{
						_frameXExisting = 1;
						_currentFrameData = _prevFrameData
						_currentFrameData.visible = true
						_nextIndex = -1
					}
				}
				if(_nextIndex in allFrameData)
				{
					 _nextFrameData =  allFrameData[_index+1];

					if(_nextFrameData.visible == false && _currentFrameData.visible==true)
					{
						_frameXExisting = 1;
					}
				}


				if((_frameXExisting != -1 || _frameYExisting != -1) || _startFrame == true ||  _endFrame == true)
				{					
				
					switch(_array.toString())
					{
						case 'rotation':
							if (_currentFrameData && _currentFrameData.clip)
							{
								var godotRotation = _currentFrameData.rotation;
								positions.push(godotRotation);
							}else{
								positions.push(0);
							}
							break;
					
						case 'x,y':
							if (_currentFrameData && _currentFrameData.clip)
							{
								positions.push('Vector2('+Math.round(_currentFrameData.x)+','+Math.round(_currentFrameData.y)+')');
							}else{
								positions.push('Vector2('+0+','+0+')');
							}
							break;
					
						case 'scaleX,scaleY':
							if (_currentFrameData && _currentFrameData.clip)
							{
								positions.push('Vector2('+ convertToTwoDecimal(_currentFrameData.scaleX) +','+ convertToTwoDecimal(_currentFrameData.scaleY)+')');
							}else{
								positions.push('Vector2('+0+','+0+')');
							}
							break;

						case 'visible':
							var _visible = false;
							if(_currentFrameData == null) _visible = false;
							if(_currentFrameData != null) _visible = _currentFrameData.visible;/* && _currentFrameData.sceneName == SceneData.currentSceneData.currentScene.name*/;
							if(_currentFrameData != null  && _nextFrameData != null && _nextFrameData.visible == false && _currentFrameData.visible==true && _endFrame == false && _startFrame == false && _nextIndex == -1)
							{
								_visible = false;
							}

							positions.push(_visible);


							break;
							
					
						default:
							break;
					}


					frames.push(getTimeFromFrame(i));
					transitions.push(1);

					
				}

				_incFrame++;

			}

			
			dictData['values'] = positions;
			dictData['frames'] = frames;
			dictData['transitions'] = transitions;
			return dictData;
		}

		private function createDropZone():Sprite {
			dropZone = new Sprite();

			// Fond semi-transparent
			dropZone.graphics.beginFill(0x000000, 0.1);
			dropZone.graphics.drawRoundRect(0, 0, 500, 500, 20, 20);
			dropZone.graphics.endFill();

			// Contour pointillé bleu foncé
			drawDashedRect(dropZone, 0, 0, 500, 500, 20, 10, 5, 0x00008B, 2);

			dropZone.x = (stage.stageWidth - 500) / 2;
			dropZone.y = (stage.stageHeight - 500) / 2;

			addChild(dropZone);

			// === Titre au-dessus de la box ===
			titleText = new TextField();
			titleText.text = "Drag your SWF in the box for conversion";
			titleText.textColor = 0x333399;
			titleText.width = stage.stageWidth;
			titleText.height = 30;
			titleText.selectable = false;
			titleText.multiline = false;
			titleText.wordWrap = false;
			titleText.x = 0;
			titleText.y = dropZone.y - 40;
			titleText.autoSize = "center";

			var titleFormat:TextFormat = new TextFormat();
			titleFormat.font = "Arial";
			titleFormat.size = 20;
			titleFormat.bold = true;
			titleFormat.align = "center";

			titleText.setTextFormat(titleFormat);
			titleText.defaultTextFormat = titleFormat;

			addChild(titleText);

			return dropZone;
		}

		private function createOpenFolderButton():void {
			openFolderBtn = new Sprite();
			
			// Style du bouton
			openFolderBtn.graphics.beginFill(0x00008B); // bleu foncé
			openFolderBtn.graphics.drawRoundRect(0, 0, 200, 40, 10, 10);
			openFolderBtn.graphics.endFill();

			// Label du bouton
			openFolderLabel = new TextField();
			openFolderLabel.text = "Open Export Folder";
			openFolderLabel.textColor = 0xFFFFFF;
			openFolderLabel.width = 200;
			openFolderLabel.height = 40;
			openFolderLabel.selectable = false;
			openFolderLabel.mouseEnabled = false;
			openFolderLabel.autoSize = "center";
			openFolderLabel.x = (200 - openFolderLabel.textWidth) / 2 - 2;
			openFolderLabel.y = (40 - openFolderLabel.textHeight) / 2 - 2;

			var titleFormat:TextFormat = new TextFormat();
			titleFormat.font = "Arial";
			titleFormat.size = 14;
			titleFormat.bold = true;
			titleFormat.align = "center";

			openFolderLabel.setTextFormat(titleFormat);
			openFolderLabel.defaultTextFormat = titleFormat;

			openFolderBtn.addChild(openFolderLabel);

			// Position du bouton sous la dropBox
			openFolderBtn.x = (stage.stageWidth - 200) / 2;
			openFolderBtn.y = dropZone.y + dropZone.height + 20;

			addChild(openFolderBtn);

			// Interaction
			openFolderBtn.buttonMode = true;
			openFolderBtn.mouseChildren = false;
			openFolderBtn.addEventListener(MouseEvent.CLICK, onOpenFolderClick);
		}

		private function onOpenFolderClick(e:MouseEvent):void {
			if (outputFolder && outputFolder.exists) {
				outputFolder.openWithDefaultApplication();
			} else {
				trace("⚠ Aucun dossier d'export trouvé");
			}
		}

		private function createMarginInputs():void {
			marginContainer = new Sprite();
			
			var labelFormat:TextFormat = new TextFormat("Arial", 14, 0xFFFFFF);
			labelFormat.bold = true;

			var inputFormat:TextFormat = new TextFormat("Arial", 14, 0xFFFFFF);

			// Texture Margin Label
			var marginLabel:TextField = new TextField();
			marginLabel.text = "Texture Margin:";
			marginLabel.setTextFormat(labelFormat);
			marginLabel.autoSize = "left";
			marginLabel.x = 10;
			marginLabel.y = 12;
			marginContainer.addChild(marginLabel);
			
			// Margin X Input
			marginXInput = new TextField();
			marginXInput.type = "input";
			marginXInput.border = true;
			marginXInput.borderColor = 0xAAAAAA;
			marginXInput.background = true;
			marginXInput.backgroundColor = 0x333333;
			marginXInput.width = 40;
			marginXInput.height = 20;
			marginXInput.text = "0";
			marginXInput.restrict = "0-9";
			marginXInput.defaultTextFormat = inputFormat;
			marginXInput.setTextFormat(inputFormat);
			marginXInput.x = marginLabel.x + marginLabel.width + 5;
			marginXInput.y = 10;
			marginContainer.addChild(marginXInput);
			
			// Margin Y Input
			marginYInput = new TextField();
			marginYInput.type = "input";
			marginYInput.border = true;
			marginYInput.borderColor = 0xAAAAAA;
			marginYInput.background = true;
			marginYInput.backgroundColor = 0x333333;
			marginYInput.width = 40;
			marginYInput.height = 20;
			marginYInput.text = "0";
			marginYInput.restrict = "0-9";
			marginYInput.defaultTextFormat = inputFormat;
			marginYInput.setTextFormat(inputFormat);
			marginYInput.x = marginXInput.x + marginXInput.width + 5;
			marginYInput.y = 10;
			marginContainer.addChild(marginYInput);

			// --- Atlas Checkbox ---
			var atlasLabel:TextField = new TextField();
			atlasLabel.text = "Single Texture";
			atlasLabel.setTextFormat(labelFormat);
			atlasLabel.autoSize = "left";
			atlasLabel.x = marginYInput.x + marginYInput.width + 20;
			atlasLabel.y = 12;
			marginContainer.addChild(atlasLabel);

			atlasEnabledCheckbox = new Sprite();
			atlasEnabledCheckbox.graphics.lineStyle(1, 0xFFFFFF);
			atlasEnabledCheckbox.graphics.beginFill(0x333333);
			atlasEnabledCheckbox.graphics.drawRoundRect(0, 0, 16, 16, 4, 4);
			atlasEnabledCheckbox.graphics.endFill();
			atlasEnabledCheckbox.x = atlasLabel.x + atlasLabel.width + 5;
			atlasEnabledCheckbox.y = 12;
			atlasEnabledCheckbox.buttonMode = true;
			atlasEnabledCheckbox.addEventListener(MouseEvent.CLICK, toggleAtlas);
			marginContainer.addChild(atlasEnabledCheckbox);

			var containerWidth:Number = atlasEnabledCheckbox.x + atlasEnabledCheckbox.width + 10;

			marginContainer.graphics.beginFill(0x00008B); // Dark blue
			marginContainer.graphics.drawRoundRect(0, 0, containerWidth, 40, 10, 10);
			marginContainer.graphics.endFill();
			
			var totalWidth:Number = containerWidth + openFolderBtn.width + 10;
			var startX:Number = (stage.stageWidth - totalWidth) / 2;
			
			marginContainer.x = startX;
			marginContainer.y = openFolderBtn.y;
			
			openFolderBtn.x = startX + containerWidth + 10;
			
			addChild(marginContainer);
		}

		private function toggleAtlas(e:MouseEvent):void {
			atlasEnabled = !atlasEnabled;
			
			atlasEnabledCheckbox.graphics.clear();
			atlasEnabledCheckbox.graphics.lineStyle(1, 0xFFFFFF);
			atlasEnabledCheckbox.graphics.beginFill(0x333333);
			atlasEnabledCheckbox.graphics.drawRoundRect(0, 0, 16, 16, 4, 4);
			atlasEnabledCheckbox.graphics.endFill();
			
			if (atlasEnabled) {
				atlasEnabledCheckbox.graphics.lineStyle(2, 0xFFFFFF);
				atlasEnabledCheckbox.graphics.moveTo(4, 8);
				atlasEnabledCheckbox.graphics.lineTo(8, 12);
				atlasEnabledCheckbox.graphics.lineTo(12, 4);
			}
		}

		private function drawDashedRect(sprite:Sprite, x:Number, y:Number, w:Number, h:Number, radius:Number, dashLength:Number, gapLength:Number, color:uint, thickness:Number):void {
			var g:Graphics = sprite.graphics;
			g.lineStyle(thickness, color);

			// Simple approximation : 4 côtés avec pointillés
			drawDashedLine(g, x + radius, y, x + w - radius, y, dashLength, gapLength); // top
			drawDashedLine(g, x + w, y + radius, x + w, y + h - radius, dashLength, gapLength); // right
			drawDashedLine(g, x + w - radius, y + h, x + radius, y + h, dashLength, gapLength); // bottom
			drawDashedLine(g, x, y + h - radius, x, y + radius, dashLength, gapLength); // left
		}

		private function drawDashedLine(g:Graphics, x1:Number, y1:Number, x2:Number, y2:Number, dashLength:Number, gapLength:Number):void {
			var dx:Number = x2 - x1;
			var dy:Number = y2 - y1;
			var dist:Number = Math.sqrt(dx*dx + dy*dy);
			var angle:Number = Math.atan2(dy, dx);

			var drawn:Number = 0;
			while (drawn < dist) {
				var segment:Number = Math.min(dashLength, dist - drawn);
				g.moveTo(x1 + Math.cos(angle) * drawn, y1 + Math.sin(angle) * drawn);
				drawn += segment;
				g.lineTo(x1 + Math.cos(angle) * drawn, y1 + Math.sin(angle) * drawn);
				drawn += gapLength;
			}
		}
	}
}
import com.adobe.images.PNGEncoder;

import flash.display.*;
import flash.events.*;
import flash.filesystem.*;
import flash.geom.*;
import flash.net.URLRequest;
import flash.geom.Matrix;
import flash.utils.*;

// === CLASSES INTERNES ===

internal class NodeData 
{
	public static var allNodesData = new Array();
	public var clipName : String;
	public var nodeList : Array = new Array();

	public static function getExistingNodeData(_name : String) : NodeData
	{
		var _nodeDataToFind : NodeData = null;

		for each(var _nodeData : NodeData in allNodesData)
		{
			if(_name == _nodeData.clipName)
			{
				_nodeDataToFind = _nodeData;
				break;
			}
		}
		return _nodeDataToFind;
	}

}

internal class SceneData 
{
	public static var allSceneData : Array = new Array();
	public static var currentSceneData : SceneData;
	public static var frameCounter : int = 0;

	public var currentScene : Scene;
	public var id : String;
	public var nameScene : String;
	public var totalFrames : int;
	public var startFrame : int;
	public var endFrame : int;
	public var animationsDataList : Array = new Array();
	public var currentFrameRate : Number;
	public var duration : Number;

	public function init(_scene : Scene, _currentFrameRate : Number)
	{
		currentScene = _scene;
		currentFrameRate = _currentFrameRate;
		nameScene = _scene.name;
		totalFrames = _scene.numFrames;
		startFrame = frameCounter + 1;
		endFrame = frameCounter + _scene.numFrames;
		frameCounter +=  _scene.numFrames;
		duration = totalFrames / currentFrameRate ;
		
	}
}

internal class AnimationData 
{
	public var id : String;
	public var name : String;
	public var datas : Array = new Array();
}

internal class FrameData {
	public var frameNumber:int;
	public var x:Number;
	public var y:Number;
	public var clip : *;
	public var scaleX:Number;
	public var scaleY:Number;
	public var rotation:Number;
	public var alpha:Number;
	public var visible:Boolean;
	public var exists:Boolean;
	public var width : Number;
	public var height : Number;
	public var sceneName :String; 
	public var id : String;
	
	public function FrameData(frame:int, clip:*,_scene : Scene) 
	{
		this.id = 'ID_' + frame;
		this.clip = clip;
		
		this.sceneName = _scene != null ?_scene.name : null;	
		this.frameNumber = frame;
		this.exists = (clip != null && clip.parent != null);
		
		if (exists) 
		{
			var _datas = {
				x: clip.x,
				y: clip.y,
				width : clip.width,
				height : clip.height,
				rotation : GodotExport.getTrueRotationRadians(clip),
				scaleX : GodotExport.getSignedScale(clip).x,
				scaleY : GodotExport.getSignedScale(clip).y
			}
		

			if(clip.parent != null && (clip is Shape))
			{
				var _bounds : Rectangle = clip.getBounds(clip.parent);

				_datas.x = _bounds.x + (_bounds.width/2);
				_datas.y = _bounds.y + (_bounds.height/2);
				_datas.scaleX = Math.abs(_datas.scaleX);
				_datas.scaleY = Math.abs(_datas.scaleY);
			}

			this.x = _datas.x;
			this.y = _datas.y;
			this.scaleX = _datas.scaleX;
			this.scaleY = _datas.scaleY;
			this.rotation = _datas.rotation;
			this.alpha = clip.alpha;
			this.visible = clip.visible;
			this.width = _datas.width;
			this.height = _datas.height;
		} else {
			this.visible = false;
			this.exists = false;
		}
	}

}

internal class TransitionDetector {
	private var timeline:MovieClip;
	private var targetClipName:String;
	public var frameData:Vector.<FrameData>;
	
	public function TransitionDetector(timeline:MovieClip, clipName:String) {
		this.timeline = timeline;
		this.targetClipName = clipName;
		this.frameData = new Vector.<FrameData>();

		for(var i:int = 0; i < timeline.totalFrames; i++)
		{
			var _frameData:FrameData = new FrameData(i, null, null);
			this.frameData.push(_frameData);
		}

	}


	public function addFrame(i : int, targetClip : *, _scene : Scene)
	{
		var _frameData : FrameData = new FrameData(i, targetClip,_scene);
		frameData[i] = _frameData
		//frameData.push(data);
	}

	
	public function findClipByName(container:DisplayObjectContainer, name:String):MovieClip {
		for (var i:int = 0; i < container.numChildren; i++) {
			var child:DisplayObject = container.getChildAt(i);
			if (child.name == name && child is MovieClip) {
				return child as MovieClip;
			}
			if (child is DisplayObjectContainer) {
				var found:MovieClip = findClipByName(child as DisplayObjectContainer, name);
				if (found) return found;
			}
		}
		return null;
	}
	
	// Fonction utilitaire pour obtenir le signe
	private function sign(v:int):int {
		if (v > 0) return 1;
		if (v < 0) return -1;
		return 0;
	}
	
	public function getKeyframes():Dictionary 
	{
		var props:Array = ["x","y","scaleX","scaleY","rotation","alpha","visible","exists","width","height"];
		var result:Dictionary = new Dictionary();

		if (frameData.length == 0) return result;
		
		for each (var p:String in props) {
			var keys:Vector.<int> = new Vector.<int>();
			keys.push(frameData[0].frameNumber);
			
			var inTransition:Boolean = false;
			var lastDiffValue:int = 0;
			
			for (var i:int = 1; i < frameData.length; i++) {
				var cur:* = frameData[i][p];
				var prev:* = frameData[i-1][p];

				if (p == "visible" || p == "exists") 
				{
					if (cur != prev) keys.push(frameData[i].frameNumber);
					continue;
				}

				var _forceFrame = false;
				var curVisible :* = frameData[i]['visible'];
				var prevVisible :* = frameData[i-1]['visible'];
				if (curVisible != prevVisible) _forceFrame = true;

				var diff:int ;


				if(p == 'scaleX' || p == 'scaleY')
				{
					diff = Math.round((cur -prev)*100) ;
				}
				else if(p == 'rotation')
				{
					var _cur = GodotExport.convertToTwoDecimal(cur);
					var _prev = GodotExport.convertToTwoDecimal(prev);
					diff = Math.floor((_cur-_prev)*100) ;
				}
				else
				{
					diff = Math.floor(cur -prev) ;
				}
				
				if (!inTransition) {
					if (diff != 0) {
						inTransition = true;
						lastDiffValue = diff;
						keys.push(frameData[i-1].frameNumber); // début
					}
				} else {
					if (diff != 0) {
						// changement de signe OU écart > 1
						if (sign(diff) != sign(lastDiffValue) || Math.abs(diff - lastDiffValue) > 1) {
							keys.push(frameData[i-1].frameNumber); // fin de transition précédente
							lastDiffValue = diff;
							keys.push(frameData[i].frameNumber);   // redémarrage
						} else {
							lastDiffValue = diff; // transition continue
						}
					} else {
						// fin si diff = 0
						keys.push(frameData[i-1].frameNumber);
						inTransition = false;
						lastDiffValue = 0;
					}
				}
			}
			
			if (inTransition) {
				keys.push(frameData[frameData.length-1].frameNumber);
			}
			
			// unique + tri
			var unique:Vector.<int> = new Vector.<int>();
			var seen:Object = {};
			for each (var f:int in keys) {
				if (!seen[f]) {
					unique.push(f);
					seen[f] = true;
				}
			}
			unique.sort(Array.NUMERIC);
			result[p] = unique;
		}
		return result;
	}
}

internal class GodotExporter {
	public static function exportToGodot(frameData:Vector.<FrameData>, keyframesByProp:Dictionary):String {
		var output:String = '';
		
		for (var prop:String in keyframesByProp) {
			var frames:Vector.<int> = keyframesByProp[prop];
			output += '\t"' + prop + '": [';
			
			var valueList:Array = [];
			for each (var f:int in frames) {
				var val:* = frameData[f - 1][prop];
				valueList.push(f + " => " + val);
			}
			trace("Property: " + prop + " | Frames & Values: " + valueList.join(", "));
			
			output += frames.join(", ");

		}
		

		return output;
	}
}

