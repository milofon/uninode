/**
 * The module contains the object UniTree
 *
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2020-03-03
 */

module uninode.tree;

private
{
    import std.format : fmt = format;
    import std.array : split;

    import optional : Optional;

    import uninode.node;
}


/// Delimiter char for config path
enum DELIMITER_CHAR = ".";


/**
 * A [UniTree] struct
 */
struct UniTree
{
    private
    {
        alias Node = UniNodeImpl!UniTree;
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
    {
        node = Node(val);
    }

    /**
     * Compares two `UniNode`s for equality.
     */
    bool opEquals(const(UniTree) rhs) const pure @safe
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

    /**
     * Convert UniNode to primitive type
     */
    inout(T) get(T)() inout pure @safe
    {
        return node.get!T;
    }

    /**
     * Get the node
     *
     * Params:
     * path = The path to the desired site
     *
     * Example:
     * ---
     * node.get!int("foo.bar");
     * ---
     */
    inout(T) get(T)(string path) inout pure @safe
    {
        auto nodePtr = findNode(path);
        if (!nodePtr)
            throw new UniNodeException(fmt!"Not found subtree '%s'"(path));
        static if (is (T : UniTree))
            return *nodePtr;
        else
            return nodePtr.node.get!T;
    }

    /**
     * Convert UniNode to sequence
     */
    inout(UniTree[]) getSequence() inout pure @safe
    {
        return node.getSequence();
    }

    /**
     * Convert UniNode to sequence
     */
    inout(UniTree[]) getSequence(string path) inout pure @safe
    {
        auto nodePtr = findNode(path);
        if (nodePtr)
            return nodePtr.node.getSequence();
        else
            throw new UniNodeException(fmt!"Not found subtree '%s'"(path));
    }

    /**
     * Convert UniNode to mapping
     */
    inout(UniTree[string]) getMapping() inout pure @safe
    {
        return node.getMapping();
    }

    /**
     * Convert UniNode to mapping
     */
    inout(UniTree[string]) getMapping(string path) inout pure @safe
    {
        auto nodePtr = findNode(path);
        if (nodePtr)
            return nodePtr.node.getMapping();
        else
            throw new UniNodeException(fmt!"Not found subtree '%s'"(path));
    }

    /**
     * Convert UniNode to primitive type or return alternative value
     */
    inout(T) getOrElse(T)(T alt) inout pure nothrow @safe
    {
        return node.getOrElse!T(alt);
    }

    /**
     * Convert UniNode to primitive type or return alternative value
     */
    inout(T) getOrElse(T)(string path, T alt) inout pure @safe
    {
        auto nodePtr = findNode(path);
        if (nodePtr)
        {
            static if (is (T : UniTree))
                return *nodePtr;
            else
                return nodePtr.node.getOrElse!T(alt);
        }
        else
            return alt;
    }

    /**
     * Convert UniNode to optional primitive type
     */
    Optional!(const(T)) opt(T)() const pure @safe
    {
        return node.opt!T;
    }

    /**
     * Convert UniNode to optional primitive type
     */
    Optional!(T) opt(T)() pure @safe
    {
        return node.opt!T;
    }

    /**
     * Get the tree
     *
     * Params:
     * path = The path to the desired site
     *
     * Example:
     * ---
     * node.opt!int("foo.bar");
     * ---
     */
    Optional!(const(T)) opt(T)(string path) const pure @safe
    {
        auto nodePtr = findNode(path);
        if (nodePtr)
        {
            static if (is (T : UniTree))
                return Optional!(const(T))(*nodePtr);
            else
                return nodePtr.node.opt!T;
        }
        else
            return Optional!(const(T)).init;
    }

    /**
     * Get the tree
     *
     * Params:
     * path = The path to the desired site
     *
     * Example:
     * ---
     * node.opt!int("foo.bar");
     * ---
     */
    Optional!(T) opt(T)(string path) pure @safe
    {
        auto nodePtr = findNode(path);
        if (nodePtr)
        {
            static if (is (T : UniTree))
                return Optional!(T)(*nodePtr);
            else
                return nodePtr.node.opt!T;
        }
        else
            return Optional!(T).init;
    }

    /**
     * Getting node or throw exception
     */
    inout(T) getOrThrown(T, E = UniNodeException)(lazy string msg,
            size_t line = __LINE__, string file = __FILE__) inout pure @safe
    {
        try
            return node.get!T;
        catch (Exception e)
            throw new E(msg, file, line);
    }

    /**
     * Getting node or throw exception with path
     */
    inout(T) getOrThrown(T, E = UniNodeException)(string path, lazy string msg,
            size_t line = __LINE__, string file = __FILE__) inout pure @safe
    {
        auto nodePtr = findNode(path);
        if (!nodePtr)
            throw new E(msg, file, line);
        static if (is (T : UniTree))
            return *nodePtr;
        else
        {
            try
                return nodePtr.node.get!T;
            catch (Exception e)
                throw new E(msg, file, line);
        }
    }

    /**
     * Checking for the presence of the node in the specified path
     *
     * It the node is an object, the we try to find the embedded objects in the specified path
     *
     * Params:
     *
     * path = The path to the desired site
     */
    inout(UniTree)* opBinaryRight(string op)(string path) inout
        if (op == "in")
    {
        return findNode(path);
    }

    /**
     * Recursive merge properties
     *
     * When the merger is not going to existing nodes
     * If the parameter is an array, it will their concatenation
     *
     * Params:
     *
     * src = Source properties
     */
    UniTree opBinary(string op)(auto ref UniTree src)
        if ("~" == op)
    {
        if (src.canNil)
            return this; // bitcopy this

        if (this.canNil)
            return src; //bintcopy src

        void mergeNode(ref UniTree dst, ref UniTree src) @safe
        {
            if (dst.canNil)
            {
                if (src.canMapping)
                    dst = UniTree.emptyMapping;

                if (src.canSequence)
                    dst = UniTree.emptySequence;
            }

            if (dst.canMapping && src.canMapping)
            {
                foreach (string key, ref UniTree ch; src)
                {
                    if (auto tg = key in dst)
                        mergeNode(*tg, ch);
                    else
                        dst[key] = ch;
                }
            }
            else if (dst.canSequence && src.canSequence)
                dst = UniTree(dst.getSequence ~ src.getSequence);
        }

        UniTree ret;
        mergeNode(ret, this);
        mergeNode(ret, src);
        return ret;
    }

private:

    /**
     * Getting node in the specified path
     *
     * It the node is an object, the we try to find the embedded objects in the specified path
     *
     * Params:
     *
     * path = The path to the desired site
     */
    inout(UniTree)* findNode(string path) inout pure @safe
    {
        auto names = path.split(DELIMITER_CHAR);

        inout(UniTree)* findPath(inout(UniTree)* node, string[] names) inout
        {
            if(names.length == 0)
                return node;

            immutable name = names[0];
            if (node.canMapping)
                if (auto chd = name in (*node).node)
                    return findPath(chd, names[1..$]);

            return null;
        }

        if (names.length > 0)
            return findPath(&this, names);

        return null;
    }
}

