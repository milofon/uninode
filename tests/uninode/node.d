/**
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-10-08
 */

module uninode.test_node;

private
{
    import std.algorithm.iteration : map;
    import std.traits : isArray, isAssociativeArray;
    import std.exception : assertThrown, collectException;
    import std.meta : AliasSeq, allSatisfy;
    import std.array : array;
    import std.range : iota;
    import std.conv : text;

    import uninode.node;
}


version (unittest)
{
    void testInitNode(T)(T val, bool function(UniNode) @safe checker) @safe
    {
        UniNode node = UniNode(val);
        assert (checker(node));

        const T cv = val;
        const cnode = UniNode(cv);
        assert (checker(cnode));

        static if (isArray!T)
            immutable T iv = val.idup;
        else static if (isAssociativeArray!T)
            immutable T iv = () @trusted { return cast(immutable) val; } ();
        else
            immutable T iv = val;
        immutable inode = UniNode(iv);
        assert (checker(inode));
    }
}


@("Should size normal")
@safe unittest
{
    const node = UniNode(1);
    assert (node.sizeof == 24);
}


@("Should allow create node")
@safe unittest
{
    const node = UniNode(null);
    assert (node.canNil);

    testInitNode!(int)(11, (n) => n.canInteger);
    testInitNode!(uint)(11u, (n) => n.canUinteger);
    testInitNode!(float)(1.1, (n) => n.canFloating);
    testInitNode!(double)(1.1, (n) => n.canFloating);
    testInitNode!(string)("hello", (n) => n.canText);
    ubyte[2] bytes = [1, 2];
    testInitNode(bytes, (n) => n.canRaw);
    ubyte[] abytes = [1, 2];
    testInitNode(abytes, (n) => n.canRaw);

    testInitNode([UniNode(1), UniNode(2)], (n) => n.canSequence);
    testInitNode(["one": UniNode(1), "two": UniNode(2)], (n) => n.canMapping);

    const anode = UniNode(1, "one", 1.2);
    assert (anode.canSequence);

    const arr = [UniNode(1), UniNode(2)];
    const canode = UniNode(arr);
    assert (canode.canSequence);
}


@("Should allow create sequence node")
@safe unittest
{
    const start = iota(5).map!(i => UniNode(i)).array;

    const seq = UniNode(start);
    static assert (is(typeof(seq.getSequence()) == const(UniNode[])));
    assert (seq.canSequence);
    assert (seq[0].get!int == 0); // opIndex
    static assert (!__traits(compiles, () { seq[0] = 2; })); // no modify const

    auto mutSeq = UniNode(start);
    static assert (is(typeof(mutSeq.getSequence()) == UniNode[]));
    UniNode[] refArr = mutSeq.getSequence; // ref array

    assert (mutSeq[0].get!int == 0); // opIndex
    mutSeq[0] = 101; // opIndexAssign
    assert (mutSeq[0].get!int == 101); // opIndex
    assert (refArr[0].get!int == 101); // array modify too

    mutSeq[0] = UniNode([UniNode(2), UniNode(3)]);
    assert (mutSeq[0][1].get!int == 3); // nested opIndex

    mutSeq[0][1] = 4; // nested opIndexAssign
    assert (mutSeq[0][1].get!int == 4);
    assert (refArr[0].getSequence[1].get!int == 4); // ref array

    assert (mutSeq.getSequence.length == 5);
    mutSeq ~= UniNode(5); // opOpAssign
    assert (mutSeq.getSequence.length == 6);
    assert (refArr.length == 5); // not modify ref array
    assert (mutSeq[5].get!int == 5);

    mutSeq ~= [UniNode(55), UniNode(44)]; // opOpAssign array
    assert (mutSeq.getSequence.length == 7);
    assert (mutSeq[6][1].get!int == 44);

    const eNode = UniNode.emptySequence;
    assert (eNode.canSequence);

    assert (start.length == 5);
}


@("Should allow create mapping node")
@safe unittest
{
    const mapp = ["one": UniNode(1), "two": UniNode(2), "three": UniNode(3)];

    const cMapp = UniNode(mapp);
    static assert (is(typeof(cMapp.getMapping()) == const(UniNode[string])));
    assert (cMapp.canMapping);
    assert (cMapp["one"].get!int == 1);
    static assert (!__traits(compiles, () { cMapp["four"] = 4; }));

    auto mutMapp = UniNode(mapp);
    static assert (is(typeof(mutMapp.getMapping()) == UniNode[string]));
    assert (mutMapp.canMapping);
    assert (mutMapp["two"].get!int == 2);
    UniNode[string] refMapp = mutMapp.getMapping;

    assert (mutMapp["one"].get!int == 1); // opIndex
    mutMapp["one"] = 101;
    assert (mutMapp["one"].get!int == 101);
    assert (refMapp["one"].get!int == 101);

    mutMapp["one"] = UniNode(["one": UniNode(11), "two": UniNode(12)]);
    assert (mutMapp["one"]["two"].get!int == 12);

    mutMapp["one"]["one"] = 1010;
    assert (mutMapp["one"]["one"].get!int == 1010);
    assert (refMapp["one"].getMapping["one"].get!int == 1010);

    assert (mutMapp.getMapping.length == 3);
    mutMapp["four"] = UniNode(4);
    assert (mutMapp.getMapping.length == 4);
    assert (refMapp.length == 4); // ref modify too
    assert (mutMapp["four"].get!int == 4);
    assert (mapp.length == 3); // start not modify

    const eMap = UniNode.emptyMapping;
    assert (eMap.canMapping);

    mutMapp.remove("four");
    assert (mutMapp.getMapping.length == 3);
    assert (refMapp.length == 3); // ref modify too

    assert ("one" in cMapp);
    auto cNode = "one" in cMapp;
    assert (cNode.get!int == 1);
    static assert (is(typeof(cNode) == const(UniNode)*));

    auto context = UniNode.emptyMapping;
    context["loop"] = UniNode.emptyMapping;
    context["loop"]["length"] = UniNode(1);
}


@("Should work protect number overflow")
@safe unittest
{
    const minNode = UniNode(long.min);
    auto e = collectException!UniNodeException(minNode.get!ubyte);
    assert (e.msg == "Signed value less zero");

    const bigNode = UniNode(long.max);
    e = collectException!UniNodeException(bigNode.get!ubyte);
    assert (e.msg == "Conversion positive overflow");

    const uNode = UniNode(ulong.max);
    e = collectException!UniNodeException(uNode.get!ubyte);
    assert (e.msg == "Conversion positive overflow");

    assertThrown!UniNodeException(uNode.get!long);
    assertThrown!UniNodeException(bigNode.get!(byte));
}


@("Should allow create unsigned integer node")
@safe unittest
{
    foreach (TT; AliasSeq!(ubyte, ushort, uint, ulong))
    {
        TT v = cast(TT)11U;
        const node = UniNode(v);
        assert (node.canUinteger);
        assert (node.get!TT == 11U);
    }
}


@("Should allow create integer node")
@safe unittest
{
    foreach (TT; AliasSeq!(byte, short, int, long))
    {
        TT v = -11;
        const node = UniNode(v);
        assert (node.canInteger);
        assert (node.get!TT == -11);
    }
}


@("Should allow boolean node")
@safe unittest
{
    const node = UniNode(true);
    assert (node.canBoolean);
    assert (node.get!bool == true);

    const nodei = UniNode(0);
    assert (nodei.canInteger);
    assert (nodei.get!bool == false);

    const nodeu = UniNode(ulong.max);
    assert (nodeu.canUinteger);
    assert (nodeu.get!bool == true);
}


@("Should allow create floating node")
@safe unittest
{
    foreach (TT; AliasSeq!(float, double))
    {
        TT v = 11.11;
        const node = UniNode(v);
        assert (node.canFloating);
        assert (node.get!TT == cast(TT)11.11);
    }

    const nodeu = UniNode(11u);
    assert (nodeu.get!double == 11.0);

    const nodei = UniNode(-11);
    assert (nodei.get!double == -11.0);
}


@("Should allow create string node")
@safe unittest
{
    enum text = "hello";

    const node = UniNode(text);
    assert(node.canText);
    assert (node.get!string == text);

    ubyte[] bytes = new ubyte[text.length];
    foreach (i, c; text)
        bytes[i] = c;

    const nodeb = UniNode(bytes);
    assert(nodeb.get!string == text);
}


@("Should allow create raw node")
@safe unittest
{
    ubyte[] dynArr = [1, 2, 3];
    auto node = UniNode(dynArr);
    assert (node.canRaw);
    assert (node.get!(ubyte[]) == [1, 2, 3]);

    ubyte[3] stArr = [1, 2, 3];
    node = UniNode(stArr);
    assert (node.canRaw);
    assert (node.get!(ubyte[3]) == [1, 2, 3]);

    Bytes bb = [1, 2, 3];
    node = UniNode(bb);
    assert (node.canRaw);
    assert (node.get!(ubyte[]) == [1, 2, 3]);
}


@("Should work numeric node")
@safe unittest
{
    auto snode = UniNode(-10);
    const exc = collectException!UniNodeException(snode.get!ulong);
    assert (exc && exc.msg == "Signed value less zero");

    auto unode = UniNode(ulong.max);
    const exc2 = collectException!UniNodeException(unode.get!long);
    assert (exc2 && exc2.msg == "Unsigned value great max");
}


@("Should work system code")
@system unittest
{
    const node = UniNode(1);
    auto mnode = UniNode(["one": node, "two": node]);
    const anode = UniNode([node, node]);

    ulong counter;
    foreach (string key, const(UniNode) n; mnode.getMapping)
        counter++;
    assert (counter == mnode.getMapping.length);

    counter = 0;
    foreach (ulong idx, const(UniNode) n; anode.getSequence)
        counter++;
    assert (counter == anode.getSequence.length);

    counter = 0;
    foreach (const(UniNode) n; anode.getSequence)
        counter++;
    assert (counter == anode.getSequence.length);
}


@("Should work opApply for object")
@safe unittest
{
    import std.algorithm.searching : canFind, all;

    string[] keys;
    UniNode[] values;

    const cNode = UniNode(["one": UniNode(1), "two": UniNode(2)]);
    foreach (string k, const(UniNode) n; cNode)
    {
        keys ~= k;
        values ~= n;
    }

    UniNode[string] mapp = ["tree": UniNode(3), "four": UniNode(4)];
    UniNode mNode = UniNode(mapp);
    foreach (string k, UniNode n; mNode)
    {
        keys ~= k;
        values ~= n;
    }

    assert (["one", "two", "tree", "four"].all!((i) => keys.canFind(i)));
    assert ([UniNode(1), UniNode(2), UniNode(3), UniNode(4)].all!(
                (i) => values.canFind(i)));
}


@("Should work opApply for array")
@safe unittest
{
    import std.algorithm.searching : canFind, all;

    auto arr = [UniNode(5), UniNode(7)];
    auto node = UniNode(arr);
    UniNode[] values;
    foreach (const(UniNode) n; node)
        values ~= n;

    assert (arr.all!((i) => values.canFind(i)));
}


@("Should work opApply for array with idx")
@safe unittest
{
    import std.algorithm.searching : canFind, all;

    auto arr = [UniNode(5), UniNode(7), UniNode(3)];
    auto node = UniNode(arr);
    size_t summ;
    UniNode[] values;
    foreach (size_t i, UniNode n; node)
    {
        values ~= n;
        summ += i;
    }

    assert (arr.all!((i) => values.canFind(i)));
    assert (summ == 3);
}


@("Should work opApply for array @system")
@system unittest
{
    import std.algorithm.searching : canFind, all;

    auto arr = [UniNode(5), UniNode(7)];
    const node = UniNode(arr);
    UniNode[] values;
    foreach (UniNode n; node)
        values ~= n;

    assert (arr.all!((i) => values.canFind(i)));
}


@("Should work toHash")
@safe unittest
{
    const node1 = UniNode(1);
    assert (node1.toHash == 1);

    auto val = "hello";
    const nodes = UniNode(val);
    assert (nodes.toHash == val.hashOf);
}


@("Should work function default value")
@safe unittest
{
    string val;
    void fun(UniNode node = UniNode(""))
    {
        val = node.get!string;
    }

    fun();
    assert (val == "");
    fun(UniNode("1"));
    assert (val == "1");
}


@("Should work any memory types")
@safe unittest
{
    immutable inode = UniNode("immutable");
    const cnode = UniNode("const");
    const node = UniNode("auto");
    assert (inode.length == 9);
    assert (cnode.length == 5);
    assert (node.length == 4);
}


@("Should allow match node")
@safe unittest
{
    import std.format : fmt = format;

    alias allMatch = match!(
        (bool val) => fmt!"got %s"(val),
        (byte val) => fmt!"got integer %s"(val),
        (ubyte val) => fmt!"got unsigned integer %s"(val),
        (float val) => fmt!"got float val %s"(val),
        (Bytes val) => fmt!"got bytes %s"(val),
        (string val) => fmt!"got string '%s'"(val),
        (const(UniNode)[] seq) => fmt!"got seq len %s"(seq.length),
        (const(UniNode[string]) mapp) => fmt!"got mapping len %s"(mapp.length),
        () { return "got empty"; }
    );

    void testNode(UniNode node, string msg)
    {
        const val = allMatch(node);
        assert (val == msg);
    }

    testNode(UniNode(), "got empty");
    testNode(UniNode(12), "got integer 12");
    testNode(UniNode(11u), "got unsigned integer 11");
    testNode(UniNode(1.1), "got float val 1.1");
    ubyte[2] bytes = [1, 2];
    testNode(UniNode(bytes), "got bytes [1, 2]");
    testNode(UniNode("hello"), "got string 'hello'");
    testNode(UniNode([UniNode(1), UniNode(2)]), "got seq len 2");
    testNode(UniNode(["one": UniNode(1), "two": UniNode(2)]), "got mapping len 2");
}


@("Should work length operator")
@safe unittest
{
    assert (UniNode("hello").length == 5);
    ubyte[] bytes = [1, 2, 3];
    assert (UniNode(bytes).length == 3);
    assert (UniNode([UniNode(1), UniNode(2)]).length == 2);
    assert (UniNode(["one": UniNode(1), "two": UniNode(2)]).length == 2);
}


@("Should allow template match node")
@safe unittest
{
    const node = UniNode();
    const val = node.match!(
            (val) => "tpl",
        );
    assert (val == "tpl");

    bool flag = false;
    node.match!(
            (val) { flag = true; },
        );
    assert (flag);
}


@("Should work opEquals")
@safe unittest
{
    const node1 = UniNode(1);
    const node2 = UniNode(1u);
    assert (node1.opEquals(node2));
    assert (node2.opEquals(node1));
    assert (node1 == node2);

    auto n1 = UniNode(1);
    auto n2 = UniNode("1");
    auto n3 = UniNode(1);

    assert (n1 == n3);
    assert (n1 != n2);
    assert (n1 != UniNode(3));

    assert (UniNode([n1, n2, n3]) != UniNode([n2, n1, n3]));
    assert (UniNode([n1, n2, n3]) == UniNode([n1, n2, n3]));

    assert (UniNode(["one": n1, "two": n2]) == UniNode(["one": n1, "two": n2]));
}


@("Should work toString method")
@safe unittest
{
    auto intNode = UniNode(int.max);
    auto uintNode = UniNode(uint.max);
    auto fNode = UniNode(float.nan);
    auto textNode = UniNode("node");
    auto boolNode = UniNode(true);
    ubyte[] bytes = [1, 2, 3];
    auto binNode = UniNode(bytes);
    auto nilNode = UniNode();

    auto arrNode = UniNode([intNode, fNode, textNode, nilNode]);
    const objNode = UniNode([
            "i": intNode,
            "ui": uintNode,
            "f": fNode,
            "text": textNode,
            "bool": boolNode,
            "bin": binNode,
            "nil": nilNode,
            "arr": arrNode]);

    assert (objNode.text == "{i:int(2147483647), bool:bool(true), "
            ~ "text:text(node), arr:[int(2147483647), float(nan), text(node), "
            ~ "nil], nil:nil, ui:uint(4294967295), bin:raw([1, 2, 3]), f:float(nan)}");
}


@("Should work function parameters")
@safe unittest
{
    static int initializer(int start, int end, out UniNode result)
    {
        result = UniNode.emptySequence;
        foreach (int i; start .. end)
            result ~= UniNode(i);
        return 0;
    }

    UniNode ret;
    assert (!initializer(1, 5, ret));
    assert (ret.canSequence);
    assert (ret.length == 4);

    ret.match!(
            (ref UniNode[] arr) { arr ~= UniNode(6); },
            () {}
        );
    assert (ret.length == 5);

    auto mapp = UniNode.emptyMapping;
    mapp["two"] = UniNode(33);
    mapp.match!(
        (ref UniNode[string] mapp) { mapp = ["one": UniNode(1)]; },
        () {}
    );
    assert (mapp["one"].get!int == 1);
}


@("Should work require")
@safe unittest
{
    UniNode mapp = UniNode.emptyMapping;
    auto req = mapp.require("one", 1);
    assert (req == UniNode(1));
    req = mapp.require("one", 11);
    assert (req == UniNode(1));
}


@("Should work opApply modify")
@safe unittest
{
    UniNode mapp = UniNode(["one": UniNode(1), "two": UniNode(2)]);
    foreach (string k, ref UniNode n; mapp)
        n = UniNode(k);
    assert (mapp["one"] == UniNode("one"));

    UniNode seq = UniNode([UniNode(1), UniNode(2)]);
    foreach (size_t idx, ref UniNode n; seq)
        n = UniNode(idx * 4);
    assert (seq[1] == UniNode(4));
}


@("Should work opt method")
@system unittest
{
    immutable node = UniNode(1);
    assert (!node.opt!int.empty);
    assert (node.opt!string.empty);
    assert (node.opt!(UniNode[]).empty);
    assert (node.opt!(UniNode[string]).empty);

    UniNode anode = UniNode([UniNode(1), UniNode(2)]);
    assert (!anode.opt!(UniNode[]).empty);
    assert (!anode.optSequence.empty);
    assert (node.optSequence.empty);

    UniNode mnode = UniNode(["one": UniNode(1), "two": UniNode(2)]);
    assert (!mnode.opt!(UniNode[string]).empty);
    assert (!mnode.optMapping.empty);
    assert (node.optMapping.empty);
}

