package;

import flixel.FlxG;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import haxe.Json;
import haxe.Serializer;
import haxe.Unserializer;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import openfl.events.Event;
import openfl.net.FileFilter;
import openfl.net.FileReference;
import openfl.utils.ByteArray;

typedef PatchPair =
{
	var orig:String;
	var n:String;
}

class ConverterState extends FlxState
{
	private var titleText:FlxText;
	private var loadSolBtn:FlxButton;
	private var exportJsonBtn:FlxButton;
	private var importJsonBtn:FlxButton;
	private var exportSolBtn:FlxButton;
	private var infoText:FlxText;
	private var dataPreview:FlxText;

	private var currentData:Dynamic;
	private var currentFileName:String;
	private var currentSerialized:String;
	private var annotatedExport:Dynamic;

	override public function create():Void
	{
		super.create();

		FlxG.cameras.bgColor = FlxColor.fromRGB(45, 45, 45);

		titleText = new FlxText(0, 20, FlxG.width, "FlxSave SOL → JSON Converter");
		titleText.setFormat(null, 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(titleText);

		loadSolBtn = createButton("Load SOL File", 100, loadSOL);
		exportJsonBtn = createButton("Export to JSON", 170, exportJSON);
		importJsonBtn = createButton("Import from JSON", 240, importJSON);
		exportSolBtn = createButton("Save SOL File", 310, exportSOL);

		exportJsonBtn.active = false;
		exportSolBtn.active = false;

		infoText = new FlxText(20, 0, FlxG.width - 40, "No SOL file loaded");
		infoText.setFormat(null, 16, 0xFFCCCCCC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(infoText);

		dataPreview = new FlxText(20, 320, FlxG.width - 40, "");
		dataPreview.setFormat(null, 12, 0xFF90EE90, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		dataPreview.fieldWidth = FlxG.width - 40;
		add(dataPreview);
	}

	function createButton(label:String, y:Int, onClick:Void->Void):FlxButton
	{
		var btn = new FlxButton(FlxG.width / 2 - 100, y, label, onClick);
		btn.scale.set(1.5, 1.5);
		btn.updateHitbox();
		add(btn);
		return btn;
	}

	function loadSOL():Void
	{
		var fileRef = new FileReference();
		fileRef.addEventListener(Event.SELECT, function(_:Event) fileRef.load());
		fileRef.addEventListener(Event.COMPLETE, function(_:Event) onSolLoaded(fileRef));
		fileRef.browse([new FileFilter("FlxSave SOL Files", "*.sol")]);
	}

	function onSolLoaded(fileRef:FileReference):Void
	{
		// Read data from openfl ByteArray -> haxe.Bytes
		final openflBytes:ByteArray = fileRef.data;
		openflBytes.position = 0;
		final bytes = Bytes.alloc(openflBytes.length);
		for (i in 0...openflBytes.length)
			bytes.set(i, openflBytes.readByte());

		final input = new BytesInput(bytes);
		currentSerialized = input.readAll().toString();

		final unser = new Unserializer(currentSerialized);
		currentData = unser.unserialize();

		currentFileName = fileRef.name;
		annotatedExport = annotateForJson(currentData);

		infoText.text = 'Loaded: ${fileRef.name} Size: ${bytes.length} bytes — Unserialized OK.';
		exportJsonBtn.active = true;
		exportSolBtn.active = true;

		updateDataPreview();
	}

	function exportJSON():Void
	{
		if (annotatedExport == null)
		{
			infoText.text = "No data to export";
			return;
		}

		var out = {
			__meta: {
				originalSerialized: currentSerialized,
				sourceFileName: currentFileName
			},
			data: annotatedExport
		};
		var jsonString = Json.stringify(out, null, "  ");
		var fileRef = new FileReference();
		var baseName = getFileNameWithoutExtension(currentFileName == null ? "save" : currentFileName);
		fileRef.save(jsonString, baseName + "_annotated.json");
		infoText.text = "Annotated JSON exported successfully.";
	}

	function importJSON():Void
	{
		var fileRef = new FileReference();
		fileRef.addEventListener(Event.SELECT, (_:Event) -> fileRef.load());
		fileRef.addEventListener(Event.COMPLETE, (_:Event) -> onJsonImported(fileRef));
		fileRef.browse([new FileFilter("JSON Files", "*.json")]);
	}

	function onJsonImported(fileRef:FileReference):Void
	{
		final jsonString = fileRef.data.readUTFBytes(fileRef.data.bytesAvailable);
		final parsed = Json.parse(jsonString);

		if (Reflect.hasField(parsed, "__meta") && Reflect.hasField(parsed, "data"))
		{
			final meta = parsed.__meta;
			final annotated = parsed.data;

			final rebuilt = buildFromAnnotated(annotated);
			currentData = rebuilt;
			currentSerialized = meta.originalSerialized != null ? meta.originalSerialized : null;
			currentFileName = getFileNameWithoutExtension(fileRef.name) + ".sol";
			annotatedExport = annotated;

			infoText.text = 'Loaded annotated JSON: ${fileRef.name} — Converted to SOL structure.';
		}
		else
		{
			currentData = Json.parse(jsonString);
			currentFileName = getFileNameWithoutExtension(fileRef.name) + ".sol";
			annotatedExport = annotateForJson(currentData);
			infoText.text = 'Loaded plain JSON and converted to SOL structure (best-effort).';
		}

		exportJsonBtn.active = true;
		exportSolBtn.active = true;
		updateDataPreview();
	}

	function exportSOL():Void
	{
		if (currentData == null)
		{
			infoText.text = "No data to save";
			return;
		}

		// Try minimal patching when original serialized string available
		if (currentSerialized != null && annotatedExport != null)
		{
			var patched:String = tryPatchSerialized(currentSerialized, annotatedExport);
			if (patched != null)
			{
				saveStringAsSol(patched, currentFileName);
				infoText.text = "SOL file saved by patching original serialized string (minimal).";
				return;
			}
		}

		// Full re-serialize
		var serializer = new Serializer();
		serializer.useCache = true;
		serializer.useEnumIndex = true;
		serializer.serialize(currentData);
		var serializedString = serializer.toString();
		saveStringAsSol(serializedString, currentFileName);
		infoText.text = "SOL file saved successfully.";
	}

	function saveStringAsSol(str:String, fileName:String):Void
	{
		final output = new BytesOutput();
		output.writeString(str);
		final bytes = output.getBytes();

		final byteArray = new ByteArray();
		for (i in 0...bytes.length)
			byteArray.writeByte(bytes.get(i));

		final fileRef = new FileReference();
		fileRef.save(byteArray, fileName == null ? "save.sol" : fileName);
	}

	function tryPatchSerialized(original:String, annotated:Dynamic):Null<String>
	{
		if (original == null || annotated == null)
			return null;

		final pairs:Array<PatchPair> = [];
		collectLeafSerializations(annotated, pairs);

		if (pairs.length == 0)
			return null;

		var usedOrig:Map<String, Bool> = new Map();
		for (p in pairs)
		{
			final orig:String = p.orig;
			if (usedOrig.exists(orig))
				return null;
			final cnt:Int = countOccurrences(original, orig);
			if (cnt != 1)
				return null;
			usedOrig.set(orig, true);
		}

		var patched:String = original;
		for (p in pairs)
			patched = patched.split(p.orig).join(p.n);
		return patched;
	}

	private function collectLeafSerializations(node:Dynamic, out:Array<{orig:String, n:String}>):Void
	{
		if (node == null)
			return;

		if (Reflect.hasField(node, "__typeHint") && Reflect.hasField(node, "value") && Reflect.hasField(node, "__serialized"))
		{
			var orig:String = node.__serialized;
			var rebuilt = buildFromAnnotated(node);
			var newS:String = serializeValue(rebuilt);
			if (orig != null && orig != newS)
				out.push({orig: orig, n: newS});
			return;
		}

		if (Std.isOfType(node, Array))
		{
			var len:Int = node == null ? 0 : node.length;
			for (i in 0...len)
				collectLeafSerializations(node[i], out);
			return;
		}

		if (Reflect.isObject(node))
		{
			var fields:Array<String> = Reflect.fields(node);
			for (f in fields)
				collectLeafSerializations(Reflect.field(node, f), out);
		}
	}

	private function countOccurrences(hay:String, needle:String):Int
	{
		if (hay == null || needle == null || needle.length == 0)
			return 0;
		var pos = 0;
		var cnt = 0;
		while (true)
		{
			var idx = hay.indexOf(needle, pos);
			if (idx == -1)
				break;
			cnt++;
			pos = idx + needle.length;
		}
		return cnt;
	}

	private function serializeValue(v:Dynamic):String
	{
		var s = new Serializer();
		s.useCache = true;
		s.useEnumIndex = true;
		s.serialize(v);
		return s.toString();
	}

	private function tryUnserialize(serialized:String):Dynamic
	{
		var u = new Unserializer(serialized);
		return u.unserialize();
	}

	private function getTypeName(v:Dynamic):String
	{
		if (v == null)
			return "Null";
		if (Std.isOfType(v, Bool))
			return "Bool";
		if (Std.isOfType(v, Int))
			return "Int";
		if (Std.isOfType(v, Float))
			return "Float";
		if (Std.isOfType(v, String))
			return "String";
		if (Std.isOfType(v, Array))
			return "Array";
		if (Std.isOfType(v, StringMap))
			return "StringMap";
		if (Reflect.isObject(v))
			return "Object";
		return "Unknown";
	}

	private function annotateForJson(v:Dynamic):Dynamic
	{
		var s = new Serializer();
		s.useCache = true;
		s.useEnumIndex = true;
		s.serialize(v);
		var ser = s.toString();

		// Primitives
		if (v == null || Std.isOfType(v, Bool) || Std.isOfType(v, Int) || Std.isOfType(v, Float) || Std.isOfType(v, String))
		{
			return {
				__typeHint: getTypeName(v),
				__serialized: ser,
				value: v
			};
		}

		if (Std.isOfType(v, StringMap))
		{
			var sm:StringMap<Dynamic> = cast(v, StringMap<Dynamic>);
			var map:Dynamic = {};
			for (k in sm.keys())
				Reflect.setField(map, k, annotateForJson(sm.get(k)));
			return {
				__typeHint: "StringMap",
				__origType: "StringMap",
				__serialized: ser,
				value: map
			};
		}

		if (Std.isOfType(v, Array))
		{
			var arr:Array<Dynamic> = cast(v, Array<Dynamic>);
			var out:Array<Dynamic> = [];
			for (i in 0...arr.length)
				out.push(annotateForJson(arr[i]));
			return {__typeHint: "Array", __serialized: ser, value: out};
		}

		if (Reflect.isObject(v))
		{
			var fields:Array<String> = Reflect.fields(v);
			var map2:Dynamic = {};
			for (f in fields)
			{
				var val = Reflect.field(v, f);
				Reflect.setField(map2, f, annotateForJson(val));
			}
			var origType:String = null;
			try
			{
				origType = Type.getClassName(Type.getClass(v));
			}
			catch (e:Dynamic)
			{
				origType = null;
			}
			if (origType != null)
			{
				return {
					__typeHint: "Object",
					__origType: origType,
					__serialized: ser,
					value: map2
				};
			}
			return {__typeHint: "Object", __serialized: ser, value: map2};
		}

		return {__typeHint: "Unknown", __serialized: ser, value: Std.string(v)};
	}

	private function buildFromAnnotated(node:Dynamic):Dynamic
	{
		if (node == null)
			return null;

		if (Reflect.hasField(node, "__typeHint") && Reflect.hasField(node, "value"))
		{
			var hint:String = node.__typeHint;
			var val:Dynamic = node.value;
			switch (hint)
			{
				case "Null":
					return null;
				case "Bool":
					return (val == true);
				case "Int":
					return Std.int(val);
				case "Float":
					return (val + 0.0);
				case "String":
					return Std.string(val);
				case "Array":
					var arrOut:Array<Dynamic> = [];
					if (val != null)
						for (i in 0...val.length)
							arrOut.push(buildFromAnnotated(val[i]));
					return arrOut;
				case "StringMap":
					var sm:StringMap<Dynamic> = new StringMap();
					if (val != null)
					{
						for (fld in Reflect.fields(val))
							sm.set(fld, buildFromAnnotated(Reflect.field(val, fld)));
					}
					return sm;
				case "Object":
					var o:Dynamic = {};
					if (val != null)
					{
						for (f in Reflect.fields(val))
							Reflect.setField(o, f, buildFromAnnotated(Reflect.field(val, f)));
					}
					return o;
				default:
					if (Reflect.hasField(node, "__serialized"))
					{
						var maybe = tryUnserialize(node.__serialized);
						if (maybe != null)
							return maybe;
					}
					return val;
			}
		}

		if (Std.isOfType(node, Array))
		{
			var outA:Array<Dynamic> = [];
			if (node != null)
				for (i2 in 0...node.length)
					outA.push(buildFromAnnotated(node[i2]));
			return outA;
		}
		if (Reflect.isObject(node))
		{
			var outO:Dynamic = {};
			for (f2 in Reflect.fields(node))
				Reflect.setField(outO, f2, buildFromAnnotated(Reflect.field(node, f2)));
			return outO;
		}
		return node;
	}

	private function updateDataPreview():Void
	{
		if (annotatedExport == null)
		{
			dataPreview.text = "";
			return;
		}

		final preview = new StringBuf();
		preview.add("Annotated Data Preview:\n");
		previewAnnotated(annotatedExport, preview, "", 0, 4);
		dataPreview.text = preview.toString();
	}

	private function previewAnnotated(node:Dynamic, buf:StringBuf, indent:String, depth:Int, maxDepth:Int):Void
	{
		if (depth > maxDepth)
		{
			buf.add(indent + "...\n");
			return;
		}
		if (node == null)
		{
			buf.add(indent + "null\n");
			return;
		}

		if (Reflect.hasField(node, "__typeHint") && Reflect.hasField(node, "value"))
		{
			var hint:String = node.__typeHint;
			var val:Dynamic = node.value;
			buf.add(indent + "(" + hint + ") ");
			if (hint == "Array")
			{
				buf.add("Array[" + (val == null ? 0 : val.length) + "]\n");
				if (val != null)
				{
					var limit = (val.length < 6) ? val.length : 6;
					for (i in 0...limit)
						previewAnnotated(val[i], buf, indent + "  ", depth + 1, maxDepth);
				}
			}
			else if (hint == "StringMap")
			{
				var keys:Array<String> = Reflect.fields(val);
				buf.add("StringMap{" + (keys == null ? 0 : keys.length) + "}\n");
				if (keys != null)
					for (kk in keys)
					{
						buf.add(indent + "  " + kk + ":\n");
						previewAnnotated(Reflect.field(val, kk), buf, indent + "    ", depth + 1, maxDepth);
					}
			}
			else if (hint == "Object")
			{
				var fields:Array<String> = Reflect.fields(val);
				buf.add("Object{" + (fields == null ? 0 : fields.length) + "}\n");
				if (fields != null)
					for (f in fields)
					{
						buf.add(indent + "  " + f + ":\n");
						previewAnnotated(Reflect.field(val, f), buf, indent + "    ", depth + 1, maxDepth);
					}
			}
			else
				buf.add(Std.string(val) + "\n");

			return;
		}

		if (Std.isOfType(node, Array))
		{
			buf.add(indent + "Array[...]\n");
			return;
		}
		if (Reflect.isObject(node))
		{
			buf.add(indent + "Object{...}\n");
			return;
		}
		buf.add(indent + Std.string(node) + "\n");
	}

	function getFileNameWithoutExtension(fileName:String):String
	{
		var dotIndex = fileName.lastIndexOf(".");
		return if (dotIndex == -1) fileName else fileName.substring(0, dotIndex);
	}
}
