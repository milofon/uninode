/**
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-10-08
 */

module uninode.test_serialization;

private
{
    import std.meta : AliasSeq;
    import std.exception : assertThrown, collectException;
    import std.traits : isPointer;
    import std.conv : text;
    import std.typecons;

    import uninode.node : Bytes;
    import uninode.serialization;
}


version (unittest)
{
    static void test(T)(auto ref T value, UniNode expected)
    {
        assert (serializeToUniNode(value) == expected, serializeToUniNode(value).text);
        static if (isPointer!T)
        {
            if (value)
                assert (*deserializeUniNode!T(expected) == *value);
            else
                assert (deserializeUniNode!T(expected) is null);
        }
        else
            assert (deserializeUniNode!T(expected) == value);
    }
}


@("Sould de/serialize simple types")
@safe unittest
{
    test(null, UniNode());
    test(cast(int*)null, UniNode());
    int i = 42;
    () @trusted { test(&i, UniNode(42)); }();

    foreach (T; AliasSeq!(byte, short, int, long))
    {
        T v = cast(T)11;
        test(v, UniNode(v));
    }

    foreach (T; AliasSeq!(ubyte, ushort, uint, ulong))
    {
        T v = cast(T)11u;
        test(v, UniNode(v));
    }

    foreach (T; AliasSeq!(float, double))
    {
        T v = cast(T)1.1;
        test(v, UniNode(v));
    }

    test("hello", UniNode("hello"));
    test(true, UniNode(true));
    test(false, UniNode(false));

    ubyte[3] bytes = [1, 2, 3];
    test(bytes, UniNode(bytes));
}


@("Should de/serialize nullable types")
@safe unittest
{
    assert (serializeToUniNode(Nullable!int.init).canNil);

    auto nNode = serializeToUniNode(Nullable!int(11));
    assert (nNode == UniNode(11));
    const nVal = deserializeUniNode!(Nullable!byte)(nNode);
    assert (!nVal.isNull);
    assert (nVal.get == 11);

    auto oNode = serializeToUniNode(Nullable!string("hello"));
    assert (oNode == UniNode("hello"));
    const oVal = deserializeUniNode!(Nullable!string)(oNode);
    assert (!oVal.isNull);
    assert (oVal.get == "hello");
}


@("Should de/serialization array")
@safe unittest
{
    ubyte[] bytes = [1, 2, 3];
    ulong[] numbers = [4, 5, 6];

    const bNode = serializeToUniNode(bytes);
    assert (bNode.canRaw);
    assert (deserializeUniNode!(ubyte[3])(bNode) == bytes);
    assert (deserializeUniNode!(ubyte[])(bNode) == bytes);
    assert (deserializeUniNode!(long[3])(bNode) == bytes);
    assert (deserializeUniNode!(long[])(bNode) == bytes);

    const aNode = serializeToUniNode(numbers);
    assert (aNode.getSequence[1] == UniNode(5));
    assert (deserializeUniNode!(ubyte[3])(aNode) == numbers);
    assert (deserializeUniNode!(ubyte[])(aNode) == numbers);
    assert (deserializeUniNode!(ulong[3])(aNode) == numbers);
    assert (deserializeUniNode!(ulong[])(aNode) == numbers);

    test(["hello", "world"], UniNode([UniNode("hello"), UniNode("world")]));
}


@("Should de/serialization associative array")
@safe unittest
{
    auto aa = ["one": 1, "two": 2];
    const aaNode = serializeToUniNode(aa);
    assert (aaNode.getMapping["one"] == UniNode(1));
    assert (deserializeUniNode!(int[string])(aaNode) == aa);

    test(["hello": "world"], UniNode(["hello": UniNode("world")]));
}


@("Should de/serialization typedef")
@safe unittest
{
    alias TD = Typedef!int;
    TD v = 20;
    const tdNode = serializeToUniNode(v);
    assert (tdNode == UniNode(20));
    assert (deserializeUniNode!TD(tdNode) == 20);
}


@("Should de/serialization BitFlags")
@safe unittest
{
    enum E
    {
        A = 1 << 0,
        B = 1 << 2
    }

    BitFlags!E flags = E.B;
    const bfNode = serializeToUniNode(flags);
    assert (bfNode == UniNode([UniNode(4)]));
    assert (deserializeUniNode!(BitFlags!E)(bfNode) == flags);
}


@("Should de/serialization datetime")
@safe unittest
{
    import std.datetime : SysTime, DateTime, Date;
    auto date = Date(2000, 6, 1);
    const dNode = serializeToUniNode(date);
    assert (dNode == UniNode("2000-06-01"));
    assert (deserializeUniNode!Date(dNode) == date);
}


@("Should de/serialization pointer")
@system unittest
{
    int v = 11;
    int* ptr = &v;
    const ptrNode = serializeToUniNode(ptr);
    assert (ptrNode == UniNode(11));
    assert (*deserializeUniNode!(int*)(ptrNode) == v);
    assert (!deserializeUniNode!(int*)(UniNode()));
}


@("Should de/serialization char")
@safe unittest
{
    const c = 'c';
    const cNode = serializeToUniNode(c);
    assert (cNode == UniNode("c"));
    assert (deserializeUniNode!char(cNode) == c);
}


@("Should de/serialization tuple")
@safe unittest
{
    alias PairDict = Tuple!(int, "b", int, "a");
    auto pd = PairDict(1, 2);
    const pdNode = serializeToUniNode(pd);
    assert (pdNode.getMapping["b"] == UniNode(1));
    assert (pdNode.getMapping["a"] == UniNode(2));
    assert (deserializeUniNode!PairDict(pdNode) == pd);

    const shortNode = UniNode(["a": UniNode(1)]);
    assertThrown!UniNodeDeserializationException(deserializeUniNode!PairDict(shortNode));

    alias PairArr = Tuple!(int, int);
    auto pa = PairArr(2, 3);
    const paNode = serializeToUniNode(pa);

    assert (paNode.getSequence[0] == UniNode(2));
    assert (paNode.getSequence[1] == UniNode(3));
    assert (deserializeUniNode!PairArr(paNode) == pa);

    const sNodeArr = UniNode([UniNode(3)]);
    assertThrown!UniNodeDeserializationException(deserializeUniNode!PairArr(sNodeArr));

    static struct S(T...)
    {
        @name("ff")
        T f;
    }

    const s = S!(int, string)(42, "hello");
    const ss = serializeToUniNode(s);
    assert (ss == UniNode(["ff": UniNode([UniNode(42), UniNode("hello")])]));

    const sc = deserializeUniNode!(S!(int, string))(ss);
    assert (sc == s);

    static struct T
    {
        @asArray
        S!(int, string) g;
    }

    const t = T(s);
    const st = serializeToUniNode(t);
    assert (st == UniNode(["g": UniNode([UniNode(42), UniNode("hello")])]));
}


@("Testing the various UDAs")
@safe unittest
{
    enum E { hello, world }
    static struct S
    {
        @byName E e;
        @ignore int i;
        @optional float f;
    }

    auto s = S(E.world, 42, 1.0f);
    assert(serializeToUniNode(s) == UniNode(["e": UniNode("world"), "f": UniNode(1)]));
}


@("Custom serialization support")
@safe unittest
{
    import std.datetime : TimeOfDay, Date, DateTime, SysTime, UTC;
    auto t = TimeOfDay(6, 31, 23);
    assert(serializeToUniNode(t) == UniNode("06:31:23"));
    auto d = Date(1964, 1, 23);
    assert(serializeToUniNode(d) == UniNode("1964-01-23"));
    auto dt = DateTime(d, t);
    assert(serializeToUniNode(dt) == UniNode("1964-01-23T06:31:23"));
    auto st = SysTime(dt, UTC());
    assert(serializeToUniNode(st) == UniNode("1964-01-23T06:31:23Z"));
}


@("Testing corner case: member function returning by ref")
@safe unittest
{
    static struct S
    {
        int i;
        ref int foo() { return i; }
    }

    auto s = S(1);
    assert(serializeToUniNode(s).deserializeUniNode!S == s);
}


@("Testing corner case: Variadic template constructors and methods")
@safe unittest
{
    static struct S
    {
        int i;
        this(Args...)(Args args) {}
        int foo(Args...)(Args) { return i; }
        ref int bar(Args...)(Args) { return i; }
    }

    const s = S(1);
    assert(s.serializeToUniNode.deserializeUniNode!S == s);
}


@("Make sure serializing through properties still works")
@safe unittest
{
    static struct S
    {
        @safe:
            public int i;
        private int privateJ;

        @property int j() inout @safe { return privateJ; }
        @property void j(int j) @safe { privateJ = j; }
    }

    auto s = S(1, 2);
    assert(s.serializeToUniNode().deserializeUniNode!S() == s);
}


@("Should custom serializationMethod struct")
@safe unittest
{
    import std.conv : text, to;

    static struct Test
    {
        int a;

        @SerializationMethod
        UniNode serializeToUniNode() inout
        {
            return UniNode(a.text);
        }

        @DeserializationMethod
        static Test deserializeUniNode(UniNode value)
        {
            return Test(value.get!string.to!int + 10);
        }
    }

    auto t = Test(1);
    auto tNode = serializeToUniNode(t);
    assert (tNode == UniNode("1"));
    assert (deserializeUniNode!Test(tNode) == Test(11));
}


@("Should work de/serialization struct")
@system unittest
{
    static struct Test
    {
        int a;
        int b;
        int c;
    }

    auto t = Test(4, 5, 6);
    const tNode = serializeToUniNode(t);
    assert (tNode == UniNode(["a": UniNode(4),
                "b": UniNode(5), "c": UniNode(6)]));
    assert (deserializeUniNode!Test(tNode) == t);
}


@("Should work attributes")
@system unittest
{
    enum Color { red, green, blue }
    alias Gradient = Tuple!(Color, "cs", Color, "ce");
    alias Center = Tuple!(double, double);

    static struct Point
    {
        double x;
        double y;
    }

    static struct Pixel
    {
        @name("pivot")
        Point point;
        @name("col")
        @byName
        Color color;
    }


    static struct Surface
    {
        Pixel[] pixels;
        Gradient gradFront;
        @asArray
        Gradient gradBack;
        @asArray
        Center center;
        @ignore
        Point left;
        @masked
        Point bottom;
        @asString
        int id;
        @asArray
        Point top;
    }

    auto st = Surface([
            Pixel(Point(1.1, 2.3), Color.red),
            Pixel(Point(2.3, 3.3), Color.green),
            Pixel(Point(3.3, 1.1), Color.blue),
        ],
        Gradient(Color.red, Color.blue),
        Gradient(Color.green, Color.blue),
        Center(4.1, 3.4));

    st.left = Point(0.1, 0.2);
    st.bottom = Point(0.3, 0.7);
    st.id = 100;
    st.top = Point(30, 40);

    auto stNode = serializeToUniNode(st);
    assert (stNode.canMapping);

    const pixels = stNode.getMapping["pixels"];
    assert (pixels.length == 3);

    const p1 = pixels.getSequence[0];

    // name
    assert ("pivot" in p1.getMapping);
    assert ("col" in p1.getMapping);

    // byName
    assert (p1.getMapping["col"] == UniNode("red"));

    // ignore
    assert ("left" !in stNode.getMapping);

    // masked
    assert ("bottom" !in stNode.getMapping);

    // asString
    assert ("id" in stNode.getMapping);

    // asArray
    assert (stNode.getMapping["top"].canSequence);

    const e = collectException!UniNodeDeserializationException(
            deserializeUniNode!Surface(stNode));
    assert (e.msg == "Missing non-optional field 'bottom' of type 'Surface'.");

    UniNode[string] fixUni = cast(UniNode[string])stNode.getMapping;
    fixUni["bottom"] = serializeToUniNode(st.bottom);

    auto dsurf = deserializeUniNode!Surface(UniNode(fixUni));
    assert (dsurf != st);

    dsurf.left = Point(0.1, 0.2);
    dsurf.id = 100;
    assert (dsurf == st);

    static struct Pair
    {
        @optional
        int a;
        int b;
    }

    const optNode = UniNode(["a": UniNode(), "b": UniNode(2)]);
    assert (deserializeUniNode!Pair(optNode) == Pair(0, 2));

    const oNode = UniNode(["a": UniNode(4), "b": UniNode(2)]);
    assert (deserializeUniNode!Pair(oNode) == Pair(4, 2));
}


@("Should serializeToUniNode enum")
@safe unittest
{
    enum Color { red, green, blue }

    @asArray
    static struct TestArr
    {
        @byName
        Color textColor;
        Color numColor;

        Color col() @property inout
        {
            return Color.blue;
        }

        void col(int c) @property
        {
            textColor = cast(Color)c;
        }

        void col(Color c) @property
        {
            textColor = c;
        }
    }
    auto ta = TestArr(Color.blue, Color.green);
    const eNode = serializeToUniNode(ta);
    assert (eNode.getSequence[0] == UniNode("blue"));
    assert (eNode.getSequence[1] == UniNode(1));

    const eVal = deserializeUniNode!TestArr(eNode);
    assert (eVal == ta);

    struct TestMap
    {
        @byName
        Color textColor;
        Color numColor;
    }

    auto tm = TestMap(Color.blue, Color.green);
    assert (serializeToUniNode(tm).getMapping["textColor"] == UniNode("blue"));
    assert (serializeToUniNode(tm).getMapping["numColor"] == UniNode(1));
}


@("Should work serialization")
@system unittest
{
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
        @byName
        Gender gender;
        Flags f;
    }

    auto orig = Face(Rect(Point(2, 3), 5, 5), [1, 2, 4], "anno",
            Gender.F, Flags(Flag.a, Flag.b));
    const data = serializeToUniNode(orig);
    assert (data.deserializeUniNode!Face == orig);
}


@("single-element tuples")
@safe unittest
{
    static struct F { int field; }

    {
        static struct S { typeof(F.init.tupleof) fields; }
        auto b = serializeToUniNode(S(42));
        auto a = deserializeUniNode!S(b);
        assert(a.fields[0] == 42);
    }

    {
        static struct T { @asArray typeof(F.init.tupleof) fields; }
        auto b = serializeToUniNode(T(42));
        auto a = deserializeUniNode!(T)(b);
        assert(a.fields[0] == 42);
    }
}


@("@system property getters/setters does not compile")
@system unittest {
    static class A
    {
        @property @name("foo")
        {
            string fooString() const { return a; }
            void fooString(string a) { this.a = a; }
        }

        private string a;
    }

    auto a1 = new A;
    a1.a = "hello";

    auto b = serializeToUniNode(a1);
    const a2 = deserializeUniNode!(A)(b);
    assert (a1.a == a2.a);
}


@("Should serialization builtin")
@system unittest
{
    static struct Bar { Bar[] foos; int i; }
    Bar b1 = {[{null, 2}], 1};
    auto s = serializeToUniNode(b1);
    const b = deserializeUniNode!(Bar)(s);
    assert (b.i == 1);
    assert (b.foos.length == 1);
    assert (b.foos[0].i == 2);
}


@("Should de/serialization UniNode")
@system unittest
{
    const node = UniNode(1);
    const sNode = serializeToUniNode(node);
    assert (node == sNode);

    const dNode = deserializeUniNode!UniNode(node);
    assert (dNode == node);
}

