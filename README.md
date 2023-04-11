# QOIF-D
Implementation of the "[Quite OK Image format](https://qoiformat.org/)" in D Language. The implementation is based off the
[QOIF specification](https://qoiformat.org/qoi-specification.pdf) and does not rely on the reference en-/decoder.

The goal of this library is to add a simple and easy-to-use way for encoding or decoding QOIF images that could be used
in D


## Usage
Decoding is done using the `encode` function:
```d
auto originalImage = cast(ubyte[]) read("test_data/kodim10.qoi");
QoifImage decoded = decode(originalImage);
```

Encoding is done in a similar fashion:
```d
auto imageData = [Pixel(255, 0, 0), Pixel(0, 255, 0), Pixel(0, 0, 255), Pixel(255, 255, 255)];
auto encodedImage = encode(image, 2, 2);
```