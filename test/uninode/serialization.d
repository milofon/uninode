/**
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-10-08
 */

module uninode.serialization_test;

private
{
    import dunit;

    import uninode.serialization;
}



class TestSerialization
{
    mixin UnitTest;


    @Test
    void testSerialize()
    {
        import std.typecons : BitFlags;

        enum Flag {
            a = 1<<0,
            b = 1<<1,
            c = 1<<2
        }

        alias Flags = BitFlags!Flag;

        enum Gender
        {
            M,
            F
        }

        struct Point
        {
            int x;
            int y;
        }

        struct Rect
        {
            Point pivot;
            int w;
            int h;
        }

        struct Face
        {
            Rect pos;
            ubyte[] vector;
            string id;
            Gender gender;
            Flags f;
        }

        auto orig = Face(Rect(Point(2, 3), 5, 5), [1, 2, 4], "anno",
                Gender.F, Flags(Flag.a, Flag.b));
        auto data = serializeToUniNode(orig);
        auto face = deserializeUniNode!Face(data);

        assertEquals(orig, face);
    }
}

