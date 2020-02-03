/**
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-10-08
 */

module uninode.core_test;

private
{
    import std.meta : AliasSeq, allSatisfy;

    import uninode.core;
    import std.exception : assertThrown, collectException;
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
    auto node = UniNode();
    assert (node.canNil);

    node = UniNode(null);
    assert (node.canNil);

    node = UniNode(1);
    assert (node.canInteger);

    node = UniNode(1u);
    assert (node.canUinteger);

    node = UniNode(1.1);
    assert (node.canFloating);

    node = UniNode("text");
    assert (node.canText);

    ubyte[2] bytes = [1, 2];
    node = UniNode(bytes);
    assert (node.canRaw);

    node = UniNode([UniNode(1), UniNode(2)]);
    assert (node.canSequence);

    node = UniNode(["one": UniNode(1), "two": UniNode(2)]);
    assert (node.canMapping);

    node = UniNode(1, "one", 1.2);
    assert (node.canSequence);
}

@("Should work protect number overflow")
@safe unittest
{
    const minNode = UniNode(long.min);
    assertThrown!UniNodeException(minNode.convertTo!ubyte);
    const bigNode = UniNode(long.max);
    assertThrown!UniNodeException(bigNode.convertTo!ubyte);
    const uNode = UniNode(ulong.max);
    assertThrown!UniNodeException(uNode.convertTo!ubyte);
    assertThrown!UniNodeException(uNode.convertTo!long);
    assertThrown!UniNodeException(bigNode.convertTo!(byte));
}


@("Should allow create unsigned integer node")
@safe unittest
{
    foreach (TT; AliasSeq!(ubyte, ushort, uint, ulong))
    {
        TT v = cast(TT)11U;
        const node = UniNode(v);
        assert (node.canUinteger);
        assert (node.convertTo!TT == 11U);
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
        assert (node.convertTo!TT == -11);
    }
}


@("Should allow boolean node")
@safe unittest
{
    const node = UniNode(true);
    assert (node.canBoolean);
    assert (node.convertTo!bool == true);

    const nodei = UniNode(0);
    assert (nodei.canInteger);
    assert (nodei.convertTo!bool == false);

    const nodeu = UniNode(ulong.max);
    assert (nodeu.canUinteger);
    assert (nodeu.convertTo!bool == true);
}


@("Should allow create floating node")
@safe unittest
{
    foreach (TT; AliasSeq!(float, double))
    {
        TT v = 11.11;
        const node = UniNode(v);
        assert (node.canFloating);
        assert (node.convertTo!TT == cast(TT)11.11);
    }

    const nodeu = UniNode(11u);
    assert (nodeu.convertTo!double == 11.0);

    const nodei = UniNode(-11);
    assert (nodei.convertTo!double == -11.0);
}


@("Should allow create string node")
@safe unittest
{
    enum text = "hello";

    const node = UniNode(text);
    assert(node.canText);
    assert (node.convertTo!string == text);

    ubyte[] bytes = new ubyte[text.length];
    foreach (i, c; text)
        bytes[i] = c;

    const nodeb = UniNode(bytes);
    assert(nodeb.convertTo!string == text);
}


@("Should allow create raw node")
@safe unittest
{
    ubyte[] dynArr = [1, 2, 3];
    auto node = UniNode(dynArr);
    assert (node.canRaw);
    assert (node.convertTo!(ubyte[]) == [1, 2, 3]);

    ubyte[3] stArr = [1, 2, 3];
    node = UniNode(stArr);
    assert (node.canRaw);
    assert (node.convertTo!(ubyte[3]) == [1, 2, 3]);

    Bytes bb = [1, 2, 3];
    node = UniNode(bb);
    assert (node.canRaw);
    assert (node.convertTo!(ubyte[]) == [1, 2, 3]);
}


@("Should allow create sequence node")
@system unittest
{
    const node = UniNode(1);
    const seq = UniNode([node, node, node]);
    assert (seq.canSequence);
    assert (seq.convertToSequence == [node, node, node]);
}


@("Should allow create object node")
@safe unittest
{
    const node = UniNode(1);
    const mapp = ["one": node, "two": node, "three": node];
    const obj = UniNode(mapp);
    assert (obj.canMapping);
    const sseq = UniNode([node, obj]);
    assert (sseq.canSequence);
    assert (obj.convertToMapping == mapp);
}


@("Should work canMatch")
@safe unittest
{
    static struct OverloadSet
    {
        static void fun(int n) {}
        static void fun(double d) {}
    }

    assert(canMatch!(OverloadSet.fun, int));
    assert(canMatch!(OverloadSet.fun, double));
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
    testNode([UniNode(1), UniNode(2)].toSequence, "got seq len 2");
    testNode(["one": UniNode(1), "two": UniNode(2)].toMapping, "got mapping len 2");
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


@("Should work toHash")
@safe unittest
{
    const node1 = UniNode(1);
    assert (node1.toHash == 1);
}


@("Should work immutable node")
@safe unittest{
    auto inode = immutable(UniNode)(1U);
    assert (inode.canUinteger);
    assert (!inode.canNil);
    assertThrown(inode.convertTo!string == "one");
}


@("Should work numeric node")
@safe unittest
{
    auto snode = UniNode(-10);
    auto exc = collectException!UniNodeException(snode.convertTo!ulong);
    assert (exc && exc.msg == "Signed value less zero");

    auto unode = UniNode(ulong.max);
    auto exc2 = collectException!UniNodeException(unode.convertTo!long);
    assert (exc2 && exc2.msg == "Unsigned value great max");
}


@("Should work system code")
@system unittest
{
    const node = UniNode(1);
    const mnode = ["one": node, "two": node].toMapping;
    const anode = [node, node].toSequence;

    ulong counter;
    foreach (string key, ref const(UniNode) n; mnode.convertToMapping)
        counter++;
    assert (counter == mnode.length);

    counter = 0;
    foreach (ulong idx, const(UniNode) n; anode.convertToSequence)
        counter++;
    assert (counter == anode.length);

    counter = 0;
    foreach (const(UniNode) n; anode.convertToSequence)
        counter++;
    assert (counter == anode.length);
}


@("Should work funcgtion default value")
@safe unittest
{
    string val;
    void fun(UniNode node = UniNode(""))
    {
        val = node.convertTo!string;
    }

    fun();
    assert (val == "");
    fun(UniNode("1"));
    assert (val == "1");
}


@("Should work in multithread code")
@system unittest
{
    import std.concurrency : spawn, Tid, thisTid, 
           send, receive, OwnerTerminated, receiveOnly;

    alias Message = immutable(UniNode);

    static void summator(Tid parent)
    {
        bool runned = true;
        while(runned)
            receive(
                    (Message node) {
                        auto val = node.match!(
                                (int i) => i + 1,
                                () => 0
                            );
                        parent.send(Message(val));
                    },
                    (OwnerTerminated e) {
                        runned = false;
                    }
                );
    }

    auto p = spawn(&summator, thisTid());

    size_t counter;
    foreach (i; 0..4)
    {
        p.send(Message(i));
        receive((Message msg) {
                counter += msg.match!(
                        (int i) => i,
                        () => 0);
            });
    }

    assert (counter == 10);
}


@("Should work any memory types")
@safe unittest
{
    immutable inode = UniNode("immutable");
    const cnode = UniNode("const");
    UniNode node = UniNode("auto");
    assert (inode.length == 9);
    assert (cnode.length == 5);
    assert (node.length == 4);
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
    auto objNode = UniNode([
            "i": intNode,
            "ui": uintNode,
            "f": fNode,
            "text": textNode,
            "bool": boolNode,
            "bin": binNode,
            "nil": nilNode,
            "arr": arrNode]);
    
    assert (objNode.toString == `{i:int(2147483647), bool:bool(true), text:text(node), arr:[int(2147483647), float(nan), text(node), nil], ui:uint(4294967295), nil:nil, bin:raw([1, 2, 3]), f:float(nan)}`);
}

