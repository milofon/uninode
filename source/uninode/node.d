/**
 * The module contains the object UniNode
 *
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2020-01-12
 */

module uninode.node;

private
{
    import std.algorithm.searching: canFind;
    import std.meta : AliasSeq, allSatisfy, staticMap;
    import std.format : fmt = format;
    import std.typecons : Tuple, Nullable;
    import std.exception : enforce;
    import std.string : capitalize;
    import std.conv : to, ConvOverflowException;
    import std.array : appender, join;
    import std.traits;
}


alias Bytes = immutable(ubyte)[];


/**
 * A [UniNode] implementation
 */
struct UniNodeImpl(Node)
{
    private pure nothrow @safe @nogc
    {
        union Storage
        {
            bool boolean;
            ulong uinteger;
            long integer;
            double floating;
            string text;
            Bytes raw;
            Node[] sequence;
            Node[string] mapping;
        }

        alias GetFieldPair(string F) = AliasSeq!(typeof(__traits(getMember, Storage, F)), F);
        alias Types = Tuple!(staticMap!(GetFieldPair, FieldNameTuple!Storage));
        alias AllTypes = Tuple!(staticMap!(GetFieldPair, FieldNameTuple!Storage),
                typeof(null), "nil");

        ref inout(T) _val(T)() inout pure nothrow @trusted @nogc
            if (isUniNodeType!(T, Node))
        {
            return __traits(getMember, _storage, Types.fieldNames[NodeTag!(Node, T)]);
        }

        Storage _storage;
        Tag _tag = Tag.nil;
    }

    /**
     * UniNodeImpl Tag
     */
    mixin("enum Tag : ubyte {" ~ [AllTypes.fieldNames].join(", ") ~ "}");

    /**
     * Check type node
     */
    bool can(Tag tag) inout pure nothrow @safe @nogc
    {
        return _tag == tag;
    }

    /**
     * Auto generage can functions
     */
    static foreach (string name; AllTypes.fieldNames)
    {
        /**
         * Check node is null
         */
        mixin("bool can", name.capitalize, `() inout pure nothrow @safe @nogc
        {
            return _tag == Tag.`, name, `;
        }`);
    }

    /**
     * Return tag Node
     */
    const(Tag) tag() inout pure nothrow @safe @nogc
    {
        return _tag;
    }

    /**
     * Constructs a UniNode
     */
    this(typeof(null)) inout pure nothrow @safe @nogc
    {
        _tag = Tag.nil;
    }

    /**
     * Constructs a UniNode
     *
     * Params:
     * value = ctor value
     */
    this(T)(auto ref T value) inout pure nothrow @trusted @nogc
        if (isUniNodeInnerType!(T) && !isRawData!T)
    {
        static if (isBoolean!T)
        {
            _storage.boolean = value;
            _tag = Tag.boolean;
        }
        else static if(isSignedNumeric!T)
        {
            _storage.integer = value;
            _tag = Tag.integer;
        }
        else static if(isUnsignedNumeric!T)
        {
            _storage.uinteger = value;
            _tag = Tag.uinteger;
        }
        else static if(isFloatingPoint!T)
        {
            _storage.floating = value;
            _tag = Tag.floating;
        }
        else static if(is(Unqual!T == string))
        {
            _storage.text = value;
            _tag = Tag.text;
        }
        else
            _tag = Tag.nil;
    }

    /**
     * Constructs a UniNode
     * with gc
     *
     * Params:
     * value = ctor value
     */
    this(T)(auto ref T value) inout pure nothrow @trusted
        if (isRawData!T || isUniNodeArray!(T, Node))
    {
        static if(isRawData!T)
        {
            static if (isStaticArray!T || isMutable!T)
                _storage.raw = value.idup;
            else
            {
                alias ST = typeof(_storage.raw);
                _storage.raw = cast(ST)value;
            }
            _tag = Tag.raw;
        }
        else static if (isUniNodeArray!(T, Node))
        {
            alias ST = typeof(_storage.sequence);
            _storage.sequence = cast(ST)value.dup;
            _tag = Tag.sequence;
        }
        else
            _tag = Tag.nil;
    }

    /**
     * Constructs a UniNode
     * with gc and throw
     *
     * Params:
     * value = ctor value
     */
    this(T)(auto ref T value) inout pure @trusted
        if (isUniNodeMapping!(T, Node))
    {
        alias ST = typeof(_storage.mapping);
        _storage.mapping = cast(ST)value.dup;
        _tag = Tag.mapping;
    }

    /**
     * Constructs a UniNode sequence from arguments
     *
     * Params:
     * value = ctor value
     */
    this(T...)(auto ref T value) inout pure nothrow @trusted
        if (T.length > 1 && allSatisfy!(isUniNodeInnerType, T))
    {
        alias ST = typeof(_storage.sequence);
        Node[] seq = new Node[value.length];
        static foreach (idx, val; value)
            seq[idx] = Node(val);
        _storage.sequence = cast(ST)seq;
        _tag = Tag.sequence;
    }

    /**
     * Construct empty Node sequence
     */
    static Node emptySequence() nothrow @safe
    {
        return Node(cast(Node[])null);
    }

    /**
     * Construct empty Node mapping
     */
    static Node emptyMapping() @safe
    {
        return Node(cast(Node[string])null);
    }

    /**
     * Convert UniNode to sequence
     */
    inout(Node[]) getSequence() inout pure @safe
    {
        enforceUniNode(can(Tag.sequence),
            fmt!("Trying to convert sequence but have %s.")(_tag), __FILE__, __LINE__);
        return _val!(inout(Node[]));
    }

    /**
     * Convert UniNode to mapping
     */
    inout(Node[string]) getMapping() inout pure @safe
    {
        enforceUniNode(can(Tag.mapping),
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        return _val!(inout(Node[string]));
    }

    /**
     * Convert UniNode to primitive type
     */
    inout(T) get(T)() inout pure @safe
    {
        T wrapTo(A)(auto ref A val) inout pure @safe
        {
            try
                return val.to!T;
            catch (ConvOverflowException e)
                throw new UniNodeException(e.msg);
        }

        void checkTag(T)(Tag target, string file = __FILE__, size_t line = __LINE__)
            inout pure @safe
        {
            enforceUniNode(_tag == target,
                fmt!("Trying to convert %s but have %s.")(T.stringof, _tag), file, line);
        }

        static if (isSignedNumeric!T)
        {
            if (canUinteger)
            {
                immutable val = _val!ulong;
                enforceUniNode(val < T.max, "Unsigned value great max");
                return wrapTo(val);
            }
            checkTag!T(Tag.integer);
            immutable val = _val!long;
            return wrapTo(val);
        }
        else static if (isUnsignedNumeric!T)
        {
            if (canInteger)
            {
                immutable val = _val!long;
                enforceUniNode(val >= 0, "Signed value less zero");
                return wrapTo(val);
            }
            checkTag!T(Tag.uinteger);
            immutable val = _val!ulong;
            return wrapTo(val);
        }
        else static if (isBoolean!T)
        {
            if (canUinteger)
                return _val!ulong != 0;
            if (canInteger)
                return _val!long != 0;
            else
            {
                checkTag!T(Tag.boolean);
                return _val!bool;
            }
        }
        else static if (isFloatingPoint!T)
        {
            if (canUinteger)
            {
                immutable val = _val!ulong;
                return wrapTo(val);
            }
            if (canInteger)
            {
                immutable val = _val!long;
                return wrapTo(val);
            }
            else
            {
                checkTag!T(Tag.floating);
                return _val!double;
            }
        }
        else static if (is(T == string))
        {
            if (canRaw)
                return cast(string)_val!Bytes;
            checkTag!T(Tag.text);
            return _val!string.to!T;
        }
        else static if (isRawData!T)
        {
            checkTag!T(Tag.raw);
            immutable val = _val!Bytes;
            static if (isStaticArray!T)
                return cast(inout(T))val[0..T.length];
            else
                return val.to!T;
        }
        else static if (isUniNodeArray!(T, Node))
            return getSequence();
        else static if (isUniNodeMapping!(T, Node))
            return getMapping();
        else
            throw new UniNodeException(fmt!"Not support type '%s'"(T.stringof));
    }

    /**
     * Convert UniNode to optional primitive type
     */
    Nullable!(const(T)) opt(T)() const pure nothrow @safe
    {
        alias RT = Nullable!(const(T));
        try
            return RT(get!T);
        catch (Exception e)
            return RT.init;
    }

    /**
     * Convert UniNode to optional primitive type
     */
    Nullable!(T) opt(T)() pure nothrow @safe
    {
        alias RT = Nullable!(T);
        try
            return RT(get!T);
        catch (Exception e)
            return RT.init;
    }

    /**
     * Convert UniNode to primitive type or return alternative value
     */
    inout(T) getOrElse(T)(T alt) inout pure nothrow @safe
    {
        try
            return get!T;
        catch (Exception e)
            return alt;
    }

    /**
     * Convert UniNode to optional sequence
     */
    Nullable!(const(Node[])) optSequence() const pure nothrow @safe
    {
        alias RT = Nullable!(const(Node[]));
        try
            return RT(getSequence());
        catch (Exception e)
            return RT.init;
    }

    /**
     * Convert UniNode to optional sequence
     */
    Nullable!(Node[]) optSequence() pure nothrow @safe
    {
        alias RT = Nullable!(Node[]);
        try
            return RT(getSequence());
        catch (Exception e)
            return RT.init;
    }

    /**
     * Convert UniNode to optional mapping
     */
    Nullable!(const(Node[string])) optMapping() const pure nothrow @safe
    {
        alias RT = Nullable!(const(Node[string]));
        try
            return RT(getMapping());
        catch (Exception e)
            return RT.init;
    }

    /**
     * Convert UniNode to optional mapping
     */
    Nullable!(Node[string]) optMapping() pure nothrow @safe
    {
        alias RT = Nullable!(Node[string]);
        try
            return RT(getMapping());
        catch (Exception e)
            return RT.init;
    }

    /**
     * Implement index operator by Node array
     */
    inout(Node) opIndex(size_t idx) inout @safe
    {
        enforceUniNode(can(Tag.sequence),
            fmt!("Trying to convert sequence but have %s.")(_tag), __FILE__, __LINE__);
        return _val!(inout(Node[]))[idx];
    }

    /**
     * Implement index operator by Node object
     */
    inout(Node) opIndex(string key) inout @safe
    {
        enforceUniNode(can(Tag.mapping),
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        return _val!(inout(Node[string]))[key];
    }

    /**
     * Implement index assign operator by Node sequence
     */
    void opIndexAssign(T)(auto ref T val, size_t idx) @safe
        if (isUniNodeInnerType!T || isUniNode!T)
    {
        enforceUniNode(can(Tag.sequence),
            fmt!("Trying to convert sequence but have %s.")(_tag), __FILE__, __LINE__);
        static if (isUniNode!T)
            _val!(inout(Node[]))[idx] = val;
        else
            _val!(inout(Node[]))[idx] = Node(val);
    }

    /**
     * Implement index assign operator by Node mapping
     */
    void opIndexAssign(T)(auto ref T val, string key) @safe
        if (isUniNodeInnerType!T || isUniNode!T)
    {
        enforceUniNode(can(Tag.mapping),
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        static if (isUniNode!T)
            _val!(inout(Node[string]))[key] = val;
        else
            _val!(inout(Node[string]))[key] = Node(val);
    }

    /**
     * Implement operator ~= by UniNode array
     */
    void opOpAssign(string op)(auto ref Node elem) @safe
        if (op == "~")
    {
        enforceUniNode(can(Tag.sequence),
            fmt!("Trying to convert sequence but have %s.")(_tag), __FILE__, __LINE__);
        _val!(Node[]) ~= elem;
    }

    /**
     * Implement operator ~= by UniNode array
     */
    void opOpAssign(string op)(auto ref Node[] elem) @safe
        if (op == "~")
    {
        opOpAssign!op(Node(elem));
    }

    /**
     * Particular keys in an Node can be removed with the remove
     */
    void remove(string key) @safe
    {
        enforceUniNode(can(Tag.mapping),
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        _val!(Node[string]).remove(key);
    }

    /**
     * Inserting if not present
     */
    Node require(T)(string key, auto ref T val) @safe
        if (isUniNodeInnerType!T || isUniNode!T)
    {
        enforceUniNode(can(Tag.mapping),
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        if (auto ret = key in _val!(Node[string]))
            return *ret;
        else
        {
            static if (isUniNode!T)
                return _val!(Node[string])[key] = val;
            else
                return _val!(Node[string])[key] = Node(val);
        }
    }

    /**
     * Implement operator in for mapping
     */
    inout(Node)* opBinaryRight(string op)(string key) inout @safe
        if (op == "in")
    {
        enforceUniNode(_tag == Tag.mapping,
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        return key in _val!(inout(Node[string]));
    }

    /**
     * Iteration by Node mapping
     */
    int opApply(D)(D dg) inout
        if (isCallable!D && (Parameters!D.length == 1 && isUniNode!(Parameters!D[0]))
                || (Parameters!D.length == 2 && isUniNode!(Parameters!D[1])))
    {
        alias Params = Parameters!D;

        ref P toDelegateParam(P)(ref inout(Node) node) @trusted
        {
            return *(cast(P*)&node);
        }

        static if (Params.length == 1 && isUniNode!(Params[0]))
        {
            foreach (ref inout(Node) node; _val!(inout(Node[]))())
            {
                if (auto ret = dg(toDelegateParam!(Params[0])(node)))
                    return ret;
            }
        }
        else static if (Params.length == 2 && isUniNode!(Params[1]))
        {
            static if (isSomeString!(Params[0]))
            {
                foreach (Params[0] key, ref inout(Node) node; _val!(inout(Node[string]))())
                    if (auto ret = dg(key, toDelegateParam!(Params[1])(node)))
                        return ret;
            }
            else
            {
                foreach (Params[0] key, ref inout(Node) node; _val!(inout(Node[])))
                    if (auto ret = dg(key, toDelegateParam!(Params[1])(node)))
                        return ret;
            }
        }
        return 0;
    }

    /**
     * Returns the hash of the `Node`'s current value.
     */
    size_t toHash() const nothrow @trusted
    {
        final switch (_tag)
        {
            static foreach (tid, T; AllTypes.Types)
            {
                case tid:
                    static if (is(T == typeof(null)))
                        return typeid(T).getHash(null);
                    else
                    {
                        auto val = _val!T;
                        return typeid(T).getHash(&val);
                    }
            }
        }
    }

    /**
     * Returns the length sequence types
     */
    size_t length() const pure @property
    {
        return this.match!(
                (string val) => val.length,
                (Bytes val) => val.length,
                (const(Node)[] val) => val.length,
                (const(Node[string]) val) => val.length,
                () { throw new UniNodeException("Expected " ~ Node.stringof ~ " not length"); }
            );
    }

    /**
     * Compares two `UniNode`s for equality.
     */
    bool opEquals()(auto ref const(Node) rhs) const @safe
    {
        return this.match!((value) {
                return rhs.match!((rhsValue) {
                    static if (is(typeof(value) == typeof(rhsValue)))
                        return value == rhsValue;
                    else static if (isNumeric!(typeof(value))
                            && isNumeric!(typeof(rhsValue)))
                        return value == rhsValue;
                    else
                        return false;
                });
            });
    }

    /**
     * Returns string representaion
     */
    string toString() const @safe
    {
        auto buff = appender!string;

        void toStringNode(UniNodeImpl!Node node) @safe const
        {
            node.match!(
                    (bool v) => buff.put(fmt!"bool(%s)"(v)),
                    (long v) => buff.put(fmt!"int(%s)"(v)),
                    (ulong v) => buff.put(fmt!"uint(%s)"(v)),
                    (double v) => buff.put(fmt!"float(%s)"(v)),
                    (string v) => buff.put(fmt!"text(%s)"(v)),
                    (Bytes v) => buff.put(fmt!"raw(%s)"(v)),
                    (const(Node)[] v) {
                        buff.put("[");
                        const len = v.length;
                        size_t count;
                        foreach (ref const(Node) nodeV; v)
                        {
                            count++;
                            toStringNode(nodeV);
                            if (count < len)
                                buff.put(", ");
                        }
                        buff.put("]");
                    },
                    (const(Node[string]) v) {
                        buff.put("{");
                        const len = v.length;
                        size_t count;
                        foreach (string key, ref const(Node) nodeV; v)
                        {
                            count++;
                            buff.put(key ~ ":");
                            toStringNode(nodeV);
                            if (count < len)
                                buff.put(", ");
                        }
                        buff.put("}");
                    },
                    () => buff.put("nil")
                );
        }

        toStringNode(this);
        return buff.data;
    }
}


/**
 * A [UniNode] struct
 */
struct UniNode
{
    private
    {
        alias Node = UniNodeImpl!UniNode;
        alias node this;
    }

    /**
     * Node implementation
     */
    Node node;

    /**
     * Common constructor
     */
    this(T)(auto ref T val) inout pure nothrow @safe @nogc
        if ((isUniNodeInnerType!T && !isRawData!T) || is (T == typeof(null)))
    {
        node = Node(val);
    }

    /**
     * Common constructor
     */
    this(T)(auto ref T val) inout pure nothrow @safe
        if (isRawData!T || isUniNodeArray!(T, Node))
    {
        node = Node(val);
    }

    /**
     * Common constructor
     */
    this(T)(auto ref T val) inout pure @safe
        if (isUniNodeMapping!(T, Node))
    {
        node = Node(val);
    }

    /**
     * Sequence constructor
     */
    this(T...)(auto ref T val) inout pure nothrow @safe
        if (T.length > 0 && allSatisfy!(isUniNodeInnerType, T))
    {
        node = Node(val);
    }

    /**
     * Compares two `UniNode`s for equality.
     */
    bool opEquals(const(UniNode) rhs) const pure @safe
    {
        return node.opEquals(rhs);
    }

    /**
     * Returns the hash of the `UniNode`'s current value.
     */
    size_t toHash() const nothrow @safe
    {
        return node.toHash();
    }
}


/**
 * Thrown when an unhandled type is encountered.
 */
class UniNodeException : Exception
{
    /**
     * common constructor
     */
    pure nothrow @safe @nogc
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}


/**
 * Calls a type-appropriate function with the value held in a [UniNode].
 */
template match(handlers...)
    if (handlers.length)
{
    /**
     * The actual `match` function.
     *
     * Params:
     *   self = A [UniNode] object
     */
    auto match(Node)(auto ref Node node)
        if (is(Node : UniNodeImpl!Th, Th))
    {
        return matchImpl!(handlers)(node);
    }
}


/**
 * Checking is UniNode
 */
template isUniNode(T)
{
    alias UT = Unqual!T;
    static if (__traits(compiles, is(UT : UniNodeImpl!UT)))
        enum isUniNode = is(UT : UniNodeImpl!UT);
    else
        enum isUniNode = false;
}

@("Checking is UniNode")
@safe unittest
{
    alias UniUni = UniNode;
    assert (isUniNode!UniUni);
    assert (isUniNode!UniNode);
    assert (!isUniNode!int);
    assert (isUniNode!(const(UniNode)));
}


package:


alias enforceUniNode = enforce!UniNodeException;


/**
 * Checking for uninode
 */
template isUniNodeType(T, N)
{
    enum isUniNodeType = isUniNodeInnerType!T
        || isUniNodeArray!(T, N) || isUniNodeMapping!(T, N);
}

@("Checking for uninode type")
@safe unittest
{
    static foreach(T; Fields!(UniNode.Storage))
        assert(isUniNodeType!(T, UniNode), "Type " ~ T.stringof ~ " not UniNode");
}


/**
 * Checking for inner types
 */
template isUniNodeInnerType(T)
{
    alias TU = Unqual!T;
    enum isUniNodeInnerType = isNumeric!TU || isBoolean!TU ||
            is(TU == string) || isRawData!TU;
}

@("Checking for inner types")
@safe unittest
{
    static foreach(T; AliasSeq!(int, long, uint, ulong, bool, string))
        assert (isUniNodeInnerType!(T));
    assert (isUniNodeInnerType!string);
    assert (!isUniNodeInnerType!(typeof(null)));
}


/**
 * Checking for binary data
 */
template isRawData(T)
{
    enum isRawData = isArray!T && is(Unqual!(ForeachType!T) == ubyte);
}

@("Checking for binary data")
@safe unittest
{
    assert (isRawData!(Bytes));
}


/**
 * Checking for array
 */
template isUniNodeArray(T, N)
{
    enum isUniNodeArray = isArray!T && is(Unqual!(ForeachType!T) : Unqual!N);
}

@("Checking for array")
@safe unittest
{
    assert (isUniNodeArray!(UniNode[], UniNode));
}


/**
 * Checking for object
 */
template isUniNodeMapping(T, N)
{
    enum isUniNodeMapping = isAssociativeArray!T
        && is(Unqual!(ForeachType!T) : Unqual!N) && is(KeyType!T == string);
}

@("Checking for object")
@safe unittest
{
    assert (isUniNodeMapping!(UniNode[string], UniNode));
}


private:


/**
 * True if `handler` is a potential match for `T`, otherwise false.
 */
enum bool canMatch(alias handler, T) = is(typeof((T arg) => handler(arg)));

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


@("Checking all types")
@safe unittest
{
    assert(allSatisfy!(isCopyable, UniNode.Storage));
    assert(!allSatisfy!(hasElaborateCopyConstructor, UniNode.Storage));
    assert(!allSatisfy!(hasElaborateDestructor, UniNode.Storage));
}


/**
 * Checking for an integer signed number
 */
template isSignedNumeric(T)
{
    enum isSignedNumeric = isNumeric!T && isSigned!T && !isFloatingPoint!T;
}

@("Checking for an integer signed number")
@safe unittest
{
    static foreach(T; AliasSeq!(byte, int, short, long))
        assert(isSignedNumeric!T);
}


/**
 * Checking for an integer unsigned number
 */
template isUnsignedNumeric(T)
{
    enum isUnsignedNumeric = isUnsigned!T && !isFloatingPoint!T;
}

@("Checking for an integer unsigned number")
@safe unittest
{
    static foreach(T; AliasSeq!(ubyte, uint, ushort, ulong))
        assert(isUnsignedNumeric!T);
}


/**
 * Language type to uninode inner tag
 */
template NodeTag(Node, T)
    if (isUniNodeType!(T, Node))
{
    static if (isBoolean!T)
        enum NodeTag = Node.Tag.boolean;
    else static if (isSignedNumeric!T)
        enum NodeTag = Node.Tag.integer;
    else static if (isUnsignedNumeric!T)
        enum NodeTag = Node.Tag.uinteger;
    else static if (isFloatingPoint!T)
        enum NodeTag = Node.Tag.floating;
    else static if (isSomeString!T)
        enum NodeTag = Node.Tag.text;
    else static if (isRawData!T)
        enum NodeTag = Node.Tag.raw;
    else static if (isUniNodeArray!(T, Node))
        enum NodeTag = Node.Tag.sequence;
    else static if (isUniNodeMapping!(T, Node))
        enum NodeTag = Node.Tag.mapping;
    else
        enum NodeTag = Node.Tag.nil;
}

@("NodeTag test")
@safe unittest
{
    static assert (NodeTag!(UniNode, bool) == UniNode.Tag.boolean);
    static assert (NodeTag!(UniNode, int) == UniNode.Tag.integer);
    static assert (NodeTag!(UniNode, uint) == UniNode.Tag.uinteger);
    static assert (NodeTag!(UniNode, float) == UniNode.Tag.floating);
    static assert (NodeTag!(UniNode, string) == UniNode.Tag.text);
    static assert (NodeTag!(UniNode, ubyte[]) == UniNode.Tag.raw);
    static assert (NodeTag!(UniNode, UniNode[]) == UniNode.Tag.sequence);
    static assert (NodeTag!(UniNode, UniNode[string]) == UniNode.Tag.mapping);
}


/**
 * Match implementation
 */
template matchImpl(handlers...)
    if (handlers.length)
{
    // Converts an unsigned integer to a compile-time string constant.
    enum toCtString(ulong n) = n.stringof[0 .. $ - 2];

    auto matchImpl(Node)(auto ref Node node)
        if (is(Node : UniNodeImpl!T, T))
    {
        alias AllTypes = Node.AllTypes.Types;
        enum MatchType : ubyte { NO, TPL, FUN, EMP }
        struct Match
        {
            MatchType type;
            size_t hid;
            ubyte dist;
        }

        enum defaultMatch = Match(MatchType.NO, 0, ubyte.max);

        template HandlerMatch(alias handler, size_t hid, T)
        {
            static if (isCallable!handler)
            {
                alias params = Parameters!handler;
                static if (params.length == 1)
                {
                    enum dist = GetDistance!(Node, T, params[0]);
                    enum type = dist < ubyte.max ? MatchType.FUN : MatchType.NO;
                    enum HandlerMatch = Match(type, hid, dist);
                }
                else static if (params.length == 0)
                    enum HandlerMatch = Match(MatchType.EMP, hid, ubyte.max);
                else
                    enum HandlerMatch = defaultMatch;
            }
            else static if (canMatch!(handler, T))
                enum HandlerMatch = Match(MatchType.TPL, hid, ubyte.max-1);
            else
                enum HandlerMatch = defaultMatch;
        }

        enum matches = () {
            Match[AllTypes.length] matches;

            foreach (tid, T; AllTypes)
            {
                foreach (hid, handler; handlers)
                {
                    enum m = HandlerMatch!(handler, hid, T);
                    if (matches[tid].type != MatchType.NO)
                    {
                        if (matches[tid].dist > m.dist)
                            matches[tid] = m;
                    }
                    else
                        matches[tid] = m;
                }
            }
            return matches;
        } ();

        // Check for unreachable handlers
        static foreach(hid, handler; handlers)
        {
            static assert(matches[].canFind!(m => m.type != MatchType.NO && m.hid == hid),
                "handler #" ~ toCtString!hid ~ " " ~
                "of type `" ~ ( __traits(isTemplate, handler)
                    ? "template"
                    : typeof(handler).stringof
                ) ~ "` " ~
                "never matches"
            );
        }

        // Workaround for dlang issue 19993
        static foreach (size_t hid, handler; handlers) {
            mixin("alias handler", toCtString!hid, " = handler;");
        }

        final switch (node._tag)
        {
            static foreach (tid, T; AllTypes)
            {
                case tid:
                    static if (matches[tid].type == MatchType.TPL)
                        static if (is(T == typeof(null)))
                            return mixin("handler",
                                toCtString!(matches[tid].hid))(null);
                        else
                            return mixin("handler",
                                toCtString!(matches[tid].hid))(node.get!T);
                    else static if (matches[tid].type == MatchType.EMP)
                    {
                        alias h = handlers[matches[tid].hid];
                        static if (is(ReturnType!h == void))
                        {
                            mixin("handler", toCtString!(matches[tid].hid))();
                            return 0;
                        }
                        else
                            return mixin("handler", toCtString!(matches[tid].hid))();
                    }
                    else static if (matches[tid].type == MatchType.FUN)
                    {
                        alias h = handlers[matches[tid].hid];
                        alias PT = Unqual!(Parameters!h[0]);
                        static if (is(ReturnType!h == void))
                        {
                            static if (isUniNodeArray!(PT, Node) || isUniNodeMapping!(PT, Node))
                                mixin("handler",
                                    toCtString!(matches[tid].hid))(node._val!T);
                            else
                                mixin("handler",
                                    toCtString!(matches[tid].hid))(node.get!(PT));
                            return 0;
                        }
                        else
                        {
                            static if (isUniNodeArray!(PT, Node) && isUniNodeMapping!(PT, Node))
                                return mixin("handler",
                                    toCtString!(matches[tid].hid))(node._val!(T));
                            else
                                return mixin("handler",
                                    toCtString!(matches[tid].hid))(node.get!(PT));
                        }
                    }
                    else
                    {
                        static if(exhaustive)
                            static assert(false,
                                "No matching handler for type `" ~ T.stringof ~ "`");
                        else
                            throw new MatchException(
                                "No matching handler for type `" ~ T.stringof ~ "`");
                    }
            }
        }

        assert (false);
    }
}


/**
 * Get distande by types
 */
template GetDistance(Node, Org, Trg)
    if (isUniNodeType!(Org, Node) || is (Org == typeof(null)))
{
    static if (isBoolean!Org && isBoolean!Trg)
        enum GetDistance = 0;
    else static if (isSignedNumeric!Org && isSignedNumeric!Trg)
        enum GetDistance = Org.sizeof - Trg.sizeof;
    else static if (isUnsignedNumeric!Org && isUnsignedNumeric!Trg)
        enum GetDistance = Org.sizeof - Trg.sizeof;
    else static if (isFloatingPoint!Org && isFloatingPoint!Trg)
        enum GetDistance = Org.sizeof - Trg.sizeof;
    else static if (is(Org == string) && is (Trg == string))
        enum GetDistance = 0;
    else static if (isRawData!Org && isRawData!Trg)
        enum GetDistance = 0;
    else static if (isUniNodeArray!(Org, Node) && isUniNodeArray!(Trg, Node))
        enum GetDistance = 0;
    else static if (isUniNodeMapping!(Org, Node) && isUniNodeMapping!(Trg, Node))
        enum GetDistance = 0;
    else static if (is(Org == typeof(null)) && is(Trg == typeof(null)))
        enum GetDistance = 0;
    else
        enum GetDistance = ubyte.max;
}


auto assumeSafe(F)(F fun)
    if (isFunctionPointer!F || isDelegate!F)
{
    static if (functionAttributes!F & FunctionAttribute.safe)
        return fun;
    else
        return (ParameterTypeTuple!F args) @trusted {
            return fun(args);
        };
}

