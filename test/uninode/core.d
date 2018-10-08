/**
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-10-08
 */

module uninode.core_test;

private
{
    import dunit;

    import uninode.core;
}


class TestCore
{
    mixin UnitTest;

    @Test
    void testSize()
    {
        auto node = UniNode(11U);
        assertEquals(node.sizeof, 24);
    }


    @Test
    void testImmutableInstance()
    {
        auto inode = immutable(UniNode)(1U);
        assertEquals(inode.kind, UniNode.Kind.uinteger);
        assertFalse(inode.isNull);
    }


    @Test
    void testNumeric()
    {
        auto snode = UniNode(-10);
        auto exp = expectThrows!UniNodeException(snode.get!ulong);
        assertEquals("Signed value less zero", exp.msg);

        auto unode = UniNode(ulong.max);
        auto exp2 = expectThrows!UniNodeException(unode.get!long);
        assertEquals("Unsigned value great max", exp2.msg);
    }


    @Test
    void testSafeCode() @safe
    {
        auto node = UniNode(1);
        auto mnode = UniNode(["one": node, "two": node]);
        auto anode = UniNode([node, node]);

        ulong counter;
        foreach (string key, UniNode n; mnode)
            counter++;
        assertEquals(counter, mnode.length);

        counter = 0;
        foreach (ulong idx, UniNode n; anode)
            counter++;
        assertEquals(counter, anode.length);

        counter = 0;
        foreach (UniNode n; anode)
            counter++;
        assertEquals(counter, anode.length);
    }


    @Test
    void testSystemCode() @system
    {
        auto node = UniNode(1);
        auto mnode = UniNode(["one": node, "two": node]);
        auto anode = UniNode([node, node]);

        ulong counter;
        foreach (string key, UniNode n; mnode)
            counter++;
        assertEquals(counter, mnode.length);

        counter = 0;
        foreach (ulong idx, UniNode n; anode)
            counter++;
        assertEquals(counter, anode.length);

        counter = 0;
        foreach (UniNode n; anode)
            counter++;
        assertEquals(counter, anode.length);
    }


    @Test
    void testFunctionDefaultValue()
    {
        string val;
        void fun(UniNode node = UniNode(""))
        {
            val = node.get!string;
        }

        fun();
        assertEquals(val, "");
        fun(UniNode("1"));
        assertEquals(val, "1");
    }


    @Test
    void testMemoryType()
    {
        import std.meta : AliasSeq;

        alias IUniNode = immutable(UniNode);
        alias CUniNode = const(UniNode);

        void testImNode(TT)(immutable(UniNode) imnode, TT initVal)
        {
            assert(imnode.kind != UniNode.Kind.nil);
            auto ret = imnode.get!TT;
            assert(is(typeof(ret) == immutable(TT)));
            assert(ret == initVal);
        }

        void testConstNode(TT)(const(UniNode) cnode, TT initVal)
        {
            assert(cnode.kind != UniNode.Kind.nil);
            auto ret = cnode.get!TT;
            assert(is(typeof(ret) == const(TT)));
            assert(ret == initVal);
        }

        auto ibool = IUniNode(true);
        testImNode!bool(ibool, true);

        foreach (TT; AliasSeq!(byte, short, int, long))
        {
            immutable(TT) ival = 12;

            auto inode = IUniNode(ival);
            testImNode!TT(inode, ival);

            auto cnode = CUniNode(ival);
            testConstNode!TT(cnode, ival);
        }


        foreach (TT; AliasSeq!(ubyte, ushort, uint, ulong))
        {
            immutable(TT) ival = 13U;
            auto inode = IUniNode(ival);
            testImNode!TT(inode, ival);

            auto cnode = CUniNode(ival);
            testConstNode!TT(cnode, ival);
        }


        auto snode = IUniNode("one");
        testImNode!string(snode, "one");
    }


    @Test
    void testMultiThreads()
    {
        import std.concurrency;

        static void child(Tid parent, UniNode tail)
        {
            bool runned = true;
            while(runned)
                receive(
                        (UniNode nodes) {
                            nodes ~= tail;
                            parent.send(nodes);
                        },
                        (OwnerTerminated e) {
                            runned = false;
                        }
                    );
        }

        auto tail = immutable(UniNode)(1);
        auto p = spawn(&child, thisTid(), tail);
        auto nodes = UniNode.emptyArray();

        foreach (i; 0..4)
        {
            p.send(nodes);
            nodes = receiveOnly!UniNode;
        }

        assertEquals(nodes.length, 4);
    }
}

