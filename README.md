## Synopsis

This is the Adalight library with the Arduino code modified to use [FastLED](https://github.com/FastLED/FastLED) ([fastled.io](http://fastled.io)). This expands Adalight to, in theory, work with [any supported FastLED strip](https://github.com/FastLED/FastLED/wiki/Chipset-reference) including WS2812B (aka Adafruit NeoPixels).

In addition to ambilight setups, the protocol can be used to stream *any* color data from a computer to supported LED strips (data rate limited by serial throughput).


## Configuration

Open the LEDstream_FastLED file in the Arduino IDE and edit the setting definitions at the top for your setup. These include:

- Number of LEDs
- LED data pin
- Max brightness
- LED type
- LED color order
- Serial speed
- Serial timeout length

There are also optional settings to configure a dedicated ground pin and to put the Arduino into a "calibration" mode, where all LED colors match the first LED.

Upload to your Arduino and use a corresponding PC application to stream color data. The Processing files are included, though I would recommend using Patrick Siegler's (@psieg) fork of Lightpacks's Prismatik, which you can find [here](https://github.com/psieg/Lightpack).

## Issues and LED-types

I've only tested the code with the WS2812B strips I have on hand, but so far it performs flawlessly. If you find an issue with the code or can confirm that it works with another chipset, please let me know!

## Credits and Contributions

The base for the original FastLED modifications is [this gist](https://gist.github.com/jamesabruce/09d79a56d270ed37870c) by [James Bruce](https://github.com/jamesabruce). Thanks James!

Pull requests to improve this software are always welcome!

## License

Adalight is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as
published by the Free Software Foundation, either version 3 of
the License, or (at your option) any later version.

Adalight is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with Adalight.  If not, see <http://www.gnu.org/licenses/>.
