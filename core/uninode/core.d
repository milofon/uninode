/**
 * The module contains the object UniNode
 *
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-08-14
 */

module uninode.core;



mixin template UniNodeMixin(This)
{
    private
    {
        import std.traits;
        import std.traits : isTraitsArray = isArray;
        import std.variant : maxSize;
        import std.format : fmt = format;
        import std.array : appender;
        import std.conv : to;
        import uninode.core;
    }

@safe:
    private nothrow
    {
        alias Bytes = immutable(ubyte)[];
        union U {
            typeof(null) nil;
            bool boolean;
            ulong uinteger;
            long integer;
            real floating;
            string text;
            Bytes raw;
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

        @property ref inout(Bytes) _raw() inout
        {
            return getDataAs!(Bytes)();
        }
    }


    alias Kind = TypeEnum!U;


    Kind kind() @property inout nothrow pure
    {
        return _kind;
    }


    this(typeof(null)) nothrow
    {
        _kind = Kind.nil;
    }

    /**
     * Check node is null
     */
    bool isNull() inout nothrow pure
    {
        return _kind == Kind.nil;
    }


    unittest
    {
        auto node = UniNode(null);
        assert (node.isNull);
        auto node2 = UniNode();
        assert (node2.isNull);
    }


    this(T)(T val) inout nothrow if (isUnsignedNumeric!T)
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


    this(T)(T val) inout nothrow if (isSignedNumeric!T)
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


    this(T)(T val) inout nothrow if (isBoolean!T)
    {
        _kind = Kind.boolean;
        (cast(bool)_bool) = val;
    }


    unittest
    {
        auto node = UniNode(true);
        assert (node.kind == UniNode.Kind.boolean);
        assert (node.get!bool == true);

        auto nodei = UniNode(0);
        assert (nodei.kind == UniNode.Kind.integer);
    }


    this(T)(T val) inout nothrow if (isFloatingPoint!T)
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


    this(T)(T val) inout nothrow if(isSomeString!T)
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


    this(T)(T val) inout nothrow if (isRawData!T)
    {
        _kind = Kind.raw;
        static if (isStaticArray!T || isMutable!T)
            (cast(Bytes)_raw) = val.idup;
        else
            (cast(Bytes)_raw) = val;
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

        Bytes bb = [1, 2, 3];
        node = UniNode(bb);
        assert (node.kind == UniNode.Kind.raw);
        assert (node.get!(ubyte[]) == [1, 2, 3]);
    }


    this(This[] val) nothrow
    {
        _kind = Kind.array;
        _array = val;
    }


    static This emptyArray() @property nothrow
    {
        return This(cast(This[])null);
    }

    /**
     * Check node is array
     */
    bool isArray() inout pure nothrow
    {
        return _kind == Kind.array;
    }


    unittest
    {
        auto node = UniNode.emptyArray;
        assert(node.isArray);
        assert(node.length == 0);
    }


    this(This[string] val) nothrow
    {
        _kind = Kind.object;
        _object = val;
    }


    static This emptyObject() @property nothrow
    {
        return This(cast(This[string])null);
    }

    /**
     * Check node is object
     */
    bool isObject() inout
    {
        return _kind == Kind.object;
    }


    unittest
    {
        auto node = UniNode.emptyObject;
        assert(node.isObject);
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


    inout(T) get(T)() inout @trusted if (isUniNodeType!(T))
    {
        static if (isSignedNumeric!T)
        {
            if (_kind == Kind.uinteger)
            {
                auto val = _uint;
                enforceUniNode(val < T.max, "Unsigned value great max");
                return cast(T)(val);
            }
            checkType!T(Kind.integer);
            return cast(T)(_int);
        }
        else static if (isUnsignedNumeric!T)
        {
            if (_kind == Kind.integer)
            {
                auto val = _int;
                enforceUniNode(val >= 0, "Signed value less zero");
                return cast(T)(val);
            }
            checkType!T(Kind.uinteger);
            return cast(T)(_uint);
        }
        else static if (isBoolean!T)
        {
            checkType!T(Kind.boolean);
            return _bool;
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
        else static if (isSomeString!T)
        {
            if (_kind == Kind.raw)
                return cast(T)_raw;
            checkType!T(Kind.text);
            return _string;
        }
        else static if (isRawData!T)
        {
            checkType!T(Kind.raw);
            static if (isStaticArray!T)
                return cast(inout(T))_raw[0..T.length];
            else
                return cast(inout(T))_raw;
        }
        else static if (isUniNodeArray!(T))
        {
            checkType!T(Kind.array);
            return _array;
        }
        else static if (isUniNodeObject!(T))
        {
            checkType!T(Kind.object);
            return _object;
        }
        else
            enforceUniNode(false, fmt!"Not support type '%s'"(T.stringof));
    }


    int opApply(F)(scope F dg)
    {
        auto fun = assumeSafe!F(dg);
        alias Params = Parameters!F;

        static if (Params.length == 1 && is(Unqual!(Params[0]) : This))
        {
            enforceUniNode(_kind == Kind.array,
                    "Expected " ~ This.stringof ~ " array");
            foreach (ref node; _array)
            {
                if (auto ret = fun(node))
                    return ret;
            }
        }
        else static if (Params.length == 2 && is(Unqual!(Params[1]) : This))
        {
            static if (isSomeString!(Params[0]))
            {
                enforceUniNode(_kind == Kind.object,
                        "Expected " ~ This.stringof ~ " object");
                foreach (string key, ref node; _object)
                {
                    if (auto ret = fun(key, node))
                        return ret;
                }
            }
            else
            {
                enforceUniNode(_kind == Kind.array,
                        "Expected " ~ This.stringof ~ " array");

                foreach (size_t key, ref node; _array)
                {
                    if (auto ret = fun(key, node))
                        return ret;
                }
            }
        }

        return 0;
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
                return _array == other._array;
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


    string toString()
    {
        auto buff = appender!string;

        void fun(ref This node) @safe
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
                    foreach (size_t i, ref This v; node)
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


    unittest
    {
        auto node = UniNode();
        assert (node.isNull);

        auto anode = UniNode([node, node]);
        assert (anode.isArray);

        auto mnode = UniNode(["one": node, "two": node]);
        assert (mnode.isObject);
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
            arr ~= UniNode(i);
        assert(arr[1] == UniNode(2));
    }


    ref inout(This) opIndex(string key) inout
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


    void opOpAssign(string op)(This[] elem) if (op == "~")
    {
        opOpAssign!op(UniNode(elem));
    }


    void opOpAssign(string op)(This elem) if (op == "~")
    {
        enforceUniNode(_kind == Kind.array, "Expected " ~ This.stringof ~ " array");
        if (elem.kind == Kind.array)
            _array ~= elem._array;
        else
            _array ~= elem;
    }


    unittest
    {
        auto node = UniNode(1);
        auto anode = UniNode([node, node]);
        assert(anode.length == 2);
        anode ~= node;
        anode ~= anode;
        assert(anode.length == 6);
        assert(anode[$-1] == node);
    }


    package template isUniNodeType(T)
    {
        enum isUniNodeType = isUniNodeInnerType!T
            || isUniNodeArray!(T) || isUniNodeObject!(T);
    }


private:


    void checkType(T)(Kind target) inout
    {
        enforceUniNode(_kind == target,
                fmt!("Trying to get %s but have %s.")(T.stringof, _kind));
    }


    template TypeEnum(U)
    {
        import std.array : join;
        mixin("enum TypeEnum : ubyte { " ~ [FieldNameTuple!U].join(", ") ~ " }");
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


    template isUniNodeInnerType(T)
    {
        enum isUniNodeInnerType = isNumeric!T || isBoolean!T || isSomeString!T
            || is(T == typeof(null)) || isRawData!T;
    }


    template isUniNodeArray(T)
    {
        enum isUniNodeArray = isTraitsArray!T && is(Unqual!(ForeachType!T) == This);
    }


    template isUniNodeObject(T)
    {
        enum isUniNodeObject = isAssociativeArray!T
            && is(Unqual!(ForeachType!T) == This) && is(KeyType!T == string);
    }


    auto assumeSafe(F)(F fun) @safe
        if (isFunctionPointer!F || isDelegate!F)
    {
        static if (hasFunctionAttributes!(F, "@safe"))
            return fun;
        else
        {
            enum attrs = (functionAttributes!F & ~FunctionAttribute.system)
                | FunctionAttribute.safe;
            return () @trusted {
                return cast(SetFunctionAttributes!(F, functionLinkage!F, attrs)) fun;
            } ();
        }
    }
}


/**
 * Universal structure for data storage of different types
 */
struct UniNode
{
@safe:
    mixin UniNodeMixin!UniNode;
}


/**
 * UniNode error class
 */
class UniNodeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__,
            Throwable next = null) @safe pure
    {
        super(msg, file, line, next);
    }
}


/**
 * Enforce UniNodeException
 */
void enforceUniNode(T)(T value, lazy string msg = "UniNode exception",
        string file = __FILE__, size_t line = __LINE__) @safe pure
{
    if (!value)
        throw new UniNodeException(msg, file, line);
}

