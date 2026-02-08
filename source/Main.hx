class Main extends openfl.display.Sprite
{
    public function new()
    {
        super();
        addChild(new flixel.FlxGame(800, 600, ConverterState, 360, 360, true));
    }
}