/**
 * Copyright: (c) 2015-2020, Milofon Project.
 * License: Subject to the terms of the BSD 3-Clause License, as written in the included LICENSE.md file.
 * Author: <m.galanin@milofon.pro> Maksim Galanin
 * Date: 2020-03-03
 */

module uninode.test_tree;

private
{
    import std.exception : assertThrown, collectException;

    import uninode.tree;
    import optional : frontOr;
}


alias orElse = frontOr;


version(unittest)
{
    enum SimpleConfigs = q{
        auto chObj = UniTree(["one": UniTree(1), "two": UniTree(2)]);
        const chArr = UniTree([UniTree(3), UniTree(4), UniTree(5)]);
        auto root = UniTree(["obj": chObj, "arr": chArr]);
    };
}


@("Should size normal")
@safe unittest
{
    const node = UniTree(1);
    assert (node.sizeof == 24);
}


@("Should work get method with path")
@safe unittest
{
    mixin (SimpleConfigs);
    assert (root.get!int("obj.one") == 1);
    assert (!root.opt!int("obj.one").empty);
    assert (root.opt!int("obj.three").empty);
    assert (root.get!UniTree("obj").canMapping);
    assert (root.get!UniTree("obj").get!int("one") == 1);
}


@("Should work getOrThrown")
@safe unittest
{
    mixin (SimpleConfigs);
    auto e = collectException(root.getOrThrown!int("not found"));
    assert (e.msg == "not found");
    e = collectException(root.getOrThrown!UniTree("one", "not obj"));
    assert (e.msg == "not obj");
    assert (root.getOrThrown!UniTree("obj", "not found obj").canMapping);
}


@("Should work getOrElse")
@safe unittest
{
    mixin (SimpleConfigs);
    assert (root.opt!int("one").orElse(10) == 10);
}


@("Should work in operator")
@safe unittest
{
    mixin(SimpleConfigs);
    assert("obj.one" in root);
    assert("obj.two" in root);
    assert("obj.tree" !in root);
}


@("Should work getSequence")
@safe unittest
{
    mixin(SimpleConfigs);
    assert (root.getSequence("arr").length == 3);
    assertThrown(root.getSequence("obj.one"));
}


@("Should work merge method")
@safe unittest
{
    mixin(SimpleConfigs);
    auto node = UniTree(["five": UniTree(5)]);
    UniTree root2 = UniTree(["obj": node, "arr": UniTree([UniTree(6)])]);
    UniTree nilRoot = UniTree(null);
    assert ((root ~ nilRoot) == root);
    assert ((nilRoot ~ root) == root);

    auto res = root ~ root2;
    assert(res.get!UniTree("arr").length == 4);
    assert(res.getSequence("arr")[3].get!int == 6);
    assert(res.get!int("obj.five") == 5);
}


@("Should work getOrElse method")
@safe unittest
{
    mixin(SimpleConfigs);
    assert (root.getOrElse("one", 10) == 10);
}

