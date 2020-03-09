/**
 * The module contains serialization functions
 *
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2020-01-12
 */

module uninode.serialization;

public import uninode.node : UniNode;

private
{
    import std.typetuple : TypeTuple;
    import std.exception : enforce;
    import std.conv : text, to;
    import std.typecons;
    import std.traits;
    import std.meta;

    import bolts : FilterMembersOf;
    import optional : Optional, OptionalTarget;
    import optional.traits : isOptional;

    import uninode.node;
}

///Marks a method for use in serialization
enum SerializationMethod;

///Marks a method for use in deserialization
enum DeserializationMethod;


/**
 * Attribute for overriding the field name during (de-)serialization.
 */
NameAttribute name(string name) @safe nothrow pure @property
{
    return NameAttribute(name);
}


/**
 * Attribute for forcing serialization of enum fields by name instead of by value.
 */
ByNameAttribyte byName() @safe nothrow pure @property
{
    return ByNameAttribyte();
}


/**
 * Attribute for representing a struct/class as an array instead of an object.
 */
AsArrayAttribute asArray() @safe nothrow pure @property
{
    return AsArrayAttribute();
}


/**
 * Attribute for marking non-serialized fields.
 */
IgnoreAttribute ignore() pure nothrow @safe @property
{
    return IgnoreAttribute();
}


/**
 * Attribute for marking non-serialized fields.
 */
OptionalAttribute optional() pure nothrow @safe @property
{
    return OptionalAttribute();
}


/**
 * Attribute marking a field as masked during serialization.
 */
MaskedAttribute masked() pure nothrow @safe @property
{
    return MaskedAttribute();
}


/**
 * Attribute for forcing serialization as string.
 */
AsStringAttribute asString() pure nothrow @safe @property
{
    return AsStringAttribute();
}


/**
 * Default UniNode serializer
 */
struct UniNodeSerializer {}


/**
 * Serialize object to UniNode
 *
 * Params:
 * object = serialized object
 */
UniNode serializeToUniNode(T)(auto ref const T value)
{
    return serialize!(UniNode, UniNodeSerializer)(value);
}


/**
 * Deserialize object form UniNode
 *
 * Params:
 * src = UniNode value
 */
T deserializeUniNode(T)(UniNode src)
{
    T value;
    deserialize!(UniNode, UniNodeSerializer)(src, value);
    return value;
}


/**
 * Serializes a value with Serializer
 */
template serialize(Node, Serializer : UniNodeSerializer)
    if (isUniNode!Node)
{
    Node serialize(T)(auto ref const T value)
    {
        static if (__traits(compiles, __traits(getAttributes, T)))
        {
            alias TA = TypeTuple!(__traits(getAttributes, T));
            return serializeValue!(T, TA)(value);
        }
        else
            return serializeValue!(T)(value);
    }


private:


    Node serializeValue(T, A...)(auto ref const T value)
    {
        alias TU = Unqual!T;

        static if (is(TU == typeof(null)))
            return Node();
        else static if (is(TU : Node))
            return value;
        else static if (isNullable!T)
        {
            if (value.isNull)
                return serializeValue!(A)(null);
            else
                return serializeValue!(TemplateArgsOf!T[0], A)(value.get);
        }
        else static if (isOptional!T)
        {
            if (value.empty)
                return serializeValue!(A)(null);
            else
                return serializeValue!(OptionalTarget!T, A)(value.front);
        }
        else static if (is(T == enum))
        {
            static if (hasAttribute!(ByNameAttribyte, A))
                return serializeValue!(string, A)(value.text);
            else
                return serializeValue!(OriginalType!TU, A)(cast(OriginalType!TU)value);
        }
        else static if (isInstanceOf!(Typedef, TU))
            return serializeValue!(TypedefType!TU, A)(cast(TypedefType!TU)value);
        else static if (isPointer!T)
        {
            if (value is null)
                return Node();
            return serializeValue!(PointerTarget!TU, A)(*value);
        }
        else static if (isTimeType!T)
            return serializeValue!(string, A)(value.toISOExtString);
        else static if (isSomeChar!T)
            return serializeValue!(string, A)(value.text);
        else static if (hasAttribute!(AsStringAttribute, A))
            return serializeValue!(string)(value.text);
        else static if (is(T == Tuple!TPS, TPS...))
        {
            import std.algorithm.searching: all;
            enum fieldsCount = TU.Types.length;

            static if (all!"!a.empty"([TU.fieldNames]) && !hasAttribute!(AsArrayAttribute, A))
            {
                Node[string] output;
                foreach (i, _; TU.Types)
                {
                    alias TV = typeof(value[i]);
                    enum memberName = underscoreStrip(TU.fieldNames[i]);
                    output[memberName] = serializeValue!(TV, A)(value[i]);
                }
                return Node(output);
            }
            else static if (fieldsCount == 1)
                return serializeValue!(typeof(value[0]), A)(value[0]);
            else
            {
                Node[] output;
                output.reserve(fieldsCount);
                foreach (i, _; TU.Types)
                {
                    alias TV = typeof(value[i]);
                    output ~= serializeValue!(typeof(value[i]), A)(value[i]);
                }
                return Node(output);
            }
        }
        else static if (isAssociativeArray!T)
        {
            alias TK = KeyType!TU;
            alias TV = Unqual!(ValueType!TU);

            Node[string] output;
            foreach (key, ref el; value)
            {
                string keyname;
                static if (is(TK : string))
                    keyname = key;
                else static if (is(TK : real) || is(TK : long) || is(TK == enum))
                    keyname = key.text;
                else static assert(false, "Associative array keys must be strings," ~
                        "numbers, enums.");
                output[keyname] = serializeValue!(TV)(el);
            }
            return Node(output);
        }
        else static if (is(TU == BitFlags!E, E))
        {
            size_t cnt = 0;
            foreach (v; EnumMembers!E)
                if (value & v)
                    cnt++;

            Node[] output = new Node[cnt];
            cnt = 0;
            foreach (v; EnumMembers!E)
            {
                if (value & v)
                    output[cnt++] = serializeValue!(E)(v);
            }
            return Node(output);
        }
        else static if (isSimpleList!T)
        {
            static if (isRawData!T && !hasAttribute!(AsArrayAttribute, A))
                return Node(value);
            else
            {
                Node[] output = new Node[value.length];
                alias TV = Unqual!(ForeachType!T);
                foreach (i, v; value)
                    output[i] = serializeValue!(TV, A)(v);
                return Node(output);
            }
        }
        else static if (is(TU == struct) || is(TU == class))
        {
            static if (is(T == class))
                if (value is null)
                    return Node();

            static auto safeGetMember(string mname)(ref const T val) @safe
            {
                static if (__traits(compiles, __traits(getMember, val, mname)))
                    return __traits(getMember, val, mname);
                else
                {
                    pragma(msg, "Warning: Getter for "~fullyQualifiedName!T~"."~mname~" is not @safe");
                    return () @trusted { return __traits(getMember, val, mname); } ();
                }
            }

            static if (hasSerializationMethod!(T, Node))
                return __traits(getMember, value,
                        __traits(identifier, serializationMethod!T))();
            else static if (hasAttribute!(AsArrayAttribute, A))
            {
                alias members = FilterMembersOf!(TU, isSerializableField);
                enum nfields = getExpandedFieldCount!(TU, members);
                Node[] output = new Node[nfields];
                size_t fcount = 0;

                foreach (i, mName; members)
                {
                    alias TMS = TypeTuple!(typeof(__traits(getMember, value, mName)));
                    foreach (j, TM; TMS)
                    {
                        alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mName))[j]));
                        static if (!isBuiltinTuple!(T, mName))
                            output[fcount++] = serializeValue!(TM, TA)(safeGetMember!mName(value));
                        else
                            output[fcount++] = serializeValue!(TM, TA)(tuple(__traits(getMember, value, mName))[j]);
                    }
                }
                return Node(output);
            }
            else
            {
                Node[string] output;
                foreach (mName; FilterMembersOf!(TU, isSerializableField))
                {
                    alias TM = TypeTuple!(typeof(__traits(getMember, TU, mName)));
                    alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mName))[0]));
                    enum memberName = GetMemeberName!(T, mName);
                    static if (!isBuiltinTuple!(T, mName))
                        auto vt = safeGetMember!mName(value);
                    else
                    {
                        alias TTM = TypeTuple!(typeof(__traits(getMember, value, mName)));
                        auto vt = tuple!TTM(__traits(getMember, value, mName));
                    }
                    output[memberName] = serializeValue!(typeof(vt), TA)(vt);
                }
                return Node(output);
            }
        }
        else static if (isUniNodeInnerType!TU)
            return Node(value);
        else
            static assert(false, "Unsupported serialization type: " ~ T.stringof);
    }
}


/**
 * Deserializes a value with Serializer
 */
template deserialize(Node, Serializer : UniNodeSerializer)
    if (isUniNode!Node)
{
    void deserialize(T)(auto ref Node value, out T result)
    {
        static if (__traits(compiles, __traits(getAttributes, T)))
        {
            alias TA = TypeTuple!(__traits(getAttributes, T));
            result = deserializeValue!(T, TA)(value);
        }
        else
            result = deserializeValue!(T)(value);
    }


private:


    T deserializeValue(T, A...)(auto ref const Node value)
    {
        static if (is(T == typeof(null)))
            return typeof(null).init;
        else static if (isNullable!T)
        {
            if (!value.canNil)
                return T(deserializeValue!(TemplateArgsOf!T[0], A)(value));
            else
                return T.init;
        }
        else static if (isOptional!T)
        {
            if (!value.canNil)
                return T(deserializeValue!(OptionalTarget!T, A)(value));
            else
                return T.init;
        }
        else static if (isInstanceOf!(Typedef, T))
            return T(deserializeValue!(TypedefType!T, A)(value));
        else static if (isPointer!T)
        {
            if (value.canNil)
                return null;
            alias PT = PointerTarget!T;
            auto ret = new PT;
            *ret = deserializeValue!(PT, A)(value);
            return ret;
        }
        else static if (isTimeType!T)
            return T.fromISOExtString(deserializeValue!(string, A)(value));
        else static if (isSomeChar!T)
        {
            const s = deserializeValue!(string, A)(value);
            enforceDeserialization(s.length, "String length mismatch");
            return s[0];
        }
        else static if (is(T == Tuple!TPS, TPS...))
        {
            import std.algorithm.searching: all;
            enum fieldsCount = T.Types.length;

            static if (all!"!a.empty"([T.fieldNames]) && !hasAttribute!(AsArrayAttribute, A))
            {
                T output;
                bool[fieldsCount] set;
                foreach (ref name, ref const(Node) val; value.getMapping)
                {
                    switch (name)
                    {
                        foreach (i, TV; T.Types)
                        {
                            enum fieldName = underscoreStrip(T.fieldNames[i]);
                            case fieldName: {
                                output[i] = deserializeValue!(TV, A)(val);
                                set[i] = true;
                            } break;
                        }
                        default: break;
                    }
                }
                foreach (i, fieldName; T.fieldNames)
                    enforceDeserialization(set[i], "Missing tuple field '"~fieldName
                            ~"' of type '"~T.Types[i].stringof~"'.");
                return output;
            }
            else static if (fieldsCount == 1)
                return T(deserializeValue!(T.Types[0], A)(value));
            else
            {
                T output;
                size_t currentField = 0;
                foreach (ref const(Node) val; value.getSequence)
                {
                    switch (currentField++)
                    {
                        foreach (i, TV; T.Types)
                        {
                            case i:
                                output[i] = deserializeValue!(TV, A)(val);
                                break;
                        }
                        default: break;
                    }
                }
                enforceDeserialization(currentField == fieldsCount,
                        "Missing tuple field(s) - expected '"~fieldsCount.stringof
                            ~"', received '"~currentField.stringof~"'.");
                return output;
            }
        }
        else static if (is(T == BitFlags!E, E))
        {
            T output;
            foreach (ref idx, ref const(Node) val; value.getSequence)
                output |= deserializeValue!(E, A)(val);
            return output;
        }
        else static if (is(T == enum))
        {
            static if (hasAttribute!(ByNameAttribyte, A))
                return deserializeValue!(string, A)(value).to!T;
            else
                return cast(T)deserializeValue!(OriginalType!T, A)(value);
        }
        else static if (isStaticArray!T)
        {
            alias TV = typeof(T.init[0]);
            T output;
            enforceDeserialization(value.length == T.length, "Static array length mismatch");

            if (value.canRaw)
            {
                foreach (ref idx, val; value.get!Bytes)
                    output[idx] = val;
            }
            else
            {
                foreach (ref idx, ref const(Node) val; value.getSequence)
                    output[idx] = deserializeValue!(TV)(val);
            }

            return output;
        }
        else static if (isSimpleList!T)
        {
            alias TV = typeof(T.init[0]);

            T output;
            output.reserve(value.length);

            if (value.canRaw)
            {
                static if (isNumeric!(ForeachType!T))
                {
                    foreach (val; value.get!Bytes)
                        output ~= val;
                }

                return output;
            }
            else
            {
                foreach (ref idx, ref const(Node) val; value.getSequence)
                    output ~= deserializeValue!(TV)(val);
            }

            return output;
        }
        else static if (isAssociativeArray!T)
        {
            alias TK = KeyType!T;
            alias TV = ValueType!T;
            T output;

            foreach (ref name, ref const(Node) val; value.getMapping)
            {
                TK key;
                static if (is(TK == string) || (is(TK == enum)
                            && is(OriginalType!TK == string)))
                    key = cast(TK)name;
                else static if (is(TK : real) || is(TK : long) || is(TK == enum))
                    key = name.to!TK;
                else
                    static assert(false, "Associative array keys must be strings," ~
                        "numbers, enums.");
                output[key] = deserializeValue!(TV, A)(val);
            }

            return output;
        }
        else static if (is(T : Node))
            return value;
        else static if (is(T == struct) || is(T == class))
        {
            static if (is(T == class))
                if (value.canNil)
                    return null;

            void safeSetMember(string mname, U)(ref T value, U fval) @safe
            {
                static if (__traits(compiles, () @safe { __traits(getMember, value, mname) = fval; }))
                    __traits(getMember, value, mname) = fval;
                else
                {
                    pragma(msg, "Warning: Setter for "~fullyQualifiedName!T~"."~mname~" is not @safe");
                    () @trusted { __traits(getMember, value, mname) = fval; } ();
                }
            }

            bool canDeserializable(A...)(Node val)
            {
                static if (hasAttribute!(OptionalAttribute, A))
                    return !val.canNil();
                else
                    return true;
            }

            static if (hasDeserializationMethod!(T, Node))
                return deserializationMethod!T(value);
            else
            {
                T output;
                static if (is(T == class))
                    output = new T;
                alias Members = FilterMembersOf!(T, isDeserializableField);
                enum FDS = getExpandedFieldsData!(T, Members);
                bool[FDS.length] set;

                static if (hasAttribute!(AsArrayAttribute, A))
                {
                    foreach (ref idx, ref const(Node) val; value.getSequence)
                    {
                        switch (idx)
                        {
                            foreach (i, FD; FDS)
                            {
                                enum mName = FD[0];
                                enum mIndex = FD[1];
                                alias MT = TypeTuple!(__traits(getMember, T, mName));
                                alias MTI = MT[mIndex];
                                alias TMTI = typeof(MTI);
                                alias TMTIA = TypeTuple!(__traits(getAttributes, MTI));
                            case i:
                                if (canDeserializable!TMTIA(val))
                                {
                                    static if (!isBuiltinTuple!(T, mName))
                                        safeSetMember!mName(output, deserializeValue!(TMTI, TMTIA)(val));
                                    else
                                        __traits(getMember, output, mName)[mIndex] = deserializeValue!(TMTI,
                                                TMTIA)(val);
                                }
                                set[i] = true;
                                break;
                            }
                            default: break;
                        }
                    }
                }
                else
                {
                    foreach (ref name, ref const(Node) val; value.getMapping)
                    {
                        switch (name)
                        {
                            foreach (i, mName; Members)
                            {
                                alias TM = TypeTuple!(typeof(__traits(getMember, T, mName)));
                                alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T,
                                                    mName))[0]));
                                enum memberName = GetMemeberName!(T, mName);
                            case memberName:
                                if (canDeserializable!TA(val))
                                {
                                    static if (!isBuiltinTuple!(T, mName))
                                        safeSetMember!mName(output, deserializeValue!(TM, TA)(val));
                                    else
                                        __traits(getMember, output, mName) = deserializeValue!(Tuple!TM, TA)(val);
                                }
                                set[i] = true;
                                break;
                            }
                            default: break;
                        }
                    }
                }

                foreach (i, mName; Members)
                {
                    alias MTA = __traits(getAttributes, __traits(getMember, T, mName));
                    static if (!hasAttribute!(OptionalAttribute, MTA))
                        enforceDeserialization(set[i], "Missing non-optional field '"~mName
                                ~"' of type '"~T.stringof~"'.");
                }

                return output;
            }
        }
        else static if (isUniNodeInnerType!T)
        {
            static if (is(T == Node))
                return value;
            else
                return value.get!T;
        }
        else
            static assert(false, "Unsupported serialization type: " ~ T.stringof);
    }
}


/**
 * Thrown on UniNode deserialization errors
 */
class UniNodeDeserializationException : Exception
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


package alias enforceDeserialization = enforce!UniNodeDeserializationException;


private:


/**
 * Check nullable Type
 */
enum isNullable(T) = isInstanceOf!(Nullable, T);

@("Should work isNullable")
@safe unittest
{
    assert (isNullable!(Nullable!int));
    assert (isNullable!(Nullable!(int, 0)));
    assert (!isNullable!int);
}


/**
 * Check datetime type
 */
template isTimeType(T) {
    import std.datetime : DateTime, Date, SysTime, TimeOfDay;
    enum isTimeType = is(T == SysTime) || is(T == DateTime) || is(T == Date)
        || is(T == TimeOfDay);
}

@("Should work isTimeType")
@safe unittest
{
    import std.datetime : DateTime, Date, SysTime, TimeOfDay;
    assert (isTimeType!DateTime);
    assert (isTimeType!Date);
    assert (isTimeType!SysTime);
    assert (isTimeType!TimeOfDay);
}


/**
 * Determines if a member is a public, non-static, de-facto data field.
 * In addition to plain data fields, R/W properties are also accepted.
 */
template isSerializableAvailableField(T, string M)
{
    import std.typetuple : TypeTuple;

    static void testAssign()()
    {
        T t = void;
        __traits(getMember, t, M) = __traits(getMember, t, M);
    }

    // reject type aliases
    static if (is(TypeTuple!(__traits(getMember, T, M))))
        enum isSerializableAvailableField = false;
    // reject non-public members
    else static if (!isPublicMember!(T, M))
        enum isSerializableAvailableField = false;
    // reject static members
    else static if (!isNonStaticMember!(T, M))
        enum isSerializableAvailableField = false;
    // reject non-typed members
    else static if (!is(typeof(__traits(getMember, T, M))))
        enum isSerializableAvailableField = false;
    // reject void typed members (includes templates)
    else static if (is(typeof(__traits(getMember, T, M)) == void))
        enum isSerializableAvailableField = false;
    // reject non-assignable members
    else static if (!__traits(compiles, testAssign!()()))
        enum isSerializableAvailableField = false;
    // reject ignore members
    else static if (anySatisfy!(isSomeFunction, __traits(getMember, T, M)))
    {
        // If M is a function, reject if not @property or returns by ref
        private enum FA = functionAttributes!(__traits(getMember, T, M));
        enum isSerializableAvailableField = (FA & FunctionAttribute.property) != 0;
    }
    else
        enum isSerializableAvailableField = true;
}


/**
 * Determins if a member is a public, non-static data field.
 */
template isSerializablePlainField(T, string M)
{
    private T tGen(){ return T.init; }

    static if (!isSerializableField!(T, M))
        enum isSerializablePlainField = false;
    else
    {
        enum isSerializablePlainField = __traits(compiles,
                *(&__traits(getMember, tGen(), M)) = *(&__traits(getMember, tGen(), M)));
    }
}


/**
 * Determins if a member is serializable
 */
template isSerializableField(T, string M)
{
    static if (isSerializableAvailableField!(T, M))
    {
        alias AA = __traits(getAttributes, __traits(getMember, T, M));
        static if (hasAttribute!(MaskedAttribute, AA))
            enum isSerializableField = false;
        else static if (hasAttribute!(IgnoreAttribute, AA))
            enum isSerializableField = false;
        else
            enum isSerializableField = true;
    }
    else
        enum isSerializableField = false;
}


/**
 * Determins if a member is deseriazable
 */
template isDeserializableField(T, string M)
{
    static if (isSerializableAvailableField!(T, M))
    {
        alias AA = __traits(getAttributes, __traits(getMember, T, M));
        static if (hasAttribute!(IgnoreAttribute, AA))
            enum isDeserializableField = false;
        else static if (hasAttribute!(AsStringAttribute, AA))
            enum isDeserializableField = false;
        else
            enum isDeserializableField = true;
    }
    else
        enum isDeserializableField = false;
}


@("Should work isSerializableAvailableField")
@safe unittest
{
    import std.algorithm.searching : canFind;

    struct S
    {
        alias a = int;        // alias
        int i;                // plain field
        enum j = 42;          // manifest constant
        static int k = 42;    // static field
        private int privateJ; //private field

        this(Args...)(Args args) {}

        // read-write property (OK)
        @property int p1() { return privateJ; }
        @property void p1(int j) { privateJ = j; }
        // read-only property (NO)
        @property int p2() { return privateJ; }
        // write-only property (NO)
        @property void p3(int value) { privateJ = value; }
        // ref returning property (OK)
        @property ref int p4() { return i; }
        // parameter-less template property (OK)
        @property ref int p5()() { return i; }
        // not treated as a property by DMD, so not a field
        @property int p6()() { return privateJ; }
        @property void p6(int j)() { privateJ = j; }

        static @property int p7() { return k; }
        static @property void p7(int value) { k = value; }

        ref int f1() { return i; } // ref returning function (no field)

        int f2(Args...)(Args) { return i; }

        ref int f3(Args...)(Args) { return i; }

        void someMethod() {}

        ref int someTempl()() { return i; }
    }

    static immutable plainFields = ["i"];
    static immutable fields = ["i", "p1", "p4", "p5"];

    foreach (fName; __traits(allMembers, S))
    {
        static if (isSerializableField!(S, fName))
            assert (fields.canFind(fName), fName ~ " detected as field.");
        else
            assert (!fields.canFind(fName), fName ~ " not detected as field.");

        static if (isSerializablePlainField!(S, fName))
            assert (plainFields.canFind(fName), fName ~ " not detected as plain field.");
        else
            assert (!plainFields.canFind(fName), fName ~ " not detected as plain field.");
    }
}


/**
 * Tests if a member requires $(D this) to be used.
 */
template isNonStaticMember(T, string M)
{
    import std.typetuple;
    import std.traits;

    static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M))))
        enum isNonStaticMember = false;
    else
    {
        alias MF = TypeTuple!(__traits(getMember, T, M));
        static if (M.length == 0)
            enum isNonStaticMember = false;
        else static if (anySatisfy!(isSomeFunction, MF))
            enum isNonStaticMember = !__traits(isStaticFunction, MF);
        else
            enum isNonStaticMember = !__traits(compiles, (){ auto x = __traits(getMember, T, M); }());
    }
}

@("Should work isNonStaticMember template")
@safe unittest
{
    struct S
    {
        int a;
        static int b;
        enum c = 42;
        void f();
        static void g();
        ref int h() { return a; }
        static ref int i() { return b; }
    }

    assert (isNonStaticMember!(S, "a"));
    assert (!isNonStaticMember!(S, "b"));
    assert (!isNonStaticMember!(S, "c"));
    assert (isNonStaticMember!(S, "f"));
    assert (!isNonStaticMember!(S, "g"));
    assert (isNonStaticMember!(S, "h"));
    assert (!isNonStaticMember!(S, "i"));
}

@("Should work isNonStaticMember tuple fields")
@safe unittest
{
    struct S(T...)
    {
        T a;
        static T b;
    }

    alias T = S!(int, float);
    assert (isNonStaticMember!(T, "a"));
    assert (!isNonStaticMember!(T, "b"));

    alias U = S!();
    assert (!isNonStaticMember!(U, "a"));
    assert (!isNonStaticMember!(U, "b"));
}


/**
 * Tests if the protection of a member is public.
 */
template isPublicMember(T, string M)
{
    import std.algorithm : among;

    static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M))))
        enum isPublicMember = false;
    else
    {
        alias MEM = TypeTuple!(__traits(getMember, T, M));
        enum isPublicMember = __traits(getProtection, MEM).among("public", "export");
    }
}

@("Should work isPublicMember")
@safe unittest
{
    class C
    {
        int a;
        export int b;
        protected int c;
        private int d;
        package int e;
        void f() {}
        static void g() {}
        private void h() {}
        private static void i() {}
    }

    assert (isPublicMember!(C, "a"));
    assert (isPublicMember!(C, "b"));
    assert (!isPublicMember!(C, "c"));
    assert (!isPublicMember!(C, "d"));
    assert (!isPublicMember!(C, "e"));
    assert (isPublicMember!(C, "f"));
    assert (isPublicMember!(C, "g"));
    assert (!isPublicMember!(C, "h"));
    assert (!isPublicMember!(C, "i"));

    struct S
    {
        int a;
        export int b;
        private int d;
        package int e;
    }
    assert (isPublicMember!(S, "a"));
    assert (isPublicMember!(S, "b"));
    assert (!isPublicMember!(S, "d"));
    assert (!isPublicMember!(S, "e"));

    S s;
    s.a = 21;
    assert (s.a == 21);
}


/**
 * Check Tuple
 */
template isBuiltinTuple(T, string member)
{
    alias TM = AliasSeq!(typeof(__traits(getMember, T.init, member)));
    static if (TM.length > 1) enum isBuiltinTuple = true;
    else static if (is(typeof(__traits(getMember, T.init, member)) == TM[0]))
        enum isBuiltinTuple = false;
    else enum isBuiltinTuple = true; // single-element tuple
}


/**
 * Get expanded fields count
 */
size_t getExpandedFieldCount(T, FIELDS...)()
{
    size_t ret = 0;
    foreach (F; FIELDS)
        ret += TypeTuple!(__traits(getMember, T, F)).length;
    return ret;
}


/**
 * Get expanded fields data
 */
template getExpandedFieldsData(T, FIELDS...)
{
    import std.meta : aliasSeqOf, staticMap;
    import std.range : repeat, zip, iota;

    enum subfieldsCount(alias F) = TypeTuple!(__traits(getMember, T, F)).length;
    alias processSubfield(alias F) = aliasSeqOf!(zip(repeat(F), iota(subfieldsCount!F)));
    alias getExpandedFieldsData = staticMap!(processSubfield, FIELDS);
}


/**
 * Strip underscore
 */
string underscoreStrip(string fieldName) @safe nothrow @nogc
{
    if (fieldName.length < 1 || fieldName[$-1] != '_')
        return fieldName;
    else
        return fieldName[0 .. $-1];
}


/**
 * Return member name
 */
template GetMemeberName(T, string M)
{
    alias isNamed(alias M) = hasUDA!(M, NameAttribute);
    alias FM = Filter!(isNamed, TypeTuple!(__traits(getMember, T, M)));
    static if (FM.length > 0)
        enum GetMemeberName = underscoreStrip(getUDAs!(FM[0], NameAttribute)[0].name);
    else
        enum GetMemeberName = underscoreStrip(M);
}


/**
 * Check attribute
 */
template hasAttribute(alias T, ATTRIBUTES...)
{
    static if (ATTRIBUTES.length == 1)
        enum hasAttribute = is(typeof(ATTRIBUTES[0]) == T);
    else static if (ATTRIBUTES.length > 1)
        enum hasAttribute = hasAttribute!(T, ATTRIBUTES[0 .. $/2]) || hasAttribute!(T, ATTRIBUTES[$/2 .. $]);
    else
        enum hasAttribute = false;
}


/**
 * Return serialization method
 */
alias serializationMethod(T) = getSymbolsByUDA!(T, SerializationMethod)[0];


/**
 * Check SerializationMethod
 */
template hasSerializationMethod(T, Node)
{
    alias methods = getSymbolsByUDA!(T, SerializationMethod);

    static if (methods.length == 1)
        enum hasSerializationMethod = Parameters!(methods[0]).length == 0
                && is(ReturnType!(methods[0]) : Node);
    else
        enum hasSerializationMethod = false;
}


/**
 * Return deserialization method
 */
alias deserializationMethod(T) = getSymbolsByUDA!(T, DeserializationMethod)[0];


/**
 * Check SerializationMethod
 */
template hasDeserializationMethod(T, Node)
{
    alias methods = getSymbolsByUDA!(T, DeserializationMethod);

    static if (methods.length == 1)
        enum hasDeserializationMethod = Parameters!(methods[0]).length == 1
                && is(Parameters!(methods[0])[0] : Node)
                && is(ReturnType!(methods[0]) == T);
    else
        enum hasDeserializationMethod = false;
}


/**
 * Check type of simple list
 */
alias isSimpleList = templateAnd!(isArray, templateNot!isSomeString,
        templateNot!isAssociativeArray);

@("Should work isSimpleList")
@safe unittest
{
    assert(isSimpleList!(int[]));
    assert(isSimpleList!(string[]));
    assert(!isSimpleList!(string));
    assert(!isSimpleList!(char[]));
    assert(!isSimpleList!(int));
    assert(!isSimpleList!(int[string]));
    assert(isSimpleList!(char[10]));
}


/**
 * Attribute for overriding the field name during (de-)serialization.
 */
struct NameAttribute
{
    /// Custom member name
    string name;
}


/**
 * Attribute for forcing serialization of enum fields by name instead of by value.
 */
struct ByNameAttribyte {}


/**
 * Attribute for representing a struct/class as an array instead of an object.
 */
struct AsArrayAttribute {}


/**
 * Attribute marking a field as optional during deserialization.
 */
struct OptionalAttribute {}


/**
 * Attribute marking a field as masked during serialization.
 */
struct MaskedAttribute {}


/**
 *	Attribute for marking non-serialized fields.
 */
struct IgnoreAttribute {}


/**
 * Attribute for forcing serialization as string.
 */
struct AsStringAttribute {}

