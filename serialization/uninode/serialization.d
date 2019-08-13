/**
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-08-15
 */

module uninode.serialization;

public
{
    import vibe.data.serialization : byName, optional;
}

private
{
    import vibe.data.serialization :
                vDeserialize = deserialize,
                vSerialize = serialize;

    import uninode.core;
}


/**
 * Serialize object to UniNode
 *
 * Params:
 * object = serialized object
 */
UniNode serializeToUniNode(T)(T object)
{
    return vSerialize!(UniNodeSerializer, T)(object);
}


/**
 * Deserialize object form UniNode
 *
 * Params:
 * src = UniNode value
 */
T deserializeUniNode(T)(UniNode src)
{
    return vDeserialize!(UniNodeSerializer, T, UniNode)(src);
}


/**
 * Serializer for a UniNode representation.
 */
struct UniNodeSerializer
{
    enum isSupportedValueType(T) = isUniNodeType!(T, UniNode) || is(T == UniNode);


    private
    {
        UniNode _current;
        UniNode[] _stack;
    }


    @disable this(this);

    /**
     * Construct serializer from UniNode
     */
    this(UniNode data) @safe
    {
        _current = data;
    }

    /**
     *  serialization
     */

    UniNode getSerializedResult() @safe
    {
        return _current;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void beginWriteDictionary(TypeTraits)()
    {
        _stack ~= UniNode.emptyObject();
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void endWriteDictionary(TypeTraits)()
    {
        _current = _stack[$-1];
        _stack.length--;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void beginWriteDictionaryEntry(ElementTypeTraits)(string) {}

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void endWriteDictionaryEntry(ElementTypeTraits)(string name)
    {
        _stack[$-1][name] = _current;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void beginWriteArray(TypeTraits)(size_t)
    {
        _stack ~= UniNode.emptyArray();
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void endWriteArray(TypeTraits)()
    {
        _current = _stack[$-1];
        _stack.length--;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void beginWriteArrayEntry(ElementTypeTraits)(size_t) {}

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void endWriteArrayEntry(ElementTypeTraits)(size_t)
    {
        _stack[$-1] ~= _current;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void writeValue(TypeTraits, T)(T value) if (!is(T == UniNode))
    {
        _current = UniNode(value);
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void writeValue(TypeTraits, T)(T value) if (is(T == UniNode))
    {
        _current = value;
    }

    /**
     * deserialization
     */

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void readDictionary(TypeTraits)(scope void delegate(string) @safe entry_callback) @safe
    {
        const old = _current;
        foreach (ref string key, ref UniNode value; _current)
        {
            _current = value;
            entry_callback(key);
        }
        _current = old;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void beginReadDictionaryEntry(ElementTypeTraits)(string) {}

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void endReadDictionaryEntry(ElementTypeTraits)(string) {}

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void readArray(TypeTraits)(scope void delegate(size_t) @safe size_callback,
            scope void delegate() @safe entry_callback)
    {
        const old = _current;
        size_callback(_current.length);
        foreach (ref UniNode ent; _current)
        {
            _current = ent;
            entry_callback();
        }
        _current = old;
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void beginReadArrayEntry(ElementTypeTraits)(size_t) {}

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    void endReadArrayEntry(ElementTypeTraits)(size_t) {}

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    T readValue(TypeTraits, T)() @safe
    {
        static if (is(T == UniNode))
            return _current;
        else static if (is(T == float) || is(T == double))
        {
            switch (_current.kind)
            {
                default:
                    return cast(T)_current.get!T;
                case UniNode.Kind.nil:
                    return T.nan;
                case UniNode.Kind.floating:
                    return _current.get!T;
            }
        }
        else
            return _current.get!T();
    }

    /**
     * See_also: http://vibed.org/api/vibe.data.serialization/
     */
    bool tryReadNull(TypeTraits)()
    {
        return _current.kind == UniNode.Kind.nil;
    }
}
