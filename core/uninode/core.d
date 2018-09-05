/**
 * The module contains the object UniNode
 *
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-08-14
 */

module uninode.core;

private
{
    import std.algorithm.comparison : equal;
    import std.traits;
    import std.traits : isTraitsArray = isArray;
    import std.variant : maxSize;
    import std.format : fmt = format;
    import std.array : appender;
    import std.conv : to;
}


/**
 * Universal structure for data storage of different types
 */
struct UniNode
{
@safe:
    UniNodeImpl!UniNode node;
    alias node this;


    this(V)(V val) inout
    {
        node = UniNodeImpl!UniNode(val);
    }
}



unittest
{
    import std.concurrency;

    static void child(Tid parent, UniNode tail)
    {
        bool runned = true;
        while(runned)
            receive(
                (UniNode nodes) {
                    nodes.appendArrayElement(tail);
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

    assert(nodes.length == 4);
}



unittest
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


/**
 * Implementation universal structure for data storage of different types
 */
struct UniNodeImpl(This)
{
@safe:

    private
    {
        union U {
            typeof(null) nil;
            bool boolean;
            ulong uinteger;
            long integer;
            real floating;
            string text;
            ubyte[] raw;
            This[] array;
            This[string] object;
        }

        struct SizeChecker
        {
            int function() fptr;
            ubyte[maxSize!U] data;
        }

        enum size = SizeChecker.sizeof - (int function()).sizeof;

        union
        {
            ubyte[size] _store;
            // conservatively mark the region as pointers
            static if (size >= (void*).sizeof)
                void*[size / (void*).sizeof] p;
        }

        Kind _kind;

        ref inout(T) getDataAs(T)() inout @trusted {
            static assert(T.sizeof <= _store.sizeof);
            return (cast(inout(T)[1])_store[0 .. T.sizeof])[0];
        }

        @property ref inout(This[string]) _object() inout
        {
            return getDataAs!(This[string])();
        }

        @property ref inout(This[]) _array() inout
        {
            return getDataAs!(This[])();
        }

        @property ref inout(bool) _bool() inout
        {
            return getDataAs!bool();
        }

        @property ref inout(long) _int() inout
        {
            return getDataAs!long();
        }

        @property ref inout(ulong) _uint() inout
        {
            return getDataAs!ulong();
        }

        @property ref inout(real) _float() inout
        {
            return getDataAs!real();
        }

        @property ref inout(string) _string() inout
        {
            return getDataAs!string();
        }

        @property ref inout(ubyte[]) _raw() inout
        {
            return getDataAs!(ubyte[])();
        }
    }


    alias Kind = TypeEnum!U;


    Kind kind() @property inout pure
    {
        return _kind;
    }


    static This emptyObject() @property
    {
        return This(cast(This[string])null);
    }


    this(This[string] val)
    {
        _kind = Kind.object;
        _object = val;
    }


    unittest
    {
        auto node = UniNode.emptyObject;
        assert(node.isObject);
    }


    inout(This)* opBinaryRight(string op)(string key) inout if (op == "in")
    {
        enforceUniNode(_kind == Kind.object, "Expected " ~ This.stringof ~ " object");
        return key in _object;
    }


    unittest
    {
        auto node = UniNode(1);
        auto mnode = UniNode(["one": node, "two": node]);
        assert (mnode.isObject);
        assert("one" in mnode);
    }


    static This emptyArray() @property
    {
        return This(cast(This[])null);
    }


    this(This[] val)
    {
        _kind = Kind.array;
        _array = val;
    }


    unittest
    {
        auto node = UniNode.emptyArray;
        assert(node.isArray);
    }


    this(typeof(null))
    {
        _kind = Kind.nil;
    }


    unittest
    {
        auto node = UniNode(null);
        assert (node.isNull);
        auto node2 = UniNode();
        assert (node2.isNull);
    }


    this(T)(T val) inout if (isBoolean!T)
    {
        _kind = Kind.boolean;
        (cast(bool)_bool) = val;
    }


    unittest
    {
        auto node = UniNode(false);
        assert (node.kind == UniNode.Kind.boolean);
        assert (node.get!bool == false);

        auto nodei = UniNode(0);
        assert (nodei.kind == UniNode.Kind.integer);
    }


    this(T)(T val) inout if (isUnsignedNumeric!T)
    {
        _kind = Kind.uinteger;
        (cast(ulong)_uint) = val;
    }


    unittest
    {
        import std.meta : AliasSeq;
        foreach (TT; AliasSeq!(ubyte, ushort, uint, ulong))
        {
            TT v = cast(TT)11U;
            auto node = UniNode(v);
            assert (node.kind == UniNode.Kind.uinteger);
            assert (node.get!TT == cast(TT)11U);
        }
    }


    this(T)(T val) inout if (isSignedNumeric!T)
    {
        _kind = Kind.integer;
        (cast(long)_int) = val;
    }


    unittest
    {
        import std.meta : AliasSeq;
        foreach (TT; AliasSeq!(byte, short, int, long))
        {
            TT v = -11;
            auto node = UniNode(v);
            assert (node.kind == UniNode.Kind.integer);
            assert (node.get!TT == cast(TT)-11);
        }
    }


    this(T)(T val) inout if (isFloatingPoint!T)
    {
        _kind = Kind.floating;
        (cast(real)_float) = val;
    }


    unittest
    {
        import std.meta : AliasSeq;
        foreach (TT; AliasSeq!(float, double))
        {
            TT v = 11.11;
            auto node = UniNode(v);
            assert (node.kind == UniNode.Kind.floating);
            assert (node.get!TT == cast(TT)11.11);
        }
    }


    this(T)(T val) inout if(isSomeString!T)
    {
        _kind = Kind.text;
        (cast(string)_string) = val;
    }


    unittest
    {
        string str = "hello";
        auto node = UniNode(str);
        assert(node.kind == UniNode.Kind.text);
        assert (node.get!(string) == "hello");
    }


    this(T)(T val) if (isRawData!T)
    {
        _kind = Kind.raw;
        static if (isStaticArray!T)
            _raw = val.dup;
        else
            _raw = val;
    }


    unittest
    {
        ubyte[] dynArr = [1, 2, 3];
        auto node = UniNode(dynArr);
        assert (node.kind == UniNode.Kind.raw);
        assert (node.get!(ubyte[]) == [1, 2, 3]);

        ubyte[3] stArr = [1, 2, 3];
        node = UniNode(stArr);
        assert (node.kind == UniNode.Kind.raw);
        assert (node.get!(ubyte[3]) == [1, 2, 3]);
    }


    unittest
    {
        auto node = UniNode();
        assert (node.isNull);

        auto anode = UniNode([node, node]);
        assert (anode.isArray);

        auto mnode = UniNode(["one": node, "two": node]);
        assert (mnode.isObject);
    }


    size_t length() const @property
    {
        switch (_kind) with (Kind)
        {
            case text:
                return _string.length;
            case raw:
                return _raw.length;
            case array:
                return _array.length;
            case object:
                return _object.length;
            default:
                enforceUniNode(false, "Expected " ~ This.stringof ~ " not length");
                assert(false);
        }
    }


    alias opDollar = length;


    void appendArrayElement(This element)
    {
        enforceUniNode(_kind == Kind.array,
                "'appendArrayElement' only allowed for array types, not "
                ~.to!string(_kind)~".");
        _array ~= element;
    }


    unittest
    {
        auto node = UniNode(1);
        auto anode = UniNode([node, node]);
        assert(anode.length == 2);
        anode.appendArrayElement(node);
        assert(anode.length == 3);
        assert(anode[$-1] == node);
    }


    inout(T) get(T)() inout @trusted if (isUniNodeType!(T, This))
    {
        try {
            static if (isSignedNumeric!T)
            {
                if (_kind == Kind.uinteger)
                    return cast(T)(_uint);
                checkType!T(Kind.integer);
                return cast(T)(_int);
            }
            else static if (isUnsignedNumeric!T)
            {
                if (_kind == Kind.integer)
                {
                    auto val = _int;
                    if (val >= 0)
                        return cast(T)(val);
                }
                checkType!T(Kind.uinteger);
                return cast(T)(_uint);
            }
            else static if (isFloatingPoint!T)
            {
                if (_kind == Kind.integer)
                    return cast(T)(_int);
                if (_kind == Kind.uinteger)
                    return cast(T)(_uint);

                checkType!T(Kind.floating);
                return cast(T)(_float);
            }
            else static if (isRawData!T)
            {
                checkType!T(Kind.raw);
                if (_kind == Kind.nil)
                    return inout(T).init;

                static if (isStaticArray!T)
                    return cast(inout(T))_raw[0..T.length];
                else
                    return cast(inout(T))_raw;
            }
            else static if (isSomeString!T)
            {
                if (_kind == Kind.raw)
                    return cast(T)_raw;
                else if (_kind == Kind.text)
                    return _string;
                else
                {
                    checkType!T(Kind.text);
                    return "";
                }
            }
            else static if (isBoolean!T)
            {
                checkType!T(Kind.boolean);
                return _bool;
            }
            else static if (isTraitsArray!T && is(ForeachType!T == This))
            {
                checkType!T(Kind.array);
                return _array;
            }
            else static if (isAssociativeArray!T
                    && is(ForeachType!T == This) && is(KeyType!T == string))
            {
                checkType!T(Kind.object);
                return _object;
            }
            else
                enforceUniNode(false);
        }
        catch (Throwable e)
            throw new UniNodeException(e.msg, e.file, e.line, e.next);
    }


    int opApply(int delegate(ref string idx, ref This obj) @safe dg)
    {
        enforceUniNode(_kind == Kind.object, "Expected " ~ This.stringof ~ " object");
        foreach (idx, ref v; _object)
        {
            if (auto ret = dg(idx, v))
                return ret;
        }
        return 0;
    }


    unittest
    {
        auto node = UniNode(1);
        auto mnode = UniNode(["one": node, "two": node]);
        assert (mnode.isObject);

        string[] keys;
        UniNode[] nodes;
        foreach (string key, ref UniNode node; mnode)
        {
            keys ~= key;
            nodes ~= node;
        }

        assert(keys == ["two", "one"]);
        assert(nodes.length == 2);
    }


    int opApply(scope int delegate(ref This obj) @safe dg)
    {
        enforceUniNode(_kind == Kind.array, "Expected " ~ This.stringof ~ " array");
        foreach (ref v; _array)
        {
            if (auto ret = dg(v))
                return ret;
        }
        return 0;
    }


    unittest
    {
        auto node = UniNode(1);
        auto mnode = UniNode([node, node]);
        assert (mnode.isArray);

        UniNode[] nodes;
        foreach (ref UniNode node; mnode)
            nodes ~= node;

        assert(nodes.length == 2);
    }


    bool opEquals(const This other) const
    {
        return opEquals(other);
    }


    bool opEquals(ref const This other) const
    {
        if (_kind != other.kind)
            return false;

        final switch (_kind) with (Kind)
        {
            case nil:
                return true;
            case boolean:
                return _bool == other._bool;
            case uinteger:
                return _uint == other._uint;
            case integer:
                return _int == other._int;
            case floating:
                return _float == other._float;
            case text:
                return _string == other._string;
            case raw:
                return _raw == other._raw;
            case array:
                return equal(_array, other._array);
            case object:
                return _object == other._object;
        }
    }


    unittest
    {
        auto n1 = UniNode(1);
        auto n2 = UniNode("1");
        auto n3 = UniNode(1);

        assert(n1 == n3);
        assert(n1 != n2);
        assert(n1 != UniNode(3));

        assert(UniNode([n1, n2, n3]) != UniNode([n2, n1, n3]));
        assert(UniNode([n1, n2, n3]) == UniNode([n1, n2, n3]));

        assert(UniNode(["one": n1, "two": n2]) == UniNode(["one": n1, "two": n2]));
    }


    ref inout(This) opIndex(size_t idx) inout
    {
        enforceUniNode(_kind == Kind.array, "Expected " ~ This.stringof ~ " array");
        return _array[idx];
    }


    unittest
    {
        auto arr = UniNode.emptyArray;
        foreach(i; 1..10)
            arr.appendArrayElement(UniNode(i));
        assert(arr[1] == UniNode(2));
    }


    ref This opIndex(string key)
    {
        enforceUniNode(_kind == Kind.object, "Expected " ~ This.stringof ~ " object");
        return _object[key];
    }


    unittest
    {
        UniNode[string] obj;
        foreach(i; 1..10)
            obj[i.to!string] = UniNode(i*i);

        UniNode node = UniNode(obj);
        assert(node["2"] == UniNode(4));
    }


    ref This opIndexAssign(This val, string key)
    {
        return opIndexAssign(val, key);
    }


    ref This opIndexAssign(ref This val, string key)
    {
        enforceUniNode(_kind == Kind.object, "Expected " ~ This.stringof ~ " object");
        return _object[key] = val;
    }


    unittest
    {
        UniNode node = UniNode.emptyObject;
        UniNode[string] obj;
        foreach(i; 1..10)
            node[i.to!string] = UniNode(i*i);

        assert(node["2"] == UniNode(4));
    }


    string toString()
    {
        auto buff = appender!string;

        void fun(ref UniNodeImpl!This node) @safe
        {
            switch (node.kind)
            {
                case Kind.nil:
                    buff.put("nil");
                    break;
                case Kind.boolean:
                    buff.put("bool("~node.get!bool.to!string~")");
                    break;
                case Kind.uinteger:
                    buff.put("uint("~node.get!ulong.to!string~")");
                    break;
                case Kind.integer:
                    buff.put("int("~node.get!long.to!string~")");
                    break;
                case Kind.floating:
                    buff.put("float("~node.get!double.to!string~")");
                    break;
                case Kind.text:
                    buff.put("text("~node.get!string.to!string~")");
                    break;
                case Kind.raw:
                    buff.put("raw("~node.get!(ubyte[]).to!string~")");
                    break;
                case Kind.object:
                {
                    buff.put("{");
                    size_t len = node.length;
                    size_t count;
                    foreach (ref string k, ref This v; node)
                    {
                        count++;
                        buff.put(k ~ ":");
                        fun(v);
                        if (count < len)
                            buff.put(", ");
                    }
                    buff.put("}");
                    break;
                }
                case Kind.array:
                {
                    buff.put("[");
                    size_t len = node.length;
                    size_t count;
                    foreach (i, v; node.get!(This[]))
                    {
                        count++;
                        fun(v);
                        if (count < len)
                            buff.put(", ");
                    }
                    buff.put("]");
                    break;
                }
                default:
                    buff.put("undefined");
                    break;
            }
        }

        fun(this);
        return buff.data;
    }


    unittest
    {
        auto obj = UniNode.emptyObject;

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

        assert(objNode.toString.length);
    }

    /**
     * cast to This type
     */
    inout(This) toThis() inout
    {
        return () @trusted { return cast(This)this; }();
    }

    /**
     * Check node is null
     */
    bool isNull() inout
    {
        return _kind == Kind.nil;
    }

    /**
     * Check node is object
     */
    bool isObject() inout
    {
        return _kind == Kind.object;
    }

    /**
     * Check node is array
     */
    bool isArray() inout
    {
        return _kind == Kind.array;
    }


    unittest
    {
        UniNode node;
        assert(node.isNull);
        assert(!node.isObject);
        assert(!node.isArray);

        node = UniNode.emptyObject;
        assert(!node.isNull);
        assert(node.isObject);
        assert(!node.isArray);

        node = UniNode.emptyArray;
        assert(!node.isNull);
        assert(!node.isObject);
        assert(node.isArray);
    }


private:


    void checkType(T)(Kind target) inout
    {
        enforceUniNode(_kind == target,
                fmt!("Trying to get %s but have %s.")(T.stringof, _kind));
    }
}


/**
 * UniNode error class
 */
class UniNodeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__,
            Throwable next = null) @safe
    {
        super(msg, file, line, next);
    }
}



template isUniNodeType(T, This)
{
    enum isUniNodeType = isUniNodeInnerType!T
        || isUniNodeArray!(T, This) || isUniNodeObject!(T, This);
}



template isUniNodeInnerType(T)
{
    enum isUniNodeInnerType = isNumeric!T || isBoolean!T || isSomeString!T
        || is(T == typeof(null)) || isRawData!T;
}



template isUniNodeArray(T, This)
{
    enum isUniNodeArray = isTraitsArray!T && is(Unqual!(ForeachType!T) == This);
}



template isUniNodeObject(T, This)
{
    enum isUniNodeObject = isAssociativeArray!T
        && is(Unqual!(ForeachType!T) == This) && is(KeyType!T == string);
}


private:


template TypeEnum(U)
{
	import std.array : join;
	mixin("enum TypeEnum { " ~ [FieldNameTuple!U].join(", ") ~ " }");
}


/**
 * Check for an integer signed number
 */
template isSignedNumeric(T)
{
    enum isSignedNumeric = isNumeric!T && isSigned!T && !isFloatingPoint!T;
}


/**
 * Check for an integer unsigned number
 */
template isUnsignedNumeric(T)
{
    enum isUnsignedNumeric = isNumeric!T && isUnsigned!T && !isFloatingPoint!T;
}


/**
 * Checking for binary data
 */
template isRawData(T)
{
    enum isRawData = isTraitsArray!T && is(Unqual!(ForeachType!T) == ubyte);
}



void enforceUniNode(T)(T value, lazy string msg = "UniNode exception",
        string file = __FILE__, size_t line = __LINE__) @safe
{
    if (!value)
        throw new UniNodeException(msg, file, line);
}

