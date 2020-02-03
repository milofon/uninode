/**
 * The module contains the object UniNode
 *
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2020-01-12
 */

module uninode.core;

private
{   
    import std.algorithm.searching: canFind;
    import std.meta : AliasSeq, allSatisfy;
    import std.format : fmt = format;
    import std.typecons : Flag, No, Yes;
    import std.exception : enforce;
    import std.string : capitalize;
    import std.conv : to, ConvOverflowException;
    import std.array : appender;
    import std.traits;
}


alias Bytes = immutable(ubyte)[];


/**
 * A [UniNode] implementation
 */
struct UniNodeImpl(Node)
{
    @safe private nothrow pure
    {
        union Storage
        {
            typeof(null) nil;
            bool boolean;
            ulong uinteger;
            long integer;
            double floating;
            string text;
            Bytes raw;
            const(Node)[] sequence;
            const(Node)[string] mapping;
        }

        alias Tag = TypeEnum!Storage;
        alias Names = FieldNameTuple!Storage;

        ref inout(T) _val(T)() inout @trusted
            if (isUniNodeType!(T, Node))
        {
            return __traits(getMember, _storage, Names[ToNodeTag!(Node, T)]);
        }

        Storage _storage;
        Tag _tag;
    }

    /**
     * Constructs a UniNode
     *
     * Params:
     * value = ctor value
     */
    this(T)(auto ref T value) pure inout nothrow
        if (isUniNodeInnerType!T)
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
        else static if(is(T == string))
        {
            _storage.text = value;
            _tag = Tag.text;
        }
        else static if(isRawData!T)
        {
            static if (isStaticArray!T || isMutable!T)
                _storage.raw = value.idup;
            else
                _storage.raw = value;

            _tag = Tag.raw;
        }
        else
            _tag = Tag.nil;
    }

    /**
     * Constructs a UniNode from sequence
     *
     * Params:
     * value = ctor value
     */
    this(T)(auto ref T[] value) pure inout nothrow @trusted
        if(is (T : Node))
    {
        _storage.sequence = cast(inout)value;
        _tag = Tag.sequence;
    }

    /**
     * Constructs a UniNode from mapping
     *
     * Params:
     * value = ctor value
     */
    this(T)(auto ref inout(T[string]) value) pure inout nothrow @trusted
        if(is (T : Node))
    {
        _storage.mapping = cast(inout)value;
        _tag = Tag.mapping;
    }

    /**
     * Constructs a UniNode sequence from arguments
     *
     * Params:
     * value = ctor value
     */
    this(T...)(auto ref T value) pure inout nothrow @trusted
        if (T.length > 1)
    {
        Node[] seq = new Node[value.length];
        foreach (idx, val; value)
            seq[idx] = Node(val);
        _storage.sequence = cast(inout)seq;
        _tag = Tag.sequence;
    }

    /**
     * Auto generage can functions
     */
    static foreach (string name; Names)
    {
        /**
         * Check node is null
         */
        mixin("bool can", name.capitalize, `() pure inout nothrow
        {
            return _tag == Tag.`, name, `;
        }`);
    }

    /**
     * Convert UniNode to primitive type
     */
    inout(T) convertTo(T)() inout @trusted
    {
        static if (isSignedNumeric!T)
        {
            if (canUinteger)
            {
                immutable val = _val!ulong;
                enforceUniNode(val < T.max, "Unsigned value great max");
                return wrapTo!T(val);
            }
            checkTag!T(Tag.integer);
            immutable val = _val!long;
            return wrapTo!T(val);
        }
        else static if (isUnsignedNumeric!T)
        {
            if (canInteger)
            {
                immutable val = _val!long;
                enforceUniNode(val >= 0, "Signed value less zero");
                return wrapTo!T(val);
            }
            checkTag!T(Tag.uinteger);
            immutable val = _val!ulong;
            return wrapTo!T(val);
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
                return wrapTo!T(val);
            }
            if (canInteger)
            {
                immutable val = _val!long;
                return wrapTo!T(val);
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
                return cast(inout(T))val;
        }
        else static if (isUniNodeArray!(T, Node))
            return convertToSequence();
        else static if (isUniNodeMapping!(T, Node))
            return convertToMapping();
        else
            throw new UniNodeException(fmt!"Not support type '%s'"(T.stringof));
    }

    /**
     * Convert UniNode to sequence
     */
    inout(const(Node)[]) convertToSequence() inout @trusted
    {
        enforceUniNode(_tag == Tag.sequence,
            fmt!("Trying to convert sequence but have %s.")(_tag), __FILE__, __LINE__);
        return _val!(const(Node)[]);
    }

    /**
     * Convert UniNode to mapping
     */
    inout(const(Node)[string]) convertToMapping() inout @trusted
    {
        enforceUniNode(_tag == Tag.mapping,
            fmt!("Trying to convert mapping but have %s.")(_tag), __FILE__, __LINE__);
        return _val!(const(Node)[string]);
    }

	/**
	 * Compares two `UniNode`s for equality.
	 */
    bool opEquals()(auto ref const(UniNode) rhs) const
    {
        return this.match!((ref value) {
                return rhs.match!((ref rhsValue) {
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
     * Returns the hash of the `UniNode`'s current value.
     *
     * Not available when compiled with `-betterC`.
     */
    size_t toHash() const
    {
        return this.match!hashOf;
    }

    /**
     * Returns the length sequence types
     */
    size_t length() const @property
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

private:


    inout(T) wrapTo(T, A)(auto ref A val) inout pure
    {
        try
            return val.to!T;
        catch (ConvOverflowException e)
            throw new UniNodeException(e.msg);
    }


    void checkTag(T)(Tag target, string file = __FILE__, size_t line = __LINE__) inout
    {
        enforceUniNode(_tag == target,
            fmt!("Trying to convert %s but have %s.")(T.stringof, _tag), file, line);
    }
}


/**
 * A [UniNode] struct
 */
struct UniNode
{
@safe nothrow pure:
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
    this(T)(auto ref T val) inout pure
    {
        node = Node(val);
    }

    /**
     * Sequence constructor
     */
    this(T...)(auto ref T val) inout pure
    {
        node = Node(val);
    }

	/**
	 * Compares two `UniNode`s for equality.
	 */
    bool opEquals()(auto ref const(UniNode) rhs) inout
    {
        return node.opEquals(rhs);
    }

    /**
     * Returns the hash of the `UniNode`'s current value.
     *
     * Not available when compiled with `-betterC`.
     */
    size_t toHash() const
    {
        return node.toHash();
    }
}


/**
 * Thrown by [tryMatch] when an unhandled type is encountered.
 *
 * Not available when compiled with `-betterC`.
 */
version (D_Exceptions)
class UniNodeException : Exception
{
    /**
     * common constructor
     */
    pure @safe @nogc nothrow
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}


version (D_Exceptions)
alias enforceUniNode = enforce!UniNodeException;


/**
 * True if `handler` is a potential match for `T`, otherwise false.
 */
enum bool canMatch(alias handler, T) = is(typeof((T arg) => handler(arg)));


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
        return node.matchImpl!(Yes.exhaustive,  handlers);
    }
}


/**
 * Attempts to call a type-appropriate function with the value held in a
 * [UniNode], and throws on failure.
 */
version (D_Exceptions)
template tryMatch(handlers...)
    if (handlers.length)
{
	/**
	 * The actual `tryMatch` function.
	 *
	 * Params:
	 *   self = A [UniNode] object
	 */
    auto tryMatch(Node)(auto ref Node node)
        if (is(Node : UniNodeImpl!Th, Th))
    {
        return node.matchImpl!(No.exhaustive, handlers);
    }
}


/**
 * Convert Node array to Node sequence
 *
 * Params:
 * arr = Node array
 */
Node toSequence(Node)(Node[] arr)
    if (is(Node : UniNodeImpl!Th, Th))
{
    return Node(arr);
}


/**
 * Convert Node associative array to Node mapping
 *
 * Params:
 * aarr = Node associative array
 */
Node toMapping(Node)(Node[string] aarr)
    if (is(Node : UniNodeImpl!Th, Th))
{
    return Node(aarr); 
}


private:


// Converts an unsigned integer to a compile-time string constant.
enum toCtString(ulong n) = n.stringof[0 .. $ - 2];


/**
 * Generate TypeEnum
 */
template TypeEnum(U)
{
    import std.array : join;
    mixin("enum TypeEnum : ubyte { " ~ [FieldNameTuple!U].join(", ") ~ " }");
}


@("Checking all types")
@safe unittest
{
    assert(allSatisfy!(isCopyable, UniNode.Storage));
    assert(!allSatisfy!(hasElaborateCopyConstructor, UniNode.Storage));
    assert(!allSatisfy!(hasElaborateDestructor, UniNode.Storage));
}


/**
 * Checking for uninode
 */
template isUniNodeType(T, This)
{
    enum isUniNodeType = isUniNodeInnerType!T
        || isUniNodeArray!(T, This) || isUniNodeMapping!(T, This);
}

@("Checking for uninode")
@safe unittest
{
    static foreach(T; Fields!(UniNode.Storage))
        assert(isUniNodeType!(T, UniNode), "Type " ~ T.stringof ~ " not UniNode");
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
    enum isUnsignedNumeric = isNumeric!T && isUnsigned!T && !isFloatingPoint!T;
}

@("Checking for an integer unsigned number")
@safe unittest
{
    static foreach(T; AliasSeq!(ubyte, uint, ushort, ulong))
        assert(isUnsignedNumeric!T);
}


/**
 * Checking for inner types
 */
template isUniNodeInnerType(T)
{
    enum isUniNodeInnerType = isNumeric!T || isBoolean!T || is(T == string)
        || is(T == typeof(null)) || isRawData!T;
}

@("Checking for inner types")
@safe unittest
{
    static foreach(T; AliasSeq!(typeof(null), int, long, uint, ulong, bool, string))
        assert (isUniNodeInnerType!(T));
    assert (isUniNodeInnerType!string);
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
template isUniNodeArray(T, This)
{
    enum isUniNodeArray = isArray!T && is(Unqual!(ForeachType!T) : Unqual!This);
}

@("Checking for array")
@safe unittest
{
    assert (isUniNodeArray!(UniNode[], UniNode));
}


/**
 * Checking for object
 */
template isUniNodeMapping(T, This)
{
    enum isUniNodeMapping = isAssociativeArray!T
        && is(Unqual!(ForeachType!T) : Unqual!This) && is(KeyType!T == string);
}

@("Checking for object")
@safe unittest
{
    assert (isUniNodeMapping!(UniNode[string], UniNode));
}


/**
 * Language type to uninode inner tag
 */
template ToNodeTag(Node, T)
    if (isUniNodeType!(T, Node))
{
    static if (isBoolean!T)
        enum ToNodeTag = Node.Tag.boolean;
    else static if (isSignedNumeric!T)
        enum ToNodeTag = Node.Tag.integer;
    else static if (isUnsignedNumeric!T)
        enum ToNodeTag = Node.Tag.uinteger;
    else static if (isFloatingPoint!T)
        enum ToNodeTag = Node.Tag.floating;
    else static if (isSomeString!T)
        enum ToNodeTag = Node.Tag.text;
    else static if (isRawData!T)
        enum ToNodeTag = Node.Tag.raw;
    else static if (isUniNodeArray!(T, Node))
        enum ToNodeTag = Node.Tag.sequence;
    else static if (isUniNodeMapping!(T, Node))
        enum ToNodeTag = Node.Tag.mapping;
    else
        enum ToNodeTag = Node.Tag.nil;
}

@("ToNodeTag test")
@safe unittest
{
    static assert (ToNodeTag!(UniNode, bool) == UniNode.Tag.boolean);
    static assert (ToNodeTag!(UniNode, int) == UniNode.Tag.integer);
    static assert (ToNodeTag!(UniNode, uint) == UniNode.Tag.uinteger);
    static assert (ToNodeTag!(UniNode, float) == UniNode.Tag.floating);
    static assert (ToNodeTag!(UniNode, string) == UniNode.Tag.text);
    static assert (ToNodeTag!(UniNode, ubyte[]) == UniNode.Tag.raw);
    static assert (ToNodeTag!(UniNode, UniNode[]) == UniNode.Tag.sequence);
    static assert (ToNodeTag!(UniNode, UniNode[string]) == UniNode.Tag.mapping);
}


template matchImpl(Flag!"exhaustive" exhaustive, handlers...)
    if (handlers.length)
{
    auto matchImpl(Node)(auto ref Node node)
		if (is(Node : UniNodeImpl!T, T))
	{
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
            Match[Node.Names.length] matches;

            foreach (tid, T; Fields!(Node.Storage))
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

        // static foreach (tid, m; matches)
        //     pragma(msg, Node.Names[tid], " -> ", m);

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
            static foreach (tid, T; Fields!(Node.Storage))
            {
                case tid:
                    static if (matches[tid].type == MatchType.TPL)
                        return mixin("handler",
                            toCtString!(matches[tid].hid))(node._val!T);
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
                        alias PT = Parameters!h;
                        static if (is(ReturnType!h == void))
                        {
                            mixin("handler",
                                toCtString!(matches[tid].hid))(node.convertTo!(PT[0]));
                            return 0;
                        }
                        else
                        {
                            return mixin("handler",
                                    toCtString!(matches[tid].hid))(node.convertTo!(PT[0]));
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
    if (isUniNodeType!(Org, Node))
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

