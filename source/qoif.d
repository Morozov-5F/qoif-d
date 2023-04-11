/**
 * Copyright (c) 2023, Evgenii Morozov
 * All rights reserved.
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */
module qoif;

private
{
    import std.bitmanip : bigEndianToNative, nativeToBigEndian, bitfields;
    import core.simd;

    // Private helper definitions
    struct QoifHeader
    {
    align(1):
        char[4] magic;
        ubyte[4] rawWidth;
        ubyte[4] rawHeight;
        QoifChannels channels;
        QoifColorSpace colorspace;

        uint width() @safe
        {
            return bigEndianToNative!uint(rawWidth);
        }

        uint height() @safe
        {
            return bigEndianToNative!uint(rawHeight);
        }

        this(uint width, uint height, QoifChannels channels = QoifChannels.RGB,
            QoifColorSpace colorspace = QoifColorSpace.sRGB) @safe
        {
            assert(colorspace == QoifColorSpace.sRGB);

            magic = "qoif";
            rawWidth = nativeToBigEndian(width);
            rawHeight = nativeToBigEndian(height);
            this.channels = channels;
            this.colorspace = colorspace;
        }
    }

    unittest
    {
        // Sanity checks for qoif header structure - make sure it produces the proper output
    }

    enum QOIFTag8Bit : ubyte
    {
        QOI_OP_RGB = 0b11111110,
        QOI_OP_RGBA = 0b11111111,
    }

    enum QoifTag2Bit : ubyte
    {
        QOI_OP_INDEX = 0b00,
        QOI_OP_DIFF = 0b01,
        QOI_OP_LUMA = 0b10,
        QOI_OP_RUN = 0b11,
    }

    struct QoifEntryRGB
    {
    align(1):
        const QOIFTag8Bit tag = QOIFTag8Bit.QOI_OP_RGB;
        ubyte red, green, blue;

        this(ubyte r, ubyte g, ubyte b) @safe
        {
            red = r;
            green = g;
            blue = b;
        }

        @safe unittest
        {
            auto testEntry = QoifEntryRGB(52, 34, 102);
            assert(toByteArray(testEntry) == [0xFE, 52, 34, 102]);
        }

        this(const ref QoifPixel pixel) @safe
        {
            this(pixel.r, pixel.g, pixel.b);
        }
    }

    struct QoifEntryRGBA
    {
    align(1):
        const QOIFTag8Bit tag = QOIFTag8Bit.QOI_OP_RGBA;
        ubyte red, green, blue, alpha;

        this(ubyte r, ubyte g, ubyte b, ubyte a) @safe
        {
            red = r;
            green = g;
            blue = b;
            alpha = a;
        }

        @safe unittest
        {
            auto testEntry = QoifEntryRGBA(52, 34, 102, 100);
            assert(toByteArray(testEntry) == [0xFF, 52, 34, 102, 100]);
        }

        this(const ref QoifPixel pixel) @safe
        {
            this(pixel.r, pixel.g, pixel.b, pixel.a);
        }
    }

    struct QoifEntryIndex
    {
        mixin(bitfields!(ubyte, "index", 6, QoifTag2Bit, "type", 2,));

        this(size_t index) @safe
        {
            assert(index < 64);

            type = QoifTag2Bit.QOI_OP_INDEX;
            this.index = cast(ubyte) index;
        }

        @safe unittest
        {
            auto testEntry = QoifEntryIndex(62);
            assert(toByteArray(testEntry) == [0b00111110]);
        }
    }

    struct QoifEntryDiff
    {
        mixin(bitfields!(ubyte, "db", 2, ubyte, "dg", 2, ubyte, "dr", 2, QoifTag2Bit, "type", 2,));

        this(byte dr, byte dg, byte db) @safe
        {
            type = QoifTag2Bit.QOI_OP_DIFF;
            this.db = cast(ubyte)(db + 2);
            this.dg = cast(ubyte)(dg + 2);
            this.dr = cast(ubyte)(dr + 2);
        }

        @safe unittest
        {
            auto testEntry = QoifEntryDiff(-2, 0, 1);
            assert(toByteArray(testEntry) == [0b01001011]);
        }

        this(const ref QoifPixelDiff pixelDiff) @safe
        {
            this(pixelDiff.dr, pixelDiff.dg, pixelDiff.db);
        }
    }

    struct QoifEntryLuma
    {
        mixin(bitfields!(ubyte, "diffGreen", 6, QoifTag2Bit, "type", 2, ubyte,
                "db_dg", 4, ubyte, "dr_dg", 4,));

        this(byte diffGreen, byte dr_dg, byte db_dg) @safe
        {
            type = QoifTag2Bit.QOI_OP_LUMA;
            this.diffGreen = cast(ubyte)(diffGreen + 32);
            this.db_dg = cast(ubyte)(db_dg + 8);
            this.dr_dg = cast(ubyte)(dr_dg + 8);
        }

        @safe unittest
        {
            auto testEntry = QoifEntryLuma(-15, 0, 4);
            assert(toByteArray(testEntry) == [0b10010001, 0b10001100]);
        }

        this(const ref QoifPixelDiff pixelDiff) @safe
        {
            this(pixelDiff.dg, pixelDiff.dr_dg, pixelDiff.db_dg);
        }
    }

    struct QoifEntryRun
    {
        mixin(bitfields!(ubyte, "run", 6, QoifTag2Bit, "type", 2,));

        this(size_t repeatingPixels) @safe
        {
            type = QoifTag2Bit.QOI_OP_RUN;
            this.run = cast(ubyte)(repeatingPixels - 1);
        }

        @safe unittest
        {
            auto testEntry = QoifEntryRun(35);
            assert(toByteArray(testEntry) == [0b11100010]);
        }
    }

    struct QoifPixel
    {
        ubyte r, g, b, a = 255;

        this(ubyte r, ubyte g, ubyte b, ubyte a) @safe
        {
            this.r = r;
            this.g = g;
            this.b = b;
            this.a = a;
        }

        this(Pixel pixel) @safe
        {
            this(pixel.r, pixel.g, pixel.b, pixel.a);
        }

        Pixel toPixel() @safe
        {
            return Pixel(r, g, b, a);
        }

        QoifPixelDiff opBinary(string op : "-")(const QoifPixel other) const @safe
        {
            return QoifPixelDiff(cast(byte)(r - other.r),
                cast(byte)(g - other.g), cast(byte)(b - other.b), cast(byte)(a - other.a));
        }

        alias toPixel this;
    }

    struct QoifPixelDiff
    {
        byte dr, dg, db, da, dr_dg, db_dg;

        this(int dr, int dg, int db, int da = 0) @safe
        {
            this.dr = cast(byte) dr;
            this.dg = cast(byte) dg;
            this.db = cast(byte) db;
            this.da = cast(byte) da;

            dr_dg = cast(byte)(this.dr - this.dg);
            db_dg = cast(byte)(this.db - this.dg);
        }

        bool isWithinQoifDiff() @safe
        {
            // TODO: Check if da == 0?
            return (-2 <= dr && dr <= 1) && (-2 <= dg && dg <= 1) && (-2 <= db && db <= 1);
        }

        bool isWithingQoifLumaDiff() @safe
        {
            // TODO: Check if da == 0?
            return (-32 <= dg && dg <= 31) && (-8 <= dr_dg && dr_dg <= 7)
                && (-8 <= db_dg && db_dg <= 7);
        }
    }

    @trusted ubyte[] toByteArray(T)(inout T t)
    {
        return (cast(ubyte*)&t)[0 .. T.sizeof].dup;
    }
}

public
{
    enum QoifChannels : ubyte
    {
        RGB = 3,
        RGBA = 4,
    }

    enum QoifColorSpace : ubyte
    {
        sRGB = 0,
        linear = 1,
    }

    class QoifImage
    {
        uint width;
        uint height;

        QoifChannels channels;
        QoifColorSpace colorSpace;

        Pixel[] data;

        this(Pixel[] data, uint width, uint height, QoifChannels channels, QoifColorSpace colorSpace) @safe
        {
            this.data = data;
            this.width = width;
            this.height = height;
            this.channels = channels;
            this.colorSpace = colorSpace;
        }

        private this(QoifHeader header, Pixel[] data) @safe
        {
            this(data, header.width, header.height, header.channels, header.colorspace);
        }
    }

    union Pixel
    {
        struct
        {
            ubyte r, g, b, a;
        }

        uint raw;

        this(ubyte r, ubyte g, ubyte b, ubyte a = 255) @safe
        {
            this.r = r;
            this.g = g;
            this.b = b;
            this.a = a;
        }
    }

    ubyte[] encode(uint[] pixels, int width, int height,
        QoifChannels channels = QoifChannels.RGB, QoifColorSpace colorSpace = QoifColorSpace.sRGB) @safe
    {
        return encode(pixels, width, height, channels, colorSpace);
    }

    ubyte[] encode(Pixel[] pixels, int width, int height,
        QoifChannels channels = QoifChannels.RGB, QoifColorSpace colorSpace = QoifColorSpace.sRGB) @safe
    {
        import std.outbuffer;

        auto encodedBuffer = new OutBuffer();
        encodedBuffer.reserve(QoifHeader.sizeof + width * height + 8);

        QoifHeader newHeader = QoifHeader(width, height, channels, colorSpace);
        encodedBuffer.write(toByteArray(newHeader));

        auto previousPixel = QoifPixel(0, 0, 0, 255);
        QoifPixel[64] previouslySeenPixels = QoifPixel(0, 0, 0, 0);

        size_t currentPixelIndex = 0;
        while (currentPixelIndex < pixels.length)
        {
            auto currentPixel = QoifPixel(pixels[currentPixelIndex]);
            int indexPosition = (
                currentPixel.r * 3 + currentPixel.g * 5 + currentPixel.b * 7 + currentPixel.a * 11) % 64;
            QoifPixelDiff diff = currentPixel - previousPixel;

            // 1. Check if we already seen the pixel
            if (currentPixel == previousPixel)
            {
                ubyte matchingPixels = 0;
                while (matchingPixels < 62 && currentPixelIndex + matchingPixels < pixels.length)
                {
                    if (pixels[currentPixelIndex + matchingPixels] != previousPixel)
                    {
                        break;
                    }
                    matchingPixels++;
                }
                QoifEntryRun entry = QoifEntryRun(matchingPixels);
                encodedBuffer.write(toByteArray(entry));
                currentPixelIndex += matchingPixels - 1;
            }
            else if (previouslySeenPixels[indexPosition] == currentPixel)
            {
                QoifEntryIndex entry = QoifEntryIndex(indexPosition);
                encodedBuffer.write(toByteArray(entry));
            }
            // Encode as RGBA only if we support those channels and alpha has changed
            else if (newHeader.channels == QoifChannels.RGBA && diff.da != 0)
            {
                QoifEntryRGBA entry = QoifEntryRGBA(currentPixel);
                encodedBuffer.write(toByteArray(entry));
            }
            else if (diff.isWithinQoifDiff)
            {
                QoifEntryDiff entry = QoifEntryDiff(diff);
                encodedBuffer.write(toByteArray(entry));
            }
            else if (diff.isWithingQoifLumaDiff)
            {
                QoifEntryLuma entry = QoifEntryLuma(diff);
                encodedBuffer.write(toByteArray(entry));
            }
            else
            {
                QoifEntryRGB entry = QoifEntryRGB(currentPixel);
                encodedBuffer.write(toByteArray(entry));
            }

            // Don't forget to update previuos pixels with the current value
            previouslySeenPixels[indexPosition] = currentPixel;
            previousPixel = currentPixel;
            currentPixelIndex++;
        }

        // Place the stream ending
        encodedBuffer.fill0(7);
        encodedBuffer.write(cast(ubyte)1);

        return encodedBuffer.toBytes;
    }

    /// This test verifies that basic 2x2 single color image is encoded properly
    @safe private unittest
    {
        // Test image:
        // |---|---|
        // | R | G |
        // |---|---|
        // | B | W |
        // |---|---|
        ubyte[] expectedData = [
            // Header
            'q', 'o', 'i', 'f', 0, 0, 0, 2, 0, 0, 0, 2, 3, 0,
            // Data
            0b01011010, 0b01110110, 0b01101101, 0b01010110,
            // Footer
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0, 0x01
        ];

        auto image = [
            Pixel(255, 0, 0), Pixel(0, 255, 0), Pixel(0, 0, 255),
            Pixel(255, 255, 255)
        ];

        auto actualData = encode(image, 2, 2);
        assert(actualData == expectedData);
    }

    /// This test verifies that encoder is capable of encoding all the QOIF types
    @safe private unittest
    {
        // All of the cases here a 1x1 images just to verify basic types
        struct TestData
        {
            string caseName;
            Pixel image;
            QoifChannels imageChannels;
            ubyte[] expectedData;
        }

        // dfmt off
        TestData[] testData = [
            {"Single color", Pixel(23, 128, 54), QoifChannels.RGB, [ 0xFE, 23, 128, 54 ] },
            {"Single color with alpha", Pixel(23, 128, 54, 128), QoifChannels.RGBA, [ 0xFF, 23, 128, 54, 128 ] },
            {"Previously seen color", Pixel(0, 0, 0, 0), QoifChannels.RGBA, [ 0x00 ] },
            {"Delta-encoded color", Pixel(255, 255, 255), QoifChannels.RGB, [ 0b01010101 ] },
            {"Enhanced delta-encoded color", Pixel(2, 10, 17), QoifChannels.RGB, [ 0b10101010, 0b00001111 ] },
        ];
        // dfmt on

        foreach (t; testData)
        {
            ubyte[] expectedData = cast(ubyte[])[
                'q', 'o', 'i', 'f', 0, 0, 0, 1, 0, 0, 0, 1, t.imageChannels, 0
            ] ~ t.expectedData ~ cast(ubyte[])[
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0, 0x01
            ];

            auto actualData = encode([t.image], 1, 1, t.imageChannels);
            assert(actualData == expectedData, t.caseName ~ " failed");
        }
    }

    QoifImage decode(const ubyte[] data) @trusted
    {
        auto header = cast(QoifHeader*) data;

        import std.conv : to;

        Pixel[] image = new Pixel[header.width * header.height];
        size_t offset = QoifHeader.sizeof;
        Pixel previousPixel = Pixel(0, 0, 0, 255);
        Pixel[64] previouslySeenPixels = Pixel(0, 0, 0, 0);

        size_t pixelsProcessed;
        while (pixelsProcessed < header.width * header.height)
        {
            assert(offset < data.length);

            size_t offsetChange;
            size_t processedPixelChange = 1;
            // Check the tag, 8 bit first
            if (data[offset] == QOIFTag8Bit.QOI_OP_RGB)
            {
                auto entry = cast(QoifEntryRGB*)&data[offset];
                offsetChange = (*entry).sizeof;
                image[pixelsProcessed] = Pixel(entry.red, entry.green,
                    entry.blue, previousPixel.a);
            }
            else if (data[offset] == QOIFTag8Bit.QOI_OP_RGBA)
            {
                auto entry = cast(QoifEntryRGBA*)&data[offset];
                offsetChange = (*entry).sizeof;
                image[pixelsProcessed] = Pixel(entry.red, entry.green, entry.blue, entry.alpha);
            }
            else
            {
                ubyte twoByteTag = data[offset] >>> 6;
                switch (twoByteTag)
                {
                case QoifTag2Bit.QOI_OP_INDEX:
                    auto entry = cast(QoifEntryIndex*)&data[offset];
                    image[pixelsProcessed] = previouslySeenPixels[entry.index];
                    offsetChange = QoifEntryIndex.sizeof;
                    break;
                case QoifTag2Bit.QOI_OP_DIFF:
                    auto entry = cast(QoifEntryDiff*)&data[offset];
                    image[pixelsProcessed].r = cast(ubyte)(previousPixel.r + (-2 + entry.dr));
                    image[pixelsProcessed].g = cast(ubyte)(previousPixel.g + (-2 + entry.dg));
                    image[pixelsProcessed].b = cast(ubyte)(previousPixel.b + (-2 + entry.db));
                    image[pixelsProcessed].a = previousPixel.a;
                    offsetChange = QoifEntryDiff.sizeof;
                    break;
                case QoifTag2Bit.QOI_OP_LUMA:
                    auto entry = cast(QoifEntryLuma*)&data[offset];
                    byte dg = cast(byte)(-32 + entry.diffGreen);
                    byte dr = cast(byte)(dg + (-8 + entry.dr_dg));
                    byte db = cast(byte)(dg + (-8 + entry.db_dg));
                    image[pixelsProcessed].r = cast(ubyte)(previousPixel.r + dr);
                    image[pixelsProcessed].g = cast(ubyte)(previousPixel.g + dg);
                    image[pixelsProcessed].b = cast(ubyte)(previousPixel.b + db);
                    image[pixelsProcessed].a = previousPixel.a;
                    offsetChange = QoifEntryLuma.sizeof;
                    break;
                case QoifTag2Bit.QOI_OP_RUN:
                    auto entry = cast(QoifEntryRun*)&data[offset];
                    for (size_t i = 0; i <= entry.run; ++i)
                    {
                        image[pixelsProcessed + i] = previousPixel;
                    }
                    processedPixelChange += entry.run;
                    offsetChange = QoifEntryRun.sizeof;
                    break;
                default:
                    assert(0);
                }
            }
            previousPixel = image[pixelsProcessed];
            int indexPosition = (
                previousPixel.r * 3 + previousPixel.g * 5 + previousPixel.b * 7
                    + previousPixel.a * 11) % 64;
            previouslySeenPixels[indexPosition] = previousPixel;

            offset += offsetChange;
            pixelsProcessed += processedPixelChange;
        }
        return new QoifImage(*header, image);
    }

    /// Encode and decode RGB image
    @safe unittest
    {
        import std.file : read;

        auto originalImage = cast(ubyte[]) read("test_data/testcard.qoi");
        QoifImage decoded = decode(originalImage);
        assert(decoded.channels = QoifChannels.RGB);
        assert(decoded.colorSpace = QoifColorSpace.sRGB);

        auto encodedImage = encode(decoded.data, decoded.header.width,
            decoded.header.height, decoded.header.channels, decoded.header.colorspace);
        assert(originalImage == encodedImage);
    }

    @safe unittest
    {
        import std.file : read;

        // Test RGBA image decode and encode
        auto originalImage = cast(ubyte[]) read("test_data/testcard_rgba.qoi");
        QoifImage decoded = decode(originalImage);
        auto encodedImage = encode(decoded.data, decoded.header.width,
            decoded.header.height, decoded.header.channels, decoded.header.colorspace);
        assert(originalImage == encodedImage);
    }
}
