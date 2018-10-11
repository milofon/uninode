/**
 * Copyright: (c) 2015-2018, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2018-08-15
 */

module uninode.serialization;

public
{
    import vibe.data.serialization : optional, byName;
}

private
{
    import vibe.data.serialization :
                vSerialize = serialize,
                vDeserialize = deserialize;

    import uninode.core;
}



UniNode serializeToUniNode(T)(T object)
{
    return vSerialize!(UniNodeSerializer, T)(object);
}



T deserializeUniNode(T)(UniNode src)
{
    return vDeserialize!(UniNodeSerializer, T, UniNode)(src);
}



struct UniNodeSerializer
{
    enum isSupportedValueType(T) = isUniNodeType!(T, UniNode) || is(T == UniNode);


    private
    {
        UniNode _current;
        UniNode[] _stack;
    }


    @disable this(this);


    this(UniNode data) @safe
    {
        _current = data;
    }


    // serialization
    UniNode getSerializedResult() @safe
    {
        return _current;
    }


    void beginWriteDictionary(TypeTraits)()
    {
        _stack ~= UniNode.emptyObject();
    }


    void endWriteDictionary(TypeTraits)()
    {
        _current = _stack[$-1];
        _stack.length--;
    }


    void beginWriteDictionaryEntry(ElementTypeTraits)(string name) {}


    void endWriteDictionaryEntry(ElementTypeTraits)(string name)
    {
        _stack[$-1][name] = _current;
    }


    void beginWriteArray(TypeTraits)(size_t length)
    {
        _stack ~= UniNode.emptyArray();
    }


    void endWriteArray(TypeTraits)()
    {
        _current = _stack[$-1];
        _stack.length--;
    }


    void beginWriteArrayEntry(ElementTypeTraits)(size_t index) {}


    void endWriteArrayEntry(ElementTypeTraits)(size_t index)
    {
        _stack[$-1] ~= _current;
    }


    void writeValue(TypeTraits, T)(T value) if (!is(T == UniNode))
    {
        _current = UniNode(value);
    }


    void writeValue(TypeTraits, T)(UniNode value) if (is(T == UniNode))
    {
        _current = value;
    }


    // deserialization
    void readDictionary(TypeTraits)(scope void delegate(string) @safe entry_callback) @safe
    {
        auto old = _current;
        foreach (ref string key, ref UniNode value; _current)
        {
            _current = value;
            entry_callback(key);
        }
        _current = old;
    }


    void beginReadDictionaryEntry(ElementTypeTraits)(string) {}


    void endReadDictionaryEntry(ElementTypeTraits)(string) {}


    void readArray(TypeTraits)(scope void delegate(size_t) @safe size_callback,
            scope void delegate() @safe entry_callback)
    {
        auto old = _current;
        size_callback(_current.length);
        foreach (ref UniNode ent; _current)
        {
            _current = ent;
            entry_callback();
        }
        _current = old;
    }


    void beginReadArrayEntry(ElementTypeTraits)(size_t index) {}


    void endReadArrayEntry(ElementTypeTraits)(size_t index) {}


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


    bool tryReadNull(TypeTraits)()
    {
        return _current.kind == UniNode.Kind.nil;
    }
}

