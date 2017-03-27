## Synopsis

This project modifies the Adalight protocol to use [FastLED](https://github.com/FastLED/FastLED) ([fastled.io](http://fastled.io)). This expands Adalight to, in theory, work with *[any supported FastLED strip](https://github.com/FastLED/FastLED/wiki/Chipset-reference)* including WS2812B (aka Adafruit NeoPixels).

In addition to ambilight setups, the protocol can be used to stream *any* color data from a computer to supported LED strips.

## Configuration

Open the LEDstream_FastLED file in the Arduino IDE and customize the settings at the top for your setup. You will need to change:

- Number of LEDs
- LED data pin
- LED type

Additional settings allow for adjusting:

- Max brightness
- LED color order
- Serial speed
- Serial timeout length

There are also optional settings to clear the LEDs on reset, configure a dedicated ground pin, and to put the Arduino into a "calibration" mode, where all LED colors match the first LED.

Upload to your Arduino and use a corresponding PC application to stream color data. You can get the Processing files from the [main Adalight repository](https://github.com/adafruit/Adalight), though I would recommend using [Patrick Siegler's](https://github.com/psieg/) fork of Lightpacks's Prismatik, which you can find [here](https://github.com/psieg/Lightpack).

## Issues and LED-types

I've only tested the code with the WS2812B strips I have on hand, but so far it performs flawlessly. If you find an issue with the code or can confirm that it works with another chipset, please let me know!

## Credits and Contributions

Thanks to Adafruit for the initial code and the Adalight protocol. The base for the original FastLED modifications is [this gist](https://gist.github.com/jamesabruce/09d79a56d270ed37870c) by [James Bruce](https://github.com/jamesabruce). Thanks James!

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
