const { iniInternals } = require("bun:internal-for-testing");
const { parse } = iniInternals;
import { expect, test, describe, it } from "bun:test";

describe("parse ini", () => {
  it("works with unicode in the .ini file", () => {
    let ini /* ini */ = `
hi👋lol = 'lol hi 👋'
`;

    expect(parse(ini)).toEqual({
      "hi👋lol": "lol hi 👋",
    });

    ini = /* ini */ `
[😎.🫒.🤦‍♀️]
lol = 'wtf'
    `;

    expect(parse(ini)).toEqual({
      "😎": {
        "🫒": {
          "🤦‍♀️": {
            lol: "wtf",
          },
        },
      },
    });
  });

  it("matches stupid npm/ini behavior", () => {
    let ini /* ini */ = `
'{ "what": "is this" }' = seriously?
`;

    let result = parse(ini);
    expect(result).toEqual({
      "[Object object]": "seriously?",
    });

    ini = /* ini */ `
'[1, 2, 3]' = cmon man
`;

    result = parse(ini);
    expect(result).toEqual({
      "1,2,3": "cmon man",
    });
  });

  test("basic", () => {
    const ini = /* ini */ `
    hello = 'friends'
    `;

    expect(parse(ini)).toEqual({
      hello: "friends",
    });
  });

  test("basic sections", () => {
    const ini = /* ini */ `
hello = 'friends'

[foo]
bar = 'baz'
    `;

    expect(parse(ini)).toEqual({
      hello: "friends",
      foo: {
        bar: "baz",
      },
    });
  });

  test("key and then section edgecase", () => {
    const ini = /* ini */ `
foo = 'hihihi'

[foo]
isbar = 'lol'
    `;

    expect(parse(ini)).toEqual({
      foo: "hihihi",
    });
  });

  describe("duplicate properties", () => {
    test("decode with duplicate properties", () => {
      const ini = /* ini */ `
zr[] = deedee
zr=123
ar[] = one
ar[] = three
str = 3
brr = 1
brr = 2
brr = 3
brr = 3
`;

      expect(parse(ini)).toEqual({
        zr: ["deedee", "123"],
        ar: ["one", "three"],
        str: "3",
        brr: "3",
      });
    });
  });

  test("bigboi", async () => {
    const foo = await Bun.$`cat ${__dirname}/foo.ini`.text();
    const result = parse(foo);
    console.log(JSON.stringify(result));
    expect(result).toEqual({
      " xa  n          p ": '"\r\nyoyoyo\r\r\n',
      "[disturbing]": "hey you never know",
      "a": {
        "[]": "a square?",
        "av": "a val",
        "b": {
          "c": {
            "e": "1",
            "j": "2",
          },
        },
        "cr": ["four", "eight"],
        "e": '{ o: p, a: { av: a val, b: { c: { e: "this [value]" } } } }',
        "j": '"{ o: "p", a: { av: "a val", b: { c: { e: "this [value]" } } } }"',
      },
      "a with spaces": "b  c",
      "ar": ["one", "three", "this is included"],
      "b": {},
      "br": "warm",
      "eq": "eq=eq",
      "false": false,
      "null": null,
      "o": "p",
      "s": "something",
      "s1": "\"something'",
      "s2": "something else",
      "s3": "",
      "s4": "",
      "s5": "   ",
      "s6": " a ",
      "s7": true,
      "true": true,
      "undefined": "undefined",
      "x.y.z": {
        "a.b.c": {
          "a.b.c": "abc",
          "nocomment": "this; this is not a comment",
          "noHashComment": "this# this is not a comment",
        },
        "x.y.z": "xyz",
      },
      "zr": ["deedee"],
    });
  });
});

const wtf = {
  "o": "p",
  "a with spaces": "b  c",
  " xa  n          p ": '"\r\nyoyoyo\r\r\n',
  "[disturbing]": "hey you never know",
  "s": "something",
  "s1": "\"something'",
  "s2": "something else",
  "s3": true,
  "s4": true,
  "s5": "   ",
  "s6": " a ",
  "s7": true,
  "true": true,
  "false": false,
  "null": null,
  "undefined": "undefined",
  "zr": ["deedee"],
  "ar": [["one"], "three", "this is included"],
  "br": "warm",
  "eq": "eq=eq",
  "a": {
    "av": "a val",
    "e": '{ o: p, a: { av: a val, b: { c: { e: "this [value]" } } } }',
    "j": '"{ o: "p", a: { av: "a val", b: { c: { e: "this [value]" } } } }"',
    "[]": "a square?",
    "cr": [["four"], "eight"],
    "b": { "c": { "e": "1", "j": "2" } },
  },
  "b": {},
  "x.y.z": {
    "x.y.z": "xyz",
    "a.b.c": {
      "a.b.c": "abc",
      "nocomment": "this; this is not a comment",
      "noHashComment": "this# this is not a comment",
    },
  },
};
